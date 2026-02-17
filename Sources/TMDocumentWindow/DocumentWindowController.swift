import AppKit
import TMAppKit
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMGrammar
import TMSearchReplace
import TMTheme

/// The main document window controller, managing the layout that matches
/// TextMate's window structure:
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │ Tab Bar                                 │
/// ├────────────┬────────────────────────────┤
/// │ File       │ Gutter │ Editor (EditorView) │
/// │ Browser    │        │                   │
/// │ (sidebar)  │        │                   │
/// │            │        │                   │
/// ├────────────┴────────┴───────────────────┤
/// │ Live Search Bar (optional)              │
/// ├─────────────────────────────────────────┤
/// │ Status Bar                              │
/// └─────────────────────────────────────────┘
/// ```
@MainActor
public class DocumentWindowController: NSWindowController {
	public let tabBarView = TabBarView()
	public let fileBrowserView = FileBrowserView()
	public let gutterView = GutterView()
	public let statusBarView = StatusBarView()
	public let editorView = EditorView()
	public let liveSearchBar = LiveSearchBarView()

	/// The document model for the currently displayed file.
	public private(set) var textDocument: TMDocument

	/// The bridge connecting the document, editor engine, and editor view.
	public private(set) var documentEditor: TMDocumentEditor?

	/// Shared clipboards for copy/paste/find/replace across editors.
	public let clipboards = ClipboardSet()

	/// Grammar registry for syntax highlighting (optional).
	public var grammarRegistry: GrammarRegistry?

	/// Theme engine for scope-based styling (optional).
	public var themeEngine: ThemeEngine?

	private let splitView = NSSplitView()
	private let editorContainer = NSView()
	private let scrollView = NSScrollView()

	private var fileBrowserWidth: CGFloat = 200
	private var isFileBrowserVisible = true

	/// Incremental search state backing the live search bar.
	public let incrementalSearch = IncrementalSearchState()

	/// Constraint anchoring the split view bottom to the live search bar.
	private var splitViewBottomConstraint: NSLayoutConstraint?

	/// Height constraint for the live search bar (0 when hidden).
	private var searchBarHeightConstraint: NSLayoutConstraint?

	private var currentTheme: Theme?

	/// Creates a new document window with the standard TextMate layout.
	public init(document: TMDocument? = nil) {
		textDocument = document ?? TMDocument()

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
			styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false,
		)
		window.setFrameAutosaveName("DocumentWindow")
		window.titlebarAppearsTransparent = false
		window.isReleasedWhenClosed = false
		window.minSize = NSSize(width: 400, height: 300)
		window.center()

		super.init(window: window)
		setupLayout()
		wireDocumentEditor()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Public API

	/// Apply a theme to the editor content area only.
	///
	/// Chrome (tab bar, status bar, gutter, file browser) follows system
	/// appearance (light/dark mode) and is NOT affected by custom themes.
	public func applyTheme(_ theme: Theme) {
		currentTheme = theme

		// Editor content
		let bg = theme.globalSettings.background.nsColor
		let fg = theme.globalSettings.foreground.nsColor
		editorView.layoutManager.backgroundColor = bg
		editorView.layoutManager.foregroundColor = fg
		editorView.caretColor = theme.globalSettings.caret.nsColor
		editorView.selectionColor = theme.globalSettings.selection.nsColor
		scrollView.backgroundColor = bg
	}

	/// Set the project root for the file browser.
	public func setProjectRoot(_ url: URL) {
		fileBrowserView.rootURL = url
		window?.title = url.lastPathComponent
	}

	/// Open a file, detecting its encoding automatically.
	public func openFile(at url: URL) {
		let doc = TMDocument(path: url.path)
		Task { @MainActor in
			do {
				try await doc.load()
				self.textDocument = doc
				self.wireDocumentEditor()
				window?.title = doc.displayName
				statusBarView.setEncoding(doc.encoding.charset)
				updateWindowTitle()
			} catch {
				let alert = NSAlert(error: error)
				alert.runModal()
			}
		}
	}

	/// Save the current document. Returns `true` if the save succeeded.
	@discardableResult
	public func saveDocument() -> Bool {
		guard textDocument.path != nil else {
			return saveDocumentAs()
		}
		documentEditor?.documentWillSave()
		textDocument.setContent(documentEditor?.editor.text ?? "")
		Task { @MainActor in
			do {
				try await textDocument.save()
				updateWindowTitle()
			} catch {
				let alert = NSAlert(error: error)
				alert.runModal()
			}
		}
		return true
	}

