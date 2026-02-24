import Testing
@testable import TMEditorUI

@Suite("SoftBreaks")
struct SoftBreaksTests {
	// MARK: - Basic Cases

	@Test("empty string returns no breaks")
	func emptyString() {
		let breaks = softBreaks(in: "", width: 10, tabSize: 4)
		#expect(breaks.isEmpty)
	}

	@Test("short string returns no breaks")
	func shortString() {
		let breaks = softBreaks(in: "foo", width: 10, tabSize: 4)
		#expect(breaks.isEmpty)
	}

	@Test("string exactly at width returns no breaks")
	func exactWidth() {
		let breaks = softBreaks(in: "foo bar xy", width: 10, tabSize: 4)
		#expect(breaks.isEmpty)
	}

	@Test("string one char over width breaks at word boundary")
	func oneOverAtWord() {
		// "foo bar xyz" — 11 chars, width 10
		// Should break after "bar " (offset 8) so "foo bar " fits in 10
		let breaks = softBreaks(in: "foo bar xyz", width: 10, tabSize: 4)
		#expect(breaks.count == 1)
		#expect(breaks[0] == 8) // break after "foo bar "
	}

	@Test("no spaces causes hard break at column limit")
	func noSpacesHardBreak() {
		// "foo-bar-xyz" — 11 chars, width 10
		// No space to break at, so hard break at offset 10
		let breaks = softBreaks(in: "foo-bar-xyz", width: 10, tabSize: 4)
		#expect(breaks.count == 1)
		#expect(breaks[0] == 10) // hard break at column 10
	}

	@Test("multiple breaks for very long line")
	func multipleBreaks() {
		// "foo bar xyz fud baz abc def"
		let breaks = softBreaks(in: "foo bar xyz fud baz abc def", width: 10, tabSize: 4)
		#expect(breaks.count >= 2) // At least 2 breaks needed for 27 chars at width 10
	}

	// MARK: - Space Handling

	@Test("break after last fitting space")
	func breakAfterLastSpace() {
		// "foo bar fud" — 11 chars, width 10
		let breaks = softBreaks(in: "foo bar fud", width: 10, tabSize: 4)
		#expect(breaks.count == 1)
		#expect(breaks[0] == 8) // After "foo bar "
	}

	@Test("break with multiple spaces")
	func multipleSpaces() {
		// "foo bar  fud" — 12 chars, width 10
		let breaks = softBreaks(in: "foo bar  fud", width: 10, tabSize: 4)
		#expect(breaks.count == 1)
		#expect(breaks[0] == 9) // After "foo bar  "
	}

	@Test("newline resets column")
	func newlineResetsColumn() {
		// Newline within line — column resets
		let breaks = softBreaks(in: "foo bar\nxyz", width: 10, tabSize: 4)
		#expect(breaks.isEmpty) // Each segment fits in 10
	}

	// MARK: - Tab Handling

	@Test("tab expands to tab stop")
	func tabExpansion() {
		// With tabSize 4: "\txy" = 4 + 2 = 6 columns
		let breaks = softBreaks(in: "\txy", width: 10, tabSize: 4)
		#expect(breaks.isEmpty) // 6 < 10
	}

	@Test("tab causes wrap when exceeding width")
	func tabCausesWrap() {
		// "\t\t\tx" = 12 columns with tabSize 4 — exceeds width 10
		let breaks = softBreaks(in: "\t\t\tx", width: 10, tabSize: 4)
		#expect(!breaks.isEmpty)
	}

	// MARK: - Prefix Size

	@Test("prefix size narrows continuation lines")
	func prefixSizeNarrows() {
		// "foo bar xyz abc def" — width 10, prefix 4
		// First line wraps at 10, continuation lines at width 10 - 4 = 6
		let breaks = softBreaks(in: "foo bar xyz abc def", width: 10, tabSize: 4, prefixSize: 4)
		#expect(breaks.count >= 2) // More breaks due to narrower continuation
	}

	// MARK: - Zero Width

	@Test("zero width returns no breaks")
	func zeroWidth() {
		let breaks = softBreaks(in: "hello world", width: 0, tabSize: 4)
		#expect(breaks.isEmpty) // Guard returns early
	}

	// MARK: - Unicode

	@Test("ASCII-only wrapping is byte-precise")
	func asciiPrecise() {
		let breaks = softBreaks(in: "abcde fghij", width: 10, tabSize: 4)
		#expect(breaks.count == 1)
		#expect(breaks[0] == 6) // After "abcde "
	}
}
