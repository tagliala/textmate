import Testing
import TMCore
@testable import TMEditor

// MARK: - Snippet Mirror Tests

@Suite("Snippet Mirror Propagation")
struct SnippetMirrorTests {
	/// Inserts a snippet into the editor and pushes the snippet session.
	///
	/// Creates an editor with the given initial text, positions the caret at
	/// `insertAt`, inserts the snippet, and pushes tab stops + mirrors.
	private func makeEditorWithSnippet(
		text: String = "",
		insertAt: Int = 0,
		snippet: String,
	) -> Editor {
		let editor = Editor(text: text)
		let pos = editor.buffer.convert(offset: insertAt)
		editor.selections = SelectionState(caret: pos)

		// Parse the snippet.
		let state = SnippetState.parse(snippet)
		let expandedText = state.text
		let baseOffset = insertAt

		// Insert the expanded text.
		editor.insertText(expandedText)

		// Build tab stops from the snippet state's fields.
		var tabStops: [SnippetController.TabStop] = []
		let sortedFieldKeys = state.fields.keys.sorted()
		for key in sortedFieldKeys where key != 0 {
			if let field = state.fields[key] {
				let startOff = baseOffset + field.range.from.offset
				let endOff = baseOffset + field.range.to.offset
				let startPos = editor.buffer.convert(offset: min(startOff, editor.buffer.size))
				let endPos = editor.buffer.convert(offset: min(endOff, editor.buffer.size))
				let placeholder = field.range.substring(of: expandedText)
				tabStops.append(SnippetController.TabStop(
					index: key,
					range: TMCore.TextRange(anchor: startPos, head: endPos),
					placeholder: placeholder,
					choices: field.choices,
				))
			}
		}
		if let exitField = state.fields[0] {
			let startOff = baseOffset + exitField.range.from.offset
			let endOff = baseOffset + exitField.range.to.offset
			let startPos = editor.buffer.convert(offset: min(startOff, editor.buffer.size))
			let endPos = editor.buffer.convert(offset: min(endOff, editor.buffer.size))
			tabStops.append(SnippetController.TabStop(
				index: 0,
				range: TMCore.TextRange(anchor: startPos, head: endPos),
				placeholder: exitField.range.substring(of: expandedText),
			))
		}

		if !tabStops.isEmpty {
			let hasMirrors = !state.mirrors.isEmpty
			let session = SnippetController.Session(
				snippetText: expandedText,
				tabStops: tabStops,
				baseOffset: baseOffset,
				snippetState: hasMirrors ? state : nil,
			)
			editor.snippetController.push(session)
			if let first = tabStops.first {
				editor.selections = SelectionState([first.range])
			}
		}

		return editor
	}

	// MARK: - Basic Mirror Tests

	@Test("Snippet with mirror — typing updates mirror")
	func basicMirrorUpdate() throws {
		// Snippet: "${1:name} and $1" → "name and name"
		let editor = makeEditorWithSnippet(snippet: "${1:name} and $1")
		#expect(editor.buffer.string == "name and name")

		// Select the first tab stop (placeholder "name") and type "Bob".
		// The first tab stop should be selected already (from=0, to=4).
		let sel = try #require(editor.selections.primary)
		#expect(sel.start.offset == 0)
		#expect(sel.end.offset == 4)

		// Type "Bob" — this replaces the selection.
		editor.insertText("Bob")

		// Buffer should now be "Bob and Bob"
		#expect(editor.buffer.string == "Bob and Bob")
	}

	@Test("Mirror update with text before snippet")
	func mirrorUpdateWithPrefix() {
		// Start with "Hello " already in the buffer, insert snippet at offset 6.
		let editor = makeEditorWithSnippet(
			text: "Hello ",
			insertAt: 6,
			snippet: "${1:name} and $1",
		)
		#expect(editor.buffer.string == "Hello name and name")

		// Type "World" to replace "name" at the first tab stop.
		editor.insertText("World")
		#expect(editor.buffer.string == "Hello World and World")
	}

	@Test("Mirror update — delete entire placeholder")
	func mirrorDeletePlaceholder() {
		let editor = makeEditorWithSnippet(snippet: "${1:name} and $1")
		#expect(editor.buffer.string == "name and name")

		// Type "" (empty) to delete the placeholder.
		editor.insertText("")

		// Both field and mirror should be empty.
		#expect(editor.buffer.string == " and ")
	}