	/// Present a Save panel and save the document. Returns `true` on success.
	@discardableResult
	public func saveDocumentAs() -> Bool {
		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.nameFieldStringValue = textDocument.displayName

		guard panel.runModal() == .OK, let url = panel.url else {
			return false
		}

		documentEditor?.documentWillSave()
		textDocument.setContent(documentEditor?.editor.text ?? "")
		textDocument.setPath(url.path)
		Task { @MainActor in
			do {
				try await textDocument.save()
				window?.title = textDocument.displayName
				updateWindowTitle()
			} catch {
				let alert = NSAlert(error: error)
				alert.runModal()
			}
		}
		return true
	}

	/// Show or activate the incremental (live) search bar.
	public func showLiveSearch() {
		searchBarHeightConstraint?.constant = LiveSearchBarView.barHeight
		window?.contentView?.layoutSubtreeIfNeeded()

		// Snapshot current buffer text and anchor at the caret.
		if let editor = documentEditor?.editor {
			let text = editor.text
			let anchor = editor.selections.primary?.head.offset ?? 0
			incrementalSearch.activate(anchorOffset: anchor, bufferText: text)
		}

		liveSearchBar.activate()
	}

	/// Hide the live search bar.
	public func hideLiveSearch() {
		incrementalSearch.deactivate()
		liveSearchBar.deactivate()
		searchBarHeightConstraint?.constant = 0
		window?.contentView?.layoutSubtreeIfNeeded()
		window?.makeFirstResponder(editorView)
	}

	/// Whether the live search bar is currently visible.
	public var isLiveSearchVisible: Bool {
		(searchBarHeightConstraint?.constant ?? 0) > 0
	}

	/// Show a transient HUD overlay in the editor view.
	public func showHUD(text: String) {
		EditorHUD.show(in: editorView, text: text)
	}

	/// Toggle file browser visibility.
	public func toggleFileBrowser() {
		isFileBrowserVisible.toggle()
		if isFileBrowserVisible {
			splitView.setPosition(fileBrowserWidth, ofDividerAt: 0)
		} else {
			fileBrowserWidth = splitView.subviews[0].frame.width
			splitView.setPosition(0, ofDividerAt: 0)
		}
	}

	// MARK: - Printing

	/// Handles File → Print by creating a ``PrintableDocumentView`` with
	/// the current document content and a ``PrintOptionsViewController``
	/// accessory panel.
	@IBAction public func printDocument(_: Any?) {
		let text = documentEditor?.editor.text ?? textDocument.content ?? ""
		let title = textDocument.displayName

		// Determine the font name from the editor view's layout manager.
		let fontName = editorView.layoutManager.font.fontName

		let printView = PrintableDocumentView(
			text: text,
			title: title,
			fontName: fontName,
			styleProvider: editorView.layoutManager.styleProvider,
		)

		// Configure the print options accessory.
		let accessory = PrintOptionsViewController()
		// Theme list can be populated if a registry is available.
		// For now, use the current theme if set.
		if let theme = currentTheme {
			accessory.availableThemes = [
				PrintOptionsViewController.ThemeEntry(name: theme.name, uuid: theme.uuid),
			]
		}

		let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
		printInfo.dictionary()[PrintSettingKey.fontSize] = NSNumber(
			value: UserDefaults.standard.integer(forKey: PrintSettingKey.fontSize),
		)
		if let uuid = UserDefaults.standard.string(forKey: PrintSettingKey.themeUUID) {
			printInfo.dictionary()[PrintSettingKey.themeUUID] = uuid
		}

		let operation = NSPrintOperation(view: printView, printInfo: printInfo)
		let panel = operation.printPanel
		panel.options.insert(.showsPreview)
		panel.addAccessoryController(accessory)

		operation.runModal(
			for: window!,
			delegate: nil,
			didRun: nil,
			contextInfo: nil,
		)
	}

	// MARK: - Private Setup

	private func setupLayout() {
		guard let contentView = window?.contentView else { return }
		contentView.wantsLayer = true

		// Tab bar at the top
		tabBarView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(tabBarView)

		// Split view: file browser | editor area
		splitView.isVertical = true
		splitView.dividerStyle = .thin
		splitView.translatesAutoresizingMaskIntoConstraints = false

		// File browser (left pane)
		fileBrowserView.translatesAutoresizingMaskIntoConstraints = false

		// Editor area (right pane): gutter + text view
		editorContainer.wantsLayer = true
		editorContainer.translatesAutoresizingMaskIntoConstraints = false

		setupEditorView()
		setupEditorContainer()

		splitView.addArrangedSubview(fileBrowserView)
		splitView.addArrangedSubview(editorContainer)
		contentView.addSubview(splitView)

		// Live search bar (initially hidden)
		liveSearchBar.translatesAutoresizingMaskIntoConstraints = false
		liveSearchBar.delegate = self
		contentView.addSubview(liveSearchBar)

		// Status bar at the bottom
		statusBarView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(statusBarView)

		let searchBarHeight = liveSearchBar.heightAnchor.constraint(equalToConstant: 0)
		searchBarHeightConstraint = searchBarHeight

		NSLayoutConstraint.activate([
			// Tab bar
			tabBarView.topAnchor.constraint(equalTo: contentView.topAnchor),
			tabBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			tabBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			tabBarView.heightAnchor.constraint(equalToConstant: tabBarView.tabBarHeight),

			// Split view
			splitView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
			splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			splitView.bottomAnchor.constraint(equalTo: liveSearchBar.topAnchor),

			// Live search bar
			liveSearchBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			liveSearchBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			liveSearchBar.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),
			searchBarHeight,

			// File browser min width
			fileBrowserView.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

			// Status bar
			statusBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			statusBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			statusBarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
		])

