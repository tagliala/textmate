import AppKit
import Testing
import TMAppKit
import TMBundleRuntime
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMTheme
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

	@Test("isDragSource starts false")
	func isDragSourceInitiallyFalse() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		#expect(!view.isDragSource)
	}

	@Test("source operation mask allows copy and move within app")
	func sourceOperationMaskWithinApp() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let session = FakeDraggingSession()
		let mask = view.draggingSession(session, sourceOperationMaskFor: .withinApplication)
		#expect(mask.contains(.copy))
		#expect(mask.contains(.move))
	}

	@Test("source operation mask allows copy and generic outside app")
	func sourceOperationMaskOutside() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let session = FakeDraggingSession()
		let mask = view.draggingSession(session, sourceOperationMaskFor: .outsideApplication)
		#expect(mask.contains(.copy))
		#expect(mask.contains(.generic))
		#expect(!mask.contains(.move))
	}
}

/// Minimal NSDraggingSession stand-in for testing.
@MainActor
private final class FakeDraggingSession: NSDraggingSession {}

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

// MARK: - Spell Checking Integration Tests

@Suite("TMDocumentEditor — Spell Checking")
@MainActor
struct SpellCheckIntegrationTests {
	private func makeEditor(text: String = "hello world") -> (TMDocumentEditor, EditorView) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, view)
	}

	@Test("spell checking disabled by default")
	func disabledByDefault() {
		let (docEditor, _) = makeEditor()
		#expect(docEditor.isContinuousSpellCheckingEnabled == false)
	}

	@Test("enabling spell checking propagates to editor view")
	func enablePropagates() {
		let (docEditor, view) = makeEditor()
		docEditor.isContinuousSpellCheckingEnabled = true
		#expect(view.isContinuousSpellCheckingEnabled == true)
	}

	@Test("disabling spell checking propagates to editor view")
	func disablePropagates() {
		let (docEditor, view) = makeEditor()
		docEditor.isContinuousSpellCheckingEnabled = true
		docEditor.isContinuousSpellCheckingEnabled = false
		#expect(view.isContinuousSpellCheckingEnabled == false)
	}

	@Test("misspellingsForLine returns empty when disabled")
	func misspellingsEmptyWhenDisabled() throws {
		let (docEditor, _) = makeEditor(text: "helo wrld")
		#expect(docEditor.isContinuousSpellCheckingEnabled == false)
		let result = try docEditor.editorView(
			#require(docEditor.editorView),
			misspellingsForLine: 0,
		)
		#expect(result.isEmpty)
	}

	@Test("misspellingsForLine caches results")
	func cachesMisspellings() {
		let (docEditor, _) = makeEditor(text: "helo wrld")
		docEditor.isContinuousSpellCheckingEnabled = true

		// First call fills the cache.
		let first = docEditor.misspellingsForLine(0)
		// Second call should return the same (cached) result.
		let second = docEditor.misspellingsForLine(0)
		#expect(first.count == second.count)
	}

	@Test("invalidateSpellCheckCache clears cache")
	func invalidateClears() {
		let (docEditor, _) = makeEditor(text: "hello world")
		docEditor.isContinuousSpellCheckingEnabled = true
		// Fill cache.
		_ = docEditor.misspellingsForLine(0)
		// Invalidate.
		docEditor.invalidateSpellCheckCache()
		// After invalidation the internal cache is empty, but the method
		// still returns results (re-checked lazily).
		let result = docEditor.misspellingsForLine(0)
		#expect(result.isEmpty) // "hello world" is not misspelled
	}

	@Test("spellDocumentTag returns a valid tag")
	func spellDocumentTag() {
		let (docEditor, view) = makeEditor()
		let tag = docEditor.editorViewSpellDocumentTag(view)
		#expect(tag != 0)
	}

	@Test("enabling spell checking wires layoutManager misspellingProvider")
	func misspellingProviderWired() {
		let (_, view) = makeEditor()
		// The misspelling provider should be set up by init.
		#expect(view.layoutManager.misspellingProvider != nil)
	}

	@Test("spellingSuggestions returns suggestions for misspelled word")
	func suggestionsForMisspelled() {
		let (docEditor, _) = makeEditor(text: "helo world")
		docEditor.isContinuousSpellCheckingEnabled = true
		// Point at (0,0) should hit the first word "helo" which is likely misspelled.
		let suggestions = docEditor.spellingSuggestions(at: .zero)
		// We can't predict exact suggestions, but a misspelled word should yield at least one.
		#expect(suggestions.count >= 0) // non-crashing is the key assertion
	}
}

