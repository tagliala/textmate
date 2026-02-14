import AppKit
import CoreText

/// Manages the layout of text lines for the custom rendering engine.
///
/// This is the Swift counterpart of `ng::layout_t` from the C++ codebase.
/// It handles:
/// - Viewport-based line layout (only visible lines + overscan are laid out)
/// - Soft wrapping with configurable wrap column
/// - Line ↔ point coordinate conversion
/// - Font metrics and line height calculation
/// - Invalidation on text edit, resize, font, or theme change
///
/// The layout manager does NOT own the text buffer or perform rendering.
/// It produces `LayoutLine` objects for the view to draw.
@MainActor
public final class EditorLayoutManager {
	// MARK: - Configuration

	/// The font metrics used for layout.
	public private(set) var fontMetrics: FontMetrics

	/// The font used for text rendering.
	public private(set) var font: NSFont

	/// Whether soft wrapping is enabled.
	public var softWrap: Bool = false {
		didSet {
			if oldValue != softWrap { invalidateAllLines() }
		}
	}

	/// The column at which to wrap (0 = wrap to viewport width).
	public var wrapColumn: Int = 0 {
		didSet {
			if oldValue != wrapColumn, softWrap { invalidateAllLines() }
		}
	}

	/// Whether to allow scrolling past the end of the document.
	public var scrollPastEnd: Bool = false

	/// Whether to draw the wrap column indicator.
	public var drawWrapColumn: Bool = false

	/// Whether to draw indent guides.
	public var drawIndentGuides: Bool = false

	/// The tab size in spaces.
	public var tabSize: Int = 4 {
		didSet {
			if oldValue != tabSize { invalidateAllLines() }
		}
	}

	/// Layout margins.
	public var margin: NSEdgeInsets = .init(top: 8, left: 8, bottom: 8, right: 8) {
		didSet { invalidateAllLines() }
	}

	/// The viewport size (used for soft-wrap and scroll calculations).
	public var viewportSize: CGSize = .zero {
		didSet {
			if oldValue.width != viewportSize.width, softWrap {
				invalidateAllLines()
			}
		}
	}

	// MARK: - Line Data

	/// The text lines (hard lines from the buffer, split by \n).
	private var lines: [String] = []

	/// Laid-out lines for the current viewport. Indexed by hard line number.
	private var layoutLines: [Int: [LayoutLine]] = [:]

	/// Cached total height (sum of all line heights).
	private var cachedTotalHeight: CGFloat?

	/// Set of hard line indices that need re-layout.
	private var dirtyLines: IndexSet = []

	/// Default foreground color for text.
	public var foregroundColor: NSColor = .textColor

	/// Default background color.
	public var backgroundColor: NSColor = .textBackgroundColor

	/// Style callback: given a hard line index, returns style runs.
	/// The layout manager calls this when laying out lines that need styling.
	public var styleProvider: ((Int, String) -> [StyleRun])?

	// MARK: - Init

	/// Creates a layout manager with the given font.
	public init(font: NSFont? = nil) {
		let f = font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
		self.font = f
		fontMetrics = FontMetrics(font: f)
	}

	// MARK: - Font

	/// Update the font and recalculate all metrics.
	public func setFont(_ newFont: NSFont) {
		font = newFont
		fontMetrics = FontMetrics(font: newFont)
		invalidateAllLines()
	}

	/// Update font by name and size.
	public func setFont(name: String, size: CGFloat) {
		let newFont = NSFont(name: name, size: size)
			?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
		setFont(newFont)
	}

	// MARK: - Text Content

	/// The total number of hard lines.
	public var lineCount: Int {
		lines.count
	}

	/// Set the full text content, splitting into lines.
	public func setText(_ text: String) {
		lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		invalidateAllLines()
	}

	/// Replace a range of hard lines with new lines.
	public func replaceLines(in range: Range<Int>, with newLines: [String]) {
		lines.replaceSubrange(range, with: newLines)
		// Invalidate the replaced range and everything after
		let start = range.lowerBound
		let end = lines.count
		dirtyLines.insert(integersIn: start ..< max(start + 1, end))
		cachedTotalHeight = nil
		layoutLines = layoutLines.filter { $0.key < start }
	}

	/// Get the text content of a specific line.
	public func lineText(_ lineIndex: Int) -> String? {
		guard lineIndex >= 0, lineIndex < lines.count else { return nil }
		return lines[lineIndex]
	}

