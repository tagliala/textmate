import AppKit

/// Status bar view displayed at the bottom of the editor window.
///
/// Port of C++ `OTVStatusBar` from `Frameworks/OakTextView/src/OTVStatusBar.mm`.
///
/// Shows: selection info, grammar name, tab settings, symbol navigator,
/// bundle items action button, and macro recording indicator.
/// Click grammar → grammar chooser, tab size → picker, symbol → symbol list.
/// Uses system appearance colors — follows light/dark mode automatically.
@MainActor
public class StatusBarView: NSView {
	// MARK: - UI Elements

	private let selectionField = NSTextField(labelWithString: "1:1")
	private let grammarPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
	private let tabSizePopUp = NSPopUpButton(frame: .zero, pullsDown: true)
	private let symbolPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
	private let bundleItemsPopUp = NSPopUpButton(frame: .zero, pullsDown: true)
	private let encodingPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
	private let lineEndingPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
	private let macroRecordingButton: NSButton = {
		let button = NSButton()
		button.setButtonType(.toggle)
		button.isBordered = false
		button.imagePosition = .imageOnly
		button.toolTip = "Click to start recording a macro"
		button.setAccessibilityLabel("Record a macro")

		// Draw a red circle for the macro recording indicator.
		let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
			NSColor.systemRed.set()
			NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
			return true
		}
		button.image = image
		return button
	}()

	/// Dividers between status bar sections.
	private var dividers: [NSBox] = []

	/// Delegate that handles status bar interactions.
	public weak var delegate: StatusBarViewDelegate?

	/// The height of the status bar in points.
	public var statusBarHeight: CGFloat = 24

	// MARK: - Macro Recording

	/// Timer for the pulsing macro recording animation.
	private nonisolated(unsafe) var recordingTimer: Timer? {
		willSet { recordingTimer?.invalidate() }
	}

	/// Elapsed time counter for the recording animation.
	private var recordingTime: CGFloat = 0

	/// Whether a macro is currently being recorded.
	public var isRecordingMacro: Bool = false {
		didSet {
			guard oldValue != isRecordingMacro else { return }
			if isRecordingMacro {
				recordingTimer = Timer.scheduledTimer(
					withTimeInterval: 0.02,
					repeats: true,
				) { [weak self] _ in
					MainActor.assumeIsolated {
						self?.updateRecordingAnimation()
					}
				}
			} else {
				recordingTimer = nil
				recordingTime = 0
				macroRecordingButton.alphaValue = 1
			}
		}
	}

	// MARK: - Init

	override public var isFlipped: Bool {
		true
	}

	override public init(frame: NSRect) {
		super.init(frame: frame)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	deinit {
		recordingTimer?.invalidate()
	}

	// MARK: - Public API

	/// The current selection string displayed in the status bar.
	public var selectionStringValue: String {
		selectionField.stringValue
	}

	/// The current grammar title displayed in the grammar popup.
	public var grammarTitle: String {
		grammarPopUp.title
	}

	/// The current tab settings title displayed in the tab size popup.
	public var tabSettingsTitle: String {
		tabSizePopUp.title
	}

	/// The current symbol title displayed in the symbol popup.
	public var symbolTitle: String {
		symbolPopUp.title
	}

	/// The current encoding title displayed in the encoding popup.
	public var encodingTitle: String {
		encodingPopUp.title
	}

	/// The current line ending title displayed in the line ending popup.
	public var lineEndingTitle: String {
		lineEndingPopUp.title
	}

	/// Update the selection display string.
	///
	/// Formats multi-cursor selections: `&` → `, `, `x` → `×`.
	/// Uses monospaced number font to prevent jitter.
	public func setSelectionString(_ string: String) {
		var formatted = string
			.replacingOccurrences(of: "&", with: ", ")
			.replacingOccurrences(of: "x", with: "×")
		if formatted.isEmpty { formatted = "1:1" }
		selectionField.stringValue = formatted
	}

	/// Convenience: set line/column display.
	public func setLineColumn(line: Int, column: Int) {
		selectionField.stringValue = "\(line):\(column)"
	}

	/// Set the grammar name shown in the grammar popup.
	public func setGrammar(_ name: String) {
		grammarPopUp.removeAllItems()
		grammarPopUp.addItem(withTitle: name.isEmpty ? "(no grammar)" : name)
	}

	/// Set the symbol name shown in the symbol popup.
	public func setSymbolName(_ name: String?) {
		symbolPopUp.removeAllItems()
		symbolPopUp.addItem(withTitle: name ?? "Symbols")
	}

	/// Update tab settings display.
	public func setTabSettings(useSoftTabs: Bool, tabSize: Int) {
		tabSizePopUp.setTitle(
			useSoftTabs ? "Soft Tabs:\u{2003}\(tabSize)" : "Tab Size:\u{2003}\(tabSize)",
		)
	}

	/// Set the encoding display by selecting the matching charset in the popup.
	public func setEncoding(_ encoding: String) {
		for (index, item) in (encodingPopUp.menu?.items ?? []).enumerated() {
			if (item.representedObject as? String) == encoding {
				encodingPopUp.selectItem(at: index)
				return
			}
		}
		// Unknown encoding — add it as a custom item and select.
		let item = NSMenuItem(title: encoding, action: nil, keyEquivalent: "")
		item.representedObject = encoding
		encodingPopUp.menu?.addItem(item)
		encodingPopUp.select(item)
	}

	/// Set the line ending display by selecting the matching title.
	public func setLineEnding(_ lineEnding: String) {
		for (index, item) in (lineEndingPopUp.menu?.items ?? []).enumerated() {
			if item.title == lineEnding {
				lineEndingPopUp.selectItem(at: index)
				return
			}
		}
	}

	// MARK: - Private Setup

	private func setupViews() {
		wantsLayer = true

		let statusFont = NSFont.systemFont(ofSize: 11)

		// Selection field — monospaced numbers to avoid jitter.
		selectionField.font = monospacedNumberFont(base: statusFont)
		selectionField.lineBreakMode = .byTruncatingTail
		selectionField.textColor = .secondaryLabelColor
		selectionField.translatesAutoresizingMaskIntoConstraints = false
		addSubview(selectionField)

		// Grammar popup
		configurePopUp(grammarPopUp, font: statusFont, title: "Plain Text", label: "Grammar")
		grammarPopUp.translatesAutoresizingMaskIntoConstraints = false
		addSubview(grammarPopUp)

		// Tab size popup (pulls down)
		configurePopUp(tabSizePopUp, font: statusFont, title: "Spaces:\u{2003}3", label: "Tab Size")
		tabSizePopUp.pullsDown = true
		tabSizePopUp.translatesAutoresizingMaskIntoConstraints = false
		addSubview(tabSizePopUp)
		rebuildTabSizeMenu()

		// Encoding popup
		configurePopUp(encodingPopUp, font: statusFont, title: "UTF-8", label: "Encoding")
		encodingPopUp.translatesAutoresizingMaskIntoConstraints = false
		encodingPopUp.target = self
		encodingPopUp.action = #selector(encodingSelected(_:))
		addSubview(encodingPopUp)
		rebuildEncodingMenu()

		// Line ending popup
		configurePopUp(lineEndingPopUp, font: statusFont, title: "LF", label: "Line Ending")
		lineEndingPopUp.translatesAutoresizingMaskIntoConstraints = false
		lineEndingPopUp.target = self
		lineEndingPopUp.action = #selector(lineEndingSelected(_:))
		addSubview(lineEndingPopUp)
		rebuildLineEndingMenu()

		// Symbol popup
		configurePopUp(symbolPopUp, font: statusFont, title: "Symbols", label: "Symbol")
		symbolPopUp.translatesAutoresizingMaskIntoConstraints = false
		addSubview(symbolPopUp)

		// Bundle items popup (action gear)
		bundleItemsPopUp.font = statusFont
		bundleItemsPopUp.isBordered = false
		bundleItemsPopUp.pullsDown = true
		bundleItemsPopUp.translatesAutoresizingMaskIntoConstraints = false
		bundleItemsPopUp.setAccessibilityLabel("Bundle Item")
		let gearItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
		gearItem.image = NSImage(named: NSImage.actionTemplateName)
		(bundleItemsPopUp.cell as? NSPopUpButtonCell)?.usesItemFromMenu = false
		(bundleItemsPopUp.cell as? NSPopUpButtonCell)?.menuItem = gearItem
		addSubview(bundleItemsPopUp)

		// Macro recording button
		macroRecordingButton.translatesAutoresizingMaskIntoConstraints = false
		macroRecordingButton.target = self
		macroRecordingButton.action = #selector(toggleMacroRecordingAction(_:))
		addSubview(macroRecordingButton)

		// Create dividers
		for _ in 0 ..< 7 {
			let divider = NSBox()
			divider.boxType = .separator
			divider.translatesAutoresizingMaskIntoConstraints = false
			addSubview(divider)
			dividers.append(divider)
		}

		// Register for popup notifications
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(grammarPopUpWillOpen(_:)),
			name: NSPopUpButton.willPopUpNotification,
			object: grammarPopUp,
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(symbolPopUpWillOpen(_:)),
			name: NSPopUpButton.willPopUpNotification,
			object: symbolPopUp,
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(bundleItemsPopUpWillOpen(_:)),
			name: NSPopUpButton.willPopUpNotification,
			object: bundleItemsPopUp,
		)

		setupConstraints()
	}

	private func setupConstraints() {
		let d = dividers
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: statusBarHeight),

			// Selection field
			selectionField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
			selectionField.centerYAnchor.constraint(equalTo: centerYAnchor),
			selectionField.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
			selectionField.widthAnchor.constraint(lessThanOrEqualToConstant: 225),

			// Divider 1
			d[0].leadingAnchor.constraint(equalTo: selectionField.trailingAnchor, constant: 8),
			d[0].centerYAnchor.constraint(equalTo: centerYAnchor),
			d[0].widthAnchor.constraint(equalToConstant: 1),
			d[0].heightAnchor.constraint(equalToConstant: 15),

			// Grammar popup
			grammarPopUp.leadingAnchor.constraint(equalTo: d[0].trailingAnchor, constant: 2),
			grammarPopUp.centerYAnchor.constraint(equalTo: centerYAnchor),
			grammarPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
			grammarPopUp.widthAnchor.constraint(lessThanOrEqualToConstant: 225),

			// Divider 2
			d[1].leadingAnchor.constraint(equalTo: grammarPopUp.trailingAnchor, constant: 5),
			d[1].centerYAnchor.constraint(equalTo: centerYAnchor),
			d[1].widthAnchor.constraint(equalToConstant: 1),
			d[1].heightAnchor.constraint(equalToConstant: 15),

			// Tab size popup
			tabSizePopUp.leadingAnchor.constraint(equalTo: d[1].trailingAnchor, constant: 2),
			tabSizePopUp.centerYAnchor.constraint(equalTo: centerYAnchor),

			// Divider 3
			d[2].leadingAnchor.constraint(equalTo: tabSizePopUp.trailingAnchor, constant: 4),
			d[2].centerYAnchor.constraint(equalTo: centerYAnchor),
			d[2].widthAnchor.constraint(equalToConstant: 1),
			d[2].heightAnchor.constraint(equalToConstant: 15),

			// Encoding popup
			encodingPopUp.leadingAnchor.constraint(equalTo: d[2].trailingAnchor, constant: 2),
			encodingPopUp.centerYAnchor.constraint(equalTo: centerYAnchor),

			// Divider 4
			d[3].leadingAnchor.constraint(equalTo: encodingPopUp.trailingAnchor, constant: 4),
			d[3].centerYAnchor.constraint(equalTo: centerYAnchor),
			d[3].widthAnchor.constraint(equalToConstant: 1),
			d[3].heightAnchor.constraint(equalToConstant: 15),

			// Line ending popup
			lineEndingPopUp.leadingAnchor.constraint(equalTo: d[3].trailingAnchor, constant: 2),
			lineEndingPopUp.centerYAnchor.constraint(equalTo: centerYAnchor),

			// Divider 5
			d[4].leadingAnchor.constraint(equalTo: lineEndingPopUp.trailingAnchor, constant: 4),
			d[4].centerYAnchor.constraint(equalTo: centerYAnchor),
			d[4].widthAnchor.constraint(equalToConstant: 1),
			d[4].heightAnchor.constraint(equalToConstant: 15),

			// Bundle items popup (action gear)
			bundleItemsPopUp.leadingAnchor.constraint(equalTo: d[4].trailingAnchor, constant: 5),
			bundleItemsPopUp.centerYAnchor.constraint(equalTo: centerYAnchor),
			bundleItemsPopUp.widthAnchor.constraint(equalToConstant: 31),

			// Divider 6
			d[5].leadingAnchor.constraint(equalTo: bundleItemsPopUp.trailingAnchor, constant: 4),
			d[5].centerYAnchor.constraint(equalTo: centerYAnchor),
			d[5].widthAnchor.constraint(equalToConstant: 1),
			d[5].heightAnchor.constraint(equalToConstant: 15),

			// Symbol popup
			symbolPopUp.leadingAnchor.constraint(equalTo: d[5].trailingAnchor, constant: 2),
			symbolPopUp.centerYAnchor.constraint(equalTo: centerYAnchor),
			symbolPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),

			// Divider 7
			d[6].leadingAnchor.constraint(equalTo: symbolPopUp.trailingAnchor, constant: 5),
			d[6].centerYAnchor.constraint(equalTo: centerYAnchor),
			d[6].widthAnchor.constraint(equalToConstant: 1),
			d[6].heightAnchor.constraint(equalToConstant: 15),

			// Macro recording button
			macroRecordingButton.leadingAnchor.constraint(equalTo: d[6].trailingAnchor, constant: 6),
			macroRecordingButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
			macroRecordingButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			macroRecordingButton.widthAnchor.constraint(equalToConstant: 16),
			macroRecordingButton.heightAnchor.constraint(equalToConstant: 16),
		])

		// Content hugging priorities (match C++ layout)
		selectionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		selectionField.setContentCompressionResistancePriority(.defaultLow + 2, for: .horizontal)
		grammarPopUp.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
		symbolPopUp.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
		symbolPopUp.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
	}

	// MARK: - Tab Size Menu

	/// Rebuild the tab size popup menu matching the C++ layout:
	/// Indent Size header, 2/3/4/8/Other, separator, Tabs/Spaces toggle.
	private func rebuildTabSizeMenu() {
		let menu = NSMenu()

		// Header: current indent display
		let titleItem = NSMenuItem(title: tabSizePopUp.title, action: nil, keyEquivalent: "")
		menu.addItem(titleItem)

		// Indent Size header
		let header = NSMenuItem(title: "Indent Size", action: nil, keyEquivalent: "")
		header.isEnabled = false
		menu.addItem(header)

		// Size options
		for size in [2, 3, 4, 8] {
			let item = NSMenuItem(
				title: "\(size)",
				action: #selector(tabSizeSelected(_:)),
				keyEquivalent: "",
			)
			item.target = self
			item.tag = size
			item.indentationLevel = 1
			menu.addItem(item)
		}

		// Other...
		let other = NSMenuItem(
			title: "Other…",
			action: #selector(showCustomTabSizePanel(_:)),
			keyEquivalent: "",
		)
		other.target = self
		other.indentationLevel = 1
		menu.addItem(other)

		menu.addItem(.separator())

		// Indent Using header
		let indentHeader = NSMenuItem(title: "Indent Using", action: nil, keyEquivalent: "")
		indentHeader.isEnabled = false
		menu.addItem(indentHeader)

		// Tabs
		let tabs = NSMenuItem(
			title: "Tabs",
			action: #selector(setIndentWithTabs(_:)),
			keyEquivalent: "",
		)
		tabs.target = self
		tabs.indentationLevel = 1
		menu.addItem(tabs)

		// Spaces
		let spaces = NSMenuItem(
			title: "Spaces",
			action: #selector(setIndentWithSpaces(_:)),
			keyEquivalent: "",
		)
		spaces.target = self
		spaces.indentationLevel = 1
		menu.addItem(spaces)

		tabSizePopUp.menu = menu
	}

	// MARK: - Actions

	@objc private func tabSizeSelected(_ sender: NSMenuItem) {
		let size = sender.tag
		guard size > 0 else { return }
		delegate?.statusBarView(self, didSelectTabSize: size)
	}

	@objc private func showCustomTabSizePanel(_: NSMenuItem) {
		let alert = NSAlert()
		alert.messageText = "Custom Tab Size"
		alert.informativeText = "Enter a tab/indent size:"
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")

		let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
		input.stringValue = "4"
		input.placeholderString = "Size"
		alert.accessoryView = input

		let response = alert.runModal()
		if response == .alertFirstButtonReturn {
			if let size = Int(input.stringValue), size > 0 {
				delegate?.statusBarView(self, didSelectTabSize: size)
			}
		}
	}

	@objc private func setIndentWithTabs(_: NSMenuItem) {
		delegate?.statusBarView(self, didSelectUseSoftTabs: false)
	}

	@objc private func setIndentWithSpaces(_: NSMenuItem) {
		delegate?.statusBarView(self, didSelectUseSoftTabs: true)
	}

	@objc private func toggleMacroRecordingAction(_: NSButton) {
		delegate?.statusBarViewDidToggleMacroRecording(self)
	}

	@objc private func grammarPopUpWillOpen(_: Notification) {
		delegate?.statusBarViewWillShowGrammarMenu(self, popup: grammarPopUp)
	}

	@objc private func symbolPopUpWillOpen(_: Notification) {
		delegate?.statusBarViewWillShowSymbolMenu(self, popup: symbolPopUp)
	}

	@objc private func bundleItemsPopUpWillOpen(_: Notification) {
		delegate?.statusBarViewWillShowBundleItemsMenu(self, popup: bundleItemsPopUp)
	}

	@objc private func encodingSelected(_: NSPopUpButton) {
		guard let charset = encodingPopUp.selectedItem?.representedObject as? String else { return }
		delegate?.statusBarView(self, didSelectEncoding: charset)
	}

	@objc private func lineEndingSelected(_: NSPopUpButton) {
		guard let ending = lineEndingPopUp.selectedItem?.title else { return }
		delegate?.statusBarView(self, didSelectLineEnding: ending)
	}

	// MARK: - Encoding & Line Ending Menus

	/// Common IANA charset names for the encoding popup.
	private static let commonCharsets: [(display: String, charset: String)] = [
		("UTF-8", "UTF-8"),
		("UTF-16 BE", "UTF-16BE"),
		("UTF-16 LE", "UTF-16LE"),
		("ISO 8859-1", "ISO-8859-1"),
		("Mac Roman", "macintosh"),
		("Shift JIS", "Shift_JIS"),
		("Windows 1252", "windows-1252"),
	]

	private func rebuildEncodingMenu() {
		let menu = NSMenu()
		for (display, charset) in Self.commonCharsets {
			let item = NSMenuItem(title: display, action: nil, keyEquivalent: "")
			item.representedObject = charset
			menu.addItem(item)
		}
		encodingPopUp.menu = menu
		encodingPopUp.selectItem(at: 0)
	}

	private func rebuildLineEndingMenu() {
		let menu = NSMenu()
		for title in ["LF", "CR", "CR/LF"] {
			menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
		}
		lineEndingPopUp.menu = menu
		lineEndingPopUp.selectItem(at: 0)
	}

	// MARK: - Recording Animation

	/// Updates the macro recording button pulse.
	///
	/// Matches C++ animation: `0.70 + 0.30 * cos(π + t)`, period ~0.02s.
	private func updateRecordingAnimation() {
		let fraction = 0.70 + 0.30 * cos(.pi + recordingTime)
		macroRecordingButton.alphaValue = max(0, min(1, fraction))
		recordingTime += 0.075
	}

	// MARK: - Helpers

	private func configurePopUp(
		_ popUp: NSPopUpButton,
		font: NSFont,
		title: String,
		label: String,
	) {
		popUp.font = font
		popUp.isBordered = false
		popUp.addItem(withTitle: title)
		popUp.setAccessibilityLabel(label)
	}

	/// Creates a font with monospaced number spacing to prevent jitter
	/// when the selection string changes.
	private func monospacedNumberFont(base: NSFont) -> NSFont {
		let descriptor = base.fontDescriptor.addingAttributes([
			.featureSettings: [[
				NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
				NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
			]],
		])
		return NSFont(descriptor: descriptor, size: 0) ?? base
	}
}

