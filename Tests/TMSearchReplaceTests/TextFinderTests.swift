import Testing
@testable import TMSearchReplace

// MARK: - PlainTextFinder Tests

@Suite("PlainTextFinder")
struct PlainTextFinderTests {
	@Test("Finds simple substring")
	func simpleFind() {
		let finder = PlainTextFinder(searchString: "hello")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "say hello world", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 1)
		#expect(matches[0].range == 4 ..< 9)
	}

	@Test("Finds multiple occurrences")
	func multipleOccurrences() {
		let finder = PlainTextFinder(searchString: "ab")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "ababab", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 3)
	}

	@Test("Case sensitive by default")
	func caseSensitive() {
		let finder = PlainTextFinder(searchString: "Hello")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "hello HELLO Hello", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 1)
	}

	@Test("Case insensitive with option")
	func caseInsensitive() {
		let finder = PlainTextFinder(searchString: "Hello", options: .ignoreCase)
		var matches: [FindMatch] = []
		finder.eachMatch(in: "hello HELLO Hello", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 3)
	}

	@Test("Full word matching")
	func fullWords() {
		let finder = PlainTextFinder(searchString: "cat", options: .fullWords)
		var matches: [FindMatch] = []
		finder.eachMatch(in: "cat concatenate category cat", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 2) // "cat" at start and end, not "concatenate" or "category"
	}

	@Test("Backwards search finds last match")
	func backwards() {
		let finder = PlainTextFinder(searchString: "x", options: .backwards)
		var matches: [FindMatch] = []
		finder.eachMatch(in: "x y x z x", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 1)
		#expect(matches[0].range == 8 ..< 9) // Last "x"
	}

	@Test("Stop callback halts search")
	func stopCallback() {
		let finder = PlainTextFinder(searchString: "a")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "aaa", offset: 0, moreToCome: false) { match, stop in
			matches.append(match)
			if matches.count == 2 { stop = true }
		}
		#expect(matches.count == 2)
	}

	@Test("Empty search string finds nothing")
	func emptySearch() {
		let finder = PlainTextFinder(searchString: "")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "hello", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.isEmpty)
	}

	@Test("No match returns nothing")
	func noMatch() {
		let finder = PlainTextFinder(searchString: "xyz")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "hello world", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.isEmpty)
	}

	@Test("Offset is applied to byte ranges")
	func offset() {
		let finder = PlainTextFinder(searchString: "world")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "hello world", offset: 100, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 1)
		#expect(matches[0].range == 106 ..< 111)
	}

	@Test("Unicode text")
	func unicode() {
		let finder = PlainTextFinder(searchString: "café")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "at the café today", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 1)
	}

	@Test("Ignore whitespace collapses spaces")
	func ignoreWhitespace() {
		let finder = PlainTextFinder(searchString: "hello world", options: .ignoreWhitespace)
		var matches: [FindMatch] = []
		finder.eachMatch(in: "hello   world", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 1)
	}
}

// MARK: - RegexFinder Tests

@Suite("RegexFinder")
struct RegexFinderTests {
	@Test("Simple regex match")
	func simpleRegex() throws {
		let finder = try RegexFinder(pattern: "h[aeiou]llo")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "hello hallo hullo", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 3)
	}

	@Test("Capture groups")
	func captureGroups() throws {
		let finder = try RegexFinder(pattern: "(\\w+)=(\\w+)")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "key=value", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 1)
		#expect(matches[0].captures["0"] == "key=value")
		#expect(matches[0].captures["1"] == "key")
		#expect(matches[0].captures["2"] == "value")
	}

	@Test("Case insensitive regex")
	func caseInsensitive() throws {
		let finder = try RegexFinder(pattern: "hello", options: .ignoreCase)
		var matches: [FindMatch] = []
		finder.eachMatch(in: "Hello HELLO hello", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 3)
	}

	@Test("Backwards regex finds last match")
	func backwards() throws {
		let finder = try RegexFinder(pattern: "\\d+", options: .backwards)
		var matches: [FindMatch] = []
		finder.eachMatch(in: "1 22 333", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 1)
		#expect(matches[0].captures["0"] == "333")
	}

	@Test("Full words with regex")
	func fullWords() throws {
		let finder = try RegexFinder(pattern: "cat", options: .fullWords)
		var matches: [FindMatch] = []
		finder.eachMatch(in: "cat concatenate cat", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.count == 2)
	}

	@Test("Invalid regex throws")
	func invalidRegex() {
		#expect(throws: Error.self) {
			_ = try RegexFinder(pattern: "[invalid")
		}
	}

	@Test("Empty pattern finds nothing meaningful")
	func emptyPattern() throws {
		let finder = try RegexFinder(pattern: "xyz_nonexistent")
		var matches: [FindMatch] = []
		finder.eachMatch(in: "hello world", offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}
		#expect(matches.isEmpty)
	}
}

// MARK: - Factory Tests

@Suite("TextFinder Factory")
struct TextFinderFactoryTests {
	@Test("Creates PlainTextFinder without regex option")
	func plainText() throws {
		let finder = try makeTextFinder(pattern: "hello", options: .none)
		#expect(finder is PlainTextFinder)
	}

	@Test("Creates RegexFinder with regex option")
	func regex() throws {
		let finder = try makeTextFinder(pattern: "hello", options: .regularExpression)
		#expect(finder is RegexFinder)
	}

	@Test("Invalid regex throws from factory")
	func invalidRegex() {
		#expect(throws: Error.self) {
			_ = try makeTextFinder(pattern: "[invalid", options: .regularExpression)
		}
	}
}

// MARK: - Regex Validation Tests

@Suite("RegexValidation")
struct RegexValidationTests {
	@Test("Valid pattern returns nil")
	func validPattern() {
		#expect(validateRegexPattern("hello") == nil)
		#expect(validateRegexPattern("\\d+") == nil)
		#expect(validateRegexPattern("(a|b)+") == nil)
	}

	@Test("Invalid pattern returns error message")
	func invalidPattern() {
		let result = validateRegexPattern("[invalid")
		#expect(result != nil)
	}
}
