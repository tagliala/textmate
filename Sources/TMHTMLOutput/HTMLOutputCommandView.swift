#if canImport(AppKit) && canImport(WebKit)
import AppKit
import WebKit

/// Delegate protocol for HTML output command view events.
@MainActor
public protocol HTMLOutputCommandViewDelegate: AnyObject {
	/// Handle a `txmt://` URL activation (open file at line).
	func commandView(_ view: HTMLOutputCommandView, handleTxMtURL url: URL)
	/// Handle an `open()` call from JavaScript.
	func commandView(_ view: HTMLOutputCommandView, openFile path: String, options: String?)
	/// The command view finished loading.
	func commandViewDidFinishLoading(_ view: HTMLOutputCommandView)
}

/// Default no-op implementations.
public extension HTMLOutputCommandViewDelegate {
	func commandView(_: HTMLOutputCommandView, handleTxMtURL _: URL) {}
	func commandView(_: HTMLOutputCommandView, openFile _: String, options _: String?) {}
	func commandViewDidFinishLoading(_: HTMLOutputCommandView) {}
}

/// Full HTML output view for TextMate bundle commands.
///
/// Ports `Frameworks/HTMLOutput/src/OakHTMLOutputView.mm`.
/// Composes `HTMLOutputBrowserView` with:
/// - TextMate JavaScript bridge (`TextMate.system()`, `TextMate.log()`, `TextMate.open()`)
/// - Auto-scroll while a command is running
/// - Command lifecycle management (`loadCommand`, `stopCommand` with user confirmation)
/// - Reusability for sequential command output
/// - Printing support
@MainActor
public final class HTMLOutputCommandView: NSView {
	// MARK: - Public Properties

	/// The underlying browser view providing WKWebView + status bar.
	public let browserView: HTMLOutputBrowserView

	/// Delegate for command view events.
	public weak var delegate: HTMLOutputCommandViewDelegate?

	/// UUID of the command that produced this output.
	public var commandIdentifier: UUID?

	/// Whether a command is currently running.
	public private(set) var isRunningCommand = false

	/// Whether this view can be reused for the next command.
	public var isReusable: Bool = true

	/// Whether the JavaScript API (TextMate object) is disabled.
	public var disableJavaScriptAPI: Bool = false

	/// Environment variables passed to the JavaScript bridge's `system()`.
	public var environment: [String: String] = [:]

	/// The title of the current page.
	public var mainFrameTitle: String {
		browserView.webView.title ?? ""
	}

	// MARK: - Private State

	/// Whether auto-scrolling is enabled during command execution.
	private var autoScrollEnabled = false

	/// Active `TextMate.system()` subprocesses keyed by JS-assigned ID.
	private var activeCommands: [String: Process] = [:]

	/// Saved visible rect for content reload.
	private var pendingVisibleRect: CGRect = .zero

	// MARK: - Initialization

