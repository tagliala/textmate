import CoreGraphics
import Testing
@testable import TMEditorUI

@Suite("LayoutParagraph")
struct LayoutParagraphTests {
	// MARK: - ParagraphNodeType

	@Test("ParagraphNodeType has all expected cases")
	func nodeTypeCases() {
		let types: [ParagraphNodeType] = [.text, .unprintable, .folding, .softBreak, .newline]
		#expect(types.count == 5)
	}

	// MARK: - ParagraphNode

	@Test("ParagraphNode stores type and length")
	func nodeProperties() {
		let node = ParagraphNode(type: .text, length: 42)
		#expect(node.type == .text)
		#expect(node.length == 42)
	}

	@Test("ParagraphNode insert increases length")
	func nodeInsert() {
		let node = ParagraphNode(type: .text, length: 10)
		node.insert(5, length: 3)
		#expect(node.length == 13)
	}

	@Test("ParagraphNode erase decreases length")
	func nodeErase() {
		let node = ParagraphNode(type: .text, length: 10)
		node.erase(from: 2, to: 5)
		#expect(node.length == 7)
	}

	@Test("ParagraphNode folding type has fixed width")
	func foldingNodeWidth() {
		let node = ParagraphNode(type: .folding, length: 100, width: 25)
		#expect(node.width == 25)
	}

	@Test("ParagraphNode text type width is 0 before layout")
	func textNodeWidthBeforeLayout() {
		let node = ParagraphNode(type: .text, length: 10)
		#expect(node.width == 0) // No CTLine yet
	}

	// MARK: - ParagraphConstants

	@Test("Constants have expected values")
	func constantValues() {
		#expect(ParagraphConstants.ctLineMaxSize == 2048)
		#expect(ParagraphConstants.foldingDotsRatio == 20.0 / 10.0)
	}

	// MARK: - SoftLine

	@Test("SoftLine stores all properties")
	func softLineProperties() {
		let sl = SoftLine(offset: 10, x: 5, y: 20, baseline: 12, height: 16, firstNode: 0, lastNode: 3)
		#expect(sl.offset == 10)
		#expect(sl.x == 5)
		#expect(sl.y == 20)
		#expect(sl.baseline == 12)
		#expect(sl.height == 16)
		#expect(sl.firstNode == 0)
		#expect(sl.lastNode == 3)
	}

	// MARK: - LineRecord

	@Test("LineRecord stores gutter info")
	func lineRecordProperties() {
		let lr = LineRecord(line: 5, softline: 2, top: 100, bottom: 116, baseline: 112)
		#expect(lr.line == 5)
		#expect(lr.softline == 2)
		#expect(lr.top == 100)
		#expect(lr.bottom == 116)
		#expect(lr.baseline == 112)
	}

	// MARK: - LayoutParagraph Basic Operations

	@Test("Empty paragraph has zero length")
	func emptyParagraphLength() {
		let para = LayoutParagraph()
		#expect(para.length == 0)
	}

	@Test("Paragraph needs layout when created")
	func paragraphNeedsLayoutInitially() {
		let para = LayoutParagraph()
		#expect(para.needsLayout == true)
	}

