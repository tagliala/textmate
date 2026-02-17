import AppKit
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI

/// Bridges a `TMDocument` to an `Editor` and an `EditorView`.
///
/// This is the Swift counterpart of the C++ `OakDocumentEditor`. It:
/// - Creates an `Editor` backed by the document's content
/// - Implements `EditorViewDelegate` to translate view events into editor actions
/// - Syncs text mutations back to the document
/// - Serializes selection state on save
/// - Manages undo change-group nesting
@MainActor
public final class TMDocumentEditor {
	// MARK: - Properties

	/// The document being edited.
	public let document: TMDocument

	/// The editor engine operating on the document's content.
	public let editor: Editor

	/// The view displaying this editor (weak to avoid retain cycle).
	public private(set) weak var editorView: EditorView?

	/// Nesting level for undo change groups.
	private var changeGroupLevel: Int = 0

	/// Observation token for document change callbacks.
	private var documentObservationID: UUID?

	// MARK: - Init

	/// Creates a document editor.
	///
	/// - Parameters:
	///   - document: The document to edit. Must have content loaded.
	///   - editorView: The view that will display the editor content.
	///   - clipboards: Shared clipboards for copy/paste/find/replace.
	public init(
		document: TMDocument,
		editorView: EditorView,
		clipboards: ClipboardSet = ClipboardSet(),
	) {
		precondition(
			document.state == .loaded || document.content != nil,
			"Document must be loaded before creating an editor",
		)

		self.document = document
		self.editorView = editorView

		// Create an editor backed by the document's content.
		let text = document.content ?? ""
		editor = Editor(text: text, clipboards: clipboards)

		// Apply document settings to the editor.
		editor.tabSize = document.tabSize
		editor.indentUsingSpaces = document.softTabs

		// Wire the view delegate.
		editorView.delegate = self

		// Push initial content to the view.
		editorView.setText(text)

		// Restore selection from document metadata if available.
		if let selectionString = document.selection {
			restoreSelection(from: selectionString)
		}

		// Observe document changes (e.g., external reload).
		documentObservationID = document.addChangeCallback { [weak self] in
			self?.documentDidChange()
		}
	}

	deinit {
		MainActor.assumeIsolated {
			// Save state before teardown.
			documentWillSave()

			if let id = documentObservationID {
				document.removeChangeCallback(id: id)
			}

			// Balance any open change groups.
			while changeGroupLevel > 0 {
				_ = endChangeGrouping()
			}
		}
	}

	// MARK: - Change Grouping

	/// Begins an undo change group. Nested calls are balanced.
	/// Returns `true` if this call opened the outermost group.
	@discardableResult
	public func beginChangeGrouping() -> Bool {
		changeGroupLevel += 1
		return changeGroupLevel == 1
	}

	/// Ends an undo change group. Returns `true` if this call
	/// closed the outermost group.
	@discardableResult
	public func endChangeGrouping() -> Bool {
		guard changeGroupLevel > 0 else { return false }
		changeGroupLevel -= 1
		return changeGroupLevel == 0
	}

	// MARK: - Selection Serialization

	/// Serializes the editor's selection state into the document
	/// before a save operation.
	public func documentWillSave() {
		let sels = editor.selections.selections
		guard !sels.isEmpty else { return }

		// Serialize selections as "line:col[-line:col][&...]".
		var parts: [String] = []
		for sel in sels {
			let fromPos = editor.buffer.convert(offset: sel.start.offset)
			let toPos = editor.buffer.convert(offset: sel.end.offset)
			if sel.isEmpty {
				parts.append("\(fromPos.line + 1):\(fromPos.column)")
			} else {
				parts.append("\(fromPos.line + 1):\(fromPos.column)-\(toPos.line + 1):\(toPos.column)")
			}
		}

		let savedVisibleIndex = document.visibleIndex
		document.selection = parts.joined(separator: "&")
		document.visibleIndex = savedVisibleIndex
	}

