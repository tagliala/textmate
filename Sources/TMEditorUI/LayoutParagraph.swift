import CoreGraphics
@preconcurrency import CoreText

/// The type of a paragraph layout node.
///
/// Maps to C++ `paragraph_t::node_type_t`.
public enum ParagraphNodeType: Sendable {
	/// Regular text content.
	case text
	/// An unprintable/control character displayed as a placeholder.
	case unprintable
	/// A folded region collapsed into a visual indicator.
	case folding
	/// A soft-break point inserted for soft-wrapping.
	case softBreak
	/// The newline character at the end of the line.
	case newline
}

/// A segment within a paragraph that has its own layout and rendering.
///
/// Swift counterpart of C++ `paragraph_t::node_t` in `paragraph.h`.
///
/// A paragraph is composed of an ordered sequence of nodes. Each node
/// represents text, an unprintable character placeholder, a folding
/// indicator, a soft-wrap break, or a newline character.
public final class ParagraphNode: @unchecked Sendable {
	/// The type of this node.
	public let type: ParagraphNodeType

	/// The byte length this node covers in the buffer.
	public private(set) var length: Int

	/// The pixel width of this node (for fixed-width nodes like folding dots).
	private var fixedWidth: CGFloat

	/// The CoreText line for rendering (if applicable).
	public private(set) var ctLine: CTLine?

	/// Creates a paragraph node.
	public init(type: ParagraphNodeType, length: Int = 0, width: CGFloat = 0) {
		self.type = type
		self.length = length
		fixedWidth = width
		ctLine = nil
	}

	/// Insert `len` bytes at position `i` within this node.
	public func insert(_: Int, length len: Int) {
		length += len
		ctLine = nil
	}

	/// Erase bytes `from ..< to` within this node.
	public func erase(from: Int, to: Int) {
		precondition(from <= to && to <= length)
		length -= (to - from)
		ctLine = nil
	}

	/// Invalidate the cached CTLine when scopes change.
	public func didUpdateScopes(from _: Int, to _: Int) {
		ctLine = nil
	}

	/// The computed width of this node.
	public var width: CGFloat {
		if let line = ctLine {
			return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
		}
		return fixedWidth
	}

	/// Invalidate the cached CTLine when font metrics change.
	public func resetFontMetrics() {
		ctLine = nil
	}

	/// Invalidate the cached CTLine for tab width recalculation.
	public func updateTabWidth() {
		ctLine = nil
	}

	/// Layout this node, creating its CTLine.
	///
	/// This is called during the paragraph layout pass. The specific behavior
	/// depends on the node type.
	///
	/// - Parameters:
	///   - layoutInfo: The information needed to create the CTLine.
	public func layout(with layoutInfo: ParagraphNodeLayoutInfo) {
		guard ctLine == nil else { return }

		switch type {
		case .text:
			ctLine = layoutInfo.createTextLine()

		case .unprintable:
			ctLine = layoutInfo.createUnprintableLine()

		case .folding:
			fixedWidth = round(layoutInfo.capHeight * ParagraphConstants.foldingDotsRatio)

		case .softBreak:
			ctLine = layoutInfo.createSoftBreakLine()

		case .newline:
			break
		}
	}
}

/// Layout parameters passed to a `ParagraphNode` during layout.
///
/// This struct captures all the information a node needs to create its CTLine,
/// avoiding the need to pass many parameters through multiple call layers.
public struct ParagraphNodeLayoutInfo: Sendable {
	/// The text content of this node from the buffer.
	public let text: String
	/// A factory closure that creates a CTLine from attributed text.
	public let createTextLine: @Sendable () -> CTLine?
	/// A factory closure for creating an unprintable representation CTLine.
	public let createUnprintableLine: @Sendable () -> CTLine?
	/// A factory closure for creating a soft-break fill CTLine.
	public let createSoftBreakLine: @Sendable () -> CTLine?
	/// The cap height for folding dot sizing.
	public let capHeight: CGFloat

	public init(
		text: String,
		createTextLine: @escaping @Sendable () -> CTLine?,
		createUnprintableLine: @escaping @Sendable () -> CTLine?,
		createSoftBreakLine: @escaping @Sendable () -> CTLine?,
		capHeight: CGFloat,
	) {
		self.text = text
		self.createTextLine = createTextLine
		self.createUnprintableLine = createUnprintableLine
		self.createSoftBreakLine = createSoftBreakLine
		self.capHeight = capHeight
	}
}

