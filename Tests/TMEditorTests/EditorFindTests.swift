import Testing
import TMCore
import TMSearchReplace
@testable import TMEditor

// MARK: - Editor Find/Replace Tests

@Suite("Editor Find/Replace")
struct EditorFindReplaceTests {
	/// Creates an editor with the given text and sets the find clipboard.
	private func makeEditor(
		text: String,
		findPattern: String = "",
		replacePattern: String = "",
		findOptions: FindOptions = [.wrapAround],
	) -> Editor {
		let editor = Editor(text: text)
		editor.findOptions = findOptions
		if !findPattern.isEmpty {
			editor.clipboards.find.push(ClipboardEntry(findPattern))
		}
		if !replacePattern.isEmpty {
			editor.clipboards.replace.push(ClipboardEntry(replacePattern))
		}
		return editor
	}

	// MARK: - Find Next

	@Test("findNext selects first match from start")
	func findNextFromStart() throws {
		let editor = makeEditor(text: "hello world hello", findPattern: "hello")
		editor.perform(.findNext)

		#expect(editor.selections.count == 1)
		let sel = try #require(editor.selections.primary)
		// First "hello" is at bytes 0..<5
		#expect(sel.start.offset == 0)
		#expect(sel.end.offset == 5)
	}

	@Test("findNext advances past current selection")
	func findNextAdvances() {
		let editor = makeEditor(text: "hello world hello", findPattern: "hello")

		// Find first match
		editor.perform(.findNext)
		#expect(editor.selections.primary?.start.offset == 0)

		// Find next match — should find second "hello"
		editor.perform(.findNext)
		#expect(editor.selections.primary?.start.offset == 12)
		#expect(editor.selections.primary?.end.offset == 17)
	}

	@Test("findNext wraps around")
	func findNextWrapsAround() {
		let editor = makeEditor(text: "hello world hello", findPattern: "hello")

		// Find first and second matches
		editor.perform(.findNext)
		editor.perform(.findNext)
		#expect(editor.selections.primary?.start.offset == 12)

		// Next find should wrap to the first match
		editor.perform(.findNext)
		#expect(editor.selections.primary?.start.offset == 0)
	}

	@Test("findNext with no match leaves selection unchanged")
	func findNextNoMatch() {
		let editor = makeEditor(text: "hello world", findPattern: "xyz")
		let originalSel = editor.selections

		editor.perform(.findNext)

		// Selection should remain unchanged
		#expect(editor.selections == originalSel)
	}

	@Test("findNext with empty find clipboard does nothing")
	func findNextEmptyClipboard() {
		let editor = Editor(text: "hello world")
		let originalSel = editor.selections

		editor.perform(.findNext)

		#expect(editor.selections == originalSel)
	}

	// MARK: - Find Previous

	@Test("findPrevious searches backwards")
	func findPrevious() throws {
		let editor = makeEditor(text: "hello world hello", findPattern: "hello")

		// Place caret at end
		editor.selections = SelectionState(
			caret: editor.buffer.convert(offset: editor.buffer.size),
		)

		editor.perform(.findPrevious)

		// Should find the second "hello" (working backwards from end)
		let sel = try #require(editor.selections.primary)
		#expect(sel.start.offset == 12)
		#expect(sel.end.offset == 17)
	}

	// MARK: - Find and Modify Selection

	@Test("findNextAndModifySelection adds match to selections")
	func findNextAndModifySelection() {
		let editor = makeEditor(text: "aa bb aa bb", findPattern: "aa")

		// Find first match normally
		editor.perform(.findNext)
		#expect(editor.selections.count == 1)
		#expect(editor.selections.primary?.start.offset == 0)

		// Find next and extend — should have 2 selections
		editor.perform(.findNextAndModifySelection)
		#expect(editor.selections.count == 2)
	}

	// MARK: - Find All

	@Test("findAll selects all matches")
	func findAll() {
		let editor = makeEditor(text: "aa bb aa cc aa", findPattern: "aa")
		editor.perform(.findAll)

		#expect(editor.selections.count == 3)
		let offsets = editor.selections.selections.map(\.start.offset).sorted()
		#expect(offsets == [0, 6, 12])
	}

	@Test("findAll with no matches leaves selection unchanged")
	func findAllNoMatches() {
		let editor = makeEditor(text: "hello world", findPattern: "xyz")
		let originalSel = editor.selections

		editor.perform(.findAll)

		#expect(editor.selections == originalSel)
	}

	@Test("findAllInSelection searches within selection")
	func findAllInSelection() {
		let editor = makeEditor(text: "aa bb aa cc aa", findPattern: "aa")

		// Select "aa bb aa" (bytes 0..<8)
		editor.selections = SelectionState([
			TextRange(
				anchor: editor.buffer.convert(offset: 0),
				head: editor.buffer.convert(offset: 8),
			),
		])

		editor.perform(.findAllInSelection)

		#expect(editor.selections.count == 2)
		let offsets = editor.selections.selections.map(\.start.offset).sorted()
		#expect(offsets == [0, 6])
	}

	// MARK: - Replace

	@Test("replace inserts replacement at selection")
	func replace() {
		let editor = makeEditor(
			text: "hello world",
			findPattern: "hello",
			replacePattern: "goodbye",
		)

		// Find the match first
		editor.perform(.findNext)
		#expect(editor.selectedText == "hello")

		// Replace
		editor.perform(.replace)
		#expect(editor.text == "goodbye world")
	}

