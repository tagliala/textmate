/// All editor actions, mirroring TextMate's C++ `action_t` enum.
///
/// Actions are organized into categories: movement, selection extension,
/// deletion, clipboard, text transformation, find/replace, marks,
/// tab/newline/indent, completion, and line movement.
public enum EditorAction: String, Sendable, CaseIterable {
	// MARK: - Movement

	case moveBackward
	case moveForward
	case moveFreehandedBackward
	case moveFreehandedForward
	case moveUp
	case moveDown
	case moveToBeginOfSelection
	case moveToEndOfSelection
	case moveSubWordLeft
	case moveSubWordRight
	case moveWordBackward
	case moveWordForward
	case moveToBeginOfSoftLine
	case moveToEndOfSoftLine
	case moveToBeginOfIndentedLine
	case moveToEndOfIndentedLine
	case moveToBeginOfLine
	case moveToEndOfLine
	case moveToBeginOfParagraph
	case moveToEndOfParagraph
	case moveToBeginOfHardParagraph
	case moveToEndOfHardParagraph
	case moveToBeginOfTypingPair
	case moveToEndOfTypingPair
	case moveToBeginOfColumn
	case moveToEndOfColumn
	case pageUp
	case pageDown
	case moveToBeginOfDocument
	case moveToEndOfDocument

	// MARK: - Selection Extension

	case moveBackwardAndModifySelection
	case moveForwardAndModifySelection
	case moveFreehandedBackwardAndModifySelection
	case moveFreehandedForwardAndModifySelection
	case moveUpAndModifySelection
	case moveDownAndModifySelection
	case moveSubWordLeftAndModifySelection
	case moveSubWordRightAndModifySelection
	case moveWordBackwardAndModifySelection
	case moveWordForwardAndModifySelection
	case moveToBeginOfSoftLineAndModifySelection
	case moveToEndOfSoftLineAndModifySelection
	case moveToBeginOfIndentedLineAndModifySelection
	case moveToEndOfIndentedLineAndModifySelection
	case moveToBeginOfLineAndModifySelection
	case moveToEndOfLineAndModifySelection
	case moveToBeginOfParagraphAndModifySelection
	case moveToEndOfParagraphAndModifySelection
	case moveToBeginOfTypingPairAndModifySelection
	case moveToEndOfTypingPairAndModifySelection
	case moveToBeginOfColumnAndModifySelection
	case moveToEndOfColumnAndModifySelection
	case pageUpAndModifySelection
	case pageDownAndModifySelection
	case moveToBeginOfDocumentAndModifySelection
	case moveToEndOfDocumentAndModifySelection
	case selectWord
	case selectWordOrTypingPair
	case selectScope
	case selectSoftLine
	case selectLineExcludingNewline
	case selectLine
	case selectParagraph
	case selectTypingPair
	case selectAll

	// MARK: - Delete

	case deleteBackward
	case deleteForward
	case deleteSubWordLeft
	case deleteSubWordRight
	case deleteWordBackward
	case deleteWordForward
	case deleteToBeginOfIndentedLine
	case deleteToEndOfIndentedLine
	case deleteToBeginOfLine
	case deleteToEndOfLine
	case deleteToBeginOfParagraph
	case deleteToEndOfParagraph
	case deleteToBeginOfTypingPair
	case deleteToEndOfTypingPair
	case deleteSelection
	case deleteTabTrigger

	// MARK: - Clipboard

	case cut
	case copy
	case copySelectionToFindClipboard
	case copySelectionToReplaceClipboard
	case paste
	case pasteNext
	case pastePrevious
	case pasteFromHistoryAndFind
	case yank

	// MARK: - Text Transformation

	case transposeCharacters
	case transposeWords
	case transposeUpperLower
	case capitalize
	case changeCaseOfLetter
	case changeCaseOfWord
	case uppercase
	case lowercase
	case reformatText
	case reformatTextAndJustify
	case unwrapText
	case shiftLeft
	case shiftRight
	case indent

	// MARK: - Find / Replace

	case findNext
	case findPrevious
	case findNextAndModifySelection
	case findPreviousAndModifySelection
	case findAll
	case findAllInSelection
	case replace
	case replaceAll
	case replaceAllInSelection
	case replaceAndFind

