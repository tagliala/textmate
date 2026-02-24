import AppKit
import Testing
import TMBundle
import TMCore
import TMEditorUI
import TMGrammar
import TMTheme
@testable import TMDocumentManager
@testable import TMDocumentWindow

// MARK: - Test Helpers

/// Creates a grammar definition that matches `\bkeyword\b` → `keyword.test`.
private func makeKeywordGrammar() -> GrammarDefinition {
	GrammarDefinition(
		scopeName: "source.test",
		name: "Test",
		fileTypes: ["test"],
		uuid: nil,
		firstLineMatch: nil,
		patterns: [
			GrammarDefinition.Pattern(
				match: "\\bkeyword\\b",
				name: "keyword.test",
			),
		],
		repository: [:],
		foldingStartMarker: nil,
		foldingStopMarker: nil,
	)
}

/// Creates a grammar + theme-equipped SyntaxHighlighter ready to use.
@MainActor
private func makeHighlighter() -> SyntaxHighlighter {
	let registry = GrammarRegistry()
	let gramDef = makeKeywordGrammar()
	registry.register(gramDef)

	let rules = [
		ThemeStyleRule(
			scopeSelector: "keyword",
			name: "Keywords",
			foreground: ThemeColor(red: 1, green: 0, blue: 0),
		),
	]
	let theme = Theme(
		name: "Test",
		semanticClass: "theme.light.test",
		uuid: "00000000-0000-0000-0000-000000000002",
		globalSettings: ThemeGlobalSettings(
			foreground: ThemeColor(red: 0, green: 0, blue: 0),
			background: ThemeColor(red: 1, green: 1, blue: 1),
		),
		gutterSettings: ThemeGutterSettings(),
		rules: rules,
	)
	let engine = ThemeEngine(theme: theme, fontSize: 12)

	let hl = SyntaxHighlighter(grammarRegistry: registry, themeEngine: engine)
	hl.setGrammar(scope: gramDef.scopeName)
	return hl
}

// MARK: - EditRegionTracker Tests

@Suite("EditRegionTracker")
@MainActor
struct EditRegionTrackerTests {
	@Test("tracks single insert within a line")
	func singleInsert() {
		let buffer = TextBuffer("hello world\n")
		let tracker = EditRegionTracker()
		tracker.buffer = buffer
		buffer.addCallback(tracker)

		buffer.insert(at: 5, string: " there")
		let region = tracker.consume()

		#expect(region != nil)
		#expect(region?.startLine == 0)
		#expect(region?.oldLineCount == 1)
		#expect(region?.newLineCount == 1)

		buffer.removeCallback(tracker)
	}

	@Test("tracks single deletion within a line")
	func singleDeletion() {
		let buffer = TextBuffer("hello world\n")
		let tracker = EditRegionTracker()
		tracker.buffer = buffer
		buffer.addCallback(tracker)

		buffer.erase(from: 5, to: 11) // Delete " world"
		let region = tracker.consume()

		#expect(region != nil)
		#expect(region?.startLine == 0)
		#expect(region?.oldLineCount == 1)
		#expect(region?.newLineCount == 1)

		buffer.removeCallback(tracker)
	}

	@Test("tracks insert that adds a newline")
	func insertNewline() {
		let buffer = TextBuffer("hello world\n")
		let tracker = EditRegionTracker()
		tracker.buffer = buffer
		buffer.addCallback(tracker)

		buffer.insert(at: 5, string: "\n")
		let region = tracker.consume()

		#expect(region != nil)
		#expect(region?.startLine == 0)
		#expect(region?.oldLineCount == 1) // Was one line
		#expect(region?.newLineCount == 2) // Now two lines

		buffer.removeCallback(tracker)
	}

	@Test("tracks deletion that removes a newline")
	func deleteNewline() {
		let buffer = TextBuffer("hello\nworld\n")
		let tracker = EditRegionTracker()
		tracker.buffer = buffer
		buffer.addCallback(tracker)

		buffer.erase(from: 5, to: 6) // Delete the \n between lines
		let region = tracker.consume()

		#expect(region != nil)
		#expect(region?.startLine == 0)
		#expect(region?.oldLineCount == 2) // Spanned two lines
		#expect(region?.newLineCount == 1) // Now one line

		buffer.removeCallback(tracker)
	}

	@Test("returns nil for multiple edits")
	func multipleEdits() {
		let buffer = TextBuffer("hello world\n")
		let tracker = EditRegionTracker()
		tracker.buffer = buffer
		buffer.addCallback(tracker)

		buffer.insert(at: 5, string: " there")
		buffer.insert(at: 0, string: "A")
		let region = tracker.consume()

		#expect(region == nil)

		buffer.removeCallback(tracker)
	}

