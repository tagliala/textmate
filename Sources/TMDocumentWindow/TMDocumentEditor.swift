import AppKit
import TMBundleRuntime
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMGrammar
import TMTheme

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

	/// Syntax highlighter that bridges grammar parser + theme engine
	/// to produce style runs for the layout manager.
	public let syntaxHighlighter = SyntaxHighlighter()

	/// The completion choice menu (floating panel).
	private var choiceMenu: ChoiceMenuPanel?

	/// Nesting level for undo change groups.
	private var changeGroupLevel: Int = 0

	/// Observation token for document change callbacks.
	private var documentObservationID: UUID?

	/// Bundle index for tab trigger lookup (injected from the app layer).
	public var bundleIndex: BundleIndex?

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

		// Wire syntax highlighting into the layout manager.
		setupSyntaxHighlighting(editorView: editorView)

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

		// Re-sync the parser with the full text.
		// In a future phase, this can be optimized to only replace
		// the changed lines using IncrementalParser.replaceLines.
		syntaxHighlighter.setText(text)
		syntaxHighlighter.parseSync()

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

			// Re-parse the new content.
			syntaxHighlighter.setText(docContent)
			syntaxHighlighter.parseSync()

			syncSelectionToView()
		}
	}

	/// Reloads the editor content from the backing document.
	///
	/// Call this after the document has been reloaded from disk.
	public func reloadFromDocument() {
		documentDidChange()
	}

	// MARK: - Syntax Highlighting Setup

	/// Configures the syntax highlighting pipeline for an editor view.
	private func setupSyntaxHighlighting(editorView: EditorView) {
		// Wire the style provider: the layout manager will call back
		// into the syntax highlighter when it needs style runs for a line.
		editorView.layoutManager.styleProvider = syntaxHighlighter.makeStyleProvider()

		// When the parser reports changed lines, invalidate the layout.
		syntaxHighlighter.onStylesChanged = { [weak editorView] range in
			editorView?.layoutManager.invalidateStyles(from: range.lowerBound, to: range.upperBound)
			editorView?.needsDisplay = true
		}
	}

	/// Configures the grammar and theme for syntax highlighting.
	///
	/// Call this after loading a document to enable scope-based coloring.
	///
	/// - Parameters:
	///   - grammarRegistry: The registry of available grammars.
	///   - themeEngine: The theme engine for scope → style resolution.
	///   - scope: The grammar scope (e.g. "source.swift"), or `nil`
	///     to auto-detect from the document's file extension.
	public func configureGrammar(
		registry: GrammarRegistry,
		themeEngine: ThemeEngine,
		scope: String? = nil,
	) {
		syntaxHighlighter.setGrammarRegistry(registry)
		syntaxHighlighter.setThemeEngine(themeEngine)

		let resolvedScope = scope ?? detectScope()
		syntaxHighlighter.setGrammar(scope: resolvedScope)

		// Parse the current content.
		if let text = document.content {
			syntaxHighlighter.setText(text)
			syntaxHighlighter.parseSync()
			editorView?.needsDisplay = true
		}
	}

	/// Auto-detects the grammar scope from the document's file path.
	private func detectScope() -> String? {
		guard let path = document.path else { return nil }
		let detector = FileTypeDetector()
		let result = detector.detect(path: path, content: document.content)
		return result.scope
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
		dismissChoiceMenu()
		beginChangeGrouping()
		editor.insertText(text)
		endChangeGrouping()
		syncAfterEdit()
	}

	public func editorView(_: EditorView, performAction action: EditorViewAction) {
		// Intercept Tab to check for tab trigger expansion before passing to editor.
		if action == .insertTab, editor.snippetController.isEmpty {
			if expandTabTrigger() {
				syncAfterEdit()
				return
			}
		}

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
		dismissChoiceMenu()
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
			let isCompletion = action == .complete || action == .nextCompletion || action == .previousCompletion
			let needsGroup = action.isDeletion || action.isClipboard || action.isTextTransform || isCompletion
			if needsGroup { beginChangeGrouping() }
			editor.perform(action)
			if needsGroup { endChangeGrouping() }

			if isCompletion {
				syncAfterEdit()
				updateChoiceMenu()
			} else if action.isDeletion || action.isClipboard || action.isTextTransform || action.isFindReplace {
				syncAfterEdit()
				dismissChoiceMenu()
			} else {
				syncSelectionToView()
				dismissChoiceMenu()
			}
		}
	}
}

// MARK: - Completion UI

extension TMDocumentEditor {
	/// Shows or updates the choice menu with current completion suggestions.
	private func updateChoiceMenu() {
		guard editor.isCompletionActive else {
			dismissChoiceMenu()
			return
		}

		let suggestions = editor.completionSuggestions
		guard !suggestions.isEmpty else {
			dismissChoiceMenu()
			return
		}

		// If there's exactly one suggestion and it was just inserted, dismiss.
		if suggestions.count == 1, editor.completionIndex == 0 {
			// Single completion: already applied, just dismiss.
			dismissChoiceMenu()
			return
		}

		let menu = choiceMenu ?? createChoiceMenu()
		menu.choices = suggestions
		menu.choiceIndex = editor.completionIndex

		if !menu.isMenuVisible, let view = editorView {
			let screenPoint = caretScreenPoint(in: view)
			menu.show(at: screenPoint, in: view)
		}
	}