	/// Restores selections from a serialized string.
	private func restoreSelection(from selectionString: String) {
		let parts = selectionString.split(separator: "&")
		var ranges: [TMCore.TextRange] = []

		for part in parts {
			let fromTo = part.split(separator: "-", maxSplits: 1)
			if fromTo.count == 2 {
				if let from = parsePosition(String(fromTo[0])),
				   let to = parsePosition(String(fromTo[1]))
				{
					ranges.append(TMCore.TextRange(anchor: from, head: to))
				}
			} else if let pos = parsePosition(String(part)) {
				ranges.append(TMCore.TextRange(caret: pos))
			}
		}

		if !ranges.isEmpty {
			editor.selections = SelectionState(ranges)
		}
	}

	/// Parses "line:col" into a TextPosition (1-based line).
	private func parsePosition(_ str: String) -> TextPosition? {
		let components = str.split(separator: ":", maxSplits: 1)
		guard components.count == 2,
		      let line = Int(components[0]),
		      let col = Int(components[1])
		else { return nil }
		// Convert 1-based line to offset.
		let offset = editor.buffer.lineStart(line - 1) + col
		let clamped = min(offset, editor.buffer.size)
		return editor.buffer.convert(offset: clamped)
	}

	// MARK: - Content Sync

	/// Syncs the editor's content to the document and updates the view.
	private func syncAfterEdit() {
		let text = editor.text
		document.setContent(text)
		editorView?.setText(text)
		syncSelectionToView()
	}

	/// Updates the view's carets and selection ranges to match the editor state.
	private func syncSelectionToView() {
		guard let view = editorView else { return }

		let sels = editor.selections.selections
		var carets: [(line: Int, index: Int)] = []
		var selRanges: [(start: (line: Int, index: Int), end: (line: Int, index: Int))] = []

		for sel in sels {
			let headPos = editor.buffer.convert(offset: sel.head.offset)
			carets.append((headPos.line, headPos.column))

			if !sel.isEmpty {
				let startPos = editor.buffer.convert(offset: sel.start.offset)
				let endPos = editor.buffer.convert(offset: sel.end.offset)
				selRanges.append(
					(start: (startPos.line, startPos.column), end: (endPos.line, endPos.column)),
				)
			}
		}

		view.carets = carets.isEmpty ? [(0, 0)] : carets
		view.selectionRanges = selRanges
		view.scrollToCaret()
	}

	/// Called when the document changes externally (e.g., reload).
	private func documentDidChange() {
		// If content differs from what the editor has, it was an external change.
		guard let docContent = document.content else { return }
		if docContent != editor.text {
			// Re-initialize editor content.
			// In a future phase this could do a proper delta/merge.
			editor.buffer.replace(from: 0, to: editor.buffer.size, with: docContent)
			editorView?.setText(docContent)
			syncSelectionToView()
		}
	}

	// MARK: - Undo / Redo

	/// Undoes the last editor operation.
	public func undo() {
		editor.undo()
		syncAfterEdit()
	}

	/// Redoes the last undone operation.
	public func redo() {
		editor.redo()
		syncAfterEdit()
	}
}

// MARK: - EditorViewAction → EditorAction Mapping