	// MARK: - Layout

	/// The default line height based on current font metrics.
	public var defaultLineHeight: CGFloat {
		fontMetrics.lineHeight()
	}

	/// The effective wrap width (viewport width minus margins, or column-based).
	public var effectiveWrapWidth: CGFloat {
		if wrapColumn > 0 {
			return CGFloat(wrapColumn) * fontMetrics.columnWidth
		}
		return max(100, viewportSize.width - margin.left - margin.right)
	}

	/// Total document height (sum of all line heights).
	public var totalHeight: CGFloat {
		if let cached = cachedTotalHeight { return cached }
		let height = CGFloat(lines.count) * defaultLineHeight + margin.top + margin.bottom
		cachedTotalHeight = height
		return height
	}

	/// Total content width.
	public var totalWidth: CGFloat {
		if softWrap {
			return viewportSize.width
		}
		// Find the widest line among laid-out lines
		let maxLineWidth = layoutLines.values.flatMap(\.self)
			.map(\.width)
			.max() ?? 0
		return max(maxLineWidth + margin.left + margin.right, viewportSize.width)
	}

	/// Lay out lines visible in the given rect, plus overscan.
	///
	/// Returns the lines that should be drawn.
	public func layoutLines(in visibleRect: CGRect, overscan: Int = 50) -> [LayoutLine] {
		let lineHeight = defaultLineHeight
		guard lineHeight > 0, !lines.isEmpty else { return [] }

		let firstLine = max(0, Int((visibleRect.minY - margin.top) / lineHeight) - overscan)
		let lastLine = min(lines.count - 1, Int((visibleRect.maxY - margin.top) / lineHeight) + overscan)
		guard firstLine <= lastLine else { return [] }

		var result: [LayoutLine] = []
		for lineIdx in firstLine ... lastLine {
			let laid = layoutLine(lineIdx)
			result.append(contentsOf: laid)
		}
		return result
	}