/// Constants used by the paragraph layout system.
public enum ParagraphConstants {
	/// Width/height ratio for folding dots indicator.
	/// Matches the C++ `kFoldingDotsRatio = 20.0 / 10.0`.
	public static let foldingDotsRatio: CGFloat = 20.0 / 10.0

	/// Maximum bytes per CTLine before splitting into separate text nodes.
	/// Matches the C++ `kCTLineMaxSize = 2048`.
	public static let ctLineMaxSize: Int = 2048
}

/// A soft-line within a paragraph — one visual row after soft-wrapping.
///
/// Maps to C++ `paragraph_t::softline_t`.
public struct SoftLine: Sendable {
	/// Byte offset within the paragraph where this soft-line starts.
	public let offset: Int
	/// The x position of the start of this soft-line.
	public let x: CGFloat
	/// The y position relative to the paragraph top.
	public let y: CGFloat
	/// The baseline position within this soft-line's height.
	public let baseline: CGFloat
	/// The height of this soft-line.
	public let height: CGFloat
	/// Index of the first node in this soft-line.
	public let firstNode: Int
	/// Index past the last node in this soft-line (exclusive).
	public let lastNode: Int

	public init(offset: Int, x: CGFloat, y: CGFloat, baseline: CGFloat, height: CGFloat, firstNode: Int, lastNode: Int) {
		self.offset = offset
		self.x = x
		self.y = y
		self.baseline = baseline
		self.height = height
		self.firstNode = firstNode
		self.lastNode = lastNode
	}
}

/// A line record for gutter view support.
///
/// Maps to C++ `ng::line_record_t`.
public struct LineRecord: Sendable {
	/// The hard line number.
	public let line: Int
	/// The soft-line offset within the paragraph.
	public let softline: Int
	/// The top y-coordinate.
	public let top: CGFloat
	/// The bottom y-coordinate.
	public let bottom: CGFloat
	/// The baseline y-coordinate.
	public let baseline: CGFloat

	public init(line: Int, softline: Int, top: CGFloat, bottom: CGFloat, baseline: CGFloat) {
		self.line = line
		self.softline = softline
		self.top = top
		self.bottom = bottom
		self.baseline = baseline
	}
}

/// A paragraph in the layout engine — one hard line from the buffer,
/// composed of nodes (text, unprintable, folding, soft-break, newline).
///
/// Swift counterpart of C++ `ng::paragraph_t` in `paragraph.h`.
///
/// The paragraph handles:
/// - Decomposing buffer text into typed nodes
/// - Inserting soft-break nodes for word wrap
/// - Computing soft-line metrics (height, baseline, offsets)
/// - Hit-testing (point → index and index → rect)
/// - Navigation within folds (bol/eol that skip folded content)
public final class LayoutParagraph: @unchecked Sendable {
	/// The ordered sequence of nodes in this paragraph.
	private var nodes: [ParagraphNode] = []

	/// Whether this paragraph needs re-layout.
	private var isDirty: Bool = true

	public init() {}

	// MARK: - Properties

	/// Total byte length of this paragraph (sum of all node lengths).
	public var length: Int {
		nodes.reduce(0) { $0 + $1.length }
	}

	/// The total width (widest soft-line).
	public var totalWidth: CGFloat {
		var x: CGFloat = 0
		var maxWidth: CGFloat = 0
		for node in nodes {
			if node.type == .softBreak {
				x = 0
			}
			x += node.width
			maxWidth = max(x, maxWidth)
		}
		return maxWidth
	}

	/// The total height given the specified font metrics.
	public func totalHeight(metrics: FontMetrics) -> CGFloat {
		let lines = computeSoftLines(metrics: metrics)
		guard let last = lines.last else { return metrics.lineHeight() }
		return last.y + last.height
	}

	/// Whether the paragraph needs layout.
	public var needsLayout: Bool {
		isDirty
	}

	// MARK: - Content Modification