	@Test("resets after consume")
	func resetAfterConsume() {
		let buffer = TextBuffer("hello\n")
		let tracker = EditRegionTracker()
		tracker.buffer = buffer
		buffer.addCallback(tracker)

		buffer.insert(at: 5, string: "!")
		_ = tracker.consume()

		// Second consume with no edits
		let region = tracker.consume()
		#expect(region == nil)

		buffer.removeCallback(tracker)
	}

	@Test("tracks edit on second line correctly")
	func editSecondLine() {
		let buffer = TextBuffer("line one\nline two\n")
		let tracker = EditRegionTracker()
		tracker.buffer = buffer
		buffer.addCallback(tracker)

		let offset = buffer.lineStart(1) // Start of "line two"
		buffer.insert(at: offset, string: "X")
		let region = tracker.consume()

		#expect(region != nil)
		#expect(region?.startLine == 1)
		#expect(region?.oldLineCount == 1)
		#expect(region?.newLineCount == 1)

		buffer.removeCallback(tracker)
	}

	@Test("tracks replacement spanning multiple lines")
	func replacementSpanningLines() {
		let buffer = TextBuffer("aaa\nbbb\nccc\n")
		let tracker = EditRegionTracker()
		tracker.buffer = buffer
		buffer.addCallback(tracker)

		// Replace "bbb\nccc" (bytes 4..11) with "XXX"
		let from = buffer.lineStart(1)
		let to = buffer.lineStart(1) + 7 // "bbb\nccc" = 7 bytes
		buffer.replace(from: from, to: to, with: "XXX")
		let region = tracker.consume()

		#expect(region != nil)
		#expect(region?.startLine == 1)
		#expect(region?.oldLineCount == 2) // "bbb\n" + "ccc"
		#expect(region?.newLineCount == 1) // "XXX"

		buffer.removeCallback(tracker)
	}
}

// MARK: - Incremental Reparse Integration Tests

