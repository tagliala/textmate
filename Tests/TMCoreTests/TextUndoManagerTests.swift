import Testing
@testable import TMCore

@Suite("TextUndoManager — Undo/Redo with Coalescing")
struct TextUndoManagerTests {
	// MARK: - Helpers

	/// Creates a buffer + undo manager pair for testing.
	private func makeBufferAndUndo(_ content: String = "") -> (TextBuffer, TextUndoManager) {
		let buf = TextBuffer(content)
		let undo = TextUndoManager(buffer: buf)
		return (buf, undo)
	}

	/// Performs a grouped edit.
	private func groupedReplace(
		_ buf: TextBuffer, _ undo: TextUndoManager,
		from: Int, to: Int, with text: String,
		selection: SelectionState? = nil,
	) {
		let sel = selection ?? SelectionState(caret: TextPosition.zero)
		undo.beginUndoGroup(selections: sel)
		buf.replace(from: from, to: to, with: text)
		undo.endUndoGroup(selections: sel)
	}

	// MARK: - Basic Undo/Redo

	@Test func initialState() {
		let (_, undo) = makeBufferAndUndo("abc")
		#expect(!undo.canUndo)
		#expect(!undo.canRedo)
		#expect(!undo.inUndoGroup)
	}

	@Test func undoSingleInsert() {
		let (buf, undo) = makeBufferAndUndo("abc")
		groupedReplace(buf, undo, from: 3, to: 3, with: "def")
		#expect(buf.string == "abcdef")
		#expect(undo.canUndo)

		undo.undo()
		#expect(buf.string == "abc")
		#expect(!undo.canUndo)
		#expect(undo.canRedo)
	}

	@Test func redoAfterUndo() {
		let (buf, undo) = makeBufferAndUndo("abc")
		groupedReplace(buf, undo, from: 3, to: 3, with: "def")
		undo.undo()
		#expect(buf.string == "abc")

		undo.redo()
		#expect(buf.string == "abcdef")
		#expect(undo.canUndo)
		#expect(!undo.canRedo)
	}

	@Test func undoSingleErase() {
		let (buf, undo) = makeBufferAndUndo("abcdef")
		groupedReplace(buf, undo, from: 3, to: 6, with: "")
		#expect(buf.string == "abc")

		undo.undo()
		#expect(buf.string == "abcdef")
	}

	@Test func undoReplace() {
		let (buf, undo) = makeBufferAndUndo("Hello, world!")
		groupedReplace(buf, undo, from: 7, to: 12, with: "Swift")
		#expect(buf.string == "Hello, Swift!")

		undo.undo()
		#expect(buf.string == "Hello, world!")
	}

	// MARK: - Multiple Undo/Redo Steps

	@Test func multipleUndoSteps() {
		let (buf, undo) = makeBufferAndUndo("")
		groupedReplace(buf, undo, from: 0, to: 0, with: "A")
		groupedReplace(buf, undo, from: 1, to: 1, with: "B")
		groupedReplace(buf, undo, from: 2, to: 2, with: "C")
		#expect(buf.string == "ABC")

		undo.undo()
		#expect(buf.string == "AB")
		undo.undo()
		#expect(buf.string == "A")
		undo.undo()
		#expect(buf.string == "")
		#expect(!undo.canUndo)
	}

	@Test func multipleRedoSteps() {
		let (buf, undo) = makeBufferAndUndo("")
		groupedReplace(buf, undo, from: 0, to: 0, with: "A")
		groupedReplace(buf, undo, from: 1, to: 1, with: "B")
		groupedReplace(buf, undo, from: 2, to: 2, with: "C")

		undo.undo()
		undo.undo()
		undo.undo()
		#expect(buf.string == "")

		undo.redo()
		#expect(buf.string == "A")
		undo.redo()
		#expect(buf.string == "AB")
		undo.redo()
		#expect(buf.string == "ABC")
	}

	// MARK: - Redo History Discarded on New Edit

	@Test func newEditDiscardsRedoHistory() {
		let (buf, undo) = makeBufferAndUndo("")
		groupedReplace(buf, undo, from: 0, to: 0, with: "A")
		groupedReplace(buf, undo, from: 1, to: 1, with: "B")

		undo.undo()
		#expect(buf.string == "A")
		#expect(undo.canRedo)

		// New edit should discard redo history.
		groupedReplace(buf, undo, from: 1, to: 1, with: "X")
		#expect(buf.string == "AX")
		#expect(!undo.canRedo)
	}

	// MARK: - Undo Group Nesting

	@Test func nestedUndoGroups() {
		let (buf, undo) = makeBufferAndUndo("abc")
		let sel = SelectionState(caret: TextPosition.zero)

		undo.beginUndoGroup(selections: sel)
		undo.beginUndoGroup(selections: sel) // nested
		buf.insert(at: 3, string: "d")
		undo.endUndoGroup(selections: sel)
		buf.insert(at: 4, string: "e")
		undo.endUndoGroup(selections: sel)

		#expect(buf.string == "abcde")

		// Both inserts were in the same outer group — single undo undoes both.
		undo.undo()
		#expect(buf.string == "abc")
	}

	// MARK: - Selection State Preservation

	@Test func selectionStatePreserved() {
		let (buf, undo) = makeBufferAndUndo("abc")
		let beforeSel = SelectionState(caret: TextPosition(line: 0, column: 3, offset: 3))
		let afterSel = SelectionState(caret: TextPosition(line: 0, column: 6, offset: 6))

		undo.beginUndoGroup(selections: beforeSel)
		buf.insert(at: 3, string: "def")
		undo.endUndoGroup(selections: afterSel)

		let restored = undo.undo()
		#expect(restored == beforeSel)

		let reapplied = undo.redo()
		#expect(reapplied == afterSel)
	}

	// MARK: - Edge Cases

	@Test func undoEmptyGroupIsNoop() {
		let (_, undo) = makeBufferAndUndo("abc")
		let sel = SelectionState(caret: TextPosition.zero)
		undo.beginUndoGroup(selections: sel)
		// No edits within group.
		undo.endUndoGroup(selections: sel)

		#expect(!undo.canUndo) // No records created.
	}

	@Test func multipleEditsInOneGroup() {
		let (buf, undo) = makeBufferAndUndo("abc")
		let sel = SelectionState(caret: TextPosition.zero)

		undo.beginUndoGroup(selections: sel)
		buf.replace(from: 0, to: 1, with: "X") // "Xbc"
		buf.replace(from: 1, to: 2, with: "Y") // "XYc"
		undo.endUndoGroup(selections: sel)

		#expect(buf.string == "XYc")

		// Both edits are in one undo group — single undo reverses both.
		undo.undo()
		#expect(buf.string == "abc")
	}

	// MARK: - Revision Tracking

	@Test func revisionUpdatesOnUndoRedo() {
		let (buf, undo) = makeBufferAndUndo("abc")
		let initialRev = buf.revision

		groupedReplace(buf, undo, from: 3, to: 3, with: "d")
		let afterInsertRev = buf.revision
		#expect(afterInsertRev > initialRev)

		undo.undo()
		#expect(buf.revision == initialRev)

		undo.redo()
		#expect(buf.revision == afterInsertRev)
	}
}
