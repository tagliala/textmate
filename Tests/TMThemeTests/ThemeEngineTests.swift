import CoreText
import Foundation
import Testing
import TMGrammar
@testable import TMTheme

// MARK: - FontSizeSpec Tests

@Suite("FontSizeSpec")
struct FontSizeSpecTests {
	@Test("parse absolute pt size")
	func absolutePt() throws {
		let spec = try #require(FontSizeSpec.parse("14pt"))
		if case let .absolute(size) = spec {
			#expect(size == 14)
		} else {
			Issue.record("Expected .absolute")
		}
	}

	@Test("parse absolute bare number")
	func absoluteBare() throws {
		let spec = try #require(FontSizeSpec.parse("16"))
		if case let .absolute(size) = spec {
			#expect(size == 16)
		} else {
			Issue.record("Expected .absolute")
		}
	}

	@Test("parse relative em size")
	func relativeEm() throws {
		let spec = try #require(FontSizeSpec.parse("1.2em"))
		if case let .relative(factor) = spec {
			#expect(abs(factor - 1.2) < 0.001)
		} else {
			Issue.record("Expected .relative")
		}
	}

	@Test("parse relative percentage")
	func relativePercent() throws {
		let spec = try #require(FontSizeSpec.parse("150%"))
		if case let .relative(factor) = spec {
			#expect(abs(factor - 1.5) < 0.001)
		} else {
			Issue.record("Expected .relative")
		}
	}

	@Test("parse nil returns nil")
	func parseNil() {
		#expect(FontSizeSpec.parse(nil) == nil)
	}

	@Test("parse empty returns nil")
	func parseEmpty() {
		#expect(FontSizeSpec.parse("") == nil)
	}

	@Test("resolve absolute")
	func resolveAbsolute() {
		let spec = FontSizeSpec.absolute(18)
		#expect(spec.resolve(base: 12) == 18)
	}

	@Test("resolve relative")
	func resolveRelative() {
		let spec = FontSizeSpec.relative(1.5)
		#expect(spec.resolve(base: 12) == 18)
	}
}

// MARK: - TriBool Tests

@Suite("TriBool")
struct TriBoolTests {
	@Test("init from optional bool")
	func initFromOptional() {
		#expect(TriBool(true) == .true)
		#expect(TriBool(false) == .false)
		#expect(TriBool(nil) == .unset)
	}

	@Test("boolValue")
	func boolValue() {
		#expect(TriBool.true.boolValue == true)
		#expect(TriBool.false.boolValue == false)
		#expect(TriBool.unset.boolValue == false)
	}
}

// MARK: - DecomposedStyle Tests

@Suite("DecomposedStyle")
struct DecomposedStyleTests {
	@Test("merge foreground replaces")
	func mergeForeground() {
		var base = DecomposedStyle(foreground: ThemeColor(red: 1, green: 0, blue: 0))
		let overlay = DecomposedStyle(foreground: ThemeColor(red: 0, green: 1, blue: 0))
		base.merge(overlay)
		#expect(base.foreground?.green == 1.0)
	}

	@Test("merge foreground preserves when rhs is nil")
	func mergeForegroundPreserve() {
		var base = DecomposedStyle(foreground: ThemeColor(red: 1, green: 0, blue: 0))
		let overlay = DecomposedStyle()
		base.merge(overlay)
		#expect(base.foreground?.red == 1.0)
	}

	@Test("merge background blends alpha")
	func mergeBackgroundBlend() throws {
		var base = DecomposedStyle(background: ThemeColor(red: 1, green: 1, blue: 1))
		let overlay = DecomposedStyle(
			background: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.5),
		)
		base.merge(overlay)
		let bg = try #require(base.background)
		// blend: ia * 1.0 + a * 0.0 = 0.5
		#expect(abs(bg.red - 0.5) < 0.01)
		#expect(abs(bg.green - 0.5) < 0.01)
		#expect(abs(bg.blue - 0.5) < 0.01)
		// Alpha preserved from base.
		#expect(bg.alpha == 1.0)
	}

	@Test("merge bool flags: rhs overrides when set")
	func mergeBoolOverride() {
		var base = DecomposedStyle()
		base.bold = .false
		var overlay = DecomposedStyle()
		overlay.bold = .true
		base.merge(overlay)
		#expect(base.bold == .true)
	}

	@Test("merge bool flags: rhs preserves when unset")
	func mergeBoolPreserve() {
		var base = DecomposedStyle()
		base.italic = .true
		let overlay = DecomposedStyle()
		base.merge(overlay)
		#expect(base.italic == .true)
	}

	@Test("merge font name replaces")
	func mergeFontName() {
		var base = DecomposedStyle(fontName: "Menlo")
		let overlay = DecomposedStyle(fontName: "Monaco")
		base.merge(overlay)
		#expect(base.fontName == "Monaco")
	}

	@Test("merge font name preserves when rhs is nil")
	func mergeFontNamePreserve() {
		var base = DecomposedStyle(fontName: "Menlo")
		let overlay = DecomposedStyle()
		base.merge(overlay)
		#expect(base.fontName == "Menlo")
	}

	@Test("merge absolute font size replaces")
	func mergeAbsoluteSize() {
		var base = DecomposedStyle(fontSizeSpec: .absolute(12))
		let overlay = DecomposedStyle(fontSizeSpec: .absolute(18))
		base.merge(overlay)
		if case let .absolute(size)? = base.fontSizeSpec {
			#expect(size == 18)
		} else {
			Issue.record("Expected .absolute")
		}
	}

	@Test("merge relative font size multiplies absolute base")
	func mergeRelativeOnAbsolute() {
		var base = DecomposedStyle(fontSizeSpec: .absolute(10))
		let overlay = DecomposedStyle(fontSizeSpec: .relative(1.5))
		base.merge(overlay)
		if case let .absolute(size)? = base.fontSizeSpec {
			#expect(size == 15)
		} else {
			Issue.record("Expected .absolute after relative merge")
		}
	}
}

