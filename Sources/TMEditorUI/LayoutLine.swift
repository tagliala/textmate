import AppKit
import CoreText

/// A style run representing a contiguous span of text with uniform visual style.
public struct StyleRun: Sendable {
	/// Byte offset within the line where this style starts.
	public let start: Int
	/// Length of this style run in UTF-8 bytes.
	public let length: Int
	/// The foreground color.
	public let foreground: NSColor
	/// The background color (nil for transparent / editor background).
	public let background: NSColor?
	/// Whether the text is bold.
	public let isBold: Bool
	/// Whether the text is italic.
	public let isItalic: Bool
	/// Whether the text has underline.
	public let isUnderline: Bool
	/// Whether the text has strikethrough.
	public let isStrikethrough: Bool

	public init(
		start: Int,
		length: Int,
		foreground: NSColor,
		background: NSColor? = nil,
		isBold: Bool = false,
		isItalic: Bool = false,
		isUnderline: Bool = false,
		isStrikethrough: Bool = false,
	) {
		self.start = start
		self.length = length
		self.foreground = foreground
		self.background = background
		self.isBold = isBold
		self.isItalic = isItalic
		self.isUnderline = isUnderline
		self.isStrikethrough = isStrikethrough
	}
}

/// A single laid-out line ready for rendering.
///
/// Corresponds to the C++ `ct::line_t` in `Frameworks/layout/src/ct.h` and
/// the row entries in `ng::layout_t`.
public final class LayoutLine: @unchecked Sendable {
	/// The hard line index in the underlying text buffer.
	public let lineIndex: Int

	/// Soft-wrap offset within this hard line (0 if not wrapped or first segment).
	public let softWrapOffset: Int

	/// The position of this line in document coordinates.
	public var origin: CGPoint

	/// The height of this line (including inter-line spacing).
	public let height: CGFloat

	/// The width of this line's content (excluding margins).
	public let width: CGFloat

	/// The CoreText line object for rendering.
	public let ctLine: CTLine

	/// The resolved style runs for this line, in order.
	public let styleRuns: [StyleRun]

	/// The plain text content of this line (for hit-testing and measurement).
	public let text: String

	/// Tab positions detected in this line (character indices).
	public let tabLocations: [Int]

	/// Space positions detected in this line (character indices).
	public let spaceLocations: [Int]

	public init(
		lineIndex: Int,
		softWrapOffset: Int = 0,
		origin: CGPoint,
		height: CGFloat,
		width: CGFloat,
		ctLine: CTLine,
		styleRuns: [StyleRun],
		text: String,
		tabLocations: [Int] = [],
		spaceLocations: [Int] = [],
	) {
		self.lineIndex = lineIndex
		self.softWrapOffset = softWrapOffset
		self.origin = origin
		self.height = height
		self.width = width
		self.ctLine = ctLine
		self.styleRuns = styleRuns
		self.text = text
		self.tabLocations = tabLocations
		self.spaceLocations = spaceLocations
	}

	// MARK: - Hit Testing

	/// Returns the string index for the given x-offset within this line.
	public func index(forOffset xOffset: CGFloat) -> Int {
		let idx = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: xOffset, y: 0))
		return max(0, idx)
	}

	/// Returns the x-offset for the given string index.
	public func offset(forIndex index: Int) -> CGFloat {
		CTLineGetOffsetForStringIndex(ctLine, index, nil)
	}

	// MARK: - Drawing

	/// Draw the foreground text at the given position.
	public func drawForeground(at point: CGPoint, in context: CGContext) {
		context.saveGState()
		context.textPosition = point
		CTLineDraw(ctLine, context)
		context.restoreGState()
	}

	/// Draw background rectangles for style runs with background colors.
	public func drawBackground(
		at point: CGPoint,
		height: CGFloat,
		in context: CGContext,
		defaultBackground: CGColor,
	) {
		for run in styleRuns {
			guard let bg = run.background?.cgColor, bg != defaultBackground else { continue }
			let startX = offset(forIndex: run.start) + point.x
			let endX = offset(forIndex: run.start + run.length) + point.x
			let rect = CGRect(x: startX, y: point.y, width: endX - startX, height: height)
			context.setFillColor(bg)
			context.fill(rect)
		}
	}
}
