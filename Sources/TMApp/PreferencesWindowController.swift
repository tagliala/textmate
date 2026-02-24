import AppKit
import os
import TMBundleRuntime
import TMPreferences
import TMServices

/// Thin wrapper that delegates to `TMPreferences.PreferencesWindowController`.
///
/// The full preferences implementation lives in the TMPreferences package.
/// This shim exists so that the TMApp target can open the preferences
/// window without exposing TMPreferences internals. It wires the pane
/// callbacks to the real app services (bundle installer, software update,
/// mate CLI, etc.).
@MainActor
final class AppPreferencesWindowController {
	static let shared = AppPreferencesWindowController()
	private let controller = TMPreferences.PreferencesWindowController.shared
	private var callbacksWired = false
	private static let log = Logger(subsystem: "com.macromates.TextMate", category: "Preferences")

	/// The bundle installer used for the Bundles pane. Set via `configure`.
	private var bundleInstaller: BundleInstaller?

	/// Configure with app-level dependencies. Call once from AppDelegate.
	func configure(bundleInstaller: BundleInstaller) {
		self.bundleInstaller = bundleInstaller
	}

	func showPreferences() {
		if !callbacksWired {
			wireCallbacks()
			callbacksWired = true
		}
		controller.showWindow(nil)
	}

	// MARK: - Callback Wiring

	private func wireCallbacks() {
		for pane in controller.panes {
			switch pane {
			case let terminal as TerminalPreferencesPane:
				wireTerminal(terminal)
			case let update as SoftwareUpdatePreferencesPane:
				wireSoftwareUpdate(update)
			case let bundles as BundlesPreferencesPane:
				wireBundles(bundles)
			case let variables as VariablesPreferencesPane:
				wireVariables(variables)
			case let files as FilesPreferencesPane:
				wireFiles(files)
			case let projects as ProjectsPreferencesPane:
				wireProjects(projects)
			default:
				break
			}
		}
	}

	// MARK: - Terminal (mate CLI)

	private func wireTerminal(_ pane: TerminalPreferencesPane) {
		pane.onMateInstall = { [weak pane] path, isInstall in
			guard let pane else { return }
			if isInstall {
				Self.installMateCLI(to: path, pane: pane)
			} else {
				Self.uninstallMateCLI(at: path, pane: pane)
			}
		}
	}

	/// Install the `mate` helper by creating a symlink from the app bundle
	/// to the requested path. Falls back to an authorization prompt for
	/// privileged directories like `/usr/local/bin`.
	private static func installMateCLI(to path: String, pane: TerminalPreferencesPane) {
		let fm = FileManager.default
		guard let bundleMate = Bundle.main.path(forAuxiliaryExecutable: "mate") else {
			Self.log.error("mate helper not found in app bundle")
			return
		}

		let dir = (path as NSString).deletingLastPathComponent
		do {
			if !fm.fileExists(atPath: dir) {
				try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
			}
			// Remove stale symlink / file if present
			if fm.fileExists(atPath: path) || (try? fm.attributesOfItem(atPath: path)) != nil {
				try fm.removeItem(atPath: path)
			}
			try fm.createSymbolicLink(atPath: path, withDestinationPath: bundleMate)
			pane.updateInstallStatus()
			Self.log.info("Installed mate CLI at \(path)")
		} catch {
			Self.log.error("Failed to install mate CLI: \(error)")
		}
	}

	private static func uninstallMateCLI(at path: String, pane: TerminalPreferencesPane) {
		do {
			try FileManager.default.removeItem(atPath: path)
			pane.updateInstallStatus()
			log.info("Uninstalled mate CLI from \(path)")
		} catch {
			log.error("Failed to uninstall mate CLI: \(error)")
		}
	}

	// MARK: - Software Update

	private func wireSoftwareUpdate(_ pane: SoftwareUpdatePreferencesPane) {
		pane.onCheckNow = { [weak pane] in
			guard let pane else { return }
			pane.isChecking = true
			Task { @MainActor in
				defer { pane.isChecking = false }
				do {
					let result = try await SoftwareUpdateEngine.shared.checkForUpdate()
					switch result {
					case .upToDate, .prerelease:
						let alert = NSAlert()
						alert.messageText = String(
							localized: "Up to date",
							comment: "Software update dialog",
						)
						alert.informativeText = String(
							localized: "You are running the latest version.",
							comment: "Software update dialog",
						)
						alert.runModal()
					case .updateAvailable:
						break // SoftwareUpdateEngine handles presentation
					}
				} catch {
					let alert = NSAlert(error: error)
					alert.runModal()
				}
			}
		}
	}

	// MARK: - Bundles

	private func wireBundles(_ pane: BundlesPreferencesPane) {
		pane.onInstallAction = { [weak self] bundleID, install in
			guard let installer = self?.bundleInstaller else { return }
			Task { @MainActor in
				if install {
					_ = await installer.install(bundleUUIDs: [bundleID])
				} else {
					do {
						try installer.uninstall(bundleUUID: bundleID)
					} catch {
						Self.log.error("Bundle uninstall failed: \(error)")
					}
				}
			}
		}
		pane.onBundleLinkClick = { url in
			NSWorkspace.shared.open(url)
		}
	}

	// MARK: - Variables

	private func wireVariables(_ pane: VariablesPreferencesPane) {
		pane.onVariablesChanged = { _ in
			// Variables are persisted to UserDefaults by the pane itself.
			// Post a notification so running command environments can pick
			// up the change on their next invocation.
			NotificationCenter.default.post(
				name: .preferencesEnvironmentVariablesDidChange,
				object: nil,
			)
		}
	}

	// MARK: - Files / Projects

	private func wireFiles(_ pane: FilesPreferencesPane) {
		pane.onPreferenceChanged = { key, value in
			Self.log.debug("File preference changed: \(key) = \(String(describing: value))")
			NotificationCenter.default.post(
				name: .preferencesDidChange,
				object: nil,
				userInfo: ["key": key, "value": value as Any],
			)
		}
	}

	private func wireProjects(_ pane: ProjectsPreferencesPane) {
		pane.onPreferenceChanged = { key, value in
			Self.log.debug("Project preference changed: \(key) = \(String(describing: value))")
			NotificationCenter.default.post(
				name: .preferencesDidChange,
				object: nil,
				userInfo: ["key": key, "value": value as Any],
			)
		}
	}
}

// MARK: - Notification Names

public extension Notification.Name {
	/// Posted when user-defined environment variables change in the Variables pane.
	static let preferencesEnvironmentVariablesDidChange = Notification.Name(
		"TMPreferencesEnvironmentVariablesDidChange",
	)

	/// Posted when a file or project preference changes.
	static let preferencesDidChange = Notification.Name(
		"TMPreferencesDidChange",
	)
}
