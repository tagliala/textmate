import Testing
@testable import TMCore

@Suite("FormatStringExpander — Variable Expansion & Transforms")
struct FormatStringExpanderTests {
	// MARK: - Basic Expansion

	@Test func plainText() {
		let result = FormatString.expand("hello world")
		#expect(result == "hello world")
	}

	@Test func variableExpansion() {
		let result = FormatString.expand("hello $name", variables: ["name": "world"])
		#expect(result == "hello world")
	}

	@Test func missingVariable() {
		let result = FormatString.expand("hello $name")
		#expect(result == "hello ")
	}

	@Test func bracedVariable() {
		let result = FormatString.expand("${a} and ${b}", variables: ["a": "x", "b": "y"])
		#expect(result == "x and y")
	}

	// MARK: - Fallback

	@Test func fallbackUsed() {
		let result = FormatString.expand("${name:-fallback}")
		#expect(result == "fallback")
	}

	@Test func fallbackNotUsed() {
		let result = FormatString.expand("${name:-fallback}", variables: ["name": "real"])
		#expect(result == "real")
	}

	// MARK: - Conditions

	@Test func conditionIfSet() {
		let result = FormatString.expand("${name:+yes}", variables: ["name": "val"])
		#expect(result == "yes")
	}

	@Test func conditionIfNotSet() {
		let result = FormatString.expand("${name:+yes}")
		#expect(result == "")
	}

	@Test func conditionIfElseTrue() {
		let result = FormatString.expand("${x:?present:absent}", variables: ["x": "v"])
		#expect(result == "present")
	}

	@Test func conditionIfElseFalse() {
		let result = FormatString.expand("${x:?present:absent}")
		#expect(result == "absent")
	}

	@Test func legacyConditionSet() {
		let result = FormatString.expand("(?1:then:else)", variables: ["1": "x"])
		#expect(result == "then")
	}

	@Test func legacyConditionUnset() {
		let result = FormatString.expand("(?1:then:else)")
		#expect(result == "else")
	}

	// MARK: - Case Changes

	@Test func uppercaseAll() {
		let result = FormatString.expand("\\U$1\\E rest", variables: ["1": "hello"])
		#expect(result == "HELLO rest")
	}

	@Test func lowercaseAll() {
		let result = FormatString.expand("\\L$1\\E rest", variables: ["1": "HELLO"])
		#expect(result == "hello rest")
	}

	@Test func uppercaseNext() {
		let result = FormatString.expand("\\u$1", variables: ["1": "hello"])
		#expect(result == "Hello")
	}

	@Test func lowercaseNext() {
		let result = FormatString.expand("\\l$1", variables: ["1": "HELLO"])
		#expect(result == "hELLO")
	}

	// MARK: - Named Transforms

	@Test func transformUpcase() {
		let result = FormatString.expand("${name:/upcase}", variables: ["name": "hello"])
		#expect(result == "HELLO")
	}

	@Test func transformDowncase() {
		let result = FormatString.expand("${name:/downcase}", variables: ["name": "HELLO"])
		#expect(result == "hello")
	}

	@Test func transformCapitalize() {
		let result = FormatStringExpander.capitalize("the quick brown fox")
		#expect(result == "The Quick Brown Fox")
	}

	@Test func capitalizeStopWords() {
		// Short words should be lowercased when not first/last
		let result = FormatStringExpander.capitalize("from the over when")
		// "From" first word caps, "the" (3 chars → lowercase), "over" (4 chars → capitalize), "When" last word caps
		#expect(result == "From the Over When")
	}

	@Test func transformAsciify() {
		let result = FormatStringExpander.asciify("café")
		#expect(result == "cafe")
	}

	@Test func transformUrlEncode() {
		let result = FormatStringExpander.urlEncode("hello world")
		#expect(result == "hello%20world")
	}

	@Test func transformShellEscape() {
		let result = FormatStringExpander.shellEscape("hello world")
		#expect(result == "'hello world'")
	}

	@Test func shellEscapeSingleQuote() {
		let result = FormatStringExpander.shellEscape("it's")
		#expect(result == "it\\'s")
	}

	@Test func transformDirname() {
		let result = FormatString.expand("${name:/dirname}", variables: ["name": "/usr/local/bin/ls"])
		#expect(result == "/usr/local/bin")
	}

	@Test func transformBasename() {
		let result = FormatString.expand("${name:/basename}", variables: ["name": "/usr/local/bin/ls"])
		#expect(result == "ls")
	}

	// MARK: - Number Formatting

	@Test func formatNumberWithCommas() {
		#expect(FormatStringExpander.formatNumber("1234567") == "1,234,567")
	}

	@Test func formatNumberSmall() {
		#expect(FormatStringExpander.formatNumber("42") == "42")
	}

	@Test func formatNumberWithDecimal() {
		#expect(FormatStringExpander.formatNumber("1234.56") == "1,234.56")
	}

	// MARK: - Duration Formatting

	@Test func formatDurationSeconds() {
		#expect(FormatStringExpander.formatDuration("45") == "45 seconds")
	}

	@Test func formatDurationMinutes() {
		#expect(FormatStringExpander.formatDuration("125") == "2 minutes, 5 seconds")
	}

	@Test func formatDurationHours() {
		#expect(FormatStringExpander.formatDuration("7200") == "2 hours")
	}

	@Test func formatDurationDays() {
		#expect(FormatStringExpander.formatDuration("90000") == "1 day, 1 hour")
	}

	// MARK: - Control Codes

	@Test func controlCodeExpansion() {
		#expect(FormatString.expand("a\\tb") == "a\tb")
		#expect(FormatString.expand("a\\nb") == "a\nb")
		#expect(FormatString.expand("a\\rb") == "a\rb")
	}

	@Test func hexUnicodeExpansion() {
		let result = FormatString.expand("\\x{2014}")
		#expect(result == "\u{2014}") // em dash
	}

	// MARK: - Regex Replacement

	@Test func simpleReplacement() {
		let result = FormatString.replace("hello world", pattern: "world", format: "Swift")
		#expect(result == "hello Swift")
	}

	@Test func captureGroupReplacement() {
		let result = FormatString.replace("hello world", pattern: "(\\w+) (\\w+)", format: "$2 $1")
		#expect(result == "world hello")
	}

	@Test func globalReplacement() {
		let result = FormatString.replace("aaa", pattern: "a", format: "b", repeat: true)
		#expect(result == "bbb")
	}

	@Test func nonGlobalReplacement() {
		let result = FormatString.replace("aaa", pattern: "a", format: "b", repeat: false)
		#expect(result == "baa")
	}

	@Test func replacementWithCaseChange() {
		let result = FormatString.replace("hello", pattern: "(h)(ello)", format: "\\U$1\\E$2")
		#expect(result == "Hello")
	}

	// MARK: - Escape Round-Trip

	@Test func escapeSpecialChars() {
		let original = "hello\tworld\n$var (paren)"
		let escaped = FormatString.escape(original)
		let result = FormatString.expand(escaped)
		#expect(result == original)
	}

	@Test func escapeBackslash() {
		let escaped = FormatString.escape("back\\slash")
		let result = FormatString.expand(escaped)
		#expect(result == "back\\slash")
	}

	// MARK: - Implicit Variable Isolation

	@Test func nestedFormatStringIsolation() {
		// $1 in the format string of a variable transform shouldn't leak
		let result = FormatString.replace(
			"hello",
			pattern: "(h)(ello)",
			format: "${1:/upcase}$2",
		)
		#expect(result == "Hello")
	}
}
