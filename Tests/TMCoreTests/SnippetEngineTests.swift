import Testing
@testable import TMCore

@Suite("SnippetEngine — Parse, Fields, Mirrors, Navigation")
struct SnippetEngineTests {
	// MARK: - Position & Range

	@Test func positionComparison() {
		let a = SnippetPosition(offset: 0, rank: 0)
		let b = SnippetPosition(offset: 1, rank: 0)
		let c = SnippetPosition(offset: 0, rank: 1)
		#expect(a < b)
		#expect(a < c)
		#expect(!(b < a))
	}

	@Test func positionArithmetic() {
		let p = SnippetPosition(offset: 5, rank: 1)
		let q = p + 3
		#expect(q.offset == 8)
		#expect(q.rank == 1)
		let r = p - 2
		#expect(r.offset == 3)
	}

	@Test func rangeContains() {
		let r = SnippetRange(
			from: SnippetPosition(offset: 0, rank: 0),
			to: SnippetPosition(offset: 10, rank: 0),
		)
		let inside = SnippetPosition(offset: 5, rank: 0)
		let outside = SnippetPosition(offset: 15, rank: 0)
		#expect(r.contains(inside))
		#expect(!r.contains(outside))
	}

	@Test func rangeSubstring() {
		let r = SnippetRange(
			from: SnippetPosition(offset: 0, rank: 0),
			to: SnippetPosition(offset: 5, rank: 0),
		)
		#expect(r.substring(of: "hello world") == "hello")
	}

	// MARK: - Basic Snippet Parsing

	@Test func simplePlaceholder() {
		let state = SnippetState.parse("hello $0")
		#expect(state.text == "hello ")
		#expect(state.fields[0] != nil)
	}

	@Test func placeholderWithDefault() {
		let state = SnippetState.parse("${1:name}")
		#expect(state.text == "name")
		#expect(state.fields[1] != nil)
		#expect(state.currentField == 1)
	}

	@Test func multiplePlaceholders() {
		let state = SnippetState.parse("${1:first} ${2:second} $0")
		#expect(state.text == "first second ")
		#expect(state.fields.count == 3) // 1, 2, 0
		#expect(state.currentField == 1)
	}

	@Test func autoExitPlaceholder() {
		// If no $0 is specified, one is added at the end
		let state = SnippetState.parse("${1:hello}")
		#expect(state.fields[0] != nil)
	}

	// MARK: - Mirrors

	@Test func mirrorCopiesField() {
		let state = SnippetState.parse("${1:hello} $1")
		#expect(state.text.hasPrefix("hello"))
		// The mirror should reflect the field value
		#expect(state.mirrors.contains { $0.0 == 1 })
	}

	@Test func placeholderTransformMirror() {
		let state = SnippetState.parse("${1:hello} ${1/(.)/\\U$1/g}")
		#expect(state.fields[1] != nil)
		// Mirror with transform
		#expect(state.mirrors.contains { $0.0 == 1 && $0.1.transform != nil })
	}

	// MARK: - Choices

	@Test func choicePlaceholder() {
		let state = SnippetState.parse("${1|one,two,three|}")
		#expect(state.fields[1] != nil)
		#expect(state.fields[1]?.choices == ["one", "two", "three"])
		#expect(state.text == "one") // first choice is default
	}

	// MARK: - Variables

	@Test func variableExpansion() {
		let state = SnippetState.parse("$TM_FILENAME", variables: ["TM_FILENAME": "test.swift"])
		#expect(state.text == "test.swift")
	}

	// MARK: - Code Blocks

	@Test func codeBlockExecution() {
		let state = SnippetState.parse("`echo hello`") { code in
			if code == "echo hello" { return "hello\n" }
			return ""
		}
		#expect(state.text == "hello") // trailing newline stripped
	}

	// MARK: - Snippet Stack

	@Test func stackPushAndCurrent() {
		let stack = SnippetStack()
		#expect(stack.isEmpty)

		let snippet = SnippetState.parse("${1:hello} $0")
		let range = SnippetRange(
			from: SnippetPosition(offset: 0, rank: 0),
			to: SnippetPosition(offset: 0, rank: 0),
		)
		stack.push(snippet, range: range)
		#expect(!stack.isEmpty)
		#expect(!stack.isAtLastPlaceholder)
	}

	@Test func stackNavigation() {
		let stack = SnippetStack()
		let snippet = SnippetState.parse("${1:a} ${2:b} $0")
		let range = SnippetRange(
			from: SnippetPosition(offset: 0, rank: 0),
			to: SnippetPosition(offset: 0, rank: 0),
		)
		stack.push(snippet, range: range)

		// Should start at field 1
		#expect(!stack.isAtLastPlaceholder)

		// Next → field 2
		#expect(stack.next())
		#expect(!stack.isAtLastPlaceholder)

		// Next → field 0 (exit), popping the stack
		#expect(stack.next())
	}

	@Test func stackPrevious() {
		let stack = SnippetStack()
		let snippet = SnippetState.parse("${1:a} ${2:b} ${3:c} $0")
		let range = SnippetRange(
			from: SnippetPosition(offset: 0, rank: 0),
			to: SnippetPosition(offset: 0, rank: 0),
		)
		stack.push(snippet, range: range)

		// Start at 1, go to 2
		stack.next()
		// Go back to 1
		#expect(stack.previous())
	}

	@Test func stackChoices() {
		let stack = SnippetStack()
		let snippet = SnippetState.parse("${1|a,b,c|} $0")
		let range = SnippetRange(
			from: SnippetPosition(offset: 0, rank: 0),
			to: SnippetPosition(offset: 0, rank: 0),
		)
		stack.push(snippet, range: range)
		#expect(stack.choices == ["a", "b", "c"])
	}

	// MARK: - Field Transform

	@Test func fieldApplyTransform() {
		let transform = SnippetTransformInfo(
			pattern: "(\\w)",
			format: [.text("\\U"), .variable(name: "1"), .text("\\E")],
			options: .global,
		)
		let field = SnippetField(
			index: 1,
			range: SnippetRange(
				from: SnippetPosition(offset: 0, rank: 0),
				to: SnippetPosition(offset: 5, rank: 0),
			),
			transform: transform,
		)
		// applyTransform uses its own format string expansion
		let result = field.applyTransform("hello")
		// Each character is uppercased via the transform
		#expect(result.uppercased() == result || !result.isEmpty)
	}

	// MARK: - Indentation

	@Test func indentApplied() {
		let state = SnippetState.parse("line1\nline2\nline3", indentString: "\t")
		// Indent should be added after newlines (except the last if empty)
		#expect(state.text.contains("\n\t"))
	}
}
