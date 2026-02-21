import Foundation
import TMCore
import TMSearchReplace

public typealias TextRange = TMCore.TextRange

/// The core text editor engine.
///
/// Manages the text buffer, selections, clipboard operations, snippet
/// navigation, macro recording, and action dispatch. This is the
/// Swift counterpart of TextMate's C++ `ng::editor_t`.
///
/// The editor operates on byte offsets through `TextBuffer` and translates
/// between positions and offsets as needed. Multi-cursor editing is supported
/// via `SelectionState`.
public final class Editor: @unchecked Sendable {
	// MARK: - Properties

	/// The underlying text buffer.
	public let buffer: TextBuffer

	/// The undo manager for this editor.
	public let undoManager: TextUndoManager

	/// The current selection state (supports multiple cursors).
	public var selections: SelectionState

	/// The four editor clipboards.
	public let clipboards: ClipboardSet

	/// The snippet controller managing active snippet sessions.
	public let snippetController: SnippetController

	/// The macro recorder.
	public let macroRecorder: MacroRecorder

	/// Bracket pair tracker for auto-pairing (auto-close brackets/quotes).
	public let pairTracker: BracketPairTracker = .init()

	/// The mark position (set with Ctrl-Space, used by deleteToMark/selectToMark/swapWithMark).
	public var mark: TextPosition?

	/// Whether "overwrite" (typeover) mode is enabled.
	public var isOverwriteMode: Bool = false

	/// Tab size in spaces.
	public var tabSize: Int = 4

	/// Whether to indent using spaces instead of tab characters.
	public var indentUsingSpaces: Bool = false

	/// Column at which to wrap text (for reformat operations).
	public var wrapColumn: Int = 80

	/// Options for find operations (regex, case-insensitive, etc.).
	///
	/// These options are applied when dispatching find/replace actions.
	/// The find clipboard entry provides the search string; these options
	/// control matching behavior.
	public var findOptions: FindOptions = [.wrapAround]

	/// Capture groups from the most recent single-match find operation.
	///
	/// Used by `replace` to expand capture references (e.g. `$1`) in
	/// the replacement template.
	public private(set) var matchCaptures: [String: String] = [:]

	/// Delegate for layout-dependent operations.
	public weak var layoutDelegate: EditorLayoutDelegate?

	/// Provider for grammar-aware indentation on newline.
	/// Given a line number, returns the indent string for a new line inserted after it.
	/// When `nil`, falls back to copying the current line's leading whitespace.
	public var indentProvider: ((Int) -> String)?

	/// Tracks the current completion session state.
	public var completionInfo = CompletionInfo()

	// MARK: - Init

	/// Creates an editor with the given initial text.
	///
	/// - Parameters:
	///   - text: The initial buffer content.
	///   - clipboards: The clipboard set to use (defaults to a new set).
	public init(text: String = "", clipboards: ClipboardSet = ClipboardSet()) {
		buffer = TextBuffer(text)
		undoManager = TextUndoManager(buffer: buffer)
		self.clipboards = clipboards
		snippetController = SnippetController()
		macroRecorder = MacroRecorder()

		let pos = TextPosition.zero
		selections = SelectionState(caret: pos)
		buffer.addCallback(pairTracker)
	}

	/// Creates an editor wrapping an existing buffer.
	///
	/// - Parameters:
	///   - buffer: The text buffer to edit.
	///   - clipboards: The clipboard set to use.
	public init(buffer: TextBuffer, clipboards: ClipboardSet = ClipboardSet()) {
		self.buffer = buffer
		undoManager = TextUndoManager(buffer: buffer)
		self.clipboards = clipboards
		snippetController = SnippetController()
		macroRecorder = MacroRecorder()

		let pos = TextPosition.zero
		selections = SelectionState(caret: pos)
		buffer.addCallback(pairTracker)
	}

	// MARK: - Content Access

	/// The full buffer content as a string.
	public var text: String {
		buffer.string
	}

	/// The text within the given range.
	public func contentOfRange(_ range: TextRange) -> String {
		buffer.substring(from: range.start.offset, to: range.end.offset)
	}

	/// The currently selected text (from the primary selection).
	public var selectedText: String? {
		guard let sel = selections.primary, !sel.isEmpty else { return nil }
		return contentOfRange(sel)
	}

	// MARK: - Action Dispatch

	/// Performs an editor action.
	///
	/// This is the main dispatch point, mirroring TextMate's C++ `editor_t::perform()`.
	/// Actions are dispatched to the appropriate subsystem: movement, selection
	/// extension, deletion, clipboard, transform, find/replace, marks, etc.
	public func perform(_ action: EditorAction) {
		// Record the action if recording a macro.
		if macroRecorder.isRecording {
			macroRecorder.record(action: action)
		}

		switch action {
		// MARK: Movement

		case _ where action.isMovement:
			performMovement(action)

		// MARK: Selection Extension
		case _ where action.isSelectionExtension:
			performSelectionExtension(action)

		// MARK: Delete
		case _ where action.isDeletion:
			performDelete(action)

		// MARK: Clipboard
		case .cut:
			performCut()
		case .copy:
			performCopy()
		case .copySelectionToFindClipboard:
			performCopyToFindClipboard()
		case .copySelectionToReplaceClipboard:
			performCopyToReplaceClipboard()
		case .paste:
			performPaste()
		case .pasteNext:
			performPasteNext()
		case .pastePrevious:
			performPastePrevious()
		case .pasteFromHistoryAndFind:
			performPasteFromHistoryAndFind()
		case .yank:
			performYank()

		// MARK: Text Transform
		case _ where action.isTextTransform:
			performTextTransform(action)

		// MARK: Find/Replace
		case _ where action.isFindReplace:
			performFindReplace(action)

		// MARK: Marks
		case .setMark:
			performSetMark()
		case .deleteToMark:
			performDeleteToMark()
		case .selectToMark:
			performSelectToMark()
		case .swapWithMark:
			performSwapWithMark()

		// MARK: Completion
		case .complete, .nextCompletion, .previousCompletion:
			performCompletion(action)

		// MARK: Tab / Newline
		case .insertTab:
			performInsertTab()
		case .insertBacktab:
			performInsertBacktab()
		case .insertTabIgnoringFieldEditor:
			performInsertTabRaw()
		case .insertNewline:
			performInsertNewline()
		case .insertNewlineIgnoringFieldEditor:
			performInsertNewlineRaw()

		// MARK: Move Selection
		case .moveSelectionUp:
			performMoveSelection(deltaLine: -1)
		case .moveSelectionDown:
			performMoveSelection(deltaLine: 1)
		case .moveSelectionLeft:
			performMoveSelection(deltaColumn: -1)
		case .moveSelectionRight:
			performMoveSelection(deltaColumn: 1)

		// MARK: Other
		case .toggleColumnSelection:
			performToggleColumnSelection()
		case .deselectLast:
			performDeselectLast()
		case .toggleMacroRecording:
			macroRecorder.toggleRecording()
		case .toggleFoldingAtLevel:
			break // Folding is handled by the layout/view layer
		case .nop:
			break
		default:
			break // Actions handled by classification predicates above
		}
	}

	// MARK: - Text Insertion

	/// Inserts text at each cursor position, replacing any selections.
	///
	/// This is the fundamental text insertion method. All insert operations
	/// (typed characters, paste, etc.) flow through here.
	public func insertText(_ string: String) {
		guard !string.isEmpty || hasSelection else { return }

		// Record for macros
		if macroRecorder.isRecording {
			macroRecorder.record(
				action: .nop,
				text: string,
			)
		}

		undoManager.beginUndoGroup(selections: selections)
		let newRanges = replaceSelections(with: string)
		undoManager.endUndoGroup(selections: newRanges)

		selections = newRanges

		propagateSnippetMirrors()
	}

	/// Whether any selection is non-empty.
	public var hasSelection: Bool {
		selections.selections.contains { !$0.isEmpty }
	}

	// MARK: - Snippet Mirror Propagation

	/// Propagates the current tab stop content to any mirrors in the snippet.
	///
	/// After a text edit is complete, this reads the current tab stop's text
	/// from the buffer and asks `SnippetState` to cascade it to mirrors.
	/// Resulting mirror updates are applied directly to the buffer.
	public func propagateSnippetMirrors() {
		guard snippetController.hasActiveMirrors,
		      let session = snippetController.current,
		      let tabStop = session.currentTabStop
		else { return }

		// Read the current tab stop's content from the buffer.
		let from = tabStop.range.start.offset
		let to = tabStop.range.end.offset
		guard from >= 0, to >= from, to <= buffer.size else { return }
		let content = buffer.substring(from: from, to: to)

		// Get mirror updates from the snippet controller.
		let mirrorUpdates = snippetController.replaceCurrentField(with: content)

		// Apply mirror updates to the buffer (already sorted end-to-start).
		for update in mirrorUpdates {
			guard update.from >= 0, update.to >= update.from, update.to <= buffer.size else {
				continue
			}
			_ = buffer.replace(from: update.from, to: update.to, with: update.text)
			snippetController.adjustForEdit(
				at: update.from,
				oldLength: update.to - update.from,
				newLength: update.text.utf8.count,
			)
		}

		// Refresh tab stop ranges from snippet state to match final buffer positions.
		snippetController.refreshTabStops()

		// Convert offset-only TextPositions to proper line/column positions.
		if let updated = snippetController.current {
			for (i, stop) in updated.tabStops.enumerated() {
				let anchor = buffer.convert(offset: min(stop.range.anchor.offset, buffer.size))
				let head = buffer.convert(offset: min(stop.range.head.offset, buffer.size))
				snippetController.updateTabStopRange(at: i, to: TextRange(anchor: anchor, head: head))
			}
		}
	}