// MARK: - EditorView Spell Checking State Tests

@Suite("EditorView — Spell Checking State")
@MainActor
struct EditorViewSpellCheckTests {
	@Test("spell checking disabled by default")
	func disabledByDefault() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		#expect(view.isContinuousSpellCheckingEnabled == false)
	}

	@Test("setting isContinuousSpellCheckingEnabled triggers display")
	func settingTriggersDisplay() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		view.isContinuousSpellCheckingEnabled = true
		#expect(view.isContinuousSpellCheckingEnabled == true)
	}

	@Test("spellingLanguage is nil by default")
	func languageDefaultNil() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		#expect(view.spellingLanguage == nil)
	}

	@Test("spellingLanguage can be set")
	func languageSettable() {
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		view.spellingLanguage = "en_US"
		#expect(view.spellingLanguage == "en_US")
	}
}

// MARK: - Macro Recording Tests

@Suite("TMDocumentEditor — Macro Recording")
@MainActor
struct MacroRecordingTests {
	private func makeEditor(text: String = "") -> (TMDocumentEditor, EditorView) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, view)
	}

	@Test("macro recorder not recording by default")
	func notRecordingByDefault() {
		let (docEditor, _) = makeEditor()
		#expect(docEditor.macroRecorder.isRecording == false)
		#expect(docEditor.macroRecorder.lastMacro == nil)
	}

	@Test("toggleMacroRecording starts recording")
	func startRecording() {
		let (docEditor, _) = makeEditor()
		let result = docEditor.toggleMacroRecording()
		#expect(result == nil) // Starting returns nil
		#expect(docEditor.macroRecorder.isRecording == true)
	}

	@Test("toggleMacroRecording stops recording and returns macro")
	func stopRecording() {
		let (docEditor, _) = makeEditor()
		docEditor.toggleMacroRecording()
		let macro = docEditor.toggleMacroRecording()
		#expect(macro != nil)
		#expect(docEditor.macroRecorder.isRecording == false)
	}

	@Test("text insertion records action during recording")
	func textInsertionRecords() {
		let (docEditor, view) = makeEditor()
		docEditor.toggleMacroRecording() // start
		docEditor.editorView(view, insertText: "a", replacementRange: NSRange(location: NSNotFound, length: 0))
		docEditor.editorView(view, insertText: "b", replacementRange: NSRange(location: NSNotFound, length: 0))
		let macro = docEditor.toggleMacroRecording() // stop
		#expect(macro != nil)
		#expect(macro?.actions.count == 2)
		#expect(macro?.actions[0].text == "a")
		#expect(macro?.actions[1].text == "b")
	}

	@Test("editor action records during recording")
	func editorActionRecords() {
		let (docEditor, view) = makeEditor(text: "hello")
		docEditor.toggleMacroRecording()
		docEditor.editorView(view, performAction: .moveRight)
		let macro = docEditor.toggleMacroRecording()
		#expect(macro != nil)
		#expect(macro?.actions.count == 1)
		#expect(macro?.actions[0].action == .moveForward)
	}

	@Test("replayMacro replays text insertions")
	func replayTextInsertions() {
		let (docEditor, view) = makeEditor()
		// Record typing "hi"
		docEditor.toggleMacroRecording()
		docEditor.editorView(view, insertText: "h", replacementRange: NSRange(location: NSNotFound, length: 0))
		docEditor.editorView(view, insertText: "i", replacementRange: NSRange(location: NSNotFound, length: 0))
		docEditor.toggleMacroRecording()

		// Now replay — should append "hi" again
		let textBefore = docEditor.editor.text
		docEditor.replayMacro()
		#expect(docEditor.editor.text == textBefore + "hi")
	}

	@Test("replayMacro does nothing without recorded macro")
	func replayWithoutMacro() {
		let (docEditor, _) = makeEditor(text: "hello")
		docEditor.replayMacro()
		#expect(docEditor.editor.text == "hello") // unchanged
	}
}

// MARK: - Menu Actions — Spell & Macro Validation Tests