@Suite("Incremental Reparse Integration")
@MainActor
struct IncrementalReparseIntegrationTests {
	@Test("incremental reparse matches full reparse for single insert")
	func incrementalMatchesFull() {
		// Set up two identical highlighters
		let hlIncremental = makeHighlighter()
		let hlFull = makeHighlighter()
		let text = "hello\nworld\nkeyword\n"
		hlIncremental.setText(text)
		hlIncremental.parseSync()
		hlFull.setText(text)
		hlFull.parseSync()

		// Simulate an edit: change "world" to "keyword"
		// Old line 1: "world\n" → New line 1: "keyword\n"
		hlIncremental.replaceLines(in: 1 ..< 2, with: ["keyword\n"])
		hlIncremental.parseSync()

		let newText = "hello\nkeyword\nkeyword\n"
		hlFull.setText(newText)
		hlFull.parseSync()

		// Compare style runs for all lines
		let lines = ["hello", "keyword", "keyword"]
		for (i, line) in lines.enumerated() {
			let runsInc = hlIncremental.styleRuns(forLine: i, text: line)
			let runsFull = hlFull.styleRuns(forLine: i, text: line)
			#expect(
				runsInc.count == runsFull.count,
				"Line \(i): style run count mismatch (\(runsInc.count) vs \(runsFull.count))",
			)
			for (ri, rf) in zip(runsInc, runsFull) {
				#expect(ri.start == rf.start, "Line \(i): start mismatch")
				#expect(ri.length == rf.length, "Line \(i): length mismatch")
			}
		}
	}

	@Test("incremental reparse matches full reparse for line insertion")
	func incrementalMatchesFullLineInsert() {
		let hlInc = makeHighlighter()
		let hlFull = makeHighlighter()
		let text = "hello\nworld\n"
		hlInc.setText(text)
		hlInc.parseSync()
		hlFull.setText(text)
		hlFull.parseSync()

		// Insert a new line between "hello" and "world"
		// Old line 0 was "hello\n" → new lines 0 and 1 are "hello\n" and "keyword\n"
		hlInc.replaceLines(in: 0 ..< 1, with: ["hello\n", "keyword\n"])
		hlInc.parseSync()

		hlFull.setText("hello\nkeyword\nworld\n")
		hlFull.parseSync()

		let lines = ["hello", "keyword", "world"]
		for (i, line) in lines.enumerated() {
			let runsInc = hlInc.styleRuns(forLine: i, text: line)
			let runsFull = hlFull.styleRuns(forLine: i, text: line)
			#expect(
				runsInc.count == runsFull.count,
				"Line \(i): style run count mismatch",
			)
		}
	}

	@Test("incremental reparse matches full reparse for line deletion")
	func incrementalMatchesFullLineDeletion() {
		let hlInc = makeHighlighter()
		let hlFull = makeHighlighter()
		let text = "hello\nkeyword\nworld\n"
		hlInc.setText(text)
		hlInc.parseSync()
		hlFull.setText(text)
		hlFull.parseSync()

		// Delete line 1 ("keyword\n") by replacing lines 0-1 with just line 0
		hlInc.replaceLines(in: 1 ..< 2, with: [])
		hlInc.parseSync()

		hlFull.setText("hello\nworld\n")
		hlFull.parseSync()

		let lines = ["hello", "world"]
		for (i, line) in lines.enumerated() {
			let runsInc = hlInc.styleRuns(forLine: i, text: line)
			let runsFull = hlFull.styleRuns(forLine: i, text: line)
			#expect(
				runsInc.count == runsFull.count,
				"Line \(i): style run count mismatch",
			)
		}
	}

	@Test("syncAfterEdit uses incremental reparse for single edit")
	func syncAfterEditIncremental() {
		let doc = TMDocument()
		doc.setContent("hello\nworld\n", preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let docEditor = TMDocumentEditor(document: doc, editorView: view)

		// Set up syntax highlighting with the keyword grammar
		let registry = GrammarRegistry()
		registry.register(makeKeywordGrammar())
		let theme = Theme(
			name: "Test",
			semanticClass: "theme.light.test",
			uuid: "00000000-0000-0000-0000-000000000003",
			globalSettings: ThemeGlobalSettings(
				foreground: ThemeColor(red: 0, green: 0, blue: 0),
				background: ThemeColor(red: 1, green: 1, blue: 1),
			),
			gutterSettings: ThemeGutterSettings(),
			rules: [
				ThemeStyleRule(
					scopeSelector: "keyword",
					name: "Keywords",
					foreground: ThemeColor(red: 1, green: 0, blue: 0),
				),
			],
		)
		let engine = ThemeEngine(theme: theme, fontSize: 12)
		docEditor.syntaxHighlighter.setGrammarRegistry(registry)
		docEditor.syntaxHighlighter.setThemeEngine(engine)
		docEditor.syntaxHighlighter.setGrammar(scope: "source.test")
		docEditor.syntaxHighlighter.setText(docEditor.editor.text)
		docEditor.syntaxHighlighter.parseSync()

		// Now simulate a single edit: type "keyword" replacing "world" on line 1
		let lineStart = docEditor.editor.buffer.lineStart(1)
		let lineEnd = lineStart + 5 // "world" = 5 bytes
		docEditor.editor.buffer.replace(from: lineStart, to: lineEnd, with: "keyword")
		docEditor.syncAfterEdit()

		// Verify the parser updated correctly
		let runs = docEditor.syntaxHighlighter.styleRuns(forLine: 1, text: "keyword")
		let hasRed = runs.contains { run in
			run.foreground.redComponent > 0.8 && run.foreground.greenComponent < 0.2
		}
		#expect(hasRed, "Line 1 ('keyword') should be colored red after incremental reparse")
	}

	@Test("syncAfterEdit falls back to full reparse for multiple edits")
	func syncAfterEditFallback() {
		let doc = TMDocument()
		doc.setContent("hello\nworld\nfoo\n", preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let docEditor = TMDocumentEditor(document: doc, editorView: view)

		// Set up syntax highlighting
		let registry = GrammarRegistry()
		registry.register(makeKeywordGrammar())
		let theme = Theme(
			name: "Test",
			semanticClass: "theme.light.test",
			uuid: "00000000-0000-0000-0000-000000000004",
			globalSettings: ThemeGlobalSettings(
				foreground: ThemeColor(red: 0, green: 0, blue: 0),
				background: ThemeColor(red: 1, green: 1, blue: 1),
			),
			gutterSettings: ThemeGutterSettings(),
			rules: [
				ThemeStyleRule(
					scopeSelector: "keyword",
					name: "Keywords",
					foreground: ThemeColor(red: 1, green: 0, blue: 0),
				),
			],
		)
		let engine = ThemeEngine(theme: theme, fontSize: 12)
		docEditor.syntaxHighlighter.setGrammarRegistry(registry)
		docEditor.syntaxHighlighter.setThemeEngine(engine)
		docEditor.syntaxHighlighter.setGrammar(scope: "source.test")
		docEditor.syntaxHighlighter.setText(docEditor.editor.text)
		docEditor.syntaxHighlighter.parseSync()

		// Simulate two edits (triggers full reparse fallback)
		docEditor.editor.buffer.insert(at: 0, string: "A")
		docEditor.editor.buffer.insert(at: 0, string: "B")
		docEditor.syncAfterEdit()

		// Verify the text is consistent
		#expect(docEditor.editor.text == "BAhello\nworld\nfoo\n")
	}
}
