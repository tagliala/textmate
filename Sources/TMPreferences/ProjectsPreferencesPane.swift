#if canImport(AppKit)
import AppKit

/// Projects preferences pane — file browser, tabs, glob patterns, HTML output placement.
///
/// Port of `Frameworks/Preferences/src/ProjectsPreferences.mm`.
@MainActor
public final class ProjectsPreferencesPane: PreferencesPane {
	override public var toolbarItemImage: NSImage? {
		NSImage(systemSymbolName: "folder", accessibilityDescription: "Projects")
	}

	override public var toolbarItemLabel: String {
		"Projects"
	}

	override public var paneIdentifier: String {
		"Projects"
	}

	override public var defaultsProperties: [String: String] {
		[
			"foldersOnTop": PreferencesKeys.foldersOnTop,
			"showFileExtensions": PreferencesKeys.showFileExtensions,
			"disableTabBarCollapsing": PreferencesKeys.disableTabBarCollapsing,
			"disableAutoResize": PreferencesKeys.disableFileBrowserWindowResize,
			"autoRevealFile": PreferencesKeys.autoRevealFile,
			"fileBrowserPlacement": PreferencesKeys.fileBrowserPlacement,
			"htmlOutputPlacement": PreferencesKeys.htmlOutputPlacement,
			"allowExpandingLinks": PreferencesKeys.allowExpandingLinks,
			"fileBrowserSingleClickToOpen": PreferencesKeys.fileBrowserSingleClickToOpen,
			"disableTabReordering": PreferencesKeys.disableTabReordering,
			"disableTabAutoClose": PreferencesKeys.disableTabAutoClose,
		]
	}

	override public var tmProperties: [String: String] {
		[
			"excludePattern": "excludeInFileChooser",
			"includePattern": "includeInFileChooser",
			"binaryPattern": "binary",
		]
	}

	/// Callback when a preference value changes.
	public var onPreferenceChanged: ((String, Any?) -> Void)?

	// MARK: - File browser location

	/// Current file browser root URL string.
	public var fileBrowserURL: String? {
		didSet { onPreferenceChanged?("fileBrowserURL", fileBrowserURL) }
	}

	// MARK: - View Loading

