@preconcurrency import Foundation
import os.log

// MARK: - Software Update Engine

/// Automatic software update checking, downloading, and installation engine.
///
/// Port of `Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm`.
///
/// Provides:
/// - Background activity scheduler for periodic update checks
/// - Channel-based update URL management (release/beta/nightly)
/// - Version comparison against remote version info (JSON or plist)
/// - Download and install-and-relaunch flow
/// - "Suspend until" mechanism for deferring update checks
///
/// This class manages the *engine* logic. UI presentation (alert dialogs,
/// progress views) belongs in higher-level SwiftUI or AppKit code that
/// observes this engine's published state.
@MainActor
public final class SoftwareUpdateEngine: Observable {
	// MARK: - UserDefaults Keys

	/// UserDefaults key constants matching the C++ originals.
	public enum DefaultsKey {
		public static let lastCheck = "SoftwareUpdateLastPoll"
		public static let suspendUntil = "SoftwareUpdateSuspendUntil"
		public static let disablePolling = "SoftwareUpdateDisablePolling"
		public static let askBeforeUpdating = "SoftwareUpdateAskBeforeUpdating"
		public static let channel = "SoftwareUpdateChannel"
		public static let disableReadOnlyWarning = "SoftwareUpdateDisableReadOnlyFileSystemWarningKey"
	}

	// MARK: - Channels

	/// Well-known update channel names.
	public enum Channel {
		public static let release = "release"
		public static let prerelease = "beta"
		public static let canary = "nightly"
	}

	// MARK: - Update Check Result

	/// The result of an update version check.
	public enum VersionCheckResult: Sendable {
		/// A newer version is available.
		case updateAvailable(url: URL, version: String)
		/// The user is running the latest version.
		case upToDate(version: String)
		/// The user is running a prerelease (newer than remote).
		case prerelease(localVersion: String, remoteVersion: String)
	}

	// MARK: - Errors

	/// Errors related to the update process.
	public enum UpdateError: Error, Sendable, CustomStringConvertible {
		case noChannelConfigured
		case unknownChannel(String)
		case incompleteServerResponse
		case malformedServerResponse
		case missingContentType
		case readOnlyFileSystem
		case installationFailed(String)
		case integrityCheckFailed

		public var description: String {
			switch self {
			case .noChannelConfigured: "No channel configured."
			case let .unknownChannel(ch): "No channel named '\(ch)'."
			case .incompleteServerResponse: "Incomplete server response."
			case .malformedServerResponse: "Malformed server response."
			case .missingContentType: "Missing Content-Type in server response."
			case .readOnlyFileSystem: "Application is on a read-only file system."
			case let .installationFailed(msg): "Failed to install update: \(msg)"
			case .integrityCheckFailed: "The download is incomplete."
			}
		}
	}

	// MARK: - State

	/// Whether an update check is currently in progress.
	public private(set) var isChecking = false

	/// Error string from the last background check, if any.
	public private(set) var errorString: String?

	/// Whether automatic update checking is enabled.
	public var isAutomaticCheckEnabled: Bool {
		didSet {
			guard isAutomaticCheckEnabled != oldValue else { return }
			configureScheduler()
		}
	}

	/// Map of channel name → check URL.
	public var channels: [String: URL] = [:]

	/// Public keys for signature verification (signee → PEM key).
	public var publicKeys: [String: String] = [:]

	/// The interval between automatic checks (default: 1 hour).
	public var checkInterval: TimeInterval = 60 * 60

	/// The download manager to use.
	public var downloadManager: DownloadManager = .shared

	private var scheduler: NSBackgroundActivityScheduler?
	private let logger = Logger(subsystem: "com.macromates.TextMate", category: "SoftwareUpdate")
	private nonisolated(unsafe) var defaultsObserver: NSObjectProtocol?

	// MARK: - Singleton

	/// Shared instance.
	public static let shared = SoftwareUpdateEngine()

	// MARK: - Initialization

