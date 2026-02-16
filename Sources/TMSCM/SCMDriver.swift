import Foundation

// MARK: - SCM Driver Protocol

/// Protocol for VCS drivers — equivalent to `scm::driver_t`.
///
/// Each driver knows how to detect its VCS type and query file statuses.
public protocol SCMDriver: Sendable {
	/// The VCS name (e.g., "git", "hg", "svn").
	var name: String { get }

	/// The marker used to detect this VCS type.
	///
	/// The driver checks for this marker in parent directories
	/// (e.g., ".git" for Git, ".hg" for Mercurial).
	var detectionMarker: String { get }

	/// Whether this driver may touch the filesystem during status queries.
	///
	/// If true, FSEvents-based change detection via snapshot diffing may be needed.
	var mayTouchFilesystem: Bool { get }

	/// Whether this driver tracks directory status separately.
	var tracksDirectories: Bool { get }

	/// Detect the repository root for the given path.
	///
	/// Walks parent directories looking for `detectionMarker`.
	/// Returns the root directory path if found, or nil.
	func detectRoot(for path: String) -> String?

	/// Query the status of files in the repository rooted at the given path.
	///
	/// - Parameter rootPath: The repository root.
	/// - Returns: A status map of path→status.
	func status(rootPath: String) async throws -> SCMStatusMap

	/// Query SCM variables for the repository at the given path.
	///
	/// - Parameter rootPath: The repository root.
	/// - Returns: SCM variables including branch, name, etc.
	func variables(rootPath: String) async throws -> SCMVariables
}

// MARK: - Default Implementation

public extension SCMDriver {
	var mayTouchFilesystem: Bool {
		false
	}

	var tracksDirectories: Bool {
		false
	}

	/// Default root detection: walk parent directories looking for the marker.
	func detectRoot(for path: String) -> String? {
		var url = URL(fileURLWithPath: path)

		// If the path is a file, start from its parent directory
		var isDir: ObjCBool = false
		if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
			url = url.deletingLastPathComponent()
		}

		while url.path != "/", url.path != "" {
			let markerPath = url.appendingPathComponent(detectionMarker).path
			if FileManager.default.fileExists(atPath: markerPath) {
				return url.path
			}
			url = url.deletingLastPathComponent()
		}

		// Check root
		let rootMarker = URL(fileURLWithPath: "/").appendingPathComponent(detectionMarker).path
		if FileManager.default.fileExists(atPath: rootMarker) {
			return "/"
		}

		return nil
	}
}

// MARK: - Driver Registry

/// Registry of available SCM drivers — checks each driver in order to find
/// the appropriate one for a given path.
public struct SCMDriverRegistry: Sendable {
	/// The registered drivers, checked in order.
	public let drivers: [any SCMDriver]

	/// Default registry with all built-in drivers.
	public static let `default` = SCMDriverRegistry(drivers: [
		GitDriver(),
		HgDriver(),
		SvnDriver(),
	])

	public init(drivers: [any SCMDriver]) {
		self.drivers = drivers
	}

	/// Find the appropriate driver and repository root for a given path.
	///
	/// Checks each driver in order, returning the first match.
	public func detect(for path: String) -> (driver: any SCMDriver, rootPath: String)? {
		for driver in drivers {
			if let root = driver.detectRoot(for: path) {
				return (driver, root)
			}
		}
		return nil
	}
}

// MARK: - Shell Helpers

/// Run a shell command and return its stdout.
///
/// Used internally by SCM drivers to call VCS executables.
func runCommand(
	_ executable: String,
	arguments: [String],
	workingDirectory: String,
	environment: [String: String]? = nil,
) async throws -> String {
	try await withCheckedThrowingContinuation { continuation in
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

		if let environment {
			var env = ProcessInfo.processInfo.environment
			env.merge(environment) { _, new in new }
			process.environment = env
		}

		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice

		do {
			try process.run()
		} catch {
			continuation.resume(throwing: error)
			return
		}

		process.waitUntilExit()

		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		let output = String(data: data, encoding: .utf8) ?? ""
		continuation.resume(returning: output)
	}
}

/// Find an executable in PATH.
func findExecutable(_ name: String) -> String? {
	let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/usr/local/bin")
		.split(separator: ":")
		.map(String.init)

	for dir in paths {
		let fullPath = (dir as NSString).appendingPathComponent(name)
		if FileManager.default.isExecutableFile(atPath: fullPath) {
			return fullPath
		}
	}
	return nil
}
