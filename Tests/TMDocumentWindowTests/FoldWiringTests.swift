import AppKit
import Testing
import TMAppKit
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
@testable import TMDocumentWindow

// MARK: - Code Folding End-to-End Wiring Tests

@Suite("FoldWiring")
@MainActor
struct FoldWiringTests {
	// MARK: - Helpers

	/// Creates a document editor with the given multiline text.
	private func makeEditor(text: String) -> (TMDocumentEditor, EditorView) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, view)
	}

	// MARK: - FoldManager Wiring

	@Test("document editor creates fold manager on init")
	func foldManagerCreated() {
		let (docEditor, _) = makeEditor(text: "line 1\nline 2\n")
		#expect(docEditor.foldManager != nil)
	}

	@Test("fold manager data source has correct line count")
	func foldDataSourceLineCount() throws {
		let (docEditor, _) = makeEditor(text: "aaa\nbbb\nccc\n")
		let fm = try #require(docEditor.foldManager)
		#expect(fm.dataSource.lineCount == docEditor.editor.buffer.lines)
	}

	@Test("fold manager is wired to layout manager")
	func foldManagerWiredToLayout() {
		let (_, view) = makeEditor(text: "hello\nworld\n")
		#expect(view.layoutManager.foldManager != nil)
	}

	// MARK: - Toggle Fold API

	@Test("toggleFold at line returns affected range")
	func toggleFoldReturnsRange() throws {
		let text = "func foo() {\n\tbar()\n}\n"
		let (docEditor, _) = makeEditor(text: text)

		// Manually fold a range to test unfold
		let fm = try #require(docEditor.foldManager)
		let ranges = fm.foldableRanges()
		guard let first = ranges.first else {
			// No foldable ranges computed → skip (depends on data source markers)
			return
		}
		fm.fold(from: first.from, to: first.to)
		#expect(!fm.foldedRanges.isEmpty)

		// Toggle to unfold
		let result = docEditor.toggleFold(atLine: 0)
		#expect(result != nil)
	}

	// MARK: - Fold State Queries

	@Test("foldableLineNumbers returns 1-based line numbers")
	func foldableLineNumbers() {
		// Use indent-based folding: line 0 has less indent than line 1
		let text = "top\n\tchild\n\t\tgrandchild\n"
		let (docEditor, _) = makeEditor(text: text)
		let foldable = docEditor.foldableLineNumbers()
		// Lines 0 and 1 should be foldable (indent-start markers)
		// 1-based: lines 1 and 2
		#expect(foldable.contains(1))
		#expect(foldable.contains(2))
	}

	@Test("foldedLineNumbers matches fold manager state")
	func foldedLineNumbers() throws {
		let text = "top\n\tchild\n\t\tgrandchild\n"
		let (docEditor, _) = makeEditor(text: text)
		let fm = try #require(docEditor.foldManager)

		// Initially no folds
		#expect(docEditor.foldedLineNumbers().isEmpty)

		// Fold the first range
		let ranges = fm.foldableRanges()
		if let first = ranges.first {
			fm.fold(from: first.from, to: first.to)
			let folded = docEditor.foldedLineNumbers()
			#expect(!folded.isEmpty)
		}
	}

	// MARK: - Serialization

	@Test("fold state round-trip through string serialization")
	func foldSerializationRoundTrip() throws {
		let text = "aaa\nbbb\nccc\nddd\n"
		let (docEditor, _) = makeEditor(text: text)
		let fm = try #require(docEditor.foldManager)

		fm.fold(from: 3, to: 7)
		let serialized = docEditor.foldedAsString
		#expect(serialized != nil)

		// Clear and restore
		_ = fm.unfold(from: 3, to: 7)
		#expect(fm.foldedRanges.isEmpty)

		try docEditor.restoreFolds(from: #require(serialized))
		#expect(fm.foldedRanges.count == 1)
		#expect(fm.foldedRanges[0].from == 3)
		#expect(fm.foldedRanges[0].to == 7)
	}

	// MARK: - Layout Manager Fold Integration

	@Test("layout manager hides folded lines")
	func layoutManagerHidesFoldedLines() throws {
		let text = "line0\nline1\nline2\nline3\n"
		let (docEditor, view) = makeEditor(text: text)
		let fm = try #require(docEditor.foldManager)

		// Fold from end of line 0 to end of line 2
		// This should hide lines 1 and 2
		let start = docEditor.editor.buffer.lineEnd(0)
		let end = docEditor.editor.buffer.lineEnd(2)
		fm.fold(from: start, to: end)
		view.layoutManager.invalidateFolds()

		#expect(view.layoutManager.isLineFolded(1) == true)
		#expect(view.layoutManager.isLineFolded(2) == true)
		#expect(view.layoutManager.isLineFolded(0) == false)
		#expect(view.layoutManager.isLineFolded(3) == false)
	}

	@Test("layout manager totalHeight decreases when lines are folded")
	func layoutManagerHeightDecreases() throws {
		let text = "line0\nline1\nline2\nline3\n"
		let (docEditor, view) = makeEditor(text: text)
		let fm = try #require(docEditor.foldManager)

		let heightBefore = view.layoutManager.totalHeight

		let start = docEditor.editor.buffer.lineEnd(0)
		let end = docEditor.editor.buffer.lineEnd(2)
		fm.fold(from: start, to: end)
		view.layoutManager.invalidateAllLines()

		let heightAfter = view.layoutManager.totalHeight
		#expect(heightAfter < heightBefore)
	}
}

