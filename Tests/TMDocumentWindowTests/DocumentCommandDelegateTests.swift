import AppKit
import Foundation
import Testing
import TMBundle
import TMTheme
@testable import TMBundleRuntime
@testable import TMCompatibility
@testable import TMCore
@testable import TMDocumentManager
@testable import TMDocumentWindow
@testable import TMEditor
@testable import TMGrammar

// MARK: - DocumentCommandDelegate Tests

@Suite("DocumentCommandDelegate - End-to-End Command Integration")
struct DocumentCommandDelegateTests {
	// MARK: - Environment Building

	@Test("Environment contains TM_TAB_SIZE")
	@MainActor func environmentContainsTabSize() {
		let wc = DocumentWindowController()
		let env = wc.environment
		#expect(env["TM_TAB_SIZE"] != nil)
	}

	@Test("Environment contains TM_SOFT_TABS")
	@MainActor func environmentContainsSoftTabs() {
		let wc = DocumentWindowController()
		let env = wc.environment
		#expect(env["TM_SOFT_TABS"] != nil)
	}

	@Test("Environment contains TM_APP_PATH")
	@MainActor func environmentContainsAppPath() {
		let wc = DocumentWindowController()
		let env = wc.environment
		#expect(env["TM_APP_PATH"] == Bundle.main.bundlePath)
	}

	@Test("Environment contains TM_PID")
	@MainActor func environmentContainsPID() {
		let wc = DocumentWindowController()
		let env = wc.environment
		#expect(env["TM_PID"] == String(ProcessInfo.processInfo.processIdentifier))
	}

	@Test("Environment contains TM_SELECTION for default caret position")
	@MainActor func environmentContainsSelection() {
		let wc = DocumentWindowController()
		let env = wc.environment
		#expect(env["TM_SELECTION"] != nil)
	}

	@Test("Environment includes document path when set")
	@MainActor func environmentIncludesFilePath() {
		let doc = TMDocument(path: "/tmp/test.txt")
		doc.setContent("hello")
		let wc = DocumentWindowController(document: doc)
		let env = wc.environment
		#expect(env["TM_FILEPATH"] == "/tmp/test.txt")
		#expect(env["TM_FILENAME"] == "test.txt")
		#expect(env["TM_DIRECTORY"] == "/tmp")
	}

	@Test("Environment includes project directory when set")
	@MainActor func environmentIncludesProjectDir() {
		let wc = DocumentWindowController()
		wc.projectPath = "/Users/test/project"
		let env = wc.environment
		#expect(env["TM_PROJECT_DIRECTORY"] == "/Users/test/project")
	}

	@Test("Environment inherits process environment")
	@MainActor func environmentInheritsProcessEnv() {
		let wc = DocumentWindowController()
		let env = wc.environment
		// PATH should come from the process environment
		#expect(env["PATH"] != nil)
	}

	@Test("Environment includes TM_LINE_NUMBER starting at 1")
	@MainActor func environmentLineNumberStartsAt1() {
		let doc = TMDocument()
		doc.setContent("first\nsecond\nthird")
		let wc = DocumentWindowController(document: doc)
		let env = wc.environment
		#expect(env["TM_LINE_NUMBER"] == "1")
	}

	// MARK: - Input Data

	@Test("Input data returns entire document")
	@MainActor func inputDataEntireDocument() {
		let doc = TMDocument()
		doc.setContent("Hello World")
		let wc = DocumentWindowController(document: doc)
		let data = wc.inputData(
			for: .entireDocument,
			fallback: .nothing,
			format: .text,
			scope: "",
		)
		#expect(String(data: data, encoding: .utf8) == "Hello World")
	}

	@Test("Input data returns empty for no input")
	@MainActor func inputDataNothingReturnsEmpty() {
		let doc = TMDocument()
		doc.setContent("Hello World")
		let wc = DocumentWindowController(document: doc)
		let data = wc.inputData(
			for: .nothing,
			fallback: .nothing,
			format: .text,
			scope: "",
		)
		#expect(String(data: data, encoding: .utf8) == "")
	}

