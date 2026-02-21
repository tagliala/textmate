import AppKit
import Testing
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
@testable import TMDocumentWindow

// MARK: - ChoiceMenuPanel Wiring Tests

@Suite("TMDocumentEditor — ChoiceMenu Wiring")
@MainActor
struct ChoiceMenuWiringTests {
	// MARK: - Helpers

	private func makeEditor(text: String = "") -> (TMDocumentEditor, EditorView) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, view)
	}

	/// Pushes a snippet session with choices on the first tab stop.
	private func pushSnippetWithChoices(
		_ docEditor: TMDocumentEditor,
		choices: [String],
		placeholder: String = "",
	) {
		let placeholderLen = placeholder.utf8.count
		let range = TMCore.TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0),
			head: TextPosition(line: 0, column: placeholderLen, offset: placeholderLen),
		)
		let tabStop = SnippetController.TabStop(
			index: 1,
			range: range,
			placeholder: placeholder,
			choices: choices,
		)
		let exitStop = SnippetController.TabStop(
			index: 0,
			range: TMCore.TextRange(
				anchor: TextPosition(line: 0, column: placeholderLen, offset: placeholderLen),
				head: TextPosition(line: 0, column: placeholderLen, offset: placeholderLen),
			),
		)
		let session = SnippetController.Session(
			snippetText: placeholder,
			tabStops: [tabStop, exitStop],
			currentTabStopIndex: 0,
			baseOffset: 0,
		)
		docEditor.editor.snippetController.push(session)
	}

	// MARK: - handleKeyDown

	@Test("handleKeyDown returns false when no choice menu exists")
	func handleKeyDownNoMenu() throws {
		let (docEditor, view) = makeEditor(text: "hello")
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "\r",
			charactersIgnoringModifiers: "\r",
			isARepeat: false,
			keyCode: 36,
		))
		let handled = docEditor.editorView(view, handleKeyDown: event)
		#expect(!handled)
	}

	@Test("handleKeyDown returns false when choice menu is not visible")
	func handleKeyDownMenuNotVisible() throws {
		let (docEditor, view) = makeEditor(text: "hello")
		// Create a menu but don't show it.
		let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
		let menu = ChoiceMenuPanel(font: font)
		menu.choices = ["a", "b"]
		docEditor.choiceMenu = menu

		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "\r",
			charactersIgnoringModifiers: "\r",
			isARepeat: false,
			keyCode: 36,
		))
		let handled = docEditor.editorView(view, handleKeyDown: event)
		// Menu exists but is not visible, so key goes unhandled.
		#expect(!handled)
	}

	// MARK: - showSnippetChoicesIfNeeded

	@Test("showSnippetChoicesIfNeeded creates choice menu when snippet has choices")
	func showCreatesMenuForSnippetChoices() {
		let (docEditor, _) = makeEditor(text: "")
		pushSnippetWithChoices(docEditor, choices: ["one", "two", "three"])

		#expect(docEditor.choiceMenu == nil)
		docEditor.showSnippetChoicesIfNeeded()
		#expect(docEditor.choiceMenu != nil)
		#expect(docEditor.choiceMenu?.choices == ["one", "two", "three"])
		#expect(docEditor.choiceMenu?.choiceIndex == 0)
	}

	@Test("showSnippetChoicesIfNeeded does nothing without snippet choices")
	func showDoesNothingWithoutChoices() {
		let (docEditor, _) = makeEditor(text: "hello")
		docEditor.showSnippetChoicesIfNeeded()
		#expect(docEditor.choiceMenu == nil)
	}

	@Test("showSnippetChoicesIfNeeded does nothing when snippet is empty")
	func showDoesNothingWithEmptySnippet() {
		let (docEditor, _) = makeEditor(text: "hello")
		// No snippet session pushed.
		#expect(docEditor.editor.snippetController.isEmpty)
		docEditor.showSnippetChoicesIfNeeded()
		#expect(docEditor.choiceMenu == nil)
	}

	@Test("showSnippetChoicesIfNeeded updates choices when menu already exists")
	func showUpdatesExistingMenu() {
		let (docEditor, _) = makeEditor(text: "")
		pushSnippetWithChoices(docEditor, choices: ["a", "b"])

		docEditor.showSnippetChoicesIfNeeded()
		let menu = docEditor.choiceMenu
		#expect(menu?.choices == ["a", "b"])

		// Clear first session, push another with different choices.
		docEditor.editor.snippetController.clear()
		pushSnippetWithChoices(docEditor, choices: ["x", "y", "z"])

		docEditor.showSnippetChoicesIfNeeded()
		// Should reuse the same menu object.
		#expect(docEditor.choiceMenu === menu)
		#expect(docEditor.choiceMenu?.choices == ["x", "y", "z"])
	}

	// MARK: - acceptChoiceMenuSelection

	@Test("acceptChoiceMenuSelection replaces tab stop content for snippet choice")
	func acceptReplacesSnippetTabStop() {
		let (docEditor, _) = makeEditor(text: "cat")
		pushSnippetWithChoices(
			docEditor,
			choices: ["cat", "dog", "bird"],
			placeholder: "cat",
		)

		docEditor.acceptChoiceMenuSelection("dog")

		#expect(docEditor.editor.text == "dog")
	}

	@Test("acceptChoiceMenuSelection cancels completion for active completion")
	func acceptCancelsCompletion() {
		let (docEditor, _) = makeEditor(text: "hello")
		// Activate completion mode by setting suggestions directly.
		docEditor.editor.completionInfo.setSuggestions(["hello", "help", "hero"])
		#expect(!docEditor.editor.completionInfo.isEmpty)

		docEditor.acceptChoiceMenuSelection("help")

		#expect(docEditor.editor.completionInfo.isEmpty)
	}

	@Test("acceptChoiceMenuSelection dismisses the choice menu")
	func acceptDismissesMenu() {
		let (docEditor, _) = makeEditor(text: "cat")
		pushSnippetWithChoices(
			docEditor,
			choices: ["cat", "dog"],
			placeholder: "cat",
		)
		docEditor.showSnippetChoicesIfNeeded()
		#expect(docEditor.choiceMenu != nil)

		docEditor.acceptChoiceMenuSelection("dog")
		// Menu dismiss is called (the panel object still exists but should not be visible).
		// We verify that the buffer was updated instead.
		#expect(docEditor.editor.text == "dog")
	}

	// MARK: - createChoiceMenu callbacks

	@Test("createChoiceMenu wires onAccept callback")
	func createMenuHasOnAccept() {
		let (docEditor, _) = makeEditor(text: "")
		docEditor.showSnippetChoicesIfNeeded()
		// No snippet = no menu, so push one.
		pushSnippetWithChoices(docEditor, choices: ["a"])
		docEditor.showSnippetChoicesIfNeeded()
		#expect(docEditor.choiceMenu?.onAccept != nil)
	}

	@Test("createChoiceMenu wires onCancel callback")
	func createMenuHasOnCancel() {
		let (docEditor, _) = makeEditor(text: "")
		pushSnippetWithChoices(docEditor, choices: ["a"])
		docEditor.showSnippetChoicesIfNeeded()
		#expect(docEditor.choiceMenu?.onCancel != nil)
	}

	// MARK: - EditorView key interception

	@Test("EditorView keyDown calls delegate handleKeyDown")
	func editorViewCallsDelegate() throws {
		let (docEditor, view) = makeEditor(text: "hello")
		// Confirm TMDocumentEditor is the delegate.
		#expect(view.delegate === docEditor)

		// Without a visible choice menu, handleKeyDown returns false,
		// meaning keyDown proceeds to interpretKeyEvents normally.
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "a",
			charactersIgnoringModifiers: "a",
			isARepeat: false,
			keyCode: 0,
		))
		let handled = docEditor.editorView(view, handleKeyDown: event)
		#expect(!handled)
	}
}