		// Set initial sidebar width
		splitView.setPosition(fileBrowserWidth, ofDividerAt: 0)
	}

	private func setupEditorView() {
		editorView.layoutManager.setFont(.monospacedSystemFont(ofSize: 13, weight: .regular))
		editorView.translatesAutoresizingMaskIntoConstraints = false

		scrollView.documentView = editorView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
	}

	private func setupEditorContainer() {
		gutterView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		editorContainer.addSubview(gutterView)
		editorContainer.addSubview(scrollView)

		NSLayoutConstraint.activate([
			gutterView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
			gutterView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
			gutterView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
			gutterView.widthAnchor.constraint(equalToConstant: gutterView.gutterWidth),

			scrollView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
		])
	}

	private func updateWindowTitle() {
		let title = textDocument.displayName
		window?.title = textDocument.isModified ? "● \(title)" : title
	}

	/// Wires or re-wires the document editor for the current document.
	private func wireDocumentEditor() {
		// Ensure the document has content (treat nil as empty for untitled).
		if textDocument.content == nil {
			textDocument.setContent("", preserveRevision: true)
		}

		documentEditor = TMDocumentEditor(
			document: textDocument,
			editorView: editorView,
			clipboards: clipboards,
		)

		// Configure syntax highlighting if a grammar registry is available.
		if let registry = grammarRegistry, let engine = themeEngine {
			documentEditor?.configureGrammar(
				registry: registry,
				themeEngine: engine,
			)
		}
	}
}

// MARK: - LiveSearchBarViewDelegate

extension DocumentWindowController: LiveSearchBarViewDelegate {
	public func liveSearchBar(_: LiveSearchBarView, searchStringDidChange text: String) {
		incrementalSearch.searchString = text
		incrementalSearch.ignoreCase = liveSearchBar.ignoreCase
		incrementalSearch.wrapAround = liveSearchBar.wrapAround
		liveSearchBar.hasNoResults = incrementalSearch.hasNoResults

		// Move selection to the current match.
		if let match = incrementalSearch.currentMatch {
			applySearchMatch(match)
		}
	}

	public func liveSearchBarDidAccept(_: LiveSearchBarView) {
		// Accept the current match position and dismiss.
		hideLiveSearch()
	}

	public func liveSearchBarDidCancel(_: LiveSearchBarView) {
		// Restore original position (anchor) and dismiss.
		if let editor = documentEditor?.editor {
			let anchor = incrementalSearch.anchorOffset
			let pos = editor.buffer.convert(offset: min(anchor, editor.buffer.size))
			editor.selections = SelectionState(caret: pos)
		}
		hideLiveSearch()
	}

	public func liveSearchBarDidRequestNext(_: LiveSearchBarView) {
		incrementalSearch.findNext()
		if let match = incrementalSearch.currentMatch {
			applySearchMatch(match)
		}
	}

	public func liveSearchBarDidRequestPrevious(_: LiveSearchBarView) {
		incrementalSearch.findPrevious()
		if let match = incrementalSearch.currentMatch {
			applySearchMatch(match)
		}
	}

	/// Moves the editor selection to encompass a search match.
	private func applySearchMatch(_ match: FindMatch) {
		guard let editor = documentEditor?.editor else { return }
		let start = editor.buffer.convert(offset: min(match.range.lowerBound, editor.buffer.size))
		let end = editor.buffer.convert(offset: min(match.range.upperBound, editor.buffer.size))
		let range = TMCore.TextRange(anchor: start, head: end)
		editor.selections = SelectionState([range])

		// Sync the view.
		let pos = editor.buffer.convert(offset: end.offset)
		editorView.carets = [(pos.line, pos.column)]
		editorView.selectionRanges = [
			(start: (start.line, start.column), end: (end.line, end.column)),
		]
		editorView.scrollToCaret()
	}
}