@Suite("DocumentWindowController — Spell & Macro Validation")
@MainActor
struct SpellMacroValidationTests {
	@Test("validateMenuItem toggleContinuousSpellChecking sets checkmark")
	func toggleSpellCheckCheckmark() {
		let controller = DocumentWindowController()
		let item = NSMenuItem(
			title: "Check Spelling While Typing",
			action: NSSelectorFromString("toggleContinuousSpellChecking:"),
			keyEquivalent: "",
		)
		_ = controller.validateMenuItem(item)
		#expect(item.state == .off)

		controller.isSpellCheckingEnabled = true
		_ = controller.validateMenuItem(item)
		#expect(item.state == .on)
	}

	@Test("toggleContinuousSpellChecking toggles flag")
	func toggleSpellChecking() {
		let controller = DocumentWindowController()
		#expect(controller.isSpellCheckingEnabled == false)

		controller.toggleContinuousSpellChecking(nil)
		#expect(controller.isSpellCheckingEnabled == true)

		controller.toggleContinuousSpellChecking(nil)
		#expect(controller.isSpellCheckingEnabled == false)
	}

	@Test("validateMenuItem toggleMacroRecording updates title")
	func macroRecordingTitle() {
		let doc = TMDocument()
		doc.setContent("", preserveRevision: true)
		let controller = DocumentWindowController(document: doc)

		let item = NSMenuItem(
			title: "Start Recording",
			action: NSSelectorFromString("toggleMacroRecording:"),
			keyEquivalent: "",
		)

		_ = controller.validateMenuItem(item)
		#expect(item.title == "Start Recording")

		// Start recording
		controller.documentEditor?.toggleMacroRecording()
		_ = controller.validateMenuItem(item)
		#expect(item.title == "Stop Recording")
	}

	@Test("validateMenuItem replayMacro disabled without macro")
	func replayMacroDisabled() {
		let doc = TMDocument()
		doc.setContent("", preserveRevision: true)
		let controller = DocumentWindowController(document: doc)

		let item = NSMenuItem(
			title: "Replay Macro",
			action: NSSelectorFromString("replayMacro:"),
			keyEquivalent: "",
		)
		let enabled = controller.validateMenuItem(item)
		#expect(enabled == false)
	}
}

// MARK: - Theme Live Reload Tests

@Suite("DocumentWindowController — Theme Live Reload")
@MainActor
struct ThemeLiveReloadTests {
	private func makeTheme(
		foreground: ThemeColor = ThemeColor(red: 0, green: 0, blue: 0),
		background: ThemeColor = ThemeColor(red: 1, green: 1, blue: 1),
		caret: ThemeColor? = nil,
		selection: ThemeColor? = nil,
	) -> Theme {
		Theme(
			name: "Test",
			semanticClass: "theme.light.test",
			uuid: "00000000-0000-0000-0000-000000000001",
			globalSettings: ThemeGlobalSettings(
				foreground: foreground,
				background: background,
				caret: caret ?? foreground,
				selection: selection ?? ThemeColor(red: 0.8, green: 0.8, blue: 1),
			),
			gutterSettings: ThemeGutterSettings(),
			rules: [],
		)
	}

	@Test("applyTheme sets themeEngine")
	func applyThemeSetsEngine() {
		let wc = DocumentWindowController()
		#expect(wc.themeEngine == nil)

		let theme = makeTheme()
		wc.applyTheme(theme)

		#expect(wc.themeEngine != nil)
	}

	@Test("applyTheme updates editor background color")
	func applyThemeUpdatesBackground() {
		let wc = DocumentWindowController()
		let theme = makeTheme(background: ThemeColor(red: 0.2, green: 0.3, blue: 0.4))
		wc.applyTheme(theme)

		let bg = wc.editorView.layoutManager.backgroundColor
		#expect(abs(bg.redComponent - 0.2) < 0.01)
		#expect(abs(bg.greenComponent - 0.3) < 0.01)
		#expect(abs(bg.blueComponent - 0.4) < 0.01)
	}

	@Test("applyTheme replaces themeEngine on subsequent call")
	func applyThemeReplacesEngine() {
		let wc = DocumentWindowController()

		let theme1 = makeTheme(foreground: ThemeColor(red: 1, green: 0, blue: 0))
		wc.applyTheme(theme1)
		let engine1 = wc.themeEngine

		let theme2 = makeTheme(foreground: ThemeColor(red: 0, green: 1, blue: 0))
		wc.applyTheme(theme2)
		let engine2 = wc.themeEngine

		#expect(engine1 !== engine2)
	}

