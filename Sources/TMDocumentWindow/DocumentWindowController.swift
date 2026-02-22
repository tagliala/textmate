import AppKit
import ObjectiveC
import TMAppKit
import TMBundleRuntime
import TMBundleUI
import TMCompatibility
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMFileBrowser
import TMGrammar
import TMSCM
import TMSearchReplace
import TMServices
import TMSettings
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
public class DocumentWindowController: NSWindowController, NSMenuItemValidation {
	public let tabBarView = TabBarView()
	public let fileBrowserController = FileBrowserViewController()
	public let gutterView = GutterView()
	public let statusBarView = StatusBarView()
	public let editorView = EditorView()
	public let liveSearchBar = LiveSearchBarView()
	public let projectLayoutView = ProjectLayoutView()

	// MARK: - Multi-Document State

	/// Unique identifier for this window controller (used by AllControllers registry).
	public var identifier: UUID? {
		didSet {
			if let old = oldValue { Self.allControllers.removeValue(forKey: old) }
			if let id = identifier { Self.allControllers[id] = self }
		}
	}

	/// All open documents in tab order.
	public internal(set) var documents: [TMDocument] = [] {
		didSet {
			updateTabBar()
			Self.scheduleSessionBackup()
		}
	}

	/// The index of the currently selected tab.
	public internal(set) var selectedTabIndex: Int = 0

	/// UUIDs of documents marked as "sticky" (won't auto-close).
	public internal(set) var stickyDocumentIdentifiers: Set<UUID> = []

	/// The effective project path (derived from document or explicitly set).
	public internal(set) var projectPath: String?

	/// The default project path set by the user or session restore.
	public var defaultProjectPath: String?

	/// The currently selected document (forwarding to documents array).
	public var selectedDocument: TMDocument? {
		guard selectedTabIndex >= 0, selectedTabIndex < documents.count else { return nil }
		return documents[selectedTabIndex]
	}

	/// The document model for the currently displayed file.
	/// - Note: Legacy property; prefer `selectedDocument` for multi-tab workflows.
	public internal(set) var textDocument: TMDocument

	/// The bridge connecting the document, editor engine, and editor view.
	public private(set) var documentEditor: TMDocumentEditor?

	/// Shared clipboards for copy/paste/find/replace across editors.
	public let clipboards = ClipboardSet()

	/// Grammar registry for syntax highlighting (optional).
	public var grammarRegistry: GrammarRegistry?

	/// Theme engine for scope-based styling (optional).
	public var themeEngine: ThemeEngine?

	/// Bundle index for tab trigger lookup (optional, injected from app layer).
	public var bundleIndex: BundleIndex?

	/// Command dispatcher for executing bundle commands (injected from app layer).
	public var commandDispatcher: CommandDispatcher?

	/// Scheduler for auto-refresh commands (re-executes on save, change, close).
	public var autoRefreshScheduler: AutoRefreshScheduler?

	/// Registry of all active window controllers, keyed by identifier.
	public nonisolated(unsafe) static var allControllers: [UUID: DocumentWindowController] = [:]

	let editorContainer = NSView()
	let scrollView = NSScrollView()
	var gutterWidthConstraint: NSLayoutConstraint?

	var fileBrowserWidth: CGFloat {
		get { projectLayoutView.fileBrowserWidth }
		set { projectLayoutView.fileBrowserWidth = newValue }
	}

	var isFileBrowserVisible = true

	/// Whether gutter line numbers are visible.
	var isLineNumbersVisible = true

	/// Whether spell checking is enabled for the current document.
	var isSpellCheckingEnabled = false

	/// Document-scoped spell check tag for tracking learned words.
	public lazy var spellDocumentTag = SpellCheckService.DocumentTag()

	/// Tracks modified state so UI only updates when it flips.
	private var lastKnownModifiedState = false

	/// File watcher for detecting external changes to open documents.
	private var fileWatcher: FileWatcher?

	/// Watch tokens keyed by document path.
	private var watchTokens: [String: FileWatcher.WatchToken] = [:]

	/// Incremental search state backing the live search bar.
	public let incrementalSearch = IncrementalSearchState()

	/// Height constraint for the live search bar (0 when hidden).
	private var searchBarHeightConstraint: NSLayoutConstraint?

	var currentTheme: Theme?

	/// Creates a new document window with the standard TextMate layout.
	public init(document: TMDocument? = nil) {
		let doc = document ?? TMDocument()
		textDocument = doc

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
		window.collectionBehavior = [.fullScreenPrimary]
		window.isRestorable = false
		window.center()

		super.init(window: window)

		identifier = UUID()
		// didSet is not called during init, so register manually.
		if let id = identifier { Self.allControllers[id] = self }
		documents = [doc]
		selectedTabIndex = 0

		setupLayout()
		tabBarView.windowIdentifier = identifier
		wireDocumentEditor()

		// Set ourselves as the window delegate for lifecycle events.
		window.delegate = self
	}