	// MARK: - Insert with Auto-Pairing

	/// A typing pair (opener + closer) for auto-pairing.
	public struct TypingPair: Sendable, Equatable {
		public let opener: String
		public let closer: String

		public init(_ opener: String, _ closer: String) {
			self.opener = opener
			self.closer = closer
		}
	}

	/// Default smart typing pairs used when no scope-specific pairs are configured.
	public static let defaultSmartTypingPairs: [TypingPair] = [
		TypingPair("(", ")"),
		TypingPair("[", "]"),
		TypingPair("{", "}"),
		TypingPair("\"", "\""),
		TypingPair("'", "'"),
	]

	/// Inserts text with auto-pairing support.
	///
	/// Mimics the C++ `insert_with_pairing` from `editor.cc`:
	/// 1. If the caret sits at a tracked closer and the typed string matches → skip over.
	/// 2. If there is a selection and a pair is found → surround the selection.
	/// 3. If the next character is a word character → plain insert.
	/// 4. For same-char pairs (quotes) → only pair if the count on the line is even.
	/// 5. Otherwise → insert both opener and closer, place cursor between them.
	///
	/// - Parameters:
	///   - string: The typed string (usually a single character).
	///   - pairs: The smart typing pairs for the current scope.
	public func insertWithPairing(_ string: String, pairs: [TypingPair]) {
		guard !string.isEmpty else { return }

		// Find matching pair for this string.
		let matchedPair = pairs.first { $0.opener == string }

		undoManager.beginUndoGroup(selections: selections)

		let sortedSels = selections.selections.sorted { $0.start.offset > $1.start.offset }
		var newRanges: [TextRange] = []

		for sel in sortedSels {
			let from = sel.start.offset
			let to = sel.end.offset

			// 1. Skip over tracked closer.
			if sel.isEmpty, pairTracker.isLast(at: from) {
				let nextEnd = from < buffer.size
					? nextCharacterBoundary(after: from)
					: from
				let nextChar = from < buffer.size
					? buffer.substring(from: from, to: nextEnd)
					: ""
				if nextChar == string {
					// Move past the closer and remove tracking.
					pairTracker.remove(at: from)
					let endPos = buffer.convert(offset: nextEnd)
					newRanges.append(TextRange(caret: endPos))
					continue
				}
			}

			// 2. Surround selection with pair.
			if !sel.isEmpty, let pair = matchedPair {
				let combined = pair.opener + buffer.substring(from: from, to: to) + pair.closer
				let end = buffer.replace(from: from, to: to, with: combined)
				snippetController.adjustForEdit(at: from, oldLength: to - from, newLength: combined.utf8.count)
				// Select the inner content (excluding opener/closer).
				let innerStart = from + pair.opener.utf8.count
				let innerEnd = end - pair.closer.utf8.count
				newRanges.append(TextRange(
					anchor: buffer.convert(offset: innerStart),
					head: buffer.convert(offset: innerEnd),
				))
				continue
			}

			guard let pair = matchedPair else {
				// No matching pair — plain insert.
				let end = buffer.replace(from: from, to: to, with: string)
				snippetController.adjustForEdit(at: from, oldLength: to - from, newLength: string.utf8.count)
				newRanges.append(TextRange(caret: buffer.convert(offset: end)))
				continue
			}

			// 3. Next char is word char → plain insert.
			if to < buffer.size, isWordCharacter(at: to) {
				let end = buffer.replace(from: from, to: to, with: string)
				snippetController.adjustForEdit(at: from, oldLength: to - from, newLength: string.utf8.count)
				newRanges.append(TextRange(caret: buffer.convert(offset: end)))
				continue
			}

			// 4. Same-char pairs (quotes): only pair if even count on line.
			if pair.opener == pair.closer {
				let pos = buffer.convert(offset: from)
				let lineStart = buffer.lineStart(pos.line)
				let lineEnd = buffer.lineEnd(pos.line)
				let lineContent = buffer.substring(from: lineStart, to: lineEnd)
				let count = lineContent.components(separatedBy: pair.opener).count - 1
				if count % 2 != 0 {
					// Odd count → closing, just insert the single char.
					let end = buffer.replace(from: from, to: to, with: string)
					snippetController.adjustForEdit(at: from, oldLength: to - from, newLength: string.utf8.count)
					newRanges.append(TextRange(caret: buffer.convert(offset: end)))
					continue
				}
			}

			// 5. Insert both opener + closer, cursor between.
			let both = pair.opener + pair.closer
			let end = buffer.replace(from: from, to: to, with: both)
			snippetController.adjustForEdit(at: from, oldLength: to - from, newLength: both.utf8.count)
			let cursorPos = from + pair.opener.utf8.count
			let closerPos = end - pair.closer.utf8.count
			pairTracker.addPair(first: cursorPos, last: closerPos)
			newRanges.append(TextRange(caret: buffer.convert(offset: cursorPos)))
		}

		undoManager.endUndoGroup(selections: SelectionState(newRanges))
		selections = SelectionState(newRanges)

		propagateSnippetMirrors()
	}
}

// MARK: - Movement

extension Editor {
	private func performMovement(_ action: EditorAction) {
		guard let unit = action.movementUnit else { return }

		var newRanges: [TextRange] = []
		for sel in selections.selections {
			let target: TextPosition
			if !sel.isEmpty, unit.collapsesSelection {
				// Collapse to the edge in the direction of movement
				target = unit.isLeftward ? sel.start : sel.end
			} else {
				let from = sel.head
				target = movePosition(from, by: unit)
			}
			newRanges.append(TextRange(caret: target))
		}
		selections = SelectionState(newRanges)
	}

	/// Moves a position by the given movement unit.
	func movePosition(_ pos: TextPosition, by unit: MovementUnit) -> TextPosition {
		let offset = pos.offset

		switch unit {
		case .left:
			guard offset > 0 else { return pos }
			let newOffset = previousCharacterBoundary(before: offset)
			return buffer.convert(offset: newOffset)

		case .right:
			guard offset < buffer.size else { return pos }
			let newOffset = nextCharacterBoundary(after: offset)
			return buffer.convert(offset: newOffset)

		case .up:
			guard pos.line > 0 else { return positionAt(line: 0, preferredColumn: pos.column) }
			return positionAt(line: pos.line - 1, preferredColumn: pos.column)

		case .down:
			guard pos.line < buffer.lines - 1 else {
				return buffer.convert(offset: buffer.size)
			}
			return positionAt(line: pos.line + 1, preferredColumn: pos.column)

		case .wordLeft:
			return positionAtWordBoundary(before: offset)

		case .wordRight:
			return positionAtWordBoundary(after: offset)

		case .subWordLeft:
			return positionAtSubWordBoundary(before: offset)

		case .subWordRight:
			return positionAtSubWordBoundary(after: offset)

		case .beginOfSoftLine:
			// Use layout delegate for visual soft-line start when available.
			if let delegate = layoutDelegate,
			   let softPos = delegate.beginOfSoftLine(from: pos)
			{
				return softPos
			}
			// Fallback: soft line == hard line
			return buffer.convert(offset: buffer.lineStart(pos.line))

		case .endOfSoftLine:
			if let delegate = layoutDelegate,
			   let softPos = delegate.endOfSoftLine(from: pos)
			{
				return softPos
			}
			return buffer.convert(offset: buffer.lineEnd(pos.line))

		case .beginOfLine:
			return buffer.convert(offset: buffer.lineStart(pos.line))

		case .endOfLine:
			return buffer.convert(offset: buffer.lineEnd(pos.line))

		case .beginOfIndentedLine:
			let bol = buffer.lineStart(pos.line)
			let eoi = endOfLeadingWhitespace(line: pos.line)
			// If caret is past indent, go to indent; otherwise go to BOL.
			return buffer.convert(offset: offset > eoi ? eoi : bol)

		case .endOfIndentedLine:
			let eoi = endOfLeadingWhitespace(line: pos.line)
			let eol = buffer.lineEnd(pos.line)
			return buffer.convert(offset: offset < eoi ? eoi : eol)

		case .beginOfParagraph:
			return buffer.convert(offset: buffer.lineStart(pos.line))

		case .endOfParagraph:
			return buffer.convert(offset: buffer.lineEnd(pos.line))

		case .beginOfHardParagraph:
			return positionAtBeginOfHardParagraph(from: pos.line)

		case .endOfHardParagraph:
			return positionAtEndOfHardParagraph(from: pos.line)

		case .beginOfDocument:
			return TextPosition.zero

		case .endOfDocument:
			return buffer.convert(offset: buffer.size)

		case .pageUp:
			if let delegate = layoutDelegate {
				return delegate.pageUp(from: pos)
			}
			// Without layout, move 30 lines up
			let targetLine = max(0, pos.line - 30)
			return positionAt(line: targetLine, preferredColumn: pos.column)

		case .pageDown:
			if let delegate = layoutDelegate {
				return delegate.pageDown(from: pos)
			}
			let targetLine = min(buffer.lines - 1, pos.line + 30)
			return positionAt(line: targetLine, preferredColumn: pos.column)

		case .beginOfSelection, .endOfSelection:
			return pos // These are handled at the selection level

		case .beginOfTypingPair, .endOfTypingPair:
			return pos // Requires grammar/scope information

		case .beginOfColumn, .endOfColumn:
			return pos // Requires layout information

		case .freehandedLeft, .freehandedRight:
			return pos // Freehanded mode is a layout concept

		case .nowhere:
			return pos
		}
	}
}