	/// Insert buffer content into this paragraph.
	///
	/// Scans the text for newlines and unprintable characters, creating
	/// appropriate node types.
	///
	/// - Parameters:
	///   - pos: Buffer offset where insertion starts.
	///   - len: Number of bytes inserted.
	///   - text: The inserted text content.
	///   - bufferOffset: The buffer offset of this paragraph's start.
	public func insert(pos: Int, length _: Int, text: String, bufferOffset: Int) {
		let relativePos = pos - bufferOffset
		var from = 0
		var i = 0

		for scalar in text.unicodeScalars {
			let charLen = scalar.utf8.count

			if scalar == "\n" || unprintableRepresentation(for: scalar) != nil {
				if from != i {
					insertText(at: relativePos + from, length: i - from)
				}
				if scalar == "\n" {
					insertNewline(at: relativePos + i, length: charLen)
				} else {
					insertUnprintable(at: relativePos + i, length: charLen)
				}
				from = i + charLen
			} else if i - from >= ParagraphConstants.ctLineMaxSize {
				insertText(at: relativePos + from, length: i - from)
				from = i
			}
			i += charLen
		}

		if from != text.utf8.count {
			insertText(at: relativePos + from, length: text.utf8.count - from)
		}

		isDirty = true
	}

	/// Insert a folded region.
	public func insertFolded(pos: Int, length len: Int, bufferOffset: Int) {
		let iter = iteratorAt(pos - bufferOffset)
		nodes.insert(ParagraphNode(type: .folding, length: len), at: iter)
		isDirty = true
	}

	/// Erase a range from this paragraph.
	public func erase(from: Int, to: Int, bufferOffset: Int) {
		precondition(bufferOffset <= from && to <= bufferOffset + length)

		var eraseFrom = from
		var i = bufferOffset
		for node in nodes {
			let len = node.length
			if i <= eraseFrom, eraseFrom < i + len {
				let last = min(to - i, len)
				node.erase(from: eraseFrom - i, to: last)
				eraseFrom = i + last
				if to - i <= last { break }
			}
			i += node.length
		}

		// Remove empty nodes (except soft-breaks which are length-0 by design)
		nodes.removeAll { $0.length == 0 && $0.type != .softBreak }
		isDirty = true
	}

	/// Invalidate cached rendering data when scopes change.
	public func didUpdateScopes(from: Int, to: Int, bufferOffset: Int) {
		var i = bufferOffset
		for node in nodes {
			node.didUpdateScopes(from: from - i, to: to - i)
			i += node.length
		}
		isDirty = true
	}

	// MARK: - Layout

	/// Perform layout: compute soft-break points and create CTLines.
	///
	/// - Parameters:
	///   - softWrap: Whether soft-wrapping is enabled.
	///   - wrapColumn: The column at which to wrap.
	///   - metrics: Font metrics for line height calculation.
	///   - layoutProvider: Provides CTLine factories for nodes.
	/// - Returns: `true` if the layout actually changed (was dirty).
	@discardableResult
	public func layout(
		softWrap: Bool,
		wrapColumn: Int,
		metrics: FontMetrics,
		layoutProvider: ParagraphLayoutProvider,
	) -> Bool {
		guard isDirty else { return false }

		// Remove existing soft-breaks
		nodes.removeAll { $0.type == .softBreak }

		// Insert soft-break nodes for word wrapping when softWrap is enabled.
		if softWrap, wrapColumn > 0 {
			// Build the paragraph text from all node lengths.
			let totalLen = nodes.reduce(0) { $0 + $1.length }
			let hasFoldings = nodes.contains { $0.type == .folding }

			// Only wrap if there are no folded regions (matches C++ behavior).
			if !hasFoldings, totalLen > 0 {
				// We need the raw text to compute soft breaks. The layout
				// provider will supply the text when laying out each node,
				// but for break calculation we use the byte lengths.
				// Since we don't have the raw buffer text here, we approximate
				// with node lengths. The EditorLayoutManager handles the actual
				// CTTypesetter-based wrapping; this path is for the lower-level
				// paragraph system used by the gutter/hit-test code.
				// For now, insert a soft-break node at the wrap column boundary
				// using a simplified character-counting approach.
				var col = 0
				var offset = 0
				for node in Array(nodes) {
					col += node.length
					offset += node.length
					if col >= wrapColumn, node.type == .text, col > 0 {
						let insertIdx = iteratorAt(offset)
						nodes.insert(ParagraphNode(type: .softBreak, length: 0), at: insertIdx)
						col = 0
					}
				}
			}
		}

		// Layout each node
		var x: CGFloat = 0
		var bufferOffset = 0
		for node in nodes {
			let info = layoutProvider.layoutInfo(
				for: node,
				at: bufferOffset,
				xPosition: x,
				metrics: metrics,
			)
			node.layout(with: info)
			x += node.width
			bufferOffset += node.length
		}

		isDirty = false
		return true
	}

