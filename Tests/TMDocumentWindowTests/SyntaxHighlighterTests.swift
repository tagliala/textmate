import AppKit
import Testing
import TMBundle
import TMBundleRuntime
import TMEditorUI
import TMGrammar
import TMTheme
@testable import TMDocumentWindow

// MARK: - Test Helpers

/// Creates a minimal theme with a rule that colors "keyword" scopes red.
private func makeTheme(
	foreground: ThemeColor = ThemeColor(red: 0, green: 0, blue: 0),
	background: ThemeColor = ThemeColor(red: 1, green: 1, blue: 1),
	rules: [ThemeStyleRule] = [],
) -> Theme {
	Theme(
		name: "Test",
		semanticClass: "theme.light.test",
		uuid: "00000000-0000-0000-0000-000000000001",
		globalSettings: ThemeGlobalSettings(
			foreground: foreground,
			background: background,
		),
		gutterSettings: ThemeGutterSettings(),
		rules: rules,
	)
}

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

/// Creates a grammar + registry + engine + highlighter ready to use.
@MainActor
private func makeHighlighter(
	grammarDef: GrammarDefinition? = nil,
	theme: Theme? = nil,
	redKeywords: Bool = true,
) -> SyntaxHighlighter {
	let registry = GrammarRegistry()
	let gramDef = grammarDef ?? makeKeywordGrammar()
	registry.register(gramDef)

	let themeRules: [ThemeStyleRule] = redKeywords ? [
		ThemeStyleRule(
			scopeSelector: "keyword",
			name: "Keywords",
			foreground: ThemeColor(red: 1, green: 0, blue: 0),
		),
	] : []

	let engine = ThemeEngine(
		theme: theme ?? makeTheme(rules: themeRules),
		fontSize: 12,
	)

	let highlighter = SyntaxHighlighter(
		grammarRegistry: registry,
		themeEngine: engine,
	)
	highlighter.setGrammar(scope: gramDef.scopeName)
	return highlighter
}

// MARK: - SyntaxHighlighter Tests

@Suite("SyntaxHighlighter — Core")
@MainActor
struct SyntaxHighlighterCoreTests {
	@Test("no grammar produces empty style runs")
	func noGrammar() {
		let hl = SyntaxHighlighter()
		let runs = hl.styleRuns(forLine: 0, text: "hello world")
		#expect(runs.isEmpty)
	}

	@Test("no theme engine produces empty style runs")
	func noThemeEngine() {
		let registry = GrammarRegistry()
		registry.register(makeKeywordGrammar())
		let hl = SyntaxHighlighter(grammarRegistry: registry)
		hl.setGrammar(scope: "source.test")
		hl.setText("keyword test")
		hl.parseSync()
		let runs = hl.styleRuns(forLine: 0, text: "keyword test")
		#expect(runs.isEmpty)
	}

	@Test("unknown grammar scope clears parser")
	func unknownGrammar() {
		let hl = makeHighlighter()
		hl.setGrammar(scope: "source.nonexistent")
		#expect(hl.parser == nil)
		#expect(hl.activeScope == "source.nonexistent")
	}

	@Test("setting nil grammar clears parser")
	func nilGrammar() {
		let hl = makeHighlighter()
		#expect(hl.parser != nil)
		hl.setGrammar(scope: nil as String?)
		#expect(hl.parser == nil)
		#expect(hl.activeScope == nil)
	}

	@Test("hasDirtyLines after setText")
	func dirtyAfterSetText() {
		let hl = makeHighlighter()
		hl.setText("hello keyword world")
		#expect(hl.parser?.hasDirtyLines == true)
	}

	@Test("parseSync clears dirty lines")
	func parseSyncClearsDirty() {
		let hl = makeHighlighter()
		hl.setText("hello keyword world")
		hl.parseSync()
		#expect(hl.parser?.hasDirtyLines == false)
	}
}

// MARK: - Style Run Generation Tests

@Suite("SyntaxHighlighter — Style Runs")
@MainActor
struct SyntaxHighlighterStyleRunTests {
	@Test("keyword gets distinct foreground color")
	func keywordColor() {
		let hl = makeHighlighter()
		hl.setText("hello keyword world\n")
		hl.parseSync()

		let runs = hl.styleRuns(forLine: 0, text: "hello keyword world")
		#expect(!runs.isEmpty)

		// At least one run should have a red-ish foreground (keyword.test → red)
		let hasRed = runs.contains { run in
			let red = run.foreground.redComponent
			let green = run.foreground.greenComponent
			return red > 0.8 && green < 0.2
		}
		#expect(hasRed, "Expected a red-colored run for 'keyword'")
	}

