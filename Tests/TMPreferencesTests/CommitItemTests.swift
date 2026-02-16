import Testing
@testable import TMPreferences

@Suite("CommitItem")
struct CommitItemTests {
	// MARK: - Initialization

	@Test("standard status auto-selects for commit")
	func standardStatusCommit() {
		let item = CommitItem(path: "file.swift", scmStatus: "M")
		#expect(item.commit == true)
		#expect(item.path == "file.swift")
		#expect(item.scmStatus == "M")
	}

	@Test("added status auto-selects for commit")
	func addedStatusCommit() {
		let item = CommitItem(path: "new.swift", scmStatus: "A")
		#expect(item.commit == true)
	}

	@Test("deleted status auto-selects for commit")
	func deletedStatusCommit() {
		let item = CommitItem(path: "removed.swift", scmStatus: "D")
		#expect(item.commit == true)
	}

	@Test("unversioned status auto-deselects from commit")
	func unversionedStatusDeselect() {
		let item = CommitItem(path: "unversioned.txt", scmStatus: "?")
		#expect(item.commit == false)
	}

	@Test("external status auto-deselects from commit")
	func externalStatusDeselect() {
		let item = CommitItem(path: "external.txt", scmStatus: "X")
		#expect(item.commit == false)
	}

	@Test("explicit commit false overrides status")
	func explicitCommitFalse() {
		let item = CommitItem(path: "file.swift", scmStatus: "M", commit: false)
		#expect(item.commit == false)
	}

	@Test("explicit commit true for unversioned still deselects")
	func explicitCommitTrueUnversioned() {
		// Auto-deselect logic: commit && status != "?" && status != "X"
		let item = CommitItem(path: "file.txt", scmStatus: "?", commit: true)
		#expect(item.commit == false)
	}

	// MARK: - Identifiable

	@Test("id is the path")
	func identifiable() {
		let item = CommitItem(path: "src/main.swift", scmStatus: "M")
		#expect(item.id == "src/main.swift")
	}

	// MARK: - Sorting

	@Test("items sort case-insensitively by path")
	func sorting() {
		let a = CommitItem(path: "Alpha.swift", scmStatus: "M")
		let b = CommitItem(path: "beta.swift", scmStatus: "A")
		let c = CommitItem(path: "gamma.swift", scmStatus: "D")

		var items = [c, a, b]
		items.sort(by: <)

		#expect(items.map(\.path) == ["Alpha.swift", "beta.swift", "gamma.swift"])
	}

	@Test("sorting is stable for equal case-insensitive names")
	func sortingEqualPaths() {
		let a = CommitItem(path: "File.swift", scmStatus: "M")
		let b = CommitItem(path: "file.swift", scmStatus: "A")
		// Both should sort as equal
		#expect(!(a < b) || !(b < a))
	}

	// MARK: - Equatable

	@Test("same items are equal")
	func equality() {
		let a = CommitItem(path: "f.txt", scmStatus: "M")
		let b = CommitItem(path: "f.txt", scmStatus: "M")
		#expect(a == b)
	}

	@Test("different paths are not equal")
	func inequalityPath() {
		let a = CommitItem(path: "a.txt", scmStatus: "M")
		let b = CommitItem(path: "b.txt", scmStatus: "M")
		#expect(a != b)
	}

	@Test("different statuses are not equal")
	func inequalityStatus() {
		let a = CommitItem(path: "f.txt", scmStatus: "M")
		let b = CommitItem(path: "f.txt", scmStatus: "A")
		#expect(a != b)
	}
}
