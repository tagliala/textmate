#if canImport(AppKit)
import AppKit

// MARK: - Built-In Registration

public extension DialogShim {
	/// Register the built-in handlers for the standard `tm_dialog2` commands.
	///
	/// Call this once during application startup or when wiring a window
	/// controller. Subsequent calls are safe — existing registrations are
	/// overwritten with the same instances.
	func registerBuiltInHandlers() {
		register(AlertDialogHandler(), forCommand: "alert")
		register(MenuDialogHandler(), forCommand: "menu")
		register(TooltipDialogHandler(shim: self), forCommand: "tooltip")
		register(FilePanelDialogHandler(), forCommand: "filepanel")
		register(HelpDialogHandler(), forCommand: "help")
	}
}

// MARK: - Alert Handler

/// Handles the `alert` command: shows an `NSAlert` and returns the
/// index of the pressed button.
@MainActor
public struct AlertDialogHandler: DialogCommandHandler {
	public init() {}

	public func handle(command _: String, arguments: [String], input: Data?) -> DialogResult {
		// Parse arguments: --title <t> --body <b> --button1 <b1> --button2 <b2> --button3 <b3>
		var title = "Alert"
		var body = ""
		var buttons: [String] = []

		// Also accept plist input with keys: alertTitle, informativeText, buttons
		if let data = input,
		   let plist = try? PropertyListSerialization.propertyList(
		   	from: data, format: nil,
		   ) as? [String: Any]
		{
			if let t = plist["alertTitle"] as? String ?? plist["title"] as? String {
				title = t
			}
			if let b = plist["informativeText"] as? String ?? plist["body"] as? String {
				body = b
			}
			if let btns = plist["buttons"] as? [String] {
				buttons = btns
			}
		}

		// Command-line arguments override plist.
		var i = 0
		while i < arguments.count {
			switch arguments[i] {
			case "--title" where i + 1 < arguments.count:
				title = arguments[i + 1]
				i += 2
			case "--body" where i + 1 < arguments.count:
				body = arguments[i + 1]
				i += 2
			case "--button1" where i + 1 < arguments.count:
				if buttons.isEmpty { buttons.append(arguments[i + 1]) }
				else { buttons[0] = arguments[i + 1] }
				i += 2
			case "--button2" where i + 1 < arguments.count:
				while buttons.count < 2 {
					buttons.append("")
				}
				buttons[1] = arguments[i + 1]
				i += 2
			case "--button3" where i + 1 < arguments.count:
				while buttons.count < 3 {
					buttons.append("")
				}
				buttons[2] = arguments[i + 1]
				i += 2
			default:
				i += 1
			}
		}

		if buttons.isEmpty { buttons = ["OK"] }

		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = body
		for btn in buttons {
			alert.addButton(withTitle: btn)
		}

		let response = alert.runModal()
		let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

		let output: [String: Any] = ["buttonIndex": index]
		return DialogResult(exitCode: 0, output: output, errorMessage: nil)
	}
}

// MARK: - Menu Handler

/// Handles the `menu` command: shows a popup menu and returns the
/// selected item index.
@MainActor
public struct MenuDialogHandler: DialogCommandHandler {
	public init() {}

	public func handle(command _: String, arguments _: [String], input: Data?) -> DialogResult {
		// Expects plist input with key "menuItems": array of dicts with "title" key.
		guard let data = input,
		      let plist = try? PropertyListSerialization.propertyList(
		      	from: data, format: nil,
		      ) as? [String: Any],
		      let items = plist["menuItems"] as? [[String: Any]]
		else {
			return DialogResult(exitCode: 1, output: nil, errorMessage: "Expected 'menuItems' in input plist.\n")
		}

		let menuItems = items.map { dict -> DialogMenuItem in
			let title = dict["title"] as? String ?? ""
			let separator = dict["separator"] as? Bool ?? (title == "-")
			let disabled = dict["isDisabled"] as? Bool ?? false
			return DialogMenuItem(title: title, isSeparator: separator, isDisabled: disabled)
		}

		let location = NSEvent.mouseLocation
		if let selected = DialogShim.shared.showMenu(items: menuItems, at: location) {
			let output: [String: Any] = ["selectedIndex": selected]
			return DialogResult(exitCode: 0, output: output, errorMessage: nil)
		}

		// User cancelled.
		return DialogResult(exitCode: 0, output: nil, errorMessage: nil)
	}
}