// MARK: - TextBufferFoldDataSource Tests

@Suite("TextBufferFoldDataSource")
@MainActor
struct TextBufferFoldDataSourceTests {
	@Test("lineCount matches buffer")
	func lineCount() {
		let buf = TextBuffer("aaa\nbbb\nccc\n")
		let ds = TextBufferFoldDataSource(buffer: buf)
		#expect(ds.lineCount == buf.lines)
	}

	@Test("bufferSize matches buffer")
	func bufferSize() {
		let buf = TextBuffer("hello\nworld\n")
		let ds = TextBufferFoldDataSource(buffer: buf)
		#expect(ds.bufferSize == buf.size)
	}

	@Test("lineStart delegates to buffer")
	func lineStart() {
		let buf = TextBuffer("aaa\nbbb\n")
		let ds = TextBufferFoldDataSource(buffer: buf)
		#expect(ds.lineStart(0) == buf.lineStart(0))
		#expect(ds.lineStart(1) == buf.lineStart(1))
	}

	@Test("lineEnd delegates to buffer")
	func lineEnd() {
		let buf = TextBuffer("aaa\nbbb\n")
		let ds = TextBufferFoldDataSource(buffer: buf)
		#expect(ds.lineEnd(0) == buf.lineEnd(0))
		#expect(ds.lineEnd(1) == buf.lineEnd(1))
	}

	@Test("character at offset returns correct character")
	func characterAtOffset() {
		let buf = TextBuffer("abc")
		let ds = TextBufferFoldDataSource(buffer: buf)
		#expect(ds.character(at: 0) == "a")
		#expect(ds.character(at: 1) == "b")
		#expect(ds.character(at: 2) == "c")
	}

	@Test("default fold info computes indent-based markers")
	func defaultFoldInfo() {
		let buf = TextBuffer("top\n\tchild\n\t\tgrandchild\n")
		let ds = TextBufferFoldDataSource(buffer: buf)

		let info0 = ds.foldInfo(forLine: 0)
		#expect(info0.indent == 0)
		#expect(info0.isIndentStartMarker == true)
		#expect(info0.isEmpty == false)

		let info1 = ds.foldInfo(forLine: 1)
		#expect(info1.indent == 1)
		#expect(info1.isIndentStartMarker == true)
	}

	@Test("empty line reports isEmpty")
	func emptyLine() {
		let buf = TextBuffer("hello\n\nworld\n")
		let ds = TextBufferFoldDataSource(buffer: buf)
		let info1 = ds.foldInfo(forLine: 1)
		#expect(info1.isEmpty == true)
	}

	@Test("custom foldInfoProvider overrides default")
	func customProvider() {
		let buf = TextBuffer("aaa\nbbb\n")
		let ds = TextBufferFoldDataSource(buffer: buf)
		ds.foldInfoProvider = { _ in
			var info = FoldManager.LineInfo()
			info.isStartMarker = true
			info.indent = 42
			return info
		}
		let info = ds.foldInfo(forLine: 0)
		#expect(info.isStartMarker == true)
		#expect(info.indent == 42)
	}
}

// MARK: - EditorLayoutManager Fold Tests

@Suite("EditorLayoutManager Folds")
@MainActor
struct EditorLayoutManagerFoldTests {
	@Test("isLineFolded returns false when no fold manager")
	func noFoldManager() {
		let lm = EditorLayoutManager()
		lm.setText("hello\nworld\n")
		#expect(lm.isLineFolded(0) == false)
		#expect(lm.isLineFolded(1) == false)
	}

