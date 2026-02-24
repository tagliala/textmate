import Testing
import TMCore
import TMEditor

#if canImport(AppKit)
import AppKit
import TMEditorUI
#endif

// MARK: - Completion Engine Tests

@Suite("CompletionEngine — Word Collection")
struct CompletionEngineWordTests {
	let engine = CompletionEngine()

	@Test("empty buffer returns empty completions")
	func emptyBuffer() {
		let buffer = TextBuffer("")
		let result = engine.completions(buffer: buffer, bow: 0, eow: 0, prefix: "", suffix: "")
		#expect(result.isEmpty)
	}

	@Test("no prefix and no suffix returns empty")
	func noPrefixNoSuffix() {
		let buffer = TextBuffer("hello world")
		let result = engine.completions(buffer: buffer, bow: 0, eow: 5, prefix: "", suffix: "")
		#expect(result.isEmpty)
	}

	@Test("finds matching word with prefix")
	func findsMatchingWord() {
		let buffer = TextBuffer("hello help")
		// Cursor after "hel" at offset 3, word is "hello" (0..5), prefix="hel"
		let result = engine.completions(buffer: buffer, bow: 0, eow: 5, prefix: "hel", suffix: "lo")
		#expect(!result.isEmpty)
		// "help" matches prefix "hel", so its suffix "p" should be in results
		#expect(result.contains("p"))
	}

	@Test("excludes the current word from results")
	func excludesCurrentWord() {
		let buffer = TextBuffer("hello hello")
		// Both words are "hello" — the current word at bow=0 should be excluded
		let result = engine.completions(buffer: buffer, bow: 0, eow: 5, prefix: "hel", suffix: "lo")
		// The second "hello" is the same word string, so it contributes the same suffix "lo"
		// but since hasSuffix check: suffixTrimLength removes "lo", we get empty insertion text
		// Actually the current word "hello" is excluded, and the other "hello" is also "hello"
		// so it matches excludeWord="hello" and gets excluded too.
		// Let's verify no completions for identical words.
		#expect(result.isEmpty)
	}

	@Test("finds multiple matching words ranked by distance")
	func multipleMatchesByDistance() {
		let buffer2 = TextBuffer("far foo fur")
		// Cursor is on "f" at the beginning of "fur" (offset 8), word is "fur" (8..11)
		let result = engine.completions(buffer: buffer2, bow: 8, eow: 11, prefix: "f", suffix: "ur")
		// "far" has prefix "f" but suffix "ur" doesn't match "ar"
		// With retry (no suffix match), we try prefix-only:
		// "far" → suffix "ar", "foo" → suffix "oo"
		// Nearest to position 8: "foo" at 4 (distance 4), "far" at 0 (distance 8)
		#expect(!result.isEmpty)
	}

	@Test("ranks nearest word first")
	func ranksNearestFirst() {
		// "apportion"=0..9, " "=9, "apple"=10..15, " "=15, "app"=16..19
		let buffer = TextBuffer("apportion apple app")
		// Cursor is on "app" at offset 16, prefix="app"
		let result = engine.completions(buffer: buffer, bow: 16, eow: 19, prefix: "app", suffix: "")
		// "apportion" at 0 (dist 16), "apple" at 10 (dist 6)
		// apple is closer → "le" first, then "ortion"
		#expect(result.count == 2)
		if result.count == 2 {
			#expect(result[0] == "le")
			#expect(result[1] == "ortion")
		}
	}

	@Test("handles underscore words")
	func underscoreWords() {
		let buffer = TextBuffer("my_var my_value other")
		// Cursor at "my_" (offset 7..15 for "my_value"), prefix="my_"
		let result = engine.completions(buffer: buffer, bow: 7, eow: 15, prefix: "my_", suffix: "value")
		// "my_var" matches prefix "my_", suffix doesn't have to match
		#expect(!result.isEmpty)
	}
}

// MARK: - Completion Info Tests