	@Test("Mirror update — type character by character")
	func mirrorTypeCharacterByCharacter() {
		let editor = makeEditorWithSnippet(snippet: "${1:name} and $1")
		#expect(editor.buffer.string == "name and name")

		// First, replace the selection "name" with "B".
		editor.insertText("B")
		#expect(editor.buffer.string == "B and B")

		// Now the caret should be after "B" at offset 1. Type "o".
		editor.insertText("o")
		#expect(editor.buffer.string == "Bo and Bo")

		// Type "b".
		editor.insertText("b")
		#expect(editor.buffer.string == "Bob and Bob")
	}

	@Test("Snippet without mirrors — no mirror propagation")
	func snippetWithoutMirrors() {
		let editor = makeEditorWithSnippet(snippet: "${1:first} ${2:second} $0")
		#expect(editor.buffer.string == "first second ")

		// Type replacement — should only affect the first field.
		editor.insertText("hello")
		#expect(editor.buffer.string == "hello second ")
	}

	// MARK: - Tab Stop Navigation

	@Test("Tab navigates to next tab stop after mirror update")
	func tabNavigationAfterMirror() throws {
		// Snippet: "${1:name} is ${2:great} and $1"
		let editor = makeEditorWithSnippet(snippet: "${1:name} is ${2:great} and $1")
		#expect(editor.buffer.string == "name is great and name")

		// Type in first tab stop.
		editor.insertText("Bob")
		#expect(editor.buffer.string == "Bob is great and Bob")

		// Navigate to next tab stop.
		let range = editor.snippetController.next()
		#expect(range != nil)
		editor.selections = try SelectionState([#require(range)])

		// Type in second tab stop.
		editor.insertText("ok")
		#expect(editor.buffer.string == "Bob is ok and Bob")
	}

	// MARK: - SnippetController Unit Tests

	@Test("SnippetController.replaceCurrentField returns empty for no mirrors")
	func replaceCurrentFieldNoMirrors() {
		let controller = SnippetController()
		let session = SnippetController.Session(
			snippetText: "hello",
			tabStops: [
				SnippetController.TabStop(
					index: 1,
					range: TextRange(
						anchor: TextPosition(line: 0, column: 0, offset: 0),
						head: TextPosition(line: 0, column: 5, offset: 5),
					),
					placeholder: "hello",
				),
			],
			baseOffset: 0,
			snippetState: nil,
		)
		controller.push(session)

		let updates = controller.replaceCurrentField(with: "world")
		#expect(updates.isEmpty)
	}

	@Test("SnippetController.hasActiveMirrors reflects state")
	func hasActiveMirrorsReflectsState() {
		let controller = SnippetController()
		#expect(!controller.hasActiveMirrors)

		// Push a session without mirrors.
		let session1 = SnippetController.Session(
			snippetText: "hello",
			tabStops: [],
			snippetState: nil,
		)
		controller.push(session1)
		#expect(!controller.hasActiveMirrors)
	}

	@Test("syncCurrentField keeps SnippetState.currentField in sync")
	func syncCurrentFieldOnNavigation() {
		let state = SnippetState.parse("${1:a} ${2:b} $0")
		let controller = SnippetController()

		let anchor0 = TextPosition(line: 0, column: 0, offset: 0)
		let head1 = TextPosition(line: 0, column: 1, offset: 1)
		let anchor2 = TextPosition(line: 0, column: 2, offset: 2)
		let head3 = TextPosition(line: 0, column: 3, offset: 3)
		let anchor4 = TextPosition(line: 0, column: 4, offset: 4)
		let head4 = TextPosition(line: 0, column: 4, offset: 4)

		let session = SnippetController.Session(
			snippetText: state.text,
			tabStops: [
				SnippetController.TabStop(index: 1, range: TextRange(anchor: anchor0, head: head1), placeholder: "a"),
				SnippetController.TabStop(index: 2, range: TextRange(anchor: anchor2, head: head3), placeholder: "b"),
				SnippetController.TabStop(index: 0, range: TextRange(anchor: anchor4, head: head4)),
			],
			snippetState: state,
		)
		controller.push(session)

		// Initially at tab stop 1 → state.currentField should be 1.
		#expect(state.currentField == 1)

		// Navigate to tab stop 2.
		_ = controller.next()
		#expect(state.currentField == 2)
	}
}
