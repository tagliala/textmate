import AppKit
import TMAppKit
import TMTheme

/// The main document window controller, managing the layout that matches
/// TextMate's window structure:
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │ Tab Bar                                 │
/// ├────────────┬────────────────────────────┤
/// │ File       │ Gutter │ Editor (NSTextView) │
/// │ Browser    │        │                   │
/// │ (sidebar)  │        │                   │
/// │            │        │                   │
/// ├────────────┴────────┴───────────────────┤
/// │ Status Bar                              │
/// └─────────────────────────────────────────┘
/// ```
@MainActor
public class DocumentWindowController: NSWindowController {
	public let tabBarView = TabBarView()
	public let fileBrowserView = FileBrowserView()
	public let gutterView = GutterView()
	public let statusBarView = StatusBarView()
	public let textView = NSTextView()

	/// The document model for the currently displayed file.
	public let documentModel = DocumentModel()

	private let splitView = NSSplitView()
	private let editorContainer = NSView()
	private let scrollView = NSScrollView()

	private var fileBrowserWidth: CGFloat = 200
	private var isFileBrowserVisible = true

	private var currentTheme: Theme?

	/// Creates a new document window with the standard TextMate layout.
	public init() {
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
		textView.backgroundColor = bg
		textView.textColor = fg
		textView.insertionPointColor = theme.globalSettings.caret.nsColor
		textView.selectedTextAttributes = [
			.backgroundColor: theme.globalSettings.selection.nsColor,
		]
		scrollView.backgroundColor = bg
	}

	/// Set the project root for the file browser.
	public func setProjectRoot(_ url: URL) {
		fileBrowserView.rootURL = url
		window?.title = url.lastPathComponent
	}

	/// Open a file, detecting its encoding automatically.
	public func openFile(at url: URL) {
		do {
			let text = try documentModel.readFile(at: url)
			textView.string = text
			window?.title = documentModel.displayTitle
			statusBarView.setEncoding(documentModel.encodingDisplayName)
			documentModel.isModified = false
			updateWindowTitle()
		} catch {
			let alert = NSAlert(error: error)
			alert.runModal()
		}
	}

	/// Save the current document. Returns `true` if the save succeeded.
	@discardableResult
	public func saveDocument() -> Bool {
		guard documentModel.fileURL != nil else {
			return saveDocumentAs()
		}
		do {
			try documentModel.writeFile(text: textView.string)
			updateWindowTitle()
			return true
		} catch {
			let alert = NSAlert(error: error)
			alert.runModal()
			return false
		}
	}

	/// Present a Save panel and save the document. Returns `true` on success.
	@discardableResult
	public func saveDocumentAs() -> Bool {
		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.nameFieldStringValue = documentModel.displayTitle

		guard panel.runModal() == .OK, let url = panel.url else {
			return false
		}

		documentModel.fileURL = url
		do {
			try documentModel.writeFile(text: textView.string)
			window?.title = documentModel.displayTitle
			updateWindowTitle()
			return true
		} catch {
			let alert = NSAlert(error: error)
			alert.runModal()
			return false
		}
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

		setupTextView()
		setupEditorContainer()

		splitView.addArrangedSubview(fileBrowserView)
		splitView.addArrangedSubview(editorContainer)
		contentView.addSubview(splitView)

		// Status bar at the bottom
		statusBarView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(statusBarView)

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
			splitView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),

			// File browser min width
			fileBrowserView.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

			// Status bar
			statusBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			statusBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			statusBarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			statusBarView.heightAnchor.constraint(equalToConstant: statusBarView.statusBarHeight),
		])

		// Set initial sidebar width
		splitView.setPosition(fileBrowserWidth, ofDividerAt: 0)
	}

	private func setupTextView() {
		textView.isEditable = true
		textView.isSelectable = true
		textView.allowsUndo = true
		textView.isRichText = false
		textView.usesFontPanel = true
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.isAutomaticTextReplacementEnabled = false
		textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
		textView.textContainerInset = NSSize(width: 0, height: 4)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.textContainer?.widthTracksTextView = true

		scrollView.documentView = textView
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
		let title = documentModel.displayTitle
		window?.title = documentModel.isModified ? "● \(title)" : title
	}
}