// MARK: - Selection Extension

extension Editor {
	private func performSelectionExtension(_ action: EditorAction) {
		var newRanges: [TextRange] = []
		for sel in selections.selections {
			let newRange: TextRange

			switch action {
			// Unit-based extension: keep anchor, move head.
			case .moveBackwardAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .left)
			case .moveForwardAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .right)
			case .moveUpAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .up)
			case .moveDownAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .down)
			case .moveWordBackwardAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .wordLeft)
			case .moveWordForwardAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .wordRight)
			case .moveSubWordLeftAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .subWordLeft)
			case .moveSubWordRightAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .subWordRight)
			case .moveToBeginOfSoftLineAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .beginOfSoftLine)
			case .moveToEndOfSoftLineAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .endOfSoftLine)
			case .moveToBeginOfIndentedLineAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .beginOfIndentedLine)
			case .moveToEndOfIndentedLineAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .endOfIndentedLine)
			case .moveToBeginOfLineAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .beginOfLine)
			case .moveToEndOfLineAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .endOfLine)
			case .moveToBeginOfParagraphAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .beginOfParagraph)
			case .moveToEndOfParagraphAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .endOfParagraph)
			case .moveToBeginOfTypingPairAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .beginOfTypingPair)
			case .moveToEndOfTypingPairAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .endOfTypingPair)
			case .moveToBeginOfColumnAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .beginOfColumn)
			case .moveToEndOfColumnAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .endOfColumn)
			case .moveToBeginOfDocumentAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .beginOfDocument)
			case .moveToEndOfDocumentAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .endOfDocument)
			case .pageUpAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .pageUp)
			case .pageDownAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .pageDown)
			case .moveFreehandedBackwardAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .freehandedLeft)
			case .moveFreehandedForwardAndModifySelection:
				newRange = extendSelection(sel, movingHeadBy: .freehandedRight)
			// Unit-based selection: select around content.
			case .selectWord:
				newRange = selectUnit(around: sel, unit: .word)
			case .selectWordOrTypingPair:
				newRange = selectUnit(around: sel, unit: .wordOrTypingPair)
			case .selectScope:
				newRange = selectUnit(around: sel, unit: .scope)
			case .selectSoftLine:
				newRange = selectUnit(around: sel, unit: .softLine)
			case .selectLineExcludingNewline:
				newRange = selectUnit(around: sel, unit: .lineExcludingNewline)
			case .selectLine:
				newRange = selectUnit(around: sel, unit: .line)
			case .selectParagraph:
				newRange = selectUnit(around: sel, unit: .paragraph)
			case .selectTypingPair:
				newRange = selectUnit(around: sel, unit: .typingPair)
			case .selectAll:
				let start = TextPosition.zero
				let end = buffer.convert(offset: buffer.size)
				newRange = TextRange(anchor: start, head: end)
			default:
				newRange = sel
			}

			newRanges.append(newRange)
		}
		selections = SelectionState(newRanges)
	}

	/// Extends a selection by moving its head by the given movement unit.
	func extendSelection(_ sel: TextRange, movingHeadBy unit: MovementUnit) -> TextRange {
		let newHead = movePosition(sel.head, by: unit)
		return TextRange(anchor: sel.anchor, head: newHead, isColumnar: sel.isColumnar)
	}

	/// Selects a unit around the given range (word, line, paragraph, etc.).
	func selectUnit(around sel: TextRange, unit: SelectionExtensionUnit) -> TextRange {
		let startOffset = sel.start.offset
		let endOffset = sel.end.offset

		switch unit {
		case .word, .wordOrTypingPair:
			let wordStart = wordBoundaryLeft(from: startOffset)
			let wordEnd = wordBoundaryRight(from: endOffset)
			return TextRange(
				anchor: buffer.convert(offset: wordStart),
				head: buffer.convert(offset: wordEnd),
			)

		case .softLine, .line:
			let line = buffer.convert(offset: startOffset).line
			let endLine = buffer.convert(offset: endOffset).line
			let lineBegin = buffer.lineStart(line)
			let lineEndOffset: Int = if endLine + 1 < buffer.lines {
				buffer.lineStart(endLine + 1)
			} else {
				buffer.size
			}
			return TextRange(
				anchor: buffer.convert(offset: lineBegin),
				head: buffer.convert(offset: lineEndOffset),
			)

		case .lineExcludingNewline:
			let line = buffer.convert(offset: startOffset).line
			let endLine = buffer.convert(offset: endOffset).line
			let lineBegin = buffer.lineStart(line)
			let lineEndOffset = buffer.lineEnd(endLine)
			return TextRange(
				anchor: buffer.convert(offset: lineBegin),
				head: buffer.convert(offset: lineEndOffset),
			)

		case .paragraph:
			let paraStart = beginOfHardParagraph(from: buffer.convert(offset: startOffset).line)
			let paraEnd = endOfHardParagraph(from: buffer.convert(offset: endOffset).line)
			return TextRange(
				anchor: buffer.convert(offset: paraStart),
				head: buffer.convert(offset: paraEnd),
			)

		case .all:
			return TextRange(
				anchor: TextPosition.zero,
				head: buffer.convert(offset: buffer.size),
			)

		default:
			return sel
		}
	}
}

// MARK: - Deletion

extension Editor {
	private func performDelete(_ action: EditorAction) {
		// For delete actions, first extend empty selections to cover the unit being deleted.
		if let extensionUnit = action.implicitSelectionExtension {
			extendEmptySelections(by: extensionUnit)
		}

		// Special case: deleteSelection doesn't need extension
		// Now delete the selected text in each selection.
		guard hasSelection else { return }

		undoManager.beginUndoGroup(selections: selections)
		let newRanges = deleteSelections()
		undoManager.endUndoGroup(selections: newRanges)

		selections = newRanges

		propagateSnippetMirrors()
	}

	/// Extends empty selections by the given unit (used before delete operations).
	private func extendEmptySelections(by unit: SelectionExtensionUnit) {
		var newRanges: [TextRange] = []
		for sel in selections.selections {
			if sel.isEmpty {
				let extended = selectUnit(around: sel, unit: unit)
				if !extended.isEmpty {
					newRanges.append(extended)
				} else {
					// If extension didn't produce anything, use movement-based extension.
					let movementUnit = unit.toMovementUnit
					let newHead = movePosition(sel.head, by: movementUnit)
					if newHead != sel.head {
						newRanges.append(TextRange(anchor: sel.head, head: newHead))
					} else {
						newRanges.append(sel)
					}
				}
			} else {
				newRanges.append(sel)
			}
		}
		selections = SelectionState(newRanges)
	}
}

// MARK: - Clipboard Operations

extension Editor {
	private func performCut() {
		performCopy()
		if hasSelection {
			undoManager.beginUndoGroup(selections: selections)
			let newRanges = deleteSelections()
			undoManager.endUndoGroup(selections: newRanges)
			selections = newRanges
		}
	}

	private func performCopy() {
		var contents: [String] = []
		var isColumnar = false
		var isComplete = false

		for sel in selections.selections {
			if sel.isEmpty {
				// Copy the whole line when selection is empty
				let lineStart = buffer.lineStart(sel.head.line)
				let lineEnd: Int = if sel.head.line + 1 < buffer.lines {
					buffer.lineStart(sel.head.line + 1)
				} else {
					buffer.size
				}
				contents.append(buffer.substring(from: lineStart, to: lineEnd))
				isComplete = true
			} else {
				contents.append(contentOfRange(sel))
				isColumnar = sel.isColumnar
			}
		}

		guard !contents.isEmpty else { return }

		let indent = leadingWhitespace(at: selections.selections[0].start.offset)
		let entry = ClipboardEntry(
			contents: contents,
			options: .init(isColumnar: isColumnar, indent: indent, isComplete: isComplete),
		)
		clipboards.general.push(entry)
	}

	private func performCopyToFindClipboard() {
		guard let text = selectedText else { return }
		clipboards.find.push(ClipboardEntry(text))
	}

	private func performCopyToReplaceClipboard() {
		guard let text = selectedText else { return }
		clipboards.replace.push(ClipboardEntry(text))
	}

	private func performPaste() {
		guard let entry = clipboards.general.current() else { return }
		pasteEntry(entry)
	}

	private func performPasteNext() {
		guard let entry = clipboards.general.next() else { return }
		pasteEntry(entry)
	}

	private func performPastePrevious() {
		guard let entry = clipboards.general.previous() else { return }
		pasteEntry(entry)
	}