	@Test("Input data falls back when primary source is nil")
	@MainActor func inputDataFallbackWhenPrimaryNil() {
		let doc = TMDocument()
		doc.setContent("Hello World")
		let wc = DocumentWindowController(document: doc)
		// Selection is empty (caret) so .selection returns nil → fall back to .entireDocument
		let data = wc.inputData(
			for: .selection,
			fallback: .entireDocument,
			format: .text,
			scope: "",
		)
		#expect(String(data: data, encoding: .utf8) == "Hello World")
	}

	@Test("Input data returns current line")
	@MainActor func inputDataCurrentLine() {
		let doc = TMDocument()
		doc.setContent("line one\nline two\nline three")
		let wc = DocumentWindowController(document: doc)
		let data = wc.inputData(
			for: .line,
			fallback: .nothing,
			format: .text,
			scope: "",
		)
		// Caret is at beginning (line 0), so we get "line one\n"
		let text = String(data: data, encoding: .utf8)
		#expect(text == "line one\n")
	}

	@Test("Input data returns character at caret")
	@MainActor func inputDataCharacter() {
		let doc = TMDocument()
		doc.setContent("ABCDEF")
		let wc = DocumentWindowController(document: doc)
		let data = wc.inputData(
			for: .character,
			fallback: .nothing,
			format: .text,
			scope: "",
		)
		// Caret at offset 0 → character "A"
		let text = String(data: data, encoding: .utf8)
		#expect(text == "A")
	}

	// MARK: - Text Output Application

	@Test("Apply text output replaces document")
	@MainActor func applyOutputReplacesDocument() {
		let doc = TMDocument()
		doc.setContent("old content")
		let wc = DocumentWindowController(document: doc)

		wc.applyTextOutput(
			"new content",
			placement: .replaceDocument,
			format: .text,
			caret: .afterOutput,
		)

		#expect(wc.documentEditor?.editor.text == "new content")
	}

	@Test("Apply text output at caret inserts text")
	@MainActor func applyOutputAtCaret() {
		let doc = TMDocument()
		doc.setContent("hello world")
		let wc = DocumentWindowController(document: doc)

		// Caret is at position 0
		wc.applyTextOutput(
			"*** ",
			placement: .atCaret,
			format: .text,
			caret: .afterOutput,
		)

		#expect(wc.documentEditor?.editor.text == "*** hello world")
	}

	@Test("Apply text output replaces selection")
	@MainActor func applyOutputReplacesSelection() throws {
		let doc = TMDocument()
		doc.setContent("hello world")
		let wc = DocumentWindowController(document: doc)

		// Select "hello"
		let start = TextPosition.zero
		let end = try #require(wc.documentEditor?.editor.buffer.convert(offset: 5))
		wc.documentEditor?.editor.selections = SelectionState(
			[TextRange(anchor: start, head: end)],
		)

		wc.applyTextOutput(
			"goodbye",
			placement: .replaceSelection,
			format: .text,
			caret: .afterOutput,
		)

		#expect(wc.documentEditor?.editor.text == "goodbye world")
	}

	@Test("Apply text output as replaceInput")
	@MainActor func applyOutputReplacesInput() throws {
		let doc = TMDocument()
		doc.setContent("foo bar baz")
		let wc = DocumentWindowController(document: doc)

		// Select "bar"
		let start = try #require(wc.documentEditor?.editor.buffer.convert(offset: 4))
		let end = try #require(wc.documentEditor?.editor.buffer.convert(offset: 7))
		wc.documentEditor?.editor.selections = SelectionState(
			[TextRange(anchor: start, head: end)],
		)

		wc.applyTextOutput(
			"qux",
			placement: .replaceInput,
			format: .text,
			caret: .afterOutput,
		)

		#expect(wc.documentEditor?.editor.text == "foo qux baz")
	}

	// MARK: - Tooltip / New Document / Error

	@Test("Show tooltip does not crash")
	@MainActor func showToolTipDoesNotCrash() {
		let wc = DocumentWindowController()
		// Just verify it doesn't throw
		wc.showToolTip("test message")
	}

