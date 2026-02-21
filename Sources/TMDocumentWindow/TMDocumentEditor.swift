import AppKit
import TMBundleRuntime
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMGrammar
import TMServices
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

	/// Callback to execute a bundle command (e.g., drag commands).
	/// Set by the window controller to route through the command pipeline.
	public var onExecuteBundleCommand: ((BundleCommand) async -> Void)?

	/// Whether auto-pairing (smart typing pairs) is enabled.
	public var autoPairingEnabled: Bool = true

	/// Smart typing pairs for the current scope (e.g. `[("(", ")"), ("[", "]")]`).
	/// Injected from the scope-preferences layer; falls back to defaults.
	public var smartTypingPairs: [Editor.TypingPair] = Editor.defaultSmartTypingPairs

	/// Whether continuous spell checking is enabled for this editor.
	public var isContinuousSpellCheckingEnabled: Bool = false {
		didSet {
			editorView?.isContinuousSpellCheckingEnabled = isContinuousSpellCheckingEnabled
			if isContinuousSpellCheckingEnabled {
				recheckSpelling()
			} else {
				spellCheckCache.removeAll()
				editorView?.needsDisplay = true
			}
		}
	}

	/// The spell checking language (nil = auto-detect).
	public var spellingLanguage: String?

	/// Document-scoped spell check tag.
	public let spellDocumentTag = SpellCheckService.DocumentTag()

	/// Cached misspelled ranges per hard line index.
	private var spellCheckCache: [Int: [MisspelledRange]] = [:]

	/// The macro recorder for this editor.
	public let macroRecorder = MacroRecorder()

	/// The fold data source bridging TextBuffer to FoldManager.
	private var foldDataSource: TextBufferFoldDataSource?

	/// The code folding manager for this editor.
	public private(set) var foldManager: FoldManager?

	/// Grammar-based fold info provider (compiled fold markers).
	private var grammarFoldProvider: GrammarFoldProvider?

	/// Grammar-aware indent pattern provider.
	private var indentPatternProvider: IndentPatternProvider?

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

		// Wire the misspelling provider into the layout manager.
		editorView.layoutManager.misspellingProvider = { [weak self] lineIndex in
			self?.misspellingsForLine(lineIndex) ?? []
		}

		// Set up code folding.
		let ds = TextBufferFoldDataSource(buffer: editor.buffer)
		foldDataSource = ds
		let fm = FoldManager(dataSource: ds)
		foldManager = fm
		editorView.layoutManager.foldManager = fm

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
	func syncAfterEdit() {
		let text = editor.text
		document.setContent(text)
		editorView?.setText(text)

		// Re-sync the parser with the full text.
		// In a future phase, this can be optimized to only replace
		// the changed lines using IncrementalParser.replaceLines.
		syntaxHighlighter.setText(text)
		syntaxHighlighter.parseSync()

		// Invalidate spell check cache so misspellings re-compute on draw.
		invalidateSpellCheckCache()

		syncSelectionToView()
	}

	/// Updates the view's carets and selection ranges to match the editor state.
	func syncSelectionToView() {
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

		// Configure grammar-based fold markers.
		configureFoldMarkers(registry: registry, scope: resolvedScope)

		// Configure grammar-aware indentation.
		configureIndentPatterns(scope: resolvedScope)

		// Parse the current content.
		if let text = document.content {
			syntaxHighlighter.setText(text)
			syntaxHighlighter.parseSync()
			editorView?.needsDisplay = true
		}
	}

	/// Configures grammar-aware indent patterns from bundle preferences.
	private func configureIndentPatterns(scope: String?) {
		let provider = IndentPatternProvider(
			buffer: editor.buffer,
			tabSize: editor.tabSize,
			indentUsingSpaces: editor.indentUsingSpaces,
		)
		provider.configure(bundleIndex: bundleIndex, scope: scope)

		if provider.hasPatterns {
			indentPatternProvider = provider
			editor.indentProvider = { [weak provider] line in
				provider?.indentAfterLine(line) ?? ""
			}
		} else {
			indentPatternProvider = nil
			editor.indentProvider = nil
		}
	}

	/// Configures fold markers from grammar definitions and/or bundle
	/// preferences, mirroring the C++ `setup_patterns()` in folds.cc.
	private func configureFoldMarkers(registry: GrammarRegistry, scope: String?) {
		guard let scope, let foldDataSource else { return }

		let provider = GrammarFoldProvider(buffer: editor.buffer)
		provider.tabSize = editor.tabSize
		provider.configure(
			grammarDefinition: registry.definition(forScope: scope),
			bundleIndex: bundleIndex,
			scope: scope,
		)

		if provider.hasPatterns {
			grammarFoldProvider = provider
			foldDataSource.foldInfoProvider = { [weak provider] line in
				provider?.foldInfo(forLine: line) ?? FoldManager.LineInfo()
			}
		} else {
			grammarFoldProvider = nil
			foldDataSource.foldInfoProvider = nil
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
		if autoPairingEnabled, text.count == 1, !smartTypingPairs.isEmpty {
			editor.insertWithPairing(text, pairs: smartTypingPairs)
		} else {
			editor.insertText(text)
		}
		macroRecorder.record(action: .nop, text: text)
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
		macroRecorder.record(action: editorAction)
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

		// Map Escape (cancelOperation:) to completion, mirroring the C++
		// OakTextView::cancelOperation: → complete: mapping.
		let effectiveName = selectorName == "cancelOperation:" ? "complete:" : selectorName

		if let action = EditorAction(selector: effectiveName) {
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

	public func editorView(_: EditorView, performKeyEquivalent event: NSEvent) -> Bool {
		guard let bundleIndex else { return false }

		// Convert the event to a key equivalent string for bundle lookup.
		let keyEquiv = keyEquivalentString(from: event)
		guard !keyEquiv.isEmpty else { return false }

		let matches = bundleIndex.query(BundleQuery(
			field: .keyEquivalent,
			value: keyEquiv,
			kinds: .executable,
		))
		guard let item = matches.first else { return false }

		// Execute the matched bundle item.
		if item.kind.contains(.snippet), let content = item.plist?["content"] as? String {
			beginChangeGrouping()
			insertSnippetWithExpansion(content)
			endChangeGrouping()
			return true
		}

		// For commands, the execution pipeline handles it. Signal that we matched.
		return true
	}

	public func editorView(_: EditorView, fontScaleDidChange scale: CGFloat) {
		guard let view = editorView else { return }
		let currentSize = view.layoutManager.font.pointSize
		let newSize = max(6, min(currentSize * scale, 200))
		let newFont = NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
		view.layoutManager.setFont(newFont)
		view.needsDisplay = true
	}

	public func editorView(_: EditorView, didReceiveFileDrop urls: [URL], atLine _: Int, index _: Int) {
		let paths = urls.map(\.path)
		let extensions = urls.compactMap { $0.pathExtension.isEmpty ? nil : $0.pathExtension.lowercased() }

		if let bundleIndex, let onExecuteBundleCommand {
			let handler = DragCommandHandler(bundleIndex: bundleIndex)
			let scope = syntaxHighlighter.activeScope ?? ""
			let commands = handler.findCommands(forFileExtensions: extensions, scope: scope)
			if let cmd = commands.first {
				let bundleCmd = handler.buildBundleCommand(from: cmd, droppedFiles: paths)
				Task { @MainActor in
					await onExecuteBundleCommand(bundleCmd)
				}
				return
			}
		}

		// Fallback: insert file paths at caret.
		let text = paths.joined(separator: "\n")
		beginChangeGrouping()
		editor.insertText(text)
		endChangeGrouping()
		syncAfterEdit()
	}

	public func editorViewNeedsContextMenu(_: EditorView, for _: NSEvent) -> NSMenu? {
		let menu = NSMenu()
		menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
		menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
		menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
		menu.addItem(.separator())
		menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
		return menu
	}

	public func editorView(_: EditorView, validateMenuItem menuItem: NSMenuItem) -> Bool {
		let action = menuItem.action
		if action == #selector(NSText.cut(_:)) || action == #selector(NSText.copy(_:)) {
			return editor.hasSelection
		}
		return true
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
			let hasMirrors = !state.mirrors.isEmpty
			let session = SnippetController.Session(
				snippetText: expandedText,
				tabStops: tabStops,
				baseOffset: baseOffset,
				snippetState: hasMirrors ? state : nil,
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

// MARK: - Key Equivalent String

extension TMDocumentEditor {
	/// Converts an NSEvent to the TextMate key equivalent string format.
	///
	/// Uses the `@` (Cmd), `^` (Ctrl), `~` (Option), `$` (Shift) modifier
	/// prefix notation followed by the key character.
	func keyEquivalentString(from event: NSEvent) -> String {
		guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return "" }
		let flags = event.modifierFlags
		var result = ""
		if flags.contains(.control) { result += "^" }
		if flags.contains(.option) { result += "~" }
		if flags.contains(.shift) { result += "$" }
		if flags.contains(.command) { result += "@" }
		result += chars.lowercased()
		return result
	}
}

// MARK: - Spell Checking

extension TMDocumentEditor {
	/// Rechecks spelling for all lines and invalidates the display.
	func recheckSpelling() {
		guard isContinuousSpellCheckingEnabled else { return }
		spellCheckCache.removeAll()
		editorView?.needsDisplay = true
	}

	/// Returns misspelled ranges for a specific line.
	/// Uses a per-line cache that is invalidated on edits.
	func misspellingsForLine(_ lineIndex: Int) -> [MisspelledRange] {
		guard isContinuousSpellCheckingEnabled else { return [] }

		if let cached = spellCheckCache[lineIndex] {
			return cached
		}

		guard let lineText = editorView?.layoutManager.lineText(lineIndex),
		      !lineText.isEmpty
		else {
			spellCheckCache[lineIndex] = []
			return []
		}

		let serviceRanges = SpellCheckService.shared.spellCheck(
			lineText,
			language: spellingLanguage,
			tag: spellDocumentTag,
		)

		let result = serviceRanges.map {
			MisspelledRange(from: $0.start, to: $0.end)
		}
		spellCheckCache[lineIndex] = result
		return result
	}

	/// Invalidates the spell check cache after an edit.
	func invalidateSpellCheckCache() {
		spellCheckCache.removeAll()
	}

	/// Returns spelling suggestions for the word at a given point.
	func spellingSuggestions(at point: NSPoint) -> [String] {
		guard let view = editorView else { return [] }
		let localPoint = view.convert(point, from: nil)
		let (line, idx) = view.layoutManager.characterIndex(at: localPoint)

		guard let lineText = view.layoutManager.lineText(line), !lineText.isEmpty else { return [] }

		// Find the word boundaries around the clicked position.
		let chars = Array(lineText)
		var wordStart = min(idx, chars.count - 1)
		var wordEnd = wordStart

		while wordStart > 0, chars[wordStart - 1].isLetter || chars[wordStart - 1] == "'" {
			wordStart -= 1
		}
		while wordEnd < chars.count, chars[wordEnd].isLetter || chars[wordEnd] == "'" {
			wordEnd += 1
		}

		guard wordEnd > wordStart else { return [] }
		let word = String(chars[wordStart ..< wordEnd])

		return SpellCheckService.shared.suggestions(for: word, language: spellingLanguage)
	}
}

// MARK: - Spell Delegate Methods

public extension TMDocumentEditor {
	func editorViewSpellDocumentTag(_: EditorView) -> Int {
		spellDocumentTag.value()
	}

	func editorView(_: EditorView, misspellingsForLine lineIndex: Int) -> [MisspelledRange] {
		misspellingsForLine(lineIndex)
	}

	func editorView(_: EditorView, spellingSuggestionsAt point: NSPoint) -> [String] {
		spellingSuggestions(at: point)
	}
}

// MARK: - Macro Recording & Playback

public extension TMDocumentEditor {
	/// Toggles macro recording on/off.
	/// Returns the completed macro if recording was stopped.
	@discardableResult
	func toggleMacroRecording() -> MacroRecorder.Macro? {
		macroRecorder.toggleRecording()
	}

	/// Replays the last recorded macro through the editor.
	func replayMacro() {
		guard let macro = macroRecorder.lastMacro, !macro.isEmpty else { return }
		beginChangeGrouping()
		macroRecorder.replay(macro: macro) { [weak self] action in
			guard let self else { return }
			if let text = action.text {
				editor.insertText(text)
			} else {
				editor.perform(action.action)
			}
		}
		endChangeGrouping()
		syncAfterEdit()
	}
}

// MARK: - Code Folding

public extension TMDocumentEditor {
	/// Toggle a fold at the given 0-based line index.
	///
	/// - Returns: The affected range, or `nil` if nothing changed.
	@discardableResult
	func toggleFold(atLine line: Int, recursive: Bool = false) -> (from: Int, to: Int)? {
		guard let fm = foldManager else { return nil }
		let result = fm.toggleAtLine(line, recursive: recursive)
		guard result.from < result.to else { return nil }
		editorView?.layoutManager.invalidateFolds()
		editorView?.updateFrameSize()
		editorView?.needsDisplay = true
		return result
	}

	/// Toggle all folds at the given nesting level (0 = all).
	func toggleAllFolds(atLevel level: Int) {
		guard let fm = foldManager else { return }
		_ = fm.toggleAllAtLevel(level)
		editorView?.layoutManager.invalidateFolds()
		editorView?.updateFrameSize()
		editorView?.needsDisplay = true
	}

	/// Returns the set of 1-based line numbers that have fold markers.
	func foldableLineNumbers() -> Set<Int> {
		guard let fm = foldManager else { return [] }
		var result = Set<Int>()
		let lineCount = editor.buffer.lines
		for n in 0 ..< lineCount {
			if fm.hasStartMarker(line: n) {
				result.insert(n + 1)
			}
		}
		return result
	}

	/// Returns the set of 1-based line numbers that are currently folded.
	func foldedLineNumbers() -> Set<Int> {
		guard let fm = foldManager else { return [] }
		var result = Set<Int>()
		let lineCount = editor.buffer.lines
		for n in 0 ..< lineCount {
			if fm.hasFolded(line: n) {
				result.insert(n + 1)
			}
		}
		return result
	}

	/// Serialized fold state for session persistence.
	var foldedAsString: String? {
		foldManager?.foldedAsString()
	}

	/// Restore fold state from a serialized string.
	func restoreFolds(from string: String) {
		foldManager?.setFolded(fromString: string)
		editorView?.layoutManager.invalidateFolds()
		editorView?.updateFrameSize()
		editorView?.needsDisplay = true
	}
}
