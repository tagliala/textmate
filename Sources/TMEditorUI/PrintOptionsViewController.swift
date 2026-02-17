import AppKit
import TMTheme

// MARK: - Print Options View Controller

/// Accessory view controller for the print panel, allowing the user to
/// select a theme, font size, and header/footer options for printing.
///
/// Port of C++ `OakDocumentPrintOptionsViewController` from
/// `Frameworks/document/src/Printing.mm`.
///
/// Conforms to `NSPrintPanelAccessorizing` so the print panel shows
/// this view controller's UI alongside the standard print controls.
@MainActor
public class PrintOptionsViewController: NSViewController, NSPrintPanelAccessorizing {
	// MARK: - Theme Data

	/// A theme entry for the popup menu.
	public struct ThemeEntry: Sendable {
		public let name: String
		public let uuid: String

		public init(name: String, uuid: String) {
			self.name = name
			self.uuid = uuid
		}
	}

	/// The available themes (set before presenting the print panel).
	public var availableThemes: [ThemeEntry] = []

	// MARK: - UI Elements

	private var themesPopUp: NSPopUpButton!
	private var fontSizesPopUp: NSPopUpButton!
	private var headerCheckbox: NSButton!

	// MARK: - Initialization

	public init() {
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	// MARK: - View Lifecycle

	override public func loadView() {
		let contentView = NSView(frame: .zero)
		contentView.translatesAutoresizingMaskIntoConstraints = false

		// Theme label and popup
		let themesLabel = makeLabel("Theme:")
		themesPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
		themesPopUp.translatesAutoresizingMaskIntoConstraints = false
		rebuildThemesMenu()

		// Font size label and popup
		let fontSizesLabel = makeLabel("Font Size:")
		fontSizesPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
		fontSizesPopUp.translatesAutoresizingMaskIntoConstraints = false
		rebuildFontSizeMenu()

		// Header/footer checkbox
		headerCheckbox = NSButton(
			checkboxWithTitle: "Print header and footer",
			target: self,
			action: #selector(headerCheckboxChanged(_:)),
		)
		headerCheckbox.translatesAutoresizingMaskIntoConstraints = false

		// Actions
		themesPopUp.target = self
		themesPopUp.action = #selector(themeChanged(_:))
		fontSizesPopUp.target = self
		fontSizesPopUp.action = #selector(fontSizeChanged(_:))

		// Add subviews
		contentView.addSubview(themesLabel)
		contentView.addSubview(themesPopUp)
		contentView.addSubview(fontSizesLabel)
		contentView.addSubview(fontSizesPopUp)
		contentView.addSubview(headerCheckbox)

		// Layout constraints (matches C++ VFL layout)
		NSLayoutConstraint.activate([
			// Row 1: Theme
			themesLabel.trailingAnchor.constraint(equalTo: themesPopUp.leadingAnchor, constant: -8),
			themesLabel.firstBaselineAnchor.constraint(equalTo: themesPopUp.firstBaselineAnchor),
			themesLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 4),

			themesPopUp.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -4),
			themesPopUp.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),

			// Row 2: Font Size
			fontSizesLabel.trailingAnchor.constraint(equalTo: fontSizesPopUp.leadingAnchor, constant: -8),
			fontSizesLabel.firstBaselineAnchor.constraint(equalTo: fontSizesPopUp.firstBaselineAnchor),
			fontSizesLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 4),

			fontSizesPopUp.leadingAnchor.constraint(equalTo: themesPopUp.leadingAnchor),
			fontSizesPopUp.trailingAnchor.constraint(equalTo: themesPopUp.trailingAnchor),
			fontSizesPopUp.topAnchor.constraint(equalTo: themesPopUp.bottomAnchor, constant: 8),

