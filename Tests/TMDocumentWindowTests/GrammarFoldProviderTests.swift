import AppKit
import Testing
import TMBundle
import TMBundleRuntime
import TMCore
import TMDocumentManager
import TMEditorUI
import TMGrammar
import TMTheme
@testable import TMDocumentWindow

// MARK: - Helpers

private func makeThemeEngine() -> ThemeEngine {
	let theme = Theme(
		name: "Test",
		semanticClass: "theme.light.test",
		uuid: "00000000-0000-0000-0000-000000000002",
		globalSettings: ThemeGlobalSettings(),
	)
	return ThemeEngine(theme: theme, fontSize: 12)
}

// MARK: - GrammarFoldProvider Tests

@Suite("GrammarFoldProvider")
@MainActor
struct GrammarFoldProviderTests {
	// MARK: - Helpers

	private func makeGrammarDefinition(
		scope: String = "source.test",
		foldingStartMarker: String? = nil,
		foldingStopMarker: String? = nil,
	) -> GrammarDefinition {
		GrammarDefinition(
			scopeName: scope,
			name: "Test",
			fileTypes: [],
			patterns: [],
			repository: [:],
			foldingStartMarker: foldingStartMarker,
			foldingStopMarker: foldingStopMarker,
		)
	}

	// MARK: - Basic Configuration

	@Test("hasPatterns is false when not configured")
	func noPatternsInitially() {
		let buf = TextBuffer("hello\n")
		let provider = GrammarFoldProvider(buffer: buf)
		#expect(provider.hasPatterns == false)
	}

