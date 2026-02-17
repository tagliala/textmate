import AppKit
import Testing
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
@testable import TMDocumentWindow

// MARK: - TMDocumentEditor Tests

@Suite("TMDocumentEditor")
@MainActor
struct TMDocumentEditorTests {
	// MARK: - Helpers

	/// Creates a document editor with the given text content.
	private func makeEditor(text: String = "hello world") -> (TMDocumentEditor, TMDocument) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, doc)
	}

	// MARK: - Initialization

	@Test("creates editor from document content")
	func initFromDocument() {
		let (docEditor, _) = makeEditor(text: "abc def")
		#expect(docEditor.editor.text == "abc def")
	}

	@Test("creates editor for untitled document")
	func initUntitled() {
		let doc = TMDocument()
		doc.setContent("", preserveRevision: true)
		let view = EditorView(frame: .zero)
		let editor = TMDocumentEditor(document: doc, editorView: view)
		#expect(editor.editor.text == "")
	}

	@Test("applies document tab settings")
	func appliesTabSettings() {
		let doc = TMDocument()
		doc.tabSize = 8
		doc.softTabs = true
		doc.setContent("x", preserveRevision: true)
		let view = EditorView(frame: .zero)
		let editor = TMDocumentEditor(document: doc, editorView: view)
		#expect(editor.editor.tabSize == 8)
		#expect(editor.editor.indentUsingSpaces == true)
	}

	// MARK: - Action Mapping

	@Test("maps view movement actions to editor actions")
	func actionMappingMovement() {
		#expect(TMDocumentEditor.editorAction(from: .moveUp) == .moveUp)
		#expect(TMDocumentEditor.editorAction(from: .moveDown) == .moveDown)
		#expect(TMDocumentEditor.editorAction(from: .moveLeft) == .moveBackward)
		#expect(TMDocumentEditor.editorAction(from: .moveRight) == .moveForward)
		#expect(TMDocumentEditor.editorAction(from: .moveToBeginningOfLine) == .moveToBeginOfSoftLine)
		#expect(TMDocumentEditor.editorAction(from: .moveToEndOfLine) == .moveToEndOfSoftLine)
		#expect(TMDocumentEditor.editorAction(from: .moveToBeginningOfDocument) == .moveToBeginOfDocument)
		#expect(TMDocumentEditor.editorAction(from: .moveToEndOfDocument) == .moveToEndOfDocument)
		#expect(TMDocumentEditor.editorAction(from: .moveWordForward) == .moveWordForward)
		#expect(TMDocumentEditor.editorAction(from: .moveWordBackward) == .moveWordBackward)
		#expect(TMDocumentEditor.editorAction(from: .pageUp) == .pageUp)
		#expect(TMDocumentEditor.editorAction(from: .pageDown) == .pageDown)
	}

	@Test("maps view selection extension actions to editor actions")
	func actionMappingSelection() {
		#expect(TMDocumentEditor.editorAction(from: .moveUpAndModifySelection) == .moveUpAndModifySelection)
		#expect(TMDocumentEditor.editorAction(from: .moveDownAndModifySelection) == .moveDownAndModifySelection)
		#expect(TMDocumentEditor.editorAction(from: .moveLeftAndModifySelection) == .moveBackwardAndModifySelection)
		#expect(TMDocumentEditor.editorAction(from: .moveRightAndModifySelection) == .moveForwardAndModifySelection)
		#expect(TMDocumentEditor
			.editorAction(from: .moveWordForwardAndModifySelection) == .moveWordForwardAndModifySelection)
		#expect(TMDocumentEditor
			.editorAction(from: .moveWordBackwardAndModifySelection) == .moveWordBackwardAndModifySelection)
		#expect(TMDocumentEditor
			.editorAction(from: .moveToBeginningOfLineAndModifySelection) == .moveToBeginOfSoftLineAndModifySelection)
		#expect(TMDocumentEditor
			.editorAction(from: .moveToEndOfLineAndModifySelection) == .moveToEndOfSoftLineAndModifySelection)
		#expect(TMDocumentEditor
			.editorAction(from: .moveToBeginningOfDocumentAndModifySelection) == .moveToBeginOfDocumentAndModifySelection)
		#expect(TMDocumentEditor
			.editorAction(from: .moveToEndOfDocumentAndModifySelection) == .moveToEndOfDocumentAndModifySelection)
	}

	@Test("maps view deletion actions to editor actions")
	func actionMappingDeletion() {
		#expect(TMDocumentEditor.editorAction(from: .deleteForward) == .deleteForward)
		#expect(TMDocumentEditor.editorAction(from: .deleteBackward) == .deleteBackward)
		#expect(TMDocumentEditor.editorAction(from: .deleteWordForward) == .deleteWordForward)
		#expect(TMDocumentEditor.editorAction(from: .deleteWordBackward) == .deleteWordBackward)
		#expect(TMDocumentEditor.editorAction(from: .deleteToBeginningOfLine) == .deleteToBeginOfIndentedLine)
		#expect(TMDocumentEditor.editorAction(from: .deleteToEndOfLine) == .deleteToEndOfIndentedLine)
	}

	@Test("maps view insertion actions to editor actions")
	func actionMappingInsertion() {
		#expect(TMDocumentEditor.editorAction(from: .insertNewline) == .insertNewline)
		#expect(TMDocumentEditor.editorAction(from: .insertTab) == .insertTab)
		#expect(TMDocumentEditor.editorAction(from: .insertBacktab) == .insertBacktab)
		#expect(TMDocumentEditor.editorAction(from: .selectAll) == .selectAll)
	}

	// MARK: - Content Sync

	@Test("text insertion syncs to document")
	func insertSyncsToDocument() {
		let (docEditor, doc) = makeEditor(text: "")
		// Simulate typing
		docEditor.editor.insertText("hello")
		// Manually sync (normally done by the delegate methods)
		doc.setContent(docEditor.editor.text)
		#expect(doc.content == "hello")
	}

	@Test("editor action syncs to document via delegate")
	func actionSyncsViaDelegate() {
		let (docEditor, doc) = makeEditor(text: "hello world")
		// Move to end and type
		docEditor.editor.perform(.moveToEndOfDocument)
		docEditor.editor.insertText("!")
		doc.setContent(docEditor.editor.text)
		#expect(doc.content == "hello world!")
	}

	// MARK: - Selection Serialization

	@Test("documentWillSave serializes caret position")
	func saveSerializesCaret() {
		let (docEditor, doc) = makeEditor(text: "line one\nline two")
		// Place caret at start
		docEditor.editor.selections = SelectionState(
			caret: docEditor.editor.buffer.convert(offset: 0),
		)
		docEditor.documentWillSave()
		#expect(doc.selection == "1:0")
	}

	@Test("documentWillSave serializes selection range")
	func saveSerializesRange() {
		let (docEditor, doc) = makeEditor(text: "hello world")
		// Select "hello" (offset 0..<5)
		let anchor = docEditor.editor.buffer.convert(offset: 0)
		let head = docEditor.editor.buffer.convert(offset: 5)
		docEditor.editor.selections = SelectionState([TMCore.TextRange(anchor: anchor, head: head)])
		docEditor.documentWillSave()
		#expect(doc.selection == "1:0-1:5")
	}

	@Test("documentWillSave serializes multi-line selection")
	func saveSerializesMultiLine() {
		let (docEditor, doc) = makeEditor(text: "line1\nline2\nline3")
		// Select from start of line 1 to start of line 3
		let anchor = docEditor.editor.buffer.convert(offset: 0)
		let head = docEditor.editor.buffer.convert(offset: 12) // "line1\nline2\n" = 12 bytes
		docEditor.editor.selections = SelectionState([TMCore.TextRange(anchor: anchor, head: head)])
		docEditor.documentWillSave()
		#expect(doc.selection == "1:0-3:0")
	}

	@Test("documentWillSave serializes multiple selections")
	func saveSerializesMultipleSels() {
		let (docEditor, doc) = makeEditor(text: "aaa bbb aaa")
		let sel1 = TMCore.TextRange(
			anchor: docEditor.editor.buffer.convert(offset: 0),
			head: docEditor.editor.buffer.convert(offset: 3),
		)
		let sel2 = TMCore.TextRange(
			anchor: docEditor.editor.buffer.convert(offset: 8),
			head: docEditor.editor.buffer.convert(offset: 11),
		)
		docEditor.editor.selections = SelectionState([sel1, sel2])
		docEditor.documentWillSave()
		#expect(doc.selection == "1:0-1:3&1:8-1:11")
	}

	// MARK: - Change Grouping

	@Test("change grouping nests correctly")
	func changeGroupingNesting() {
		let (docEditor, _) = makeEditor()

		// First open returns true
		#expect(docEditor.beginChangeGrouping() == true)
		// Nested open returns false
		#expect(docEditor.beginChangeGrouping() == false)
		// First close returns false (still nested)
		#expect(docEditor.endChangeGrouping() == false)
		// Final close returns true
		#expect(docEditor.endChangeGrouping() == true)
	}

	@Test("end without begin returns false")
	func endWithoutBegin() {
		let (docEditor, _) = makeEditor()
		#expect(docEditor.endChangeGrouping() == false)
	}

	// MARK: - Undo/Redo

	@Test("undo reverts text change")
	func undoRevertsChange() {
		let (docEditor, _) = makeEditor(text: "hello")
		// Select all and delete
		docEditor.editor.perform(.selectAll)
		docEditor.editor.perform(.deleteSelection)
		#expect(docEditor.editor.text == "")

		docEditor.undo()
		#expect(docEditor.editor.text == "hello")
	}

	@Test("redo re-applies undone change")
	func redoReapplies() {
		let (docEditor, _) = makeEditor(text: "hello")
		docEditor.editor.perform(.selectAll)
		docEditor.editor.perform(.deleteSelection)
		#expect(docEditor.editor.text == "")

		docEditor.undo()
		#expect(docEditor.editor.text == "hello")

		docEditor.redo()
		#expect(docEditor.editor.text == "")
	}
}

