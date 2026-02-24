#if canImport(AppKit)
import AppKit

/// Compatibility shim for the `tm_dialog2` plugin.
///
/// The original C++ implementation (`PlugIns/dialog/Dialog2.mm`) uses
/// `NSConnection` to expose a DIALOG server to subprocesses. This shim
/// provides equivalent high-level Swift APIs and a registry of command
/// handlers so bundle commands can show menus, tooltips, alerts, and
/// panels without touching the Obj-C plugin.
@MainActor
public final class DialogShim {
	/// Shared instance (mirrors the singleton nature of Dialog2).
	public static let shared = DialogShim()

	/// Registered command handlers keyed by command name.
	private var commands: [String: DialogCommandHandler] = [:]

	private init() {}

	// MARK: - Command Registration

	/// Register a handler for a named dialog command.
	///
	/// The original tm_dialog2 commands are:
	///  menu, filepanel, images, tooltip, popup, x-insert, defaults,
	///  prototype, alert, nib, help
	public func register(_ handler: DialogCommandHandler, forCommand name: String) {
		commands[name] = handler
	}

	/// Retrieve the handler for a given command name.
	public func handler(forCommand name: String) -> DialogCommandHandler? {
		commands[name]
	}

	/// All registered command names.
	public var registeredCommands: [String] {
		Array(commands.keys.sorted())
	}

	// MARK: - Dispatch

	/// Dispatch a command from its argument list, similar to
	/// `[Dialog2 connectFromClientWithOptions:]`.
	///
	/// - Parameters:
	///   - arguments: Command-line-style arguments, where
	///     `arguments[0]` is the binary name and `arguments[1]`
	///     is the command name.
	///   - input: Optional plist data from stdin.
	/// - Returns: The result as a property list, or `nil`.
	public func dispatch(
		arguments: [String],
		input: Data? = nil,
	) -> DialogResult {
		guard arguments.count > 1 else {
			return DialogResult(
				exitCode: 1,
				output: nil,
				errorMessage: "Usage: tm_dialog2 <command> [options]\n",
			)
		}

		let commandName = arguments[1]
		guard let handler = commands[commandName] else {
			return DialogResult(
				exitCode: 1,
				output: nil,
				errorMessage: "Unknown command '\(commandName)'. Try 'help'.\n",
			)
		}

		let options = Array(arguments.dropFirst(2))
		return handler.handle(command: commandName, arguments: options, input: input)
	}

	// MARK: - High-Level APIs

	/// Show a contextual menu near the caret.
	///
	/// - Parameters:
	///   - items: Menu items to display.
	///   - location: Screen point to show the menu at.
	/// - Returns: The index of the selected item, or `nil` if cancelled.
	public func showMenu(
		items: [DialogMenuItem],
		at location: NSPoint,
	) -> Int? {
		let menu = NSMenu(title: "")
		for (idx, item) in items.enumerated() {
			if item.isSeparator {
				menu.addItem(.separator())
			} else {
				let mi = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
				mi.tag = idx
				mi.isEnabled = !item.isDisabled
				menu.addItem(mi)
			}
		}

		guard menu.popUp(positioning: nil, at: location, in: nil) else {
			return nil
		}

		let highlighted = menu.highlightedItem
		return highlighted?.tag
	}

	/// Show a tooltip with HTML content.
	///
	/// - Parameters:
	///   - html: HTML content to render.
	///   - at: Screen location for the tooltip.
	///   - transparent: Whether the tooltip background is transparent.
	public func showToolTip(
		html: String,
		at location: NSPoint,
		transparent: Bool = false,
	) {
		delegate?.dialogShim(self, showToolTipHTML: html, at: location, transparent: transparent)
	}