	@Test("hasPatterns is false when grammar has no fold markers")
	func noPatternsWithoutMarkers() {
		let buf = TextBuffer("hello\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition()
		provider.configure(grammarDefinition: def)
		#expect(provider.hasPatterns == false)
	}

	@Test("hasPatterns is true when grammar has start marker")
	func hasPatternsWithStartMarker() {
		let buf = TextBuffer("hello\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(
			foldingStartMarker: "\\{\\s*$",
			foldingStopMarker: "^\\s*\\}",
		)
		provider.configure(grammarDefinition: def)
		#expect(provider.hasPatterns == true)
	}

	// MARK: - Fold Marker Detection

	@Test("detects start marker on brace line")
	func detectsStartMarker() {
		let buf = TextBuffer("func foo() {\n\tbar()\n}\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(
			foldingStartMarker: "\\{\\s*$",
			foldingStopMarker: "^\\s*\\}",
		)
		provider.configure(grammarDefinition: def)

		let info0 = provider.foldInfo(forLine: 0)
		#expect(info0.isStartMarker == true)
		#expect(info0.isStopMarker == false)
	}

	@Test("detects stop marker on closing brace line")
	func detectsStopMarker() {
		let buf = TextBuffer("func foo() {\n\tbar()\n}\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(
			foldingStartMarker: "\\{\\s*$",
			foldingStopMarker: "^\\s*\\}",
		)
		provider.configure(grammarDefinition: def)

		let info2 = provider.foldInfo(forLine: 2)
		#expect(info2.isStopMarker == true)
		#expect(info2.isStartMarker == false)
	}

	@Test("middle lines have no start/stop markers")
	func middleLinesNoMarkers() {
		let buf = TextBuffer("func foo() {\n\tbar()\n}\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(
			foldingStartMarker: "\\{\\s*$",
			foldingStopMarker: "^\\s*\\}",
		)
		provider.configure(grammarDefinition: def)

		let info1 = provider.foldInfo(forLine: 1)
		#expect(info1.isStartMarker == false)
		#expect(info1.isStopMarker == false)
	}

	// MARK: - Indent Suppression

	@Test("indent-based markers are suppressed when regex markers match")
	func indentSuppressedWhenRegexMatches() {
		// Line 0 ends with {, line 1 is indented → even though indent increases,
		// isIndentStartMarker should be false because isStartMarker is true
		let buf = TextBuffer("if (x) {\n\ty = 1\n}\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(
			foldingStartMarker: "\\{\\s*$",
			foldingStopMarker: "^\\s*\\}",
		)
		provider.configure(grammarDefinition: def)

		let info0 = provider.foldInfo(forLine: 0)
		#expect(info0.isStartMarker == true)
		#expect(info0.isIndentStartMarker == false)
	}

	@Test("indent-based markers used when no regex markers match")
	func indentBasedWhenNoRegex() {
		// No fold markers configured → uses indent-based
		let buf = TextBuffer("top\n\tchild\n\t\tgrandchild\n")
		let provider = GrammarFoldProvider(buffer: buf)
		provider.tabSize = 4
		provider.configure(grammarDefinition: makeGrammarDefinition())

		let info0 = provider.foldInfo(forLine: 0)
		// No markers configured → indent-based available
		#expect(info0.isIndentStartMarker == true)
	}

	// MARK: - Indentation

	@Test("indent is computed correctly for tabs")
	func tabIndent() {
		let buf = TextBuffer("\t\tindented\n")
		let provider = GrammarFoldProvider(buffer: buf)
		provider.tabSize = 4
		let def = makeGrammarDefinition(
			foldingStartMarker: "NOMATCH",
			foldingStopMarker: "NOMATCH",
		)
		provider.configure(grammarDefinition: def)

		let info = provider.foldInfo(forLine: 0)
		#expect(info.indent == 8)
	}

	@Test("indent is computed correctly for spaces")
	func spaceIndent() {
		let buf = TextBuffer("   indented\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(
			foldingStartMarker: "NOMATCH",
			foldingStopMarker: "NOMATCH",
		)
		provider.configure(grammarDefinition: def)

		let info = provider.foldInfo(forLine: 0)
		#expect(info.indent == 3)
	}

	// MARK: - Empty Lines

	@Test("empty line reports isEmpty")
	func emptyLineDetection() {
		let buf = TextBuffer("hello\n\nworld\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(
			foldingStartMarker: "NOMATCH",
			foldingStopMarker: "NOMATCH",
		)
		provider.configure(grammarDefinition: def)

		let info1 = provider.foldInfo(forLine: 1)
		#expect(info1.isEmpty == true)
	}

	@Test("whitespace-only line reports isEmpty")
	func whitespaceOnlyLine() {
		let buf = TextBuffer("hello\n   \nworld\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(
			foldingStartMarker: "NOMATCH",
			foldingStopMarker: "NOMATCH",
		)
		provider.configure(grammarDefinition: def)

		let info1 = provider.foldInfo(forLine: 1)
		#expect(info1.isEmpty == true)
	}

	// MARK: - Out of Range

	@Test("out of range line returns default info")
	func outOfRangeReturnsDefault() {
		let buf = TextBuffer("hello\n")
		let provider = GrammarFoldProvider(buffer: buf)
		let def = makeGrammarDefinition(foldingStartMarker: "\\{")
		provider.configure(grammarDefinition: def)

		let info = provider.foldInfo(forLine: 99)
		#expect(info.isStartMarker == false)
		#expect(info.isStopMarker == false)
		#expect(info.isEmpty == false)
	}

	// MARK: - Reconfiguration

	@Test("configure clears previous patterns")
	func reconfigureClears() {
		let buf = TextBuffer("{\n}\n")
		let provider = GrammarFoldProvider(buffer: buf)

		let def1 = makeGrammarDefinition(foldingStartMarker: "\\{")
		provider.configure(grammarDefinition: def1)
		#expect(provider.hasPatterns == true)

		// Reconfigure with no markers
		provider.configure(grammarDefinition: makeGrammarDefinition())
		#expect(provider.hasPatterns == false)
	}

	// MARK: - Bundle Preference Override

	@Test("bundle preferences override grammar fold markers")
	func bundlePrefsOverrideGrammar() {
		let buf = TextBuffer("BEGIN\n\tcontent\nEND\n")
		let provider = GrammarFoldProvider(buffer: buf)

		// Grammar says braces
		let grammarDef = makeGrammarDefinition(
			scope: "source.test",
			foldingStartMarker: "\\{\\s*$",
			foldingStopMarker: "^\\s*\\}",
		)

		// Bundle prefs say BEGIN/END
		let settingsPlist: [String: Any] = [
			"settings": [
				"foldingStartMarker": "^BEGIN",
				"foldingStopMarker": "^END",
			] as [String: Any],
		]
		let settingsItem = BundleItem(
			uuid: UUID().uuidString,
			name: "Fold Settings",
			kind: .settings,
			scopeSelector: "source.test",
			bundleUUID: "test-bundle",
			plist: settingsPlist,
		)

		let index = BundleIndex()
		index.setIndex(items: [settingsItem], bundles: [])

		provider.configure(
			grammarDefinition: grammarDef,
			bundleIndex: index,
			scope: "source.test",
		)

		// Should match BEGIN/END from bundle prefs, not braces from grammar
		let info0 = provider.foldInfo(forLine: 0)
		#expect(info0.isStartMarker == true, "BEGIN should be a start marker")

		let info2 = provider.foldInfo(forLine: 2)
		#expect(info2.isStopMarker == true, "END should be a stop marker")
	}

	// MARK: - End-to-End Wiring

	@Test("TMDocumentEditor fold provider wired after configureGrammar")
	func editorFoldProviderWired() throws {
		let doc = TMDocument()
		doc.setContent("func foo() {\n\tbar()\n}\n", preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let docEditor = TMDocumentEditor(document: doc, editorView: view)

		// Create a registry with a grammar that has fold markers
		let registry = GrammarRegistry()
		let grammarDef = GrammarDefinition(
			scopeName: "source.test",
			name: "Test",
			fileTypes: ["test"],
			patterns: [],
			repository: [:],
			foldingStartMarker: "\\{\\s*$",
			foldingStopMarker: "^\\s*\\}",
		)
		registry.register(grammarDef)

		let themeEngine = makeThemeEngine()

		docEditor.configureGrammar(
			registry: registry,
			themeEngine: themeEngine,
			scope: "source.test",
		)

		// The fold manager should now compute foldable ranges using the grammar markers
		let fm = try #require(docEditor.foldManager)
		let ranges = fm.foldableRanges()
		// Line 0 ("func foo() {") should be foldable
		#expect(!ranges.isEmpty, "Expected at least one foldable range from grammar markers")
	}

	@Test("fold provider falls back to indent-based when grammar has no fold markers")
	func fallbackToIndentBased() throws {
		let doc = TMDocument()
		doc.setContent("top\n\tchild\n\t\tgrandchild\n", preserveRevision: true)
		let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let docEditor = TMDocumentEditor(document: doc, editorView: view)

		let registry = GrammarRegistry()
		let grammarDef = GrammarDefinition(
			scopeName: "source.plain",
			name: "Plain",
			fileTypes: ["txt"],
			patterns: [],
			repository: [:],
		)
		registry.register(grammarDef)

		let themeEngine = makeThemeEngine()

		docEditor.configureGrammar(
			registry: registry,
			themeEngine: themeEngine,
			scope: "source.plain",
		)

		// Should still get indent-based folding (fallback)
		let fm = try #require(docEditor.foldManager)
		let ranges = fm.foldableRanges()
		#expect(!ranges.isEmpty, "Expected indent-based foldable ranges")
	}
}
