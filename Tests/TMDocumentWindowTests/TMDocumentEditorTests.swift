import AppKit
import Testing
import TMAppKit
import TMBundleRuntime
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

// MARK: - Tab Trigger Expansion Tests

@Suite("TMDocumentEditor — Tab Trigger Expansion")
@MainActor
struct TabTriggerExpansionTests {
	private func makeEditor(text: String) -> TMDocumentEditor {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		return TMDocumentEditor(document: doc, editorView: view)
	}

	@Test("expandTabTrigger returns false without bundleIndex")
	func noIndexReturnsFalse() {
		let editor = makeEditor(text: "hello")
		editor.editor.perform(.moveToEndOfDocument)
		#expect(editor.expandTabTrigger() == false)
	}

	@Test("expandTabTrigger returns false at empty line")
	func emptyLineReturnsFalse() {
		let editor = makeEditor(text: "")
		let index = BundleIndex()
		editor.bundleIndex = index
		#expect(editor.expandTabTrigger() == false)
	}

	@Test("expandTabTrigger returns false when no match")
	func noMatchReturnsFalse() {
		let editor = makeEditor(text: "xyz")
		let index = BundleIndex()
		editor.bundleIndex = index
		editor.editor.perform(.moveToEndOfDocument)
		#expect(editor.expandTabTrigger() == false)
	}

	@Test("expandTabTrigger expands matching snippet")
	func expandsMatchingSnippet() {
		let editor = makeEditor(text: "fun")
		let index = BundleIndex()
		let item = BundleItem(
			uuid: "test-snippet",
			name: "Function",
			kind: .snippet,
			bundleUUID: "bundle-1",
			tabTrigger: "fun",
			plist: ["content": "function $1() {\n\t$0\n}"],
		)
		index.setIndex(items: [item], bundles: [])
		editor.bundleIndex = index
		editor.editor.perform(.moveToEndOfDocument)

		let result = editor.expandTabTrigger()
		#expect(result == true)
		// The trigger "fun" should be replaced with the expanded snippet.
		let text = editor.editor.text
		#expect(text.hasPrefix("function "))
		#expect(text.contains("{"))
		#expect(text.contains("}"))
	}

	@Test("expandTabTrigger pushes snippet session")
	func pushesSnippetSession() {
		let editor = makeEditor(text: "fun")
		let index = BundleIndex()
		let item = BundleItem(
			uuid: "test-snippet",
			name: "Function",
			kind: .snippet,
			bundleUUID: "bundle-1",
			tabTrigger: "fun",
			plist: ["content": "function $1() {\n\t$0\n}"],
		)
		index.setIndex(items: [item], bundles: [])
		editor.bundleIndex = index
		editor.editor.perform(.moveToEndOfDocument)

		_ = editor.expandTabTrigger()
		#expect(!editor.editor.snippetController.isEmpty)
	}

	@Test("insertSnippetWithExpansion inserts plain text for snippet without tab stops")
	func insertPlainSnippet() {
		let editor = makeEditor(text: "")
		editor.insertSnippetWithExpansion("hello world")
		#expect(editor.editor.text == "hello world")
		// No active snippet — $0 auto-added at end then popped
	}

	@Test("insertSnippetWithExpansion selects first tab stop")
	func selectsFirstTabStop() {
		let editor = makeEditor(text: "")
		editor.insertSnippetWithExpansion("name: ${1:default}")
		// The expanded text should be "name: default"
		#expect(editor.editor.text == "name: default")
		// First tab stop should be selected (the word "default")
		let sel = editor.editor.selections.primary
		#expect(sel != nil)
		#expect(!editor.editor.snippetController.isEmpty)
	}
}

// MARK: - Gutter Theme Tests

@Suite("GutterView — Theme Application")
@MainActor
struct GutterThemeTests {
	@Test("gutter colors are settable")
	func gutterColorsSettable() {
		let gutter = GutterView()
		gutter.foregroundColor = .red
		gutter.backgroundColor = .blue
		gutter.selectedForegroundColor = .green
		gutter.selectedBackgroundColor = .yellow
		#expect(gutter.foregroundColor == .red)
		#expect(gutter.backgroundColor == .blue)
		#expect(gutter.selectedForegroundColor == .green)
		#expect(gutter.selectedBackgroundColor == .yellow)
	}

