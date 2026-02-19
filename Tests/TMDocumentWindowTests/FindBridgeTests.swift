import AppKit
import Testing
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMSearchReplace
@testable import TMDocumentWindow

// MARK: - Find Bridge Tests

@Suite("FindBridge")
@MainActor
struct FindBridgeTests {
	// MARK: - Helpers

	private func makeEditor(text: String) -> (TMDocumentEditor, EditorView) {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let editor = TMDocumentEditor(document: doc, editorView: view)
		return (editor, view)
	}

	// MARK: - findNext

	@Test("findNext selects first match and returns position")
	func findNextSelectsMatch() {
		let (de, _) = makeEditor(text: "hello world hello")
		let result = de.findNext(pattern: "hello", options: [.wrapAround])
		#expect(result.count == 1)
		#expect(result.line == 0)
		#expect(result.column == 0)
		#expect(de.editor.selectedText == "hello")
	}

	@Test("findNext advances past current match")
	func findNextAdvances() {
		let (de, _) = makeEditor(text: "aa bb aa")
		_ = de.findNext(pattern: "aa", options: [.wrapAround])
		#expect(de.editor.selections.primary?.start.offset == 0)

		let result = de.findNext(pattern: "aa", options: [.wrapAround])
		#expect(result.count == 1)
		#expect(de.editor.selections.primary?.start.offset == 6)
	}

	@Test("findNext wraps around")
	func findNextWraps() {
		let (de, _) = makeEditor(text: "aa bb aa")
		_ = de.findNext(pattern: "aa", options: [.wrapAround])
		_ = de.findNext(pattern: "aa", options: [.wrapAround])
		let result = de.findNext(pattern: "aa", options: [.wrapAround])
		#expect(result.wrapped == true)
		#expect(de.editor.selections.primary?.start.offset == 0)
	}

	@Test("findNext with no match returns zero count")
	func findNextNoMatch() {
		let (de, _) = makeEditor(text: "hello world")
		let result = de.findNext(pattern: "xyz", options: [.wrapAround])
		#expect(result.count == 0)
	}

	@Test("findNext case insensitive")
	func findNextIgnoreCase() {
		let (de, _) = makeEditor(text: "Hello HELLO hello")
		let result = de.findNext(pattern: "hello", options: [.wrapAround, .ignoreCase])
		#expect(result.count == 1)
		#expect(de.editor.selectedText == "Hello")
	}

	@Test("findNext with regex")
	func findNextRegex() {
		let (de, _) = makeEditor(text: "foo123 bar456")
		let result = de.findNext(pattern: "\\d+", options: [.wrapAround, .regularExpression])
		#expect(result.count == 1)
		#expect(de.editor.selectedText == "123")
	}

	// MARK: - findAll

	@Test("findAll selects all matches")
	func findAllSelectsAll() {
		let (de, _) = makeEditor(text: "aa bb aa cc aa")
		let count = de.findAll(pattern: "aa", options: [])
		#expect(count == 3)
		#expect(de.editor.selections.count == 3)
	}

	@Test("findAll in selection")
	func findAllInSelection() {
		let (de, _) = makeEditor(text: "aa bb aa cc aa")
		// Select "aa bb aa" (bytes 0..<8)
		de.editor.selections = SelectionState([
			TextRange(
				anchor: de.editor.buffer.convert(offset: 0),
				head: de.editor.buffer.convert(offset: 8),
			),
		])
		let count = de.findAll(pattern: "aa", options: [], inSelection: true)
		#expect(count == 2)
		#expect(de.editor.selections.count == 2)
	}

	@Test("findAll with no matches returns zero")
	func findAllNoMatch() {
		let (de, _) = makeEditor(text: "hello world")
		let count = de.findAll(pattern: "xyz", options: [])
		#expect(count == 0)
	}

	// MARK: - countMatches

	@Test("countMatches returns count without changing selection")
	func countMatchesNoSelection() {
		let (de, _) = makeEditor(text: "aa bb aa cc aa")
		let originalSel = de.editor.selections
		let count = de.countMatches(pattern: "aa", options: [])
		#expect(count == 3)
		#expect(de.editor.selections == originalSel)
	}

	// MARK: - replaceCurrent

	@Test("replaceCurrent replaces selected text")
	func replaceCurrentBasic() {
		let (de, _) = makeEditor(text: "hello world")
		_ = de.findNext(pattern: "hello", options: [.wrapAround])
		de.replaceCurrent(with: "goodbye")
		#expect(de.editor.text == "goodbye world")
	}

