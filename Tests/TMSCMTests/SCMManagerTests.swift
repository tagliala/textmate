import Foundation
import Testing
@testable import TMSCM

// MARK: - SCMManager Tests

@Suite("SCMManager")
@MainActor
struct SCMManagerTests {
	@Test("Default init uses default registry")
	func defaultInit() {
		let manager = SCMManager()
		#expect(manager.registry.drivers.count == 3)
		#expect(!manager.isAutoRefreshEnabled)
		#expect(manager.activeRepositories.isEmpty)
	}

	@Test("Custom registry")
	func customRegistry() {
		let mockDriver = MockDriver(name: "mock", detectionMarker: ".mock")
		let registry = SCMDriverRegistry(drivers: [mockDriver])
		let manager = SCMManager(registry: registry)
		#expect(manager.registry.drivers.count == 1)
	}

	@Test("Repository detection with real git repo")
	func repositoryDetection() throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_scm_mgr_\(UUID().uuidString)")
		let gitDir = tmpDir.appendingPathComponent(".git")

		try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let manager = SCMManager()
		let repo = manager.repository(for: tmpDir.path)

		#expect(repo != nil)
		#expect(repo?.rootPath == tmpDir.path)
		#expect(repo?.driver.name == "git")
	}

	@Test("Repository caching returns same instance")
	func repositoryCaching() throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_scm_cache_\(UUID().uuidString)")
		let gitDir = tmpDir.appendingPathComponent(".git")

		try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let manager = SCMManager()
		let repo1 = manager.repository(for: tmpDir.path)
		let repo2 = manager.repository(for: tmpDir.path)

		#expect(repo1 === repo2)
	}

	@Test("No repository for non-SCM directory")
	func noRepository() {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_scm_norepo_\(UUID().uuidString)")
		try? FileManager.default.createDirectory(atPath: tmpDir.path, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let mockDriver = MockDriver(name: "mock", detectionMarker: ".nonexistent_special_marker")
		let registry = SCMDriverRegistry(drivers: [mockDriver])
		let manager = SCMManager(registry: registry)

		let repo = manager.repository(for: tmpDir.path)
		#expect(repo == nil)
	}

	@Test("Status convenience method")
	func statusConvenience() {
		let mockDriver = MockDriver(name: "mock", detectionMarker: ".nonexistent_marker")
		let registry = SCMDriverRegistry(drivers: [mockDriver])
		let manager = SCMManager(registry: registry)

		// No repo → unknown
		let status = manager.status(for: "/tmp/random/file.txt")
		#expect(status == .unknown)
	}

	@Test("Remove repository")
	func removeRepository() throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_scm_remove_\(UUID().uuidString)")
		let gitDir = tmpDir.appendingPathComponent(".git")

		try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let manager = SCMManager()
		_ = manager.repository(for: tmpDir.path)
		#expect(manager.activeRepositories.count == 1)

		manager.removeRepository(for: tmpDir.path)
		#expect(manager.activeRepositories.isEmpty)
	}

	@Test("Auto refresh toggle")
	func autoRefreshToggle() {
		let manager = SCMManager()
		#expect(!manager.isAutoRefreshEnabled)

		manager.startAutoRefresh()
		#expect(manager.isAutoRefreshEnabled)

		manager.stopAutoRefresh()
		#expect(!manager.isAutoRefreshEnabled)
	}

	@Test("Refresh interval default")
	func refreshInterval() {
		let manager = SCMManager()
		#expect(manager.refreshInterval == 3.0)
	}
}