	/// Mark the paragraph as needing re-layout.
	public func setNeedsLayout() {
		isDirty = true
	}

	/// Reset font metrics for all nodes.
	public func resetFontMetrics() {
		isDirty = true
		for node in nodes {
			node.resetFontMetrics()
		}
	}

	/// Set wrapping parameters (marks dirty).
	public func setWrapping(softWrap _: Bool, wrapColumn _: Int, metrics _: FontMetrics) {
		isDirty = true
	}

	/// Set tab size (marks dirty, updates tab widths).
	public func setTabSize(metrics: FontMetrics) {
		isDirty = true
		let lines = computeSoftLines(metrics: metrics)
		for line in lines {
			for i in line.firstNode ..< min(line.lastNode, nodes.count) {
				nodes[i].updateTabWidth()
			}
		}
	}

	// MARK: - Soft Lines

	/// Compute the soft-line decomposition of this paragraph.
	public func computeSoftLines(metrics: FontMetrics, softBreaksOnNewline: Bool = false) -> [SoftLine] {
		var softlines: [SoftLine] = []
		var x: CGFloat = 0
		var y: CGFloat = 0
		var firstNode = 0
		var firstOffset = 0
		var offset = 0
		var ascent: CGFloat = 0
		var descent: CGFloat = 0
		var leading: CGFloat = 0

		for i in 0 ..< nodes.count {
			let node = nodes[i]

			if node.type == .softBreak {
				softlines.append(SoftLine(
					offset: firstOffset,
					x: x,
					y: y,
					baseline: metrics.baseline(minAscent: ascent),
					height: metrics.lineHeight(minAscent: ascent, minDescent: descent, minLeading: leading),
					firstNode: firstNode,
					lastNode: i + (softBreaksOnNewline ? 0 : 1),
				))
				firstOffset = offset
				x = softBreaksOnNewline ? 0 : node.width
				y += metrics.lineHeight(minAscent: ascent, minDescent: descent, minLeading: leading)
				firstNode = i + (softBreaksOnNewline ? 0 : 1)
				ascent = 0
				descent = 0
				leading = 0
			}

			if let line = node.ctLine {
				var a: CGFloat = 0
				var d: CGFloat = 0
				var l: CGFloat = 0
				_ = CTLineGetTypographicBounds(line, &a, &d, &l)
				ascent = max(ascent, a)
				descent = max(descent, d)
				leading = max(leading, l)
			}

			offset += node.length
		}

		// Final soft-line
		softlines.append(SoftLine(
			offset: firstOffset,
			x: x,
			y: y,
			baseline: metrics.baseline(minAscent: ascent),
			height: metrics.lineHeight(minAscent: ascent, minDescent: descent, minLeading: leading),
			firstNode: firstNode,
			lastNode: nodes.count,
		))

		return softlines
	}

	/// Number of soft-lines.
	public func softLineCount(metrics: FontMetrics, softBreaksOnNewline: Bool = false) -> Int {
		computeSoftLines(metrics: metrics, softBreaksOnNewline: softBreaksOnNewline).count
	}

	/// The soft-line index for the given buffer index.
	public func softLine(
		forIndex index: Int,
		bufferOffset: Int,
		softLineOffset: Int,
		metrics: FontMetrics,
		softBreaksOnNewline: Bool = false,
	) -> Int {
		let softlines = computeSoftLines(metrics: metrics, softBreaksOnNewline: softBreaksOnNewline)
		let needle = index - bufferOffset
		// Find the last soft-line whose offset <= needle
		var result = 0
		for (i, sl) in softlines.enumerated() {
			if sl.offset <= needle {
				result = i
			} else {
				break
			}
		}
		return softLineOffset + result
	}

	// MARK: - Hit Testing

