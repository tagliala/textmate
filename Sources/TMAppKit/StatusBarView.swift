import AppKit

/// Status bar view displayed at the bottom of the editor window.
///
/// Shows: line/column, grammar name, tab settings, encoding, and theme indicator.
/// Click grammar label → grammar chooser, tab size → picker, encoding → picker.
/// Uses system appearance colors — follows light/dark mode automatically.
@MainActor
public class StatusBarView: NSView {
	private let lineColumnLabel = NSTextField(
		labelWithString: String(localized: "Line 1, Column 1", comment: "Status bar: initial line/column"),
	)
	private let grammarButton = StatusBarButton(
		title: String(localized: "Plain Text", comment: "Status bar: default grammar"),
	)
	private let tabSettingsButton = StatusBarButton(
		title: String(localized: "Spaces: 3", comment: "Status bar: default tab settings"),
	)
	private let encodingButton = StatusBarButton(title: "UTF-8")

	/// Delegate that handles status bar interactions.
	public weak var delegate: StatusBarViewDelegate?

	public var statusBarHeight: CGFloat = 22

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

	// MARK: - Public API

	public func setLineColumn(line: Int, column: Int) {
		lineColumnLabel.stringValue = String(
			localized: "Line \(line), Column \(column)",
			comment: "Status bar: current line and column",
		)
	}

	public func setGrammar(_ name: String) {
		grammarButton.title = name
	}

	public func setTabSettings(useSoftTabs: Bool, tabSize: Int) {
		if useSoftTabs {
			tabSettingsButton.title = String(
				localized: "Spaces: \(tabSize)",
				comment: "Status bar: soft tab size",
			)
		} else {
			tabSettingsButton.title = String(
				localized: "Tab Size: \(tabSize)",
				comment: "Status bar: hard tab size",
			)
		}
	}

	public func setEncoding(_ encoding: String) {
		encodingButton.title = encoding
	}

	// MARK: - Private

	private func setupViews() {
		wantsLayer = true

		lineColumnLabel.font = .systemFont(ofSize: 11)
		lineColumnLabel.lineBreakMode = .byTruncatingTail
		lineColumnLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(lineColumnLabel)

		for button in [grammarButton, tabSettingsButton, encodingButton] {
			button.translatesAutoresizingMaskIntoConstraints = false
			addSubview(button)
		}

		grammarButton.clickAction = { [weak self] in self?.showGrammarMenu() }
		tabSettingsButton.clickAction = { [weak self] in self?.showTabSettingsMenu() }
		encodingButton.clickAction = { [weak self] in self?.showEncodingMenu() }

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: statusBarHeight),

			lineColumnLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			lineColumnLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

			grammarButton.centerXAnchor.constraint(equalTo: centerXAnchor),
			grammarButton.centerYAnchor.constraint(equalTo: centerYAnchor),

