import Testing
import TMCore
@testable import TMEditor

// MARK: - EditorAction Tests

@Suite("EditorAction")
struct EditorActionTests {
	@Test("All actions have a raw value")
	func allActionsHaveRawValue() {
		for action in EditorAction.allCases {
			#expect(!action.rawValue.isEmpty)
		}
	}

	@Test("Selector mapping for common movement actions")
	func selectorMappingMovement() {
		#expect(EditorAction(selector: "moveBackward:") == .moveBackward)
		#expect(EditorAction(selector: "moveLeft:") == .moveBackward)
		#expect(EditorAction(selector: "moveForward:") == .moveForward)
		#expect(EditorAction(selector: "moveRight:") == .moveForward)
		#expect(EditorAction(selector: "moveUp:") == .moveUp)
		#expect(EditorAction(selector: "moveDown:") == .moveDown)
		#expect(EditorAction(selector: "moveWordBackward:") == .moveWordBackward)
		#expect(EditorAction(selector: "moveWordLeft:") == .moveWordBackward)
		#expect(EditorAction(selector: "moveToBeginningOfDocument:") == .moveToBeginOfDocument)
		#expect(EditorAction(selector: "moveToEndOfDocument:") == .moveToEndOfDocument)
	}

	@Test("Selector mapping for common selection extension actions")
	func selectorMappingSelectionExtension() {
		#expect(EditorAction(selector: "moveBackwardAndModifySelection:") == .moveBackwardAndModifySelection)
		#expect(EditorAction(selector: "moveForwardAndModifySelection:") == .moveForwardAndModifySelection)
		#expect(EditorAction(selector: "selectAll:") == .selectAll)
		#expect(EditorAction(selector: "selectWord:") == .selectWord)
	}

	@Test("Selector mapping for clipboard actions")
	func selectorMappingClipboard() {
		#expect(EditorAction(selector: "cut:") == .cut)
		#expect(EditorAction(selector: "copy:") == .copy)
		#expect(EditorAction(selector: "paste:") == .paste)
		#expect(EditorAction(selector: "yank:") == .yank)
	}

	@Test("Selector mapping for delete actions")
	func selectorMappingDelete() {
		#expect(EditorAction(selector: "deleteBackward:") == .deleteBackward)
		#expect(EditorAction(selector: "deleteForward:") == .deleteForward)
		#expect(EditorAction(selector: "deleteWordBackward:") == .deleteWordBackward)
		#expect(EditorAction(selector: "deleteWordForward:") == .deleteWordForward)
	}

	@Test("Unknown selector returns nil")
	func unknownSelectorReturnsNil() {
		#expect(EditorAction(selector: "someUnknownAction:") == nil)
		#expect(EditorAction(selector: "") == nil)
		#expect(EditorAction(selector: "doSomethingCrazy:") == nil)
	}

	@Test("Action classification: isMovement")
	func actionClassificationMovement() {
		#expect(EditorAction.moveBackward.isMovement)
		#expect(EditorAction.moveForward.isMovement)
		#expect(EditorAction.moveUp.isMovement)
		#expect(EditorAction.moveToEndOfDocument.isMovement)
		#expect(!EditorAction.cut.isMovement)
		#expect(!EditorAction.deleteBackward.isMovement)
	}

	@Test("Action classification: isSelectionExtension")
	func actionClassificationSelectionExtension() {
		#expect(EditorAction.moveBackwardAndModifySelection.isSelectionExtension)
		#expect(EditorAction.selectAll.isSelectionExtension)
		#expect(EditorAction.selectWord.isSelectionExtension)
		#expect(!EditorAction.moveBackward.isSelectionExtension)
	}

	@Test("Action classification: isDeletion")
	func actionClassificationDeletion() {
		#expect(EditorAction.deleteBackward.isDeletion)
		#expect(EditorAction.deleteForward.isDeletion)
		#expect(EditorAction.deleteWordBackward.isDeletion)
		#expect(EditorAction.deleteSelection.isDeletion)
		#expect(!EditorAction.cut.isDeletion)
	}

	@Test("Action classification: isClipboard")
	func actionClassificationClipboard() {
		#expect(EditorAction.cut.isClipboard)
		#expect(EditorAction.copy.isClipboard)
		#expect(EditorAction.paste.isClipboard)
		#expect(EditorAction.yank.isClipboard)
		#expect(!EditorAction.deleteBackward.isClipboard)
	}

	@Test("Action classification: isTextTransform")
	func actionClassificationTextTransform() {
		#expect(EditorAction.uppercase.isTextTransform)
		#expect(EditorAction.lowercase.isTextTransform)
		#expect(EditorAction.capitalize.isTextTransform)
		#expect(EditorAction.shiftLeft.isTextTransform)
		#expect(!EditorAction.cut.isTextTransform)
	}

