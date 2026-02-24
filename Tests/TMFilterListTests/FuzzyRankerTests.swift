import Testing
@testable import TMFilterList

@Suite("FuzzyRanker")
struct FuzzyRankerTests {
	// MARK: - normalizeFilter

	@Test("normalizeFilter lowercases and strips spaces")
	func normalizeFilter() {
		#expect(FuzzyRanker.normalizeFilter("Hello World") == "helloworld")
		#expect(FuzzyRanker.normalizeFilter("FOO BAR") == "foobar")
		#expect(FuzzyRanker.normalizeFilter("abc") == "abc")
		#expect(FuzzyRanker.normalizeFilter("") == "")
		#expect(FuzzyRanker.normalizeFilter("  spaces  ") == "spaces")
	}

	// MARK: - Empty Filter

	@Test("empty filter matches everything with score 1")
	func emptyFilter() {
		let result = FuzzyRanker.rank(filter: "", candidate: "anything")
		#expect(result.isMatch)
		#expect(result.score == 1.0)
		#expect(result.coverRanges.isEmpty)
	}

	// MARK: - Exact Match

	@Test("exact match returns score 1")
	func exactMatch() {
		let result = FuzzyRanker.rank(filter: "hello", candidate: "hello")
		#expect(result.isMatch)
		#expect(result.score == 1.0)
		#expect(result.coverRanges.count == 1)
		#expect(result.coverRanges[0] == CoverRange(start: 0, end: 5))
	}

	@Test("case-insensitive exact match")
	func caseInsensitiveExact() {
		let result = FuzzyRanker.rank(filter: "hello", candidate: "Hello")
		#expect(result.isMatch)
		#expect(result.score == 1.0)
	}

	// MARK: - No Match

	@Test("no match returns score 0")
	func noMatch() {
		let result = FuzzyRanker.rank(filter: "xyz", candidate: "hello")
		#expect(!result.isMatch)
		#expect(result.score == 0)
	}

	@Test("subsequence must be in order")
	func outOfOrder() {
		let result = FuzzyRanker.rank(filter: "ba", candidate: "ab")
		#expect(!result.isMatch)
	}

	// MARK: - CamelCase Matching

	@Test("CamelCase matching scores well")
	func camelCaseMatch() {
		let result = FuzzyRanker.rank(filter: "fb", candidate: "FooBar")
		#expect(result.isMatch)
		#expect(result.score > 0.5)
	}

	@Test("CamelCase matching beats scattered match")
	func camelCaseBeatScattered() {
		let camel = FuzzyRanker.rank(filter: "fb", candidate: "FooBar")
		let scattered = FuzzyRanker.rank(filter: "fb", candidate: "fxxxxxb")
		#expect(camel.score > scattered.score)
	}

	@Test("snake_case word boundaries detected")
	func snakeCaseWordBounds() {
		let result = FuzzyRanker.rank(filter: "fb", candidate: "foo_bar")
		#expect(result.isMatch)
		#expect(result.score > 0.5)
	}

	// MARK: - Contiguous Runs

	@Test("contiguous substring scores better than scattered")
	func contiguousBetterThanScattered() {
		let contiguous = FuzzyRanker.rank(filter: "foo", candidate: "foobar")
		let scattered = FuzzyRanker.rank(filter: "foo", candidate: "fxoxo")
		#expect(contiguous.score > scattered.score)
	}

	@Test("prefix match scores well")
	func prefixMatch() {
		let prefix = FuzzyRanker.rank(filter: "fo", candidate: "foobar")
		let suffix = FuzzyRanker.rank(filter: "fo", candidate: "barfoo")
		#expect(prefix.score >= suffix.score)
	}

	// MARK: - Cover Ranges

	@Test("cover ranges mark matched positions")
	func coverRanges() {
		let result = FuzzyRanker.rank(filter: "fb", candidate: "FooBar")
		#expect(result.isMatch)
		#expect(!result.coverRanges.isEmpty)
		// Should have at least one range covering position 0 (F) and one covering position 3 (B)
		let allPositions = result.coverRanges.flatMap { $0.start ..< $0.end }
		#expect(allPositions.contains(0)) // 'F'
		#expect(allPositions.contains(3)) // 'B'
	}

	@Test("exact match has single cover range")
	func exactMatchSingleRange() {
		let result = FuzzyRanker.rank(filter: "abc", candidate: "abc")
		#expect(result.coverRanges.count == 1)
		#expect(result.coverRanges[0].start == 0)
		#expect(result.coverRanges[0].end == 3)
	}

	// MARK: - Overflow Guard

	@Test("overflow guard handles large inputs")
	func overflowGuard() {
		let longCandidate = String(repeating: "a", count: 200)
		let filter = String(repeating: "a", count: 50)
		// 50 * 200 = 10000 > 8096, should use simple ratio
		let result = FuzzyRanker.rank(filter: filter, candidate: longCandidate)
		#expect(result.isMatch)
		#expect(result.score > 0)
		#expect(result.score <= 1)
	}

	// MARK: - Empty Candidate

	@Test("empty candidate returns no match for non-empty filter")
	func emptyCandidateNoMatch() {
		let result = FuzzyRanker.rank(filter: "a", candidate: "")
		#expect(!result.isMatch)
	}

	// MARK: - Real-World Patterns

	@Test("filename matching - short filter on long path")
	func filenameMatching() {
		let result = FuzzyRanker.rank(filter: "vc", candidate: "ViewController.swift")
		#expect(result.isMatch)
		#expect(result.score > 0.5)
	}

	@Test("multiple word matching")
	func multipleWordMatching() {
		let result = FuzzyRanker.rank(filter: "appd", candidate: "AppDelegate")
		#expect(result.isMatch)
		#expect(result.score > 0.5)
	}

	@Test("path matching with separators")
	func pathMatching() {
		let result = FuzzyRanker.rank(filter: "src", candidate: "src/main.swift")
		#expect(result.isMatch)
	}

	// MARK: - Score Properties

	@Test("score is always in valid range")
	func scoreRange() {
		let testCases = [
			("a", "abc"),
			("abc", "abcdef"),
			("fb", "FooBar"),
			("x", "xyz"),
			("long", "a_very_long_candidate_string"),
		]
		for (filter, candidate) in testCases {
			let result = FuzzyRanker.rank(filter: filter, candidate: candidate)
			if result.isMatch {
				#expect(result.score > 0)
				#expect(result.score <= 1)
			}
		}
	}

	// MARK: - RankResult

	@Test("RankResult.noMatch has zero score")
	func rankResultNoMatch() {
		let noMatch = RankResult.noMatch
		#expect(noMatch.score == 0)
		#expect(!noMatch.isMatch)
		#expect(noMatch.coverRanges.isEmpty)
	}

	// MARK: - CoverRange

	@Test("CoverRange properties")
	func coverRangeProperties() {
		let range = CoverRange(start: 5, end: 10)
		#expect(range.length == 5)
		#expect(range.start == 5)
		#expect(range.end == 10)
	}

	@Test("CoverRange equality")
	func coverRangeEquality() {
		let a = CoverRange(start: 0, end: 5)
		let b = CoverRange(start: 0, end: 5)
		let c = CoverRange(start: 1, end: 5)
		#expect(a == b)
		#expect(a != c)
	}
}
