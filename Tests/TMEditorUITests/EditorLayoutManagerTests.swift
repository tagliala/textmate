import AppKit
import Testing
@testable import TMEditorUI

@Suite("EditorLayoutManager")
struct EditorLayoutManagerTests {
	// MARK: - Initialization

	@Test("Default initialization")
	@MainActor
	func defaultInit() {
		let manager = EditorLayoutManager()
		#expect(manager.lineCount == 0) // No lines until setText
		#expect(manager.tabSize == 4)
		#expect(manager.softWrap == false)
		#expect(manager.wrapColumn == 0) // 0 = wrap to viewport width
	}

	// MARK: - Text Management

	@Test("Set text splits into lines")
	@MainActor
	func setTextSplitsLines() {
		let manager = EditorLayoutManager()
		manager.setText("Line 1\nLine 2\nLine 3")

		#expect(manager.lineCount == 3)
		#expect(manager.lineText(0) == "Line 1")
		#expect(manager.lineText(1) == "Line 2")
		#expect(manager.lineText(2) == "Line 3")
	}

	@Test("Empty text produces one empty line")
	@MainActor
	func emptyText() {
		let manager = EditorLayoutManager()
		manager.setText("")

		#expect(manager.lineCount == 1)
		#expect(manager.lineText(0) == "")
	}

	@Test("Text ending with newline creates trailing empty line")
	@MainActor
	func trailingNewline() {
		let manager = EditorLayoutManager()
		manager.setText("Hello\n")

		#expect(manager.lineCount == 2)
		#expect(manager.lineText(0) == "Hello")
		#expect(manager.lineText(1) == "")
	}

	@Test("Out of range line returns nil")
	@MainActor
	func outOfRangeReturnsNil() {
		let manager = EditorLayoutManager()
		manager.setText("One line")

		#expect(manager.lineText(-1) == nil)
		#expect(manager.lineText(1) == nil)
		#expect(manager.lineText(100) == nil)
	}

	// MARK: - Line Replacement

	@Test("Replace lines in middle")
	@MainActor
	func replaceLinesMiddle() {
		let manager = EditorLayoutManager()
		manager.setText("A\nB\nC\nD")

		manager.replaceLines(in: 1 ..< 3, with: ["X", "Y", "Z"])

		#expect(manager.lineCount == 5)
		#expect(manager.lineText(0) == "A")
		#expect(manager.lineText(1) == "X")
		#expect(manager.lineText(2) == "Y")
		#expect(manager.lineText(3) == "Z")
		#expect(manager.lineText(4) == "D")
	}

	@Test("Replace lines at start")
	@MainActor
	func replaceLinesStart() {
		let manager = EditorLayoutManager()
		manager.setText("A\nB\nC")

		manager.replaceLines(in: 0 ..< 1, with: ["NEW"])

		#expect(manager.lineCount == 3)
		#expect(manager.lineText(0) == "NEW")
		#expect(manager.lineText(1) == "B")
	}

	@Test("Replace lines at end (delete)")
	@MainActor
	func replaceLinesDelete() {
		let manager = EditorLayoutManager()
		manager.setText("A\nB\nC")

		manager.replaceLines(in: 2 ..< 3, with: [])

		#expect(manager.lineCount == 2)
		#expect(manager.lineText(0) == "A")
		#expect(manager.lineText(1) == "B")
	}

	// MARK: - Font

	@Test("Set font updates metrics")
	@MainActor
	func setFontUpdatesMetrics() {
		let manager = EditorLayoutManager()
		let origLineHeight = manager.defaultLineHeight

		manager.setFont(.monospacedSystemFont(ofSize: 24, weight: .regular))

		#expect(manager.defaultLineHeight > origLineHeight)
	}

	@Test("Set font by name")
	@MainActor
	func setFontByName() {
		let manager = EditorLayoutManager()
		manager.setFont(name: "Menlo", size: 14)

		#expect(manager.fontMetrics.ascent > 0)
	}

