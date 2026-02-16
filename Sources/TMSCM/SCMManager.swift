import Foundation

// MARK: - SCM Manager

/// Central manager for source-control repositories — equivalent to `SCMManager`.
///
/// Caches repository instances per root path, auto-refreshes on filesystem
/// changes, and provides convenient APIs for UI integration.
@MainActor
public final class SCMManager: Observable {
	/// Shared singleton instance.
	public static let shared = SCMManager()

	/// The driver registry used to detect VCS types.
	public let registry: SCMDriverRegistry

	/// Active repository cache: rootPath → SCMRepository.
	private var repositories: [String: SCMRepository] = [:]

	/// Refresh interval in seconds (default 3.0, matching C++ throttle).
	public var refreshInterval: TimeInterval = 3.0

	/// Auto-refresh timer task.
	private var refreshTask: Task<Void, Never>?

	/// Whether auto-refresh is currently running.
	public private(set) var isAutoRefreshEnabled: Bool = false

	/// Global observers for any repository change.
	private var globalObservers: [(SCMRepository) -> Void] = []

	public init(registry: SCMDriverRegistry = .default) {
		self.registry = registry
	}

	// MARK: - Repository Management

	/// Get or create a repository for the given file or directory path.
	///
	/// Returns nil if no VCS is detected at or above the given path.
	public func repository(for path: String) -> SCMRepository? {
		// Check if we already have a repo for this path
		for (root, repo) in repositories {
			if path.hasPrefix(root) {
				return repo
			}
		}

		// Try to detect VCS
		guard let (driver, rootPath) = registry.detect(for: path) else {
			return nil
		}

		// Check cache with detected root
		if let existing = repositories[rootPath] {
			return existing
		}

		// Create new repository
		let repo = SCMRepository(rootPath: rootPath, driver: driver)
		repositories[rootPath] = repo

		// Trigger initial refresh
		Task {
			await repo.refresh()
		}

		return repo
	}

	/// Get the SCM status for a specific file path.
	///
	/// Convenience method that finds the appropriate repository and returns the status.
	public func status(for path: String) -> SCMStatus {
		guard let repo = repository(for: path) else {
			return .unknown
		}
		return repo.status(for: path)
	}

	/// Get SCM variables for a specific file path.
	public func variables(for path: String) -> SCMVariables? {
		repository(for: path)?.variables
	}

	/// Get the branch name for a specific file path.
	public func branch(for path: String) -> String? {
		variables(for: path)?.branch
	}

	/// Remove a repository from the cache.
	public func removeRepository(for rootPath: String) {
		repositories.removeValue(forKey: rootPath)
	}

	/// All currently tracked repositories.
	public var activeRepositories: [SCMRepository] {
		Array(repositories.values)
	}

	// MARK: - Auto Refresh

	/// Start auto-refreshing all repositories at the configured interval.
	public func startAutoRefresh() {
		guard !isAutoRefreshEnabled else { return }
		isAutoRefreshEnabled = true

		refreshTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(self?.refreshInterval ?? 3.0))
				guard !Task.isCancelled else { break }
				await self?.refreshAll()
			}
		}
	}

	/// Stop auto-refreshing.
	public func stopAutoRefresh() {
		isAutoRefreshEnabled = false
		refreshTask?.cancel()
		refreshTask = nil
	}

	/// Refresh all active repositories.
	public func refreshAll() async {
		await withTaskGroup(of: Void.self) { group in
			for repo in repositories.values {
				group.addTask {
					await repo.refresh()
				}
			}
		}
	}

	/// Refresh the repository containing the given path.
	public func refresh(for path: String) async {
		guard let repo = repository(for: path) else { return }
		await repo.refresh()
	}

	// MARK: - Observers

	/// Add a global observer called when any repository updates.
	public func addGlobalObserver(_ callback: @escaping (SCMRepository) -> Void) {
		globalObservers.append(callback)
	}
}