	// MARK: - Marks

	case setMark
	case deleteToMark
	case selectToMark
	case swapWithMark

	// MARK: - Completion

	case complete
	case nextCompletion
	case previousCompletion

	// MARK: - Tab / Newline / Indent

	case insertTab
	case insertBacktab
	case insertTabIgnoringFieldEditor
	case insertNewline
	case insertNewlineIgnoringFieldEditor

	// MARK: - Move Selection

	case moveSelectionUp
	case moveSelectionDown
	case moveSelectionLeft
	case moveSelectionRight

	// MARK: - Other

	case toggleComment
	case toggleColumnSelection
	case deselectLast
	case toggleMacroRecording
	case toggleFoldingAtLevel
	case nop
}

// MARK: - Selector Mapping

public extension EditorAction {
	/// Map a Cocoa selector string (e.g. `"moveBackward:"`) to an `EditorAction`.
	///
	/// Returns `nil` if the selector is not recognized.
	init?(selector: String) {
		switch selector {
		// Movement
		case "moveBackward:", "moveLeft:":
			self = .moveBackward
		case "moveForward:", "moveRight:":
			self = .moveForward
		case "moveUp:":
			self = .moveUp
		case "moveDown:":
			self = .moveDown
		case "moveWordBackward:", "moveWordLeft:":
			self = .moveWordBackward
		case "moveWordForward:", "moveWordRight:":
			self = .moveWordForward
		case "moveSubWordLeft:":
			self = .moveSubWordLeft
		case "moveSubWordRight:":
			self = .moveSubWordRight
		case "moveToBeginningOfLine:":
			self = .moveToBeginOfSoftLine
		case "moveToEndOfLine:":
			self = .moveToEndOfSoftLine
		case "moveToBeginningOfIndentedLine:":
			self = .moveToBeginOfIndentedLine
		case "moveToEndOfIndentedLine:":
			self = .moveToEndOfIndentedLine
		case "moveToLeftEndOfLine:":
			self = .moveToBeginOfLine
		case "moveToRightEndOfLine:":
			self = .moveToEndOfLine
		case "moveToBeginningOfParagraph:":
			self = .moveToBeginOfParagraph
		case "moveToEndOfParagraph:":
			self = .moveToEndOfParagraph
		case "moveToBeginningOfBlock:":
			self = .moveToBeginOfHardParagraph
		case "moveToEndOfBlock:":
			self = .moveToEndOfHardParagraph
		case "moveToBeginningOfColumn:":
			self = .moveToBeginOfColumn
		case "moveToEndOfColumn:":
			self = .moveToEndOfColumn
		case "moveToBeginningOfDocument:":
			self = .moveToBeginOfDocument
		case "moveToEndOfDocument:":
			self = .moveToEndOfDocument
		case "pageUp:":
			self = .pageUp
		case "pageDown:":
			self = .pageDown
		// Selection Extension
		case "moveBackwardAndModifySelection:", "moveLeftAndModifySelection:":
			self = .moveBackwardAndModifySelection
		case "moveForwardAndModifySelection:", "moveRightAndModifySelection:":
			self = .moveForwardAndModifySelection
		case "moveUpAndModifySelection:":
			self = .moveUpAndModifySelection
		case "moveDownAndModifySelection:":
			self = .moveDownAndModifySelection
		case "moveWordBackwardAndModifySelection:", "moveWordLeftAndModifySelection:":
			self = .moveWordBackwardAndModifySelection
		case "moveWordForwardAndModifySelection:", "moveWordRightAndModifySelection:":
			self = .moveWordForwardAndModifySelection
		case "moveSubWordLeftAndModifySelection:":
			self = .moveSubWordLeftAndModifySelection
		case "moveSubWordRightAndModifySelection:":
			self = .moveSubWordRightAndModifySelection
		case "moveToBeginningOfLineAndModifySelection:":
			self = .moveToBeginOfSoftLineAndModifySelection
		case "moveToEndOfLineAndModifySelection:":
			self = .moveToEndOfSoftLineAndModifySelection
		case "moveToBeginningOfIndentedLineAndModifySelection:":
			self = .moveToBeginOfIndentedLineAndModifySelection
		case "moveToEndOfIndentedLineAndModifySelection:":
			self = .moveToEndOfIndentedLineAndModifySelection
		case "moveToLeftEndOfLineAndModifySelection:":
			self = .moveToBeginOfLineAndModifySelection
		case "moveToRightEndOfLineAndModifySelection:":
			self = .moveToEndOfLineAndModifySelection
		case "moveToBeginningOfParagraphAndModifySelection:":
			self = .moveToBeginOfParagraphAndModifySelection
		case "moveToEndOfParagraphAndModifySelection:":
			self = .moveToEndOfParagraphAndModifySelection
		case "moveToBeginningOfDocumentAndModifySelection:":
			self = .moveToBeginOfDocumentAndModifySelection
		case "moveToEndOfDocumentAndModifySelection:":
			self = .moveToEndOfDocumentAndModifySelection
		case "pageUpAndModifySelection:":
			self = .pageUpAndModifySelection
		case "pageDownAndModifySelection:":
			self = .pageDownAndModifySelection
		case "selectWord:":
			self = .selectWord
		case "selectParagraph:":
			self = .selectParagraph
		case "selectHardLine:":
			self = .selectLine
		case "selectCurrentScope:":
			self = .selectScope
		case "selectBlock:":
			self = .selectTypingPair
		case "selectAll:":
			self = .selectAll
		// Delete
		case "deleteBackward:":
			self = .deleteBackward
		case "deleteForward:":
			self = .deleteForward
		case "deleteWordBackward:":
			self = .deleteWordBackward
		case "deleteWordForward:":
			self = .deleteWordForward
		case "deleteSubWordLeft:":
			self = .deleteSubWordLeft
		case "deleteSubWordRight:":
			self = .deleteSubWordRight
		case "deleteToBeginningOfLine:":
			self = .deleteToBeginOfIndentedLine
		case "deleteToEndOfLine:":
			self = .deleteToEndOfIndentedLine
		case "deleteToBeginningOfParagraph:":
			self = .deleteToBeginOfParagraph
		case "deleteToEndOfParagraph:":
			self = .deleteToEndOfParagraph
		// Clipboard
		case "cut:":
			self = .cut
		case "copy:":
			self = .copy
		case "paste:":
			self = .paste
		case "pasteNext:":
			self = .pasteNext
		case "pastePrevious:":
			self = .pastePrevious
		case "yank:":
			self = .yank
		case "copySelectionToFindPboard:":
			self = .copySelectionToFindClipboard
		case "copySelectionToReplacePboard:":
			self = .copySelectionToReplaceClipboard
		// Transform
		case "transpose:":
			self = .transposeCharacters
		case "capitalizeWord:":
			self = .capitalize
		case "changeCaseOfLetter:":
			self = .changeCaseOfLetter
		case "changeCaseOfWord:":
			self = .changeCaseOfWord
		case "uppercaseWord:":
			self = .uppercase
		case "lowercaseWord:":
			self = .lowercase
		case "shiftLeft:":
			self = .shiftLeft
		case "shiftRight:":
			self = .shiftRight
		case "indent:":
			self = .indent
		case "reformatText:":
			self = .reformatText
		case "reformatTextAndJustify:":
			self = .reformatTextAndJustify
		case "unwrapText:":
			self = .unwrapText
		// Tab / Newline
		case "insertTab:":
			self = .insertTab
		case "insertBacktab:":
			self = .insertBacktab
		case "insertTabIgnoringFieldEditor:":
			self = .insertTabIgnoringFieldEditor
		case "insertNewline:":
			self = .insertNewline
		case "insertNewlineIgnoringFieldEditor:":
			self = .insertNewlineIgnoringFieldEditor
		// Find
		case "findNext:":
			self = .findNext
		case "findPrevious:":
			self = .findPrevious
		case "findNextAndModifySelection:":
			self = .findNextAndModifySelection
		case "findPreviousAndModifySelection:":
			self = .findPreviousAndModifySelection
		case "findAll:":
			self = .findAll
		case "findAllInSelection:":
			self = .findAllInSelection
		case "replace:":
			self = .replace
		case "replaceAll:":
			self = .replaceAll
		case "replaceAndFind:":
			self = .replaceAndFind
		// Marks
		case "setMark:":
			self = .setMark
		case "deleteToMark:":
			self = .deleteToMark
		case "selectToMark:":
			self = .selectToMark
		case "swapWithMark:":
			self = .swapWithMark
		// Completion
		case "complete:":
			self = .complete
		case "nextCompletion:":
			self = .nextCompletion
		case "previousCompletion:":
			self = .previousCompletion
		// Selection manipulation
		case "toggleComment:":
			self = .toggleComment
		case "toggleColumnSelection:":
			self = .toggleColumnSelection
		case "deselectLast:":
			self = .deselectLast
		// Move Selection
		case "moveSelectionUp:":
			self = .moveSelectionUp
		case "moveSelectionDown:":
			self = .moveSelectionDown
		case "moveSelectionLeft:":
			self = .moveSelectionLeft
		case "moveSelectionRight:":
			self = .moveSelectionRight
		// Macro
		case "toggleMacroRecording:":
			self = .toggleMacroRecording
		case "nop:":
			self = .nop
		default:
			return nil
		}
	}
}

