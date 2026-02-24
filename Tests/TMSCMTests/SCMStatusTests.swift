import Foundation
import Testing
@testable import TMSCM

// MARK: - SCMStatus Tests

@Suite("SCMStatus")
struct SCMStatusTests {
	@Test("All cases have distinct raw values")
	func distinctRawValues() {
		let values = Set(SCMStatus.allCases.map(\.rawValue))
		#expect(values.count == SCMStatus.allCases.count)
	}

	@Test("Short names")
	func shortNames() {
		#expect(SCMStatus.modified.shortName == "M")
		#expect(SCMStatus.added.shortName == "A")
		#expect(SCMStatus.deleted.shortName == "D")
		#expect(SCMStatus.conflicted.shortName == "C")
		#expect(SCMStatus.unversioned.shortName == "?")
		#expect(SCMStatus.ignored.shortName == "!")
	}

	@Test("Display names")
	func displayNames() {
		#expect(SCMStatus.modified.displayName == "Modified")
		#expect(SCMStatus.none.displayName == "Clean")
		#expect(SCMStatus.conflicted.displayName == "Conflicted")
	}

	@Test("isModified for changed files")
	func isModified() {
		#expect(SCMStatus.modified.isModified)
		#expect(SCMStatus.added.isModified)
		#expect(SCMStatus.deleted.isModified)
		#expect(SCMStatus.conflicted.isModified)
		#expect(!SCMStatus.none.isModified)
		#expect(!SCMStatus.unversioned.isModified)
		#expect(!SCMStatus.ignored.isModified)
		#expect(!SCMStatus.unknown.isModified)
	}

	@Test("isInteresting filters boring statuses")
	func isInteresting() {
		#expect(SCMStatus.modified.isInteresting)
		#expect(SCMStatus.added.isInteresting)
		#expect(SCMStatus.unversioned.isInteresting)
		#expect(SCMStatus.mixed.isInteresting)
		#expect(!SCMStatus.none.isInteresting)
		#expect(!SCMStatus.unknown.isInteresting)
		#expect(!SCMStatus.ignored.isInteresting)
	}

	@Test("Codable round-trip")
	func codable() throws {
		let status = SCMStatus.modified
		let data = try JSONEncoder().encode(status)
		let decoded = try JSONDecoder().decode(SCMStatus.self, from: data)
		#expect(decoded == status)
	}
}

// MARK: - SCMStatusMap Tests

@Suite("SCMStatusMap")
struct SCMStatusMapTests {
	@Test("Empty map")
	func empty() {
		let map = SCMStatusMap()
		#expect(map.isEmpty)
		#expect(map.count == 0)
		#expect(map.status(for: "/any/path") == .unknown)
	}

	@Test("Status lookup")
	func statusLookup() {
		let map = SCMStatusMap([
			"/project/file1.swift": .modified,
			"/project/file2.swift": .added,
			"/project/file3.swift": .none,
		])
		#expect(map.status(for: "/project/file1.swift") == .modified)
		#expect(map.status(for: "/project/file2.swift") == .added)
		#expect(map.status(for: "/project/file3.swift") == .none)
		#expect(map.status(for: "/project/unknown.swift") == .unknown)
	}

	@Test("Paths with specific status")
	func pathsWithStatus() {
		let map = SCMStatusMap([
			"/a.swift": .modified,
			"/b.swift": .modified,
			"/c.swift": .added,
		])
		let modified = map.paths(with: .modified)
		#expect(modified.count == 2)
		#expect(modified.contains("/a.swift"))
		#expect(modified.contains("/b.swift"))
	}

	@Test("Modified paths")
	func modifiedPaths() {
		let map = SCMStatusMap([
			"/a.swift": .modified,
			"/b.swift": .none,
			"/c.swift": .added,
			"/d.swift": .ignored,
		])
		let modified = map.modifiedPaths
		#expect(modified.count == 2)
	}

	@Test("Interesting paths")
	func interestingPaths() {
		let map = SCMStatusMap([
			"/a.swift": .modified,
			"/b.swift": .none,
			"/c.swift": .unversioned,
			"/d.swift": .ignored,
		])
		let interesting = map.interestingPaths
		#expect(interesting.count == 2) // modified + unversioned
	}

	@Test("Merge maps")
	func mergeMaps() {
		var map1 = SCMStatusMap(["/a.swift": .modified])
		let map2 = SCMStatusMap(["/a.swift": .none, "/b.swift": .added])
		map1.merge(map2)
		#expect(map1.status(for: "/a.swift") == .none) // Overridden
		#expect(map1.status(for: "/b.swift") == .added)
	}

	@Test("Directory status — uniform children")
	func directoryStatusUniform() {
		let map = SCMStatusMap([
			"/project/src/a.swift": .modified,
			"/project/src/b.swift": .modified,
		])
		#expect(map.directoryStatus(for: "/project/src") == .modified)
	}

	@Test("Directory status — mixed children")
	func directoryStatusMixed() {
		let map = SCMStatusMap([
			"/project/src/a.swift": .modified,
			"/project/src/b.swift": .added,
		])
		#expect(map.directoryStatus(for: "/project/src") == .mixed)
	}

	@Test("Directory status — no children")
	func directoryStatusEmpty() {
		let map = SCMStatusMap()
		#expect(map.directoryStatus(for: "/project/src") == .none)
	}

	@Test("Equality")
	func equality() {
		let a = SCMStatusMap(["/a": .modified])
		let b = SCMStatusMap(["/a": .modified])
		let c = SCMStatusMap(["/a": .added])
		#expect(a == b)
		#expect(a != c)
	}
}

// MARK: - SCMVariables Tests

@Suite("SCMVariables")
struct SCMVariablesTests {
	@Test("Basic creation")
	func basic() {
		let vars = SCMVariables(scmName: "git", rootPath: "/project")
		#expect(vars.scmName == "git")
		#expect(vars.rootPath == "/project")
		#expect(vars.branch == nil)
	}

	@Test("With branch")
	func withBranch() {
		let vars = SCMVariables(scmName: "git", rootPath: "/project", branch: "main")
		#expect(vars.branch == "main")
	}

	@Test("Environment variables")
	func environmentVariables() {
		let vars = SCMVariables(
			scmName: "git",
			rootPath: "/project",
			branch: "feature",
			variables: ["TM_SCM_COMMIT": "abc123"],
		)
		let env = vars.environmentVariables
		#expect(env["TM_SCM_NAME"] == "git")
		#expect(env["TM_SCM_BRANCH"] == "feature")
		#expect(env["TM_SCM_COMMIT"] == "abc123")
	}

	@Test("Environment variables — no branch")
	func envNoBranch() {
		let vars = SCMVariables(scmName: "hg", rootPath: "/project")
		let env = vars.environmentVariables
		#expect(env["TM_SCM_NAME"] == "hg")
		#expect(env["TM_SCM_BRANCH"] == "")
	}

	@Test("Equality")
	func equality() {
		let a = SCMVariables(scmName: "git", rootPath: "/project", branch: "main")
		let b = SCMVariables(scmName: "git", rootPath: "/project", branch: "main")
		#expect(a == b)
	}
}