	/// Returns the buffer index at the given point.
	public func indexAtPoint(
		_ point: CGPoint,
		metrics: FontMetrics,
		bufferOffset: Int,
		anchor: CGPoint,
	) -> Int {
		let softlines = computeSoftLines(metrics: metrics)

		for i in 0 ..< softlines.count {
			let sl = softlines[i]
			if anchor.y + sl.y <= point.y, point.y < anchor.y + sl.y + sl.height {
				var x = sl.x
				var offset = sl.offset

				for j in sl.firstNode ..< min(sl.lastNode, nodes.count) {
					let node = nodes[j]

					if node.type == .softBreak {
						return bufferOffset + offset
					} else if node.type == .newline {
						return bufferOffset + offset
					}

					if point.x <= anchor.x + x {
						return bufferOffset + offset
					} else if anchor.x + x < point.x, point.x < anchor.x + x + node.width {
						let delta = point.x - (anchor.x + x)
						if node.type == .text, let ctLine = node.ctLine {
							let idx = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: delta, y: 0))
							return bufferOffset + offset + max(0, idx)
						}
						let fraction = delta / node.width
						return bufferOffset + offset + Int(round(fraction)) * node.length
					}

					x += node.width
					offset += node.length
				}
			}
		}
		return bufferOffset + length
	}

	/// Returns a rect for the caret at the given buffer index.
	public func rectAtIndex(
		_ index: Int,
		carry: Int = 0,
		metrics: FontMetrics,
		bufferOffset: Int,
		anchor: CGPoint,
		bolAsEol: Bool = false,
		wantsBaseline: Bool = false,
	) -> CGRect {
		let needle = index - bufferOffset
		let caretOffset = CGFloat(carry) * metrics.columnWidth
		let softlines = computeSoftLines(metrics: metrics)

		for i in 0 ..< softlines.count {
			let sl = softlines[i]
			let nextOffset = (i + 1 < softlines.count) ? softlines[i + 1].offset : length
			if sl.offset <= needle, i + 1 == softlines.count || needle < nextOffset || (bolAsEol && needle == nextOffset) {
				var x = sl.x
				var offset = sl.offset
				let h = wantsBaseline ? sl.baseline : sl.height

				for j in sl.firstNode ..< min(sl.lastNode, nodes.count) {
					let node = nodes[j]
					if offset <= needle, needle < offset + node.length {
						if node.type == .text, let ctLine = node.ctLine {
							let lineOffset = CGFloat(CTLineGetOffsetForStringIndex(ctLine, needle - offset, nil))
							return CGRect(
								x: anchor.x + x + lineOffset + caretOffset,
								y: anchor.y + sl.y,
								width: metrics.columnWidth,
								height: h,
							)
						}
						let fraction = CGFloat(needle - offset) / CGFloat(max(1, node.length))
						return CGRect(
							x: anchor.x + x + fraction * node.width + caretOffset,
							y: anchor.y + sl.y,
							width: 1,
							height: h,
						)
					}
					x += node.width
					offset += node.length
				}
				return CGRect(x: anchor.x + x + caretOffset, y: anchor.y + sl.y, width: 1, height: h)
			}
		}

		let lastH = wantsBaseline ? (softlines.last?.baseline ?? 0) : (softlines.last?.height ?? 0)
		return CGRect(x: anchor.x + caretOffset, y: anchor.y, width: 1, height: lastH)
	}

	// MARK: - Navigation

	/// Beginning of logical line, accounting for fold nodes.
	public func bol(_ index: Int, bufferOffset: Int) -> Int {
		var i = bufferOffset
		var bol = i
		for node in nodes {
			if index < i { break }
			i += node.length
			if node.type == .softBreak {
				bol = i
			}
		}
		return bol
	}

	/// End of logical line, accounting for fold nodes.
	public func eol(_ index: Int, bufferOffset: Int) -> Int {
		var i = bufferOffset
		for node in nodes {
			if index < i, node.type == .softBreak {
				return i
			}
			if index <= i, node.type == .newline {
				return i
			}
			i += node.length
		}
		return i
	}

	/// Index left of the given position, skipping over folded regions.
	public func indexLeftOf(_ index: Int, bufferOffset: Int, characterSize: (Int) -> Int) -> Int {
		var result = index
		if result != bufferOffset {
			result -= characterSize(result - 1)
		}

		var i = bufferOffset
		for node in nodes {
			if i < result, result < i + node.length, node.type == .folding {
				return i
			}
			i += node.length
		}
		return result
	}

	/// Index right of the given position, skipping over folded regions.
	public func indexRightOf(_ index: Int, bufferOffset: Int, characterSize: (Int) -> Int) -> Int {
		var result = index
		if result != bufferOffset + length {
			result += characterSize(result)
		}

		var i = bufferOffset
		for node in nodes {
			if i < result, result < i + node.length, node.type == .folding {
				return i + node.length
			}
			i += node.length
		}
		return result
	}

	/// Returns the folded range at the given point, if any.
	public func foldedRangeAtPoint(
		_ point: CGPoint,
		metrics: FontMetrics,
		bufferOffset: Int,
		anchor: CGPoint,
	) -> (from: Int, to: Int)? {
		let softlines = computeSoftLines(metrics: metrics)

		for sl in softlines {
			if anchor.y + sl.y <= point.y, point.y < anchor.y + sl.y + sl.height {
				var x = sl.x
				var offset = sl.offset

				for j in sl.firstNode ..< min(sl.lastNode, nodes.count) {
					let node = nodes[j]
					if point.x <= anchor.x + x {
						return nil
					} else if anchor.x + x < point.x, point.x < anchor.x + x + node.width, node.type == .folding {
						return (bufferOffset + offset, bufferOffset + offset + node.length)
					}
					x += node.width
					offset += node.length
				}
			}
		}
		return nil
	}

	/// Returns a line record for gutter view support.
	public func lineRecord(
		forLine line: Int,
		pos: Int,
		metrics: FontMetrics,
		bufferOffset: Int,
		anchor: CGPoint,
	) -> LineRecord {
		let needle = pos - bufferOffset
		let softlines = computeSoftLines(metrics: metrics)
		var y = anchor.y

		for i in 0 ..< softlines.count {
			let sl = softlines[i]
			let nextOffset = (i + 1 < softlines.count) ? softlines[i + 1].offset : length
			let isLast = (i + 1 == softlines.count)
			if (sl.offset <= needle && needle < nextOffset) || isLast {
				return LineRecord(line: line, softline: sl.offset, top: y, bottom: y + sl.height, baseline: sl.baseline)
			}
			y += sl.height
		}
		return LineRecord(line: line, softline: 0, top: 0, bottom: 0, baseline: 0)
	}

	// MARK: - Private Helpers

	/// Find the node boundary at position `i` and return the insertion index,
	/// splitting a text node if necessary.
	private func iteratorAt(_ i: Int) -> Int {
		var from = 0
		for (idx, node) in nodes.enumerated() {
			if from == i {
				return idx
			} else if from < i, i < from + node.length {
				precondition(node.type == .text)
				let remainingLength = node.length - (i - from)
				node.erase(from: i - from, to: node.length)
				nodes.insert(ParagraphNode(type: .text, length: remainingLength), at: idx + 1)
				return idx + 1
			}
			from += node.length
		}
		return nodes.count
	}

	/// Insert a text node at position `i`.
	private func insertText(at i: Int, length len: Int) {
		var from = 0
		for node in nodes {
			if from <= i, i <= from + node.length, node.type == .text {
				if i == from + node.length, node.length >= ParagraphConstants.ctLineMaxSize {
					break
				}
				node.insert(i - from, length: len)
				return
			}
			from += node.length
		}
		let idx = iteratorAt(i)
		nodes.insert(ParagraphNode(type: .text, length: len), at: idx)
	}

	/// Insert an unprintable node at position `i`.
	private func insertUnprintable(at i: Int, length len: Int) {
		let idx = iteratorAt(i)
		nodes.insert(ParagraphNode(type: .unprintable, length: len), at: idx)
	}

	/// Insert a newline node at position `i`.
	private func insertNewline(at i: Int, length len: Int) {
		let idx = iteratorAt(i)
		nodes.insert(ParagraphNode(type: .newline, length: len), at: idx)
	}
}

// MARK: - Paragraph Layout Provider

/// Protocol for providing CTLine factories to the paragraph layout system.
///
/// The paragraph itself doesn't create CTLines directly — it delegates
/// to this provider, which knows about themes, scopes, and buffer content.
public protocol ParagraphLayoutProvider: Sendable {
	/// Returns layout info for the given node.
	///
	/// - Parameters:
	///   - node: The paragraph node to lay out.
	///   - bufferOffset: The node's byte offset within the buffer.
	///   - xPosition: The current x position (for tab stops).
	///   - metrics: The font metrics.
	/// - Returns: Layout info including CTLine factories.
	func layoutInfo(
		for node: ParagraphNode,
		at bufferOffset: Int,
		xPosition: CGFloat,
		metrics: FontMetrics,
	) -> ParagraphNodeLayoutInfo
}
