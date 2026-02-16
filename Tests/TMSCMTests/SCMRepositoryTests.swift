import Foundation
import Testing
@testable import TMSCM

// MARK: - SCMRepository Tests

@Suite("SCMRepository")
@MainActor
struct SCMRepositoryTests {
	@Test("Creation with driver")
	func creation() {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let repo = SCMRepository(rootPath: "/project", driver: driver)
		#expect(repo.rootPath == "/project")
		#expect(repo.driver.name == "mock")
		#expect(repo.statusMap.isEmpty)
		#expect(repo.variables == nil)
		#expect(!repo.isRefreshing)
	}

	@Test("Refresh updates status map")
	func refresh() async {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let repo = SCMRepository(rootPath: "/project", driver: driver)

		await repo.refresh()

		#expect(!repo.statusMap.isEmpty)
		#expect(repo.statusMap.status(for: "/project/file1.txt") == .modified)
		#expect(repo.statusMap.status(for: "/project/file2.txt") == .added)
	}

	@Test("Refresh updates variables")
	func refreshVariables() async {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let repo = SCMRepository(rootPath: "/project", driver: driver)

		await repo.refresh()

		#expect(repo.variables != nil)
		#expect(repo.variables?.scmName == "mock")
		#expect(repo.variables?.branch == "test-branch")
	}

	@Test("Status query for specific file")
	func statusForFile() async {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let repo = SCMRepository(rootPath: "/project", driver: driver)

		await repo.refresh()

		#expect(repo.status(for: "/project/file1.txt") == .modified)
		#expect(repo.status(for: "/project/unknown.txt") == .unknown)
	}

	@Test("Modified files list")
	func modifiedFiles() async {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let repo = SCMRepository(rootPath: "/project", driver: driver)

		await repo.refresh()

		let modified = repo.modifiedFiles
		#expect(modified.count == 2)
	}

	@Test("Uncommitted files include unversioned")
	func uncommittedFiles() async {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let repo = SCMRepository(rootPath: "/project", driver: driver)

		await repo.refresh()

		let uncommitted = repo.uncommittedFiles
		#expect(uncommitted.count == 2) // modified + added
	}

	@Test("Observer is called on status change")
	func observer() async {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let repo = SCMRepository(rootPath: "/project", driver: driver)

		var observerCalled = false
		_ = repo.addObserver { _ in
			observerCalled = true
		}

		await repo.refresh()
		#expect(observerCalled)
	}

	@Test("Unique identity")
	func identity() {
		let driver = MockDriver(name: "mock", detectionMarker: ".mock")
		let repo1 = SCMRepository(rootPath: "/project", driver: driver)
		let repo2 = SCMRepository(rootPath: "/project", driver: driver)
		#expect(repo1.id != repo2.id)
	}
}

// MARK: - SCMError Tests

@Suite("SCMError")
struct SCMErrorTests {
	@Test("Error descriptions")
	func errorDescriptions() {
		#expect(SCMError.executableNotFound("git").errorDescription?.contains("git") == true)
		#expect(SCMError.commandFailed("status", 1).errorDescription?.contains("status") == true)
		#expect(SCMError.parseError("bad output").errorDescription?.contains("parse") == true)
		#expect(SCMError.noRepository("/path").errorDescription?.contains("repository") == true)
	}
}