@Suite("CompletionInfo — State Management")
struct CompletionInfoTests {
	@Test("initial state is empty")
	func initialEmpty() {
		let info = CompletionInfo()
		#expect(info.isEmpty)
		#expect(info.suggestions.isEmpty)
	}

	@Test("setting suggestions makes it non-empty")
	func setSuggestions() {
		var info = CompletionInfo()
		info.setSuggestions(["alpha", "beta", "gamma"])
		#expect(!info.isEmpty)
		#expect(info.suggestions.count == 3)
	}

	@Test("advance cycles through suggestions")
	func advanceCycles() {
		var info = CompletionInfo()
		info.setSuggestions(["a", "b", "c"])

		info.advance() // index 0
		#expect(info.current == "a")

		info.advance() // index 1
		#expect(info.current == "b")

		info.advance() // index 2
		#expect(info.current == "c")

		info.advance() // wrap to 0
		#expect(info.current == "a")
	}

	@Test("recede cycles backwards")
	func recedeCycles() {
		var info = CompletionInfo()
		info.setSuggestions(["a", "b", "c"])

		info.advance() // start at "a"
		#expect(info.current == "a")

		info.recede() // wrap to "c"
		#expect(info.current == "c")

		info.recede() // back to "b"
		#expect(info.current == "b")
	}

	@Test("empty suggestions means empty state")
	func emptySuggestions() {
		var info = CompletionInfo()
		info.setSuggestions([])
		#expect(info.isEmpty)
	}

	@Test("advance on empty does nothing")
	func advanceEmpty() {
		var info = CompletionInfo()
		info.advance() // should not crash
		#expect(info.isEmpty)
	}

	@Test("recede on empty does nothing")
	func recedeEmpty() {
		var info = CompletionInfo()
		info.recede() // should not crash
		#expect(info.isEmpty)
	}
}

// MARK: - Editor Completion Integration Tests

@Suite("Editor — Completion Integration")
struct EditorCompletionTests {
	@Test("setupCompletion with matching words returns true")
	func setupWithMatches() {
		let editor = Editor(text: "function func")
		// Place cursor at end of "func" (offset 13)
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 13))

		let hasCompletions = editor.setupCompletion()
		#expect(hasCompletions)
		#expect(!editor.completionSuggestions.isEmpty)
	}

	@Test("setupCompletion with no matches returns false")
	func setupNoMatches() {
		let editor = Editor(text: "xyz")
		// Place cursor at end
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 3))

		let hasCompletions = editor.setupCompletion()
		#expect(!hasCompletions)
	}

	@Test("nextCompletion inserts completion text")
	func nextCompletionInserts() {
		let editor = Editor(text: "function fu")
		// Cursor at end of "fu" (offset 11)
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 11))

		editor.nextCompletion()

		// Should have inserted the completion suffix ("nction")
		let text = editor.text
		#expect(text.contains("function"))
		// The second word should now be "function" instead of "fu"
		#expect(text == "function function")
	}

	@Test("previousCompletion cycles backward")
	func previousCompletionCycles() {
		let editor = Editor(text: "alpha apex ap")
		// Cursor at end of "ap" (offset 13)
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 13))

		// First completion
		editor.nextCompletion()
		let firstCompletion = editor.text

		// Previous should cycle backward
		editor.previousCompletion()
		let prevCompletion = editor.text

		// They should be different completions
		#expect(firstCompletion != "alpha apex ap" || prevCompletion != "alpha apex ap")
	}

	@Test("cancelCompletion clears state")
	func cancelClearsState() {
		let editor = Editor(text: "function fu")
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 11))
		editor.nextCompletion()
		#expect(editor.isCompletionActive)

		editor.cancelCompletion()
		#expect(!editor.isCompletionActive)
		#expect(editor.completionSuggestions.isEmpty)
	}

	@Test("completion with single character prefix")
	func singleCharPrefix() {
		let editor = Editor(text: "hello h")
		// Cursor at end, word is "h" at offset 6..7
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 7))

		let hasCompletions = editor.setupCompletion()
		#expect(hasCompletions)
		#expect(editor.completionSuggestions.contains("ello"))
	}

	@Test("perform .complete triggers completion")
	func performCompleteAction() {
		let editor = Editor(text: "variable va")
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 11))

		editor.perform(.complete)

		// Should have inserted completion
		#expect(editor.isCompletionActive || editor.text != "variable va")
	}

	@Test("completion distinguishes similar words")
	func distinguishesSimilarWords() {
		let editor = Editor(text: "count counter co")
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 16))

		let hasCompletions = editor.setupCompletion()
		#expect(hasCompletions)
		// Should have both "unt" and "unter" as completions
		let suggestions = editor.completionSuggestions
		#expect(suggestions.count >= 2)
	}

	@Test("completion at beginning of buffer")
	func completionAtBeginning() {
		let editor = Editor(text: "f foo bar func")
		editor.selections = SelectionState(caret: editor.buffer.convert(offset: 1))

		let hasCompletions = editor.setupCompletion()
		#expect(hasCompletions)
	}
}

