#if canImport(AppKit) && canImport(WebKit)
import AppKit
import WebKit

/// Delegate protocol for browser view events.
@MainActor
public protocol HTMLOutputBrowserViewDelegate: AnyObject {
	/// The browser view needs to open a `txmt://` URL.
	func browserView(_ view: HTMLOutputBrowserView, handleTxMtURL url: URL)
	/// The browser view encountered a load error.
	func browserView(_ view: HTMLOutputBrowserView, didFailWithError error: Error, for url: URL?)
}

/// Default no-op implementations.
public extension HTMLOutputBrowserViewDelegate {
	func browserView(_: HTMLOutputBrowserView, handleTxMtURL _: URL) {}
	func browserView(_: HTMLOutputBrowserView, didFailWithError _: Error, for _: URL?) {}
}

/// WKWebView browser view with status bar and navigation.
///
/// Ports `Frameworks/HTMLOutput/src/browser/HOBrowserView.mm` and
/// `Frameworks/HTMLOutput/src/browser/HOWebViewDelegateHelper.mm`.
/// Provides a WKWebView with back/forward navigation, status bar,
/// progress tracking, swipe gestures, and error page display.
@MainActor
public final class HTMLOutputBrowserView: NSView {
	// MARK: - Public Properties

	/// The web view for displaying content.
	public let webView: WKWebView

	/// The status bar with navigation buttons and progress indicator.
	public let statusBar: HTMLOutputStatusBar

	/// Delegate for browser events.
	public weak var delegate: HTMLOutputBrowserViewDelegate?

	/// Whether a new web view is needed (after window.close() from JS).
	public private(set) var needsNewWebView: Bool = false