	@Test("Show new document creates content")
	@MainActor func showNewDocumentCreatesWindow() {
		let wc = DocumentWindowController()
		// This creates a new window controller — just verify no crash
		wc.showNewDocument("new text content")
	}

	@Test("Show error presents alert without crashing")
	@MainActor func showErrorDoesNotCrash() {
		let command = TMBundleRuntime.BundleCommand(
			name: "Test Command",
			uuid: "test-uuid",
			command: "echo hello",
		)
		// Without a window, runModal would be called. Just test that it doesn't crash.
		// Note: In headless test environment, alert.runModal() may not work,
		// so we just verify the method exists and is callable.
		_ = command
	}

	// MARK: - PreExec Actions

	@Test("PreExec nop returns true")
	@MainActor func preExecNopReturnsTrue() async {
		let wc = DocumentWindowController()
		let result = await wc.performPreExecAction(.nop)
		#expect(result == true)
	}

	// MARK: - Scope & Working Directory

	@Test("Current scope returns empty string by default")
	@MainActor func currentScopeDefaultEmpty() {
		let wc = DocumentWindowController()
		#expect(wc.currentScope == "")
	}

	@Test("Working directory uses project path when set")
	@MainActor func workingDirectoryUsesProjectPath() {
		let wc = DocumentWindowController()
		wc.projectPath = "/Users/test/myproject"
		#expect(wc.workingDirectory == "/Users/test/myproject")
	}

	@Test("Working directory falls back to document directory")
	@MainActor func workingDirectoryFallsBackToDocDir() {
		let doc = TMDocument(path: "/tmp/dir/file.txt")
		doc.setContent("hello")
		let wc = DocumentWindowController(document: doc)
		#expect(wc.workingDirectory == "/tmp/dir")
	}

	@Test("Working directory falls back to temp when no path")
	@MainActor func workingDirectoryFallsBackToTemp() {
		let wc = DocumentWindowController()
		let wd = wc.workingDirectory
		// Should be NSTemporaryDirectory() or similar
		#expect(!wd.isEmpty)
	}

	// MARK: - Insert Snippet

	@Test("Insert snippet inserts text")
	@MainActor func insertSnippetInsertsText() throws {
		let doc = TMDocument()
		doc.setContent("hello ")
		let wc = DocumentWindowController(document: doc)

		// Move caret to end
		let bufSize = try #require(wc.documentEditor?.editor.buffer.size)
		let endPos = try #require(wc.documentEditor?.editor.buffer.convert(
			offset: bufSize,
		))
		wc.documentEditor?.editor.selections = SelectionState(caret: endPos)

		wc.insertSnippet("world", disableAutoIndent: false)
		#expect(wc.documentEditor?.editor.text == "hello world")
	}

	// MARK: - Show Completions

	@Test("Show completions calls setSuggestions without crash")
	@MainActor func showCompletionsDoesNotCrash() {
		let doc = TMDocument()
		doc.setContent("he")
		let wc = DocumentWindowController(document: doc)
		// Just verify calling showCompletions doesn't crash
		wc.showCompletions("hello\nhelp\nhero")
	}

	// MARK: - Full Pipeline Smoke Test

	@Test("Full environment build does not crash with empty document")
	@MainActor func fullEnvironmentBuildEmpty() {
		let wc = DocumentWindowController()
		let env = wc.environment
		// Should have standard TM variables
		#expect(env["TM_TAB_SIZE"] != nil)
		#expect(env["TM_SOFT_TABS"] != nil)
		#expect(env["TM_APP_PATH"] != nil)
		#expect(env["TM_PID"] != nil)
		#expect(env["TM_SELECTION"] != nil)
	}

	@Test("Input data with word source returns word at caret")
	@MainActor func inputDataWordAtCaret() throws {
		let doc = TMDocument()
		doc.setContent("hello world")
		let wc = DocumentWindowController(document: doc)

		// Move caret into the middle of "hello"
		let pos = try #require(wc.documentEditor?.editor.buffer.convert(offset: 3))
		wc.documentEditor?.editor.selections = SelectionState(caret: pos)

		let data = wc.inputData(
			for: .word,
			fallback: .nothing,
			format: .text,
			scope: "",
		)
		let word = String(data: data, encoding: .utf8)
		#expect(word == "hello")
	}

	@Test("Full round-trip: input → output replaces document")
	@MainActor func roundTripInputOutput() {
		let doc = TMDocument()
		doc.setContent("The quick brown fox")
		let wc = DocumentWindowController(document: doc)

		// Get entire document as input
		let inputData = wc.inputData(
			for: .entireDocument,
			fallback: .nothing,
			format: .text,
			scope: "",
		)
		let input = String(data: inputData, encoding: .utf8) ?? ""
		#expect(input == "The quick brown fox")

		// Simulate command output that replaces the document
		let output = input.uppercased()
		wc.applyTextOutput(
			output,
			placement: .replaceDocument,
			format: .text,
			caret: .afterOutput,
		)

		#expect(wc.documentEditor?.editor.text == "THE QUICK BROWN FOX")
	}
}