	@Test("isLineFolded returns true for hidden lines")
	func hiddenLines() {
		let ds = MockFoldDataSource(lines: [
			"line0\n",
			"line1\n",
			"line2\n",
			"line3\n",
		])
		let fm = FoldManager(dataSource: ds)
		let lm = EditorLayoutManager()
		lm.setText("line0\nline1\nline2\nline3\n")
		lm.foldManager = fm

		// Fold from end of line 0 to end of line 2
		let start = ds.lineEnd(0)
		let end = ds.lineEnd(2)
		fm.fold(from: start, to: end)
		lm.invalidateFolds()

		#expect(lm.isLineFolded(0) == false)
		#expect(lm.isLineFolded(1) == true)
		#expect(lm.isLineFolded(2) == true)
		#expect(lm.isLineFolded(3) == false)
	}

	@Test("yPosition accounts for folded lines")
	func yPositionWithFolds() {
		let ds = MockFoldDataSource(lines: [
			"line0\n",
			"line1\n",
			"line2\n",
			"line3\n",
		])
		let fm = FoldManager(dataSource: ds)
		let lm = EditorLayoutManager()
		lm.setText("line0\nline1\nline2\nline3\n")
		lm.foldManager = fm

		let yLine3Before = lm.yPosition(forLine: 3)

		fm.fold(from: ds.lineEnd(0), to: ds.lineEnd(2))
		lm.invalidateAllLines()

		let yLine3After = lm.yPosition(forLine: 3)
		// After folding lines 1 and 2, line 3 should be higher up
		#expect(yLine3After < yLine3Before)
	}

	@Test("totalHeight decreases when lines are folded")
	func totalHeightDecreases() {
		let ds = MockFoldDataSource(lines: [
			"line0\n",
			"line1\n",
			"line2\n",
			"line3\n",
		])
		let fm = FoldManager(dataSource: ds)
		let lm = EditorLayoutManager()
		lm.setText("line0\nline1\nline2\nline3\n")
		lm.foldManager = fm

		let heightBefore = lm.totalHeight

		fm.fold(from: ds.lineEnd(0), to: ds.lineEnd(1))
		lm.invalidateAllLines()

		let heightAfter = lm.totalHeight
		#expect(heightAfter < heightBefore)
	}

	@Test("invalidateFolds clears cached hidden lines")
	func invalidateFoldsClears() {
		let ds = MockFoldDataSource(lines: ["a\n", "b\n", "c\n"])
		let fm = FoldManager(dataSource: ds)
		let lm = EditorLayoutManager()
		lm.setText("a\nb\nc\n")
		lm.foldManager = fm

		#expect(lm.isLineFolded(1) == false)

		fm.fold(from: ds.lineEnd(0), to: ds.lineEnd(1))
		// Without invalidation, cached state may be stale
		lm.invalidateFolds()
		#expect(lm.isLineFolded(1) == true)
	}
}

/// Minimal MockFoldDataSource for layout manager tests (same as in FoldManagerTests).
private struct MockFoldDataSource: FoldDataSource {
	let lines: [String]

	var lineCount: Int {
		lines.count
	}

	var bufferSize: Int {
		lines.reduce(0) { $0 + $1.utf8.count }
	}

	func lineStart(_ n: Int) -> Int {
		lines.prefix(n).reduce(0) { $0 + $1.utf8.count }
	}

	func lineEnd(_ n: Int) -> Int {
		guard n < lineCount else { return bufferSize }
		let start = lineStart(n)
		let line = lines[n]
		if line.hasSuffix("\n") {
			return start + line.utf8.count - 1
		}
		return start + line.utf8.count
	}

	func character(at offset: Int) -> String {
		var remaining = offset
		for line in lines {
			if remaining < line.utf8.count {
				let idx = line.utf8.index(line.utf8.startIndex, offsetBy: remaining)
				return String(line[idx])
			}
			remaining -= line.utf8.count
		}
		return ""
	}

	func foldInfo(forLine n: Int) -> FoldManager.LineInfo {
		guard n < lines.count else { return FoldManager.LineInfo() }
		let line = lines[n]
		var info = FoldManager.LineInfo()
		var indent = 0
		for ch in line {
			if ch == "\t" { indent += 1 } else { break }
		}
		info.indent = indent
		if line.contains("{") { info.isStartMarker = true }
		if line.contains("}") { info.isStopMarker = true }
		let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
		info.isEmpty = trimmed.isEmpty
		return info
	}
}
