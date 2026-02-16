import Testing
@testable import TMFilterList

@Suite("MatchHighlighter.splitCoverRanges")
struct SplitCoverRangesTests {
	@Test("split ranges at boundary — all in prefix")
	func allInPrefix() {
		let ranges = [CoverRange(start: 0, end: 5)]
		let split = MatchHighlighter.splitCoverRanges(ranges, at: 10)
		#expect(split.prefix.count == 1)
		#expect(split.suffix.isEmpty)
		#expect(split.prefix[0] == CoverRange(start: 0, end: 5))
	}

	@Test("split ranges at boundary — all in suffix")
	func allInSuffix() {
		let ranges = [CoverRange(start: 15, end: 20)]
		let split = MatchHighlighter.splitCoverRanges(ranges, at: 10)
		#expect(split.prefix.isEmpty)
		#expect(split.suffix.count == 1)
		#expect(split.suffix[0] == CoverRange(start: 5, end: 10)) // adjusted offset
	}

	@Test("split ranges at boundary — spans boundary")
	func spansBoundary() {
		let ranges = [CoverRange(start: 8, end: 15)]
		let split = MatchHighlighter.splitCoverRanges(ranges, at: 10)
		#expect(split.prefix.count == 1)
		#expect(split.suffix.count == 1)
		#expect(split.prefix[0] == CoverRange(start: 8, end: 10))
		#expect(split.suffix[0] == CoverRange(start: 0, end: 5))
	}

	@Test("split empty ranges")
	func emptyRanges() {
		let split = MatchHighlighter.splitCoverRanges([], at: 10)
		#expect(split.prefix.isEmpty)
		#expect(split.suffix.isEmpty)
	}

	@Test("split multiple ranges")
	func multipleRanges() {
		let ranges = [
			CoverRange(start: 0, end: 3), // prefix
			CoverRange(start: 12, end: 15), // suffix
		]
		let split = MatchHighlighter.splitCoverRanges(ranges, at: 10)
		#expect(split.prefix.count == 1)
		#expect(split.suffix.count == 1)
	}

	@Test("boundary at range end")
	func boundaryAtRangeEnd() {
		let ranges = [CoverRange(start: 0, end: 10)]
		let split = MatchHighlighter.splitCoverRanges(ranges, at: 10)
		#expect(split.prefix.count == 1)
		#expect(split.suffix.isEmpty)
		#expect(split.prefix[0] == CoverRange(start: 0, end: 10))
	}

	@Test("boundary at range start")
	func boundaryAtRangeStart() {
		let ranges = [CoverRange(start: 10, end: 15)]
		let split = MatchHighlighter.splitCoverRanges(ranges, at: 10)
		#expect(split.prefix.isEmpty)
		#expect(split.suffix.count == 1)
		#expect(split.suffix[0] == CoverRange(start: 0, end: 5))
	}
}

@Suite("MatchHighlighter.Style")
struct MatchHighlighterStyleTests {
	@Test("default style properties")
	func defaultStyle() {
		let style = MatchHighlighter.Style.default
		#expect(style.matchBackgroundColor == "tmMatchedTextBackgroundColor")
		#expect(style.matchUnderlineColor == "tmMatchedTextUnderlineColor")
		#expect(style.font == "system")
		#expect(style.fontSize == 13)
	}

	@Test("custom style")
	func customStyle() {
		let style = MatchHighlighter.Style(
			matchBackgroundColor: "custom",
			matchUnderlineColor: "custom2",
			font: "Menlo",
			fontSize: 14,
		)
		#expect(style.matchBackgroundColor == "custom")
		#expect(style.font == "Menlo")
		#expect(style.fontSize == 14)
	}
}

#if canImport(AppKit)
import AppKit

@Suite("MatchHighlighter.attributedString")
struct MatchHighlighterAppKitTests {
	@Test("attributed string with no ranges")
	func noRanges() {
		let attr = MatchHighlighter.attributedString(for: "hello", coverRanges: [])
		#expect(attr.string == "hello")
	}

	@Test("attributed string with cover ranges")
	func withRanges() {
		let ranges = [CoverRange(start: 0, end: 3)]
		let attr = MatchHighlighter.attributedString(for: "hello", coverRanges: ranges)
		#expect(attr.string == "hello")
		// Check that the first 3 characters have underline
		var effectiveRange = NSRange()
		let attrs = attr.attributes(at: 0, effectiveRange: &effectiveRange)
		#expect(attrs[.underlineStyle] != nil)
	}

	@Test("attributed string with out-of-bounds range is safe")
	func outOfBoundsRange() {
		let ranges = [CoverRange(start: 100, end: 200)]
		let attr = MatchHighlighter.attributedString(for: "hello", coverRanges: ranges)
		#expect(attr.string == "hello")
		// Should not crash, range is skipped
	}
}
#endif