	@Test("Insert text increases paragraph length")
	func insertTextLength() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 5, text: "Hello", bufferOffset: 0)
		#expect(para.length == 5)
	}

	@Test("Insert text with newline creates multiple nodes")
	func insertTextWithNewline() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 6, text: "Hi\nBye", bufferOffset: 0)
		// "Hi" (2 bytes text) + "\n" (1 byte newline) + "Bye" (3 bytes text) = 6
		#expect(para.length == 6)
	}

	@Test("Insert text with control characters creates unprintable nodes")
	func insertTextWithUnprintable() {
		let para = LayoutParagraph()
		// Text with a NUL character in the middle
		let text = "A\u{00}B"
		para.insert(pos: 0, length: text.utf8.count, text: text, bufferOffset: 0)
		#expect(para.length == text.utf8.count)
	}

	@Test("Insert folded region")
	func insertFolded() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 10, text: "0123456789", bufferOffset: 0)
		para.insertFolded(pos: 3, length: 4, bufferOffset: 0)
		#expect(para.length == 14) // 10 original + 4 folded
	}

	@Test("Erase range removes bytes from paragraph")
	func eraseRange() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 10, text: "0123456789", bufferOffset: 0)
		para.erase(from: 3, to: 7, bufferOffset: 0)
		#expect(para.length == 6)
	}

	// MARK: - Navigation

	@Test("bol returns beginning of line")
	func bolNavigation() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 5, text: "Hello", bufferOffset: 0)
		#expect(para.bol(3, bufferOffset: 0) == 0)
	}

	@Test("eol returns end of line")
	func eolNavigation() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 6, text: "Hello\n", bufferOffset: 0)
		#expect(para.eol(3, bufferOffset: 0) == 5)
	}

	// MARK: - Soft Lines

	@Test("Single text node produces one soft line")
	func singleTextOneSoftLine() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 5, text: "Hello", bufferOffset: 0)
		let metrics = FontMetrics(fontName: "Menlo", fontSize: 12)
		let softlines = para.computeSoftLines(metrics: metrics)
		#expect(softlines.count == 1)
		#expect(softlines[0].offset == 0)
		#expect(softlines[0].firstNode == 0)
	}

	@Test("Soft line count matches computeSoftLines")
	func softLineCountConsistency() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 5, text: "Hello", bufferOffset: 0)
		let metrics = FontMetrics(fontName: "Menlo", fontSize: 12)
		let count = para.softLineCount(metrics: metrics)
		let softlines = para.computeSoftLines(metrics: metrics)
		#expect(count == softlines.count)
	}

	// MARK: - DecorationRun

	@Test("DecorationRun stores properties")
	func decorationRunProperties() {
		let run = DecorationRun(location: 5, length: 10, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
		#expect(run.location == 5)
		#expect(run.length == 10)
	}

	// MARK: - MisspelledRange

	@Test("MisspelledRange stores byte offsets")
	func misspelledRangeProperties() {
		let range = MisspelledRange(from: 3, to: 8)
		#expect(range.from == 3)
		#expect(range.to == 8)
	}

	// MARK: - Index Navigation with Folding

	@Test("indexLeftOf skips folded region")
	func indexLeftOfSkipsFold() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 10, text: "0123456789", bufferOffset: 0)
		para.insertFolded(pos: 3, length: 4, bufferOffset: 0)
		// Character size callback: returns 1 for all single-byte chars
		let idx = para.indexLeftOf(7, bufferOffset: 0) { _ in 1 }
		// 7 is inside the folded node (3..<7), so left should jump to fold start
		#expect(idx == 3)
	}

	@Test("indexRightOf skips folded region")
	func indexRightOfSkipsFold() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 10, text: "0123456789", bufferOffset: 0)
		para.insertFolded(pos: 3, length: 4, bufferOffset: 0)
		// Character size callback: returns 1 for all single-byte chars
		let idx = para.indexRightOf(3, bufferOffset: 0) { _ in 1 }
		// 4 (3+1) would be inside the folded node (3..<7), so right should jump to fold end
		#expect(idx == 7)
	}

	// MARK: - Hit Testing

	@Test("indexAtPoint returns bufferOffset + length for point past end")
	func indexAtPointPastEnd() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 5, text: "Hello", bufferOffset: 0)
		let metrics = FontMetrics(fontName: "Menlo", fontSize: 12)
		let idx = para.indexAtPoint(
			CGPoint(x: 99999, y: 99999),
			metrics: metrics,
			bufferOffset: 0,
			anchor: .zero,
		)
		#expect(idx == 5) // bufferOffset + length
	}

	@Test("rectAtIndex returns valid rectangle")
	func rectAtIndexReturnsRect() {
		let para = LayoutParagraph()
		para.insert(pos: 0, length: 5, text: "Hello", bufferOffset: 0)
		let metrics = FontMetrics(fontName: "Menlo", fontSize: 12)
		let rect = para.rectAtIndex(
			0,
			metrics: metrics,
			bufferOffset: 0,
			anchor: .zero,
		)
		#expect(rect.origin.x >= 0)
		#expect(rect.height > 0)
	}

	// MARK: - ParagraphNodeLayoutInfo

	@Test("ParagraphNodeLayoutInfo stores properties")
	func layoutInfoProperties() {
		let info = ParagraphNodeLayoutInfo(
			text: "Hello",
			createTextLine: { nil },
			createUnprintableLine: { nil },
			createSoftBreakLine: { nil },
			capHeight: 8.0,
		)
		#expect(info.text == "Hello")
		#expect(info.capHeight == 8.0)
	}
}
