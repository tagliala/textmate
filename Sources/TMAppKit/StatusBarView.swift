import AppKit

/// Status bar view displayed at the bottom of the editor window.
///
/// Shows: line/column, grammar name, tab settings, encoding, and theme indicator.
/// Uses system appearance colors — follows light/dark mode automatically.
@MainActor
public class StatusBarView: NSView {
	private let lineColumnLabel = NSTextField(
		labelWithString: String(localized: "Line 1, Column 1", comment: "Status bar: initial line/column"),
	)
	private let grammarLabel = NSTextField(
		labelWithString: String(localized: "Plain Text", comment: "Status bar: default grammar"),
	)
	private let tabSettingsLabel = NSTextField(
		labelWithString: String(localized: "Spaces: 3", comment: "Status bar: default tab settings"),
	)
	private let encodingLabel = NSTextField(labelWithString: "UTF-8")

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
		grammarLabel.stringValue = name
	}

	public func setTabSettings(useSoftTabs: Bool, tabSize: Int) {
		if useSoftTabs {
			tabSettingsLabel.stringValue = String(
				localized: "Spaces: \(tabSize)",
				comment: "Status bar: soft tab size",
			)
		} else {
			tabSettingsLabel.stringValue = String(
				localized: "Tab Size: \(tabSize)",
				comment: "Status bar: hard tab size",
			)
		}
	}

	public func setEncoding(_ encoding: String) {
		encodingLabel.stringValue = encoding
	}

	// MARK: - Private

	private func setupViews() {
		wantsLayer = true

		let labels = [lineColumnLabel, grammarLabel, tabSettingsLabel, encodingLabel]
		for label in labels {
			label.font = .systemFont(ofSize: 11)
			label.lineBreakMode = .byTruncatingTail
			label.translatesAutoresizingMaskIntoConstraints = false
			addSubview(label)
		}

		// Separator between each label region
		let spacer1 = makeSpacer()
		let spacer2 = makeSpacer()
		addSubview(spacer1)
		addSubview(spacer2)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: statusBarHeight),

			lineColumnLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			lineColumnLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

			grammarLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			grammarLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

			tabSettingsLabel.trailingAnchor.constraint(equalTo: encodingLabel.leadingAnchor, constant: -16),
			tabSettingsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

			encodingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			encodingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	private func makeSpacer() -> NSView {
		let view = NSView()
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}
}