	/// Dismisses the choice menu and cancels the completion session.
	private func dismissChoiceMenu() {
		if editor.isCompletionActive {
			editor.cancelCompletion()
		}
		choiceMenu?.dismiss()
	}

	/// Creates and configures the choice menu panel.
	private func createChoiceMenu() -> ChoiceMenuPanel {
		let menu = ChoiceMenuPanel(
			font: editorView?.layoutManager.font ?? .monospacedSystemFont(
				ofSize: NSFont.systemFontSize,
				weight: .regular,
			),
		)
		choiceMenu = menu
		return menu
	}

	/// Computes the screen point at the primary caret position.
	private func caretScreenPoint(in view: EditorView) -> NSPoint {
		guard let primary = editor.selections.primary else {
			return view.frame.origin
		}
		let pos = editor.buffer.convert(offset: primary.head.offset)
		let localPoint = view.layoutManager.point(
			forLine: pos.line,
			characterIndex: pos.column,
		)
		// Place the menu below the caret line.
		let belowCaret = NSPoint(
			x: localPoint.x,
			y: localPoint.y + view.layoutManager.defaultLineHeight,
		)
		guard let window = view.window else { return belowCaret }
		return window.convertPoint(toScreen: view.convert(belowCaret, to: nil))
	}
}

// MARK: - Tab Trigger Expansion & Snippet Insertion

extension TMDocumentEditor {
	/// Expands a tab trigger at the caret position, if one matches.
	///
	/// Scans backward from the caret for identifier characters, queries the
	/// bundle index for a matching tab trigger, and inserts the snippet.
	///
	/// - Returns: `true` if a trigger was expanded.
	func expandTabTrigger() -> Bool {
		guard let bundleIndex else { return false }
		guard let primary = editor.selections.primary, primary.isEmpty else { return false }

		let caretOffset = primary.head.offset
		guard caretOffset > 0 else { return false }

		// Scan backward for word characters to find the trigger text.
		let bufString = editor.buffer.string
		let utf8 = bufString.utf8
		var startOffset = caretOffset
		while startOffset > 0 {
			let prevIdx = utf8.index(utf8.startIndex, offsetBy: startOffset - 1)
			let byte = utf8[prevIdx]
			// Accept ASCII word characters: [a-zA-Z0-9_.]
			if (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) ||
				(byte >= 0x30 && byte <= 0x39) || byte == 0x5F || byte == 0x2E
			{
				startOffset -= 1
			} else {
				break
			}
		}

		guard startOffset < caretOffset else { return false }
		let trigger = editor.buffer.substring(from: startOffset, to: caretOffset)
		guard !trigger.isEmpty else { return false }

		// Query for matching tab trigger.
		let matches = bundleIndex.query(BundleQuery(
			field: .tabTrigger,
			value: trigger,
			kinds: [.snippet, .command],
		))
		guard let item = matches.first else { return false }

		// Extract snippet content from the bundle item's plist.
		guard item.kind.contains(.snippet),
		      let content = item.plist?["content"] as? String
		else { return false }

		// Select the trigger text so insertText will replace it.
		let startPos = editor.buffer.convert(offset: startOffset)
		let endPos = editor.buffer.convert(offset: caretOffset)
		editor.selections = SelectionState([TMCore.TextRange(anchor: startPos, head: endPos)])

		// Insert the snippet with full expansion.
		insertSnippetWithExpansion(content)
		return true
	}

	/// Parses a snippet body and inserts it with full tab-stop support.
	///
	/// Replaces the current selection with the expanded snippet text and pushes
	/// a snippet session for tab-stop navigation.
	///
	/// - Parameters:
	///   - snippet: The raw snippet body (with `$1`, `${2:placeholder}`, etc.).
	///   - disableAutoIndent: If `true`, skips indent adjustment.
	public func insertSnippetWithExpansion(
		_ snippet: String,
		disableAutoIndent: Bool = false,
	) {
		// Determine indent string from the current line.
		var indentString = ""
		if !disableAutoIndent, let primary = editor.selections.primary {
			let lineStart = editor.buffer.lineStart(primary.head.line)
			let lineText = editor.buffer.substring(
				from: lineStart,
				to: min(lineStart + 256, editor.buffer.size),
			)
			for ch in lineText {
				if ch == "\t" || ch == " " { indentString.append(ch) } else { break }
			}
		}

		// Parse the snippet.
		let state = SnippetState.parse(snippet, indentString: indentString)
		let expandedText = state.text

		// Record the insertion base offset (start of current selection).
		let baseOffset: Int = if let primary = editor.selections.primary {
			primary.start.offset
		} else {
			0
		}

		// Insert the expanded text (replaces current selection).
		beginChangeGrouping()
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
		// Add $0 (exit) as the last tab stop.
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

		// Push the snippet session and select the first tab stop.
		if !tabStops.isEmpty {
			let session = SnippetController.Session(
				snippetText: expandedText,
				tabStops: tabStops,
			)
			editor.snippetController.push(session)

			// Select the first tab stop.
			if let first = tabStops.first {
				editor.selections = SelectionState([first.range])
			}
		}

		endChangeGrouping()
		syncAfterEdit()
	}
}