	@Test("runs cover entire line length")
	func runsCoverFullLine() {
		let hl = makeHighlighter()
		let text = "hello keyword world"
		hl.setText(text + "\n")
		hl.parseSync()

		let runs = hl.styleRuns(forLine: 0, text: text)
		guard !runs.isEmpty else { return }

		// Verify runs are contiguous and cover the whole line
		let totalCovered = runs.reduce(0) { $0 + $1.length }
		#expect(totalCovered == text.utf8.count)
	}

	@Test("runs are contiguous")
	func runsContiguous() {
		let hl = makeHighlighter()
		let text = "a keyword b"
		hl.setText(text + "\n")
		hl.parseSync()

		let runs = hl.styleRuns(forLine: 0, text: text)
		guard runs.count > 1 else { return }

		for i in 1 ..< runs.count {
			#expect(
				runs[i].start == runs[i - 1].start + runs[i - 1].length,
				"Run \(i) should start where run \(i - 1) ends",
			)
		}
	}

	@Test("empty line produces no runs")
	func emptyLine() {
		let hl = makeHighlighter()
		hl.setText("line1\n\nline3\n")
		hl.parseSync()

		let runs = hl.styleRuns(forLine: 1, text: "")
		#expect(runs.isEmpty)
	}

	@Test("line without keywords uses default color")
	func plainLineDefaultColor() {
		let hl = makeHighlighter()
		let text = "hello world"
		hl.setText(text + "\n")
		hl.parseSync()

		let runs = hl.styleRuns(forLine: 0, text: text)
		for run in runs {
			// No run should be red since there's no keyword
			let red = run.foreground.redComponent
			let green = run.foreground.greenComponent
			let blue = run.foreground.blueComponent
			// Default foreground is black (0,0,0) — should not be bright red
			let isBrightRed = red > 0.8 && green < 0.2 && blue < 0.2
			#expect(!isBrightRed, "Plain text shouldn't have keyword color")
		}
	}

	@Test("multi-line document per-line style runs")
	func multiLineRuns() {
		let hl = makeHighlighter()
		hl.setText("hello\nkeyword\nworld\n")
		hl.parseSync()

		let runs0 = hl.styleRuns(forLine: 0, text: "hello")
		let runs1 = hl.styleRuns(forLine: 1, text: "keyword")
		let runs2 = hl.styleRuns(forLine: 2, text: "world")

		// Line 0 and 2 should have no red; line 1 should
		let line1HasRed = runs1.contains { run in
			run.foreground.redComponent > 0.8 && run.foreground.greenComponent < 0.2
		}
		#expect(line1HasRed, "Line 1 ('keyword') should be colored red")

		for run in runs0 {
			let isRed = run.foreground.redComponent > 0.8 && run.foreground.greenComponent < 0.2
			#expect(!isRed, "Line 0 should not be red")
		}
		for run in runs2 {
			let isRed = run.foreground.redComponent > 0.8 && run.foreground.greenComponent < 0.2
			#expect(!isRed, "Line 2 should not be red")
		}
	}
}

// MARK: - Style Provider Callback Tests

@Suite("SyntaxHighlighter — Style Provider")
@MainActor
struct SyntaxHighlighterProviderTests {
	@Test("makeStyleProvider returns working closure")
	func styleProviderClosure() {
		let hl = makeHighlighter()
		hl.setText("keyword\n")
		hl.parseSync()

		let provider = hl.makeStyleProvider()
		let runs = provider(0, "keyword")
		#expect(!runs.isEmpty)
	}

	@Test("style provider produces same results as direct call")
	func styleProviderMatchesDirect() {
		let hl = makeHighlighter()
		hl.setText("hello keyword\n")
		hl.parseSync()

		let direct = hl.styleRuns(forLine: 0, text: "hello keyword")
		let provider = hl.makeStyleProvider()
		let indirect = provider(0, "hello keyword")

		#expect(direct.count == indirect.count)
		for (d, i) in zip(direct, indirect) {
			#expect(d.start == i.start)
			#expect(d.length == i.length)
		}
	}
}

// MARK: - Invalidation Tests

@Suite("SyntaxHighlighter — Invalidation")
@MainActor
struct SyntaxHighlighterInvalidationTests {
	@Test("onStylesChanged fires for changed lines")
	func callbackFires() {
		let hl = makeHighlighter()
		hl.setText("hello\nworld\n")
		hl.parseSync()

		var changedRanges: [Range<Int>] = []
		hl.onStylesChanged = { range in
			changedRanges.append(range)
		}

		// Invalidate and re-parse
		hl.invalidateLines(0 ..< 1)
		hl.parseSync()

		#expect(!changedRanges.isEmpty)
	}