	override public init(frame: NSRect) {
		browserView = HTMLOutputBrowserView(frame: NSRect(origin: .zero, size: frame.size))

		super.init(frame: frame)

		browserView.delegate = self
		browserView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(browserView)

		NSLayoutConstraint.activate([
			browserView.topAnchor.constraint(equalTo: topAnchor),
			browserView.leadingAnchor.constraint(equalTo: leadingAnchor),
			browserView.trailingAnchor.constraint(equalTo: trailingAnchor),
			browserView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		setupJavaScriptBridge()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	// MARK: - Command Lifecycle

	/// Load a URL request as a command execution.
	///
	/// - Parameters:
	///   - request: The URL request to load.
	///   - environment: Environment variables for the JS bridge.
	///   - autoScrolls: Whether to auto-scroll as content is appended.
	///   - identifier: The UUID of the command producing this output.
	public func loadCommand(
		request: URLRequest,
		environment: [String: String] = [:],
		autoScrolls: Bool = false,
		identifier: UUID? = nil,
	) {
		self.environment = environment
		commandIdentifier = identifier
		autoScrollEnabled = autoScrolls
		isRunningCommand = identifier != nil

		browserView.startProgressUpdates()

		if !isRunningCommand {
			// For non-command loads, track page progress normally
			browserView.statusBar.busy = true
		}

		browserView.webView.load(request)
	}

	/// Stop the current command, optionally asking the user first.
	///
	/// - Parameters:
	///   - askUser: Whether to show a confirmation dialog before stopping.
	///   - completionHandler: Called with `true` if the command was stopped.
	public func stopCommand(askUser: Bool, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
		guard isRunningCommand else {
			completionHandler(true)
			return
		}

		if askUser {
			let alert = NSAlert()
			alert.messageText = "Stop Command?"
			alert.informativeText = "The job that the task is performing will not be completed."
			alert.addButton(withTitle: "Stop")
			alert.addButton(withTitle: "Cancel")

			if let window {
				alert.beginSheetModal(for: window) { [weak self] response in
					if response == .alertFirstButtonReturn {
						self?.forceStopCommand()
						completionHandler(true)
					} else {
						completionHandler(false)
					}
				}
			} else {
				let response = alert.runModal()
				if response == .alertFirstButtonReturn {
					forceStopCommand()
					completionHandler(true)
				} else {
					completionHandler(false)
				}
			}
		} else {
			forceStopCommand()
			completionHandler(true)
		}
	}

	/// Force-stop the command without user confirmation.
	private func forceStopCommand() {
		browserView.webView.stopLoading()
		terminateAllCommands()
		isRunningCommand = false
		autoScrollEnabled = false
		browserView.stopProgressUpdates()
	}

	/// Set HTML content directly (not from a command).
	public func setContent(_ html: String) {
		browserView.loadHTMLString(html, baseURL: URL(fileURLWithPath: NSHomeDirectory()))
	}

	/// Append HTML content to the current page.
	public func appendHTML(_ html: String) {
		let escaped = html
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "'", with: "\\'")
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
		let scroll = autoScrollEnabled ? "true" : "false"
		let js = """
		(function() {
			var container = document.getElementById('_tm_output') || document.body;
			if (container) {
				container.insertAdjacentHTML('beforeend', '\(escaped)');
				if (\(scroll)) { window.scrollTo(0, document.body.scrollHeight); }
			}
		})();
		"""
		browserView.webView.evaluateJavaScript(js)
	}

	// MARK: - Printing

	/// Print the web view content.
	@IBAction public func printDocument(_: Any?) {
		browserView.webView.printOperation(with: .shared).runModal(
			for: window ?? NSApp.mainWindow ?? NSWindow(),
			delegate: nil,
			didRun: nil,
			contextInfo: nil,
		)
	}

	// MARK: - JavaScript Bridge

	/// Inject the `TextMate` JavaScript bridge object.
	private func setupJavaScriptBridge() {
		let controller = browserView.webView.configuration.userContentController

		// Register message handlers
		let handler = JSBridgeHandler(commandView: self)
		controller.add(handler, name: "log")
		controller.add(handler, name: "openFile")
		controller.add(handler, name: "systemCommand")

		// Inject the bridge script
		let script = WKUserScript(
			source: Self.jsBridgeSource,
			injectionTime: .atDocumentStart,
			forMainFrameOnly: false,
		)
		controller.addUserScript(script)
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
			window.webkit.messageHandlers.systemCommand.postMessage({
				action: 'setBusy', value: !!val
			});
		},

		get progress() { return this._progress; },
		set progress(val) {
			this._progress = Number(val) || 0;
			window.webkit.messageHandlers.systemCommand.postMessage({
				action: 'setProgress', value: Number(val) || 0
			});
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

	// MARK: - System Command Management

	/// Launch a subprocess for `TextMate.system()`.
	func launchSystemCommand(id: String, command: String) {
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

	/// Write data to a running system command's stdin.
	func writeToCommand(id: String, data: String) {
		guard let proc = activeCommands[id],
		      let pipe = proc.standardInput as? Pipe
		else { return }
		pipe.fileHandleForWriting.write(Data(data.utf8))
	}

	/// Close a running system command's stdin.
	func closeCommandInput(id: String) {
		guard let proc = activeCommands[id],
		      let pipe = proc.standardInput as? Pipe
		else { return }
		pipe.fileHandleForWriting.closeFile()
	}

	/// Cancel a running system command.
	func cancelCommand(id: String) {
		activeCommands[id]?.terminate()
		activeCommands.removeValue(forKey: id)
	}

	/// Terminate all active system commands.
	private func terminateAllCommands() {
		for (_, proc) in activeCommands {
			proc.terminate()
		}
		activeCommands.removeAll()
	}

	/// Push incremental output to the JS command object.
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
		browserView.webView.evaluateJavaScript(js)
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
		browserView.webView.evaluateJavaScript(js)
	}

	/// Handle `TextMate.isBusy` changes from JavaScript.
	func handleBusyChange(_ value: Bool) {
		browserView.statusBar.busy = value
	}

	/// Handle `TextMate.progress` changes from JavaScript.
	func handleProgressChange(_ value: Double) {
		browserView.statusBar.progress = value
	}
}

// MARK: - HTMLOutputBrowserViewDelegate

extension HTMLOutputCommandView: HTMLOutputBrowserViewDelegate {
	public func browserView(_: HTMLOutputBrowserView, handleTxMtURL url: URL) {
		delegate?.commandView(self, handleTxMtURL: url)
	}

	public func browserView(_: HTMLOutputBrowserView, didFailWithError _: Error, for _: URL?) {
		isRunningCommand = false
		autoScrollEnabled = false
	}
}

// MARK: - JavaScript Bridge Message Handler

/// Handles messages from the TextMate JavaScript bridge.
private final class JSBridgeHandler: NSObject, WKScriptMessageHandler {
	private weak var commandView: HTMLOutputCommandView?

	init(commandView: HTMLOutputCommandView) {
		self.commandView = commandView
	}

	nonisolated func userContentController(
		_: WKUserContentController,
		didReceive message: WKScriptMessage,
	) {
		MainActor.assumeIsolated {
			self.handleMessage(name: message.name as String, body: message.body)
		}
	}

	@MainActor
	private func handleMessage(name: String, body: Any) {
		switch name {
		case "log":
			if let msg = body as? String {
				NSLog("JavaScript Log: %@", msg)
			}

		case "openFile":
			if let dict = body as? [String: Any],
			   let path = dict["path"] as? String
			{
				let options = dict["options"] as? String
				commandView?.delegate?.commandView(commandView!, openFile: path, options: options)
			}

		case "systemCommand":
			if let dict = body as? [String: Any] {
				handleSystemCommand(dict)
			}

		default:
			break
		}
	}

	@MainActor
	private func handleSystemCommand(_ dict: [String: Any]) {
		guard let action = dict["action"] as? String else { return }

		switch action {
		case "start":
			guard let id = dict["id"] as? String,
			      let command = dict["command"] as? String
			else { return }
			commandView?.launchSystemCommand(id: id, command: command)

		case "cancel":
			guard let id = dict["id"] as? String else { return }
			commandView?.cancelCommand(id: id)

		case "write":
			guard let id = dict["id"] as? String,
			      let data = dict["data"] as? String
			else { return }
			commandView?.writeToCommand(id: id, data: data)

		case "close":
			guard let id = dict["id"] as? String else { return }
			commandView?.closeCommandInput(id: id)

		case "setBusy":
			if let value = dict["value"] as? Bool {
				commandView?.handleBusyChange(value)
			}

		case "setProgress":
			if let value = dict["value"] as? Double {
				commandView?.handleProgressChange(value)
			}

		default:
			break
		}
	}
}

// MARK: - WKNavigationDelegate forwarding

extension HTMLOutputCommandView {
	/// Called by the browser view's navigation delegate when the page finishes loading.
	/// We hook into this via KVO or delegate forwarding to track command completion.
	func webViewDidFinishNavigation() {
		if isRunningCommand {
			isRunningCommand = false
			autoScrollEnabled = false
		}
		delegate?.commandViewDidFinishLoading(self)
	}
}
#endif