// MARK: - StatusBarViewDelegate

/// Delegate for status bar interactions.
///
/// Port of the C++ `OTVStatusBar` delegate protocol and target-action
/// pattern from `Frameworks/OakTextView/src/OTVStatusBar.mm`.
@MainActor
public protocol StatusBarViewDelegate: AnyObject {
	/// Called when the user selects a grammar from the grammar popup.
	func statusBarView(_ view: StatusBarView, didSelectGrammar grammar: String)

	/// Called when the user selects a tab size.
	func statusBarView(_ view: StatusBarView, didSelectTabSize size: Int)

	/// Called when the user toggles between tabs and spaces.
	func statusBarView(_ view: StatusBarView, didSelectUseSoftTabs useSoftTabs: Bool)

	/// Called when the user selects a tab size (legacy — calls through to didSelectTabSize + didSelectUseSoftTabs).
	func statusBarView(_ view: StatusBarView, didSelectTabSettings useSoftTabs: Bool, tabSize: Int)

	/// Called when the user selects an encoding.
	func statusBarView(_ view: StatusBarView, didSelectEncoding encoding: String)

	/// Called when the user selects a line ending.
	func statusBarView(_ view: StatusBarView, didSelectLineEnding lineEnding: String)

	/// Called when the grammar popup is about to open.
	/// The delegate should populate the popup's menu with grammar items.
	func statusBarViewWillShowGrammarMenu(_ view: StatusBarView, popup: NSPopUpButton)

