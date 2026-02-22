#if canImport(AppKit)
import AppKit

/// Custom table cell view for file chooser items.
///
/// Two-line layout: icon + filename (top, truncated tail) + folder path (bottom, truncated head).
/// Match ranges are highlighted with background color and underline.
@MainActor
public class FileChooserCellView: NSTableCellView {
	private let nameLabel = NSTextField(labelWithString: "")
	private let pathLabel = NSTextField(labelWithString: "")
	private let iconView = NSImageView()
	private let closeButton = NSButton()

	/// Whether to show a close button (for open documents source).
	public var showCloseButton: Bool = false {
		didSet {
			closeButton.isHidden = !showCloseButton
		}
	}

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setupUI()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	private func setupUI() {
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyDown
		addSubview(iconView)

		nameLabel.translatesAutoresizingMaskIntoConstraints = false
		nameLabel.font = .systemFont(ofSize: 13)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.cell?.truncatesLastVisibleLine = true
		addSubview(nameLabel)

		pathLabel.translatesAutoresizingMaskIntoConstraints = false
		pathLabel.font = .systemFont(ofSize: 10)
		pathLabel.textColor = .secondaryLabelColor
		pathLabel.lineBreakMode = .byTruncatingHead
		addSubview(pathLabel)

		closeButton.translatesAutoresizingMaskIntoConstraints = false
		closeButton.bezelStyle = .inline
		closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
		closeButton.isBordered = false
		closeButton.target = self
		closeButton.action = #selector(closeClicked)
		closeButton.isHidden = true
		addSubview(closeButton)

		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 16),
			iconView.heightAnchor.constraint(equalToConstant: 16),

			nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
			nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
			nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

			pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
			pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 0),
			pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

			closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
			closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			closeButton.widthAnchor.constraint(equalToConstant: 16),
			closeButton.heightAnchor.constraint(equalToConstant: 16),
		])
	}

	/// Configure the cell with a file chooser item.
	public func configure(with item: FileChooserItem) {
		// File icon from workspace
		let url = URL(fileURLWithPath: item.path)
		iconView.image = NSWorkspace.shared.icon(forFile: url.path)

		// Name with highlight
		if !item.nameCoverRanges.isEmpty {
			nameLabel.attributedStringValue = MatchHighlighter.attributedString(
				for: item.fileName,
				coverRanges: item.nameCoverRanges,
				lineBreakMode: .byTruncatingTail,
			)
		} else {
			nameLabel.stringValue = item.fileName
		}

		// Path with highlight
		if !item.detailCoverRanges.isEmpty {
			pathLabel.attributedStringValue = MatchHighlighter.attributedString(
				for: item.directory,
				coverRanges: item.detailCoverRanges,
				lineBreakMode: .byTruncatingHead,
			)
		} else {
			pathLabel.stringValue = item.directory
		}
	}

	@objc private func closeClicked() {}
}

/// Custom table cell view for bundle item chooser items.
///
/// Single-line layout: name + key equivalent/tab trigger on the right.
/// Eclipsed items shown with strikethrough.
@MainActor
public class BundleItemCellView: NSTableCellView {
	private let nameLabel = NSTextField(labelWithString: "")
	private let rightLabel = NSTextField(labelWithString: "")

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setupUI()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	private func setupUI() {
		nameLabel.translatesAutoresizingMaskIntoConstraints = false
		nameLabel.font = .systemFont(ofSize: 13)
		nameLabel.lineBreakMode = .byTruncatingTail
		addSubview(nameLabel)

		rightLabel.translatesAutoresizingMaskIntoConstraints = false
		rightLabel.font = .systemFont(ofSize: 11)
		rightLabel.textColor = .secondaryLabelColor
		rightLabel.alignment = .right
		rightLabel.lineBreakMode = .byTruncatingTail
		addSubview(rightLabel)

		NSLayoutConstraint.activate([
			nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightLabel.leadingAnchor, constant: -8),

			rightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			rightLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			rightLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
		])
	}

	/// Configure the cell with a bundle chooser item.
	public func configure(with item: BundleChooserItem) {
		// Name with highlight
		if !item.nameCoverRanges.isEmpty {
			let attributed = MatchHighlighter.attributedString(
				for: item.name,
				coverRanges: item.nameCoverRanges,
				lineBreakMode: .byTruncatingTail,
			)
			if item.isEclipsed {
				attributed.addAttribute(
					.strikethroughStyle,
					value: NSUnderlineStyle.single.rawValue,
					range: NSRange(location: 0, length: attributed.length),
				)
			}
			nameLabel.attributedStringValue = attributed
		} else {
			nameLabel.stringValue = item.name
			if item.isEclipsed {
				let attributed = NSMutableAttributedString(string: item.name)
				attributed.addAttribute(
					.strikethroughStyle,
					value: NSUnderlineStyle.single.rawValue,
					range: NSRange(location: 0, length: attributed.length),
				)
				nameLabel.attributedStringValue = attributed
			}
		}

		// Right label: tab trigger or key equivalent
		if let trigger = item.tabTrigger, !trigger.isEmpty {
			rightLabel.stringValue = trigger + "⇥"
		} else if let keyEq = item.keyEquivalent, !keyEq.isEmpty {
			rightLabel.stringValue = keyEq
		} else {
			rightLabel.stringValue = ""
		}
	}
}

#endif