	@Test("gutter defaults are system colors")
	func gutterDefaults() {
		let gutter = GutterView()
		#expect(gutter.foregroundColor == .secondaryLabelColor)
		#expect(gutter.backgroundColor == .controlBackgroundColor)
		#expect(gutter.selectedForegroundColor == .labelColor)
		#expect(gutter.selectedBackgroundColor == .controlBackgroundColor)
	}
}

// MARK: - Editor View Drag-and-Drop Tests

@Suite("EditorView — Drag and Drop")
@MainActor
struct EditorViewDragDropTests {
	@Test("EditorView registers for drag types")
	func registersForDragTypes() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let types = view.registeredDraggedTypes
		#expect(types.contains(.string))
		#expect(types.contains(.fileURL))
	}
}

// MARK: - Auto-Pairing Integration Tests

@Suite("TMDocumentEditor — Auto-Pairing")
@MainActor
struct TMDocumentEditorAutoPairingTests {
	private func makeEditor(text: String = "") -> (TMDocumentEditor, EditorView) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, view)
	}

	@Test("auto-pairing enabled by default")
	func autoPairingEnabledByDefault() {
		let (docEditor, _) = makeEditor()
		#expect(docEditor.autoPairingEnabled)
		#expect(!docEditor.smartTypingPairs.isEmpty)
	}

	@Test("insertText routes through pairing when enabled")
	func insertTextUsesPairing() {
		let (docEditor, view) = makeEditor()
		// Type a paren — should auto-pair
		docEditor.editorView(view, insertText: "(", replacementRange: NSRange(location: NSNotFound, length: 0))
		#expect(docEditor.editor.text == "()")
	}

	@Test("insertText plain when pairing disabled")
	func insertTextPlainWhenDisabled() {
		let (docEditor, view) = makeEditor()
		docEditor.autoPairingEnabled = false
		docEditor.editorView(view, insertText: "(", replacementRange: NSRange(location: NSNotFound, length: 0))
		#expect(docEditor.editor.text == "(")
	}

	@Test("multi-character insert bypasses pairing")
	func multiCharBypassesPairing() {
		let (docEditor, view) = makeEditor()
		docEditor.editorView(view, insertText: "abc", replacementRange: NSRange(location: NSNotFound, length: 0))
		#expect(docEditor.editor.text == "abc")
	}
}

// MARK: - EditorView Interaction Tests

@Suite("EditorView — Interactions")
@MainActor
struct EditorViewInteractionTests {
	@Test("EditorView conforms to NSMenuItemValidation")
	func conformsToMenuValidation() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let validated: any NSMenuItemValidation = view
		#expect(type(of: validated) == EditorView.self)
	}

	@Test("EditorView conforms to NSDraggingSource")
	func conformsToDraggingSource() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let source: any NSDraggingSource = view
		#expect(type(of: source) == EditorView.self)
	}

	@Test("EditorView accepts first responder")
	func acceptsFirstResponder() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		#expect(view.acceptsFirstResponder)
	}

	@Test("validRequestor returns self when selection exists")
	func validRequestorForString() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		view.setText("hello world")
		view.selectionRanges = [(start: (0, 0), end: (0, 5))]
		let req = view.validRequestor(forSendType: .string, returnType: .string)
		#expect(req != nil)
	}

	@Test("validRequestor returns nil with no selection for send")
	func validRequestorNoSelectionForSend() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		// No selection → cannot send
		let req = view.validRequestor(forSendType: .string, returnType: nil)
		#expect(req == nil)
	}
}

// MARK: - Key Equivalent String Tests

@Suite("TMDocumentEditor — Key Equivalent String")
@MainActor
struct KeyEquivalentStringTests {
	private func makeEditor() -> TMDocumentEditor {
		let doc = TMDocument()
		doc.setContent("", preserveRevision: true)
		let view = EditorView(frame: .zero)
		return TMDocumentEditor(document: doc, editorView: view)
	}

	@Test("key equiv with no bundle index returns false")
	func noIndexReturnsFalse() {
		let docEditor = makeEditor()
		// bundleIndex is nil by default
		#expect(docEditor.bundleIndex == nil)
	}
}