	@Test("parseSync returns changed ranges")
	func parseSyncReturnsRanges() {
		let hl = makeHighlighter()
		hl.setText("hello\nworld\nkeyword\n")
		let ranges = hl.parseSync()

		// Initial parse should report all lines as changed
		#expect(!ranges.isEmpty)
	}
}

// MARK: - Theme Switching Tests

@Suite("SyntaxHighlighter — Theme Switching")
@MainActor
struct SyntaxHighlighterThemeSwitchTests {
	@Test("switching theme engine changes style output")
	func themeSwitchChangesStyles() {
		let hl = makeHighlighter()
		hl.setText("keyword\n")
		hl.parseSync()

		let runsBeforeSwitch = hl.styleRuns(forLine: 0, text: "keyword")

		// Switch to a theme where keywords are green
		let greenTheme = makeTheme(
			rules: [
				ThemeStyleRule(
					scopeSelector: "keyword",
					name: "Keywords",
					foreground: ThemeColor(red: 0, green: 1, blue: 0),
				),
			],
		)
		let greenEngine = ThemeEngine(theme: greenTheme, fontSize: 12)
		hl.setThemeEngine(greenEngine)

		let runsAfterSwitch = hl.styleRuns(forLine: 0, text: "keyword")

		// The foreground colors should be different
		guard let before = runsBeforeSwitch.first(where: { $0.foreground.redComponent > 0.5 }),
		      let after = runsAfterSwitch.first(where: { $0.foreground.greenComponent > 0.5 })
		else {
			return
		}
		#expect(before.foreground != after.foreground)
	}
}

// MARK: - Bold / Italic Rule Tests

@Suite("SyntaxHighlighter — Font Traits")
@MainActor
struct SyntaxHighlighterFontTraitTests {
	@Test("bold rule produces bold style run")
	func boldRule() {
		let theme = makeTheme(
			rules: [
				ThemeStyleRule(
					scopeSelector: "keyword",
					name: "Keyword",
					foreground: ThemeColor(red: 1, green: 0, blue: 0),
					isBold: true,
				),
			],
		)
		let registry = GrammarRegistry()
		registry.register(makeKeywordGrammar())
		let engine = ThemeEngine(theme: theme, fontSize: 12)
		let hl = SyntaxHighlighter(grammarRegistry: registry, themeEngine: engine)
		hl.setGrammar(scope: "source.test")
		hl.setText("keyword\n")
		hl.parseSync()

		let runs = hl.styleRuns(forLine: 0, text: "keyword")
		let boldRun = runs.first { $0.foreground.redComponent > 0.5 }
		#expect(boldRun?.isBold == true)
	}

	@Test("italic rule produces italic style run")
	func italicRule() {
		let theme = makeTheme(
			rules: [
				ThemeStyleRule(
					scopeSelector: "keyword",
					name: "Keyword",
					foreground: ThemeColor(red: 1, green: 0, blue: 0),
					isItalic: true,
				),
			],
		)
		let registry = GrammarRegistry()
		registry.register(makeKeywordGrammar())
		let engine = ThemeEngine(theme: theme, fontSize: 12)
		let hl = SyntaxHighlighter(grammarRegistry: registry, themeEngine: engine)
		hl.setGrammar(scope: "source.test")
		hl.setText("keyword\n")
		hl.parseSync()

		let runs = hl.styleRuns(forLine: 0, text: "keyword")
		let italicRun = runs.first { $0.foreground.redComponent > 0.5 }
		#expect(italicRun?.isItalic == true)
	}
}

// MARK: - Integration with Layout Manager

@Suite("SyntaxHighlighter — Layout Manager Integration")
@MainActor
struct SyntaxHighlighterLayoutTests {
	@Test("style provider wired to layout manager produces styled lines")
	func layoutManagerIntegration() {
		let hl = makeHighlighter()
		hl.setText("hello keyword world\n")
		hl.parseSync()

		let lm = EditorLayoutManager()
		lm.setText("hello keyword world")
		lm.styleProvider = hl.makeStyleProvider()

		// Layout the line
		let laid = lm.layoutLines(in: CGRect(x: 0, y: 0, width: 800, height: 100))
		#expect(!laid.isEmpty)
		// The laid-out line should have style runs
		#expect(!laid[0].styleRuns.isEmpty)
	}
}

// MARK: - Symbol Extraction Tests