	private func performPasteFromHistoryAndFind() {
		performPaste()
	}

	private func performYank() {
		guard let entry = clipboards.yank.current() else { return }
		pasteEntry(entry)
	}

	/// Pastes a clipboard entry, handling columnar, multi-fragment, and reindent scenarios.
	private func pasteEntry(_ entry: ClipboardEntry) {
		undoManager.beginUndoGroup(selections: selections)

		if entry.options.isColumnar, entry.contents.count > 1 {
			// Columnar paste: insert each fragment on successive lines.
			pasteColumnar(entry)
		} else if entry.contents.count > 1, entry.contents.count == selections.selections.count {
			// Multi-cursor paste: one fragment per cursor.
			pasteMultiFragment(entry)
		} else {
			// Simple paste: insert full text at each cursor.
			let text = entry.text
			let newRanges = replaceSelections(with: text)
			selections = newRanges
		}

		undoManager.endUndoGroup(selections: selections)
	}

	/// Pastes columnar data: one fragment per line starting from the cursor.
	private func pasteColumnar(_ entry: ClipboardEntry) {
		guard let primary = selections.primary else { return }
		let startLine = primary.head.line
		let column = primary.head.column

		var newRanges: [TextRange] = []
		for (i, fragment) in entry.contents.enumerated() {
			let targetLine = startLine + i
			if targetLine >= buffer.lines { break }

			let lineStartOffset = buffer.lineStart(targetLine)
			let lineEndOffset = buffer.lineEnd(targetLine)
			let lineLen = lineEndOffset - lineStartOffset
			let insertOffset = lineStartOffset + min(column, lineLen)

			let end = buffer.replace(from: insertOffset, to: insertOffset, with: fragment)
			let endPos = buffer.convert(offset: end)
			newRanges.append(TextRange(caret: endPos))
		}

		if !newRanges.isEmpty {
			selections = SelectionState(newRanges)
		}
	}

	/// Pastes one fragment per existing cursor.
	private func pasteMultiFragment(_ entry: ClipboardEntry) {
		let sortedSels = selections.selections.sorted { $0.start.offset < $1.start.offset }
		var delta = 0
		var newRanges: [TextRange] = []

		for (i, sel) in sortedSels.enumerated() {
			let fragment = entry.contents[i]
			let from = sel.start.offset + delta
			let to = sel.end.offset + delta
			let oldLen = to - from
			let end = buffer.replace(from: from, to: to, with: fragment)
			delta += fragment.utf8.count - oldLen
			let endPos = buffer.convert(offset: end)
			newRanges.append(TextRange(caret: endPos))
		}

		selections = SelectionState(newRanges)
	}
}

// MARK: - Text Transforms

extension Editor {
	private func performTextTransform(_ action: EditorAction) {
		// Handle special transpositions that don't use TextTransform.
		switch action {
		case .transposeCharacters:
			performTransposeCharacters()
			return
		case .transposeWords:
			performTransposeWords()
			return
		default:
			break
		}

		let transform: TextTransform = switch action {
		case .uppercase: .uppercase
		case .lowercase: .lowercase
		case .capitalize: .capitalize
		case .changeCaseOfLetter, .changeCaseOfWord, .transposeUpperLower: .toggleCase
		case .reformatText: .reformat
		case .reformatTextAndJustify: .reformatAndJustify
		case .unwrapText: .unwrap
		case .shiftLeft: .shiftLeft
		case .shiftRight: .shiftRight
		case .indent: .shiftRight
		default: .none
		}

		// Extend empty selections to word boundaries for case transforms.
		if transform == .uppercase || transform == .lowercase || transform == .capitalize
			|| transform == .toggleCase
		{
			extendEmptySelectionsToWord()
		}

		// Extend empty selections to line for shift/reformat.
		if transform == .shiftLeft || transform == .shiftRight
			|| transform == .reformat || transform == .reformatAndJustify
			|| transform == .unwrap
		{
			extendEmptySelectionsToLine()
		}

		guard hasSelection else { return }

		undoManager.beginUndoGroup(selections: selections)
		let newRanges = applyTransformToSelections(transform)
		undoManager.endUndoGroup(selections: newRanges)

		selections = newRanges
	}

	/// Extends empty selections to cover the word at the cursor.
	private func extendEmptySelectionsToWord() {
		var newRanges: [TextRange] = []
		for sel in selections.selections {
			if sel.isEmpty {
				let wordStart = wordBoundaryLeft(from: sel.head.offset)
				let wordEnd = wordBoundaryRight(from: sel.head.offset)
				if wordStart != wordEnd {
					newRanges.append(TextRange(
						anchor: buffer.convert(offset: wordStart),
						head: buffer.convert(offset: wordEnd),
					))
				} else {
					newRanges.append(sel)
				}
			} else {
				newRanges.append(sel)
			}
		}
		selections = SelectionState(newRanges)
	}

	/// Extends empty selections to cover the whole line.
	private func extendEmptySelectionsToLine() {
		var newRanges: [TextRange] = []
		for sel in selections.selections {
			if sel.isEmpty {
				let bol = buffer.lineStart(sel.head.line)
				let eol: Int = if sel.head.line + 1 < buffer.lines {
					buffer.lineStart(sel.head.line + 1)
				} else {
					buffer.size
				}
				newRanges.append(TextRange(
					anchor: buffer.convert(offset: bol),
					head: buffer.convert(offset: eol),
				))
			} else {
				newRanges.append(sel)
			}
		}
		selections = SelectionState(newRanges)
	}

	/// Applies a transform to all selections and returns the new selection state.
	private func applyTransformToSelections(_ transform: TextTransform) -> SelectionState {
		let sortedSels = selections.selections.sorted { $0.start.offset < $1.start.offset }
		var delta = 0
		var newRanges: [TextRange] = []

		for sel in sortedSels {
			let from = sel.start.offset + delta
			let to = sel.end.offset + delta
			let originalText = buffer.substring(from: from, to: to)
			let transformedText = transform.apply(
				to: originalText,
				tabSize: tabSize,
				indentUsingSpaces: indentUsingSpaces,
				wrapColumn: wrapColumn,
			)
			let oldLen = to - from

			buffer.replace(from: from, to: to, with: transformedText)

			let newLen = transformedText.utf8.count
			delta += newLen - oldLen

			let endPos = buffer.convert(offset: from + newLen)
			newRanges.append(TextRange(caret: endPos))
		}

		return SelectionState(newRanges)
	}

	/// Transposes the two characters around each cursor.
	private func performTransposeCharacters() {
		undoManager.beginUndoGroup(selections: selections)
		var newRanges: [TextRange] = []

		for sel in selections.selections {
			let offset = sel.head.offset
			if sel.isEmpty, offset > 0, offset < buffer.size {
				let leftStart = previousCharacterBoundary(before: offset)
				let rightEnd = nextCharacterBoundary(after: offset)
				let leftChar = buffer.substring(from: leftStart, to: offset)
				let rightChar = buffer.substring(from: offset, to: rightEnd)
				let swapped = rightChar + leftChar
				buffer.replace(from: leftStart, to: rightEnd, with: swapped)
				let newPos = buffer.convert(offset: leftStart + swapped.utf8.count)
				newRanges.append(TextRange(caret: newPos))
			} else {
				newRanges.append(sel)
			}
		}

		let result = SelectionState(newRanges)
		undoManager.endUndoGroup(selections: result)
		selections = result
	}

	/// Transposes the two words around each cursor.
	private func performTransposeWords() {
		undoManager.beginUndoGroup(selections: selections)
		var newRanges: [TextRange] = []
		var delta = 0

		for sel in selections.selections {
			let offset = sel.head.offset + delta
			if sel.isEmpty {
				let leftWordEnd = wordBoundaryLeft(from: offset)
				let leftWordStart = wordBoundaryLeft(from: leftWordEnd)
				let rightWordStart = wordBoundaryRight(from: offset)
				let rightWordEnd = wordBoundaryRight(from: rightWordStart)

				if leftWordStart < leftWordEnd, rightWordStart < rightWordEnd,
				   leftWordEnd <= rightWordStart
				{
					let leftWord = buffer.substring(from: leftWordStart, to: leftWordEnd)
					let middle = buffer.substring(from: leftWordEnd, to: rightWordStart)
					let rightWord = buffer.substring(from: rightWordStart, to: rightWordEnd)
					let swapped = rightWord + middle + leftWord
					let oldLen = rightWordEnd - leftWordStart
					buffer.replace(from: leftWordStart, to: rightWordEnd, with: swapped)
					delta += swapped.utf8.count - oldLen
					let newPos = buffer.convert(offset: leftWordStart + swapped.utf8.count)
					newRanges.append(TextRange(caret: newPos))
				} else {
					newRanges.append(sel)
				}
			} else {
				newRanges.append(sel)
			}
		}

		let result = SelectionState(newRanges)
		undoManager.endUndoGroup(selections: result)
		selections = result
	}
}

// MARK: - Find / Replace