	public init() {
		isAutomaticCheckEnabled = !UserDefaults.standard.bool(forKey: DefaultsKey.disablePolling)

		// Register defaults
		UserDefaults.standard.register(defaults: [
			DefaultsKey.channel: Channel.release,
		])

		// Observe UserDefaults changes
		defaultsObserver = NotificationCenter.default.addObserver(
			forName: UserDefaults.didChangeNotification,
			object: UserDefaults.standard,
			queue: .main,
		) { [weak self] _ in
			guard let self else { return }
			MainActor.assumeIsolated {
				self.isAutomaticCheckEnabled = !UserDefaults.standard.bool(forKey: DefaultsKey.disablePolling)
			}
		}

		configureScheduler()
	}

	deinit {
		let observer = defaultsObserver
		MainActor.assumeIsolated {
			if let observer {
				NotificationCenter.default.removeObserver(observer)
			}
			scheduler?.invalidate()
		}
	}

	// MARK: - Scheduler

	private func configureScheduler() {
		scheduler?.invalidate()
		scheduler = nil

		guard isAutomaticCheckEnabled else { return }

		let bundleID = Bundle.main.bundleIdentifier ?? "com.macromates.TextMate"
		let sched = NSBackgroundActivityScheduler(identifier: "\(bundleID).SoftwareUpdate")
		sched.interval = checkInterval
		sched.repeats = true

		sched.schedule { [weak self] completionHandler in
			guard let self else {
				completionHandler(.finished)
				return
			}

			Task { @MainActor in
				// Check if suspended
				if let suspendUntil = UserDefaults.standard.object(forKey: DefaultsKey.suspendUntil) as? Date {
					if suspendUntil.timeIntervalSinceNow > 0 {
						self.logger.info("Skip version check: Suspended until \(suspendUntil)")
						completionHandler(.finished)
						return
					}
					UserDefaults.standard.removeObject(forKey: DefaultsKey.suspendUntil)
				}

				do {
					let result = try await self.checkForUpdate(testBuild: false)
					self.errorString = nil

					switch result {
					case .updateAvailable:
						// The engine reports availability; UI layer handles presentation.
						break
					case .upToDate, .prerelease:
						// Nothing to do on background check
						break
					}
				} catch {
					self.errorString = "Error: \(error.localizedDescription)"
					self.logger.error("Failed to check for update: \(error.localizedDescription)")
				}

				completionHandler(.finished)
			}
		}

		scheduler = sched
	}

	// MARK: - Version Check

	/// Check for available updates.
	///
	/// - Parameter testBuild: If `true`, check the canary/nightly channel.
	/// - Returns: The version check result.
	/// - Throws: `UpdateError` on failure.
	public func checkForUpdate(testBuild: Bool = false) async throws -> VersionCheckResult {
		let channelName = testBuild ? Channel.canary :
			(UserDefaults.standard.string(forKey: DefaultsKey.channel) ?? Channel.release)

		guard let url = channels[channelName] else {
			if channels.isEmpty {
				throw UpdateError.noChannelConfigured
			}
			throw UpdateError.unknownChannel(channelName)
		}

		isChecking = true
		defer {
			isChecking = false
			UserDefaults.standard.set(Date(), forKey: DefaultsKey.lastCheck)
		}

		var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)
		request.setValue(downloadManager.userAgentString, forHTTPHeaderField: "User-Agent")

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse,
		      let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
		else {
			throw UpdateError.missingContentType
		}

		// Parse response — supports both JSON and plist
		let plist: [String: Any]? = if contentType.contains("json") {
			try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		} else {
			try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
		}

		guard let dict = plist else {
			throw UpdateError.malformedServerResponse
		}

		guard let urlString = dict["url"] as? String,
		      let remoteURL = URL(string: urlString),
		      let remoteVersion = dict["version"] as? String
		else {
			throw UpdateError.incompleteServerResponse
		}

		let localVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
		let ordering = VersionComparison.compare(localVersion, remoteVersion)