			tabSettingsButton.trailingAnchor.constraint(equalTo: encodingButton.leadingAnchor, constant: -16),
			tabSettingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),

			encodingButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			encodingButton.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	// MARK: - Popup Menus

	private func showGrammarMenu() {
		let menu = NSMenu()
		let grammars = [
			"Plain Text", "C", "C++", "CSS", "HTML", "Java", "JavaScript",
			"JSON", "Markdown", "Objective-C", "Objective-C++", "Python",
			"Ruby", "Rust", "Shell Script", "SQL", "Swift", "XML", "YAML",
		]
		for name in grammars {
			let item = NSMenuItem(title: name, action: #selector(grammarSelected(_:)), keyEquivalent: "")
			item.target = self
			if name == grammarButton.title {
				item.state = .on
			}
			menu.addItem(item)
		}
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: grammarButton.bounds.height),
			in: grammarButton,
		)
	}

	@objc private func grammarSelected(_ sender: NSMenuItem) {
		grammarButton.title = sender.title
		delegate?.statusBarView(self, didSelectGrammar: sender.title)
	}

	private func showTabSettingsMenu() {
		let menu = NSMenu()
		// Soft tabs section
		for size in [2, 3, 4, 8] {
			let title = String(localized: "Spaces: \(size)", comment: "Tab settings menu item")
			let item = NSMenuItem(title: title, action: #selector(tabSettingSelected(_:)), keyEquivalent: "")
			item.target = self
			item.tag = size // positive = soft tabs
			if tabSettingsButton.title == title { item.state = .on }
			menu.addItem(item)
		}
		menu.addItem(.separator())
		// Hard tabs section
		for size in [2, 3, 4, 8] {
			let title = String(localized: "Tab Size: \(size)", comment: "Tab settings menu item")
			let item = NSMenuItem(title: title, action: #selector(tabSettingSelected(_:)), keyEquivalent: "")
			item.target = self
			item.tag = -size // negative = hard tabs
			if tabSettingsButton.title == title { item.state = .on }
			menu.addItem(item)
		}
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: tabSettingsButton.bounds.height),
			in: tabSettingsButton,
		)
	}

	@objc private func tabSettingSelected(_ sender: NSMenuItem) {
		let tag = sender.tag
		let useSoftTabs = tag > 0
		let size = abs(tag)
		setTabSettings(useSoftTabs: useSoftTabs, tabSize: size)
		delegate?.statusBarView(self, didSelectTabSettings: useSoftTabs, tabSize: size)
	}

	private func showEncodingMenu() {
		let menu = NSMenu()
		let encodings = [
			"UTF-8", "UTF-16", "UTF-16 BE", "UTF-16 LE", "UTF-32",
			"ASCII", "ISO Latin 1", "Mac Roman", "Windows 1252",
			"EUC-JP", "Shift JIS",
		]
		for name in encodings {
			let item = NSMenuItem(title: name, action: #selector(encodingSelected(_:)), keyEquivalent: "")
			item.target = self
			if name == encodingButton.title { item.state = .on }
			menu.addItem(item)
		}
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: encodingButton.bounds.height),
			in: encodingButton,
		)
	}

	@objc private func encodingSelected(_ sender: NSMenuItem) {
		encodingButton.title = sender.title
		delegate?.statusBarView(self, didSelectEncoding: sender.title)
	}
}

/// Delegate for status bar interactions.
@MainActor
public protocol StatusBarViewDelegate: AnyObject {
	func statusBarView(_ view: StatusBarView, didSelectGrammar grammar: String)
	func statusBarView(_ view: StatusBarView, didSelectTabSettings useSoftTabs: Bool, tabSize: Int)
	func statusBarView(_ view: StatusBarView, didSelectEncoding encoding: String)
}

/// Default no-op implementations.
public extension StatusBarViewDelegate {
	func statusBarView(_: StatusBarView, didSelectGrammar _: String) {}
	func statusBarView(_: StatusBarView, didSelectTabSettings _: Bool, tabSize _: Int) {}
	func statusBarView(_: StatusBarView, didSelectEncoding _: String) {}
}

// MARK: - StatusBarButton

/// A clickable label that acts as a button in the status bar.
@MainActor
private class StatusBarButton: NSView {
	private let label = NSTextField(labelWithString: "")
	var clickAction: (() -> Void)?

	var title: String {
		get { label.stringValue }
		set { label.stringValue = newValue }
	}

	init(title: String) {
		super.init(frame: .zero)
		label.stringValue = title
		label.font = .systemFont(ofSize: 11)
		label.lineBreakMode = .byTruncatingTail
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor),
			label.trailingAnchor.constraint(equalTo: trailingAnchor),
			label.topAnchor.constraint(equalTo: topAnchor),
			label.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		// Add tracking area for hover effect
		let trackingArea = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
			owner: self,
		)
		addTrackingArea(trackingArea)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	override func mouseDown(with _: NSEvent) {
		clickAction?()
	}

	override func mouseEntered(with _: NSEvent) {
		label.textColor = .controlAccentColor
		NSCursor.pointingHand.push()
	}

	override func mouseExited(with _: NSEvent) {
		label.textColor = .secondaryLabelColor
		NSCursor.pop()
	}

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: .pointingHand)
	}
}
