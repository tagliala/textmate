import Testing
@testable import TMCore

@Suite("FormatStringParser — Parse Format Strings & Snippets")
struct FormatStringParserTests {
	// MARK: - Format String Basics

	@Test func plainText() {
		let nodes = FormatStringParser.parseFormatString("hello world")
		#expect(nodes == [.text("hello world")])
	}

	@Test func emptyInput() {
		let nodes = FormatStringParser.parseFormatString("")
		#expect(nodes.isEmpty)
	}

	@Test func simpleVariable() {
		let nodes = FormatStringParser.parseFormatString("$name")
		#expect(nodes == [.variable(name: "name")])
	}

	@Test func numericVariable() {
		let nodes = FormatStringParser.parseFormatString("$1")
		#expect(nodes == [.variable(name: "1")])
	}

	@Test func bracedVariable() {
		let nodes = FormatStringParser.parseFormatString("${name}")
		#expect(nodes == [.variable(name: "name")])
	}

	@Test func variableInText() {
		let nodes = FormatStringParser.parseFormatString("hello $name world")
		#expect(nodes.count == 3)
		#expect(nodes[0] == .text("hello "))
		#expect(nodes[1] == .variable(name: "name"))
		#expect(nodes[2] == .text(" world"))
	}

	@Test func multipleVariables() {
		let nodes = FormatStringParser.parseFormatString("$a and $b")
		#expect(nodes.count == 3)
		#expect(nodes[0] == .variable(name: "a"))
		#expect(nodes[1] == .text(" and "))
		#expect(nodes[2] == .variable(name: "b"))
	}

	// MARK: - Fallback & Conditionals

	@Test func variableFallback() {
		let nodes = FormatStringParser.parseFormatString("${name:-default}")
		#expect(nodes.count == 1)
		if case let .variableFallback(name, fallback) = nodes[0] {
			#expect(name == "name")
			#expect(fallback == [.text("default")])
		} else {
			Issue.record("Expected variableFallback")
		}
	}

	@Test func variableConditionIfSet() {
		let nodes = FormatStringParser.parseFormatString("${name:+yes}")
		if case let .variableCondition(name, ifSet, ifNotSet) = nodes[0] {
			#expect(name == "name")
			#expect(ifSet == [.text("yes")])
			#expect(ifNotSet.isEmpty)
		} else {
			Issue.record("Expected variableCondition")
		}
	}

	@Test func variableConditionIfElse() {
		let nodes = FormatStringParser.parseFormatString("${name:?yes:no}")
		if case let .variableCondition(name, ifSet, ifNotSet) = nodes[0] {
			#expect(name == "name")
			#expect(ifSet == [.text("yes")])
			#expect(ifNotSet == [.text("no")])
		} else {
			Issue.record("Expected variableCondition")
		}
	}

	@Test func legacyCondition() {
		let nodes = FormatStringParser.parseFormatString("(?1:then:else)")
		if case let .variableCondition(name, ifSet, ifNotSet) = nodes[0] {
			#expect(name == "1")
			#expect(ifSet == [.text("then")])
			#expect(ifNotSet == [.text("else")])
		} else {
			Issue.record("Expected variableCondition, got \(nodes)")
		}
	}

	@Test func legacyConditionNoElse() {
		let nodes = FormatStringParser.parseFormatString("(?2:present)")
		if case let .variableCondition(name, ifSet, ifNotSet) = nodes[0] {
			#expect(name == "2")
			#expect(ifSet == [.text("present")])
			#expect(ifNotSet.isEmpty)
		} else {
			Issue.record("Expected variableCondition")
		}
	}

	// MARK: - Case Changes

	@Test func caseChangeUpper() {
		let nodes = FormatStringParser.parseFormatString("\\U$1\\E")
		#expect(nodes.count == 3)
		#expect(nodes[0] == .caseChange(.upper))
		#expect(nodes[1] == .variable(name: "1"))
		#expect(nodes[2] == .caseChange(.none))
	}

	@Test func caseChangeLower() {
		let nodes = FormatStringParser.parseFormatString("\\L$1\\E")
		#expect(nodes[0] == .caseChange(.lower))
	}

	@Test func caseChangeUpperNext() {
		let nodes = FormatStringParser.parseFormatString("\\u$1")
		#expect(nodes[0] == .caseChange(.upperNext))
	}

	// MARK: - Control Codes

	@Test func controlCodeTab() {
		let nodes = FormatStringParser.parseFormatString("a\\tb")
		#expect(nodes == [.text("a\tb")])
	}

	@Test func controlCodeNewline() {
		let nodes = FormatStringParser.parseFormatString("a\\nb")
		#expect(nodes == [.text("a\nb")])
	}

	@Test func controlCodeReturn() {
		let nodes = FormatStringParser.parseFormatString("a\\rb")
		#expect(nodes == [.text("a\rb")])
	}

	@Test func controlCodeHex() {
		let nodes = FormatStringParser.parseFormatString("\\x41")
		#expect(nodes == [.text("A")])
	}