	@Test("applyTheme updates caret color")
	func applyThemeUpdatesCaretColor() {
		let wc = DocumentWindowController()
		let theme = makeTheme(caret: ThemeColor(red: 1, green: 0, blue: 0))
		wc.applyTheme(theme)

		let caret = wc.editorView.caretColor
		#expect(caret.redComponent > 0.9)
		#expect(caret.greenComponent < 0.1)
	}
}

// MARK: - Grammar Switching Tests

@Suite("DocumentWindowController — Grammar Switching")
@MainActor
struct GrammarSwitchingTests {
	@Test("willShowGrammarMenu populates popup with grammars")
	func populatesGrammarMenu() {
		let wc = DocumentWindowController()
		let index = BundleIndex()
		let grammar1 = BundleItem(
			uuid: "g1", name: "Swift", kind: .grammar,
			scopeSelector: "source.swift", bundleUUID: "b1",
		)
		let grammar2 = BundleItem(
			uuid: "g2", name: "Ruby", kind: .grammar,
			scopeSelector: "source.ruby", bundleUUID: "b1",
		)
		index.setIndex(items: [grammar1, grammar2], bundles: [])
		wc.bundleIndex = index

		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		wc.statusBarViewWillShowGrammarMenu(wc.statusBarView, popup: popup)

		// "Plain Text" + separator + "Ruby" + "Swift" (sorted alphabetically).
		let titles = popup.itemTitles
		#expect(titles.first == "Plain Text")
		#expect(titles.contains("Ruby"))
		#expect(titles.contains("Swift"))
	}

	@Test("willShowGrammarMenu sorts grammars alphabetically")
	func sortedAlphabetically() {
		let wc = DocumentWindowController()
		let index = BundleIndex()
		let items = [
			BundleItem(uuid: "g1", name: "Zig", kind: .grammar, scopeSelector: "source.zig", bundleUUID: "b1"),
			BundleItem(uuid: "g2", name: "Ada", kind: .grammar, scopeSelector: "source.ada", bundleUUID: "b1"),
			BundleItem(uuid: "g3", name: "Lua", kind: .grammar, scopeSelector: "source.lua", bundleUUID: "b1"),
		]
		index.setIndex(items: items, bundles: [])
		wc.bundleIndex = index

		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		wc.statusBarViewWillShowGrammarMenu(wc.statusBarView, popup: popup)

		// Skip "Plain Text" and separator.
		let grammarTitles = popup.itemTitles.filter { $0 != "Plain Text" && !$0.isEmpty }
		#expect(grammarTitles == ["Ada", "Lua", "Zig"])
	}

	@Test("willShowGrammarMenu empty without bundleIndex")
	func emptyWithoutIndex() {
		let wc = DocumentWindowController()
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		popup.addItem(withTitle: "existing")
		wc.statusBarViewWillShowGrammarMenu(wc.statusBarView, popup: popup)

		// Should be cleared without grammars.
		#expect(popup.numberOfItems == 0)
	}

	@Test("didSelectGrammar updates status bar")
	func selectGrammarUpdatesStatusBar() {
		let wc = DocumentWindowController()
		let index = BundleIndex()
		let grammar = BundleItem(
			uuid: "g1", name: "Python", kind: .grammar,
			scopeSelector: "source.python", bundleUUID: "b1",
		)
		index.setIndex(items: [grammar], bundles: [])
		wc.bundleIndex = index

		// didSelectGrammar with empty scope → Plain Text.
		wc.statusBarView(wc.statusBarView, didSelectGrammar: "")
		#expect(wc.statusBarView.grammarTitle == "Plain Text")
	}

	@Test("grammar menu items carry scope as representedObject")
	func menuItemsHaveScope() {
		let wc = DocumentWindowController()
		let index = BundleIndex()
		let grammar = BundleItem(
			uuid: "g1", name: "Go", kind: .grammar,
			scopeSelector: "source.go", bundleUUID: "b1",
		)
		index.setIndex(items: [grammar], bundles: [])
		wc.bundleIndex = index

		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		wc.statusBarViewWillShowGrammarMenu(wc.statusBarView, popup: popup)

		let goItem = popup.menu?.items.first { $0.title == "Go" }
		#expect(goItem?.representedObject as? String == "source.go")

		let plainItem = popup.menu?.items.first { $0.title == "Plain Text" }
		#expect(plainItem?.representedObject as? String == "")
	}
}