	/// Show an alert dialog.
	///
	/// - Parameters:
	///   - title: The alert title.
	///   - message: Informative text.
	///   - buttons: Button titles (first is default).
	///   - alertStyle: The NSAlert style.
	/// - Returns: The index of the button pressed (0-based).
	public func showAlert(
		title: String,
		message: String = "",
		buttons: [String] = ["OK"],
		alertStyle: NSAlert.Style = .informational,
	) -> Int {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.alertStyle = alertStyle
		for btn in buttons {
			alert.addButton(withTitle: btn)
		}
		let response = alert.runModal()
		return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
	}

	/// Show an open panel.
	///
	/// - Parameters:
	///   - title: Panel title.
	///   - directory: Initial directory.
	///   - canChooseFiles: Whether files can be selected.
	///   - canChooseDirectories: Whether directories can be selected.
	///   - allowsMultipleSelection: Whether multiple items can be selected.
	/// - Returns: Selected paths, or empty if cancelled.
	public func showOpenPanel(
		title: String? = nil,
		directory: String? = nil,
		canChooseFiles: Bool = true,
		canChooseDirectories: Bool = false,
		allowsMultipleSelection: Bool = false,
	) -> [String] {
		let panel = NSOpenPanel()
		if let title { panel.title = title }
		if let directory { panel.directoryURL = URL(fileURLWithPath: directory) }
		panel.canChooseFiles = canChooseFiles
		panel.canChooseDirectories = canChooseDirectories
		panel.allowsMultipleSelection = allowsMultipleSelection

		guard panel.runModal() == .OK else { return [] }
		return panel.urls.map(\.path)
	}

	/// Show a save panel.
	///
	/// - Parameters:
	///   - title: Panel title.
	///   - directory: Initial directory.
	///   - fileName: Default file name.
	/// - Returns: The save path, or `nil` if cancelled.
	public func showSavePanel(
		title: String? = nil,
		directory: String? = nil,
		fileName: String? = nil,
	) -> String? {
		let panel = NSSavePanel()
		if let title { panel.title = title }
		if let directory { panel.directoryURL = URL(fileURLWithPath: directory) }
		if let fileName { panel.nameFieldStringValue = fileName }

		guard panel.runModal() == .OK else { return nil }
		return panel.url?.path
	}

	/// Delegate for UI operations that need view context.
	public weak var delegate: DialogShimDelegate?
}

// MARK: - Supporting Types

/// A menu item for `DialogShim.showMenu()`.
public struct DialogMenuItem: Sendable {
	public var title: String
	public var isSeparator: Bool
	public var isDisabled: Bool

	public init(title: String = "", isSeparator: Bool = false, isDisabled: Bool = false) {
		self.title = title
		self.isSeparator = isSeparator
		self.isDisabled = isDisabled
	}
}

/// Result from a dispatched dialog command.
public struct DialogResult {
	/// Exit code (0 for success).
	public let exitCode: Int32

	/// The output property list (if any).
	public let output: Any?

	/// Error message (if any).
	public let errorMessage: String?

	/// Serialized output as property list data.
	public var outputData: Data? {
		guard let output else { return nil }
		return try? PropertyListSerialization.data(
			fromPropertyList: output,
			format: .xml,
			options: 0,
		)
	}

	public init(exitCode: Int32, output: Any?, errorMessage: String?) {
		self.exitCode = exitCode
		self.output = output
		self.errorMessage = errorMessage
	}
}

/// Handler protocol for individual dialog commands.
@MainActor
public protocol DialogCommandHandler {
	/// Handle a dialog command.
	///
	/// - Parameters:
	///   - command: The command name.
	///   - arguments: Additional arguments after the command name.
	///   - input: Optional plist data from stdin.
	/// - Returns: The result of the command.
	func handle(command: String, arguments: [String], input: Data?) -> DialogResult
}

/// Delegate for dialog operations that need view context.
@MainActor
public protocol DialogShimDelegate: AnyObject {
	/// Show an HTML tooltip.
	func dialogShim(
		_ shim: DialogShim,
		showToolTipHTML html: String,
		at location: NSPoint,
		transparent: Bool,
	)
}
#endif
