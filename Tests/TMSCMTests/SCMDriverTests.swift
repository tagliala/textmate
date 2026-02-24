import Foundation
import Testing
@testable import TMSCM

// MARK: - Mock Driver

struct MockDriver: SCMDriver, Sendable {
	let name: String
	let detectionMarker: String
	var mayTouchFilesystem: Bool = false

	func status(rootPath: String) async throws -> SCMStatusMap {
		SCMStatusMap([
			rootPath + "/file1.txt": .modified,
			rootPath + "/file2.txt": .added,
		])
	}

	func variables(rootPath: String) async throws -> SCMVariables {
		SCMVariables(scmName: name, rootPath: rootPath, branch: "test-branch")
	}
}

// MARK: - Driver Protocol Tests

@Suite("SCMDriver")
struct SCMDriverTests {
	@Test("Default root detection finds marker")
	func detectRootFindsMarker() throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_scm_\(UUID().uuidString)")
		let repoDir = tmpDir.appendingPathComponent("project")
		let markerDir = repoDir.appendingPathComponent(".mockscm")
		let subDir = repoDir.appendingPathComponent("src/deep")

		try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)

		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let driver = MockDriver(name: "mock", detectionMarker: ".mockscm")
		let root = driver.detectRoot(for: subDir.path)
		#expect(root == repoDir.path)
	}

	@Test("Root detection returns nil when no marker found")
	func detectRootReturnsNil() {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_scm_nomarker_\(UUID().uuidString)")
		try? FileManager.default.createDirectory(atPath: tmpDir.path, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let driver = MockDriver(name: "mock", detectionMarker: ".nonexistent_vcs_marker")
		let root = driver.detectRoot(for: tmpDir.path)
		#expect(root == nil)
	}

	@Test("Driver status returns map")
	func driverStatus() async throws {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let status = try await driver.status(rootPath: "/project")
		#expect(status.count == 2)
		#expect(status.status(for: "/project/file1.txt") == .modified)
	}

	@Test("Driver variables returns info")
	func driverVariables() async throws {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let vars = try await driver.variables(rootPath: "/project")
		#expect(vars.scmName == "mock")
		#expect(vars.branch == "test-branch")
	}
}

// MARK: - Driver Registry Tests

@Suite("SCMDriverRegistry")
struct SCMDriverRegistryTests {
	@Test("Default registry has built-in drivers")
	func defaultRegistry() {
		let registry = SCMDriverRegistry.default
		#expect(registry.drivers.count == 3)
		#expect(registry.drivers[0].name == "git")
		#expect(registry.drivers[1].name == "hg")
		#expect(registry.drivers[2].name == "svn")
	}

	@Test("Detect finds correct driver")
	func detectFindsDriver() throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_registry_\(UUID().uuidString)")
		let repoDir = tmpDir.appendingPathComponent("repo")
		let gitDir = repoDir.appendingPathComponent(".git")

		try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let registry = SCMDriverRegistry.default
		let result = registry.detect(for: repoDir.path)

		#expect(result != nil)
		#expect(result?.driver.name == "git")
		#expect(result?.rootPath == repoDir.path)
	}

	@Test("Detect returns nil for non-repo")
	func detectReturnsNil() {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_registry_norep_\(UUID().uuidString)")
		try? FileManager.default.createDirectory(atPath: tmpDir.path, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let driver = MockDriver(name: "mock", detectionMarker: ".nonexistent_scm_marker")
		let registry = SCMDriverRegistry(drivers: [driver])
		let result = registry.detect(for: tmpDir.path)
		#expect(result == nil)
	}

	@Test("Custom registry with mock driver")
	func customRegistry() throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_custom_\(UUID().uuidString)")
		let repoDir = tmpDir.appendingPathComponent("project")
		let markerDir = repoDir.appendingPathComponent(".mockscm")

		try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let mockDriver = MockDriver(name: "mock", detectionMarker: ".mockscm")
		let registry = SCMDriverRegistry(drivers: [mockDriver])
		let result = registry.detect(for: repoDir.path)

		#expect(result?.driver.name == "mock")
	}
}

// MARK: - Git Driver Tests

@Suite("GitDriver")
struct GitDriverTests {
	@Test("Git driver has correct properties")
	func properties() {
		let driver = GitDriver()
		#expect(driver.name == "git")
		#expect(driver.detectionMarker == ".git")
		#expect(!driver.mayTouchFilesystem)
		#expect(!driver.tracksDirectories)
	}

	@Test("Git driver detects .git directory")
	func detectsGit() throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_git_detect_\(UUID().uuidString)")
		let gitDir = tmpDir.appendingPathComponent(".git")

		try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let driver = GitDriver()
		let root = driver.detectRoot(for: tmpDir.path)
		#expect(root == tmpDir.path)
	}
}

// MARK: - Hg Driver Tests

@Suite("HgDriver")
struct HgDriverTests {
	@Test("Hg driver has correct properties")
	func properties() {
		let driver = HgDriver()
		#expect(driver.name == "hg")
		#expect(driver.detectionMarker == ".hg")
		#expect(driver.mayTouchFilesystem)
	}
}

// MARK: - Svn Driver Tests

@Suite("SvnDriver")
struct SvnDriverTests {
	@Test("Svn driver has correct properties")
	func properties() {
		let driver = SvnDriver()
		#expect(driver.name == "svn")
		#expect(driver.detectionMarker == ".svn")
		#expect(driver.tracksDirectories)
	}
}

// MARK: - Shell Helper Tests

@Suite("Shell Helpers")
struct ShellHelperTests {
	@Test("findExecutable finds common binaries")
	func findsCommonBinaries() {
		#expect(findExecutable("ls") != nil)
		#expect(findExecutable("echo") != nil)
	}

	@Test("findExecutable returns nil for nonexistent")
	func returnsNilForNonexistent() {
		#expect(findExecutable("__nonexistent_binary_xyz__") == nil)
	}

	@Test("runCommand returns output")
	func runCommandOutput() async throws {
		let output = try await runCommand(
			"/bin/echo",
			arguments: ["hello", "world"],
			workingDirectory: "/",
		)
		#expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
	}
}