	override public func loadView() {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 500))

		let grid = buildGrid()
		grid.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(grid)

		NSLayoutConstraint.activate([
			grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
			grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
		])

		view = container
	}

	private func buildGrid() -> NSGridView {
		var rows: [[NSView]] = []

		// Section 1 — File browser
		rows.append([label("File browser location:"), fileBrowserLocationPopUp()])
		rows.append([label(""), checkbox("Folders on top", key: "foldersOnTop")])
		rows.append([label(""), checkbox("Show links as expandable", key: "allowExpandingLinks")])
		rows.append([label(""), checkbox("Open files on single click", key: "fileBrowserSingleClickToOpen")])
		rows.append([label(""), checkbox("Keep current document selected", key: "autoRevealFile")])

		// Separator
		rows.append([separator(), separator()])

		// Section 2 — File browser position
		rows.append([label("Show file browser on:"), fileBrowserPlacementPopUp()])
		rows.append([label(""), checkbox("Adjust window when toggling display", key: "disableAutoResize", negated: true)])

		// Separator
		rows.append([separator(), separator()])

		// Section 3 — Tabs
		rows.append([label(""), checkbox("Show tab bar for single document", key: "disableTabBarCollapsing")])
		rows.append([label(""), checkbox("Re-order tabs when opening files", key: "disableTabReordering", negated: true)])
		rows.append([label(""), checkbox("Automatically close unused tabs", key: "disableTabAutoClose", negated: true)])

		// Separator
		rows.append([separator(), separator()])

		// Section 4 — Glob patterns
		rows.append([label("Exclude files matching:"), textField(key: "excludePattern")])
		rows.append([label("Include files matching:"), textField(key: "includePattern")])
		rows.append([label("Non-text files:"), textField(key: "binaryPattern")])

		// Separator
		rows.append([separator(), separator()])

		// Section 5 — HTML output
		rows.append([label("Show command output:"), htmlOutputPlacementPopUp()])

		let grid = NSGridView(views: rows)
		grid.rowAlignment = .firstBaseline
		grid.rowSpacing = 8
		grid.column(at: 0).width = 200
		grid.column(at: 0).xPlacement = .trailing

		return grid
	}

	// MARK: - UI Builders

	private func fileBrowserLocationPopUp() -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		popup.addItem(withTitle: "Desktop")
		popup.lastItem?.representedObject = NSHomeDirectory() + "/Desktop"
		popup.addItem(withTitle: "Home")
		popup.lastItem?.representedObject = NSHomeDirectory()
		popup.addItem(withTitle: "Computer")
		popup.lastItem?.representedObject = "/"
		popup.menu?.addItem(.separator())
		popup.addItem(withTitle: "Other…")
		popup.target = self
		popup.action = #selector(fileBrowserLocationChanged(_:))
		return popup
	}

	@objc private func fileBrowserLocationChanged(_ sender: NSPopUpButton) {
		if sender.selectedItem?.title == "Other…" {
			let panel = NSOpenPanel()
			panel.canChooseDirectories = true
			panel.canChooseFiles = false
			panel.allowsMultipleSelection = false
			panel.beginSheetModal(for: view.window!) { response in
				if response == .OK, let url = panel.url {
					self.fileBrowserURL = url.path
					UserDefaults.standard.set(url.absoluteString, forKey: PreferencesKeys.initialFileBrowserURL)
				}
			}
		} else if let path = sender.selectedItem?.representedObject as? String {
			fileBrowserURL = path
			UserDefaults.standard.set("file://" + path, forKey: PreferencesKeys.initialFileBrowserURL)
		}
	}

	private func fileBrowserPlacementPopUp() -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		popup.addItem(withTitle: "Left")
		popup.addItem(withTitle: "Right")
		popup.target = self
		popup.action = #selector(placementChanged(_:))
		let current = UserDefaults.standard.string(forKey: PreferencesKeys.fileBrowserPlacement) ?? "right"
		popup.selectItem(at: current == "left" ? 0 : 1)
		return popup
	}

	@objc private func placementChanged(_ sender: NSPopUpButton) {
		let placement = sender.indexOfSelectedItem == 0 ? "left" : "right"
		setValue(placement, forUndefinedKey: "fileBrowserPlacement")
	}

	private func htmlOutputPlacementPopUp() -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		popup.addItem(withTitle: "At bottom of project window")
		popup.addItem(withTitle: "At right of project window")
		popup.addItem(withTitle: "In new window")
		popup.target = self
		popup.action = #selector(htmlPlacementChanged(_:))
		let current = UserDefaults.standard.string(forKey: PreferencesKeys.htmlOutputPlacement) ?? "window"
		switch current {
		case "bottom": popup.selectItem(at: 0)
		case "right": popup.selectItem(at: 1)
		default: popup.selectItem(at: 2)
		}
		return popup
	}

	@objc private func htmlPlacementChanged(_ sender: NSPopUpButton) {
		let values = ["bottom", "right", "window"]
		let idx = sender.indexOfSelectedItem
		if idx >= 0, idx < values.count {
			setValue(values[idx], forUndefinedKey: "htmlOutputPlacement")
		}
	}

	private func checkbox(_ title: String, key: String, negated: Bool = false) -> NSButton {
		let btn = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged(_:)))
		btn.identifier = NSUserInterfaceItemIdentifier(key + (negated ? ".negated" : ""))
		let savedValue = UserDefaults.standard.bool(forKey: defaultsProperties[key] ?? key)
		btn.state = (negated ? !savedValue : savedValue) ? .on : .off
		return btn
	}

	@objc private func checkboxChanged(_ sender: NSButton) {
		guard let id = sender.identifier?.rawValue else { return }
		let negated = id.hasSuffix(".negated")
		let key = negated ? String(id.dropLast(8)) : id
		let value = negated ? (sender.state == .off) : (sender.state == .on)
		setValue(value, forUndefinedKey: key)
		onPreferenceChanged?(key, value)
	}

	private func textField(key: String) -> NSTextField {
		let field = NSTextField()
		field.placeholderString = "e.g., *.o, build/"
		if let settingsKey = tmProperties[key],
		   let currentValue = PreferencesSettingsBridge.shared.getValue(for: settingsKey) as? String
		{
			field.stringValue = currentValue
		}
		field.identifier = NSUserInterfaceItemIdentifier(key)
		field.target = self
		field.action = #selector(textFieldChanged(_:))
		return field
	}

	@objc private func textFieldChanged(_ sender: NSTextField) {
		guard let key = sender.identifier?.rawValue else { return }
		setValue(sender.stringValue, forUndefinedKey: key)
		onPreferenceChanged?(key, sender.stringValue)
	}

	private func label(_ text: String) -> NSTextField {
		let l = NSTextField(labelWithString: text)
		l.alignment = .right
		return l
	}

	private func separator() -> NSBox {
		let sep = NSBox()
		sep.boxType = .separator
		return sep
	}
}
#endif