			// Row 3: Header checkbox
			headerCheckbox.leadingAnchor.constraint(equalTo: fontSizesPopUp.leadingAnchor),
			headerCheckbox.topAnchor.constraint(equalTo: fontSizesPopUp.bottomAnchor, constant: 8),
			headerCheckbox.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
		])

		// Align labels to the right
		themesLabel.setContentHuggingPriority(.required, for: .horizontal)
		fontSizesLabel.setContentHuggingPriority(.required, for: .horizontal)

		contentView.frame = NSRect(origin: .zero, size: contentView.fittingSize)
		view = contentView
	}

	// MARK: - NSPrintPanelAccessorizing

	public func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
		[]
	}

	public func keyPathsForValuesAffectingPreview() -> Set<String> {
		["themeIndex", "printFontSize", "printHeaderAndFooter"]
	}

	// MARK: - Represented Object (NSPrintInfo)

	override public var representedObject: Any? {
		didSet {
			syncFromPrintInfo()
		}
	}

	private var printInfo: NSPrintInfo? {
		representedObject as? NSPrintInfo
	}

	/// Synchronize UI state from the print info dictionary.
	private func syncFromPrintInfo() {
		guard let info = printInfo else { return }
		let dict = info.dictionary()

		// Theme
		if let themeUUID = dict[PrintSettingKey.themeUUID] as? String {
			if let idx = availableThemes.firstIndex(where: { $0.uuid == themeUUID }) {
				themesPopUp?.selectItem(at: idx)
			}
		} else {
			// Default: first theme
			themesPopUp?.selectItem(at: 0)
			if let first = availableThemes.first {
				dict[PrintSettingKey.themeUUID] = first.uuid
			}
		}

		// Font size
		if let size = dict[PrintSettingKey.fontSize] as? NSNumber {
			let sizeStr = "\(size.intValue)"
			fontSizesPopUp?.selectItem(withTitle: sizeStr)
		} else {
			let defaultSize = UserDefaults.standard.integer(forKey: PrintSettingKey.fontSize)
			let size = defaultSize > 0 ? defaultSize : 11
			fontSizesPopUp?.selectItem(withTitle: "\(size)")
			dict[PrintSettingKey.fontSize] = NSNumber(value: size)
		}

		// Header/footer
		let headerKey = "NSPrintHeaderAndFooter"
		if let flag = dict[headerKey] as? NSNumber {
			headerCheckbox?.state = flag.boolValue ? .on : .off
		} else {
			let defaultFlag = UserDefaults.standard.bool(forKey: PrintSettingKey.headerAndFooter)
			headerCheckbox?.state = defaultFlag ? .on : .off
			dict[headerKey] = NSNumber(value: defaultFlag)
		}
	}

	// MARK: - Actions

	@objc private func themeChanged(_: NSPopUpButton) {
		guard let info = printInfo else { return }
		let idx = themesPopUp.indexOfSelectedItem
		guard idx >= 0, idx < availableThemes.count else { return }

		let uuid = availableThemes[idx].uuid
		info.dictionary()[PrintSettingKey.themeUUID] = uuid
		UserDefaults.standard.set(uuid, forKey: PrintSettingKey.themeUUID)
		willChangeValue(forKey: "themeIndex")
		didChangeValue(forKey: "themeIndex")
	}

	@objc private func fontSizeChanged(_: NSPopUpButton) {
		guard let info = printInfo, let title = fontSizesPopUp.titleOfSelectedItem,
		      let size = Int(title)
		else { return }

		let number = NSNumber(value: size)
		info.dictionary()[PrintSettingKey.fontSize] = number
		UserDefaults.standard.set(number, forKey: PrintSettingKey.fontSize)
		willChangeValue(forKey: "printFontSize")
		didChangeValue(forKey: "printFontSize")
	}

	@objc private func headerCheckboxChanged(_ sender: NSButton) {
		guard let info = printInfo else { return }
		let flag = sender.state == .on
		info.dictionary()["NSPrintHeaderAndFooter"] = NSNumber(value: flag)
		UserDefaults.standard.set(flag, forKey: PrintSettingKey.headerAndFooter)
		willChangeValue(forKey: "printHeaderAndFooter")
		didChangeValue(forKey: "printHeaderAndFooter")
	}

	// MARK: - UI Helpers

	private func makeLabel(_ text: String) -> NSTextField {
		let label = NSTextField(labelWithString: text)
		label.translatesAutoresizingMaskIntoConstraints = false
		label.alignment = .right
		return label
	}

	private func rebuildThemesMenu() {
		let menu = NSMenu()
		if availableThemes.isEmpty {
			let item = NSMenuItem(title: "No Themes Loaded", action: nil, keyEquivalent: "")
			item.isEnabled = false
			menu.addItem(item)
		} else {
			for entry in availableThemes {
				menu.addItem(NSMenuItem(
					title: entry.name,
					action: nil,
					keyEquivalent: "",
				))
			}
		}
		themesPopUp?.menu = menu
	}

	private func rebuildFontSizeMenu() {
		let menu = NSMenu()
		for size in 4 ... 22 {
			menu.addItem(NSMenuItem(
				title: "\(size)",
				action: nil,
				keyEquivalent: "",
			))
		}
		fontSizesPopUp?.menu = menu
	}

	// MARK: - Title

	override public var title: String? {
		get { "TextMate" }
		set { _ = newValue }
	}
}
