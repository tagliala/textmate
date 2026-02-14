import AppKit

/// A gutter view that displays line numbers alongside the editor.
///
/// For Iteration 1, this provides visual-only line numbers.
/// Fold markers and SCM indicators will be added in later iterations.
/// Uses system appearance colors — follows light/dark mode automatically.
@MainActor
public class GutterView: NSView {
	public var lineCount: Int = 1 {
		didSet { invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}

	public var firstVisibleLine: Int = 1
	public var selectedLine: Int = 1 {
		didSet { needsDisplay = true }
	}

	public var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
	public var gutterWidth: CGFloat = 40

	private var foregroundColor: NSColor = .secondaryLabelColor
	private var backgroundColor: NSColor = .controlBackgroundColor
	private var selectedForegroundColor: NSColor = .labelColor
	private var selectedBackgroundColor: NSColor = .controlBackgroundColor

	override public var isFlipped: Bool {
		true
	}

	override public var intrinsicContentSize: NSSize {
		NSSize(width: gutterWidth, height: NSView.noIntrinsicMetric)
	}

	override public init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Public API

	/// Update the gutter width to accommodate the number of digits needed.
	public func updateWidth(forLineCount count: Int) {
		let digits = max(3, String(count).count)
		let sampleString = String(repeating: "8", count: digits)
		let attrs: [NSAttributedString.Key: Any] = [.font: font]
		let size = (sampleString as NSString).size(withAttributes: attrs)
		gutterWidth = ceil(size.width) + 16 // 8pt padding each side
		invalidateIntrinsicContentSize()
	}

	// MARK: - Drawing

	override public func draw(_ dirtyRect: NSRect) {
		backgroundColor.setFill()
		dirtyRect.fill()

		let lineHeight = font.ascender - font.descender + font.leading + 2
		let attrs: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: foregroundColor,
		]
		let selectedAttrs: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: selectedForegroundColor,
		]

		let startLine = firstVisibleLine
		let visibleLines = Int(ceil(bounds.height / lineHeight))
		let endLine = min(startLine + visibleLines, lineCount)

		for line in startLine ... endLine {
			let y = CGFloat(line - startLine) * lineHeight
			let rect = NSRect(x: 0, y: y, width: bounds.width, height: lineHeight)

			guard dirtyRect.intersects(rect) else { continue }

			let isSelected = line == selectedLine
			if isSelected {
				selectedBackgroundColor.setFill()
				rect.fill()
			}

			let text = "\(line)" as NSString
			let textAttrs = isSelected ? selectedAttrs : attrs
			let textSize = text.size(withAttributes: textAttrs)
			let textRect = NSRect(
				x: bounds.width - textSize.width - 8,
				y: y + (lineHeight - textSize.height) / 2,
				width: textSize.width,
				height: textSize.height,
			)
			text.draw(in: textRect, withAttributes: textAttrs)
		}
	}
}
