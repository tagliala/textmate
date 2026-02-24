import Testing
@testable import TMSearchReplace

// MARK: - BufferSearcher Tests

@Suite("BufferSearcher")
struct BufferSearcherTests {
	let sampleText = "The quick brown fox jumps over the lazy dog"

	// MARK: - Find Next

	@Test("Find next from beginning")
	func findNextFromBeginning() throws {
		let searcher = BufferSearcher(text: sampleText)
		let result = try searcher.findNext(pattern: "fox", options: .none)
		#expect(result.hasMatches)
		#expect(result.count == 1)
		#expect(!result.didWrap)
	}

	@Test("Find next from offset")
	func findNextFromOffset() throws {
		let searcher = BufferSearcher(text: "aXaXa")
		let result = try searcher.findNext(pattern: "X", options: .none, fromOffset: 2)
		#expect(result.hasMatches)
		#expect(result.firstMatch?.range == 3 ..< 4) // Second X
	}

	@Test("Find next with wrap around")
	func findNextWrapAround() throws {
		let searcher = BufferSearcher(text: "hello world hello")
		let result = try searcher.findNext(pattern: "hello", options: .wrapAround, fromOffset: 10)
		#expect(result.hasMatches)
		#expect(result.firstMatch?.range == 12 ..< 17) // Second hello after offset 10
	}

	@Test("Find next wraps to beginning")
	func findNextWrapsToBeginning() throws {
		let searcher = BufferSearcher(text: "hello world")
		let result = try searcher.findNext(pattern: "hello", options: .wrapAround, fromOffset: 6)
		#expect(result.hasMatches)
		#expect(result.didWrap)
		#expect(result.firstMatch?.range == 0 ..< 5)
	}

	@Test("Find next no match no wrap")
	func findNextNoMatch() throws {
		let searcher = BufferSearcher(text: "hello world")
		let result = try searcher.findNext(pattern: "xyz", options: .none)
		#expect(!result.hasMatches)
		#expect(result.count == 0)
	}

	@Test("Find previous")
	func findPrevious() throws {
		let searcher = BufferSearcher(text: "aXbXcXd")
		let result = try searcher.findNext(pattern: "X", options: .backwards, fromOffset: 5)
		#expect(result.hasMatches)
		#expect(result.firstMatch?.range == 3 ..< 4) // X before offset 5
	}

	@Test("Find with empty pattern returns empty result")
	func emptyPattern() throws {
		let searcher = BufferSearcher(text: sampleText)
		let result = try searcher.findNext(pattern: "", options: .none)
		#expect(!result.hasMatches)
	}

	// MARK: - Find All

	@Test("Find all occurrences")
	func findAll() throws {
		let searcher = BufferSearcher(text: "the cat sat on the mat")
		let result = try searcher.findAll(pattern: "the", options: .none)
		#expect(result.count == 2)
	}

	@Test("Find all case insensitive")
	func findAllCaseInsensitive() throws {
		let searcher = BufferSearcher(text: "The the THE")
		let result = try searcher.findAll(pattern: "the", options: .ignoreCase)
		#expect(result.count == 3)
	}

	@Test("Find all with regex")
	func findAllRegex() throws {
		let searcher = BufferSearcher(text: "cat 123 bat 456 hat")
		let result = try searcher.findAll(pattern: "\\d+", options: .regularExpression)
		#expect(result.count == 2)
		#expect(result.matches[0].captures["0"] == "123")
		#expect(result.matches[1].captures["0"] == "456")
	}

	@Test("Find all with search range")
	func findAllInRange() throws {
		let searcher = BufferSearcher(text: "aaabbbaaaccc")
		let result = try searcher.findAll(pattern: "aaa", options: .none, searchRange: 3 ..< 12)
		#expect(result.count == 1)
	}

	@Test("Find all no matches")
	func findAllNoMatch() throws {
		let searcher = BufferSearcher(text: sampleText)
		let result = try searcher.findAll(pattern: "xyz", options: .none)
		#expect(result.count == 0)
		#expect(!result.hasMatches)
	}

