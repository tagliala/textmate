#if canImport(AppKit)
import AppKit

/// Files preferences pane — session restore, new document behavior, encoding, line endings.
///
/// Port of `Frameworks/Preferences/src/FilesPreferences.mm`.
@MainActor
public final class FilesPreferencesPane: PreferencesPane {
	override public var toolbarItemImage: NSImage? {
		NSImage(systemSymbolName: "doc", accessibilityDescription: "Files")
	}

	override public var toolbarItemLabel: String {
		"Files"
	}

	override public var paneIdentifier: String {
		"Files"
	}

	override public var defaultsProperties: [String: String] {
		[
			"disableSessionRestore": PreferencesKeys.disableSessionRestore,
			"disableDocumentAtStartup": PreferencesKeys.disableNewDocumentAtStartup,
			"disableDocumentAtReactivation": PreferencesKeys.disableNewDocumentAtReactivation,
		]
	}

	override public var tmProperties: [String: String] {
		[
			"encoding": "encoding",
			"lineEndings": "lineEndings",
		]
	}

	// MARK: - UI State

	/// Available file types for popup menus. Set by the app on configuration.
	public var availableFileTypes: [(name: String, scope: String)] = []

	/// Selected default file type scope for new documents.
	public var defaultFileType: String = "text.plain" {
		didSet { newFileTypePopUp?.selectItem(withTitle: nameForScope(defaultFileType) ?? defaultFileType) }
	}

	/// Selected file type scope for unknown documents.
	public var unknownFileType: String = "text.plain" {
		didSet { unknownFileTypePopUp?.selectItem(withTitle: nameForScope(unknownFileType) ?? unknownFileType) }
	}

	/// Current encoding name.
	public var selectedEncoding: String = "UTF-8" {
		didSet { encodingPopUp?.selectItem(withTitle: selectedEncoding) }
	}

	/// Current line ending. 0=LF, 1=CR, 2=CRLF.
	public var selectedLineEnding: Int = 0 {
		didSet { lineEndingPopUp?.selectItem(at: selectedLineEnding) }
	}

	/// Callback when a preference value changes.
	public var onPreferenceChanged: ((String, Any?) -> Void)?

	// MARK: - Outlets

	private var newFileTypePopUp: NSPopUpButton?
	private var unknownFileTypePopUp: NSPopUpButton?
	private var encodingPopUp: NSPopUpButton?
	private var lineEndingPopUp: NSPopUpButton?

	// MARK: - View Loading