extension TMDocumentEditor {
	/// Maps an `EditorViewAction` to an `EditorAction`.
	static func editorAction(from viewAction: EditorViewAction) -> EditorAction {
		switch viewAction {
		// Movement
		case .moveUp: .moveUp
		case .moveDown: .moveDown
		case .moveLeft: .moveBackward
		case .moveRight: .moveForward
		case .moveToBeginningOfLine: .moveToBeginOfSoftLine
		case .moveToEndOfLine: .moveToEndOfSoftLine
		case .moveToBeginningOfDocument: .moveToBeginOfDocument
		case .moveToEndOfDocument: .moveToEndOfDocument
		case .moveWordForward: .moveWordForward
		case .moveWordBackward: .moveWordBackward
		case .pageUp: .pageUp
		case .pageDown: .pageDown
		// Selection extension
		case .moveUpAndModifySelection: .moveUpAndModifySelection
		case .moveDownAndModifySelection: .moveDownAndModifySelection
		case .moveLeftAndModifySelection: .moveBackwardAndModifySelection
		case .moveRightAndModifySelection: .moveForwardAndModifySelection
		case .moveWordForwardAndModifySelection: .moveWordForwardAndModifySelection
		case .moveWordBackwardAndModifySelection: .moveWordBackwardAndModifySelection
		case .moveToBeginningOfLineAndModifySelection: .moveToBeginOfSoftLineAndModifySelection
		case .moveToEndOfLineAndModifySelection: .moveToEndOfSoftLineAndModifySelection
		case .moveToBeginningOfDocumentAndModifySelection: .moveToBeginOfDocumentAndModifySelection
		case .moveToEndOfDocumentAndModifySelection: .moveToEndOfDocumentAndModifySelection
		// Deletion
		case .deleteForward: .deleteForward
		case .deleteBackward: .deleteBackward
		case .deleteWordForward: .deleteWordForward
		case .deleteWordBackward: .deleteWordBackward
		case .deleteToBeginningOfLine: .deleteToBeginOfIndentedLine
		case .deleteToEndOfLine: .deleteToEndOfIndentedLine
		// Insertion
		case .insertNewline: .insertNewline
		case .insertTab: .insertTab
		case .insertBacktab: .insertBacktab
		// Selection
		case .selectAll: .selectAll
		}
	}
}

// MARK: - EditorViewDelegate

extension TMDocumentEditor: EditorViewDelegate {
	public func editorView(_: EditorView, insertText text: String, replacementRange _: NSRange) {
		beginChangeGrouping()
		editor.insertText(text)
		endChangeGrouping()
		syncAfterEdit()
	}

	public func editorView(_: EditorView, performAction action: EditorViewAction) {
		let editorAction = Self.editorAction(from: action)
		let needsGroup = editorAction.isDeletion || editorAction.isClipboard || editorAction.isTextTransform
		if needsGroup { beginChangeGrouping() }
		editor.perform(editorAction)
		if needsGroup { endChangeGrouping() }

		if editorAction.isDeletion || editorAction.isClipboard || editorAction.isTextTransform {
			syncAfterEdit()
		} else {
			// Movement / selection only — just update the view's carets.
			syncSelectionToView()
		}
	}

	public func editorView(_: EditorView, didClickAtLine line: Int, index: Int, event: NSEvent) {
		let offset = editor.buffer.lineStart(line) + index
		let position = editor.buffer.convert(offset: min(offset, editor.buffer.size))

		if event.modifierFlags.contains(.option) {
			// Add cursor.
			var ranges = editor.selections.selections
			ranges.append(TMCore.TextRange(caret: position))
			editor.selections = SelectionState(ranges)
		} else {
			editor.selections = SelectionState(caret: position)
		}
		syncSelectionToView()
	}

	public func editorView(_: EditorView, didDragToLine line: Int, index: Int, event _: NSEvent) {
		guard let anchor = editor.selections.primary?.anchor else { return }
		let offset = editor.buffer.lineStart(line) + index
		let head = editor.buffer.convert(offset: min(offset, editor.buffer.size))
		editor.selections = SelectionState([TMCore.TextRange(anchor: anchor, head: head)])
		syncSelectionToView()
	}

	public func editorViewDidDoubleClick(_: EditorView, event _: NSEvent) {
		editor.perform(.selectWord)
		syncSelectionToView()
	}

	public func editorViewDidTripleClick(_: EditorView, event _: NSEvent) {
		editor.perform(.selectLine)
		syncSelectionToView()
	}

	public func editorView(_: EditorView, doCommandBySelector selector: Selector) {
		let selectorName = NSStringFromSelector(selector)
		if let action = EditorAction(selector: selectorName) {
			let needsGroup = action.isDeletion || action.isClipboard || action.isTextTransform
			if needsGroup { beginChangeGrouping() }
			editor.perform(action)
			if needsGroup { endChangeGrouping() }

			if action.isDeletion || action.isClipboard || action.isTextTransform || action.isFindReplace {
				syncAfterEdit()
			} else {
				syncSelectionToView()
			}
		}
	}
}