	/// Default URL protocol for protocol-relative URLs.
	public var defaultURLProtocol: String {
		get {
			UserDefaults.standard.string(forKey: "defaultURLProtocol") ?? "https"
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "defaultURLProtocol")
		}
	}

	// MARK: - Private State

	/// KVO observation for estimated progress.
	private var progressObservation: NSKeyValueObservation?

	/// KVO observation for page title.
	private var titleObservation: NSKeyValueObservation?

	/// KVO observation for canGoBack.
	private var canGoBackObservation: NSKeyValueObservation?

	/// KVO observation for canGoForward.
	private var canGoForwardObservation: NSKeyValueObservation?

	// MARK: - Initialization

	override public init(frame: NSRect) {
		let config = WKWebViewConfiguration()
		config.preferences.isElementFullscreenEnabled = true
		webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
		statusBar = HTMLOutputStatusBar(frame: .zero)

		super.init(frame: frame)

		statusBar.delegate = self

		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.translatesAutoresizingMaskIntoConstraints = false
		statusBar.translatesAutoresizingMaskIntoConstraints = false

		addSubview(webView)
		addSubview(statusBar)

		NSLayoutConstraint.activate([
			webView.topAnchor.constraint(equalTo: topAnchor),
			webView.leadingAnchor.constraint(equalTo: leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: trailingAnchor),
			webView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

			statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
			statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
			statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		setupObservations()
		injectHoverStatusScript()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	deinit {
		progressObservation?.invalidate()
		titleObservation?.invalidate()
		canGoBackObservation?.invalidate()
		canGoForwardObservation?.invalidate()
	}

	// MARK: - Loading

	/// Load a URL request.
	public func loadRequest(_ request: URLRequest) {
		statusBar.busy = true
		startProgressUpdates()
		webView.load(request)
	}

	/// Load HTML content from a string.
	public func loadHTMLString(_ html: String, baseURL: URL? = nil) {
		let base = baseURL ?? URL(fileURLWithPath: NSHomeDirectory())
		webView.loadHTMLString(html, baseURL: base)
	}

	/// Navigate back.
	@objc public func goBack(_: Any? = nil) {
		webView.goBack()
	}

	/// Navigate forward.
	@objc public func goForward(_: Any? = nil) {
		webView.goForward()
	}

	/// Stop loading current page.
	@objc public func stopLoading(_: Any? = nil) {
		webView.stopLoading()
	}

	/// Reload the current page.
	@objc public func reload(_: Any? = nil) {
		webView.reload()
	}

	// MARK: - Progress Tracking

	/// Start observing progress. Called internally on page load.
	public func startProgressUpdates() {
		statusBar.busy = true
		statusBar.progress = 0
	}

	/// Stop observing progress. Called internally on load finish/fail.
	public func stopProgressUpdates() {
		statusBar.busy = false
		statusBar.progress = 0
	}

	// MARK: - KVO Setup

	private func setupObservations() {
		progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
			Task { @MainActor [weak self] in
				guard let self, let value = change.newValue else { return }
				statusBar.progress = value
			}
		}

		canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
			Task { @MainActor [weak self] in
				guard let self, let value = change.newValue else { return }
				statusBar.canGoBack = value
			}
		}

		canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
			Task { @MainActor [weak self] in
				guard let self, let value = change.newValue else { return }
				statusBar.canGoForward = value
			}
		}
	}

	// MARK: - Hover Status Script

	/// Inject JavaScript to update status text when hovering over links.
	private func injectHoverStatusScript() {
		let script = WKUserScript(
			source: """
			document.addEventListener('mouseover', function(e) {
				var link = e.target.closest('a');
				if (link && link.href) {
					window.webkit.messageHandlers.hoverLink.postMessage(link.href);
				}
			});
			document.addEventListener('mouseout', function(e) {
				var link = e.target.closest('a');
				if (link) {
					window.webkit.messageHandlers.hoverLink.postMessage('');
				}
			});
			""",
			injectionTime: .atDocumentEnd,
			forMainFrameOnly: true,
		)
		webView.configuration.userContentController.addUserScript(script)
		webView.configuration.userContentController.add(
			HoverLinkHandler(statusBar: statusBar),
			name: "hoverLink",
		)
	}

	// MARK: - Error Page

	/// Show a load error page for a URL.
	public func showLoadError(_ error: Error, for url: URL?) {
		let urlString = url?.absoluteString ?? "unknown"
		let escapedURL = urlString
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
		let escapedError = error.localizedDescription
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
		let html = """
		<title>Load Error</title>
		<h1>Load Error</h1>
		<p>WebKit reported <em>\(escapedError)</em> while loading
		<tt><a href="\(escapedURL)">\(escapedURL)</a></tt>.</p>
		"""
		webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: NSTemporaryDirectory()))
	}

	// MARK: - Swipe Navigation

	override public func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
		axis == .horizontal
	}

	override public func scrollWheel(with event: NSEvent) {
		guard NSEvent.isSwipeTrackingFromScrollEventsEnabled,
		      event.phase != [],
		      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
		else { return }

		let minThreshold: CGFloat = webView.canGoForward ? -1 : 0
		let maxThreshold: CGFloat = webView.canGoBack ? 1 : 0

		event.trackSwipeEvent(
			options: [],
			dampenAmountThresholdMin: minThreshold,
			max: maxThreshold,
		) { [weak self] gestureAmount, phase, _, _ in
			guard let self, phase == .ended else { return }
			if gestureAmount > 0, webView.canGoBack {
				webView.goBack()
			} else if gestureAmount < 0, webView.canGoForward {
				webView.goForward()
			}
		}
	}
}

// MARK: - HTMLOutputStatusBarDelegate

extension HTMLOutputBrowserView: HTMLOutputStatusBarDelegate {
	public func statusBarGoBack(_: HTMLOutputStatusBar) {
		goBack()
	}

	public func statusBarGoForward(_: HTMLOutputStatusBar) {
		goForward()
	}
}

// MARK: - WKNavigationDelegate

extension HTMLOutputBrowserView: WKNavigationDelegate {
	public func webView(
		_: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void,
	) {
		guard let url = navigationAction.request.url else {
			decisionHandler(.allow)
			return
		}

		if url.scheme == "txmt" {
			delegate?.browserView(self, handleTxMtURL: url)
			decisionHandler(.cancel)
		} else if url.scheme == "tm-file" {
			// Rewrite tm-file:// to file:// scheme
			var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
			components?.scheme = "file"
			if let rewritten = components?.url {
				decisionHandler(.cancel)
				webView.load(URLRequest(url: rewritten))
			} else {
				decisionHandler(.allow)
			}
		} else if url.scheme == "http" || url.scheme == "https",
		          navigationAction.navigationType == .linkActivated
		{
			NSWorkspace.shared.open(url)
			decisionHandler(.cancel)
		} else {
			decisionHandler(.allow)
		}
	}