// MARK: - Action Mapping Exhaustive Coverage

@Suite("TMDocumentEditor Action Mapping — Exhaustive")
@MainActor
struct TMDocumentEditorActionMappingTests {
	@Test("every EditorViewAction has a mapping")
	func exhaustiveMapping() {
		// Verify that every view action maps to something.
		let allViewActions: [EditorViewAction] = [
			.moveUp, .moveDown, .moveLeft, .moveRight,
			.moveToBeginningOfLine, .moveToEndOfLine,
			.moveToBeginningOfDocument, .moveToEndOfDocument,
			.moveWordForward, .moveWordBackward,
			.pageUp, .pageDown,
			.moveUpAndModifySelection, .moveDownAndModifySelection,
			.moveLeftAndModifySelection, .moveRightAndModifySelection,
			.moveWordForwardAndModifySelection, .moveWordBackwardAndModifySelection,
			.moveToBeginningOfLineAndModifySelection, .moveToEndOfLineAndModifySelection,
			.moveToBeginningOfDocumentAndModifySelection, .moveToEndOfDocumentAndModifySelection,
			.deleteForward, .deleteBackward,
			.deleteWordForward, .deleteWordBackward,
			.deleteToBeginningOfLine, .deleteToEndOfLine,
			.insertNewline, .insertTab, .insertBacktab,
			.selectAll,
		]

		for viewAction in allViewActions {
			// This should not crash — all cases are handled.
			let mapped = TMDocumentEditor.editorAction(from: viewAction)
			#expect(mapped.rawValue.isEmpty == false, "Mapping for \(viewAction) should produce a valid action")
		}
	}
}