// MARK: - ThemeEngine Tests

@Suite("ThemeEngine")
struct ThemeEngineTests {
	// Helper: build a minimal theme.
	private func makeTheme(
		background: ThemeColor = ThemeColor(red: 0.1, green: 0.1, blue: 0.1),
		foreground: ThemeColor = ThemeColor(red: 0.9, green: 0.9, blue: 0.9),
		rules: [ThemeStyleRule] = [],
	) -> Theme {
		Theme(
			name: "Test",
			semanticClass: "theme.dark.test",
			uuid: "00000000-0000-0000-0000-000000000000",
			globalSettings: ThemeGlobalSettings(
				foreground: foreground,
				background: background,
				caret: ThemeColor(red: 1, green: 1, blue: 1),
				selection: ThemeColor(red: 0.3, green: 0.3, blue: 0.5),
			),
			gutterSettings: ThemeGutterSettings(),
			rules: rules,
		)
	}

	@Test("engine returns global style for unmatched scope")
	func globalFallback() throws {
		let theme = makeTheme()
		let engine = ThemeEngine(theme: theme, fontSize: 14)
		let style = engine.stylesForScope(Scope("text.plain"))

		// Foreground should be the global foreground.
		let components = try #require(style.foreground.components)
		#expect(abs(components[0] - 0.9) < 0.01)
		#expect(!style.isUnderlined)
		#expect(!style.isStrikethrough)
		#expect(!style.isMisspelled)
	}

	@Test("engine resolves scope-specific foreground")
	func scopeSpecificColor() throws {
		let rules = [
			ThemeStyleRule(
				scopeSelector: "comment",
				foreground: ThemeColor(red: 0.5, green: 0.5, blue: 0.5),
			),
		]
		let theme = makeTheme(rules: rules)
		let engine = ThemeEngine(theme: theme)

		let style = engine.stylesForScope(Scope("source.swift comment.line"))
		let components = try #require(style.foreground.components)
		#expect(abs(components[0] - 0.5) < 0.01) // comment foreground
	}

	@Test("higher specificity rule wins")
	func specificityOrdering() throws {
		let rules = [
			ThemeStyleRule(
				scopeSelector: "string",
				foreground: ThemeColor(red: 1, green: 0, blue: 0),
			),
			ThemeStyleRule(
				scopeSelector: "string.quoted",
				foreground: ThemeColor(red: 0, green: 1, blue: 0),
			),
		]
		let theme = makeTheme(rules: rules)
		let engine = ThemeEngine(theme: theme)

		let style = engine.stylesForScope(Scope("source.swift string.quoted.double"))
		let c = try #require(style.foreground.components)
		// string.quoted is more specific, merged last → green wins.
		#expect(abs(c[1] - 1.0) < 0.01)
	}

	@Test("bold and italic produce font with traits")
	func boldItalicFont() {
		let rules = [
			ThemeStyleRule(
				scopeSelector: "keyword",
				isBold: true,
				isItalic: true,
			),
		]
		let theme = makeTheme(rules: rules)
		let engine = ThemeEngine(theme: theme)

		let style = engine.stylesForScope(Scope("source.swift keyword.control"))
		let traits = CTFontGetSymbolicTraits(style.font)
		#expect(traits.contains(.boldTrait))
		#expect(traits.contains(.italicTrait))
	}

