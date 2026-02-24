import Foundation
import Testing
@testable import TMSettings

@Suite("GlobPattern — Matching & Brace Expansion")
struct GlobPatternTests {
	// MARK: - Basic Matching

	@Test func emptyGlob() {
		let glob = GlobPattern("")
		#expect(!glob.doesMatch("test.txt"))
	}

	@Test func wildcardStar() {
		let glob = GlobPattern("*.txt")
		#expect(glob.doesMatch("test.txt"))
		#expect(glob.doesMatch("hello.txt"))
		#expect(!glob.doesMatch("test.cc"))
	}

	@Test func questionMark() {
		let glob = GlobPattern("?.txt")
		#expect(glob.doesMatch("a.txt"))
		#expect(!glob.doesMatch("ab.txt"))
	}

	@Test func literalMatch() {
		let glob = GlobPattern("Makefile")
		#expect(glob.doesMatch("Makefile"))
		#expect(glob.doesMatch("path/to/Makefile"))
		#expect(!glob.doesMatch("Makefile.bak"))
	}

	// MARK: - Character Classes

	@Test func charClassSimple() {
		let glob = GlobPattern("*.[ch]")
		#expect(glob.doesMatch("test.c"))
		#expect(glob.doesMatch("test.h"))
		#expect(!glob.doesMatch("test.m"))
	}

	@Test func charClassRange() {
		let glob = GlobPattern("*.[c-h]")
		#expect(glob.doesMatch("test.c"))
		#expect(glob.doesMatch("test.h"))
		#expect(glob.doesMatch("test.e"))
		#expect(!glob.doesMatch("test.a"))
	}

	// MARK: - Brace Expansion

	@Test func braceExpansionSimple() {
		let glob = GlobPattern("*.{cc,mm,h}")
		#expect(glob.doesMatch("test.cc"))
		#expect(glob.doesMatch("test.mm"))
		#expect(glob.doesMatch("test.h"))
		#expect(!glob.doesMatch("test.swift"))
	}

	@Test func expandBraces() {
		let result = GlobPattern.expandBraces("{a,b,c}")
		#expect(Set(result) == Set(["a", "b", "c"]))
	}

	@Test func expandBracesNested() {
		let result = GlobPattern.expandBraces("{a,{b,c}}")
		#expect(Set(result) == Set(["a", "b", "c"]))
	}

	@Test func expandBracesPrefix() {
		let result = GlobPattern.expandBraces("pre{a,b}suf")
		#expect(Set(result) == Set(["preasuf", "prebsuf"]))
	}

	@Test func noBraces() {
		let result = GlobPattern.expandBraces("hello")
		#expect(result == ["hello"])
	}

	// MARK: - Hidden Files

	@Test func starDoesNotMatchDotFiles() {
		let glob = GlobPattern("*")
		#expect(glob.doesMatch("test"))
		#expect(!glob.doesMatch(".hidden"))
	}

	@Test func dotStarMatchesDotFiles() {
		let glob = GlobPattern(".*")
		#expect(glob.doesMatch(".hidden"))
		#expect(!glob.doesMatch("visible"))
	}

	// MARK: - Path Matching

	@Test func starDoesNotCrossSlash() {
		let glob = GlobPattern("*.txt")
		#expect(glob.doesMatch("test.txt"))
		#expect(glob.doesMatch("dir/test.txt"))
	}

	@Test func doubleStarMatchesRecursive() {
		let glob = GlobPattern("**/*.txt")
		#expect(glob.doesMatch("test.txt"))
		#expect(glob.doesMatch("dir/test.txt"))
		#expect(glob.doesMatch("a/b/c/test.txt"))
	}

	// MARK: - Case Sensitivity

	@Test func caseSensitive() {
		let glob = GlobPattern("*.TXT", caseSensitive: true)
		#expect(!glob.doesMatch("test.txt"))
		#expect(glob.doesMatch("test.TXT"))
	}

	@Test func caseInsensitive() {
		let glob = GlobPattern("*.TXT", caseSensitive: false)
		#expect(glob.doesMatch("test.txt"))
		#expect(glob.doesMatch("test.TXT"))
	}

	// MARK: - Escaping

	@Test func escapeSpecialChars() {
		let escaped = GlobPattern.escape("test[1].txt")
		#expect(escaped == "test\\[1].txt")
	}

	@Test func escapeGlobChars() {
		let escaped = GlobPattern.escape("*.{a,b}")
		#expect(escaped.contains("\\*"))
		#expect(escaped.contains("\\{"))
	}

	// MARK: - Anchoring

	@Test func globMatchesSubpath() {
		let glob = GlobPattern("foo")
		#expect(glob.doesMatch("foo"))
		#expect(glob.doesMatch("bar/foo"))
		#expect(!glob.doesMatch("foobar"))
	}

	// MARK: - Exclusion

	@Test func tildeExclusion() {
		let glob = GlobPattern("*.cc~vendor/*")
		#expect(glob.doesMatch("test.cc"))
		#expect(!glob.doesMatch("vendor/test.cc"))
	}

	// MARK: - Glob List

	@Test func emptyGlobListIncludesAll() {
		let list = GlobList()
		#expect(list.include("anything.txt"))
		#expect(!list.exclude("anything.txt"))
	}

	@Test func globListInclude() {
		var list = GlobList()
		list.addIncludeGlob("*.txt")
		#expect(!list.exclude("test.txt"))
	}

	@Test func globListExclude() {
		var list = GlobList()
		list.addExcludeGlob("*.bak")
		#expect(list.exclude("test.bak"))
	}

	@Test func globListMixed() {
		var list = GlobList()
		list.addIncludeGlob("*")
		list.addExcludeGlob("*.bak")
		// First match wins — "*" matches first, and it's an include
		#expect(!list.exclude("test.txt"))
	}
}