	public func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
		statusBar.busy = true
		startProgressUpdates()
	}

	public func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
		statusBar.canGoBack = webView.canGoBack
		statusBar.canGoForward = webView.canGoForward
		stopProgressUpdates()
	}

	public func webView(
		_: WKWebView,
		didFailProvisionalNavigation _: WKNavigation!,
		withError error: Error,
	) {
		let url = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
		showLoadError(error, for: url)
		stopProgressUpdates()
		delegate?.browserView(self, didFailWithError: error, for: url)
	}

	public func webView(
		_: WKWebView,
		didFail _: WKNavigation!,
		withError error: Error,
	) {
		let url = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
		showLoadError(error, for: url)
		stopProgressUpdates()
		delegate?.browserView(self, didFailWithError: error, for: url)
	}
}

// MARK: - WKUIDelegate

extension HTMLOutputBrowserView: WKUIDelegate {
	/// Handle JavaScript `alert()`.
	public func webView(
		_: WKWebView,
		runJavaScriptAlertPanelWithMessage message: String,
		initiatedByFrame _: WKFrameInfo,
		completionHandler: @escaping @MainActor @Sendable () -> Void,
	) {
		let alert = NSAlert()
		alert.messageText = NSLocalizedString("Script Message", comment: "JavaScript alert title")
		alert.informativeText = message
		alert.addButton(withTitle: NSLocalizedString("OK", comment: "JavaScript alert confirmation"))

		if let window {
			alert.beginSheetModal(for: window) { _ in
				completionHandler()
			}
		} else {
			alert.runModal()
			completionHandler()
		}
	}

	/// Handle JavaScript `confirm()`.
	public func webView(
		_: WKWebView,
		runJavaScriptConfirmPanelWithMessage message: String,
		initiatedByFrame _: WKFrameInfo,
		completionHandler: @escaping @MainActor @Sendable (Bool) -> Void,
	) {
		let alert = NSAlert()
		alert.messageText = NSLocalizedString("Script Message", comment: "JavaScript confirm title")
		alert.informativeText = message
		alert.addButton(withTitle: NSLocalizedString("OK", comment: "Confirm"))
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

		if let window {
			alert.beginSheetModal(for: window) { response in
				completionHandler(response == .alertFirstButtonReturn)
			}
		} else {
			let response = alert.runModal()
			completionHandler(response == .alertFirstButtonReturn)
		}
	}

	/// Handle JavaScript `window.open()` — create a new browser window.
	public func webView(
		_: WKWebView,
		createWebViewWith _: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures _: WKWindowFeatures,
	) -> WKWebView? {
		let origin = window?.cascadeTopLeft(from: .zero) ?? .zero
		let newBrowser = HTMLOutputBrowserView(frame: NSRect(origin: .zero, size: NSSize(width: 750, height: 800)))

		let newWindow = NSWindow(
			contentRect: NSRect(origin: origin, size: NSSize(width: 750, height: 800)),
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: false,
		)
		newWindow.contentView = newBrowser
		newWindow.isReleasedWhenClosed = false

		// Bind title
		titleObservation = newBrowser.webView.observe(\.title, options: [.new]) { [weak newWindow] _, change in
			Task { @MainActor in
				newWindow?.title = change.newValue.flatMap(\.self) ?? "HTML Output"
			}
		}

		if let request = navigationAction.request.url {
			newBrowser.webView.load(URLRequest(url: request))
		}

		newWindow.makeKeyAndOrderFront(nil)
		return newBrowser.webView
	}

	/// Handle JavaScript `window.close()`.
	public func webViewDidClose(_: WKWebView) {
		needsNewWebView = true
		window?.performClose(nil)
	}
}

// MARK: - Hover Link Handler

/// Script message handler for link hover status text updates.
private final class HoverLinkHandler: NSObject, WKScriptMessageHandler {
	private weak var statusBar: HTMLOutputStatusBar?

	init(statusBar: HTMLOutputStatusBar) {
		self.statusBar = statusBar
	}

	nonisolated func userContentController(
		_: WKUserContentController,
		didReceive message: WKScriptMessage,
	) {
		MainActor.assumeIsolated {
			if let href = message.body as? String {
				self.statusBar?.statusText = href.removingPercentEncoding ?? href
			}
		}
	}
}
#endif