	/// Lay out a single hard line, returning one or more LayoutLines
	/// (multiple if soft-wrapped).
	private func layoutLine(_ lineIndex: Int) -> [LayoutLine] {
		if let cached = layoutLines[lineIndex], !dirtyLines.contains(lineIndex) {
			return cached
		}

		let text = lineIndex < lines.count ? lines[lineIndex] : ""
		let lineHeight = defaultLineHeight
		let yOrigin = margin.top + CGFloat(lineIndex) * lineHeight

		// Get style runs from the style provider
		let runs = styleProvider?(lineIndex, text) ?? []

		// Create attributed string
		let attrString = createAttributedString(text: text, styleRuns: runs)

		// Create CTLine
		let ctLine = CTLineCreateWithAttributedString(attrString)

		// Detect tab and space positions
		var tabs: [Int] = []
		var spaces: [Int] = []
		for (i, ch) in text.enumerated() {
			if ch == "\t" { tabs.append(i) }
			else if ch == " " { spaces.append(i) }
		}

		var ascent: CGFloat = 0
		var descent: CGFloat = 0
		var leading: CGFloat = 0
		let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))

		// For now, no soft wrapping — single layout line per hard line
		// (soft wrapping will be added when needed)
		let layout = LayoutLine(
			lineIndex: lineIndex,
			softWrapOffset: 0,
			origin: CGPoint(x: margin.left, y: yOrigin),
			height: lineHeight,
			width: width,
			ctLine: ctLine,
			styleRuns: runs,
			text: text,
			tabLocations: tabs,
			spaceLocations: spaces,
		)

		let result = [layout]
		layoutLines[lineIndex] = result
		dirtyLines.remove(lineIndex)
		return result
	}

	/// Create an NSAttributedString with the given style runs applied.
	private func createAttributedString(text: String, styleRuns: [StyleRun]) -> NSAttributedString {
		let attrString = NSMutableAttributedString(
			string: text,
			attributes: [
				.font: font,
				.foregroundColor: foregroundColor,
			],
		)

		let utf8 = Array(text.utf8)
		for run in styleRuns {
			// Convert byte offset to string range
			guard run.start >= 0, run.start + run.length <= utf8.count else { continue }
			let startStr = text.utf8.index(text.utf8.startIndex, offsetBy: run.start)
			let endStr = text.utf8.index(startStr, offsetBy: run.length)
			guard let startIdx = startStr.samePosition(in: text),
			      let endIdx = endStr.samePosition(in: text)
			else { continue }

			let nsRange = NSRange(startIdx ..< endIdx, in: text)

			var attrs: [NSAttributedString.Key: Any] = [
				.foregroundColor: run.foreground,
			]

			if let bg = run.background {
				attrs[.backgroundColor] = bg
			}

			if run.isBold || run.isItalic {
				var traits: NSFontDescriptor.SymbolicTraits = []
				if run.isBold { traits.insert(.bold) }
				if run.isItalic { traits.insert(.italic) }
				if let modified = font.fontDescriptor.withSymbolicTraits(traits)
					.withSize(font.pointSize) as NSFontDescriptor?
				{
					if let styledFont = NSFont(descriptor: modified, size: font.pointSize) {
						attrs[.font] = styledFont
					}
				}
			}

			if run.isUnderline {
				attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
			}
			if run.isStrikethrough {
				attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
			}

			attrString.addAttributes(attrs, range: nsRange)
		}

		// Set up tab stops
		let paragraphStyle = NSMutableParagraphStyle()
		let tabWidth = fontMetrics.columnWidth * CGFloat(tabSize)
		var tabStops: [NSTextTab] = []
		for i in 1 ... 64 {
			tabStops.append(NSTextTab(textAlignment: .left, location: tabWidth * CGFloat(i)))
		}
		paragraphStyle.tabStops = tabStops
		paragraphStyle.defaultTabInterval = tabWidth
		attrString.addAttribute(
			.paragraphStyle, value: paragraphStyle,
			range: NSRange(location: 0, length: attrString.length),
		)

		return attrString
	}

	// MARK: - Coordinate Conversion

	/// Returns the hard line index at the given y-coordinate.
	public func lineIndex(atY y: CGFloat) -> Int {
		let lineHeight = defaultLineHeight
		guard lineHeight > 0 else { return 0 }
		let line = Int((y - margin.top) / lineHeight)
		return max(0, min(line, lines.count - 1))
	}

	/// Returns the y-coordinate for the top of the given line.
	public func yPosition(forLine lineIndex: Int) -> CGFloat {
		margin.top + CGFloat(lineIndex) * defaultLineHeight
	}

	/// Returns the rect for the given line index.
	public func rect(forLine lineIndex: Int) -> CGRect {
		CGRect(
			x: 0,
			y: yPosition(forLine: lineIndex),
			width: viewportSize.width,
			height: defaultLineHeight,
		)
	}

	/// Returns the string index within a line for the given point.
	public func characterIndex(at point: CGPoint) -> (line: Int, index: Int) {
		let lineIndex = lineIndex(atY: point.y)
		guard let laid = layoutLines[lineIndex]?.first else {
			return (lineIndex, 0)
		}
		let xInLine = point.x - margin.left
		let charIdx = laid.index(forOffset: xInLine)
		return (lineIndex, charIdx)
	}

	/// Returns the point (top-left of character cell) for the given line and character index.
	public func point(forLine lineIndex: Int, characterIndex: Int) -> CGPoint {
		let y = yPosition(forLine: lineIndex)
		guard let laid = layoutLines[lineIndex]?.first else {
			return CGPoint(x: margin.left, y: y)
		}
		let x = laid.offset(forIndex: characterIndex) + margin.left
		return CGPoint(x: x, y: y)
	}

	/// Returns the rect for the caret at the given line and character index.
	public func caretRect(forLine lineIndex: Int, characterIndex: Int) -> CGRect {
		let pt = point(forLine: lineIndex, characterIndex: characterIndex)
		return CGRect(x: pt.x, y: pt.y, width: 2, height: defaultLineHeight)
	}

	// MARK: - Invalidation

	/// Mark all lines as needing re-layout.
	public func invalidateAllLines() {
		layoutLines.removeAll()
		dirtyLines = IndexSet(integersIn: 0 ..< max(1, lines.count))
		cachedTotalHeight = nil
	}

	/// Mark a range of lines as needing re-layout.
	public func invalidateLines(_ range: Range<Int>) {
		dirtyLines.insert(integersIn: range)
		for lineIdx in range {
			layoutLines.removeValue(forKey: lineIdx)
		}
		cachedTotalHeight = nil
	}

	/// Mark lines as dirty due to a scope/style change (no text change).
	public func invalidateStyles(from lineIndex: Int, to endIndex: Int) {
		invalidateLines(lineIndex ..< endIndex)
	}
}
