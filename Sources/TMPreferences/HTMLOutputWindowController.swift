#if canImport(AppKit)
import AppKit
import WebKit

/// Standalone window controller wrapping an HTML output view.
///
/// Port of `Frameworks/HTMLOutputWindow/src/HTMLOutputWindow.mm`.
/// Provides a resizable window that displays HTML output from bundle commands.
@MainActor
public final class HTMLOutputWindowController: NSWindowController, NSWindowDelegate {
	/// The web view displaying HTML output.
	public let webView: WKWebView

	/// Whether a command is currently running (shows document-edited dot).
	public var isRunningCommand: Bool = false {
		didSet { window?.isDocumentEdited = isRunningCommand }
	}

	/// Retained self to prevent deallocation while visible.
	private var retainedSelf: HTMLOutputWindowController?

	/// Callback invoked when the user requests stopping a running command.
	public var onStopCommand: (() -> Void)?

	/// Callback invoked when the window is about to close.
	public var onClose: (() -> Void)?

	// MARK: - Initialization

	/// Create an HTML output window.
	///
	/// - Parameter identifier: Optional UUID for frame autosave.
	public init(identifier: UUID? = nil) {
		let config = WKWebViewConfiguration()
		config.preferences.isElementFullscreenEnabled = true
		webView = WKWebView(frame: .zero, configuration: config)

		// Calculate default frame: screen visible frame inset by 1/3 width, 1/5 height
		let screen = NSScreen.main ?? NSScreen.screens[0]
		let visibleFrame = screen.visibleFrame
		let insetX = visibleFrame.width / 3
		let insetY = visibleFrame.height / 5
		let contentRect = visibleFrame.insetBy(dx: insetX, dy: insetY)

		let window = NSWindow(
			contentRect: contentRect,
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: false,
		)
		window.title = "HTML Output"
		window.isReleasedWhenClosed = false
		window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

		if let identifier {
			window.setFrameAutosaveName("HTML output for \(identifier.uuidString)")
		}

		super.init(window: window)
		window.delegate = self

		// Set up web view as content
		webView.translatesAutoresizingMaskIntoConstraints = false
		window.contentView?.addSubview(webView)
		if let contentView = window.contentView {
			NSLayoutConstraint.activate([
				webView.topAnchor.constraint(equalTo: contentView.topAnchor),
				webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
				webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
				webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			])
		}
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Show / Close

	override public func showWindow(_ sender: Any?) {
		retainedSelf = self
		super.showWindow(sender)
	}

	/// Load HTML content into the view.
	public func loadHTML(_ html: String, baseURL: URL? = nil) {
		webView.loadHTMLString(html, baseURL: baseURL)
	}

	/// Load a URL into the view.
	public func loadURL(_ url: URL) {
		webView.load(URLRequest(url: url))
	}

	/// Cancel (Escape) action — closes the window.
	@objc override public func cancelOperation(_ sender: Any?) {
		window?.performClose(sender)
	}

	// MARK: - NSWindowDelegate

	public func windowShouldClose(_: NSWindow) -> Bool {
		if isRunningCommand {
			// Ask the command to stop; defer close until it confirms
			onStopCommand?()
			return false
		}
		return true
	}

	public func windowWillClose(_: Notification) {
		onClose?()
		// Clear retained self after a short delay to prevent crashes
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
			self?.retainedSelf = nil
		}
	}
}
#endif