	@Test("Implicit selection extension for delete actions")
	func implicitSelectionExtension() {
		#expect(EditorAction.deleteBackward.implicitSelectionExtension == .left)
		#expect(EditorAction.deleteForward.implicitSelectionExtension == .right)
		#expect(EditorAction.deleteWordBackward.implicitSelectionExtension == .wordLeft)
		#expect(EditorAction.deleteWordForward.implicitSelectionExtension == .wordRight)
		#expect(EditorAction.cut.implicitSelectionExtension == nil)
	}
}

// MARK: - Clipboard Tests

@Suite("Clipboard")
struct ClipboardTests {
	@Test("SimpleClipboard push and current")
	func simpleClipboardPushAndCurrent() {
		let clipboard = SimpleClipboard()
		#expect(clipboard.isEmpty)
		#expect(clipboard.current() == nil)

		clipboard.push(ClipboardEntry("hello"))
		#expect(!clipboard.isEmpty)
		#expect(clipboard.count == 1)
		#expect(clipboard.current()?.text == "hello")
	}

	@Test("SimpleClipboard history navigation")
	func simpleClipboardHistoryNavigation() {
		let clipboard = SimpleClipboard()
		clipboard.push(ClipboardEntry("first"))
		clipboard.push(ClipboardEntry("second"))
		clipboard.push(ClipboardEntry("third"))

		#expect(clipboard.current()?.text == "third")
		#expect(clipboard.previous()?.text == "second")
		#expect(clipboard.previous()?.text == "first")
		#expect(clipboard.previous()?.text == "first") // Already at start
		#expect(clipboard.next()?.text == "second")
		#expect(clipboard.next()?.text == "third")
		#expect(clipboard.next()?.text == "third") // Already at end
	}

	@Test("ClipboardEntry with options")
	func clipboardEntryWithOptions() {
		let entry = ClipboardEntry(
			contents: ["line1\n", "line2\n"],
			options: .init(isColumnar: true, indent: "\t", isComplete: true),
		)
		#expect(entry.contents.count == 2)
		#expect(entry.text == "line1\nline2\n")
		#expect(entry.options.isColumnar)
		#expect(entry.options.indent == "\t")
		#expect(entry.options.isComplete)
	}

	@Test("ClipboardEntry single string convenience")
	func clipboardEntrySingleString() {
		let entry = ClipboardEntry("hello world")
		#expect(entry.contents == ["hello world"])
		#expect(entry.text == "hello world")
		#expect(!entry.options.isColumnar)
	}

	@Test("ClipboardSet provides four clipboards")
	func clipboardSetProvidesFourClipboards() {
		let set = ClipboardSet()
		set.general.push(ClipboardEntry("general"))
		set.find.push(ClipboardEntry("find"))
		set.replace.push(ClipboardEntry("replace"))
		set.yank.push(ClipboardEntry("yank"))

		#expect(set.general.current()?.text == "general")
		#expect(set.find.current()?.text == "find")
		#expect(set.replace.current()?.text == "replace")
		#expect(set.yank.current()?.text == "yank")
	}
}

// MARK: - TextTransform Tests

@Suite("TextTransform")
struct TextTransformTests {
	@Test("Uppercase transform")
	func uppercase() {
		#expect(TextTransform.uppercase.apply(to: "hello world") == "HELLO WORLD")
		#expect(TextTransform.uppercase.apply(to: "Hello") == "HELLO")
		#expect(TextTransform.uppercase.apply(to: "") == "")
	}

	@Test("Lowercase transform")
	func lowercase() {
		#expect(TextTransform.lowercase.apply(to: "HELLO WORLD") == "hello world")
		#expect(TextTransform.lowercase.apply(to: "Hello") == "hello")
	}

	@Test("Capitalize transform")
	func capitalize() {
		#expect(TextTransform.capitalize.apply(to: "hello world") == "Hello World")
		#expect(TextTransform.capitalize.apply(to: "HELLO WORLD") == "Hello World")
		#expect(TextTransform.capitalize.apply(to: "one-two") == "One-Two")
	}

	@Test("Toggle case transform")
	func toggleCase() {
		#expect(TextTransform.toggleCase.apply(to: "Hello World") == "hELLO wORLD")
		#expect(TextTransform.toggleCase.apply(to: "abc") == "ABC")
		#expect(TextTransform.toggleCase.apply(to: "ABC") == "abc")
	}

	@Test("None transform returns input unchanged")
	func noneTransform() {
		#expect(TextTransform.none.apply(to: "hello") == "hello")
	}

	@Test("Unwrap text: single newlines become spaces")
	func unwrapText() {
		#expect(TextTransform.unwrap.apply(to: "hello\nworld") == "hello world")
		#expect(TextTransform.unwrap.apply(to: "hello\n\nworld") == "hello\n\nworld")
		#expect(TextTransform.unwrap.apply(to: "one\ntwo\nthree") == "one two three")
	}

	@Test("Shift left removes one indent level")
	func shiftLeft() {
		#expect(TextTransform.shiftLeft.apply(to: "\thello", tabSize: 4) == "hello")
		#expect(TextTransform.shiftLeft.apply(to: "    hello", tabSize: 4) == "hello")
		#expect(TextTransform.shiftLeft.apply(to: "  hello", tabSize: 4) == "hello")
		#expect(TextTransform.shiftLeft.apply(to: "hello", tabSize: 4) == "hello")
	}