	override public func loadView() {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 340))

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
		// Session restore
		let sessionCheckbox = makeCheckbox(
			"Open documents from last session",
			key: "disableSessionRestore", negated: true,
		)
		let sessionHint = makeHintLabel("Hold shift (⇧) on launch to bypass")

		// New document behavior
		let startupCheckbox = makeCheckbox(
			"Create new document at startup",
			key: "disableDocumentAtStartup", negated: true,
		)
		let reactivateCheckbox = makeCheckbox(
			"Create new document on re-activation",
			key: "disableDocumentAtReactivation", negated: true,
		)

		// File type popups
		let fileTypeLabel = makeLabel("New document type:")
		let fileTypePopUp = makeFileTypePopUp(action: #selector(selectNewFileType(_:)))
		newFileTypePopUp = fileTypePopUp

		let unknownLabel = makeLabel("Unknown document type:")
		let unknownPopUp = makeFileTypePopUp(action: #selector(selectUnknownFileType(_:)))
		unknownFileTypePopUp = unknownPopUp

		// Encoding
		let encodingLabel = makeLabel("Encoding:")
		let encPopUp = makeEncodingPopUp()
		encodingPopUp = encPopUp

		// Line endings
		let lineEndLabel = makeLabel("Line endings:")
		let lePopUp = makeLineEndingPopUp()
		lineEndingPopUp = lePopUp

		let rows: [[NSView]] = [
			[makeLabel(""), sessionCheckbox],
			[makeLabel(""), sessionHint],
			[makeLabel(""), startupCheckbox],
			[makeLabel(""), reactivateCheckbox],
			[makeSeparator(), makeSeparator()],
			[fileTypeLabel, fileTypePopUp],
			[unknownLabel, unknownPopUp],
			[makeSeparator(), makeSeparator()],
			[encodingLabel, encPopUp],
			[lineEndLabel, lePopUp],
		]

		let grid = NSGridView(views: rows)
		grid.rowAlignment = .firstBaseline
		grid.rowSpacing = 8
		grid.column(at: 0).width = 200
		grid.column(at: 0).xPlacement = .trailing

		return grid
	}

	// MARK: - Actions

	@objc private func selectNewFileType(_ sender: NSPopUpButton) {
		if let item = sender.selectedItem, let scope = item.representedObject as? String {
			defaultFileType = scope
			onPreferenceChanged?("defaultFileType", scope)
		}
	}

	@objc private func selectUnknownFileType(_ sender: NSPopUpButton) {
		if let item = sender.selectedItem, let scope = item.representedObject as? String {
			unknownFileType = scope
			onPreferenceChanged?("unknownFileType", scope)
		}
	}

	// MARK: - Helpers

	private func nameForScope(_ scope: String) -> String? {
		availableFileTypes.first(where: { $0.scope == scope })?.name
	}

	private func makeCheckbox(_ title: String, key: String, negated: Bool) -> NSButton {
		let btn = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged(_:)))
		btn.identifier = NSUserInterfaceItemIdentifier(key + (negated ? ".negated" : ""))
		return btn
	}

	@objc private func checkboxChanged(_ sender: NSButton) {
		guard let id = sender.identifier?.rawValue else { return }
		let negated = id.hasSuffix(".negated")
		let key = negated ? String(id.dropLast(8)) : id
		let value = negated ? (sender.state == .off) : (sender.state == .on)
		setValue(value, forUndefinedKey: key)
	}

	private func makeLabel(_ text: String) -> NSTextField {
		let label = NSTextField(labelWithString: text)
		label.alignment = .right
		return label
	}

	private func makeHintLabel(_ text: String) -> NSTextField {
		let label = NSTextField(labelWithString: text)
		label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		label.textColor = .secondaryLabelColor
		return label
	}

	private func makeSeparator() -> NSBox {
		let sep = NSBox()
		sep.boxType = .separator
		return sep
	}

	private func makeFileTypePopUp(action: Selector) -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		for ft in availableFileTypes {
			let item = NSMenuItem(title: ft.name, action: nil, keyEquivalent: "")
			item.representedObject = ft.scope
			popup.menu?.addItem(item)
		}
		popup.target = self
		popup.action = action
		return popup
	}

	private func makeEncodingPopUp() -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		let encodings = [
			"UTF-8",
			"UTF-16",
			"UTF-16 LE",
			"UTF-16 BE",
			"ASCII",
			"ISO 8859-1",
			"Mac OS Roman",
			"Windows Latin 1",
			"Shift JIS",
			"EUC-JP",
			"GB 18030",
			"Big5",
		]
		for enc in encodings {
			popup.addItem(withTitle: enc)
		}
		popup.target = self
		popup.action = #selector(encodingChanged(_:))
		popup.selectItem(withTitle: selectedEncoding)
		return popup
	}

	@objc private func encodingChanged(_ sender: NSPopUpButton) {
		if let title = sender.selectedItem?.title {
			selectedEncoding = title
			setValue(title, forUndefinedKey: "encoding")
		}
	}

	private func makeLineEndingPopUp() -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		popup.addItem(withTitle: "LF (macOS / Unix)")
		popup.addItem(withTitle: "CR (Classic Mac)")
		popup.addItem(withTitle: "CRLF (Windows)")
		popup.target = self
		popup.action = #selector(lineEndingChanged(_:))
		popup.selectItem(at: selectedLineEnding)
		return popup
	}

	@objc private func lineEndingChanged(_ sender: NSPopUpButton) {
		selectedLineEnding = sender.indexOfSelectedItem
		setValue(selectedLineEnding, forUndefinedKey: "lineEndings")
	}
}
#endif