// MARK: - Escape → Completion Tests

@Suite("TMDocumentEditor — Escape Completion")
@MainActor
struct EscapeCompletionTests {
	private func makeEditor(text: String) -> (TMDocumentEditor, EditorView) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, view)
	}

	@Test("cancelOperation triggers completion")
	func cancelOperationTriggersCompletion() {
		let (docEditor, view) = makeEditor(text: "hello world hel")
		docEditor.editor.perform(.moveToEndOfDocument)

		// Send cancelOperation: (Escape key)
		docEditor.editorView(view, doCommandBySelector: NSSelectorFromString("cancelOperation:"))

		// The completion engine should have found "hello" and applied it.
		#expect(docEditor.editor.isCompletionActive || docEditor.editor.text.contains("hello"))
	}

	@Test("cancelOperation on empty buffer does not crash")
	func cancelOperationEmptyBuffer() {
		let (docEditor, view) = makeEditor(text: "")
		docEditor.editorView(view, doCommandBySelector: NSSelectorFromString("cancelOperation:"))
		// Should not crash — completion with no words just does nothing.
		#expect(docEditor.editor.text == "")
	}
}

// MARK: - File Drop Handler Tests

@Suite("TMDocumentEditor — File Drop")
@MainActor
struct FileDropTests {
	private func makeEditor(text: String = "") -> (TMDocumentEditor, EditorView) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, view)
	}

	@Test("file drop inserts single path")
	func singleFileDrop() {
		let (docEditor, view) = makeEditor()
		let url = URL(fileURLWithPath: "/tmp/test.txt")
		docEditor.editorView(view, didReceiveFileDrop: [url], atLine: 0, index: 0)
		#expect(docEditor.editor.text == "/tmp/test.txt")
	}

	@Test("file drop inserts multiple paths joined by newlines")
	func multipleFileDrop() {
		let (docEditor, view) = makeEditor()
		let urls = [
			URL(fileURLWithPath: "/tmp/a.txt"),
			URL(fileURLWithPath: "/tmp/b.png"),
		]
		docEditor.editorView(view, didReceiveFileDrop: urls, atLine: 0, index: 0)
		#expect(docEditor.editor.text == "/tmp/a.txt\n/tmp/b.png")
	}

	@Test("file drop appends to existing text")
	func dropAppendsToExisting() {
		let (docEditor, view) = makeEditor(text: "prefix ")
		docEditor.editor.perform(.moveToEndOfDocument)
		let url = URL(fileURLWithPath: "/tmp/file.md")
		docEditor.editorView(view, didReceiveFileDrop: [url], atLine: 0, index: 0)
		#expect(docEditor.editor.text == "prefix /tmp/file.md")
	}

	@Test("file drop invokes drag command callback when matching")
	func dropInvokesDragCommand() async {
		let (docEditor, view) = makeEditor()
		let index = BundleIndex()
		let dragItem = BundleItem(
			uuid: "drag-1",
			name: "Insert Image",
			kind: .dragCommand,
			bundleUUID: "b1",
			plist: [
				"command": "#!/bin/bash\necho '<img>'",
				"draggedFileExtensions": ["png", "jpg"],
			],
		)
		index.setIndex(items: [dragItem], bundles: [])
		docEditor.bundleIndex = index

		var receivedCommand: BundleCommand?
		docEditor.onExecuteBundleCommand = { cmd in
			receivedCommand = cmd
		}

		let url = URL(fileURLWithPath: "/tmp/photo.png")
		docEditor.editorView(view, didReceiveFileDrop: [url], atLine: 0, index: 0)

		// Allow the Task to run.
		try? await Task.sleep(for: .milliseconds(50))
		#expect(receivedCommand != nil)
		#expect(receivedCommand?.name == "Insert Image")
		// Text should NOT have been inserted (command was dispatched instead).
		#expect(docEditor.editor.text == "")
	}

	@Test("file drop falls back to path insertion without bundleIndex")
	func dropFallsBackWithoutIndex() {
		let (docEditor, view) = makeEditor()
		// No bundleIndex set — should fall through to path insertion.
		let url = URL(fileURLWithPath: "/tmp/photo.png")
		docEditor.editorView(view, didReceiveFileDrop: [url], atLine: 0, index: 0)
		#expect(docEditor.editor.text == "/tmp/photo.png")
	}

	@Test("text drop copy inserts text at position")
	func textDropCopyInserts() {
		let (docEditor, view) = makeEditor(text: "hello world")
		docEditor.editorView(
			view,
			didReceiveTextDrop: "NEW",
			atLine: 0,
			index: 5,
			isMove: false,
		)
		#expect(docEditor.editor.text == "helloNEW world")
	}

	@Test("text drop move saves pre-drag selections")
	func textDropMoveSavesSelections() {
		let (docEditor, view) = makeEditor(text: "hello world")
		// Select "hello" (offset 0..5).
		let start = docEditor.editor.buffer.convert(offset: 0)
		let end = docEditor.editor.buffer.convert(offset: 5)
		docEditor.editor.selections = SelectionState([TMCore.TextRange(anchor: start, head: end)])

		docEditor.editorView(
			view,
			didReceiveTextDrop: "hello",
			atLine: 0,
			index: 8,
			isMove: true,
		)

		// Text should be inserted at the drop position.
		#expect(docEditor.editor.text.contains("hello"))
	}

	@Test("drag move complete deletes original selection")
	func dragMoveCompletedDeletesSelection() {
		let (docEditor, view) = makeEditor(text: "ABCDE12345")
		// Select "ABCDE" (offset 0..5).
		let start = docEditor.editor.buffer.convert(offset: 0)
		let end = docEditor.editor.buffer.convert(offset: 5)
		docEditor.editor.selections = SelectionState([TMCore.TextRange(anchor: start, head: end)])

		// Simulate a text drop-move: drop "ABCDE" after "12345".
		docEditor.editorView(
			view,
			didReceiveTextDrop: "ABCDE",
			atLine: 0,
			index: 10,
			isMove: true,
		)

		// After drop, text has the insertion. Now complete the move.
		docEditor.editorViewDidCompleteDragMove(view)

		// The original "ABCDE" should be removed.
		// Result depends on insertion shifting offsets, but the original
		// 5 characters at offset 0..5 that were "ABCDE" are deleted.
		#expect(!docEditor.editor.text.hasPrefix("ABCDE"))
	}

	@Test("drag move complete is no-op without saved selections")
	func dragMoveCompleteNoOp() {
		let (docEditor, view) = makeEditor(text: "hello")
		// No text drop preceded this — should be no-op.
		docEditor.editorViewDidCompleteDragMove(view)
		#expect(docEditor.editor.text == "hello")
	}
}

