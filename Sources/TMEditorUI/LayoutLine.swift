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

/// A decoration run for underline or strikethrough, stored separately from
/// the main style runs so they can be drawn in order on top of the text.
///
/// Maps to the C++ `_underlines` / `_strikethroughs` vectors in `ct::line_t`.
public struct DecorationRun: Sendable {
	/// The CFRange location within the CTLine's attributed string.
	public let location: Int
	/// The length in the CTLine's attributed string.
	public let length: Int
	/// The decoration color.
	public let color: CGColor

	public init(location: Int, length: Int, color: CGColor) {
		self.location = location
		self.length = length
		self.color = color
	}
}

/// A misspelled range within a line, specified by UTF-8 byte offsets.
public struct MisspelledRange: Sendable {
	/// Start byte offset within the line.
	public let from: Int
	/// End byte offset within the line.
	public let to: Int

	public init(from: Int, to: Int) {
		self.from = from
		self.to = to
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

	/// Underline decoration runs (drawn separately from CoreText's underlines).
	/// Matches the C++ `_underlines` vector in `ct::line_t`.
	public let underlineRuns: [DecorationRun]

	/// Strikethrough decoration runs.
	/// Matches the C++ `_strikethroughs` vector in `ct::line_t`.
	public let strikethroughRuns: [DecorationRun]

	/// The x-height of the font, used for centering strikethrough lines.
	public let xHeight: CGFloat

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
		underlineRuns: [DecorationRun] = [],
		strikethroughRuns: [DecorationRun] = [],
		xHeight: CGFloat = 0,
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
		self.underlineRuns = underlineRuns
		self.strikethroughRuns = strikethroughRuns
		self.xHeight = xHeight
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

	// MARK: - Underline / Strikethrough / Misspelling Drawing

	/// Draw underline decorations.
	///
	/// CoreText's built-in underline rendering is poor (rdar://5845224),
	/// so we draw our own, matching the C++ `ct::line_t::draw_foreground`.
	public func drawUnderlines(at point: CGPoint, in context: CGContext) {
		for run in underlineRuns {
			let x1 = round(point.x + CGFloat(CTLineGetOffsetForStringIndex(ctLine, run.location, nil)))
			let x2 = round(point.x + CGFloat(CTLineGetOffsetForStringIndex(ctLine, run.location + run.length, nil)))
			context.setFillColor(run.color)
			context.fill(CGRect(x: x1, y: point.y + 1, width: x2 - x1, height: 1))
		}
	}

	/// Draw strikethrough decorations.
	///
	/// Strikethrough is centered vertically at xHeight/2, matching the C++
	/// rendering: `pos.y - (_x_height+1)/2`.
	public func drawStrikethroughs(at point: CGPoint, in context: CGContext) {
		for run in strikethroughRuns {
			let x1 = round(point.x + CGFloat(CTLineGetOffsetForStringIndex(ctLine, run.location, nil)))
			let x2 = round(point.x + CGFloat(CTLineGetOffsetForStringIndex(ctLine, run.location + run.length, nil)))
			let yPos = round(point.y - (xHeight + 1) / 2)
			context.setFillColor(run.color)
			context.fill(CGRect(x: x1, y: yPos, width: x2 - x1, height: 1))
		}
	}

	/// Draw misspelling dots under the specified ranges.
	///
	/// Port of the C++ `draw_spelling_dot()` function from `ct.cc`.
	///
	/// - Parameters:
	///   - misspelled: Ranges of misspelled text (UTF-8 byte offsets within line).
	///   - point: The baseline drawing position.
	///   - spellingDotImage: The spelling dot image to tile.
	///   - isFlipped: Whether the view coordinate system is flipped.
	///   - context: The drawing context.
	public func drawMisspellings(
		_ misspelled: [MisspelledRange],
		at point: CGPoint,
		spellingDotImage: CGImage?,
		isFlipped: Bool,
		in context: CGContext,
	) {
		guard let dotImage = spellingDotImage, !misspelled.isEmpty else { return }

		for range in misspelled {
			// Convert byte offsets to CTLine string indices
			// This is a simplified version; full UTF-16 distance calculation
			// would be needed for complete accuracy with surrogate pairs
			let x1 = round(point.x + CGFloat(CTLineGetOffsetForStringIndex(ctLine, range.from, nil)))
			let x2 = round(point.x + CGFloat(CTLineGetOffsetForStringIndex(ctLine, range.to, nil)))
			let dotRect = CGRect(x: x1, y: point.y + 1, width: x2 - x1, height: 3)

			context.saveGState()
			if isFlipped {
				let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 2 * dotRect.origin.y + 3)
				context.concatenate(transform)
			}
			// Tile the spelling dot image across the range
			var x = dotRect.origin.x
			while x < dotRect.origin.x + dotRect.width - 0.5 {
				context.draw(dotImage, in: CGRect(x: x, y: dotRect.origin.y, width: 4, height: 3))
				x += 4
			}
			context.restoreGState()
		}
	}
}