	@Test("Shift right adds one indent level")
	func shiftRight() {
		#expect(TextTransform.shiftRight.apply(to: "hello", tabSize: 4, indentUsingSpaces: false) == "\thello")
		#expect(TextTransform.shiftRight.apply(to: "hello", tabSize: 4, indentUsingSpaces: true) == "    hello")
		#expect(TextTransform.shiftRight.apply(to: "", tabSize: 4) == "")
	}

	@Test("Shift preserves multi-line structure")
	func shiftMultiLine() {
		let input = "line1\nline2\nline3"
		let shifted = TextTransform.shiftRight.apply(to: input, tabSize: 4, indentUsingSpaces: false)
		#expect(shifted == "\tline1\n\tline2\n\tline3")

		let unshifted = TextTransform.shiftLeft.apply(to: shifted, tabSize: 4)
		#expect(unshifted == input)
	}

	@Test("Reformat wraps at column 20")
	func reformatWrapsAtColumn() {
		let input = "The quick brown fox jumps over the lazy dog"
		let result = TextTransform.reformat.apply(to: input, wrapColumn: 20)
		let lines = result.split(separator: "\n")
		for line in lines {
			#expect(line.count <= 20)
		}
	}
}

// MARK: - SnippetController Tests

@Suite("SnippetController")
struct SnippetControllerTests {
	@Test("Empty snippet controller")
	func emptyController() {
		let controller = SnippetController()
		#expect(controller.isEmpty)
		#expect(controller.current == nil)
		#expect(controller.choices.isEmpty)
		#expect(controller.isAtLastPlaceholder)
	}

	@Test("Push and navigate tab stops")
	func pushAndNavigate() {
		let controller = SnippetController()

		let zero = TMCore.TextPosition.zero
		let pos10 = TMCore.TextPosition(line: 0, column: 10, offset: 10)
		let pos20 = TMCore.TextPosition(line: 0, column: 20, offset: 20)

		let session = SnippetController.Session(
			snippetText: "function() { }",
			tabStops: [
				SnippetController.TabStop(
					index: 1,
					range: TMCore.TextRange(
						anchor: zero,
						head: pos10,
					),
					placeholder: "name",
				),
				SnippetController.TabStop(
					index: 2,
					range: TMCore.TextRange(
						anchor: pos10,
						head: pos20,
					),
					placeholder: "body",
				),
				SnippetController.TabStop(
					index: 0,
					range: TMCore.TextRange(caret: pos20),
					placeholder: "",
				),
			],
		)

		controller.push(session)
		#expect(!controller.isEmpty)
		#expect(controller.current?.currentTabStop?.index == 1)

		// Advance to tab stop 2
		let range2 = controller.next()
		#expect(range2 != nil)
		#expect(controller.current?.currentTabStop?.index == 2)

		// Advance to exit tab stop (0) — should pop session
		let range0 = controller.next()
		#expect(range0 != nil)
		#expect(controller.isEmpty)
	}

	@Test("Previous tab stop navigation")
	func previousNavigation() {
		let controller = SnippetController()
		let zero = TMCore.TextPosition.zero
		let pos10 = TMCore.TextPosition(line: 0, column: 10, offset: 10)

		let session = SnippetController.Session(
			snippetText: "test",
			tabStops: [
				SnippetController.TabStop(index: 1, range: TMCore.TextRange(caret: zero)),
				SnippetController.TabStop(index: 2, range: TMCore.TextRange(caret: pos10)),
				SnippetController.TabStop(index: 0, range: TMCore.TextRange(caret: pos10)),
			],
		)

		controller.push(session)
		controller.next() // Move to tab stop 2

		let backRange = controller.previous()
		#expect(backRange != nil)
		#expect(controller.current?.currentTabStop?.index == 1)
	}

	@Test("Clear removes all sessions")
	func clearSessions() {
		let controller = SnippetController()
		let zero = TMCore.TextPosition.zero
		let session = SnippetController.Session(
			snippetText: "test",
			tabStops: [
				SnippetController.TabStop(index: 1, range: TMCore.TextRange(caret: zero)),
			],
		)
		controller.push(session)
		#expect(!controller.isEmpty)

		controller.clear()
		#expect(controller.isEmpty)
	}
}

// MARK: - MacroRecorder Tests

@Suite("MacroRecorder")
struct MacroRecorderTests {
	@Test("Initial state")
	func initialState() {
		let recorder = MacroRecorder()
		#expect(!recorder.isRecording)
		#expect(recorder.lastMacro == nil)
	}

	@Test("Start and stop recording")
	func startAndStopRecording() {
		let recorder = MacroRecorder()
		recorder.startRecording()
		#expect(recorder.isRecording)

		recorder.record(action: .moveForward)
		recorder.record(action: .deleteBackward)

		let macro = recorder.stopRecording()
		#expect(!recorder.isRecording)
		#expect(macro != nil)
		#expect(macro?.actions.count == 2)
		#expect(macro?.actions[0].action == .moveForward)
		#expect(macro?.actions[1].action == .deleteBackward)
	}

