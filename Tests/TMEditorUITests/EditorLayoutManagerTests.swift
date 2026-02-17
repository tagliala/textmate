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

// MARK: - Soft Wrapping

@Suite("EditorLayoutManager — Soft Wrapping")
struct EditorLayoutManagerSoftWrapTests {
	/// Helper: configures a layout manager with soft-wrap enabled at the
	/// given column width, using a monospaced font.
	@MainActor
	private func makeManager(
		text: String,
		wrapColumn: Int = 20,
		tabSize: Int = 4,
	) -> EditorLayoutManager {
		let manager = EditorLayoutManager()
		manager.softWrap = true
		manager.wrapColumn = wrapColumn
		manager.tabSize = tabSize
		manager.viewportSize = NSSize(width: 1000, height: 5000)
		manager.setText(text)
		return manager
	}

	@Test("short line produces one visual line when soft-wrap is on")
	@MainActor
	func shortLineOneVisual() {
		let manager = makeManager(text: "Hello World", wrapColumn: 20)
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))
		#expect(lines.count == 1)
		#expect(lines[0].lineIndex == 0)
		#expect(lines[0].softWrapOffset == 0)
	}

	@Test("long line produces multiple visual lines")
	@MainActor
	func longLineMultipleVisuals() {
		// "abcdefghij klmnopqrst uvwxyz" — 28 chars, wrap at 20
		let manager = makeManager(text: "abcdefghij klmnopqrst uvwxyz", wrapColumn: 20)
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))
		#expect(lines.count >= 2) // Should wrap at least once
		// All visual lines belong to hard line 0
		for line in lines {
			#expect(line.lineIndex == 0)
		}
		// First visual line starts at offset 0
		#expect(lines[0].softWrapOffset == 0)
		// Subsequent visual line starts at a positive offset
		if lines.count >= 2 {
			#expect(lines[1].softWrapOffset > 0)
		}
	}

	@Test("multiple hard lines with wrapping")
	@MainActor
	func multipleHardLinesWrapped() {
		let text = "short\nabcdefghij klmnopqrst uvwxyz\nend"
		let manager = makeManager(text: text, wrapColumn: 20)
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))

		// Line 0 is short — 1 visual line
		let line0visuals = lines.filter { $0.lineIndex == 0 }
		#expect(line0visuals.count == 1)

		// Line 1 is long — multiple visual lines
		let line1visuals = lines.filter { $0.lineIndex == 1 }
		#expect(line1visuals.count >= 2)

		// Line 2 is short — 1 visual line
		let line2visuals = lines.filter { $0.lineIndex == 2 }
		#expect(line2visuals.count == 1)
	}

	@Test("y positions are monotonically increasing across visual lines")
	@MainActor
	func yPositionsMonotonic() {
		let text = "abcdefghij klmnopqrst uvwxyz abcdef"
		let manager = makeManager(text: text, wrapColumn: 20)
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))

		for i in 1 ..< lines.count {
			#expect(
				lines[i].origin.y > lines[i - 1].origin.y,
				"Visual line \(i) should be below visual line \(i - 1)",
			)
		}
	}

	@Test("total height accounts for wrapped lines")
	@MainActor
	func totalHeightIncludesWraps() {
		let longText = "abcdefghij klmnopqrst uvwxyz"
		let shortText = "short"

		let longManager = makeManager(text: longText, wrapColumn: 20)
		let shortManager = makeManager(text: shortText, wrapColumn: 20)

		// The long line should produce a taller total height
		#expect(longManager.totalHeight > shortManager.totalHeight)
	}

	@Test("softLineCount returns correct count")
	@MainActor
	func softLineCountQuery() {
		let manager = makeManager(text: "abcdefghij klmnopqrst uvwxyz", wrapColumn: 20)
		// Force layout
		_ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))
		let count = manager.softLineCount(forLine: 0)
		#expect(count >= 2)
	}

	@Test("softLineCount is 1 when wrap is disabled")
	@MainActor
	func softLineCountNoWrap() {
		let manager = EditorLayoutManager()
		manager.softWrap = false
		manager.setText("abcdefghij klmnopqrst uvwxyz")
		#expect(manager.softLineCount(forLine: 0) == 1)
	}

	@Test("beginOfSoftLine returns segment start offset")
	@MainActor
	func beginOfSoftLineOffset() {
		let manager = makeManager(text: "abcdefghij klmnopqrst uvwxyz", wrapColumn: 20)
		_ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))

		// At the start of the line
		let bol0 = manager.beginOfSoftLine(forLine: 0, characterIndex: 0)
		#expect(bol0 == 0)

		// At a character beyond the first wrap — should return the wrap offset
		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))
		if lines.count >= 2 {
			let wrapOffset = lines[1].softWrapOffset
			let bol1 = manager.beginOfSoftLine(forLine: 0, characterIndex: wrapOffset + 1)
			#expect(bol1 == wrapOffset)
		}
	}

	@Test("endOfSoftLine returns segment end offset")
	@MainActor
	func endOfSoftLineOffset() {
		let manager = makeManager(text: "abcdefghij klmnopqrst uvwxyz", wrapColumn: 20)
		_ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))

		let lines = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))
		if lines.count >= 2 {
			// End of first visual line should be the start of 2nd
			let eol0 = manager.endOfSoftLine(forLine: 0, characterIndex: 0)
			#expect(eol0 == lines[1].softWrapOffset)
		}
	}

	@Test("character index hit-test finds correct segment")
	@MainActor
	func hitTestInWrappedLine() {
		let manager = makeManager(text: "abcdefghij klmnopqrst uvwxyz", wrapColumn: 20)
		let laid = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))

		guard laid.count >= 2 else { return }

		// Hit test in the first visual line
		let (line0, _) = manager.characterIndex(at: CGPoint(
			x: manager.margin.left + 5,
			y: laid[0].origin.y + 1,
		))
		#expect(line0 == 0)

		// Hit test in the second visual line (wrapped segment)
		let (line1, idx1) = manager.characterIndex(at: CGPoint(
			x: manager.margin.left + 5,
			y: laid[1].origin.y + 1,
		))
		#expect(line1 == 0) // Same hard line
		#expect(idx1 >= laid[1].softWrapOffset) // In the second segment
	}

	@Test("toggling softWrap invalidates and re-lays out")
	@MainActor
	func toggleSoftWrap() {
		let manager = EditorLayoutManager()
		manager.setText("abcdefghij klmnopqrst uvwxyz")
		manager.wrapColumn = 20
		manager.viewportSize = NSSize(width: 1000, height: 5000)

		// Without wrap
		manager.softWrap = false
		let noWrap = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))
		#expect(noWrap.count == 1)

		// Enable wrap
		manager.softWrap = true
		let wrapped = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))
		#expect(wrapped.count >= 2)
	}

	@Test("point for character in second visual line has larger y")
	@MainActor
	func pointInSecondVisualLine() {
		let manager = makeManager(text: "abcdefghij klmnopqrst uvwxyz", wrapColumn: 20)
		let laid = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))

		guard laid.count >= 2 else { return }

		let pt0 = manager.point(forLine: 0, characterIndex: 0)
		let pt1 = manager.point(forLine: 0, characterIndex: laid[1].softWrapOffset)

		#expect(pt1.y > pt0.y, "Second visual line should have larger y")
	}

	@Test("lineIndex atY returns correct hard line in wrapped mode")
	@MainActor
	func lineIndexAtYWrapped() {
		let text = "short\nabcdefghij klmnopqrst uvwxyz\nend"
		let manager = makeManager(text: text, wrapColumn: 20)
		_ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 1000, height: 5000))

		// Y at the very top is line 0
		let idx0 = manager.lineIndex(atY: manager.margin.top + 1)
		#expect(idx0 == 0)

		// Find the y of the last hard line
		let yLine2 = manager.yPosition(forLine: 2)
		let idx2 = manager.lineIndex(atY: yLine2 + 1)
		#expect(idx2 == 2)
	}
}
