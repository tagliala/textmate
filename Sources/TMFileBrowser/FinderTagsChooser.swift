#if canImport(AppKit)
import AppKit

/// A view for choosing Finder tags from a grid of color swatches.
///
/// Port of `OFBFinderTagsChooser` from `OFB/OFBFinderTagsChooser.mm`.
/// Displays the system-defined Finder tag colors as clickable swatches,
/// with checkmarks for currently-applied tags and X marks for tags
/// pending removal.
@MainActor
public class FinderTagsChooser: NSView {
	/// The tag that was clicked by the user.
	public private(set) var chosenTag: FinderTag?

	/// Whether the chosen tag should be removed (true) or added (false).
	public private(set) var removeChosenTag: Bool = false

	/// Target-action pattern.
	public weak var target: AnyObject?

	/// Action to send when a tag is clicked.
	public var action: Selector?

	/// Currently assigned tags.
	private let selectedTags: Set<FinderTag>

	/// Tags that are marked for removal on next click.
	private let selectedTagsToRemove: Set<FinderTag>

	/// The favorite Finder tags from the system.
	private let favoriteTags: [FinderTag]

	/// Label showing the tag name on hover.
	private let tagLabel: NSTextField = {
		let tf = NSTextField(labelWithString: "Tags…")
		tf.font = .menuFont(ofSize: 0)
		tf.textColor = .disabledControlTextColor
		tf.translatesAutoresizingMaskIntoConstraints = false
		return tf
	}()

	/// The menu this chooser belongs to (for cancelling tracking).
	private weak var parentMenu: NSMenu?

	/// Creates a Finder tags chooser for use in a context menu.
	///
	/// - Parameters:
	///   - selectedTags: Tags currently applied to the file(s).
	///   - selectedTagsToRemove: Tags pending removal.
	///   - menu: The parent menu to cancel tracking after selection.
	/// - Returns: A configured `FinderTagsChooser` instance.
	public static func chooser(
		selectedTags: [FinderTag],
		selectedTagsToRemove: [FinderTag],
		forMenu menu: NSMenu,
	) -> FinderTagsChooser {
		FinderTagsChooser(
			selectedTags: Set(selectedTags),
			selectedTagsToRemove: Set(selectedTagsToRemove),
			menu: menu,
		)
	}