	@Test("Toggle recording")
	func toggleRecording() {
		let recorder = MacroRecorder()

		let result1 = recorder.toggleRecording()
		#expect(result1 == nil) // Started recording
		#expect(recorder.isRecording)

		recorder.record(action: .moveUp)

		let result2 = recorder.toggleRecording()
		#expect(result2 != nil) // Stopped recording
		#expect(!recorder.isRecording)
		#expect(result2?.actions.count == 1)
	}

	@Test("Recording with text")
	func recordingWithText() {
		let recorder = MacroRecorder()
		recorder.startRecording()
		recorder.record(action: .nop, text: "hello")
		let macro = recorder.stopRecording()
		#expect(macro?.actions[0].text == "hello")
	}

	@Test("Actions not recorded when not recording")
	func actionsNotRecordedWhenNotRecording() {
		let recorder = MacroRecorder()
		recorder.record(action: .moveForward)
		#expect(recorder.lastMacro == nil)
	}

	@Test("Replay calls handler for each action")
	func replayCallsHandler() {
		let recorder = MacroRecorder()
		recorder.startRecording()
		recorder.record(action: .moveForward)
		recorder.record(action: .moveBackward)
		recorder.stopRecording()

		var replayedActions: [EditorAction] = []
		let result = recorder.replay { action in
			replayedActions.append(action.action)
		}

		#expect(result)
		#expect(replayedActions == [.moveForward, .moveBackward])
	}

	@Test("Replay returns false when no macro available")
	func replayReturnsFalseWhenNoMacro() {
		let recorder = MacroRecorder()
		let result = recorder.replay { _ in }
		#expect(!result)
	}

	@Test("Last macro is preserved across recordings")
	func lastMacroPreserved() {
		let recorder = MacroRecorder()
		recorder.startRecording()
		recorder.record(action: .moveForward)
		recorder.stopRecording()

		#expect(recorder.lastMacro?.actions.count == 1)

		recorder.startRecording()
		recorder.record(action: .moveUp)
		recorder.record(action: .moveDown)
		recorder.stopRecording()

		#expect(recorder.lastMacro?.actions.count == 2)
	}
}

// MARK: - Editor Tests

@Suite("Editor")
struct EditorTests {
	@Test("Editor initializes with empty text")
	func emptyEditor() {
		let editor = Editor()
		#expect(editor.text == "")
		#expect(editor.selections.isSingleCaret)
		#expect(editor.selections.primary?.head == TMCore.TextPosition.zero)
	}

	@Test("Editor initializes with text")
	func editorWithText() {
		let editor = Editor(text: "Hello, World!")
		#expect(editor.text == "Hello, World!")
	}

	@Test("Insert text at cursor")
	func insertTextAtCursor() {
		let editor = Editor()
		editor.insertText("Hello")
		#expect(editor.text == "Hello")
		#expect(editor.selections.primary?.head.offset == 5)
	}

	@Test("Insert text replaces selection")
	func insertTextReplacesSelection() {
		let editor = Editor(text: "Hello, World!")
		// Select "World"
		editor.selections = SelectionState([
			TMCore.TextRange(
				anchor: TMCore.TextPosition(line: 0, column: 7, offset: 7),
				head: TMCore.TextPosition(line: 0, column: 12, offset: 12),
			),
		])
		editor.insertText("Swift")
		#expect(editor.text == "Hello, Swift!")
	}

	@Test("Move to end of document")
	func moveToEndOfDocument() {
		let editor = Editor(text: "Line 1\nLine 2\nLine 3")
		editor.perform(.moveToEndOfDocument)
		#expect(editor.selections.primary?.head.offset == editor.buffer.size)
	}

	@Test("Move to beginning of document")
	func moveToBeginOfDocument() {
		let editor = Editor(text: "Line 1\nLine 2")
		editor.perform(.moveToEndOfDocument)
		editor.perform(.moveToBeginOfDocument)
		#expect(editor.selections.primary?.head.offset == 0)
	}

	@Test("Move right advances cursor by one character")
	func moveRight() {
		let editor = Editor(text: "abc")
		editor.perform(.moveForward)
		#expect(editor.selections.primary?.head.offset == 1)
		editor.perform(.moveForward)
		#expect(editor.selections.primary?.head.offset == 2)
	}

	@Test("Move left moves cursor back by one character")
	func moveLeft() {
		let editor = Editor(text: "abc")
		editor.perform(.moveToEndOfDocument)
		editor.perform(.moveBackward)
		#expect(editor.selections.primary?.head.offset == 2)
	}

	@Test("Move down goes to next line")
	func moveDown() {
		let editor = Editor(text: "Line 1\nLine 2\nLine 3")
		editor.perform(.moveDown)
		#expect(editor.selections.primary?.head.line == 1)
	}