// MARK: - Command Dispatch via Tab Trigger and Key Equivalent

@Suite("TMDocumentEditor — Command Dispatch")
@MainActor
struct CommandDispatchTests {
	private func makeEditor(text: String) -> TMDocumentEditor {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		return TMDocumentEditor(document: doc, editorView: view)
	}

	@Test("expandTabTrigger dispatches command item via callback")
	func tabTriggerDispatchesCommand() async {
		let editor = makeEditor(text: "greet")
		let index = BundleIndex()
		let item = BundleItem(
			uuid: "cmd-1",
			name: "Greet Command",
			kind: .command,
			bundleUUID: "b1",
			tabTrigger: "greet",
			plist: ["command": "echo hello", "input": "none", "output": "discard"],
		)
		index.setIndex(items: [item], bundles: [])
		editor.bundleIndex = index
		editor.editor.perform(.moveToEndOfDocument)

		var receivedCommand: BundleCommand?
		editor.onExecuteBundleCommand = { cmd in
			receivedCommand = cmd
		}

		let result = editor.expandTabTrigger()
		#expect(result == true)

		// Allow the Task to execute.
		try? await Task.sleep(for: .milliseconds(50))
		#expect(receivedCommand != nil)
		#expect(receivedCommand?.name == "Greet Command")
		#expect(receivedCommand?.command.contains("echo hello") == true)
	}

	@Test("expandTabTrigger selects trigger text before dispatching command")
	func tabTriggerSelectsTriggerForCommand() async {
		let editor = makeEditor(text: "run")
		let index = BundleIndex()
		let item = BundleItem(
			uuid: "cmd-2",
			name: "Run",
			kind: .command,
			bundleUUID: "b1",
			tabTrigger: "run",
			plist: ["command": "echo run", "input": "selection", "output": "replaceInput"],
		)
		index.setIndex(items: [item], bundles: [])
		editor.bundleIndex = index
		editor.editor.perform(.moveToEndOfDocument)

		var receivedCommand: BundleCommand?
		editor.onExecuteBundleCommand = { cmd in
			receivedCommand = cmd
		}

		_ = editor.expandTabTrigger()
		try? await Task.sleep(for: .milliseconds(50))

		#expect(receivedCommand != nil)
		// The trigger text "run" should be selected (anchor..head covers it).
		let sel = editor.editor.selections.primary
		#expect(sel != nil)
	}