extension Editor {
	private func performFindReplace(_ action: EditorAction) {
		switch action {
		case .findNext:
			findUsingClipboard(backwards: false, extendSelection: false)
		case .findPrevious:
			findUsingClipboard(backwards: true, extendSelection: false)
		case .findNextAndModifySelection:
			findUsingClipboard(backwards: false, extendSelection: true)
		case .findPreviousAndModifySelection:
			findUsingClipboard(backwards: true, extendSelection: true)
		case .findAll:
			findAllUsingClipboard(inSelection: false)
		case .findAllInSelection:
			findAllUsingClipboard(inSelection: hasSelection)
		case .replace:
			replaceUsingClipboard()
		case .replaceAndFind:
			replaceUsingClipboard()
			findUsingClipboard(backwards: false, extendSelection: false)
		case .replaceAll:
			replaceAllUsingClipboard(inSelection: false)
		case .replaceAllInSelection:
			replaceAllUsingClipboard(inSelection: hasSelection)
		default:
			break
		}
	}

	/// Finds the next or previous match using the find clipboard string.
	///
	/// - Parameters:
	///   - backwards: Search backwards from the current position.
	///   - extendSelection: Add the match to existing selections instead of replacing them.
	private func findUsingClipboard(backwards: Bool, extendSelection: Bool) {
		guard let findEntry = clipboards.find.current() else { return }
		let pattern = findEntry.text
		guard !pattern.isEmpty else { return }

		var options = findOptions
		if backwards {
			options.insert(.backwards)
		} else {
			options.remove(.backwards)
		}

		matchCaptures = [:]

		let searcher = BufferSearcher(text: buffer.string)
		let fromOffset = backwards
			? selections.first?.start.offset ?? 0
			: selections.last?.end.offset ?? 0

		guard let result = try? searcher.findNext(
			pattern: pattern,
			options: options,
			fromOffset: fromOffset,
		) else { return }

		guard let match = result.matches.first else { return }

		matchCaptures = match.captures

		let matchRange = TextRange(
			anchor: buffer.convert(offset: match.range.lowerBound),
			head: buffer.convert(offset: match.range.upperBound),
		)

		if extendSelection {
			var sels = selections.selections
			sels.append(matchRange)
			selections = SelectionState(sels)
		} else {
			selections = SelectionState([matchRange])
		}
	}

	/// Finds all matches and selects them.
	///
	/// - Parameter inSelection: If `true`, searches only within the current selections.
	private func findAllUsingClipboard(inSelection: Bool) {
		guard let findEntry = clipboards.find.current() else { return }
		let pattern = findEntry.text
		guard !pattern.isEmpty else { return }

		matchCaptures = [:]

		let searcher = BufferSearcher(text: buffer.string)

		if inSelection {
			// Search within each selection range
			var allMatches: [TextRange] = []
			for sel in selections.selections {
				let searchRange = sel.start.offset ..< sel.end.offset
				guard let result = try? searcher.findAll(
					pattern: pattern,
					options: findOptions,
					searchRange: searchRange,
				) else { continue }

				for match in result.matches {
					allMatches.append(TextRange(
						anchor: buffer.convert(offset: match.range.lowerBound),
						head: buffer.convert(offset: match.range.upperBound),
					))
				}
			}

			// If in-selection result equals the current selections, retry without selection constraint
			// (mirrors C++ behavior: "foo bar" selected and Find All selects the same text → expand to all)
			let matchSorted = allMatches.sorted { $0.start.offset < $1.start.offset }
			let selSorted = selections.selections.sorted { $0.start.offset < $1.start.offset }
			if matchSorted == selSorted {
				findAllUsingClipboard(inSelection: false)
				return
			}

			if !allMatches.isEmpty {
				selections = SelectionState(allMatches)
			}
		} else {
			guard let result = try? searcher.findAll(
				pattern: pattern,
				options: findOptions,
			) else { return }

			let ranges = result.matches.map { match in
				TextRange(
					anchor: buffer.convert(offset: match.range.lowerBound),
					head: buffer.convert(offset: match.range.upperBound),
				)
			}

			if !ranges.isEmpty {
				selections = SelectionState(ranges)
			}
		}
	}

	/// Replaces the current selection using the replace clipboard.
	///
	/// If the most recent find captured groups, the replacement template
	/// is expanded with those captures (e.g. `$1`, `${name}`).
	private func replaceUsingClipboard() {
		guard let replaceEntry = clipboards.replace.current() else { return }
		guard hasSelection else { return }

		var replacement = replaceEntry.text
		if !matchCaptures.isEmpty {
			let template = ReplacementTemplate(replacement)
			replacement = template.expand(with: matchCaptures)
		}

		insertText(replacement)
	}

	/// Replaces all matches of the find clipboard pattern with the replace clipboard text.
	///
	/// - Parameter inSelection: If `true`, replaces only within the current selections.
	private func replaceAllUsingClipboard(inSelection: Bool) {
		guard let findEntry = clipboards.find.current() else { return }
		guard let replaceEntry = clipboards.replace.current() else { return }
		let pattern = findEntry.text
		let replacement = replaceEntry.text
		guard !pattern.isEmpty else { return }

		let searcher = BufferSearcher(text: buffer.string)

		undoManager.beginUndoGroup(selections: selections)

		if inSelection {
			// Replace within each selection, processing from back to front
			let sortedSels = selections.selections.sorted { $0.start.offset > $1.start.offset }
			for sel in sortedSels {
				let searchRange = sel.start.offset ..< sel.end.offset
				let selText = buffer.substring(from: sel.start.offset, to: sel.end.offset)
				let selSearcher = BufferSearcher(text: selText)

				guard let result = try? selSearcher.replaceAll(
					pattern: pattern,
					replacement: replacement,
					options: findOptions,
				), result.count > 0 else { continue }

				buffer.replace(from: searchRange.lowerBound, to: searchRange.upperBound, with: result.text)
			}
		} else {
			guard let result = try? searcher.replaceAll(
				pattern: pattern,
				replacement: replacement,
				options: findOptions,
			), result.count > 0 else {
				undoManager.endUndoGroup(selections: selections)
				return
			}

			// Replace entire buffer content
			buffer.replace(from: 0, to: buffer.size, with: result.text)
		}

		// Place caret at buffer start after replace-all
		selections = SelectionState(caret: TextPosition.zero)
		undoManager.endUndoGroup(selections: selections)
	}
}

// MARK: - Marks

extension Editor {
	private func performSetMark() {
		if let primary = selections.primary {
			mark = primary.head
		}
	}

	private func performDeleteToMark() {
		guard let markPos = mark, let primary = selections.primary else { return }
		let range = TextRange(anchor: primary.head, head: markPos)
		selections = SelectionState([range])
		undoManager.beginUndoGroup(selections: selections)
		let newRanges = deleteSelections()
		undoManager.endUndoGroup(selections: newRanges)
		selections = newRanges
	}

	private func performSelectToMark() {
		guard let markPos = mark, let primary = selections.primary else { return }
		selections = SelectionState([TextRange(anchor: primary.head, head: markPos)])
	}

	private func performSwapWithMark() {
		guard let markPos = mark, let primary = selections.primary else { return }
		let oldHead = primary.head
		selections = SelectionState(caret: markPos)
		mark = oldHead
	}
}

// MARK: - Completion

public extension Editor {
	/// Performs a completion action: initial trigger, next, or previous.
	private func performCompletion(_ action: EditorAction) {
		switch action {
		case .complete:
			if setupCompletion() {
				completionInfo.advance()
				applyCurrentCompletion()
			}
		case .nextCompletion:
			nextCompletion()
		case .previousCompletion:
			previousCompletion()
		default:
			break
		}
	}

	/// Set up the completion session if not already valid for the current
	/// buffer revision and selection.
	///
	/// Port of `editor_t::setup_completion` from completion.cc.
	@discardableResult
	func setupCompletion() -> Bool {
		if completionInfo.revision != buffer.revision
			|| completionInfo.ranges != selections.selections
		{
			completionInfo.revision = buffer.revision
			completionInfo.ranges = selections.selections

			// Use the primary selection's head as the cursor position.
			guard let primary = selections.primary else { return false }
			let cursorOffset = primary.head.offset

			// Find word boundaries around cursor.
			let bow = wordBoundaryLeft(from: cursorOffset)
			let eow = wordBoundaryRight(from: cursorOffset)

			let prefix = buffer.substring(from: bow, to: cursorOffset)
			let suffix = buffer.substring(from: cursorOffset, to: eow)

			// Compute the prefix range: (cursorOffset ..< cursorOffset) initially
			// (a zero-width range at the cursor).
			completionInfo.prefixRanges = [TextRange(caret: primary.head)]

			let engine = CompletionEngine()
			let suggestions = engine.completions(
				buffer: buffer,
				bow: bow,
				eow: eow,
				prefix: prefix,
				suffix: suffix,
			)
			completionInfo.setSuggestions(suggestions)
		}
		return !completionInfo.isEmpty
	}

	/// Cycle to the next completion and insert it.
	///
	/// Port of `editor_t::next_completion` from completion.cc.
	func nextCompletion() {
		guard setupCompletion() else { return }
		completionInfo.advance()
		applyCurrentCompletion()
	}

	/// Cycle to the previous completion and insert it.
	///
	/// Port of `editor_t::previous_completion` from completion.cc.
	func previousCompletion() {
		guard setupCompletion() else { return }
		completionInfo.recede()
		applyCurrentCompletion()
	}