	deinit {
		fileWatcher?.unwatchAll()
		if let id = identifier {
			Self.allControllers.removeValue(forKey: id)
		}
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

		// Gutter
		let gs = theme.gutterSettings
		gutterView.foregroundColor = gs.foreground.nsColor
		gutterView.backgroundColor = gs.background.nsColor
		gutterView.selectedForegroundColor = gs.selectionForeground.nsColor
		gutterView.selectedBackgroundColor = gs.selectionBackground.nsColor

		// Update syntax highlighting theme engine for live reload.
		let engine = ThemeEngine(theme: theme)
		themeEngine = engine
		documentEditor?.syntaxHighlighter.setThemeEngine(engine)
		editorView.layoutManager.invalidateAllLines()
	}

	/// Set the project root for the file browser.
	public func setProjectRoot(_ url: URL) {
		projectPath = url.path
		fileBrowserController.goToURL(url)
		window?.title = url.lastPathComponent
	}

	/// Open a file, detecting its encoding automatically.
	public func openFile(at url: URL) {
		// Check if the file is already open in this window.
		if let idx = documents.firstIndex(where: { $0.path == url.path }) {
			openAndSelectDocument(documents[idx], activate: true)
			return
		}

		let doc = TMDocument(path: url.path)
		Task { @MainActor in
			do {
				try await doc.load()
				MarkTracker.shared.loadIntoDocument(doc)
				self.applySettings(to: doc)
				self.textDocument = doc
				// Replace disposable document, or append as new tab.
				if let disposable = self.disposableDocumentIndex {
					self.documents[disposable] = doc
					self.selectedTabIndex = disposable
				} else {
					self.documents.append(doc)
					self.selectedTabIndex = self.documents.count - 1
				}
				self.wireDocumentEditor()
				window?.title = doc.displayName
				statusBarView.setEncoding(doc.encoding.charset)
				statusBarView.setLineEnding(doc.encoding.lineEnding.displayName)
				statusBarView.setTabSettings(useSoftTabs: doc.softTabs, tabSize: doc.tabSize)
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
		MarkTracker.shared.saveFromDocument(textDocument)
		textDocument.setContent(documentEditor?.editor.text ?? "")
		Task { @MainActor in
			do {
				try await textDocument.save()
				updateWindowTitle()
				autoRefreshScheduler?.documentDidSave()
				DocumentBackupManager.shared.removeBackup(for: textDocument)
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
		MarkTracker.shared.saveFromDocument(textDocument)
		textDocument.setContent(documentEditor?.editor.text ?? "")
		textDocument.setPath(url.path)
		Task { @MainActor in
			do {
				try await textDocument.save()
				window?.title = textDocument.displayName
				updateWindowTitle()
				autoRefreshScheduler?.documentDidSave()
				DocumentBackupManager.shared.removeBackup(for: textDocument)
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
	@objc public func toggleFileBrowser(_: Any?) {
		isFileBrowserVisible.toggle()
		projectLayoutView.fileBrowserView = isFileBrowserVisible ? fileBrowserController.view : nil
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

	// MARK: - Scroll Line Overrides

	/// Scroll the viewport up by one line height.
	@objc override public func scrollLineUp(_: Any?) {
		let clipView = scrollView.contentView
		var origin = clipView.bounds.origin
		origin.y -= editorView.layoutManager.defaultLineHeight
		clipView.setBoundsOrigin(origin)
		scrollView.reflectScrolledClipView(clipView)
	}

	/// Scroll the viewport down by one line height.
	@objc override public func scrollLineDown(_: Any?) {
		let clipView = scrollView.contentView
		var origin = clipView.bounds.origin
		origin.y += editorView.layoutManager.defaultLineHeight
		clipView.setBoundsOrigin(origin)
		scrollView.reflectScrolledClipView(clipView)
	}

	// MARK: - Menu Validation

	@objc public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		let action = menuItem.action

		// Toggle items with checkmarks
		switch action {
		case NSSelectorFromString("toggleFileBrowser:"):
			menuItem.state = isFileBrowserVisible ? .on : .off
			return true
		case NSSelectorFromString("toggleLineNumbers:"):
			menuItem.state = isLineNumbersVisible ? .on : .off
			return true
		case NSSelectorFromString("toggleSoftWrap:"):
			menuItem.state = editorView.layoutManager.softWrap ? .on : .off
			return true
		case NSSelectorFromString("toggleShowInvisibles:"):
			menuItem.state = editorView.showInvisibles ? .on : .off
			return true
		case NSSelectorFromString("toggleScrollPastEnd:"):
			menuItem.title = editorView.layoutManager.scrollPastEnd
				? String(localized: "Disallow Scroll Past End", comment: "View menu item")
				: String(localized: "Allow Scroll Past End", comment: "View menu item")
			return true
		case NSSelectorFromString("toggleShowWrapColumn:"):
			menuItem.state = editorView.layoutManager.drawWrapColumn ? .on : .off
			return true
		case NSSelectorFromString("toggleShowIndentGuides:"):
			menuItem.state = editorView.layoutManager.drawIndentGuides ? .on : .off
			return true
		case NSSelectorFromString("takeWrapColumnFrom:"):
			menuItem.state = menuItem.tag == editorView.layoutManager.wrapColumn ? .on : .off
			return true
		case NSSelectorFromString("takeTabSizeFrom:"):
			menuItem.state = menuItem.tag == editorView.layoutManager.tabSize ? .on : .off
			return true
		case NSSelectorFromString("toggleFindOption:"):
			let option = FindOptions(rawValue: UInt32(menuItem.tag))
			menuItem.state = documentEditor?.editor.findOptions.contains(option) == true ? .on : .off
			return true
		case NSSelectorFromString("toggleContinuousSpellChecking:"):
			menuItem.state = isSpellCheckingEnabled ? .on : .off
			return true
		case NSSelectorFromString("toggleSticky:"):
			menuItem.state = selectedDocument?.isSticky == true ? .on : .off
			return true
		case NSSelectorFromString("toggleHTMLOutput:"):
			#if canImport(WebKit)
			menuItem.title = htmlOutputController?.window?.isVisible == true
				? String(localized: "Hide HTML Output", comment: "View menu item")
				: String(localized: "Show HTML Output", comment: "View menu item")
			#endif
			return true
		case NSSelectorFromString("viewHTMLSource:"):
			return htmlOutputController?.window?.isVisible == true
		case NSSelectorFromString("toggleMacroRecording:"):
			menuItem.title = documentEditor?.macroRecorder.isRecording == true
				? "Stop Recording" : "Start Recording"
			return true
		case NSSelectorFromString("replayMacro:"):
			return documentEditor?.macroRecorder.lastMacro != nil
		case NSSelectorFromString("saveScratchMacro:"):
			return documentEditor?.macroRecorder.lastMacro != nil
		case NSSelectorFromString("undo:"):
			if let name = documentEditor?.editor.undoActionName {
				menuItem.title = String(localized: "Undo \\(name)", comment: "Edit menu item with action name")
			} else {
				menuItem.title = String(localized: "Undo", comment: "Edit menu item")
			}
			return documentEditor?.editor.canUndo ?? false
		case NSSelectorFromString("redo:"):
			if let name = documentEditor?.editor.redoActionName {
				menuItem.title = String(localized: "Redo \\(name)", comment: "Edit menu item with action name")
			} else {
				menuItem.title = String(localized: "Redo", comment: "Edit menu item")
			}
			return documentEditor?.editor.canRedo ?? false
		default:
			break
		}

		// Items that require a document
		switch action {
		case NSSelectorFromString("goToRelatedFile:"),
		     NSSelectorFromString("revealFileInProject:"):
			return selectedDocument?.path != nil
		case NSSelectorFromString("revertDocumentToSaved:"):
			return selectedDocument?.path != nil && selectedDocument?.isModified == true
		case NSSelectorFromString("goToProjectFolder:"):
			return projectPath != nil
		case NSSelectorFromString("goToNextBookmark:"),
		     NSSelectorFromString("goToPreviousBookmark:"):
			return !gutterView.bookmarkedLines.isEmpty
		case NSSelectorFromString("jumpToNextMark:"),
		     NSSelectorFromString("jumpToPreviousMark:"):
			if let path = selectedDocument?.path {
				return MarkTracker.shared.hasMarks(forPath: path)
			}
			return false
		case NSSelectorFromString("moveDocumentToNewWindow:"):
			return documents.count > 1
		case NSSelectorFromString("mergeAllWindows:"):
			return Self.sortedControllers.count > 1
		case NSSelectorFromString("selectNextTab:"),
		     NSSelectorFromString("selectPreviousTab:"):
			return documents.count > 1
		case NSSelectorFromString("performCloseOtherTabs:"):
			return documents.count > 1
		case NSSelectorFromString("performCloseTabsToTheRight:"):
			return selectedTabIndex < documents.count - 1
		case NSSelectorFromString("performCloseTabsToTheLeft:"):
			return selectedTabIndex > 0
		default:
			break
		}

		return true
	}

	// MARK: - TMSettings Integration

	/// Apply `.tm_properties` settings to a document and editor after loading.
	func applySettings(to doc: TMDocument) {
		guard let filePath = doc.path else { return }
		let scope = documentEditor?.syntaxHighlighter.activeScope
		let settings = SettingsResolver.settingsForPath(filePath, scope: scope)

		// Tab size
		if let tabSizeStr = settings["tabSize"], let tabSize = Int(tabSizeStr), tabSize > 0 {
			doc.tabSize = tabSize
			editorView.layoutManager.tabSize = tabSize
		}

		// Soft tabs
		if let softTabsStr = settings["softTabs"] {
			doc.softTabs = softTabsStr == "true" || softTabsStr == "1"
		}

		// Soft wrap
		if let wrapStr = settings["softWrap"] {
			editorView.layoutManager.softWrap = wrapStr == "true" || wrapStr == "1"
		}

		// Show invisibles
		if let invisStr = settings["showInvisibles"] {
			editorView.showInvisibles = invisStr == "true" || invisStr == "1"
		}

		// Font (name and/or size)
		let fontName = settings["fontName"]
		let fontSize = settings["fontSize"].flatMap { Double($0) }.map { CGFloat($0) }
		if let name = fontName, let size = fontSize {
			editorView.layoutManager.setFont(name: name, size: size)
			gutterView.font = NSFont(name: name, size: size)
				?? .monospacedSystemFont(ofSize: size, weight: .regular)
		} else if let name = fontName {
			let size = editorView.layoutManager.font.pointSize
			editorView.layoutManager.setFont(name: name, size: size)
			gutterView.font = NSFont(name: name, size: size)
				?? .monospacedSystemFont(ofSize: size, weight: .regular)
		} else if let size = fontSize {
			editorView.layoutManager.setFont(
				.monospacedSystemFont(ofSize: size, weight: .regular),
			)
			gutterView.font = .monospacedSystemFont(ofSize: size, weight: .regular)
		}

		// Wrap column
		if let wrapColStr = settings["wrapColumn"], let wrapCol = Int(wrapColStr), wrapCol >= 0 {
			editorView.layoutManager.wrapColumn = wrapCol
		}

		// Encoding
		if let enc = settings["encoding"] {
			doc.encoding = DocumentEncoding(charset: enc, lineEnding: doc.encoding.lineEnding)
			statusBarView.setEncoding(enc)
		}
		statusBarView.setLineEnding(doc.encoding.lineEnding.displayName)

		// Spell checking
		if let spellStr = settings["spellChecking"] {
			isSpellCheckingEnabled = spellStr == "true" || spellStr == "1"
			documentEditor?.isContinuousSpellCheckingEnabled = isSpellCheckingEnabled
		}
	}

	// MARK: - Private Setup

	private func setupLayout() {
		guard let contentView = window?.contentView else { return }
		contentView.wantsLayer = true

		// Tab bar at the top
		tabBarView.translatesAutoresizingMaskIntoConstraints = false
		tabBarView.delegate = self
		contentView.addSubview(tabBarView)

		// Editor area: gutter + text view
		editorContainer.wantsLayer = true
		editorContainer.translatesAutoresizingMaskIntoConstraints = false

		setupEditorView()
		setupEditorContainer()

		// Project layout: file browser | editor area (| html output)
		projectLayoutView.translatesAutoresizingMaskIntoConstraints = false
		projectLayoutView.documentView = editorContainer

		// Wire file browser into layout
		_ = fileBrowserController.view // force loadView
		fileBrowserController.delegate = self
		fileBrowserController.scmStatusProvider = { [weak self] url in
			guard self != nil else { return .none }
			return SCMManager.shared.status(for: url.path).toFileBrowserStatus
		}
		projectLayoutView.fileBrowserView = fileBrowserController.view
		if let path = projectPath {
			fileBrowserController.goToURL(URL(fileURLWithPath: path))
		}

		contentView.addSubview(projectLayoutView)

		// Live search bar (initially hidden)
		liveSearchBar.translatesAutoresizingMaskIntoConstraints = false
		liveSearchBar.delegate = self
		contentView.addSubview(liveSearchBar)

		// Status bar at the bottom
		statusBarView.translatesAutoresizingMaskIntoConstraints = false
		statusBarView.delegate = self
		contentView.addSubview(statusBarView)

		let searchBarHeight = liveSearchBar.heightAnchor.constraint(equalToConstant: 0)
		searchBarHeightConstraint = searchBarHeight

		NSLayoutConstraint.activate([
			// Tab bar
			tabBarView.topAnchor.constraint(equalTo: contentView.topAnchor),
			tabBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			tabBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			tabBarView.heightAnchor.constraint(equalToConstant: tabBarView.tabBarHeight),

			// Project layout
			projectLayoutView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
			projectLayoutView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			projectLayoutView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			projectLayoutView.bottomAnchor.constraint(equalTo: liveSearchBar.topAnchor),

			// Live search bar
			liveSearchBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			liveSearchBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			liveSearchBar.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),
			searchBarHeight,

			// Status bar
			statusBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			statusBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			statusBarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
		])
	}

	private func setupEditorView() {
		editorView.layoutManager.setFont(.monospacedSystemFont(ofSize: 13, weight: .regular))
		editorView.layoutManager.scrollPastEnd = UserDefaults.standard.bool(forKey: "scrollPastEnd")
		editorView.layoutManager.drawWrapColumn = UserDefaults.standard.bool(forKey: "showWrapColumn")
		editorView.layoutManager.drawIndentGuides = UserDefaults.standard.bool(forKey: "showIndentGuides")
		editorView.translatesAutoresizingMaskIntoConstraints = false

		scrollView.documentView = editorView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
	}

	private func setupEditorContainer() {
		gutterView.translatesAutoresizingMaskIntoConstraints = false
		gutterView.delegate = self
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		editorContainer.addSubview(gutterView)
		editorContainer.addSubview(scrollView)

		let gwConstraint = gutterView.widthAnchor.constraint(equalToConstant: gutterView.gutterWidth)
		gutterWidthConstraint = gwConstraint

		NSLayoutConstraint.activate([
			gutterView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
			gutterView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
			gutterView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
			gwConstraint,

			scrollView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
		])
	}

	func updateWindowTitle() {
		let title = textDocument.displayName
		window?.title = textDocument.isModified ? "● \(title)" : title
		window?.isDocumentEdited = textDocument.isModified
		window?.representedURL = textDocument.path.map { URL(fileURLWithPath: $0) }
	}

	/// Update the gutter's foldable/folded line sets from the fold manager.
	func updateGutterFoldState() {
		guard let de = documentEditor else { return }
		gutterView.foldableLines = de.foldableLineNumbers()
		gutterView.foldedLines = de.foldedLineNumbers()
	}

	/// Sync the tab bar with the current documents array.
	func updateTabBar() {
		let tabs = documents.map { doc in
			TabBarView.Tab(
				identifier: doc.id.uuidString,
				title: doc.displayName,
				isModified: doc.isModified,
			)
		}
		tabBarView.setTabs(tabs, selectedIndex: selectedTabIndex)
	}

	/// Wires or re-wires the document editor for the current document.
	func wireDocumentEditor() {
		let doc = selectedDocument ?? textDocument
		textDocument = doc

		// Load marks from the global tracker when activating a document.
		MarkTracker.shared.loadIntoDocument(doc)

		// Ensure the document has content (treat nil as empty for untitled).
		if doc.content == nil {
			doc.setContent("", preserveRevision: true)
		}

		documentEditor = TMDocumentEditor(
			document: doc,
			editorView: editorView,
			clipboards: clipboards,
		)
		documentEditor?.bundleIndex = bundleIndex

		if let dispatcher = commandDispatcher {
			let scheduler = AutoRefreshScheduler(dispatcher: dispatcher)
			autoRefreshScheduler = scheduler

			documentEditor?.onExecuteBundleCommand = { [weak self, weak dispatcher] command in
				guard let self, let dispatcher else { return }
				dispatcher.delegate = self
				await dispatcher.execute(command: command)
				autoRefreshScheduler?.register(command: command)
			}
		}

		documentEditor?.onContentChanged = { [weak self] in
			guard let self else { return }
			let isModified = textDocument.isModified
			if lastKnownModifiedState != isModified {
				lastKnownModifiedState = isModified
				updateWindowTitle()
				updateTabBar()
			}
			autoRefreshScheduler?.documentDidChange()
		}

		// Wire the dialog shim so bundle commands can show menus, tooltips,
		// alerts, and file panels through DialogShim.shared.
		DialogShim.shared.delegate = self
		DialogShim.shared.registerBuiltInHandlers()

		// Configure syntax highlighting if a grammar registry is available.
		if let registry = grammarRegistry, let engine = themeEngine {
			documentEditor?.configureGrammar(
				registry: registry,
				themeEngine: engine,
			)
		}

		// Update status bar grammar display.
		if let scope = documentEditor?.syntaxHighlighter.activeScope {
			let name = bundleIndex?
				.query(BundleQuery(field: .grammarScope, value: scope, kinds: .grammar))
				.first?.name ?? scope
			statusBarView.setGrammar(name)
		} else {
			statusBarView.setGrammar("Plain Text")
		}

		lastKnownModifiedState = doc.isModified
		updateWindowTitle()
		statusBarView.setEncoding(doc.encoding.charset)
		statusBarView.setLineEnding(doc.encoding.lineEnding.displayName)
		statusBarView.setTabSettings(useSoftTabs: doc.softTabs, tabSize: doc.tabSize)
		watchDocumentFile(doc)
		updateGutterFoldState()
	}

	/// Returns the index of a "disposable" document (untitled, empty, unmodified)
	/// at the selected tab, or `nil` if none.
	var disposableDocumentIndex: Int? {
		guard selectedTabIndex < documents.count else { return nil }
		let doc = documents[selectedTabIndex]
		if doc.path == nil, doc.isModified == false,
		   (doc.content ?? "").isEmpty
		{
			return selectedTabIndex
		}
		return nil
	}

	/// Whether this window looks like a project window (has a project path and
	/// either a visible file browser or multiple tabs).
	public var treatAsProjectWindow: Bool {
		projectPath != nil && (isFileBrowserVisible || documents.count > 1)
	}

	/// The suggested save path for untitled documents.
	public var untitledSavePath: String? {
		projectPath ?? selectedDocument?.path.map { ($0 as NSString).deletingLastPathComponent }
	}

	/// Sorted list of all window controllers by window ordering.
	public static var sortedControllers: [DocumentWindowController] {
		allControllers.values.sorted { a, b in
			guard let wa = a.window, let wb = b.window else { return false }
			return wa.orderedIndex < wb.orderedIndex
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

		updateIncrementalHighlights()
	}

	public func liveSearchBarDidAccept(_: LiveSearchBarView) {
		// Accept the current match position and dismiss.
		editorView.highlightRanges = []
		hideLiveSearch()
	}

	public func liveSearchBarDidCancel(_: LiveSearchBarView) {
		// Restore original position (anchor) and dismiss.
		if let editor = documentEditor?.editor {
			let anchor = incrementalSearch.anchorOffset
			let pos = editor.buffer.convert(offset: min(anchor, editor.buffer.size))
			editor.selections = SelectionState(caret: pos)
		}
		editorView.highlightRanges = []
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

	/// Pushes incremental search highlight ranges to the editor view.
	private func updateIncrementalHighlights() {
		guard let editor = documentEditor?.editor else {
			editorView.highlightRanges = []
			return
		}
		let buf = editor.buffer
		editorView.highlightRanges = incrementalSearch.highlightedRanges.map { range in
			let start = buf.convert(offset: min(range.lowerBound, buf.size))
			let end = buf.convert(offset: min(range.upperBound, buf.size))
			return (start: (line: start.line, index: start.column), end: (line: end.line, index: end.column))
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

// MARK: - NSWindowDelegate

extension DocumentWindowController: NSWindowDelegate {
	public func windowShouldClose(_: NSWindow) -> Bool {
		handleWindowShouldClose()
	}

	public func windowWillClose(_: Notification) {
		// Save session before the window disappears.
		Self.scheduleSessionBackup()

		// Save marks for all open documents.
		for doc in documents {
			MarkTracker.shared.saveFromDocument(doc)
		}

		// Fire auto-refresh close triggers before tearing down.
		autoRefreshScheduler?.documentDidClose()
		autoRefreshScheduler?.unregisterAll()

		// Detach the dialog shim delegate if we own it.
		if DialogShim.shared.delegate === self {
			DialogShim.shared.delegate = nil
		}

		// Stop watching files.
		fileWatcher?.unwatchAll()
		watchTokens.removeAll()

		// Remove from the global controller registry.
		if let id = identifier {
			Self.allControllers.removeValue(forKey: id)
		}
	}

	public func windowDidBecomeKey(_: Notification) {
		// Update find panel's document identifier to this window's active doc.
		FindPanelController.shared.documentIdentifier = selectedDocument?.id

		// Refresh status bar in case state changed while another window was key.
		if let doc = selectedDocument {
			statusBarView.setTabSettings(useSoftTabs: doc.softTabs, tabSize: doc.tabSize)
		}

		// Register as delegate for dynamic submenus.
		installDynamicMenuDelegates()
	}

	/// Installs this controller as the NSMenuDelegate for the
	/// "Jump to Bookmark" and "Show Tab" dynamic submenus.
	private func installDynamicMenuDelegates() {
		guard let mainMenu = NSApp.mainMenu else { return }
		// Navigate > Jump to Bookmark
		if let navigateMenu = mainMenu.item(withTitle: String(localized: "Navigate", comment: "Menu title"))?.submenu,
		   let bookmarkItem = navigateMenu.item(withTitle: String(
		   	localized: "Jump to Bookmark",
		   	comment: "Navigate menu item",
		   ))
		{
			bookmarkItem.submenu?.delegate = self
		}
		// Window > Show Tab
		if let windowMenu = NSApp.windowsMenu,
		   let showTabItem = windowMenu.item(withTitle: String(localized: "Show Tab", comment: "Window menu item"))
		{
			showTabItem.submenu?.delegate = self
		}
	}
}

// MARK: - StatusBarViewDelegate

extension DocumentWindowController: StatusBarViewDelegate {
	public func statusBarViewDidToggleMacroRecording(_: StatusBarView) {
		toggleMacroRecording(nil)
	}

	public func statusBarViewWillShowSymbolMenu(_: StatusBarView, popup: NSPopUpButton) {
		populateSymbolMenu(popup)
	}

	public func statusBarView(_: StatusBarView, didSelectEncoding encoding: String) {
		textDocument.encoding = DocumentEncoding(charset: encoding, lineEnding: textDocument.encoding.lineEnding)
		textDocument.markModified()
		updateWindowTitle()
	}

	public func statusBarView(_: StatusBarView, didSelectLineEnding lineEnding: String) {
		let mapping: [String: LineEnding] = ["LF": .lf, "CR": .cr, "CR/LF": .crlf]
		guard let ending = mapping[lineEnding] else { return }
		textDocument.encoding.lineEnding = ending
		textDocument.markModified()
		updateWindowTitle()
	}

	public func statusBarViewWillShowGrammarMenu(_: StatusBarView, popup: NSPopUpButton) {
		popup.removeAllItems()
		guard let bundleIndex else { return }

		let grammars = bundleIndex.query(BundleQuery(kinds: .grammar))
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		let activeScope = documentEditor?.syntaxHighlighter.activeScope

		// "Plain Text" option at the top.
		let plainItem = NSMenuItem(title: "Plain Text", action: nil, keyEquivalent: "")
		plainItem.representedObject = "" as String
		popup.menu?.addItem(plainItem)
		popup.menu?.addItem(.separator())

		for grammar in grammars {
			let item = NSMenuItem(title: grammar.name, action: nil, keyEquivalent: "")
			item.representedObject = grammar.scopeSelector
			popup.menu?.addItem(item)
			if grammar.scopeSelector == activeScope {
				popup.select(item)
			}
		}

		// If no grammar is active, select "Plain Text".
		if activeScope == nil || activeScope?.isEmpty == true {
			popup.selectItem(at: 0)
		}
	}

	public func statusBarView(_: StatusBarView, didSelectGrammar scope: String) {
		guard let registry = grammarRegistry, let engine = themeEngine else { return }
		textDocument.fileType = scope.isEmpty ? nil : scope
		if scope.isEmpty {
			// "Plain Text" selected — clear syntax highlighting.
			documentEditor?.syntaxHighlighter.setGrammar(scope: nil)
			statusBarView.setGrammar("Plain Text")
		} else {
			documentEditor?.configureGrammar(registry: registry, themeEngine: engine, scope: scope)
			// Find the display name from the bundle index.
			let name = bundleIndex?
				.query(BundleQuery(field: .grammarScope, value: scope, kinds: .grammar))
				.first?.name ?? scope
			statusBarView.setGrammar(name)
		}
	}

	public func statusBarView(_: StatusBarView, didSelectTabSize size: Int) {
		guard size > 0 else { return }
		documentEditor?.editor.tabSize = size
		editorView.layoutManager.tabSize = size
		if let doc = selectedDocument {
			doc.tabSize = size
		}
		statusBarView.setTabSettings(useSoftTabs: textDocument.softTabs, tabSize: size)
		editorView.needsDisplay = true
	}

	public func statusBarView(_: StatusBarView, didSelectUseSoftTabs useSoftTabs: Bool) {
		if let doc = selectedDocument {
			doc.softTabs = useSoftTabs
		}
		documentEditor?.editor.indentUsingSpaces = useSoftTabs
		statusBarView.setTabSettings(useSoftTabs: useSoftTabs, tabSize: textDocument.tabSize)
	}

	public func statusBarViewWillShowBundleItemsMenu(_: StatusBarView, popup: NSPopUpButton) {
		popup.removeAllItems()
		guard let bundleIndex else { return }

		let activeScope = documentEditor?.syntaxHighlighter.activeScope

		let bundles = bundleIndex.allBundles
			.filter(\.isEnabled)
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		var selectedItem: NSMenuItem?
		for bundle in bundles {
			let items = bundleIndex.items(inBundle: bundle.uuid)
			let hasExecutable = items.contains { $0.kind.intersection(.executable) != [] }
			guard hasExecutable || !bundle.menuItems.isEmpty else { continue }

			let menuItem = NSMenuItem(title: bundle.name, action: nil, keyEquivalent: "")
			let submenu = NSMenu(title: bundle.uuid)
			submenu.identifier = NSUserInterfaceItemIdentifier(bundle.uuid)
			let builder = BundleMenuBuilder(bundleIndex: bundleIndex)
			submenu.delegate = builder
			// Keep builder alive for the lifetime of the submenu.
			objc_setAssociatedObject(submenu, "builder", builder, .OBJC_ASSOCIATION_RETAIN)
			menuItem.submenu = submenu
			popup.menu?.addItem(menuItem)

			// Check-mark the bundle containing the active grammar.
			if let activeScope, !activeScope.isEmpty {
				let hasActiveGrammar = items.contains {
					$0.kind == .grammar && $0.scopeSelector == activeScope
				}
				if hasActiveGrammar {
					menuItem.state = .on
					selectedItem = menuItem
				}
			}
		}

		if bundles.isEmpty {
			popup.menu?.addItem(NSMenuItem(title: "No Bundles Loaded", action: nil, keyEquivalent: ""))
		}

		if let selectedItem {
			popup.select(selectedItem)
		}
	}
}

// MARK: - GutterViewDelegate

extension DocumentWindowController: GutterViewDelegate {
	public func gutterView(_: GutterView, didToggleBookmarkAtLine line: Int) {
		guard let path = textDocument.path else { return }
		MarkTracker.shared.toggleBookmark(atLine: line, forPath: path)
	}

	public func gutterView(_: GutterView, didToggleFoldAtLine line: Int) {
		// line is 1-based from GutterView; FoldManager uses 0-based.
		let zeroBasedLine = line - 1
		documentEditor?.toggleFold(atLine: zeroBasedLine)
		updateGutterFoldState()
	}
}

// MARK: - File Watching

extension DocumentWindowController {
	/// Start watching the given document's backing file for external changes.
	func watchDocumentFile(_ doc: TMDocument) {
		guard let filePath = doc.path else { return }

		// Don't re-watch the same path.
		if watchTokens[filePath] != nil { return }

		if fileWatcher == nil {
			fileWatcher = FileWatcher()
		}

		let token = fileWatcher!.watch(filePath, events: [.written, .renamed, .deleted]) {
			[weak self] path, events in
			Task { @MainActor [weak self] in
				self?.handleFileWatchEvent(path: path, events: events)
			}
		}
		watchTokens[filePath] = token
	}

	/// Stop watching a specific file path.
	func unwatchDocumentFile(_ path: String) {
		guard let token = watchTokens.removeValue(forKey: path) else { return }
		fileWatcher?.unwatch(token)
	}

	/// Handle a file watch event on the main thread.
	private func handleFileWatchEvent(path: String, events: FileWatchEvent) {
		guard let doc = documents.first(where: { $0.path == path }) else {
			unwatchDocumentFile(path)
			return
		}

		if events.contains(.deleted) {
			// Mark the document as modified (file was removed from disk).
			updateWindowTitle()
			updateTabBar()
			return
		}

		if events.contains(.written) || events.contains(.renamed) {
			guard doc.hasExternalChanges() else { return }
			promptForExternalChange(doc)
		}
	}

	/// Show an alert asking the user whether to reload a file changed on disk.
	private func promptForExternalChange(_ doc: TMDocument) {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = String(
			localized: "The document \"\(doc.displayName)\" has been changed by another application.",
			comment: "External change alert",
		)
		if doc.isModified {
			alert.informativeText = String(
				localized: "Do you want to keep your version or reload the file from disk? Your unsaved changes will be merged if possible.",
				comment: "External change alert detail (modified)",
			)
			alert.addButton(withTitle: String(localized: "Reload and Merge", comment: "Button"))
			alert.addButton(withTitle: String(localized: "Keep Mine", comment: "Button"))
		} else {
			alert.informativeText = String(
				localized: "Do you want to reload the file from disk?",
				comment: "External change alert detail (clean)",
			)
			alert.addButton(withTitle: String(localized: "Reload", comment: "Button"))
			alert.addButton(withTitle: String(localized: "Keep Current", comment: "Button"))
		}

		guard let window else { return }
		alert.beginSheetModal(for: window) { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			Task { @MainActor in
				do {
					try await doc.reload(mergeChanges: doc.isModified)
					self?.documentEditor?.reloadFromDocument()
					self?.updateWindowTitle()
					self?.updateTabBar()
				} catch {
					let errAlert = NSAlert(error: error)
					errAlert.runModal()
				}
			}
		}
	}

	/// Check all open documents for external changes (e.g., on app re-activation).
	public func checkForExternalChanges() {
		for doc in documents {
			guard doc.path != nil, doc.hasExternalChanges() else { continue }
			promptForExternalChange(doc)
			return // Process one at a time (alert is sheet-modal).
		}
	}
}

// MARK: - SCM Status Mapping

extension SCMStatus {
	/// Converts TMSCM's ``SCMStatus`` to the file browser's ``FileItemImage/SCMStatus``.
	var toFileBrowserStatus: FileItemImage.SCMStatus {
		switch self {
		case .modified: .modified
		case .added: .added
		case .deleted: .deleted
		case .conflicted: .conflicted
		case .unversioned: .unversioned
		case .mixed: .mixed
		case .unknown: .unknown
		case .none, .ignored: .none
		}
	}
}

// MARK: - Dynamic Menu Delegate (Bookmarks + Show Tab)

extension DocumentWindowController: NSMenuDelegate {
	public func menuNeedsUpdate(_ menu: NSMenu) {
		let title = menu.title
		if title == String(localized: "Jump to Bookmark", comment: "Navigate menu submenu") {
			updateBookmarksMenu(menu)
		} else if title == String(localized: "Show Tab", comment: "Window menu submenu") {
			updateShowTabMenu(menu)
		}
	}

	private func updateBookmarksMenu(_ menu: NSMenu) {
		menu.removeAllItems()
		let sorted = gutterView.bookmarkedLines.sorted()
		guard !sorted.isEmpty else {
			let noItem = menu.addItem(
				withTitle: String(localized: "No Bookmarks", comment: "Bookmark submenu placeholder"),
				action: nil,
				keyEquivalent: "",
			)
			noItem.isEnabled = false
			return
		}
		for line in sorted {
			let item = menu.addItem(
				withTitle: String(localized: "Line \(line)", comment: "Bookmark submenu item"),
				action: #selector(goToBookmarkedLine(_:)),
				keyEquivalent: "",
			)
			item.target = self
			item.tag = line
		}
	}

	@objc private func goToBookmarkedLine(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem else { return }
		goToLine(menuItem.tag)
	}

	private func updateShowTabMenu(_ menu: NSMenu) {
		menu.removeAllItems()
		for (index, doc) in documents.enumerated() {
			let title = doc.displayName
			let item = menu.addItem(
				withTitle: title,
				action: #selector(selectTabFromMenu(_:)),
				keyEquivalent: "",
			)
			item.target = self
			item.tag = index
			if index == selectedTabIndex {
				item.state = .on
			}
			if doc.isModified {
				item.attributedTitle = NSAttributedString(
					string: title,
					attributes: [.obliqueness: 0.15],
				)
			}
		}
	}

	@objc private func selectTabFromMenu(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem else { return }
		let index = menuItem.tag
		guard index >= 0, index < documents.count else { return }
		selectedTabIndex = index
		openAndSelectDocument(documents[index], activate: true)
	}
}