	@Test("Move up goes to previous line")
	func moveUp() {
		let editor = Editor(text: "Line 1\nLine 2")
		editor.perform(.moveToEndOfDocument)
		editor.perform(.moveUp)
		#expect(editor.selections.primary?.head.line == 0)
	}

	@Test("Select all selects entire buffer")
	func selectAll() throws {
		let editor = Editor(text: "Hello")
		editor.perform(.selectAll)
		let sel = try #require(editor.selections.primary)
		#expect(sel.start.offset == 0)
		#expect(sel.end.offset == 5)
	}

	@Test("Delete backward removes character before cursor")
	func deleteBackward() {
		let editor = Editor(text: "abc")
		editor.perform(.moveToEndOfDocument)
		editor.perform(.deleteBackward)
		#expect(editor.text == "ab")
	}

	@Test("Delete forward removes character after cursor")
	func deleteForward() {
		let editor = Editor(text: "abc")
		editor.perform(.deleteForward)
		#expect(editor.text == "bc")
	}

	@Test("Delete selection removes selected text")
	func deleteSelection() {
		let editor = Editor(text: "Hello, World!")
		editor.perform(.selectAll)
		editor.perform(.deleteSelection)
		#expect(editor.text == "")
	}

	@Test("Cut copies and deletes selection")
	func cutCopiesAndDeletes() {
		let editor = Editor(text: "Hello")
		editor.perform(.selectAll)
		editor.perform(.cut)
		#expect(editor.text == "")
		#expect(editor.clipboards.general.current()?.text == "Hello")
	}

	@Test("Copy copies without deleting")
	func copyCopiesWithoutDeleting() {
		let editor = Editor(text: "Hello")
		editor.perform(.selectAll)
		editor.perform(.copy)
		#expect(editor.text == "Hello")
		#expect(editor.clipboards.general.current()?.text == "Hello")
	}

	@Test("Paste inserts clipboard content")
	func pasteInsertsContent() {
		let editor = Editor(text: "")
		editor.clipboards.general.push(ClipboardEntry("World"))
		editor.perform(.paste)
		#expect(editor.text == "World")
	}

	@Test("Cut and paste round-trip")
	func cutAndPasteRoundTrip() {
		let editor = Editor(text: "Hello, World!")
		editor.perform(.selectAll)
		editor.perform(.cut)
		#expect(editor.text == "")
		editor.perform(.paste)
		#expect(editor.text == "Hello, World!")
	}

	@Test("Uppercase transform")
	func uppercaseTransform() {
		let editor = Editor(text: "hello world")
		editor.perform(.selectAll)
		editor.perform(.uppercase)
		#expect(editor.text == "HELLO WORLD")
	}

	@Test("Lowercase transform")
	func lowercaseTransform() {
		let editor = Editor(text: "HELLO WORLD")
		editor.perform(.selectAll)
		editor.perform(.lowercase)
		#expect(editor.text == "hello world")
	}

	@Test("Transpose characters")
	func transposeCharacters() {
		let editor = Editor(text: "ab")
		// Move cursor to position 1 (between 'a' and 'b')
		editor.perform(.moveForward)
		editor.perform(.transposeCharacters)
		#expect(editor.text == "ba")
	}

	@Test("Insert newline with auto-indent")
	func insertNewlineWithIndent() {
		let editor = Editor(text: "    hello")
		editor.perform(.moveToEndOfLine)
		editor.perform(.insertNewline)
		// Should insert newline followed by same indentation
		#expect(editor.text == "    hello\n    ")
	}

	@Test("Insert tab with spaces")
	func insertTabWithSpaces() {
		let editor = Editor()
		editor.indentUsingSpaces = true
		editor.tabSize = 4
		editor.perform(.insertTabIgnoringFieldEditor)
		#expect(editor.text == "    ")
	}

	@Test("Insert tab character")
	func insertTabCharacter() {
		let editor = Editor()
		editor.indentUsingSpaces = false
		editor.perform(.insertTabIgnoringFieldEditor)
		#expect(editor.text == "\t")
	}

	@Test("Set and swap mark")
	func setAndSwapMark() throws {
		let editor = Editor(text: "Hello, World!")
		// Set mark at position 0
		editor.perform(.setMark)
		#expect(editor.mark?.offset == 0)

		// Move to end
		editor.perform(.moveToEndOfDocument)
		let endPos = try #require(editor.selections.primary?.head)

		// Swap with mark
		editor.perform(.swapWithMark)
		#expect(editor.selections.primary?.head.offset == 0)
		#expect(editor.mark?.offset == endPos.offset)
	}

	@Test("Select to mark")
	func selectToMark() throws {
		let editor = Editor(text: "Hello")
		editor.perform(.setMark)
		editor.perform(.moveToEndOfDocument)
		editor.perform(.selectToMark)

		let sel = try #require(editor.selections.primary)
		#expect(!sel.isEmpty)
	}

	@Test("Move to begin of line")
	func moveToBeginOfLine() {
		let editor = Editor(text: "  Hello")
		editor.perform(.moveToEndOfLine)
		editor.perform(.moveToBeginOfLine)
		#expect(editor.selections.primary?.head.offset == 0)
	}

