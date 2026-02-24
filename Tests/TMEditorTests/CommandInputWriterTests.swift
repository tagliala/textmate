import Testing
import TMCore
@testable import TMEditor

// MARK: - CommandInputWriter Tests

@Suite("CommandInputWriter")
struct CommandInputWriterTests {
	// MARK: - Helpers

	private func makeBuffer(_ text: String) -> TextBuffer {
		TextBuffer(text)
	}

	private func caretAt(_ offset: Int, in buffer: TextBuffer) -> SelectionState {
		SelectionState(caret: buffer.convert(offset: offset))
	}

	private func selectionRange(
		from: Int, to: Int, in buffer: TextBuffer,
	) -> SelectionState {
		SelectionState([
			TextRange(
				anchor: buffer.convert(offset: from),
				head: buffer.convert(offset: to),
			),
		])
	}

	// MARK: - Entire Document

	@Test("Extract entire document returns full text")
	func entireDocument() {
		let buffer = makeBuffer("Hello, World!")
		let sel = caretAt(0, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .entireDocument,
			fallback: .nothing,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "Hello, World!")
		#expect(result.inputWasSelection == false)
		#expect(result.inputRanges.count == 1)
	}

	@Test("Extract entire document on empty buffer")
	func entireDocumentEmpty() {
		let buffer = makeBuffer("")
		let sel = SelectionState(caret: .zero)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .entireDocument,
			fallback: .nothing,
			format: .text,
		)
		#expect(result.data.isEmpty)
	}

	// MARK: - Selection

	@Test("Extract selection returns selected text")
	func selection() {
		let buffer = makeBuffer("Hello, World!")
		let sel = selectionRange(from: 7, to: 12, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .selection,
			fallback: .nothing,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "World")
		#expect(result.inputWasSelection == true)
	}

	@Test("Empty selection falls back to requested fallback unit")
	func selectionFallbackToWord() {
		let buffer = makeBuffer("Hello World")
		// Caret inside "World" at offset 6
		let sel = caretAt(6, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .selection,
			fallback: .word,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "World")
		#expect(result.inputWasSelection == false)
	}

	// MARK: - Word

	@Test("Extract word at caret position")
	func wordAtCaret() {
		let buffer = makeBuffer("foo bar baz")
		// Caret inside "bar" at offset 5
		let sel = caretAt(5, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .word,
			fallback: .nothing,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "bar")
	}

	@Test("Extract word with underscore")
	func wordWithUnderscore() {
		let buffer = makeBuffer("my_variable = 42")
		let sel = caretAt(5, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .word,
			fallback: .nothing,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "my_variable")
	}

	// MARK: - Line

	@Test("Extract current line")
	func lineAtCaret() {
		let buffer = makeBuffer("line one\nline two\nline three")
		// Caret inside "line two" at offset 12
		let sel = caretAt(12, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .line,
			fallback: .nothing,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "line two")
	}

	@Test("Extract first line")
	func firstLine() {
		let buffer = makeBuffer("first\nsecond")
		let sel = caretAt(2, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .line,
			fallback: .nothing,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "first")
	}

	// MARK: - Character

	@Test("Extract single character to the right")
	func characterRight() {
		let buffer = makeBuffer("abc")
		let sel = caretAt(1, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .character,
			fallback: .nothing,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "b")
	}

	@Test("Character at end of buffer returns empty")
	func characterAtEnd() {
		let buffer = makeBuffer("ab")
		let sel = caretAt(2, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .character,
			fallback: .nothing,
			format: .text,
		)
		// At end of buffer, extendRight returns nil → falls back to range
		#expect(result.data.isEmpty)
	}

	// MARK: - Nothing

	@Test("Extract nothing returns empty data")
	func nothingInput() {
		let buffer = makeBuffer("Hello")
		let sel = caretAt(0, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .nothing,
			fallback: .nothing,
			format: .text,
		)
		#expect(result.data.isEmpty)
	}

	// MARK: - XML Format

	@Test("XML format escapes entities")
	func xmlFormat() throws {
		let buffer = makeBuffer("a < b & c > d \"e\"")
		let sel = selectionRange(from: 0, to: buffer.size, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .selection,
			fallback: .nothing,
			format: .xml,
		)
		let output = try #require(String(data: result.data, encoding: .utf8))
		#expect(output.contains("&lt;"))
		#expect(output.contains("&amp;"))
		#expect(output.contains("&gt;"))
		#expect(output.contains("&quot;"))
	}

	// MARK: - Input Variables

	@Test("Single non-empty range sets TM_INPUT_START_LINE")
	func inputStartLine() {
		let buffer = makeBuffer("line one\nline two\nline three")
		// Select "line two" (offset 9..17)
		let sel = selectionRange(from: 9, to: 17, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .selection,
			fallback: .nothing,
			format: .text,
		)
		// Line 2 (1-indexed)
		#expect(result.inputVariables["TM_INPUT_START_LINE"] == "2")
		#expect(result.inputVariables["TM_INPUT_START_LINE_INDEX"] == "0")
		#expect(result.inputVariables["TM_INPUT_START_COLUMN"] == "1")
	}

	@Test("Entire document extraction does not set input variables")
	func entireDocumentNoVars() {
		let buffer = makeBuffer("some text")
		let sel = caretAt(0, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .entireDocument,
			fallback: .nothing,
			format: .text,
		)
		#expect(result.inputVariables.isEmpty)
	}

	// MARK: - Column Counting

	@Test("Column counting accounts for tabs")
	func tabColumnCounting() {
		// Tab at position 0, then "abc" starting at column 4 (tabSize=4)
		let buffer = makeBuffer("\tabc")
		// Select "abc" (starts at offset 1, which is column 5 with tabSize=4)
		let sel = selectionRange(from: 1, to: 4, in: buffer)
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .selection,
			fallback: .nothing,
			format: .text,
		)
		// Column should be tab expansion (4) + 1 (1-indexed) = 5
		#expect(result.inputVariables["TM_INPUT_START_COLUMN"] == "5")
	}

	// MARK: - Multi-Cursor

	@Test("Multiple selections are concatenated with newlines")
	func multipleSelections() {
		let buffer = makeBuffer("aaa bbb ccc")
		let sel = SelectionState([
			TextRange(
				anchor: buffer.convert(offset: 0),
				head: buffer.convert(offset: 3),
			),
			TextRange(
				anchor: buffer.convert(offset: 8),
				head: buffer.convert(offset: 11),
			),
		])
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .selection,
			fallback: .nothing,
			format: .text,
		)
		#expect(String(data: result.data, encoding: .utf8) == "aaa\nccc")
	}

	@Test("Multi-cursor selection fallback does not use entireDocument")
	func multiCursorFallback() {
		let buffer = makeBuffer("word1 word2")
		// Two carets: one in word1, one in word2
		let sel = SelectionState([
			TextRange(caret: buffer.convert(offset: 2)),
			TextRange(caret: buffer.convert(offset: 8)),
		])
		let result = CommandInputWriter.extract(
			from: buffer,
			selections: sel,
			tabSize: 4,
			unit: .selection,
			fallback: .entireDocument,
			format: .text,
		)
		// With multiple cursors and fallback == .entireDocument, C++ logic
		// keeps unit as .selection → empty ranges
		#expect(result.inputWasSelection == true)
	}

	// MARK: - InputUnit and InputFormat Enums

	@Test("InputUnit has expected raw values")
	func inputUnitRawValues() {
		#expect(InputUnit.selection.rawValue == "selection")
		#expect(InputUnit.entireDocument.rawValue == "entireDocument")
		#expect(InputUnit.word.rawValue == "word")
		#expect(InputUnit.line.rawValue == "line")
		#expect(InputUnit.scope.rawValue == "scope")
		#expect(InputUnit.character.rawValue == "character")
		#expect(InputUnit.nothing.rawValue == "nothing")
	}

	@Test("InputFormat has expected raw values")
	func inputFormatRawValues() {
		#expect(InputFormat.text.rawValue == "text")
		#expect(InputFormat.xml.rawValue == "xml")
	}
}
