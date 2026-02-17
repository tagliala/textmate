import AppKit
import TMAppKit
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMGrammar
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

		setupEditorView()
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