// MARK: - Action Classification

public extension EditorAction {
	/// Whether this action is a movement action (moves the caret without extending selection).
	var isMovement: Bool {
		switch self {
		case .moveBackward, .moveForward, .moveFreehandedBackward, .moveFreehandedForward,
		     .moveUp, .moveDown, .moveToBeginOfSelection, .moveToEndOfSelection,
		     .moveSubWordLeft, .moveSubWordRight, .moveWordBackward, .moveWordForward,
		     .moveToBeginOfSoftLine, .moveToEndOfSoftLine,
		     .moveToBeginOfIndentedLine, .moveToEndOfIndentedLine,
		     .moveToBeginOfLine, .moveToEndOfLine,
		     .moveToBeginOfParagraph, .moveToEndOfParagraph,
		     .moveToBeginOfHardParagraph, .moveToEndOfHardParagraph,
		     .moveToBeginOfTypingPair, .moveToEndOfTypingPair,
		     .moveToBeginOfColumn, .moveToEndOfColumn,
		     .pageUp, .pageDown,
		     .moveToBeginOfDocument, .moveToEndOfDocument:
			true
		default:
			false
		}
	}

	/// Whether this action extends the current selection.
	var isSelectionExtension: Bool {
		switch self {
		case .moveBackwardAndModifySelection, .moveForwardAndModifySelection,
		     .moveFreehandedBackwardAndModifySelection, .moveFreehandedForwardAndModifySelection,
		     .moveUpAndModifySelection, .moveDownAndModifySelection,
		     .moveSubWordLeftAndModifySelection, .moveSubWordRightAndModifySelection,
		     .moveWordBackwardAndModifySelection, .moveWordForwardAndModifySelection,
		     .moveToBeginOfSoftLineAndModifySelection, .moveToEndOfSoftLineAndModifySelection,
		     .moveToBeginOfIndentedLineAndModifySelection, .moveToEndOfIndentedLineAndModifySelection,
		     .moveToBeginOfLineAndModifySelection, .moveToEndOfLineAndModifySelection,
		     .moveToBeginOfParagraphAndModifySelection, .moveToEndOfParagraphAndModifySelection,
		     .moveToBeginOfTypingPairAndModifySelection, .moveToEndOfTypingPairAndModifySelection,
		     .moveToBeginOfColumnAndModifySelection, .moveToEndOfColumnAndModifySelection,
		     .pageUpAndModifySelection, .pageDownAndModifySelection,
		     .moveToBeginOfDocumentAndModifySelection, .moveToEndOfDocumentAndModifySelection,
		     .selectWord, .selectWordOrTypingPair, .selectScope,
		     .selectSoftLine, .selectLineExcludingNewline, .selectLine,
		     .selectParagraph, .selectTypingPair, .selectAll:
			true
		default:
			false
		}
	}