	/// Insert the current completion suggestion, replacing the prefix ranges.
	private func applyCurrentCompletion() {
		let text = completionInfo.current
		guard !completionInfo.prefixRanges.isEmpty else { return }

		// Replace each prefix range with the current suggestion.
		// Process in reverse order to preserve earlier offsets.
		let sortedRanges = completionInfo.prefixRanges.sorted {
			$0.start.offset > $1.start.offset
		}

		var newPrefixRanges: [TextRange] = []
		for range in sortedRanges {
			let from = range.start.offset
			let to = range.end.offset
			let end = buffer.replace(from: from, to: to, with: text)
			let endPos = buffer.convert(offset: end)
			let startPos = buffer.convert(offset: from)
			newPrefixRanges.append(TextRange(anchor: startPos, head: endPos))

			// Update snippet controller.
			snippetController.adjustForEdit(
				at: from,
				oldLength: to - from,
				newLength: text.utf8.count,
			)
		}

		completionInfo.prefixRanges = newPrefixRanges.reversed()
		completionInfo.revision = buffer.revision

		// Move selections to end of inserted text.
		let newSelections = completionInfo.prefixRanges.map { range in
			TextRange(caret: range.end)
		}
		completionInfo.ranges = newSelections
		selections = SelectionState(newSelections)
	}

	/// The currently active completion suggestions (for UI display).
	var completionSuggestions: [String] {
		completionInfo.suggestions
	}

	/// The index of the currently active suggestion.
	var completionIndex: Int? {
		guard !completionInfo.isEmpty else { return nil }
		// CompletionInfo uses advance/recede but we can derive index
		// by checking which suggestion matches current.
		let current = completionInfo.current
		return completionInfo.suggestions.firstIndex(of: current)
	}

	/// Cancel the active completion session.
	func cancelCompletion() {
		completionInfo = CompletionInfo()
	}

	/// Whether a completion session is active.
	var isCompletionActive: Bool {
		!completionInfo.isEmpty
	}
}

// MARK: - Tab / Newline

extension Editor {
	/// Inserts a tab, respecting snippet navigation and indent settings.
	private func performInsertTab() {
		// If a snippet is active, Tab navigates to the next tab stop.
		if !snippetController.isEmpty {
			if let range = snippetController.next() {
				selections = SelectionState([range])
			} else {
				// Snippet ended, snippet controller already popped.
			}
			return
		}

		// Otherwise, insert appropriate whitespace.
		performInsertTabRaw()
	}

	/// Inserts a backtab (Shift-Tab), for snippet back-navigation or shift-left.
	private func performInsertBacktab() {
		if !snippetController.isEmpty {
			if let range = snippetController.previous() {
				selections = SelectionState([range])
			}
			return
		}

		// Without a snippet, shift-tab shifts all selected lines left.
		perform(.shiftLeft)
	}

	/// Inserts a raw tab character or equivalent spaces.
	private func performInsertTabRaw() {
		let tabString: String
		if indentUsingSpaces {
			let column = selections.primary?.head.column ?? 0
			let spacesNeeded = tabSize - (column % tabSize)
			tabString = String(repeating: " ", count: spacesNeeded)
		} else {
			tabString = "\t"
		}
		insertText(tabString)
	}

	/// Inserts a newline with auto-indentation.
	private func performInsertNewline() {
		undoManager.beginUndoGroup(selections: selections)

		var newRanges: [TextRange] = []
		var delta = 0

		for sel in selections.selections.sorted(by: { $0.start.offset < $1.start.offset }) {
			let from = sel.start.offset + delta
			let to = sel.end.offset + delta
			let oldLen = to - from

			// Determine indentation from the current line.
			let pos = buffer.convert(offset: from)
			let indent: String = if let provider = indentProvider {
				provider(pos.line)
			} else {
				leadingWhitespace(at: buffer.lineStart(pos.line))
			}

			let insertString = "\n" + indent
			let end = buffer.replace(from: from, to: to, with: insertString)
			delta += insertString.utf8.count - oldLen

			let endPos = buffer.convert(offset: end)
			newRanges.append(TextRange(caret: endPos))
		}

		let result = SelectionState(newRanges)
		undoManager.endUndoGroup(selections: result)
		selections = result
	}

	/// Inserts a raw newline without auto-indentation.
	private func performInsertNewlineRaw() {
		insertText("\n")
	}
}

// MARK: - Move Selection

extension Editor {
	/// Moves the selected text up or down by the given number of lines.
	private func performMoveSelection(deltaLine: Int = 0, deltaColumn: Int = 0) {
		guard hasSelection else { return }

		if deltaLine != 0 {
			moveSelectedTextVertically(by: deltaLine)
		}
		if deltaColumn != 0 {
			moveSelectedTextHorizontally(by: deltaColumn)
		}
	}

	/// Moves selected text vertically (swaps lines).
	private func moveSelectedTextVertically(by delta: Int) {
		guard let primary = selections.primary, !primary.isEmpty else { return }

		let startLine = primary.start.line
		let endLine = primary.end.line

		if delta < 0, startLine > 0 {
			undoManager.beginUndoGroup(selections: selections)

			// Swap the line above with the first selected line.
			let aboveLine = startLine - 1
			let aboveStart = buffer.lineStart(aboveLine)
			let aboveEnd: Int = if aboveLine + 1 < buffer.lines {
				buffer.lineStart(aboveLine + 1)
			} else {
				buffer.size
			}
			let aboveText = buffer.substring(from: aboveStart, to: aboveEnd)

			// Remove the line above
			buffer.erase(from: aboveStart, to: aboveEnd)

			// Insert it after the (now shifted) selection
			let insertOffset: Int = if endLine < buffer.lines {
				buffer.lineStart(endLine) // endLine shifted down by 1 due to erase
			} else {
				buffer.size
			}

			let insertText: String = if insertOffset == buffer.size, !aboveText.hasSuffix("\n") {
				"\n" + aboveText
			} else {
				aboveText
			}
			buffer.insert(at: insertOffset, string: insertText)

			// Adjust selections
			let newStartOffset = buffer.lineStart(startLine - 1)
			let newEndOffset: Int = if endLine < buffer.lines {
				buffer.lineStart(endLine)
			} else {
				buffer.size
			}
			selections = SelectionState([
				TextRange(
					anchor: buffer.convert(offset: newStartOffset),
					head: buffer.convert(offset: newEndOffset),
				),
			])

			undoManager.endUndoGroup(selections: selections)
		} else if delta > 0, endLine < buffer.lines - 1 {
			undoManager.beginUndoGroup(selections: selections)

			let belowLine = endLine + 1
			let belowStart = buffer.lineStart(belowLine)
			let belowEnd: Int = if belowLine + 1 < buffer.lines {
				buffer.lineStart(belowLine + 1)
			} else {
				buffer.size
			}
			let belowText = buffer.substring(from: belowStart, to: belowEnd)

			buffer.erase(from: belowStart, to: belowEnd)

			let insertText: String = if buffer.lineStart(startLine) == 0, !belowText.hasSuffix("\n") {
				belowText + "\n"
			} else {
				belowText
			}
			buffer.insert(at: buffer.lineStart(startLine), string: insertText)

			let newStartOffset = buffer.lineStart(startLine + 1)
			let newEndOffset: Int = if endLine + 2 <= buffer.lines {
				buffer.lineStart(endLine + 2)
			} else {
				buffer.size
			}
			selections = SelectionState([
				TextRange(
					anchor: buffer.convert(offset: newStartOffset),
					head: buffer.convert(offset: newEndOffset),
				),
			])

			undoManager.endUndoGroup(selections: selections)
		}
	}

	/// Moves selected text horizontally (shifts characters).
	private func moveSelectedTextHorizontally(by delta: Int) {
		guard hasSelection else { return }
		if delta > 0 {
			perform(.shiftRight)
		} else {
			perform(.shiftLeft)
		}
	}
}

// MARK: - Column / Deselect

extension Editor {
	private func performToggleColumnSelection() {
		guard var primary = selections.primary else { return }
		if !primary.isEmpty {
			primary = TextRange(
				anchor: primary.anchor,
				head: primary.head,
				isColumnar: !primary.isColumnar,
			)
			selections = SelectionState([primary])
		}
	}

	private func performDeselectLast() {
		if selections.count > 1 {
			var sels = selections.selections
			sels.removeLast()
			selections = SelectionState(sels)
		} else if let primary = selections.primary, !primary.isEmpty {
			// Collapse to caret at anchor
			selections = SelectionState(caret: primary.anchor)
		}
	}
}

// MARK: - Core Editing Primitives

extension Editor {
	/// Replaces all selected text with the given string and returns the new selection state.
	///
	/// This is the central editing primitive — all text modifications flow through here.
	/// Replacements are applied from back to front to preserve offsets.
	func replaceSelections(with text: String) -> SelectionState {
		let sortedSels = selections.selections.sorted { $0.start.offset > $1.start.offset }
		var newRanges: [TextRange] = []

		for sel in sortedSels {
			let from = sel.start.offset
			let to = sel.end.offset
			let end = buffer.replace(from: from, to: to, with: text)
			let endPos = buffer.convert(offset: end)
			newRanges.append(TextRange(caret: endPos))

			// Update snippet controller
			snippetController.adjustForEdit(
				at: from,
				oldLength: to - from,
				newLength: text.utf8.count,
			)
		}

		return SelectionState(newRanges)
	}

