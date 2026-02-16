#if canImport(AppKit)
import AppKit
import Testing
@testable import TMServices

@Suite("EventStringFormatter")
struct EventStringFormatterTests {
	// MARK: - Parsing

	@Test("Parse simple command key")
	func parseCommandKey() {
		let result = EventStringFormatter.parse("@s")
		#expect(result.flags == .command)
		#expect(result.key == "s")
	}

	@Test("Parse shift+command key")
	func parseShiftCommand() {
		let result = EventStringFormatter.parse("@$s")
		#expect(result.flags.contains(.command))
		#expect(result.flags.contains(.shift))
		#expect(result.key == "s")
	}

	@Test("Parse all modifier flags")
	func parseAllModifiers() {
		let result = EventStringFormatter.parse("$^~@x")
		#expect(result.flags.contains(.shift))
		#expect(result.flags.contains(.control))
		#expect(result.flags.contains(.option))
		#expect(result.flags.contains(.command))
		#expect(result.key == "x")
	}

	@Test("Parse numpad flag")
	func parseNumpad() {
		let result = EventStringFormatter.parse("#5")
		#expect(result.flags.contains(.numericPad))
		#expect(result.key == "5")
	}

	@Test("Parse empty string")
	func parseEmpty() {
		let result = EventStringFormatter.parse("")
		#expect(result.key == "")
		#expect(result.flags.isEmpty)
	}

	// MARK: - Creation

	@Test("Create event string from components")
	func create() {
		let result = EventStringFormatter.create(key: "s", flags: [.command, .shift])
		// Should contain @ for command and $ for shift, then the key
		#expect(result.contains("@"))
		#expect(result.contains("$"))
		#expect(result.hasSuffix("s"))
	}

	@Test("Create round-trips with parse")
	func createRoundTrip() {
		let original = EventStringFormatter.create(key: "z", flags: [.command])
		let parsed = EventStringFormatter.parse(original)
		#expect(parsed.key == "z")
		#expect(parsed.flags == .command)
	}

	// MARK: - Normalization

	@Test("Normalize reorders modifiers consistently")
	func normalize() {
		let a = EventStringFormatter.normalize("@$^~x")
		let b = EventStringFormatter.normalize("~^$@x")
		#expect(a == b)
	}

	// MARK: - Glyph Rendering

	@Test("Glyphs for modifier flags")
	func glyphsForFlags() {
		let glyphs = EventStringFormatter.glyphsForFlags([.control, .option, .shift, .command])
		// Standard order: ⌃⌥⇧⌘
		#expect(glyphs.contains("⌃"))
		#expect(glyphs.contains("⌥"))
		#expect(glyphs.contains("⇧"))
		#expect(glyphs.contains("⌘"))
	}

	@Test("Glyphs for event string with named keys")
	func glyphsForNamedKey() {
		let glyphs = EventStringFormatter.glyphsForEventString("@\u{F728}") // Delete Forward
		#expect(glyphs.contains("⌘"))
		#expect(glyphs.count > 1)
	}

	@Test("Glyphs auto-detect shift for uppercase")
	func glyphsAutoShift() {
		let glyphs = EventStringFormatter.glyphsForEventString("@S")
		// Should auto-detect shift for uppercase S
		#expect(glyphs.contains("⇧"))
	}

	// MARK: - Attributed String

	@Test("Attributed string is created")
	func attributedString() {
		let font = NSFont.menuFont(ofSize: 0)
		let attrStr = EventStringFormatter.attributedString(for: "@s", font: font)
		#expect(attrStr.length > 0)
	}

	@Test("Attributed string for empty is minimal")
	func attributedStringEmpty() {
		let font = NSFont.menuFont(ofSize: 0)
		let attrStr = EventStringFormatter.attributedString(for: "", font: font)
		// Empty event string may produce a minimal attributed string
		#expect(attrStr.length <= 1)
	}

	@Test("Function key glyphs")
	func functionKeyGlyphs() {
		// F1 = \u{F704}
		let glyphs = EventStringFormatter.glyphsForEventString("\u{F704}")
		#expect(glyphs.contains("F1"))
	}

	@Test("Tab key glyph")
	func tabKeyGlyph() {
		let glyphs = EventStringFormatter.glyphsForEventString("\t")
		#expect(glyphs.contains("⇥"))
	}
}

#endif
