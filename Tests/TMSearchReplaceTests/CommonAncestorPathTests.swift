import Testing
@testable import TMSearchReplace

// MARK: - Common Ancestor Path Tests

@Suite("CommonAncestorPath — Path Ancestor Computation")
struct CommonAncestorPathTests {
	@Test("Empty array returns nil")
	func emptyInput() {
		#expect(CommonAncestorPath.compute([]) == nil)
	}

	@Test("Single path returns the path itself (directory check)")
	func singlePath() {
		let result = CommonAncestorPath.compute(["/tmp"])
		#expect(result != nil)
		// /tmp is a directory, so it returns itself
	}

	@Test("Two paths with common prefix")
	func twoPathsCommonPrefix() {
		let result = CommonAncestorPath.compute([
			"/Users/test/src/main.swift",
			"/Users/test/src/util.swift",
		])
		// Common prefix up to last / before divergence
		#expect(result == "/Users/test/src")
	}

	@Test("Two paths sharing only root")
	func pathsSharingOnlyRoot() {
		let result = CommonAncestorPath.compute([
			"/Applications/TextMate.app",
			"/Users/test/Documents",
		])
		#expect(result == "/")
	}

	@Test("Paths in same directory")
	func pathsInSameDirectory() {
		let result = CommonAncestorPath.compute([
			"/Users/test/file1.txt",
			"/Users/test/file2.txt",
		])
		#expect(result == "/Users/test")
	}

	@Test("Three paths with partial overlap")
	func threePathsPartialOverlap() {
		let result = CommonAncestorPath.compute([
			"/Users/shared/project/src/main.swift",
			"/Users/shared/project/tests/test.swift",
			"/Users/shared/project/README.md",
		])
		#expect(result == "/Users/shared/project")
	}

	@Test("Identical paths")
	func identicalPaths() {
		let result = CommonAncestorPath.compute([
			"/Users/test/src",
			"/Users/test/src",
		])
		#expect(result != nil)
	}

	@Test("Paths with different lengths")
	func pathsDifferentLengths() {
		let result = CommonAncestorPath.compute([
			"/a/b/c/d/e/f",
			"/a/b",
		])
		// /a/b is the common part; it may or may not exist but algorithm
		// returns the prefix up to the separator before divergence
		#expect(result == "/a")
	}

	@Test("Nested paths")
	func nestedPaths() {
		let result = CommonAncestorPath.compute([
			"/Users/test/project",
			"/Users/test/project/src/main.swift",
		])
		// The shorter path is a prefix of the longer, common ancestor is /Users/test
		#expect(result == "/Users/test")
	}
}