	@Test("Move to end of line")
	func moveToEndOfLine() {
		let editor = Editor(text: "Hello\nWorld")
		editor.perform(.moveToEndOfLine)
		#expect(editor.selections.primary?.head.offset == 5)
	}

	@Test("Move to begin of indented line toggles between indent and BOL")
	func moveToBeginOfIndentedLine() {
		let editor = Editor(text: "    Hello")
		editor.perform(.moveToEndOfLine)

		// First: should go to end of indent (offset 4)
		editor.perform(.moveToBeginOfIndentedLine)
		#expect(editor.selections.primary?.head.offset == 4)

		// Second: should go to beginning of line (offset 0)
		editor.perform(.moveToBeginOfIndentedLine)
		#expect(editor.selections.primary?.head.offset == 0)
	}

	@Test("Extending selection preserves anchor")
	func extendingSelectionPreservesAnchor() throws {
		let editor = Editor(text: "Hello, World!")
		let startPos = try #require(editor.selections.primary?.head)

		editor.perform(.moveForwardAndModifySelection)
		editor.perform(.moveForwardAndModifySelection)
		editor.perform(.moveForwardAndModifySelection)

		let sel = try #require(editor.selections.primary)
		#expect(sel.anchor == startPos)
		#expect(sel.head.offset == 3)
		#expect(!sel.isEmpty)
	}

	@Test("Move word forward")
	func moveWordForward() throws {
		let editor = Editor(text: "hello world test")
		editor.perform(.moveWordForward)
		// Should move past "hello" to the space or the start of "world"
		let offset = try #require(editor.selections.primary?.head.offset)
		#expect(offset >= 5 && offset <= 6)
	}

	@Test("Move word backward")
	func moveWordBackward() throws {
		let editor = Editor(text: "hello world")
		editor.perform(.moveToEndOfDocument)
		editor.perform(.moveWordBackward)
		let offset = try #require(editor.selections.primary?.head.offset)
		#expect(offset >= 5 && offset <= 6) // At or near "world"
	}

	@Test("Toggle column selection")
	func toggleColumnSelection() {
		let editor = Editor(text: "Hello, World!")
		// First select something
		editor.selections = SelectionState([
			TMCore.TextRange(
				anchor: TMCore.TextPosition(line: 0, column: 0, offset: 0),
				head: TMCore.TextPosition(line: 0, column: 5, offset: 5),
			),
		])
		editor.perform(.toggleColumnSelection)
		#expect(editor.selections.primary?.isColumnar == true)

		editor.perform(.toggleColumnSelection)
		#expect(editor.selections.primary?.isColumnar == false)
	}

	@Test("Deselect last with multiple selections")
	func deselectLastMultipleSelections() {
		let editor = Editor(text: "Hello World")
		editor.selections = SelectionState([
			TMCore.TextRange(caret: TMCore.TextPosition(line: 0, column: 0, offset: 0)),
			TMCore.TextRange(caret: TMCore.TextPosition(line: 0, column: 6, offset: 6)),
		])
		#expect(editor.selections.count == 2)
		editor.perform(.deselectLast)
		#expect(editor.selections.count == 1)
	}

	@Test("Copy to find clipboard")
	func copyToFindClipboard() {
		let editor = Editor(text: "search term")
		editor.perform(.selectAll)
		editor.perform(.copySelectionToFindClipboard)
		#expect(editor.clipboards.find.current()?.text == "search term")
	}

	@Test("Nop does nothing")
	func nopDoesNothing() {
		let editor = Editor(text: "Hello")
		let before = editor.text
		let beforeSel = editor.selections
		editor.perform(.nop)
		#expect(editor.text == before)
		#expect(editor.selections == beforeSel)
	}

	@Test("Delete word backward")
	func deleteWordBackward() {
		let editor = Editor(text: "hello world")
		editor.perform(.moveToEndOfDocument)
		editor.perform(.deleteWordBackward)
		// Should delete "world" (and possibly trailing space)
		let text = editor.text
		#expect(text.hasPrefix("hello"))
		#expect(text.count < "hello world".count)
	}

	@Test("Shift right adds indent to selected lines")
	func shiftRightAddsIndent() {
		let editor = Editor(text: "line1\nline2\nline3")
		editor.indentUsingSpaces = false
		editor.perform(.selectAll)
		editor.perform(.shiftRight)
		let lines = editor.text.split(separator: "\n", omittingEmptySubsequences: false)
		for line in lines where !line.isEmpty {
			#expect(line.hasPrefix("\t"))
		}
	}

	@Test("Shift left removes indent from selected lines")
	func shiftLeftRemovesIndent() {
		let editor = Editor(text: "\tline1\n\tline2\n\tline3")
		editor.perform(.selectAll)
		editor.perform(.shiftLeft)
		let lines = editor.text.split(separator: "\n", omittingEmptySubsequences: false)
		for line in lines where !line.isEmpty {
			#expect(!line.hasPrefix("\t"))
		}
	}