/// Helper: Creates a ``BundleIndex`` containing a single preference item
/// that marks `keyword.test` scopes for the symbol list.
private func makeSymbolBundleIndex(
	showInSymbolList: Bool = true,
	symbolTransformation: String? = nil,
	scopeSelector: String = "keyword.test",
) -> BundleIndex {
	var settings: [String: Any] = [
		"showInSymbolList": showInSymbolList,
	]
	if let symbolTransformation {
		settings["symbolTransformation"] = symbolTransformation
	}

	let item = BundleItem(
		uuid: "sym-pref-001",
		name: "Symbol Preferences",
		kind: .settings,
		scopeSelector: scopeSelector,
		bundleUUID: "bundle-001",
		plist: ["settings": settings],
	)

	let index = BundleIndex()
	index.addItems([item])
	return index
}

@Suite("SyntaxHighlighter — Symbol Extraction")
@MainActor
struct SyntaxHighlighterSymbolTests {
	@Test("extracts symbol from keyword scope with showInSymbolList")
	func basicSymbolExtraction() {
		let hl = makeHighlighter()
		let text = "hello keyword world\n"
		hl.setText(text)
		hl.parseSync()

		let index = makeSymbolBundleIndex()
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let symbols = hl.extractSymbols(bundleIndex: index, lines: lines)

		#expect(symbols.count == 1)
		#expect(symbols.first?.name == "keyword")
		#expect(symbols.first?.selectionString == "1")
	}

	@Test("returns empty when no preferences match")
	func noMatchingPreferences() {
		let hl = makeHighlighter()
		let text = "hello keyword world\n"
		hl.setText(text)
		hl.parseSync()

		// Scope selector that doesn't match keyword.test
		let index = makeSymbolBundleIndex(scopeSelector: "string.quoted")
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let symbols = hl.extractSymbols(bundleIndex: index, lines: lines)

		#expect(symbols.isEmpty)
	}

	@Test("returns empty when showInSymbolList is false")
	func showInSymbolListFalse() {
		let hl = makeHighlighter()
		let text = "hello keyword world\n"
		hl.setText(text)
		hl.parseSync()

		let index = makeSymbolBundleIndex(showInSymbolList: false)
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let symbols = hl.extractSymbols(bundleIndex: index, lines: lines)

		#expect(symbols.isEmpty)
	}

	@Test("returns empty when text has no matching scopes")
	func noKeywordsInText() {
		let hl = makeHighlighter()
		let text = "hello world\n"
		hl.setText(text)
		hl.parseSync()

		let index = makeSymbolBundleIndex()
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let symbols = hl.extractSymbols(bundleIndex: index, lines: lines)

		#expect(symbols.isEmpty)
	}

	@Test("applies symbolTransformation to extracted text")
	func symbolTransformation() {
		let hl = makeHighlighter()
		let text = "hello keyword world\n"
		hl.setText(text)
		hl.parseSync()

		// Transform: prepend "SYM:" to the symbol name
		let index = makeSymbolBundleIndex(symbolTransformation: "s/.*/SYM: $0/")
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let symbols = hl.extractSymbols(bundleIndex: index, lines: lines)

		#expect(symbols.count == 1)
		#expect(symbols.first?.name == "SYM: keyword")
	}

	@Test("extracts multiple keywords across lines")
	func multipleSymbolsAcrossLines() {
		let hl = makeHighlighter()
		let text = "keyword one\nplain\nkeyword two\n"
		hl.setText(text)
		hl.parseSync()

		let index = makeSymbolBundleIndex()
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let symbols = hl.extractSymbols(bundleIndex: index, lines: lines)

		#expect(symbols.count == 2)
		#expect(symbols[0].name == "keyword")
		#expect(symbols[0].selectionString == "1")
		#expect(symbols[1].name == "keyword")
		#expect(symbols[1].selectionString == "3")
	}

	@Test("returns empty when no parser is set")
	func noParser() {
		let hl = SyntaxHighlighter()
		let index = makeSymbolBundleIndex()
		let symbols = hl.extractSymbols(bundleIndex: index, lines: ["hello\n"])

		#expect(symbols.isEmpty)
	}

	@Test("returns empty for empty document")
	func emptyDocument() {
		let hl = makeHighlighter()
		hl.setText("")
		hl.parseSync()

		let index = makeSymbolBundleIndex()
		let symbols = hl.extractSymbols(bundleIndex: index, lines: [""])

		#expect(symbols.isEmpty)
	}

	@Test("symbol offset reflects byte position in document")
	func symbolOffset() {
		let hl = makeHighlighter()
		// "hello " = 6 bytes, then "keyword" starts at offset 6
		let text = "hello keyword\n"
		hl.setText(text)
		hl.parseSync()

		let index = makeSymbolBundleIndex()
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let symbols = hl.extractSymbols(bundleIndex: index, lines: lines)

		#expect(symbols.count == 1)
		#expect(symbols.first?.offset == 6)
	}
}