// MARK: - Tooltip Handler

/// Handles the `tooltip` command: shows a tooltip near the caret.
@MainActor
public struct TooltipDialogHandler: DialogCommandHandler {
	private weak var shim: DialogShim?

	public init(shim: DialogShim) {
		self.shim = shim
	}

	public func handle(command _: String, arguments: [String], input: Data?) -> DialogResult {
		var text = ""
		var isHTML = false

		// Parse arguments: --text <text> or --html
		var i = 0
		while i < arguments.count {
			switch arguments[i] {
			case "--text" where i + 1 < arguments.count:
				text = arguments[i + 1]
				i += 2
			case "--html":
				isHTML = true
				i += 1
			default:
				i += 1
			}
		}

		// If text wasn't set via arguments, try plist input.
		if text.isEmpty, let data = input {
			if let plist = try? PropertyListSerialization.propertyList(
				from: data, format: nil,
			) as? [String: Any] {
				text = plist["text"] as? String ?? plist["content"] as? String ?? ""
				if let html = plist["html"] as? Bool { isHTML = html }
			} else if let str = String(data: data, encoding: .utf8) {
				text = str
			}
		}

		guard !text.isEmpty else {
			return DialogResult(exitCode: 1, output: nil, errorMessage: "No text provided.\n")
		}

		let location = NSEvent.mouseLocation
		if isHTML {
			shim?.showToolTip(html: text, at: location)
		} else {
			shim?.showToolTip(html: "<pre>\(text.escapedForHTML)</pre>", at: location)
		}

		return DialogResult(exitCode: 0, output: nil, errorMessage: nil)
	}
}

// MARK: - File Panel Handler

/// Handles the `filepanel` command: shows an open or save panel.
@MainActor
public struct FilePanelDialogHandler: DialogCommandHandler {
	public init() {}

	public func handle(command _: String, arguments: [String], input _: Data?) -> DialogResult {
		// Arguments: --save, --directory <dir>, --title <title>
		var isSave = false
		var directory: String?
		var title: String?

		var i = 0
		while i < arguments.count {
			switch arguments[i] {
			case "--save":
				isSave = true
				i += 1
			case "--directory" where i + 1 < arguments.count:
				directory = arguments[i + 1]
				i += 2
			case "--title" where i + 1 < arguments.count:
				title = arguments[i + 1]
				i += 2
			default:
				i += 1
			}
		}

		if isSave {
			if let path = DialogShim.shared.showSavePanel(title: title, directory: directory) {
				let output: [String: Any] = ["path": path]
				return DialogResult(exitCode: 0, output: output, errorMessage: nil)
			}
			return DialogResult(exitCode: 0, output: nil, errorMessage: nil)
		} else {
			let paths = DialogShim.shared.showOpenPanel(
				title: title,
				directory: directory,
			)
			if !paths.isEmpty {
				let output: [String: Any] = ["paths": paths]
				return DialogResult(exitCode: 0, output: output, errorMessage: nil)
			}
			return DialogResult(exitCode: 0, output: nil, errorMessage: nil)
		}
	}
}

// MARK: - Help Handler

/// Handles the `help` command: returns the list of registered commands.
@MainActor
public struct HelpDialogHandler: DialogCommandHandler {
	public init() {}

	public func handle(command _: String, arguments _: [String], input _: Data?) -> DialogResult {
		let commands = DialogShim.shared.registeredCommands
		let text = "Available commands: \(commands.joined(separator: ", "))\n"
		return DialogResult(exitCode: 0, output: text, errorMessage: nil)
	}
}

// MARK: - String HTML Escaping

extension String {
	/// Minimal HTML entity escaping for tooltip display.
	var escapedForHTML: String {
		replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}
}
#endif