	@Test func controlCodeHexBraced() {
		let nodes = FormatStringParser.parseFormatString("\\x{2014}")
		#expect(nodes == [.text("\u{2014}")])
	}

	// MARK: - Named Transforms

	@Test func namedTransformUpcase() {
		let nodes = FormatStringParser.parseFormatString("${name:/upcase}")
		if case let .variableChange(name, change) = nodes[0] {
			#expect(name == "name")
			#expect(change.contains(.upcase))
		} else {
			Issue.record("Expected variableChange")
		}
	}

	@Test func namedTransformDowncase() {
		let nodes = FormatStringParser.parseFormatString("${name:/downcase}")
		if case let .variableChange(_, change) = nodes[0] {
			#expect(change.contains(.downcase))
		} else {
			Issue.record("Expected variableChange")
		}
	}

	// MARK: - Variable Transforms

	@Test func variableTransform() {
		let nodes = FormatStringParser.parseFormatString("${name/foo/bar/g}")
		if case let .variableTransform(name, _, format, options) = nodes[0] {
			#expect(name == "name")
			#expect(format == [.text("bar")])
			#expect(options.contains(.global))
		} else {
			Issue.record("Expected variableTransform")
		}
	}

	// MARK: - Snippet Parsing

	@Test func snippetPlaceholder() {
		let nodes = FormatStringParser.parseSnippet("hello $1 world")
		#expect(nodes.count == 3)
		#expect(nodes[0] == .text("hello "))
		#expect(nodes[1] == .placeholder(index: 1, content: []))
		#expect(nodes[2] == .text(" world"))
	}

	@Test func snippetPlaceholderWithContent() {
		let nodes = FormatStringParser.parseSnippet("${1:default}")
		if case let .placeholder(index, content) = nodes[0] {
			#expect(index == 1)
			#expect(content == [.text("default")])
		} else {
			Issue.record("Expected placeholder with content")
		}
	}

	@Test func snippetNestedPlaceholders() {
		let nodes = FormatStringParser.parseSnippet("${1:hello ${2:world}}")
		if case let .placeholder(index, content) = nodes[0] {
			#expect(index == 1)
			#expect(content.count == 2)
			#expect(content[0] == .text("hello "))
			if case let .placeholder(idx2, content2) = content[1] {
				#expect(idx2 == 2)
				#expect(content2 == [.text("world")])
			}
		} else {
			Issue.record("Expected nested placeholder")
		}
	}

	@Test func snippetPlaceholderTransform() {
		let nodes = FormatStringParser.parseSnippet("${1/foo/bar/g}")
		if case let .placeholderTransform(index, pattern, format, options) = nodes[0] {
			#expect(index == 1)
			#expect(pattern == "foo")
			#expect(format == [.text("bar")])
			#expect(options.contains(.global))
		} else {
			Issue.record("Expected placeholderTransform")
		}
	}

	@Test func snippetChoices() {
		let nodes = FormatStringParser.parseSnippet("${1|one,two,three|}")
		if case let .placeholderChoice(index, choices) = nodes[0] {
			#expect(index == 1)
			#expect(choices.count == 3)
			#expect(choices[0] == [.text("one")])
			#expect(choices[1] == [.text("two")])
			#expect(choices[2] == [.text("three")])
		} else {
			Issue.record("Expected placeholderChoice")
		}
	}

	@Test func snippetCodeBlock() {
		let nodes = FormatStringParser.parseSnippet("hello `echo world` end")
		#expect(nodes.count == 3)
		#expect(nodes[0] == .text("hello "))
		#expect(nodes[1] == .code("echo world"))
		#expect(nodes[2] == .text(" end"))
	}

	@Test func snippetExitPlaceholder() {
		let nodes = FormatStringParser.parseSnippet("hello $0")
		#expect(nodes.count == 2)
		#expect(nodes[0] == .text("hello "))
		#expect(nodes[1] == .placeholder(index: 0, content: []))
	}

	@Test func snippetEscapedDollar() {
		let nodes = FormatStringParser.parseSnippet("cost \\$5")
		#expect(nodes == [.text("cost $5")])
	}

	@Test func snippetBracedPlaceholder() {
		let nodes = FormatStringParser.parseSnippet("${1}")
		#expect(nodes == [.placeholder(index: 1, content: [])])
	}

	@Test func snippetMultiplePlaceholders() {
		let nodes = FormatStringParser.parseSnippet("$1 and $2 then $0")
		#expect(nodes.count == 5)
		#expect(nodes[0] == .placeholder(index: 1, content: []))
		#expect(nodes[2] == .placeholder(index: 2, content: []))
		#expect(nodes[4] == .placeholder(index: 0, content: []))
	}

	// MARK: - Escape Round-Trip

	@Test func escapeFormatString() {
		let original = "hello\tworld\n$var (paren) \\back"
		let escaped = FormatString.escape(original)
		let expanded = FormatString.expand(escaped)
		#expect(expanded == original)
	}
}