	/// Whether this action deletes text.
	var isDeletion: Bool {
		switch self {
		case .deleteBackward, .deleteForward,
		     .deleteSubWordLeft, .deleteSubWordRight,
		     .deleteWordBackward, .deleteWordForward,
		     .deleteToBeginOfIndentedLine, .deleteToEndOfIndentedLine,
		     .deleteToBeginOfLine, .deleteToEndOfLine,
		     .deleteToBeginOfParagraph, .deleteToEndOfParagraph,
		     .deleteToBeginOfTypingPair, .deleteToEndOfTypingPair,
		     .deleteSelection, .deleteTabTrigger:
			true
		default:
			false
		}
	}

	/// Whether this action involves the clipboard.
	var isClipboard: Bool {
		switch self {
		case .cut, .copy, .copySelectionToFindClipboard, .copySelectionToReplaceClipboard,
		     .paste, .pasteNext, .pastePrevious, .pasteFromHistoryAndFind, .yank:
			true
		default:
			false
		}
	}

	/// Whether this action transforms text in place.
	var isTextTransform: Bool {
		switch self {
		case .transposeCharacters, .transposeWords, .transposeUpperLower,
		     .capitalize, .changeCaseOfLetter, .changeCaseOfWord,
		     .uppercase, .lowercase,
		     .reformatText, .reformatTextAndJustify, .unwrapText,
		     .shiftLeft, .shiftRight, .indent:
			true
		default:
			false
		}
	}