	@Test("Move selection down")
	func moveSelectionDown() {
		let editor = Editor(text: "line1\nline2\nline3")
		// Select line1
		editor.selections = SelectionState([
			TMCore.TextRange(
				anchor: TMCore.TextPosition(line: 0, column: 0, offset: 0),
				head: TMCore.TextPosition(line: 0, column: 5, offset: 5),
			),
		])
		editor.perform(.moveSelectionDown)
		// line1 should now be on line 2
		let lines = editor.text.split(separator: "\n")
		#expect(lines.contains("line1"))
	}
}

// MARK: - Editor Undo/Redo Tests

@Suite("Editor Undo/Redo")
struct EditorUndoRedoTests {
	@Test("Undo reverses insert")
	func undoReversesInsert() {
		let editor = Editor()
		editor.insertText("Hello")
		#expect(editor.text == "Hello")
		editor.undo()
		#expect(editor.text == "")
	}

	@Test("Redo restores after undo")
	func redoRestoresAfterUndo() {
		let editor = Editor()
		editor.insertText("Hello")
		editor.undo()
		#expect(editor.text == "")
		editor.redo()
		#expect(editor.text == "Hello")
	}

	@Test("Can undo and can redo flags")
	func canUndoCanRedo() {
		let editor = Editor()
		#expect(!editor.canUndo)
		#expect(!editor.canRedo)

		editor.insertText("test")
		#expect(editor.canUndo)
		#expect(!editor.canRedo)

		editor.undo()
		#expect(!editor.canUndo)
		#expect(editor.canRedo)
	}
}

// MARK: - Editor Multi-Cursor Tests

@Suite("Editor Multi-Cursor")
struct EditorMultiCursorTests {
	@Test("Insert text at multiple cursors")
	func insertAtMultipleCursors() {
		let editor = Editor(text: "aa bb")
		editor.selections = SelectionState([
			TMCore.TextRange(caret: TMCore.TextPosition(line: 0, column: 0, offset: 0)),
			TMCore.TextRange(caret: TMCore.TextPosition(line: 0, column: 3, offset: 3)),
		])
		editor.insertText("X")
		// Both cursors insert "X"
		#expect(editor.text.contains("X"))
		// "aa bb" → "Xaa Xbb" — offset 0 gets X, offset 3 gets X
		#expect(editor.text == "Xaa Xbb")
	}
}

// MARK: - Editor Soft-Line Movement Tests

/// A mock layout delegate that provides fixed soft-line boundaries
/// to test the editor's beginOfSoftLine / endOfSoftLine handling.
final class MockLayoutDelegate: EditorLayoutDelegate, @unchecked Sendable {
	/// Fixed soft-line begin/end offsets per hard line.
	/// Each entry: (lineStartOffset, softLineRanges as [(beginOffset, endOffset)]).
	var softLineMap: [Int: [(begin: Int, end: Int)]] = [:]

	func pageUp(from position: TMCore.TextPosition) -> TMCore.TextPosition {
		position
	}

	func pageDown(from position: TMCore.TextPosition) -> TMCore.TextPosition {
		position
	}

	func beginOfSoftLine(from position: TMCore.TextPosition) -> TMCore.TextPosition? {
		guard let ranges = softLineMap[position.line] else { return nil }
		for range in ranges.reversed() {
			if position.offset >= range.begin, position.offset <= range.end {
				return TMCore.TextPosition(line: position.line, column: range.begin, offset: range.begin)
			}
		}
		return nil
	}

	func endOfSoftLine(from position: TMCore.TextPosition) -> TMCore.TextPosition? {
		guard let ranges = softLineMap[position.line] else { return nil }
		for range in ranges {
			if position.offset >= range.begin, position.offset <= range.end {
				return TMCore.TextPosition(line: position.line, column: range.end, offset: range.end)
			}
		}
		return nil
	}
}

@Suite("Editor Soft-Line Movement")
struct EditorSoftLineMovementTests {
	@Test("beginOfSoftLine uses layout delegate when available")
	func beginOfSoftLineUsesDelegate() throws {
		let editor = Editor(text: "abcdefghij klmnopqrst uvwxyz")
		let delegate = MockLayoutDelegate()
		// Simulate two soft lines: [0..10), [11..28)
		delegate.softLineMap = [0: [(begin: 0, end: 10), (begin: 11, end: 28)]]
		editor.layoutDelegate = delegate

		// Place caret at offset 15 (in second soft line)
		editor.selections = SelectionState([
			TMCore.TextRange(caret: TMCore.TextPosition(line: 0, column: 15, offset: 15)),
		])
		editor.perform(.moveToBeginOfSoftLine)

		// Should move to offset 11 (begin of soft line), not offset 0
		let head = try #require(editor.selections.primary?.head)
		#expect(head.offset == 11)
	}