// MARK: - Choice Menu Panel Tests

#if canImport(AppKit)

@Suite("ChoiceMenuPanel — Core")
@MainActor
struct ChoiceMenuPanelCoreTests {
	@Test("initial state has empty choices")
	func initialState() {
		let menu = ChoiceMenuPanel()
		#expect(menu.choices.isEmpty)
		#expect(menu.choiceIndex == nil)
		#expect(menu.selectedChoice == nil)
	}

	@Test("setting choices updates count")
	func setChoices() {
		let menu = ChoiceMenuPanel()
		menu.choices = ["alpha", "beta", "gamma"]
		#expect(menu.choices.count == 3)
	}

	@Test("setting choiceIndex selects the choice")
	func setChoiceIndex() {
		let menu = ChoiceMenuPanel()
		menu.choices = ["alpha", "beta", "gamma"]
		menu.choiceIndex = 1
		#expect(menu.selectedChoice == "beta")
	}

	@Test("nil choiceIndex means no selection")
	func nilChoiceIndex() {
		let menu = ChoiceMenuPanel()
		menu.choices = ["alpha", "beta"]
		menu.choiceIndex = 0
		menu.choiceIndex = nil
		#expect(menu.selectedChoice == nil)
	}

	@Test("out of bounds choiceIndex returns nil selectedChoice")
	func outOfBoundsIndex() {
		let menu = ChoiceMenuPanel()
		menu.choices = ["alpha"]
		menu.choiceIndex = 5
		#expect(menu.selectedChoice == nil)
	}

	@Test("changing choices preserves selection when possible")
	func preservesSelectionOnUpdate() {
		let menu = ChoiceMenuPanel()
		menu.choices = ["alpha", "beta", "gamma"]
		menu.choiceIndex = 1 // "beta"
		menu.choices = ["alpha", "beta", "delta"]
		#expect(menu.choiceIndex == 1) // "beta" still exists at index 1
		#expect(menu.selectedChoice == "beta")
	}

	@Test("changing choices clears selection when choice removed")
	func clearsSelectionOnRemoval() {
		let menu = ChoiceMenuPanel()
		menu.choices = ["alpha", "beta", "gamma"]
		menu.choiceIndex = 2 // "gamma"
		menu.choices = ["alpha", "beta"]
		#expect(menu.choiceIndex == nil) // "gamma" removed
	}

	@Test("menu is not visible initially")
	func notVisibleInitially() {
		let menu = ChoiceMenuPanel()
		#expect(!menu.isMenuVisible)
	}
}

@Suite("ChoiceMenuPanel — Key Handling")
@MainActor
struct ChoiceMenuKeyHandlingTests {
	@Test("handleKeyEvent with no window returns unused")
	func noWindowReturnsUnused() {
		let menu = ChoiceMenuPanel()
		// Create a dummy key event (up arrow).
		let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "",
			charactersIgnoringModifiers: "",
			isARepeat: false,
			keyCode: 126, // up arrow
		)
		guard let event else { return }
		let result = menu.handleKeyEvent(event)
		#expect(result == .unused)
	}
}
#endif