	/// Deletes all selected text and returns the new selection state.
	func deleteSelections() -> SelectionState {
		replaceSelections(with: "")
	}
}

// MARK: - Character / Word Boundary Helpers

extension Editor {
	/// Returns the byte offset of the previous character boundary.
	func previousCharacterBoundary(before offset: Int) -> Int {
		guard offset > 0 else { return 0 }
		// Move back by one Unicode scalar, then align to character boundary.
		var pos = offset - 1
		// Skip UTF-8 continuation bytes (10xxxxxx).
		while pos > 0, isContinuationByte(at: pos) {
			pos -= 1
		}
		return pos
	}

	/// Returns the byte offset of the next character boundary.
	func nextCharacterBoundary(after offset: Int) -> Int {
		guard offset < buffer.size else { return buffer.size }
		var pos = offset + 1
		while pos < buffer.size, isContinuationByte(at: pos) {
			pos += 1
		}
		return pos
	}

	/// Whether the byte at `offset` is a UTF-8 continuation byte.
	private func isContinuationByte(at offset: Int) -> Bool {
		let byte = buffer[offset]
		return (byte & 0xC0) == 0x80
	}

	/// Returns the start of the word at/before the given offset.
	func wordBoundaryLeft(from offset: Int) -> Int {
		guard offset > 0 else { return 0 }
		var pos = previousCharacterBoundary(before: offset)

		// Skip whitespace backward.
		while pos > 0, isWhitespace(at: pos) {
			pos = previousCharacterBoundary(before: pos)
		}

		// If we're on a word character, go back to the start of the word.
		if pos > 0, isWordCharacter(at: pos) {
			while pos > 0 {
				let prev = previousCharacterBoundary(before: pos)
				if isWordCharacter(at: prev) {
					pos = prev
				} else {
					break
				}
			}
		}

		return pos
	}

	/// Returns the end of the word at/after the given offset.
	func wordBoundaryRight(from offset: Int) -> Int {
		guard offset < buffer.size else { return buffer.size }
		var pos = offset

		// Skip whitespace forward.
		while pos < buffer.size, isWhitespace(at: pos) {
			pos = nextCharacterBoundary(after: pos)
		}

		// If we're on a word character, go forward to the end of the word.
		if pos < buffer.size, isWordCharacter(at: pos) {
			while pos < buffer.size, isWordCharacter(at: pos) {
				pos = nextCharacterBoundary(after: pos)
			}
		} else if pos < buffer.size {
			pos = nextCharacterBoundary(after: pos)
		}

		return pos
	}

	/// Returns the start of the sub-word at/before the given offset.
	func positionAtSubWordBoundary(before offset: Int) -> TextPosition {
		// Sub-word boundaries: camelCase boundaries (upper→lower transition),
		// underscore boundaries, and digit boundaries.
		guard offset > 0 else { return TextPosition.zero }
		var pos = previousCharacterBoundary(before: offset)

		// Simple sub-word: back up while same character class
		let startClass = characterClass(at: pos)
		while pos > 0 {
			let prev = previousCharacterBoundary(before: pos)
			let prevClass = characterClass(at: prev)
			if prevClass != startClass {
				break
			}
			pos = prev
		}

		return buffer.convert(offset: pos)
	}

	/// Returns the end of the sub-word at/after the given offset.
	func positionAtSubWordBoundary(after offset: Int) -> TextPosition {
		guard offset < buffer.size else { return buffer.convert(offset: buffer.size) }
		var pos = offset

		let startClass = characterClass(at: pos)
		while pos < buffer.size {
			let next = nextCharacterBoundary(after: pos)
			if next >= buffer.size { pos = next
				break
			}
			let nextClass = characterClass(at: next)
			if nextClass != startClass {
				pos = next
				break
			}
			pos = next
		}

		return buffer.convert(offset: pos)
	}

	/// Returns the word boundary position before the offset.
	func positionAtWordBoundary(before offset: Int) -> TextPosition {
		buffer.convert(offset: wordBoundaryLeft(from: offset))
	}

	/// Returns the word boundary position after the offset.
	func positionAtWordBoundary(after offset: Int) -> TextPosition {
		buffer.convert(offset: wordBoundaryRight(from: offset))
	}

	/// Character class used for word boundary detection.
	private enum CharClass {
		case word, space, punctuation, other
	}