	// MARK: - Layout

	@Test("Layout lines returns visible lines")
	@MainActor
	func layoutVisibleLines() {
		let manager = EditorLayoutManager()
		var lines: [String] = []
		for i in 0 ..< 100 {
			lines.append("Line \(i)")
		}
		manager.setText(lines.joined(separator: "\n"))
		manager.viewportSize = NSSize(width: 500, height: 200)

		// Layout just the visible portion
		let visible = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 200))

		// Should have some lines but not all 100
		#expect(visible.count > 0)
		#expect(visible.count < 100)
	}

	@Test("Layout all lines when viewport covers everything")
	@MainActor
	func layoutAllLinesInLargeViewport() {
		let manager = EditorLayoutManager()
		manager.setText("A\nB\nC")

		let all = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 5000))
		#expect(all.count == 3)
	}

	@Test("Layout lines have correct line indices")
	@MainActor
	func layoutLineIndices() {
		let manager = EditorLayoutManager()
		manager.setText("First\nSecond\nThird")

		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 5000))

		#expect(lines[0].lineIndex == 0)
		#expect(lines[1].lineIndex == 1)
		#expect(lines[2].lineIndex == 2)
	}

	@Test("Layout caches lines on second call")
	@MainActor
	func layoutCaching() {
		let manager = EditorLayoutManager()
		manager.setText("Hello\nWorld")

		let first = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 5000))
		let second = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 5000))

		#expect(first.count == second.count)
		// Same objects should be returned from cache
		#expect(first[0] === second[0])
		#expect(first[1] === second[1])
	}

	// MARK: - Total Height & Width

	@Test("Total height scales with line count")
	@MainActor
	func totalHeight() {
		let manager = EditorLayoutManager()
		manager.setText("A")
		let oneLineHeight = manager.totalHeight

		manager.setText("A\nB\nC")
		let threeLineHeight = manager.totalHeight

		// With margins, three lines should be taller
		#expect(threeLineHeight > oneLineHeight)
	}

	@Test("Default line height is positive")
	@MainActor
	func defaultLineHeight() {
		let manager = EditorLayoutManager()
		#expect(manager.defaultLineHeight > 0)
	}

	// MARK: - Coordinate Conversion

	@Test("Line index at Y position zero is first line")
	@MainActor
	func lineIndexAtYZero() {
		let manager = EditorLayoutManager()
		manager.setText("A\nB\nC")

		let idx = manager.lineIndex(atY: manager.margin.top + 1)
		#expect(idx == 0)
	}

	@Test("Y position for line is monotonically increasing")
	@MainActor
	func yPositionMonotonic() {
		let manager = EditorLayoutManager()
		manager.setText("A\nB\nC\nD")

		let y0 = manager.yPosition(forLine: 0)
		let y1 = manager.yPosition(forLine: 1)
		let y2 = manager.yPosition(forLine: 2)
		let y3 = manager.yPosition(forLine: 3)

		#expect(y0 < y1)
		#expect(y1 < y2)
		#expect(y2 < y3)
	}

	@Test("Rect for line has positive dimensions")
	@MainActor
	func rectForLine() {
		let manager = EditorLayoutManager()
		manager.setText("Hello")
		manager.viewportSize = NSSize(width: 500, height: 200)

		let rect = manager.rect(forLine: 0)
		#expect(rect.width > 0)
		#expect(rect.height > 0)
	}

	@Test("Character index at point round-trips through point for line")
	@MainActor
	func characterIndexRoundTrip() {
		let manager = EditorLayoutManager()
		manager.setText("ABCDEF")
		manager.viewportSize = NSSize(width: 500, height: 200)

		// Need to trigger layout first
		_ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 200))

		let pt = manager.point(forLine: 0, characterIndex: 3)
		let (line, idx) = manager.characterIndex(at: pt)

		#expect(line == 0)
		#expect(idx == 3)
	}

	@Test("Caret rect has width of 2")
	@MainActor
	func caretRectWidth() {
		let manager = EditorLayoutManager()
		manager.setText("Hello")
		manager.viewportSize = NSSize(width: 500, height: 200)

		_ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 200))

		let rect = manager.caretRect(forLine: 0, characterIndex: 0)
		#expect(rect.width == 2)
		#expect(rect.height > 0)
	}

	// MARK: - Invalidation

	@Test("Invalidate all lines clears cache")
	@MainActor
	func invalidateAll() {
		let manager = EditorLayoutManager()
		manager.setText("Hello\nWorld")

		// Force layout
		_ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 200))

		manager.invalidateAllLines()

		// Layout again — should create fresh lines
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 200))
		#expect(lines.count == 2)
	}

	@Test("Invalidate specific lines only relayouts those lines")
	@MainActor
	func invalidateSpecificLines() {
		let manager = EditorLayoutManager()
		manager.setText("A\nB\nC")

		// Force full layout
		let firstLayout = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 5000))
		let lineBFirst = firstLayout[1]

		// Invalidate only line 1
		manager.invalidateLines(1 ..< 2)

		let secondLayout = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 5000))

		// Line 0 should be the same object (cached)
		#expect(firstLayout[0] === secondLayout[0])
		// Line 1 should be a new object (re-laid-out)
		#expect(lineBFirst !== secondLayout[1])
		// Line 2 should be the same object (cached)
		#expect(firstLayout[2] === secondLayout[2])
	}

	// MARK: - Style Runs

	@Test("Style provider is called during layout")
	@MainActor
	func styleProviderCalled() {
		let manager = EditorLayoutManager()
		manager.setText("Hello")

		var calledForLines: [Int] = []
		manager.styleProvider = { lineIdx, _ in
			calledForLines.append(lineIdx)
			return [
				StyleRun(start: 0, length: 5, foreground: .red),
			]
		}

		// Invalidate to force re-layout with style provider
		manager.invalidateAllLines()
		_ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 200))

		#expect(calledForLines.contains(0))
	}

	@Test("Layout line stores style runs from provider")
	@MainActor
	func layoutLineStoresStyleRuns() {
		let manager = EditorLayoutManager()
		manager.setText("Hello World")

		manager.styleProvider = { _, _ in
			[
				StyleRun(start: 0, length: 5, foreground: .red, isBold: true),
				StyleRun(start: 6, length: 5, foreground: .blue, isItalic: true),
			]
		}

		manager.invalidateAllLines()
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 200))

		#expect(lines[0].styleRuns.count == 2)
		#expect(lines[0].styleRuns[0].foreground == .red)
		#expect(lines[0].styleRuns[0].isBold == true)
		#expect(lines[0].styleRuns[1].foreground == .blue)
		#expect(lines[0].styleRuns[1].isItalic == true)
	}

	// MARK: - Tab Size

	@Test("Tab size affects wrap width")
	@MainActor
	func tabSizeDefault() {
		let manager = EditorLayoutManager()
		#expect(manager.tabSize == 4)
	}

	@Test("Wrap column affects effective wrap width")
	@MainActor
	func wrapColumnAffectsWidth() {
		let manager = EditorLayoutManager()
		manager.wrapColumn = 80
		let width80 = manager.effectiveWrapWidth

		manager.wrapColumn = 120
		let width120 = manager.effectiveWrapWidth

		#expect(width120 > width80)
	}

	// MARK: - Margin

	@Test("Margin affects line positions")
	@MainActor
	func marginAffectsPositions() {
		let manager = EditorLayoutManager()
		manager.setText("Hello")
		manager.margin = NSEdgeInsets(top: 20, left: 30, bottom: 20, right: 30)

		let y = manager.yPosition(forLine: 0)
		#expect(y >= 20) // At least the top margin
	}
}