	@Test("replaceCurrent with regex captures")
	func replaceCurrentCaptures() {
		let (de, _) = makeEditor(text: "John Smith")
		_ = de.findNext(pattern: "(\\w+) (\\w+)", options: [.wrapAround, .regularExpression])
		de.replaceCurrent(with: "$2, $1")
		#expect(de.editor.text == "Smith, John")
	}

	@Test("replaceCurrent without selection does nothing")
	func replaceCurrentNoSelection() {
		let (de, _) = makeEditor(text: "hello")
		de.replaceCurrent(with: "bye")
		#expect(de.editor.text == "hello")
	}

	// MARK: - replaceAll

	@Test("replaceAll replaces all occurrences")
	func replaceAllBasic() {
		let (de, _) = makeEditor(text: "aa bb aa cc aa")
		let count = de.replaceAll(pattern: "aa", replacement: "xx", options: [])
		#expect(count == 3)
		#expect(de.editor.text == "xx bb xx cc xx")
	}

	@Test("replaceAll in selection")
	func replaceAllInSelection() {
		let (de, _) = makeEditor(text: "aa bb aa cc aa")
		de.editor.selections = SelectionState([
			TextRange(
				anchor: de.editor.buffer.convert(offset: 0),
				head: de.editor.buffer.convert(offset: 8),
			),
		])
		let count = de.replaceAll(
			pattern: "aa", replacement: "xx", options: [], inSelection: true,
		)
		#expect(count == 2)
		#expect(de.editor.text == "xx bb xx cc aa")
	}

	@Test("replaceAll with no matches returns zero")
	func replaceAllNoMatch() {
		let (de, _) = makeEditor(text: "hello world")
		let count = de.replaceAll(pattern: "xyz", replacement: "abc", options: [])
		#expect(count == 0)
		#expect(de.editor.text == "hello world")
	}

	// MARK: - allMatchRanges

	@Test("allMatchRanges returns byte ranges for highlighting")
	func allMatchRangesBasic() {
		let (de, _) = makeEditor(text: "aa bb aa")
		let ranges = de.allMatchRanges(pattern: "aa", options: [])
		#expect(ranges.count == 2)
		#expect(ranges[0] == 0 ..< 2)
		#expect(ranges[1] == 6 ..< 8)
	}

	@Test("allMatchRanges does not change selection")
	func allMatchRangesPreservesSelection() {
		let (de, _) = makeEditor(text: "aa bb aa")
		let originalSel = de.editor.selections
		_ = de.allMatchRanges(pattern: "aa", options: [])
		#expect(de.editor.selections == originalSel)
	}

	// MARK: - Match Captures Storage

	@Test("findNext stores match captures for regex")
	func matchCapturesStored() {
		let (de, _) = makeEditor(text: "hello world")
		_ = de.findNext(pattern: "(hello) (world)", options: [.regularExpression])
		#expect(de.matchCaptures["1"] == "hello")
		#expect(de.matchCaptures["2"] == "world")
	}

	@Test("replaceCurrent clears captures after replacement")
	func capturesClearedAfterReplace() {
		let (de, _) = makeEditor(text: "hello world")
		_ = de.findNext(pattern: "(hello)", options: [.regularExpression, .wrapAround])
		#expect(!de.matchCaptures.isEmpty)
		de.replaceCurrent(with: "bye")
		#expect(de.matchCaptures.isEmpty)
	}

	// MARK: - Highlight Ranges Integration

	@Test("highlight ranges populated from byte ranges")
	func highlightRangesFromByteRanges() {
		let (de, view) = makeEditor(text: "aa bb aa")
		let byteRanges = de.allMatchRanges(pattern: "aa", options: [])
		view.highlightRanges = byteRanges.map { range in
			let start = de.editor.buffer.convert(offset: range.lowerBound)
			let end = de.editor.buffer.convert(offset: range.upperBound)
			return (
				start: (line: start.line, index: start.column),
				end: (line: end.line, index: end.column),
			)
		}
		#expect(view.highlightRanges.count == 2)
		#expect(view.highlightRanges[0].start.line == 0)
		#expect(view.highlightRanges[0].start.index == 0)
		#expect(view.highlightRanges[0].end.index == 2)
	}
}

// MARK: - FindClient Mock Server Tests

@Suite("FindClientConformance")
@MainActor
struct FindClientConformanceTests {
	private func makeWindowController(text: String) -> DocumentWindowController {
		let dwc = DocumentWindowController()
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		dwc.documents = [doc]
		dwc.selectedTabIndex = 0
		// Trigger editor wiring
		dwc.openAndSelectDocument(doc, activate: false)
		return dwc
	}

	@Test("DocumentWindowController conforms to FindClient")
	func conformance() {
		let dwc = DocumentWindowController()
		let client: FindClient = dwc
		#expect(client === dwc)
	}
}