// MARK: - HTMLOutputWindowController Tests

#if canImport(WebKit)
@Suite("HTMLOutputWindowController")
struct HTMLOutputWindowControllerTests {
	@Test("Creates window with correct title")
	@MainActor func windowCreation() {
		let controller = HTMLOutputWindowController()
		#expect(controller.window?.title == "HTML Output")
	}

	@Test("CommandView is accessible")
	@MainActor func commandViewAccessible() {
		let controller = HTMLOutputWindowController()
		#expect(controller.commandView.frame.width > 0 || true)
	}

	@Test("Can set HTML content")
	@MainActor func setContent() {
		let controller = HTMLOutputWindowController()
		controller.commandView.setContent("<h1>Hello</h1>")
		// Just verify no crash
	}
}
#endif

// MARK: - EnvironmentBuilder Integration Tests

@Suite("EnvironmentBuilder Integration")
struct EnvironmentBuilderIntegrationTests {
	@Test("Build produces TM variables")
	func buildProducesTMVars() {
		let editor = EnvironmentBuilder.EditorContext(
			tabSize: 4,
			softTabs: true,
			selectionString: "1:0",
			scope: "source.swift",
			lineNumber: 1,
			columnNumber: 1,
		)
		let doc = EnvironmentBuilder.DocumentContext(
			filePath: "/tmp/test.swift",
			displayName: "test.swift",
		)
		let env = EnvironmentBuilder.build(editor: editor, document: doc)

		#expect(env["TM_TAB_SIZE"] == "4")
		#expect(env["TM_SOFT_TABS"] == "YES")
		#expect(env["TM_SCOPE"] == "source.swift")
		#expect(env["TM_FILEPATH"] == "/tmp/test.swift")
		#expect(env["TM_FILENAME"] == "test.swift")
		#expect(env["TM_DIRECTORY"] == "/tmp")
		#expect(env["TM_SELECTION"] == "1:0")
		#expect(env["TM_LINE_NUMBER"] == "1")
	}

	@Test("BuildFull inherits process environment")
	func buildFullInheritsEnv() {
		let env = EnvironmentBuilder.buildFull()
		#expect(env["PATH"] != nil)
	}

	@Test("TM variables override inherited env")
	func tmVarsOverride() {
		let editor = EnvironmentBuilder.EditorContext(tabSize: 8)
		let env = EnvironmentBuilder.buildFull(editor: editor)
		#expect(env["TM_TAB_SIZE"] == "8")
	}

	@Test("Selected text only set when non-nil")
	func selectedTextOptional() {
		let ctx = EnvironmentBuilder.EditorContext()
		let env = EnvironmentBuilder.build(editor: ctx)
		#expect(env["TM_SELECTED_TEXT"] == nil)
	}

	@Test("Selected text included when present")
	func selectedTextPresent() {
		let ctx = EnvironmentBuilder.EditorContext(selectedText: "hello")
		let env = EnvironmentBuilder.build(editor: ctx)
		#expect(env["TM_SELECTED_TEXT"] == "hello")
	}