	@Test("underline and strikethrough flags propagate")
	func underlineStrikethrough() {
		let rules = [
			ThemeStyleRule(
				scopeSelector: "markup.underline",
				isUnderlined: true,
				isStrikethrough: true,
			),
		]
		let theme = makeTheme(rules: rules)
		let engine = ThemeEngine(theme: theme)

		let style = engine.stylesForScope(Scope("text.html markup.underline"))
		#expect(style.isUnderlined)
		#expect(style.isStrikethrough)
	}

	@Test("cache returns same result for repeated scope")
	func cacheHit() throws {
		let theme = makeTheme()
		let engine = ThemeEngine(theme: theme)
		let scope = Scope("source.ruby string.quoted")
		let s1 = engine.stylesForScope(scope)
		let s2 = engine.stylesForScope(scope)
		// Both should be equivalent (same colors).
		let c1 = try #require(s1.foreground.components)
		let c2 = try #require(s2.foreground.components)
		#expect(c1[0] == c2[0])
	}

	@Test("invalidateCache clears cached entries")
	func invalidateCache() {
		let theme = makeTheme()
		let engine = ThemeEngine(theme: theme)
		_ = engine.stylesForScope(Scope("source.swift"))
		engine.invalidateCache()
		// Should not crash and should recompute.
		let style = engine.stylesForScope(Scope("source.swift"))
		#expect(style.foreground.components != nil)
	}

	@Test("copyWithFont produces new engine with different font")
	func copyWithFont() {
		let theme = makeTheme()
		let engine = ThemeEngine(theme: theme, fontName: "Menlo", fontSize: 12)
		let copy = engine.copyWithFont(name: "Monaco", size: 18)
		#expect(copy.fontName == "Monaco")
		#expect(copy.fontSize == 18)
		#expect(copy.theme.name == "Test")
	}

	@Test("two-sided scope context resolves styles")
	func twoSidedContext() throws {
		let rules = [
			ThemeStyleRule(
				scopeSelector: "source.swift",
				foreground: ThemeColor(red: 0.2, green: 0.8, blue: 0.3),
			),
		]
		let theme = makeTheme(rules: rules)
		let engine = ThemeEngine(theme: theme)

		let context = ScopeContext(
			left: Scope("source.swift"),
			right: Scope("source.swift string"),
		)
		let style = engine.stylesForScope(context)
		let c = try #require(style.foreground.components)
		#expect(abs(c[1] - 0.8) < 0.01)
	}

	@Test("multiple rules merge colors and flags")
	func multipleRulesMerge() throws {
		let rules = [
			ThemeStyleRule(
				scopeSelector: "source",
				foreground: ThemeColor(red: 1, green: 0, blue: 0),
				isBold: true,
			),
			ThemeStyleRule(
				scopeSelector: "source.swift",
				isItalic: true,
			),
		]
		let theme = makeTheme(rules: rules)
		let engine = ThemeEngine(theme: theme)

		let style = engine.stylesForScope(Scope("source.swift"))
		// Both bold (from "source") and italic (from "source.swift") should be set.
		let traits = CTFontGetSymbolicTraits(style.font)
		#expect(traits.contains(.boldTrait))
		#expect(traits.contains(.italicTrait))
		// Foreground from "source" since "source.swift" doesn't set one.
		let c = try #require(style.foreground.components)
		#expect(abs(c[0] - 1.0) < 0.01) // red
	}

	@Test("default font is system monospace")
	func defaultFont() {
		let theme = makeTheme()
		let engine = ThemeEngine(theme: theme, fontSize: 13)
		let style = engine.stylesForScope(Scope("text.plain"))
		let size = CTFontGetSize(style.font)
		#expect(abs(size - 13) < 0.01)
	}

	@Test("custom font name is used")
	func customFont() {
		let theme = makeTheme()
		let engine = ThemeEngine(theme: theme, fontName: "Menlo", fontSize: 11)
		let style = engine.stylesForScope(Scope("text.plain"))
		let name = CTFontCopyFamilyName(style.font) as String
		#expect(name == "Menlo")
	}

	@Test("rule with font name overrides engine font")
	func ruleFontOverride() {
		let rules = [
			ThemeStyleRule(
				scopeSelector: "keyword",
				fontName: "Courier",
			),
		]
		let theme = makeTheme(rules: rules)
		let engine = ThemeEngine(theme: theme, fontName: "Menlo", fontSize: 12)

		let style = engine.stylesForScope(Scope("source.swift keyword"))
		let name = CTFontCopyFamilyName(style.font) as String
		#expect(name == "Courier")
	}