	@Test("endOfSoftLine uses layout delegate when available")
	func endOfSoftLineUsesDelegate() throws {
		let editor = Editor(text: "abcdefghij klmnopqrst uvwxyz")
		let delegate = MockLayoutDelegate()
		delegate.softLineMap = [0: [(begin: 0, end: 10), (begin: 11, end: 28)]]
		editor.layoutDelegate = delegate

		// Place caret at offset 5 (in first soft line)
		editor.selections = SelectionState([
			TMCore.TextRange(caret: TMCore.TextPosition(line: 0, column: 5, offset: 5)),
		])
		editor.perform(.moveToEndOfSoftLine)

		// Should move to offset 10, not end of hard line (28)
		let head = try #require(editor.selections.primary?.head)
		#expect(head.offset == 10)
	}

	@Test("beginOfSoftLine falls back to BOL without delegate")
	func beginOfSoftLineFallback() throws {
		let editor = Editor(text: "Hello World")
		// No layout delegate set

		editor.selections = SelectionState([
			TMCore.TextRange(caret: TMCore.TextPosition(line: 0, column: 5, offset: 5)),
		])
		editor.perform(.moveToBeginOfSoftLine)

		// Falls back to beginning of hard line
		let head = try #require(editor.selections.primary?.head)
		#expect(head.offset == 0)
	}

	@Test("endOfSoftLine falls back to EOL without delegate")
	func endOfSoftLineFallback() throws {
		let editor = Editor(text: "Hello World")

		editor.selections = SelectionState([
			TMCore.TextRange(caret: TMCore.TextPosition(line: 0, column: 5, offset: 5)),
		])
		editor.perform(.moveToEndOfSoftLine)

		// Falls back to end of hard line
		let head = try #require(editor.selections.primary?.head)
		#expect(head.offset == 11)
	}
}

// MARK: - Toggle Comment Tests

@Suite("Editor — Toggle Comment")
struct ToggleCommentTests {
	@Test("toggleLineComment adds prefix to single line")
	func addCommentSingleLine() {
		let editor = Editor(text: "hello\n")
		editor.selections = SelectionState(caret: TMCore.TextPosition(line: 0, column: 0, offset: 0))
		editor.toggleLineComment(prefix: "// ")
		#expect(editor.text == "// hello\n")
	}

	@Test("toggleLineComment removes prefix from already-commented line")
	func removeCommentSingleLine() {
		let editor = Editor(text: "// hello\n")
		editor.selections = SelectionState(caret: TMCore.TextPosition(line: 0, column: 0, offset: 0))
		editor.toggleLineComment(prefix: "// ")
		#expect(editor.text == "hello\n")
	}

	@Test("toggleLineComment adds prefix to multiple selected lines")
	func addCommentMultipleLines() {
		let editor = Editor(text: "aaa\nbbb\nccc\n")
		// Select lines 0-1.
		editor.selections = SelectionState([
			TMCore.TextRange(
				anchor: TMCore.TextPosition(line: 0, column: 0, offset: 0),
				head: TMCore.TextPosition(line: 1, column: 3, offset: 7),
			),
		])
		editor.toggleLineComment(prefix: "# ")
		#expect(editor.text == "# aaa\n# bbb\nccc\n")
	}

	@Test("toggleLineComment removes prefix from all-commented lines")
	func removeCommentMultipleLines() {
		let editor = Editor(text: "# aaa\n# bbb\nccc\n")
		editor.selections = SelectionState([
			TMCore.TextRange(
				anchor: TMCore.TextPosition(line: 0, column: 0, offset: 0),
				head: TMCore.TextPosition(line: 1, column: 5, offset: 11),
			),
		])
		editor.toggleLineComment(prefix: "# ")
		#expect(editor.text == "aaa\nbbb\nccc\n")
	}

	@Test("toggleLineComment preserves indentation when adding")
	func preserveIndentWhenAdding() {
		let editor = Editor(text: "\tfoo\n\t\tbar\n")
		editor.selections = SelectionState([
			TMCore.TextRange(
				anchor: TMCore.TextPosition(line: 0, column: 0, offset: 0),
				head: TMCore.TextPosition(line: 1, column: 4, offset: 9),
			),
		])
		editor.toggleLineComment(prefix: "// ")
		#expect(editor.text == "\t// foo\n\t// \tbar\n")
	}

	@Test("toggleLineComment with empty prefix does nothing")
	func emptyPrefixNoOp() {
		let editor = Editor(text: "hello\n")
		editor.selections = SelectionState(caret: TMCore.TextPosition(line: 0, column: 0, offset: 0))
		editor.toggleLineComment(prefix: "")
		#expect(editor.text == "hello\n")
	}

	@Test("toggleLineComment excludes line when selection ends at column 0")
	func excludeLineAtColumn0() {
		let editor = Editor(text: "aaa\nbbb\nccc\n")
		// Selection ends at start of line 2 — should only comment lines 0-1.
		editor.selections = SelectionState([
			TMCore.TextRange(
				anchor: TMCore.TextPosition(line: 0, column: 0, offset: 0),
				head: TMCore.TextPosition(line: 2, column: 0, offset: 8),
			),
		])
		editor.toggleLineComment(prefix: "// ")
		#expect(editor.text == "// aaa\n// bbb\nccc\n")
	}
}