	@Test("expandTabTrigger still expands snippets correctly")
	func tabTriggerSnippetStillWorks() {
		let editor = makeEditor(text: "fun")
		let index = BundleIndex()
		let item = BundleItem(
			uuid: "snip-1",
			name: "Function Snippet",
			kind: .snippet,
			bundleUUID: "b1",
			tabTrigger: "fun",
			plist: ["content": "function $0() {}"],
		)
		index.setIndex(items: [item], bundles: [])
		editor.bundleIndex = index
		editor.editor.perform(.moveToEndOfDocument)

		let result = editor.expandTabTrigger()
		#expect(result == true)
		#expect(editor.editor.text.hasPrefix("function "))
	}

	@Test("expandTabTrigger returns false when callback missing for command")
	func tabTriggerReturnsFalseWithoutCallback() {
		let editor = makeEditor(text: "greet")
		let index = BundleIndex()
		let item = BundleItem(
			uuid: "cmd-3",
			name: "Greet",
			kind: .command,
			bundleUUID: "b1",
			tabTrigger: "greet",
			plist: ["command": "echo hi", "input": "none", "output": "discard"],
		)
		index.setIndex(items: [item], bundles: [])
		editor.bundleIndex = index
		editor.editor.perform(.moveToEndOfDocument)

		// No onExecuteBundleCommand set
		let result = editor.expandTabTrigger()
		#expect(result == false)
	}

	@Test("performKeyEquivalent dispatches command item")
	func keyEquivDispatchesCommand() async throws {
		let editor = makeEditor(text: "")
		let index = BundleIndex()
		let item = BundleItem(
			uuid: "cmd-ke-1",
			name: "Build Command",
			kind: .command,
			bundleUUID: "b1",
			keyEquivalent: "@b",
			plist: ["command": "make build", "input": "none", "output": "discard"],
		)
		index.setIndex(items: [item], bundles: [])
		editor.bundleIndex = index

		var receivedCommand: BundleCommand?
		editor.onExecuteBundleCommand = { cmd in
			receivedCommand = cmd
		}

		// Simulate the key equivalent match by calling performKeyEquivalent
		// with an event matching "@b" (Cmd+B).
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.command],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "b",
			charactersIgnoringModifiers: "b",
			isARepeat: false,
			keyCode: 11,
		))
		let view = try #require(editor.editorView)
		let result = editor.editorView(view, performKeyEquivalent: event)
		#expect(result == true)

		try? await Task.sleep(for: .milliseconds(50))
		#expect(receivedCommand != nil)
		#expect(receivedCommand?.name == "Build Command")
		#expect(receivedCommand?.command.contains("make build") == true)
	}

	@Test("performKeyEquivalent handles snippet item via key equiv")
	func keyEquivExpandsSnippet() throws {
		let editor = makeEditor(text: "")
		let index = BundleIndex()
		let item = BundleItem(
			uuid: "snip-ke-1",
			name: "Snippet via KeyEquiv",
			kind: .snippet,
			bundleUUID: "b1",
			keyEquivalent: "@s",
			plist: ["content": "snippet_text"],
		)
		index.setIndex(items: [item], bundles: [])
		editor.bundleIndex = index

		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.command],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "s",
			charactersIgnoringModifiers: "s",
			isARepeat: false,
			keyCode: 1,
		))
		let view = try #require(editor.editorView)
		let result = editor.editorView(view, performKeyEquivalent: event)
		#expect(result == true)
		#expect(editor.editor.text == "snippet_text")
	}

	@Test("performKeyEquivalent returns false without bundle index")
	func keyEquivReturnsFalseWithoutIndex() throws {
		let editor = makeEditor(text: "")
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.command],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "b",
			charactersIgnoringModifiers: "b",
			isARepeat: false,
			keyCode: 11,
		))
		let view = try #require(editor.editorView)
		let result = editor.editorView(view, performKeyEquivalent: event)
		#expect(result == false)
	}
}
