import AppKit
import Testing
import TMBundle
import TMBundleRuntime
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMGrammar
import TMTheme
@testable import TMDocumentWindow

// MARK: - Helpers

private func makeThemeEngine() -> ThemeEngine {
	let theme = Theme(
		name: "Test",
		semanticClass: "theme.light.test",
		uuid: "00000000-0000-0000-0000-000000000003",
		globalSettings: ThemeGlobalSettings(),
	)
	return ThemeEngine(theme: theme, fontSize: 12)
}

private func makeSettingsItem(
	scope: String,
	increaseIndent: String? = nil,
	decreaseIndent: String? = nil,
	indentNext: String? = nil,
	unIndented: String? = nil,
) -> BundleItem {
	var settings: [String: Any] = [:]
	if let s = increaseIndent { settings["increaseIndentPattern"] = s }
	if let s = decreaseIndent { settings["decreaseIndentPattern"] = s }
	if let s = indentNext { settings["indentNextLinePattern"] = s }
	if let s = unIndented { settings["unIndentedLinePattern"] = s }
	return BundleItem(
		uuid: UUID().uuidString,
		name: "Indent Settings",
		kind: .settings,
		scopeSelector: scope,
		bundleUUID: "test-bundle",
		plist: ["settings": settings],
	)
}

// MARK: - IndentPatternProvider Tests

@Suite("IndentPatternProvider")
@MainActor
struct IndentPatternProviderTests {
	@Test("hasPatterns is false when not configured")
	func noPatternsInitially() {
		let buf = TextBuffer("hello\n")
		let p = IndentPatternProvider(buffer: buf, tabSize: 4, indentUsingSpaces: false)
		#expect(p.hasPatterns == false)
	}

	@Test("hasPatterns is true after configuring with indent patterns")
	func hasPatternsAfterConfigure() {
		let buf = TextBuffer("hello\n")
		let p = IndentPatternProvider(buffer: buf, tabSize: 4, indentUsingSpaces: false)

		let index = BundleIndex()
		index.setIndex(items: [
			makeSettingsItem(scope: "source.test", increaseIndent: "\\{\\s*$"),
		], bundles: [])

		p.configure(bundleIndex: index, scope: "source.test")
		#expect(p.hasPatterns == true)
	}

	@Test("indentAfterLine returns increased indent after opening brace")
	func indentAfterOpenBrace() {
		let buf = TextBuffer("if (true) {\n")
		let p = IndentPatternProvider(buffer: buf, tabSize: 4, indentUsingSpaces: true)

		let index = BundleIndex()
		index.setIndex(items: [
			makeSettingsItem(
				scope: "source.test",
				increaseIndent: "\\{\\s*$",
				decreaseIndent: "^\\s*\\}",
			),
		], bundles: [])

		p.configure(bundleIndex: index, scope: "source.test")
		let indent = p.indentAfterLine(0)
		#expect(indent == "    ", "Expected 4-space indent after {")
	}

	@Test("indentAfterLine returns tab indent when not using spaces")
	func tabIndent() {
		let buf = TextBuffer("if (true) {\n")
		let p = IndentPatternProvider(buffer: buf, tabSize: 4, indentUsingSpaces: false)

		let index = BundleIndex()
		index.setIndex(items: [
			makeSettingsItem(
				scope: "source.test",
				increaseIndent: "\\{\\s*$",
				decreaseIndent: "^\\s*\\}",
			),
		], bundles: [])

		p.configure(bundleIndex: index, scope: "source.test")
		let indent = p.indentAfterLine(0)
		#expect(indent == "\t", "Expected tab indent after {")
	}

	@Test("indentAfterLine preserves indent level without patterns")
	func noPatternsFallback() {
		let buf = TextBuffer("\t\thello\n")
		let p = IndentPatternProvider(buffer: buf, tabSize: 4, indentUsingSpaces: false)
		p.configure(bundleIndex: nil, scope: nil)
		let indent = p.indentAfterLine(0)
		#expect(indent == "\t\t")
	}

	@Test("indentAfterLine handles nested braces")
	func nestedBraces() {
		let buf = TextBuffer("if (true) {\n\tif (false) {\n")
		let p = IndentPatternProvider(buffer: buf, tabSize: 4, indentUsingSpaces: false)

		let index = BundleIndex()
		index.setIndex(items: [
			makeSettingsItem(
				scope: "source.test",
				increaseIndent: "\\{\\s*$",
				decreaseIndent: "^\\s*\\}",
			),
		], bundles: [])

		p.configure(bundleIndex: index, scope: "source.test")
		let indent = p.indentAfterLine(1)
		#expect(indent == "\t\t", "Expected 2 tabs for nested brace")
	}