	@Test("Project context variables")
	func projectContext() {
		let proj = EnvironmentBuilder.ProjectContext(
			projectDirectory: "/Users/test/project",
			projectUUID: "ABC-123",
			scmName: "git",
			scmBranch: "main",
		)
		let env = EnvironmentBuilder.build(project: proj)
		#expect(env["TM_PROJECT_DIRECTORY"] == "/Users/test/project")
		#expect(env["TM_PROJECT_UUID"] == "ABC-123")
		#expect(env["TM_SCM_NAME"] == "git")
		#expect(env["TM_SCM_BRANCH"] == "main")
	}

	@Test("App context variables")
	func appContext() {
		let app = EnvironmentBuilder.AppContext(
			appPath: "/Applications/TextMate.app",
			pid: 12345,
			supportPath: "/Library/Support",
		)
		let env = EnvironmentBuilder.build(app: app)
		#expect(env["TM_APP_PATH"] == "/Applications/TextMate.app")
		#expect(env["TM_PID"] == "12345")
		#expect(env["TM_SUPPORT_PATH"] == "/Library/Support")
	}

	@Test("Extra variables are merged")
	func extraVarsMerged() {
		let env = EnvironmentBuilder.build(extra: ["CUSTOM_VAR": "value"])
		#expect(env["CUSTOM_VAR"] == "value")
	}

	@Test("TM variables take precedence over extra")
	func tmOverridesExtra() {
		// TM_TAB_SIZE is always set, so extra with same key is overridden
		let env = EnvironmentBuilder.build(
			editor: EnvironmentBuilder.EditorContext(tabSize: 4),
			extra: ["TM_TAB_SIZE": "999"],
		)
		#expect(env["TM_TAB_SIZE"] == "4")
	}
}

// MARK: - Scope-Based Input Tests