	/// Whether this action involves find/replace operations.
	var isFindReplace: Bool {
		switch self {
		case .findNext, .findPrevious,
		     .findNextAndModifySelection, .findPreviousAndModifySelection,
		     .findAll, .findAllInSelection,
		     .replace, .replaceAll, .replaceAllInSelection, .replaceAndFind:
			true
		default:
			false
		}
	}

	/// The selection extension type needed before this delete/transform action,
	/// or `nil` if the action doesn't require implicit selection extension.
	var implicitSelectionExtension: SelectionExtensionUnit? {
		switch self {
		case .deleteBackward: .left
		case .deleteForward: .right
		case .deleteSubWordLeft: .subWordLeft
		case .deleteSubWordRight: .subWordRight
		case .deleteWordBackward: .wordLeft
		case .deleteWordForward: .wordRight
		case .deleteToBeginOfIndentedLine: .beginOfIndentedLine
		case .deleteToEndOfIndentedLine: .endOfIndentedLine
		case .deleteToBeginOfLine: .beginOfLine
		case .deleteToEndOfLine: .endOfLine
		case .deleteToBeginOfParagraph: .beginOfParagraph
		case .deleteToEndOfParagraph: .endOfParagraph
		case .deleteToBeginOfTypingPair: .beginOfTypingPair
		case .deleteToEndOfTypingPair: .endOfTypingPair
		default: nil
		}
	}
}

// MARK: - Selection Extension Unit

/// The unit by which selections are extended (used for `extend_if_empty`).
public enum SelectionExtensionUnit: Sendable {
	case left
	case right
	case freehandedLeft
	case freehandedRight
	case up
	case down
	case subWordLeft
	case subWordRight
	case wordLeft
	case wordRight
	case beginOfSoftLine
	case endOfSoftLine
	case beginOfIndentedLine
	case endOfIndentedLine
	case beginOfLine
	case endOfLine
	case beginOfParagraph
	case endOfParagraph
	case beginOfTypingPair
	case endOfTypingPair
	case beginOfColumn
	case endOfColumn
	case beginOfDocument
	case endOfDocument
	case pageUp
	case pageDown
	case word
	case wordOrTypingPair
	case scope
	case softLine
	case lineExcludingNewline
	case line
	case paragraph
	case typingPair
	case all
}

// MARK: - Movement Unit

/// The unit by which the caret is moved.
public enum MovementUnit: Sendable {
	case left
	case right
	case freehandedLeft
	case freehandedRight
	case up
	case down
	case beginOfSelection
	case endOfSelection
	case subWordLeft
	case subWordRight
	case wordLeft
	case wordRight
	case beginOfSoftLine
	case endOfSoftLine
	case beginOfIndentedLine
	case endOfIndentedLine
	case beginOfLine
	case endOfLine
	case beginOfParagraph
	case endOfParagraph
	case beginOfHardParagraph
	case endOfHardParagraph
	case beginOfTypingPair
	case endOfTypingPair
	case beginOfColumn
	case endOfColumn
	case pageUp
	case pageDown
	case beginOfDocument
	case endOfDocument
	case nowhere
}
