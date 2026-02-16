import Foundation

// MARK: - SCM Repository

/// Represents a tracked source-control repository — equivalent to `SCMRepository` / `scm::info_t`.
///
/// Manages the connection between a file path, its VCS driver, and the
/// current status of all files in the repository. Supports async status
/// updates and observer callbacks.
@MainActor
public final class SCMRepository: Observable, Identifiable {
	/// Unique identifier for this repository.
	public let id = UUID()

	/// The repository root path.
	public let rootPath: String

	/// The driver managing this repository.
	public let driver: any SCMDriver

	/// Current file status map.
	public private(set) var statusMap: SCMStatusMap = .init() {
		didSet { notifyObservers() }
	}

	/// Current SCM variables (branch, commit, etc.).
	public private(set) var variables: SCMVariables?

	/// Whether the repository is currently refreshing.
	public private(set) var isRefreshing: Bool = false

	/// Observers for status changes.
	private var observers: [(SCMStatusMap) -> Void] = []

	/// File-level observers: path → callbacks.
	private var fileObservers: [String: [(SCMStatus) -> Void]] = [:]

	/// Previous file statuses for change detection.
	private var previousFileStatuses: [String: SCMStatus] = [:]

	public init(rootPath: String, driver: any SCMDriver) {
		self.rootPath = rootPath
		self.driver = driver
	}

	// MARK: - Refresh

	/// Refresh the status of all files in the repository.
	public func refresh() async {
		guard !isRefreshing else { return }
		isRefreshing = true
		defer { isRefreshing = false }

		do {
			let newStatus = try await driver.status(rootPath: rootPath)
			let newVars = try await driver.variables(rootPath: rootPath)

			statusMap = newStatus
			variables = newVars

			// Notify file-level observers for changed files
			for (path, callbacks) in fileObservers {
				let currentStatus = newStatus.status(for: path)
				let previousStatus = previousFileStatuses[path] ?? .unknown
				if currentStatus != previousStatus {
					for callback in callbacks {
						callback(currentStatus)
					}
				}
			}

			previousFileStatuses = newStatus.entries
		} catch {
			// Silently handle errors — status will remain stale
		}
	}

	// MARK: - Status Queries

	/// Get the status for a specific file path.
	public func status(for path: String) -> SCMStatus {
		statusMap.status(for: path)
	}

	/// Get the status for a directory (computed from children).
	public func directoryStatus(for path: String) -> SCMStatus {
		statusMap.directoryStatus(for: path)
	}

	/// All modified file paths.
	public var modifiedFiles: [String] {
		statusMap.modifiedPaths
	}

	/// All uncommitted file paths (modified + unversioned).
	public var uncommittedFiles: [String] {
		statusMap.interestingPaths
	}

	// MARK: - Observers

	/// Add an observer that is called when the status map changes.
	///
	/// - Returns: An observation token. Call `removeObserver` to unregister.
	public func addObserver(_ callback: @escaping (SCMStatusMap) -> Void) -> UUID {
		let token = UUID()
		observers.append(callback)
		return token
	}

	/// Add a file-level observer that fires only when the status of a specific file changes.
	public func addFileObserver(path: String, callback: @escaping (SCMStatus) -> Void) {
		fileObservers[path, default: []].append(callback)
	}

	/// Notify all repository-level observers.
	private func notifyObservers() {
		for observer in observers {
			observer(statusMap)
		}
	}
}

// MARK: - SCM Repository Error

/// Errors that can occur during SCM operations.
public enum SCMError: Error, Sendable, LocalizedError {
	case executableNotFound(String)
	case commandFailed(String, Int32)
	case parseError(String)
	case noRepository(String)

	public var errorDescription: String? {
		switch self {
		case let .executableNotFound(name):
			"SCM executable '\(name)' not found"
		case let .commandFailed(cmd, code):
			"SCM command '\(cmd)' failed with exit code \(code)"
		case let .parseError(detail):
			"Failed to parse SCM output: \(detail)"
		case let .noRepository(path):
			"No repository found at '\(path)'"
		}
	}
}