	/// Called when the symbol popup is about to open.
	/// The delegate should populate the popup's menu with symbol items.
	func statusBarViewWillShowSymbolMenu(_ view: StatusBarView, popup: NSPopUpButton)

	/// Called when the bundle items popup is about to open.
	/// The delegate should populate the popup's menu with bundle action items.
	func statusBarViewWillShowBundleItemsMenu(_ view: StatusBarView, popup: NSPopUpButton)

	/// Called when the user clicks the macro recording button.
	func statusBarViewDidToggleMacroRecording(_ view: StatusBarView)
}

/// Default no-op implementations.
public extension StatusBarViewDelegate {
	func statusBarView(_: StatusBarView, didSelectGrammar _: String) {}
	func statusBarView(_: StatusBarView, didSelectTabSize _: Int) {}
	func statusBarView(_: StatusBarView, didSelectUseSoftTabs _: Bool) {}
	func statusBarView(_: StatusBarView, didSelectTabSettings _: Bool, tabSize _: Int) {}
	func statusBarView(_: StatusBarView, didSelectEncoding _: String) {}
	func statusBarView(_: StatusBarView, didSelectLineEnding _: String) {}
	func statusBarViewWillShowGrammarMenu(_: StatusBarView, popup _: NSPopUpButton) {}
	func statusBarViewWillShowSymbolMenu(_: StatusBarView, popup _: NSPopUpButton) {}
	func statusBarViewWillShowBundleItemsMenu(_: StatusBarView, popup _: NSPopUpButton) {}
	func statusBarViewDidToggleMacroRecording(_: StatusBarView) {}
}