	@Test("replace with regex captures expands template")
	func replaceWithCaptures() {
		let editor = makeEditor(
			text: "John Smith",
			findPattern: "(\\w+) (\\w+)",
			replacePattern: "$2, $1",
			findOptions: [.wrapAround, .regularExpression],
		)

		// Find the match (captures are stored)
		editor.perform(.findNext)
		#expect(editor.selectedText == "John Smith")
		#expect(!editor.matchCaptures.isEmpty)

		// Replace with capture expansion
		editor.perform(.replace)
		#expect(editor.text == "Smith, John")
	}

	@Test("replace without selection does nothing")
	func replaceNoSelection() {
		let editor = makeEditor(
			text: "hello",
			findPattern: "hello",
			replacePattern: "bye",
		)
		// Don't find first — caret is at 0 with empty selection
		editor.perform(.replace)
		#expect(editor.text == "hello")
	}

	// MARK: - Replace and Find

	@Test("replaceAndFind replaces then finds next")
	func replaceAndFind() {
		let editor = makeEditor(
			text: "aa bb aa",
			findPattern: "aa",
			replacePattern: "xx",
		)

		// Find first occurrence
		editor.perform(.findNext)
		#expect(editor.selections.primary?.start.offset == 0)

		// Replace and find next
		editor.perform(.replaceAndFind)

		// Text should have first "aa" replaced
		#expect(editor.text == "xx bb aa")

		// Selection should be on the second "aa"
		#expect(editor.selectedText == "aa")
	}

	// MARK: - Replace All

	@Test("replaceAll replaces all matches")
	func replaceAll() {
		let editor = makeEditor(
			text: "aa bb aa cc aa",
			findPattern: "aa",
			replacePattern: "xx",
		)

		editor.perform(.replaceAll)
		#expect(editor.text == "xx bb xx cc xx")
	}

	@Test("replaceAll with regex")
	func replaceAllRegex() {
		let editor = makeEditor(
			text: "foo123 bar456",
			findPattern: "(\\w+?)(\\d+)",
			replacePattern: "$1_$2",
			findOptions: [.regularExpression],
		)

		editor.perform(.replaceAll)
		#expect(editor.text == "foo_123 bar_456")
	}

	@Test("replaceAllInSelection replaces only within selection")
	func replaceAllInSelection() {
		let editor = makeEditor(
			text: "aa bb aa cc aa",
			findPattern: "aa",
			replacePattern: "xx",
		)

		// Select "aa bb aa" (bytes 0..<8)
		editor.selections = SelectionState([
			TextRange(
				anchor: editor.buffer.convert(offset: 0),
				head: editor.buffer.convert(offset: 8),
			),
		])

		editor.perform(.replaceAllInSelection)
		#expect(editor.text == "xx bb xx cc aa")
	}

	@Test("replaceAll with no matches does nothing")
	func replaceAllNoMatches() {
		let editor = makeEditor(
			text: "hello world",
			findPattern: "xyz",
			replacePattern: "abc",
		)

		editor.perform(.replaceAll)
		#expect(editor.text == "hello world")
	}

	// MARK: - Case Insensitive

	@Test("findNext with ignoreCase")
	func findNextIgnoreCase() {
		let editor = makeEditor(
			text: "Hello HELLO hello",
			findPattern: "hello",
			findOptions: [.wrapAround, .ignoreCase],
		)

		editor.perform(.findNext)
		#expect(editor.selectedText == "Hello")

		editor.perform(.findNext)
		#expect(editor.selectedText == "HELLO")

		editor.perform(.findNext)
		#expect(editor.selectedText == "hello")
	}

	// MARK: - Regex Find

	@Test("findNext with regex pattern")
	func findNextRegex() {
		let editor = makeEditor(
			text: "foo123 bar456",
			findPattern: "\\d+",
			findOptions: [.wrapAround, .regularExpression],
		)

		editor.perform(.findNext)
		#expect(editor.selectedText == "123")

		editor.perform(.findNext)
		#expect(editor.selectedText == "456")
	}

	// MARK: - Match Captures

	@Test("findNext stores match captures for regex")
	func matchCapturesStored() {
		let editor = makeEditor(
			text: "hello world",
			findPattern: "(hello) (world)",
			findOptions: [.regularExpression],
		)

		editor.perform(.findNext)
		#expect(editor.matchCaptures["1"] == "hello")
		#expect(editor.matchCaptures["2"] == "world")
	}

	@Test("findNext clears old captures")
	func matchCapturesCleared() {
		let editor = makeEditor(
			text: "abc def",
			findPattern: "(abc)",
			findOptions: [.wrapAround, .regularExpression],
		)

		editor.perform(.findNext)
		#expect(editor.matchCaptures["1"] == "abc")

		// Change find pattern and search again
		editor.clipboards.find.push(ClipboardEntry("def"))
		editor.findOptions = [.wrapAround]
		editor.perform(.findNext)
		// Non-regex match: captures should be empty (or just have "0")
		#expect(editor.matchCaptures["1"] == nil)
	}

	// MARK: - Undo Integration

	@Test("replaceAll is undoable")
	func replaceAllUndoable() {
		let editor = makeEditor(
			text: "aa bb aa",
			findPattern: "aa",
			replacePattern: "xx",
		)

		editor.perform(.replaceAll)
		#expect(editor.text == "xx bb xx")

		editor.undo()
		#expect(editor.text == "aa bb aa")
	}
}
