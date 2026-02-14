#if canImport(AppKit) && canImport(WebKit)
import AppKit
import WebKit

/// WKWebView-based HTML output panel for bundle command output.
///
/// Replaces the deprecated WebView-based `OakHTMLOutputView` from
/// `Frameworks/HTMLOutput/src/OakHTMLOutputView.mm`.
///
/// The view exposes a `TextMate` JavaScript object in the page context,
/// providing `system()`, `log()`, `open()`, `isBusy`, and `progress` methods
/// for backward compatibility with existing bundle HTML output commands.
@MainActor
public final class HTMLOutputView: NSView, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
	/// The web view that renders HTML output.
	public let webView: WKWebView

	/// Whether the command that produced this output is still running.
	public private(set) var isRunningCommand = false

	/// Whether this view can be reused for the next command.
	public var isReusable = true

	/// Whether the JavaScript API (`TextMate` object) is enabled.
	public var disableJavaScriptAPI = false

	/// Environment passed to the JavaScript bridge.
	public var environment: [String: String] = [:]

	/// Delegate for lifecycle events.
	public weak var delegate: HTMLOutputViewDelegate?

	/// Auto-scroll when content is appended (command is executing).
	private var autoScrollEnabled = false

	/// The title of the main frame (forwarded from the web view).
	public var mainFrameTitle: String {
		webView.title ?? ""
	}

	// MARK: - Initialization

	override public init(frame: NSRect) {
		let config = WKWebViewConfiguration()
		let userContentController = WKUserContentController()
		config.userContentController = userContentController

		webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
		webView.autoresizingMask = [.width, .height]

		super.init(frame: frame)

		webView.navigationDelegate = self
		webView.uiDelegate = self
		addSubview(webView)

		// Register message handlers for the JavaScript bridge
		let handler = self
		userContentController.add(handler, name: "log")
		userContentController.add(handler, name: "openFile")
		userContentController.add(handler, name: "systemCommand")

		// Inject the TextMate JavaScript bridge
		if !disableJavaScriptAPI {
			injectJavaScriptBridge(into: userContentController)
		}
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	// MARK: - Loading Content

	/// Load HTML content from a string.
	public func loadHTMLContent(_ html: String, baseURL: URL? = nil) {
		let base = baseURL ?? URL(fileURLWithPath: NSHomeDirectory())
		webView.loadHTMLString(html, baseURL: base)
	}

	/// Load content from a URL request.
	public func loadRequest(_ request: URLRequest, autoScrolls: Bool = false) {
		autoScrollEnabled = autoScrolls
		isRunningCommand = true
		webView.load(request)
	}

	/// Append HTML to the current page by evaluating JavaScript.
	public func appendHTML(_ html: String) {
		let escaped = html
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "'", with: "\\'")
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
		let js = """
		(function() {
			var container = document.getElementById('_tm_output') || document.body;
			if (container) {
				container.insertAdjacentHTML('beforeend', '\(escaped)');
				if (\(autoScrollEnabled)) { window.scrollTo(0, document.body.scrollHeight); }
			}
		})();
		"""
		webView.evaluateJavaScript(js)
	}

	/// Called when the command finishes.
	public func commandDidFinish() {
		isRunningCommand = false
		autoScrollEnabled = false
	}

	/// Stop the web view from loading.
	public func stopLoading() {
		webView.stopLoading()
		isRunningCommand = false
		autoScrollEnabled = false
	}

	// MARK: - JavaScript Bridge Injection

	/// Inject the `TextMate` JavaScript object for bundle compatibility.
	private func injectJavaScriptBridge(into controller: WKUserContentController) {
		let bridgeScript = WKUserScript(
			source: Self.jsBridgeSource,
			injectionTime: .atDocumentStart,
			forMainFrameOnly: false,
		)
		controller.addUserScript(bridgeScript)
	}

	/// JavaScript source for the TextMate bridge object.
	///
	/// Exposes: `TextMate.system()`, `TextMate.log()`, `TextMate.open()`,
	/// `TextMate.isBusy`, `TextMate.progress`.
	private static let jsBridgeSource = """
	window.TextMate = {
		_isBusy: false,
		_progress: 0.0,

		get isBusy() { return this._isBusy; },
		set isBusy(val) {
			this._isBusy = !!val;
		},

		get progress() { return this._progress; },
		set progress(val) {
			this._progress = Number(val) || 0;
		},

		log: function(msg) {
			window.webkit.messageHandlers.log.postMessage(String(msg));
		},

		open: function(path, options) {
			window.webkit.messageHandlers.openFile.postMessage({
				path: String(path),
				options: options !== undefined ? String(options) : null
			});
		},

		system: function(command, handler) {
			// For synchronous calls (handler is null), we post and return
			// a pending result object. The native side will call back.
			var id = Date.now() + '_' + Math.random();
			var result = {
				outputString: '',
				errorString: '',
				status: -1,
				onreadoutput: null,
				onreaderror: null,
				_id: id,

				cancel: function() {
					window.webkit.messageHandlers.systemCommand.postMessage({
						action: 'cancel', id: id
					});
				},
				write: function(str) {
					window.webkit.messageHandlers.systemCommand.postMessage({
						action: 'write', id: id, data: String(str)
					});
				},
				close: function() {
					window.webkit.messageHandlers.systemCommand.postMessage({
						action: 'close', id: id
					});
				}
			};

			window.webkit.messageHandlers.systemCommand.postMessage({
				action: 'start',
				id: id,
				command: String(command),
				hasHandler: !!handler
			});

			if (handler) {
				result._handler = handler;
			}
			window._tm_commands = window._tm_commands || {};
			window._tm_commands[id] = result;

			return result;
		}
	};
	"""

	// MARK: - WKScriptMessageHandler

	public nonisolated func userContentController(
		_: WKUserContentController,
		didReceive message: WKScriptMessage,
	) {
		Task { @MainActor in
			handleMessage(message)
		}
	}

	private func handleMessage(_ message: WKScriptMessage) {
		switch message.name {
		case "log":
			if let msg = message.body as? String {
				NSLog("JavaScript Log: %@", msg)
			}

		case "openFile":
			if let dict = message.body as? [String: Any],
			   let path = dict["path"] as? String
			{
				let options = dict["options"] as? String
				delegate?.htmlOutputView(self, openFile: path, options: options)
			}

		case "systemCommand":
			if let dict = message.body as? [String: Any] {
				handleSystemCommand(dict)
			}

		default:
			break
		}
	}

	// MARK: - System Command Handling

	/// Active system() subprocesses keyed by their JS-assigned ID.
	private var activeCommands: [String: Process] = [:]

	private func handleSystemCommand(_ dict: [String: Any]) {
		guard let action = dict["action"] as? String,
		      let id = dict["id"] as? String
		else { return }

		switch action {
		case "start":
			guard let command = dict["command"] as? String else { return }
			launchSystemCommand(id: id, command: command)

		case "cancel":
			activeCommands[id]?.terminate()
			activeCommands.removeValue(forKey: id)

		case "write":
			if let data = dict["data"] as? String,
			   let proc = activeCommands[id],
			   let pipe = proc.standardInput as? Pipe
			{
				pipe.fileHandleForWriting.write(Data(data.utf8))
			}

		case "close":
			if let proc = activeCommands[id],
			   let pipe = proc.standardInput as? Pipe
			{
				pipe.fileHandleForWriting.closeFile()
			}

		default:
			break
		}
	}

	private func launchSystemCommand(id: String, command: String) {
		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: "/bin/sh")
		proc.arguments = ["-c", command]
		proc.environment = environment

		let stdinPipe = Pipe()
		proc.standardInput = stdinPipe

		let stdoutPipe = Pipe()
		proc.standardOutput = stdoutPipe

		let stderrPipe = Pipe()
		proc.standardError = stderrPipe

		stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			let str = String(data: data, encoding: .utf8) ?? ""
			Task { @MainActor [weak self] in
				self?.updateJSCommandOutput(id: id, output: str, isError: false)
			}
		}

		stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			let str = String(data: data, encoding: .utf8) ?? ""
			Task { @MainActor [weak self] in
				self?.updateJSCommandOutput(id: id, output: str, isError: true)
			}
		}

		proc.terminationHandler = { [weak self] process in
			Task { @MainActor [weak self] in
				self?.finishJSCommand(id: id, exitStatus: process.terminationStatus)
			}
		}

		do {
			try proc.run()
			activeCommands[id] = proc
		} catch {
			finishJSCommand(id: id, exitStatus: -1)
		}
	}

	/// Push incremental output back to the JS command object.
	private func updateJSCommandOutput(id: String, output: String, isError: Bool) {
		let escaped = output
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "'", with: "\\'")
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
		let field = isError ? "errorString" : "outputString"
		let handler = isError ? "onreaderror" : "onreadoutput"
		let js = """
		(function() {
			var cmd = (window._tm_commands || {})['\(id)'];
			if (cmd) {
				cmd.\(field) += '\(escaped)';
				if (typeof cmd.\(handler) === 'function') {
					cmd.\(handler)('\(escaped)');
				}
			}
		})();
		"""
		webView.evaluateJavaScript(js)
	}

	/// Notify JS that a system() command has finished.
	private func finishJSCommand(id: String, exitStatus: Int32) {
		activeCommands.removeValue(forKey: id)
		let js = """
		(function() {
			var cmd = (window._tm_commands || {})['\(id)'];
			if (cmd) {
				cmd.status = \(exitStatus);
				if (typeof cmd._handler === 'function') {
					cmd._handler(cmd);
				}
				delete (window._tm_commands || {})['\(id)'];
			}
		})();
		"""
		webView.evaluateJavaScript(js)
	}

	// MARK: - WKNavigationDelegate

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
			// Handle txmt:// URLs — open file at line
			delegate?.htmlOutputView(self, handleTxMtURL: url)
			decisionHandler(.cancel)
		} else if url.scheme == "http" || url.scheme == "https" {
			// For external links, open in the default browser
			if navigationAction.navigationType == .linkActivated {
				NSWorkspace.shared.open(url)
				decisionHandler(.cancel)
			} else {
				decisionHandler(.allow)
			}
		} else {
			decisionHandler(.allow)
		}
	}

	public func webView(_: WKWebView, didFinish _: WKNavigation!) {
		isRunningCommand = false
		autoScrollEnabled = false
		delegate?.htmlOutputViewDidFinishLoading(self)
	}

	public func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
		isRunningCommand = false
		autoScrollEnabled = false
		delegate?.htmlOutputView(self, didFailWithError: error)
	}

	// MARK: - Printing

	/// Print the web view content.
	@IBAction public func printDocument(_: Any?) {
		webView.printOperation(with: .shared).runModal(
			for: window ?? NSApp.mainWindow ?? NSWindow(),
			delegate: nil,
			didRun: nil,
			contextInfo: nil,
		)
	}
}

// MARK: - Delegate Protocol

/// Delegate for `HTMLOutputView` events.
@MainActor
public protocol HTMLOutputViewDelegate: AnyObject {
	/// A `txmt://` URL was activated.
	func htmlOutputView(_ view: HTMLOutputView, handleTxMtURL url: URL)

	/// A request to open a file from JavaScript `TextMate.open()`.
	func htmlOutputView(_ view: HTMLOutputView, openFile path: String, options: String?)

	/// The web view finished loading.
	func htmlOutputViewDidFinishLoading(_ view: HTMLOutputView)

	/// The web view failed to load.
	func htmlOutputView(_ view: HTMLOutputView, didFailWithError error: Error)
}

/// Default no-op implementations.
public extension HTMLOutputViewDelegate {
	func htmlOutputView(_: HTMLOutputView, handleTxMtURL _: URL) {}
	func htmlOutputView(_: HTMLOutputView, openFile _: String, options _: String?) {}
	func htmlOutputViewDidFinishLoading(_: HTMLOutputView) {}
	func htmlOutputView(_: HTMLOutputView, didFailWithError _: Error) {}
}
#endif
