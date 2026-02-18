import Testing
import TMCore
@testable import TMEditor

// MARK: - Auto-Pairing Tests

@Suite("Auto-Pairing (insertWithPairing)")
struct AutoPairingTests {
	/// Creates an editor with the given text, cursor at the specified offset.
	private func makeEditor(text: String, caret: Int) -> Editor {
		let editor = Editor(text: text)
		let pos = editor.buffer.convert(offset: caret)
		editor.selections = SelectionState(caret: pos)
		return editor
	}

	/// Creates an editor with a selection range.
	private func makeEditor(text: String, from: Int, to: Int) -> Editor {
		let editor = Editor(text: text)
		let anchor = editor.buffer.convert(offset: from)
		let head = editor.buffer.convert(offset: to)
		editor.selections = SelectionState([TextRange(anchor: anchor, head: head)])
		return editor
	}

	private let defaultPairs: [Editor.TypingPair] = Editor.defaultSmartTypingPairs

	// MARK: - Basic Pairing

	@Test("Typing opener inserts both opener and closer")
	func basicPairing() throws {
		let editor = makeEditor(text: "hello", caret: 5)
		editor.insertWithPairing("(", pairs: defaultPairs)
		#expect(editor.text == "hello()")
		// Cursor should be between the pair
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 6) // between ( and )
	}

	@Test("Typing opener with curly brace")
	func curlyBracePairing() throws {
		let editor = makeEditor(text: "", caret: 0)
		editor.insertWithPairing("{", pairs: defaultPairs)
		#expect(editor.text == "{}")
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 1)
	}

	@Test("Typing opener with square bracket")
	func squareBracketPairing() throws {
		let editor = makeEditor(text: "x", caret: 1)
		editor.insertWithPairing("[", pairs: defaultPairs)
		#expect(editor.text == "x[]")
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 2)
	}

	// MARK: - Skip Over Closer

	@Test("Typing closer at tracked position skips over it")
	func skipOverCloser() throws {
		let editor = makeEditor(text: "hello", caret: 5)
		editor.insertWithPairing("(", pairs: defaultPairs)
		#expect(editor.text == "hello()")
		// Now type ')' — should skip over the tracked closer
		editor.insertWithPairing(")", pairs: defaultPairs)
		#expect(editor.text == "hello()")
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 7)
	}

	// MARK: - Surround Selection

	@Test("Typing opener with selection surrounds it")
	func surroundSelection() throws {
		let editor = makeEditor(text: "hello world", from: 6, to: 11)
		editor.insertWithPairing("(", pairs: defaultPairs)
		#expect(editor.text == "hello (world)")
		// Selection should cover the inner text "world"
		let sel = try #require(editor.selections.primary)
		#expect(!sel.isEmpty)
		let selectedText = editor.buffer.substring(from: sel.start.offset, to: sel.end.offset)
		#expect(selectedText == "world")
	}

	@Test("Surround with quotes")
	func surroundWithQuotes() {
		let editor = makeEditor(text: "hello world", from: 0, to: 5)
		editor.insertWithPairing("\"", pairs: defaultPairs)
		#expect(editor.text == "\"hello\" world")
	}

	// MARK: - Next Char Is Word Char

	@Test("No pairing when next char is word character")
	func noParingBeforeWordChar() throws {
		let editor = makeEditor(text: "hello", caret: 0)
		editor.insertWithPairing("(", pairs: defaultPairs)
		// Next char 'h' is a word char → plain insert
		#expect(editor.text == "(hello")
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 1)
	}

	// MARK: - Same-Char Pairs (Quotes)

	@Test("Quote auto-pairs when count is even")
	func quoteAutoCloses() throws {
		let editor = makeEditor(text: "x = ", caret: 4)
		editor.insertWithPairing("\"", pairs: defaultPairs)
		#expect(editor.text == "x = \"\"")
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 5) // between quotes
	}

	@Test("Quote does not auto-pair when count is odd (closing)")
	func quoteClosingNoAutoPair() throws {
		// Start with one quote already on the line
		let editor = makeEditor(text: "x = \"hello", caret: 10)
		editor.insertWithPairing("\"", pairs: defaultPairs)
		// Odd count of quotes → just insert the single quote
		#expect(editor.text == "x = \"hello\"")
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 11)
	}

	// MARK: - No Matching Pair

	@Test("Non-pair character inserts normally")
	func nonPairCharInserts() {
		let editor = makeEditor(text: "hello", caret: 5)
		editor.insertWithPairing("x", pairs: defaultPairs)
		#expect(editor.text == "hellox")
	}

	// MARK: - Empty Pairs

	@Test("No pairs provided inserts normally")
	func emptyPairsInserts() {
		let editor = makeEditor(text: "hello", caret: 5)
		editor.insertWithPairing("(", pairs: [])
		#expect(editor.text == "hello(")
	}

	// MARK: - Pair Tracker Integration

	@Test("Pair tracker registers pair after insert")
	func pairTrackerRegistersAfterInsert() {
		let editor = makeEditor(text: "", caret: 0)
		editor.insertWithPairing("(", pairs: defaultPairs)
		#expect(!editor.pairTracker.isEmpty)
		#expect(editor.pairTracker.count == 1)
	}

	@Test("Pair tracker clears after skip-over")
	func pairTrackerClearsAfterSkipOver() {
		let editor = makeEditor(text: "", caret: 0)
		editor.insertWithPairing("(", pairs: defaultPairs)
		#expect(editor.pairTracker.count == 1)
		editor.insertWithPairing(")", pairs: defaultPairs)
		// After skip-over, the pair is removed from tracker
		#expect(editor.pairTracker.isEmpty)
	}

	// MARK: - Custom Pairs

	@Test("Custom pairs work correctly")
	func customPairs() throws {
		let customPairs = [Editor.TypingPair("<", ">")]
		let editor = makeEditor(text: "", caret: 0)
		editor.insertWithPairing("<", pairs: customPairs)
		#expect(editor.text == "<>")
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 1)
	}

	// MARK: - Edge Cases

	@Test("Insert at beginning of empty buffer")
	func insertAtBeginningOfEmpty() {
		let editor = makeEditor(text: "", caret: 0)
		editor.insertWithPairing("{", pairs: defaultPairs)
		#expect(editor.text == "{}")
	}

	@Test("Multiple consecutive pair insertions")
	func multiplePairInsertions() throws {
		let editor = makeEditor(text: "", caret: 0)
		editor.insertWithPairing("(", pairs: defaultPairs)
		#expect(editor.text == "()")
		editor.insertWithPairing("[", pairs: defaultPairs)
		#expect(editor.text == "([])")
		let caretOffset = try #require(editor.selections.primary?.head.offset)
		#expect(caretOffset == 2)
	}
}