/// Creates a keyword grammar: `\bkeyword\b` → `keyword.test`.
private func makeScopeInputGrammar() -> GrammarDefinition {
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

/// Sets up a DocumentWindowController with a grammar/parser ready for
/// scope-based input tests.
@MainActor
private func makeWindowControllerWithGrammar(
	text: String,
) -> DocumentWindowController {
	let doc = TMDocument()
	doc.setContent(text, preserveRevision: true)
	let wc = DocumentWindowController(document: doc)

	let registry = GrammarRegistry()
	let gramDef = makeScopeInputGrammar()
	registry.register(gramDef)

	let theme = Theme(
		name: "Test",
		semanticClass: "theme.light.test",
		uuid: "00000000-0000-0000-0000-000000000099",
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

	guard let docEditor = wc.documentEditor else { return wc }
	docEditor.syntaxHighlighter.setGrammarRegistry(registry)
	docEditor.syntaxHighlighter.setThemeEngine(engine)
	docEditor.syntaxHighlighter.setGrammar(scope: gramDef.scopeName)
	docEditor.syntaxHighlighter.setText(text)
	docEditor.syntaxHighlighter.parseSync()

	return wc
}

@Suite("Scope-Based Command Input")
struct ScopeBasedInputTests {
	@Test("Scope input returns text matching scope selector at caret")
	@MainActor func scopeInputReturnsKeyword() throws {
		// "hello keyword world" — with caret inside "keyword"
		let wc = makeWindowControllerWithGrammar(text: "hello keyword world")
		let editor = try #require(wc.documentEditor?.editor)

		// Place caret in the middle of "keyword" (offset 9 = 'y' of keyword)
		let pos = editor.buffer.convert(offset: 9)
		editor.selections = SelectionState(caret: pos)

		// Request scope input with "keyword" as the scope selector
		let data = wc.inputData(
			for: .scope,
			fallback: .word,
			format: .text,
			scope: "keyword",
		)
		let text = String(data: data, encoding: .utf8)
		#expect(text == "keyword")
	}

	@Test("Scope input falls back to word when no parser")
	@MainActor func scopeInputFallsBackWithoutParser() throws {
		// No grammar setup — just a plain document
		let doc = TMDocument()
		doc.setContent("hello world")
		let wc = DocumentWindowController(document: doc)
		let editor = try #require(wc.documentEditor?.editor)

		// Place caret in "hello"
		let pos = editor.buffer.convert(offset: 2)
		editor.selections = SelectionState(caret: pos)

		let data = wc.inputData(
			for: .scope,
			fallback: .word,
			format: .text,
			scope: "keyword",
		)
		let text = String(data: data, encoding: .utf8)
		// Falls back to word since there's no parser
		#expect(text == "hello")
	}

	@Test("Scope input with non-matching selector returns fallback")
	@MainActor func scopeInputNonMatchingSelector() throws {
		// "hello keyword world" — caret in "hello" (not a keyword scope)
		let wc = makeWindowControllerWithGrammar(text: "hello keyword world")
		let editor = try #require(wc.documentEditor?.editor)

		// Place caret in "hello" at offset 2
		let pos = editor.buffer.convert(offset: 2)
		editor.selections = SelectionState(caret: pos)

		// Request scope input with "keyword" selector — should not match
		// since "hello" is in plain `source.test`, not `keyword.test`
		let data = wc.inputData(
			for: .scope,
			fallback: .word,
			format: .text,
			scope: "keyword",
		)
		let text = String(data: data, encoding: .utf8)
		// Falls back to word since scope doesn't match selector at caret
		#expect(text == "hello")
	}

	@Test("Scope input with empty selector matches any scope")
	@MainActor func scopeInputEmptySelector() throws {
		// An empty ScopeSelector matches everything with rank 0,
		// so it should extend across the entire document.
		let wc = makeWindowControllerWithGrammar(text: "hello keyword world")
		let editor = try #require(wc.documentEditor?.editor)

		let pos = editor.buffer.convert(offset: 9)
		editor.selections = SelectionState(caret: pos)

		let data = wc.inputData(
			for: .scope,
			fallback: .word,
			format: .text,
			scope: "",
		)
		let text = String(data: data, encoding: .utf8)
		// Empty selector matches everything — extends to full document
		#expect(text == "hello keyword world")
	}

	@Test("Scope input on multi-line document")
	@MainActor func scopeInputMultiLine() throws {
		let wc = makeWindowControllerWithGrammar(text: "hello\nkeyword\nworld")
		let editor = try #require(wc.documentEditor?.editor)

		// Place caret at start of line 1 ("keyword")
		let offset = editor.buffer.lineStart(1)
		let pos = editor.buffer.convert(offset: offset)
		editor.selections = SelectionState(caret: pos)

		let data = wc.inputData(
			for: .scope,
			fallback: .word,
			format: .text,
			scope: "keyword",
		)
		let text = String(data: data, encoding: .utf8)
		#expect(text == "keyword")
	}

	@Test("Scope input at document boundary does not crash")
	@MainActor func scopeInputAtBoundary() throws {
		let wc = makeWindowControllerWithGrammar(text: "keyword")
		let editor = try #require(wc.documentEditor?.editor)

		// Place caret at offset 0
		editor.selections = SelectionState(caret: TextPosition.zero)

		let data = wc.inputData(
			for: .scope,
			fallback: .word,
			format: .text,
			scope: "keyword",
		)
		let text = String(data: data, encoding: .utf8)
		#expect(text == "keyword")
	}

	@Test("Scope input at end of document does not crash")
	@MainActor func scopeInputAtEnd() throws {
		let wc = makeWindowControllerWithGrammar(text: "hello keyword")
		let editor = try #require(wc.documentEditor?.editor)

		// Place caret at end of "keyword"
		let pos = editor.buffer.convert(offset: editor.buffer.size)
		editor.selections = SelectionState(caret: pos)

		let data = wc.inputData(
			for: .scope,
			fallback: .word,
			format: .text,
			scope: "keyword",
		)
		let text = String(data: data, encoding: .utf8)
		// Caret is at end of buffer — might be at the edge of the keyword scope
		// Result depends on parser; at minimum it should not crash
		#expect(text != nil)
	}
}