	// MARK: - Count

	@Test("Count matches")
	func countMatches() throws {
		let searcher = BufferSearcher(text: "banana")
		let count = try searcher.countMatches(pattern: "an", options: .none)
		#expect(count == 2)
	}

	@Test("Count with no matches")
	func countNoMatches() throws {
		let searcher = BufferSearcher(text: "hello")
		let count = try searcher.countMatches(pattern: "xyz", options: .none)
		#expect(count == 0)
	}

	// MARK: - Replace All

	@Test("Replace all plain text")
	func replaceAllPlain() throws {
		let searcher = BufferSearcher(text: "hello hello hello")
		let (result, count, _) = try searcher.replaceAll(
			pattern: "hello",
			replacement: "hi",
			options: .none,
		)
		#expect(result == "hi hi hi")
		#expect(count == 3)
	}

	@Test("Replace all with regex captures")
	func replaceAllRegex() throws {
		let searcher = BufferSearcher(text: "key=value")
		let (result, count, _) = try searcher.replaceAll(
			pattern: "(\\w+)=(\\w+)",
			replacement: "$2=$1",
			options: .regularExpression,
		)
		#expect(result == "value=key")
		#expect(count == 1)
	}

	@Test("Replace all with no matches")
	func replaceAllNoMatch() throws {
		let searcher = BufferSearcher(text: "hello world")
		let (result, count, _) = try searcher.replaceAll(
			pattern: "xyz",
			replacement: "abc",
			options: .none,
		)
		#expect(result == "hello world")
		#expect(count == 0)
	}

	@Test("Replace all returns replacement ranges")
	func replaceAllRanges() throws {
		let searcher = BufferSearcher(text: "ab ab")
		let (_, _, ranges) = try searcher.replaceAll(
			pattern: "ab",
			replacement: "xyz",
			options: .none,
		)
		#expect(ranges.count == 2)
	}

	@Test("Replace in search range")
	func replaceInRange() throws {
		let searcher = BufferSearcher(text: "aaa bbb aaa")
		let (result, count, _) = try searcher.replaceAll(
			pattern: "aaa",
			replacement: "xxx",
			options: .none,
			searchRange: 0 ..< 4,
		)
		#expect(count == 1) // Only the first "aaa"
		#expect(result.hasPrefix("xxx"))
	}

	// MARK: - Edge Cases

	@Test("Unicode in search and replace")
	func unicodeSearchReplace() throws {
		let searcher = BufferSearcher(text: "café noir café")
		let (result, count, _) = try searcher.replaceAll(
			pattern: "café",
			replacement: "coffee",
			options: .none,
		)
		#expect(result == "coffee noir coffee")
		#expect(count == 2)
	}

	@Test("Multi-line text search")
	func multiLine() throws {
		let text = "line1\nline2\nline3\nline1\n"
		let searcher = BufferSearcher(text: text)
		let result = try searcher.findAll(pattern: "line1", options: .none)
		#expect(result.count == 2)
	}

	@Test("Regex with newlines")
	func regexNewlines() throws {
		let text = "start\nmiddle\nend"
		let searcher = BufferSearcher(text: text)
		let result = try searcher.findAll(pattern: "^\\w+$", options: .regularExpression)
		#expect(result.count == 3) // Each line matches
	}
}

// MARK: - BufferSearchResult Tests

@Suite("BufferSearchResult")
struct BufferSearchResultTests {
	@Test("Empty result")
	func emptyResult() {
		let result = BufferSearchResult()
		#expect(!result.hasMatches)
		#expect(result.count == 0)
		#expect(result.firstMatch == nil)
		#expect(!result.didWrap)
	}

	@Test("Result with matches")
	func withMatches() {
		let result = BufferSearchResult(
			matches: [
				FindMatch(range: 0 ..< 5),
				FindMatch(range: 10 ..< 15),
			],
			didWrap: true,
		)
		#expect(result.hasMatches)
		#expect(result.count == 2)
		#expect(result.firstMatch?.range == 0 ..< 5)
		#expect(result.didWrap)
	}
}