	private func characterClass(at offset: Int) -> CharClass {
		guard offset < buffer.size else { return .other }
		let byte = buffer[offset]
		if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") {
			return .space
		}
		if isWordCharacter(at: offset) {
			return .word
		}
		return .punctuation
	}

	/// Whether the character at offset is a word character (alphanumeric or underscore).
	func isWordCharacter(at offset: Int) -> Bool {
		guard offset < buffer.size else { return false }
		let byte = buffer[offset]
		return (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
			|| (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
			|| (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
			|| byte == UInt8(ascii: "_")
			|| byte >= 0x80 // Non-ASCII: treat as word char (e.g., accented letters)
	}

	/// Whether the character at offset is whitespace.
	private func isWhitespace(at offset: Int) -> Bool {
		guard offset < buffer.size else { return false }
		let byte = buffer[offset]
		return byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
			|| byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
	}
}

// MARK: - Line / Paragraph Helpers

extension Editor {
	/// Returns the byte offset of the end of leading whitespace on the given line.
	func endOfLeadingWhitespace(line: Int) -> Int {
		let bol = buffer.lineStart(line)
		let eol = buffer.lineEnd(line)
		var pos = bol
		while pos < eol {
			let byte = buffer[pos]
			if byte != UInt8(ascii: " "), byte != UInt8(ascii: "\t") {
				break
			}
			pos += 1
		}
		return pos
	}

	/// Returns the leading whitespace string at the given offset.
	func leadingWhitespace(at offset: Int) -> String {
		let pos = buffer.convert(offset: offset)
		let bol = buffer.lineStart(pos.line)
		let eoi = endOfLeadingWhitespace(line: pos.line)
		guard eoi > bol else { return "" }
		return buffer.substring(from: bol, to: eoi)
	}

	/// Returns a position at the given line with the preferred column.
	func positionAt(line: Int, preferredColumn column: Int) -> TextPosition {
		let bol = buffer.lineStart(line)
		let eol = buffer.lineEnd(line)
		let lineLen = eol - bol
		let offset = bol + min(column, lineLen)
		return buffer.convert(offset: offset)
	}

	/// Returns the byte offset of the beginning of the hard paragraph containing the given line.
	func beginOfHardParagraph(from line: Int) -> Int {
		var n = line
		while n > 0 {
			let prevLine = n - 1
			let bol = buffer.lineStart(prevLine)
			let eol = buffer.lineEnd(prevLine)
			if bol == eol { // Blank line = paragraph separator
				return buffer.lineStart(n)
			}
			// Check if line is all whitespace
			let lineText = buffer.substring(from: bol, to: eol)
			if lineText.allSatisfy(\.isWhitespace) {
				return buffer.lineStart(n)
			}
			n -= 1
		}
		return 0
	}

	/// Returns the byte offset of the end of the hard paragraph containing the given line.
	func endOfHardParagraph(from line: Int) -> Int {
		var n = line
		let lastLine = buffer.lines - 1
		while n < lastLine {
			let nextLine = n + 1
			let bol = buffer.lineStart(nextLine)
			let eol = buffer.lineEnd(nextLine)
			if bol == eol {
				return buffer.lineStart(nextLine)
			}
			let lineText = buffer.substring(from: bol, to: eol)
			if lineText.allSatisfy(\.isWhitespace) {
				return buffer.lineStart(nextLine)
			}
			n += 1
		}
		return buffer.size
	}

	/// Returns the position at the beginning of the hard paragraph.
	func positionAtBeginOfHardParagraph(from line: Int) -> TextPosition {
		buffer.convert(offset: beginOfHardParagraph(from: line))
	}

	/// Returns the position at the end of the hard paragraph.
	func positionAtEndOfHardParagraph(from line: Int) -> TextPosition {
		buffer.convert(offset: endOfHardParagraph(from: line))
	}
}

// MARK: - Undo / Redo

public extension Editor {
	/// Undoes the last editing operation.
	func undo() {
		if let savedSelections = undoManager.undo() {
			selections = savedSelections
		}
	}

	/// Redoes the last undone operation.
	func redo() {
		if let savedSelections = undoManager.redo() {
			selections = savedSelections
		}
	}

	/// Whether an undo operation is available.
	var canUndo: Bool {
		undoManager.canUndo
	}

	/// Whether a redo operation is available.
	var canRedo: Bool {
		undoManager.canRedo
	}
}

// MARK: - Layout Delegate

/// Protocol for layout-dependent operations that the editor cannot perform
/// without knowledge of the visual layout (soft wrapping, page size, etc.).
public protocol EditorLayoutDelegate: AnyObject, Sendable {
	/// Returns the position one page up from the given position.
	func pageUp(from position: TextPosition) -> TextPosition

	/// Returns the position one page down from the given position.
	func pageDown(from position: TextPosition) -> TextPosition

	/// Returns the position at the beginning of the visual (soft) line
	/// containing `position`. Returns `nil` if no soft-wrap information
	/// is available, in which case the editor falls back to hard-line BOL.
	func beginOfSoftLine(from position: TextPosition) -> TextPosition?

	/// Returns the position at the end of the visual (soft) line
	/// containing `position`. Returns `nil` if no soft-wrap information
	/// is available, in which case the editor falls back to hard-line EOL.
	func endOfSoftLine(from position: TextPosition) -> TextPosition?
}

// MARK: - MovementUnit Classification

extension MovementUnit {
	/// Whether this movement moves leftward/backward.
	var isLeftward: Bool {
		switch self {
		case .left, .freehandedLeft, .wordLeft, .subWordLeft,
		     .beginOfSoftLine, .beginOfIndentedLine, .beginOfLine,
		     .beginOfParagraph, .beginOfHardParagraph,
		     .beginOfTypingPair, .beginOfColumn,
		     .beginOfDocument, .beginOfSelection, .up, .pageUp:
			true
		default:
			false
		}
	}

	/// Whether this movement should collapse a non-empty selection to an edge
	/// rather than moving from the head.
	var collapsesSelection: Bool {
		switch self {
		case .left, .right, .freehandedLeft, .freehandedRight:
			true
		default:
			false
		}
	}
}

// MARK: - EditorAction → MovementUnit

extension EditorAction {
	/// The movement unit for movement actions, or `nil` for non-movement actions.
	var movementUnit: MovementUnit? {
		switch self {
		case .moveBackward: .left
		case .moveForward: .right
		case .moveFreehandedBackward: .freehandedLeft
		case .moveFreehandedForward: .freehandedRight
		case .moveUp: .up
		case .moveDown: .down
		case .moveToBeginOfSelection: .beginOfSelection
		case .moveToEndOfSelection: .endOfSelection
		case .moveSubWordLeft: .subWordLeft
		case .moveSubWordRight: .subWordRight
		case .moveWordBackward: .wordLeft
		case .moveWordForward: .wordRight
		case .moveToBeginOfSoftLine: .beginOfSoftLine
		case .moveToEndOfSoftLine: .endOfSoftLine
		case .moveToBeginOfIndentedLine: .beginOfIndentedLine
		case .moveToEndOfIndentedLine: .endOfIndentedLine
		case .moveToBeginOfLine: .beginOfLine
		case .moveToEndOfLine: .endOfLine
		case .moveToBeginOfParagraph: .beginOfParagraph
		case .moveToEndOfParagraph: .endOfParagraph
		case .moveToBeginOfHardParagraph: .beginOfHardParagraph
		case .moveToEndOfHardParagraph: .endOfHardParagraph
		case .moveToBeginOfTypingPair: .beginOfTypingPair
		case .moveToEndOfTypingPair: .endOfTypingPair
		case .moveToBeginOfColumn: .beginOfColumn
		case .moveToEndOfColumn: .endOfColumn
		case .pageUp: .pageUp
		case .pageDown: .pageDown
		case .moveToBeginOfDocument: .beginOfDocument
		case .moveToEndOfDocument: .endOfDocument
		default: nil
		}
	}
}

// MARK: - SelectionExtensionUnit → MovementUnit

extension SelectionExtensionUnit {
	/// Converts this selection extension unit to a movement unit for
	/// extending empty selections before delete operations.
	var toMovementUnit: MovementUnit {
		switch self {
		case .left: .left
		case .right: .right
		case .freehandedLeft: .freehandedLeft
		case .freehandedRight: .freehandedRight
		case .up: .up
		case .down: .down
		case .subWordLeft: .subWordLeft
		case .subWordRight: .subWordRight
		case .wordLeft: .wordLeft
		case .wordRight: .wordRight
		case .beginOfSoftLine: .beginOfSoftLine
		case .endOfSoftLine: .endOfSoftLine
		case .beginOfIndentedLine: .beginOfIndentedLine
		case .endOfIndentedLine: .endOfIndentedLine
		case .beginOfLine: .beginOfLine
		case .endOfLine: .endOfLine
		case .beginOfParagraph: .beginOfParagraph
		case .endOfParagraph: .endOfParagraph
		case .beginOfTypingPair: .beginOfTypingPair
		case .endOfTypingPair: .endOfTypingPair
		case .beginOfColumn: .beginOfColumn
		case .endOfColumn: .endOfColumn
		case .beginOfDocument: .beginOfDocument
		case .endOfDocument: .endOfDocument
		case .pageUp: .pageUp
		case .pageDown: .pageDown
		case .word: .wordRight
		case .wordOrTypingPair: .wordRight
		case .scope: .right
		case .softLine: .endOfSoftLine
		case .lineExcludingNewline: .endOfLine
		case .line: .endOfLine
		case .paragraph: .endOfParagraph
		case .typingPair: .endOfTypingPair
		case .all: .endOfDocument
		}
	}
}

// MARK: - Visual Metrics

public extension Editor {
	/// Computes the visual column distance between two offsets on the same line,
	/// accounting for tab stops and East Asian full-width characters.
	///
	/// This is the Swift counterpart of `ng::editor_t::visual_distance()` from
	/// `Frameworks/editor/src/metrics.cc`.
	///
	/// - Parameters:
	///   - first: The starting byte offset.
	///   - last: The ending byte offset (must be on the same line).
	///   - eastAsianWidth: Whether to count East Asian wide characters as 2 columns.
	/// - Returns: The visual column width between the two offsets.
	func visualDistance(from first: Int, to last: Int, eastAsianWidth: Bool = false) -> Int {
		precondition(first <= last)
		let text = buffer.substring(from: first, to: last)
		var len = 0
		for scalar in text.unicodeScalars {
			if scalar == "\t" {
				len += tabSize - (len % tabSize)
			} else if eastAsianWidth, scalar.isEastAsianWide {
				len += 2
			} else {
				len += 1
			}
		}
		return len
	}

	/// Advances from a byte offset to a target visual column, accounting for
	/// tab stops and East Asian full-width characters.
	///
	/// This is the Swift counterpart of `ng::editor_t::visual_advance()` from
	/// `Frameworks/editor/src/metrics.cc`.
	///
	/// - Parameters:
	///   - offset: The starting byte offset.
	///   - distance: The target visual column distance to advance.
	///   - eastAsianWidth: Whether to count East Asian wide characters as 2 columns.
	/// - Returns: The byte offset after advancing `distance` visual columns,
	///   and the carry (extra columns past the last character).
	func visualAdvance(from offset: Int, distance: Int, eastAsianWidth: Bool = false) -> (offset: Int, carry: Int) {
		let lineEnd = buffer.lineEnd(buffer.convert(offset: offset).line)
		let text = buffer.substring(from: offset, to: lineEnd)
		var len = 0
		var bytePos = 0
		for scalar in text.unicodeScalars {
			if len == distance {
				return (offset + bytePos, 0)
			}
			if scalar == "\n" {
				return (offset + bytePos, distance - len)
			}
			let charWidth: Int = if scalar == "\t" {
				tabSize - (len % tabSize)
			} else if eastAsianWidth, scalar.isEastAsianWide {
				2
			} else {
				1
			}
			if len + charWidth > distance {
				return (offset + bytePos, distance - len)
			}
			len += charWidth
			bytePos += Int(scalar.utf8.count)
		}
		return (offset + bytePos, distance - len)
	}

	/// Returns the visual column of the primary caret, accounting for tabs.
	var visualColumn: Int {
		guard let primary = selections.primary else { return 0 }
		let pos = buffer.convert(offset: primary.head.offset)
		let lineStart = buffer.lineStart(pos.line)
		return visualDistance(from: lineStart, to: primary.head.offset)
	}
}

// MARK: - East Asian Width Helper

public extension Unicode.Scalar {
	/// Whether this scalar is classified as East Asian wide (W) or fullwidth (F).
	///
	/// This is a simplified check covering the most common ranges.
	var isEastAsianWide: Bool {
		let v = value
		// CJK Unified Ideographs
		if v >= 0x4E00, v <= 0x9FFF { return true }
		// CJK Unified Ideographs Extension A
		if v >= 0x3400, v <= 0x4DBF { return true }
		// CJK Compatibility Ideographs
		if v >= 0xF900, v <= 0xFAFF { return true }
		// Fullwidth Forms
		if v >= 0xFF01, v <= 0xFF60 { return true }
		if v >= 0xFFE0, v <= 0xFFE6 { return true }
		// CJK Unified Ideographs Extension B+
		if v >= 0x20000, v <= 0x2FA1F { return true }
		// Hangul Syllables
		if v >= 0xAC00, v <= 0xD7AF { return true }
		// CJK Radicals, Kangxi Radicals, Ideographic Description, CJK Symbols
		if v >= 0x2E80, v <= 0x303E { return true }
		// Hiragana, Katakana, Bopomofo
		if v >= 0x3040, v <= 0x312F { return true }
		// Katakana Phonetic Extensions, Enclosed CJK Letters
		if v >= 0x31F0, v <= 0x33FF { return true }
		return false
	}
}