		switch ordering {
		case .orderedAscending:
			return .updateAvailable(url: remoteURL, version: remoteVersion)
		case .orderedSame:
			return .upToDate(version: remoteVersion)
		case .orderedDescending:
			return .prerelease(localVersion: localVersion, remoteVersion: remoteVersion)
		}
	}

	// MARK: - Installation

	/// Check whether the application bundle is on a read-only file system.
	public func isApplicationOnReadOnlyFileSystem() -> Bool {
		let bundlePath = Bundle.main.bundlePath
		var sfsb = statfs()
		guard statfs(bundlePath, &sfsb) == 0 else { return false }
		return (sfsb.f_flags & UInt32(MNT_RDONLY)) != 0
	}

	/// Check whether an application at the given URL appears installable.
	///
	/// Verifies that the expected main executable exists and is executable.
	public func isInstallableApplication(at url: URL) -> Bool {
		let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TextMate"
		let executableURL = url.appendingPathComponent("Contents/MacOS/\(appName)")

		var isExecutable: AnyObject?
		do {
			try (executableURL as NSURL).getResourceValue(&isExecutable, forKey: .isExecutableKey)
			return (isExecutable as? Bool) == true
		} catch {
			logger.error("Failed checking if \(url.path) has an executable: \(error.localizedDescription)")
			return false
		}
	}

	/// Install an update from a downloaded archive directory and relaunch.
	///
	/// This replaces the running application bundle with the one at `sourceURL`,
	/// then launches a shell script that waits for this process to exit and
	/// reopens the application.
	///
	/// - Parameter sourceURL: The directory containing the new application bundle.
	/// - Throws: `UpdateError` on failure.
	public func installAndRelaunch(from sourceURL: URL) throws {
		guard isInstallableApplication(at: sourceURL) else {
			throw UpdateError.integrityCheckFailed
		}

		if isApplicationOnReadOnlyFileSystem() {
			throw UpdateError.readOnlyFileSystem
		}

		// Replace the current application bundle
		let bundleURL = Bundle.main.bundleURL
		do {
			_ = try FileManager.default.replaceItemAt(
				bundleURL,
				withItemAt: sourceURL,
				backupItemName: nil,
				options: .usingNewMetadataOnly,
			)
		} catch {
			throw UpdateError.installationFailed(error.localizedDescription)
		}

		// Launch a shell script to wait for us to exit and then reopen
		let pid = getpid()
		let script = """
		{ kill \(pid); while ps -xp \(
			pid
		); do if (( ++n == 300 )); then exit; fi; sleep .2; done; open "$0" --args $1; } &>/dev/null &
		"""

		let task = Process()
		task.executableURL = URL(fileURLWithPath: "/bin/sh")
		task.arguments = ["-c", script, Bundle.main.bundlePath, "-showReleaseNotes YES"]
		task.standardInput = FileHandle.nullDevice
		task.standardOutput = FileHandle.nullDevice
		task.standardError = FileHandle.nullDevice

		do {
			try task.run()
		} catch {
			logger.error("Failed to launch relaunch script: \(error.localizedDescription)")
		}
	}

	/// Suspend automatic update checks for the given duration.
	///
	/// Called when the user clicks "Later" on a background update notification.
	public func suspendChecks(for duration: TimeInterval = 24 * 60 * 60) {
		UserDefaults.standard.set(
			Date().addingTimeInterval(duration),
			forKey: DefaultsKey.suspendUntil,
		)
	}

	/// Download an update archive and extract it.
	///
	/// - Parameter url: The download URL for the archive.
	/// - Returns: The URL of the extracted application directory.
	@discardableResult
	public func downloadUpdate(at url: URL) -> (progress: Progress, task: Task<URL, Error>) {
		let progress = Progress.discreteProgress(totalUnitCount: -1)
		progress.kind = .file
		progress.fileOperationKind = .downloading

		let task = Task<URL, Error> {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
				let downloadProgress = self.downloadManager.downloadArchive(
					at: url,
					forReplacing: Bundle.main.bundleURL,
					publicKeys: self.publicKeys,
				) { extractedURL, error in
					if let extractedURL {
						continuation.resume(returning: extractedURL)
					} else {
						continuation
							.resume(throwing: error ?? DownloadManager.DownloadError.extractionFailed("Unknown error"))
					}
				}

				// Bridge download progress to our progress
				progress.totalUnitCount = downloadProgress.totalUnitCount
				progress.addChild(downloadProgress, withPendingUnitCount: progress.totalUnitCount)
			}
		}

		return (progress, task)
	}
}