	@Test("deco.invisible synthetic rule emitted for invisibles color")
	func invisiblesSyntheticRule() throws {
		let rules = [
			ThemeStyleRule(
				scopeSelector: "comment",
				invisibles: ThemeColor(red: 0.3, green: 0.3, blue: 0.3),
			),
		]
		let theme = makeTheme(rules: rules)
		let engine = ThemeEngine(theme: theme)

		// The deco.invisible scope should pick up the invisibles color as foreground.
		let style = engine.stylesForScope(Scope("deco.invisible"))
		let c = try #require(style.foreground.components)
		#expect(abs(c[0] - 0.3) < 0.01)
	}

	@Test("unmatched scope uses global caret and selection")
	func globalCaretAndSelection() throws {
		let theme = makeTheme()
		let engine = ThemeEngine(theme: theme)

		let style = engine.stylesForScope(Scope("text.plain"))
		let caretComponents = try #require(style.caret.components)
		#expect(abs(caretComponents[0] - 1.0) < 0.01) // white caret
		let selComponents = try #require(style.selection.components)
		#expect(abs(selComponents[0] - 0.3) < 0.01) // from init
	}
}

// MARK: - ThemeEngine Integration with ThemeLoader

@Suite("ThemeEngine + ThemeLoader")
struct ThemeEngineLoaderTests {
	private func twilightPlist() -> Data {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
		"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
			<key>name</key>
			<string>Twilight</string>
			<key>semanticClass</key>
			<string>theme.dark.twilight</string>
			<key>uuid</key>
			<string>766026CB-703D-4610-B070-8DE07D967C5F</string>
			<key>settings</key>
			<array>
				<dict>
					<key>settings</key>
					<dict>
						<key>background</key>
						<string>#181818</string>
						<key>caret</key>
						<string>#A7A7A7</string>
						<key>foreground</key>
						<string>#F8F8F8</string>
						<key>invisibles</key>
						<string>#FFFFFF40</string>
						<key>selection</key>
						<string>#DDF0FF33</string>
					</dict>
				</dict>
				<dict>
					<key>name</key>
					<string>Comment</string>
					<key>scope</key>
					<string>comment</string>
					<key>settings</key>
					<dict>
						<key>fontStyle</key>
						<string>italic</string>
						<key>foreground</key>
						<string>#5F5A60</string>
					</dict>
				</dict>
				<dict>
					<key>name</key>
					<string>Constant</string>
					<key>scope</key>
					<string>constant</string>
					<key>settings</key>
					<dict>
						<key>foreground</key>
						<string>#CF6A4C</string>
					</dict>
				</dict>
				<dict>
					<key>name</key>
					<string>Keyword</string>
					<key>scope</key>
					<string>keyword</string>
					<key>settings</key>
					<dict>
						<key>fontStyle</key>
						<string>bold</string>
						<key>foreground</key>
						<string>#CDA869</string>
					</dict>
				</dict>
				<dict>
					<key>name</key>
					<string>String</string>
					<key>scope</key>
					<string>string</string>
					<key>settings</key>
					<dict>
						<key>foreground</key>
						<string>#8F9D6A</string>
					</dict>
				</dict>
			</array>
		</dict>
		</plist>
		"""
		return Data(xml.utf8)
	}

	@Test("load and resolve styles from Twilight theme")
	func loadAndResolve() throws {
		let theme = try ThemeLoader.load(from: twilightPlist())
		let engine = ThemeEngine(theme: theme, fontSize: 14)

		// Comment: italic, foreground #5F5A60.
		let commentStyle = engine.stylesForScope(Scope("source.swift comment.line"))
		let traits = CTFontGetSymbolicTraits(commentStyle.font)
		#expect(traits.contains(.italicTrait))
		let c = try #require(commentStyle.foreground.components)
		#expect(abs(c[0] - 0x5F / 255.0) < 0.01)

		// Keyword: bold, foreground #CDA869.
		let kwStyle = engine.stylesForScope(Scope("source.swift keyword.control"))
		let kwTraits = CTFontGetSymbolicTraits(kwStyle.font)
		#expect(kwTraits.contains(.boldTrait))
		let k = try #require(kwStyle.foreground.components)
		#expect(abs(k[0] - 0xCD / 255.0) < 0.01)

		// Constant: plain, foreground #CF6A4C.
		let constStyle = engine.stylesForScope(Scope("source.swift constant.numeric"))
		let constTraits = CTFontGetSymbolicTraits(constStyle.font)
		#expect(!constTraits.contains(.boldTrait))
		#expect(!constTraits.contains(.italicTrait))
	}

	@Test("background uses global for unscoped text")
	func globalBackground() throws {
		let theme = try ThemeLoader.load(from: twilightPlist())
		let engine = ThemeEngine(theme: theme, fontSize: 12)

		let style = engine.stylesForScope(Scope("text.plain"))
		let c = try #require(style.background.components)
		// #181818
		#expect(abs(c[0] - 0x18 / 255.0) < 0.01)
	}
}