	private init(
		selectedTags: Set<FinderTag>,
		selectedTagsToRemove: Set<FinderTag>,
		menu: NSMenu,
	) {
		self.selectedTags = selectedTags
		self.selectedTagsToRemove = selectedTagsToRemove
		parentMenu = menu
		favoriteTags = FinderTag.favoriteTags
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Layout

	private static let swatchSize: CGFloat = 24

	override public var intrinsicContentSize: NSSize {
		NSSize(
			width: Self.swatchSize * CGFloat(favoriteTags.count + 1),
			height: Self.swatchSize + tagLabel.intrinsicContentSize.height,
		)
	}

	// MARK: - Setup

	private func setupViews() {
		addSubview(tagLabel)

		var buttons: [NSButton] = []
		for (index, tag) in favoriteTags.enumerated() {
			let isSelected = selectedTags.contains(tag)
			let isRemovable = selectedTagsToRemove.contains(tag)

			let button = NSButton(frame: NSRect(x: 0, y: 0, width: Self.swatchSize, height: Self.swatchSize))
			button.setButtonType(.momentaryChange)
			button.isBordered = false
			button.image = swatchImage(
				color: tag.labelColor,
				isSelected: isSelected,
				isRemovable: isRemovable,
				mouseOver: false,
			)
			button.alternateImage = swatchImage(
				color: tag.labelColor,
				isSelected: isSelected,
				isRemovable: isRemovable,
				mouseOver: true,
			)
			button.target = self
			button.action = #selector(didClickTag(_:))
			button.tag = index
			button.translatesAutoresizingMaskIntoConstraints = false
			button.setAccessibilityLabel("\(isRemovable ? "Remove" : "Add") \(tag.displayName) tag")

			NSLayoutConstraint.activate([
				button.widthAnchor.constraint(equalToConstant: Self.swatchSize),
				button.heightAnchor.constraint(equalToConstant: Self.swatchSize),
			])

			buttons.append(button)
		}

		if !buttons.isEmpty {
			let stackView = NSStackView(views: buttons)
			stackView.spacing = 0
			stackView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(stackView)

			NSLayoutConstraint.activate([
				stackView.topAnchor.constraint(equalTo: topAnchor),
				stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),

				tagLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 5),
				tagLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
				tagLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
				tagLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
			])
		} else {
			NSLayoutConstraint.activate([
				tagLabel.topAnchor.constraint(equalTo: topAnchor),
				tagLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
				tagLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
				tagLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
			])
		}
	}

	// MARK: - Actions

	@objc private func didClickTag(_ sender: NSButton) {
		let index = sender.tag
		guard index >= 0, index < favoriteTags.count else { return }

		let tag = favoriteTags[index]
		chosenTag = tag
		removeChosenTag = selectedTagsToRemove.contains(tag)

		if let action, let target, target.responds(to: action) {
			NSApp.sendAction(action, to: target, from: self)
		}

		parentMenu?.cancelTracking()
	}

	// MARK: - Swatch Drawing

	private func swatchImage(
		color: NSColor?,
		isSelected: Bool,
		isRemovable: Bool,
		mouseOver: Bool,
	) -> NSImage {
		NSImage(size: NSSize(width: Self.swatchSize, height: Self.swatchSize), flipped: false) { rect in
			let outerRect = rect.insetBy(dx: 2.5, dy: 2.5)
			let innerRect = rect.insetBy(dx: 5.5, dy: 5.5)

			let borderColor = color ?? .secondaryLabelColor
			let fillColor: NSColor
			let markColor: NSColor

			if let color {
				let rgb = color.usingColorSpace(.sRGB) ?? color
				let factor: CGFloat = 0.8
				fillColor = NSColor(
					srgbRed: 1 - factor * (1 - rgb.redComponent),
					green: 1 - factor * (1 - rgb.greenComponent),
					blue: 1 - factor * (1 - rgb.blueComponent),
					alpha: 1,
				)
				markColor = .white
			} else {
				fillColor = .clear
				markColor = borderColor
			}

			if mouseOver {
				let path = NSBezierPath(ovalIn: outerRect)
				fillColor.setFill()
				path.fill()
				borderColor.setStroke()
				path.stroke()

				let markRect = innerRect.insetBy(dx: 3, dy: 3)
				let line = NSBezierPath()

				if isRemovable {
					// X mark
					line.move(to: markRect.origin)
					line.line(to: NSPoint(x: markRect.maxX, y: markRect.maxY))
					line.move(to: NSPoint(x: markRect.maxX, y: markRect.minY))
					line.line(to: NSPoint(x: markRect.minX, y: markRect.maxY))
				} else {
					// + mark
					line.move(to: NSPoint(x: markRect.midX, y: markRect.minY))
					line.line(to: NSPoint(x: markRect.midX, y: markRect.maxY))
					line.move(to: NSPoint(x: markRect.minX, y: markRect.midY))
					line.line(to: NSPoint(x: markRect.maxX, y: markRect.midY))
				}
				line.lineWidth = 1.5
				markColor.setStroke()
				line.stroke()
			} else {
				let path = NSBezierPath(ovalIn: innerRect)
				fillColor.setFill()
				path.fill()
				borderColor.setStroke()
				path.stroke()

				if isSelected {
					// Checkmark
					let markRect = innerRect.insetBy(dx: 3, dy: 3)
					let line = NSBezierPath()
					line.move(to: NSPoint(x: markRect.minX, y: markRect.midY))
					line.line(to: NSPoint(x: markRect.minX + markRect.width / 4, y: markRect.minY))
					line.line(to: NSPoint(x: markRect.maxX, y: markRect.maxY))
					line.lineWidth = 1.5
					markColor.setStroke()
					line.stroke()
				}
			}

			return true
		}
	}
}
#endif