	@Test("indentAfterLine keeps level for plain line")
	func plainLineKeepsLevel() {
		let buf = TextBuffer("if (true) {\n\tx = 1\n")
		let p = IndentPatternProvider(buffer: buf, tabSize: 4, indentUsingSpaces: false)

		let index = BundleIndex()
		index.setIndex(items: [
			makeSettingsItem(
				scope: "source.test",
				increaseIndent: "\\{\\s*$",
				decreaseIndent: "^\\s*\\}",
			),
		], bundles: [])

		p.configure(bundleIndex: index, scope: "source.test")
		let indent = p.indentAfterLine(1)
		#expect(indent == "\t", "Expected 1 tab: same level as inside {")
	}

	@Test("scope matching picks best-ranked preference")
	func scopeMatching() {
		let buf = TextBuffer("begin\n")
		let p = IndentPatternProvider(buffer: buf, tabSize: 2, indentUsingSpaces: true)

		// Generic scope says increase on BEGIN, specific scope says increase on {
		let index = BundleIndex()
		index.setIndex(items: [
			makeSettingsItem(scope: "source", increaseIndent: "^BEGIN"),
			makeSettingsItem(scope: "source.ruby", increaseIndent: "\\{\\s*$"),
		], bundles: [])

		// source.ruby is more specific than source
		p.configure(bundleIndex: index, scope: "source.ruby")
		// The brace pattern from source.ruby should win
		let indent = p.indentAfterLine(0)
		// "begin" doesn't match {\s*$ so should just copy whitespace
		#expect(indent == "")
	}

	// MARK: - End-to-End Wiring

	@Test("TMDocumentEditor wires indent provider after configureGrammar")
	func editorWiresIndentProvider() {
		let doc = TMDocument()
		doc.setContent("if (true) {\n\tx = 1\n}\n", preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let docEditor = TMDocumentEditor(document: doc, editorView: view)

		// Set up a bundle index with indent patterns
		let index = BundleIndex()
		index.setIndex(items: [
			makeSettingsItem(
				scope: "source.test",
				increaseIndent: "\\{\\s*$",
				decreaseIndent: "^\\s*\\}",
			),
		], bundles: [])
		docEditor.bundleIndex = index

		let registry = GrammarRegistry()
		registry.register(GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			fileTypes: ["test"],
			patterns: [],
			repository: [:],
		))

		docEditor.configureGrammar(
			registry: registry,
			themeEngine: makeThemeEngine(),
			scope: "source.test",
		)

		// The editor's indent provider should be set
		#expect(docEditor.editor.indentProvider != nil)
	}

	@Test("indent provider not set when no indent patterns in bundles")
	func noIndentPatternsNoProvider() {
		let doc = TMDocument()
		doc.setContent("hello\n", preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let docEditor = TMDocumentEditor(document: doc, editorView: view)

		let registry = GrammarRegistry()
		registry.register(GrammarDefinition(
			scopeName: "source.plain",
			name: "Plain",
			fileTypes: ["txt"],
			patterns: [],
			repository: [:],
		))

		docEditor.configureGrammar(
			registry: registry,
			themeEngine: makeThemeEngine(),
			scope: "source.plain",
		)

		#expect(docEditor.editor.indentProvider == nil)
	}

	@Test("newline insertion uses indent provider")
	func newlineUsesProvider() {
		let doc = TMDocument()
		doc.setContent("if (true) {", preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let docEditor = TMDocumentEditor(document: doc, editorView: view)
		docEditor.editor.indentUsingSpaces = true
		docEditor.editor.tabSize = 4

		// Set up indent patterns
		let index = BundleIndex()
		index.setIndex(items: [
			makeSettingsItem(
				scope: "source.test",
				increaseIndent: "\\{\\s*$",
				decreaseIndent: "^\\s*\\}",
			),
		], bundles: [])
		docEditor.bundleIndex = index

		let registry = GrammarRegistry()
		registry.register(GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			patterns: [],
			repository: [:],
		))

		docEditor.configureGrammar(
			registry: registry,
			themeEngine: makeThemeEngine(),
			scope: "source.test",
		)

		// Place caret at end of line
		let endOfLine = docEditor.editor.buffer.size
		docEditor.editor.selections = SelectionState(
			caret: docEditor.editor.buffer.convert(offset: endOfLine),
		)

		// Insert newline
		docEditor.editor.perform(.insertNewline)

		// Check that the inserted newline has increased indentation
		let text = docEditor.editor.buffer.substring(
			from: 0,
			to: docEditor.editor.buffer.size,
		)
		#expect(text.contains("\n    "), "Expected indented newline after {")
	}
}
