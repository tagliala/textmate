import AppKit

/// A gutter view that displays line numbers, fold markers, and bookmark indicators.
///
/// Supports:
/// - Line numbers with theme-aware colors
/// - Fold markers (disclosure triangles) for foldable regions
/// - Bookmark indicators (⌘F2 to toggle)
/// - Click-to-toggle bookmarks on line numbers
/// Uses system appearance colors — follows light/dark mode automatically.
@MainActor
public class GutterView: NSView {
	public var lineCount: Int = 1 {
		didSet {
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}

	public var firstVisibleLine: Int = 1
	public var selectedLine: Int = 1 {
		didSet { needsDisplay = true }
	}

	public var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
	public var gutterWidth: CGFloat = 40

	/// Lines that have bookmarks set.
	public private(set) var bookmarkedLines: Set<Int> = []

	/// Lines that are foldable (have a fold marker).
	public var foldableLines: Set<Int> = [] {
		didSet { needsDisplay = true }
	}

	/// Lines that are currently folded (collapsed).
	public private(set) var foldedLines: Set<Int> = []

	/// Delegate for gutter interactions.
	public weak var delegate: GutterViewDelegate?

	private var foregroundColor: NSColor = .secondaryLabelColor
	private var backgroundColor: NSColor = .controlBackgroundColor
	private var selectedForegroundColor: NSColor = .labelColor
	private var selectedBackgroundColor: NSColor = .controlBackgroundColor

	/// Width of the fold marker column.
	private let foldColumnWidth: CGFloat = 14

	/// Width of the bookmark indicator column.
	private let bookmarkColumnWidth: CGFloat = 8

	override public var isFlipped: Bool {
		true
	}

	override public var intrinsicContentSize: NSSize {
		NSSize(width: gutterWidth, height: NSView.noIntrinsicMetric)
	}

	override public init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		setupTrackingArea()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Public API

	/// Update the gutter width to accommodate line numbers + fold + bookmark columns.
	public func updateWidth(forLineCount count: Int) {
		let digits = max(3, String(count).count)
		let sampleString = String(repeating: "8", count: digits)
		let attrs: [NSAttributedString.Key: Any] = [.font: font]
		let size = (sampleString as NSString).size(withAttributes: attrs)
		gutterWidth = ceil(size.width) + 16 + foldColumnWidth + bookmarkColumnWidth
		invalidateIntrinsicContentSize()
	}

	/// Toggle a bookmark on the given line.
	public func toggleBookmark(atLine line: Int) {
		if bookmarkedLines.contains(line) {
			bookmarkedLines.remove(line)
		} else {
			bookmarkedLines.insert(line)
		}
		needsDisplay = true
		delegate?.gutterView(self, didToggleBookmarkAtLine: line)
	}

	/// Toggle fold state for a foldable line.
	public func toggleFold(atLine line: Int) {
		guard foldableLines.contains(line) else { return }
		if foldedLines.contains(line) {
			foldedLines.remove(line)
		} else {
			foldedLines.insert(line)
		}
		needsDisplay = true
		delegate?.gutterView(self, didToggleFoldAtLine: line)
	}

	// MARK: - Mouse Handling

	private func setupTrackingArea() {
		let trackingArea = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
			owner: self,
		)
		addTrackingArea(trackingArea)
	}

	override public func mouseDown(with event: NSEvent) {
		let location = convert(event.locationInWindow, from: nil)
		let lineHeight = lineHeight
		let clickedLine = firstVisibleLine + Int(location.y / lineHeight)
		guard clickedLine >= 1, clickedLine <= lineCount else { return }

		// Determine which column was clicked
		let lineNumberEnd = gutterWidth - foldColumnWidth
		let bookmarkEnd = bookmarkColumnWidth

		if location.x < bookmarkEnd {
			// Clicked in bookmark column
			toggleBookmark(atLine: clickedLine)
		} else if location.x > lineNumberEnd {
			// Clicked in fold column
			toggleFold(atLine: clickedLine)
		} else {
			// Clicked on line number — toggle bookmark
			toggleBookmark(atLine: clickedLine)
		}
	}

	// MARK: - Drawing

	private var lineHeight: CGFloat {
		font.ascender - font.descender + font.leading + 2
	}

	override public func draw(_ dirtyRect: NSRect) {
		backgroundColor.setFill()
		dirtyRect.fill()

		let lineHeight = lineHeight
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

		let lineNumberEnd = gutterWidth - foldColumnWidth

		for line in startLine ... endLine {
			let y = CGFloat(line - startLine) * lineHeight
			let rect = NSRect(x: 0, y: y, width: bounds.width, height: lineHeight)

			guard dirtyRect.intersects(rect) else { continue }

			let isSelected = line == selectedLine
			if isSelected {
				selectedBackgroundColor.setFill()
				rect.fill()
			}

			// Bookmark indicator (small diamond at left edge)
			if bookmarkedLines.contains(line) {
				let bookmarkRect = NSRect(
					x: 1,
					y: y + (lineHeight - 8) / 2,
					width: 6,
					height: 8,
				)
				NSColor.systemBlue.setFill()
				let path = NSBezierPath()
				let cx = bookmarkRect.midX
				let cy = bookmarkRect.midY
				path.move(to: NSPoint(x: cx, y: bookmarkRect.minY))
				path.line(to: NSPoint(x: bookmarkRect.maxX, y: cy))
				path.line(to: NSPoint(x: cx, y: bookmarkRect.maxY))
				path.line(to: NSPoint(x: bookmarkRect.minX, y: cy))
				path.close()
				path.fill()
			}

			// Line number
			let text = "\(line)" as NSString
			let textAttrs = isSelected ? selectedAttrs : attrs
			let textSize = text.size(withAttributes: textAttrs)
			let textRect = NSRect(
				x: lineNumberEnd - textSize.width - 4,
				y: y + (lineHeight - textSize.height) / 2,
				width: textSize.width,
				height: textSize.height,
			)
			text.draw(in: textRect, withAttributes: textAttrs)

			// Fold marker (disclosure triangle)
			if foldableLines.contains(line) {
				let isFolded = foldedLines.contains(line)
				let triangleSize: CGFloat = 8
				let tx = lineNumberEnd + (foldColumnWidth - triangleSize) / 2
				let ty = y + (lineHeight - triangleSize) / 2

				let triangle = NSBezierPath()
				if isFolded {
					// Right-pointing triangle (folded)
					triangle.move(to: NSPoint(x: tx, y: ty))
					triangle.line(to: NSPoint(x: tx + triangleSize, y: ty + triangleSize / 2))
					triangle.line(to: NSPoint(x: tx, y: ty + triangleSize))
				} else {
					// Down-pointing triangle (expanded)
					triangle.move(to: NSPoint(x: tx, y: ty))
					triangle.line(to: NSPoint(x: tx + triangleSize, y: ty))
					triangle.line(to: NSPoint(x: tx + triangleSize / 2, y: ty + triangleSize))
				}
				triangle.close()
				foregroundColor.withAlphaComponent(0.6).setFill()
				triangle.fill()
			}
		}
	}
}

/// Delegate for gutter interactions.
@MainActor
public protocol GutterViewDelegate: AnyObject {
	func gutterView(_ gutterView: GutterView, didToggleBookmarkAtLine line: Int)
	func gutterView(_ gutterView: GutterView, didToggleFoldAtLine line: Int)
}

/// Default no-op implementations.
public extension GutterViewDelegate {
	func gutterView(_: GutterView, didToggleBookmarkAtLine _: Int) {}
	func gutterView(_: GutterView, didToggleFoldAtLine _: Int) {}
}
