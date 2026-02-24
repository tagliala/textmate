import Testing
@testable import TMCore

// MARK: - East Asian Width

@Suite("East Asian Width Detection")
struct EastAsianWidthTests {
	@Test("CJK ideographs are wide")
	func cjkIdeographs() throws {
		#expect(try isEastAsianWide(#require(Unicode.Scalar(0x4E00)))) // 一
		#expect(try isEastAsianWide(#require(Unicode.Scalar(0x9FFF)))) // last CJK
	}

	@Test("Fullwidth ASCII variants are wide")
	func fullwidthASCII() throws {
		#expect(try isEastAsianWide(#require(Unicode.Scalar(0xFF01)))) // ！(fullwidth !)
		#expect(try isEastAsianWide(#require(Unicode.Scalar(0xFF21)))) // Ａ(fullwidth A)
	}

	@Test("ASCII characters are not wide")
	func asciiNotWide() {
		#expect(!isEastAsianWide(Unicode.Scalar("A")))
		#expect(!isEastAsianWide(Unicode.Scalar("0")))
		#expect(!isEastAsianWide(Unicode.Scalar(" ")))
	}

	@Test("Hangul syllables are wide")
	func hangul() throws {
		#expect(try isEastAsianWide(#require(Unicode.Scalar(0xAC00)))) // 가
		#expect(try isEastAsianWide(#require(Unicode.Scalar(0xD7A3)))) // last Hangul
	}

	@Test("Hiragana/Katakana are wide")
	func kana() throws {
		#expect(try isEastAsianWide(#require(Unicode.Scalar(0x3042)))) // あ
		#expect(try isEastAsianWide(#require(Unicode.Scalar(0x30A2)))) // ア
	}
}

// MARK: - Column Counting

@Suite("Column Counting")
struct ColumnCountingTests {
	@Test("ASCII text counts one column per character")
	func asciiColumns() {
		let buf = TextBuffer("hello")
		let pos = TextPosition(line: 0, column: 3, offset: 3)
		#expect(countColumns(in: buf, caret: pos, tabSize: 4) == 3)
	}

	@Test("tab advances to next tab stop")
	func tabStop() {
		let buf = TextBuffer("\thello")
		// After tab at tabSize=4, visual column is 4
		let pos = TextPosition(line: 0, column: 1, offset: 1)
		#expect(countColumns(in: buf, caret: pos, tabSize: 4) == 4)
	}

	@Test("tab at column 2 advances to column 4")
	func tabMidway() {
		let buf = TextBuffer("ab\tx")
		// Caret just after the tab: byte offset 3
		let pos = TextPosition(line: 0, column: 3, offset: 3)
		#expect(countColumns(in: buf, caret: pos, tabSize: 4) == 4)
	}

	@Test("multiple tabs")
	func multipleTabs() {
		let buf = TextBuffer("\t\t")
		let pos = TextPosition(line: 0, column: 2, offset: 2)
		#expect(countColumns(in: buf, caret: pos, tabSize: 4) == 8)
	}

	@Test("carry is added to column count")
	func carryAdded() {
		let buf = TextBuffer("hi")
		let pos = TextPosition(line: 0, column: 2, offset: 2, carry: 3)
		#expect(countColumns(in: buf, caret: pos, tabSize: 4) == 5) // 2 + 3
	}

	@Test("empty line returns carry only")
	func emptyLine() {
		let buf = TextBuffer("\n")
		let pos = TextPosition(line: 0, column: 0, offset: 0, carry: 5)
		#expect(countColumns(in: buf, caret: pos, tabSize: 4) == 5)
	}

	@Test("column count on second line")
	func secondLine() {
		let buf = TextBuffer("first\nsecond")
		let pos = buf.convert(offset: 9) // "sec" → column 3
		#expect(countColumns(in: buf, caret: pos, tabSize: 4) == 3)
	}

	@Test("CJK character counts as double width")
	func cjkWidth() {
		let buf = TextBuffer("a\u{4E00}b") // a + 一 + b
		// After 'a' and '一': 1 + 2 = 3
		let cjkBytes = "\u{4E00}".utf8.count // 3 bytes
		let pos = TextPosition(line: 0, column: 1 + cjkBytes, offset: 1 + cjkBytes)
		#expect(countColumns(in: buf, caret: pos, tabSize: 4) == 3)
	}
}

// MARK: - At Column

@Suite("At Column")
struct AtColumnTests {
	@Test("exact column in ASCII text")
	func exactASCII() {
		let buf = TextBuffer("hello")
		let pos = atColumn(in: buf, line: 0, column: 3, tabSize: 4)
		#expect(pos.offset == 3)
		#expect(pos.carry == 0)
	}

	@Test("column 0 returns start of line")
	func columnZero() {
		let buf = TextBuffer("hello")
		let pos = atColumn(in: buf, line: 0, column: 0, tabSize: 4)
		#expect(pos.offset == 0)
		#expect(pos.carry == 0)
	}

	@Test("column past end of line has carry")
	func pastEnd() {
		let buf = TextBuffer("hi")
		let pos = atColumn(in: buf, line: 0, column: 5, tabSize: 4)
		#expect(pos.offset == 2)
		#expect(pos.carry == 3) // 5 - 2 = 3
	}

	@Test("column within a tab has carry")
	func withinTab() {
		let buf = TextBuffer("\thello")
		// Tab occupies columns 0–3, so column 2 falls inside the tab
		let pos = atColumn(in: buf, line: 0, column: 2, tabSize: 4)
		#expect(pos.offset == 0)
		#expect(pos.carry == 2)
	}

	@Test("column at tab boundary has no carry")
	func tabBoundary() {
		let buf = TextBuffer("\thello")
		let pos = atColumn(in: buf, line: 0, column: 4, tabSize: 4)
		#expect(pos.offset == 1) // Just past the tab
		#expect(pos.carry == 0)
	}

	@Test("second line access")
	func secondLine() {
		let buf = TextBuffer("first\nsecond")
		let pos = atColumn(in: buf, line: 1, column: 3, tabSize: 4)
		#expect(pos.offset == 9) // "fir" in line 2 = 6+3=9
		#expect(pos.carry == 0)
	}

	@Test("roundtrip: countColumns → atColumn")
	func roundtrip() {
		let buf = TextBuffer("a\tb\tc")
		let caret = TextPosition(line: 0, column: 4, offset: 4) // "a\tb\t"
		let col = countColumns(in: buf, caret: caret, tabSize: 4)
		let pos = atColumn(in: buf, line: 0, column: col, tabSize: 4)
		#expect(pos.offset == caret.offset)
		#expect(pos.carry == 0)
	}
}

// MARK: - Columnar Dissection

@Suite("Columnar Dissection")
struct ColumnarDissectionTests {
	@Test("non-columnar range passes through")
	func nonColumnar() {
		let buf = TextBuffer("hello\nworld")
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 1, offset: 1),
			head: TextPosition(line: 1, column: 3, offset: 9),
		)
		let result = dissectColumnar(in: buf, selection: [range], tabSize: 4)
		#expect(result.count == 1)
		#expect(result[0].start.offset == 1)
		#expect(result[0].end.offset == 9)
	}

	@Test("columnar range is split into per-line ranges")
	func columnarSplit() {
		let buf = TextBuffer("hello\nworld\nfoo!!")
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 1, offset: 1),
			head: TextPosition(line: 2, column: 3, offset: 15),
			isColumnar: true,
		)
		let result = dissectColumnar(in: buf, selection: [range], tabSize: 4)
		#expect(result.count == 3) // One range per line
		// Each range should span columns 1–3
		for r in result {
			#expect(!r.isColumnar)
		}
	}

	@Test("empty columnar range passes through")
	func emptyColumnar() {
		let pos = TextPosition(line: 0, column: 2, offset: 2)
		let range = TextRange(anchor: pos, head: pos, isColumnar: true)
		let buf = TextBuffer("hello")
		let result = dissectColumnar(in: buf, selection: [range], tabSize: 4)
		#expect(result.count == 1)
	}
}

// MARK: - Sanitize

@Suite("Selection Sanitize")
struct SanitizeTests {
	@Test("empty selection returns empty")
	func emptySelection() {
		let buf = TextBuffer("hello")
		let result = sanitize(in: buf, selection: [])
		#expect(result.isEmpty)
	}

	@Test("single range is preserved")
	func singleRange() {
		let buf = TextBuffer("hello world")
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 2, offset: 2),
			head: TextPosition(line: 0, column: 5, offset: 5),
		)
		let result = sanitize(in: buf, selection: [range])
		#expect(result.count == 1)
		#expect(result[0].start.offset == 2)
		#expect(result[0].end.offset == 5)
	}

	@Test("overlapping ranges are merged")
	func overlapping() {
		let buf = TextBuffer("hello world")
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 5, offset: 5),
			),
			TextRange(
				anchor: TextPosition(line: 0, column: 3, offset: 3),
				head: TextPosition(line: 0, column: 8, offset: 8),
			),
		]
		let result = sanitize(in: buf, selection: ranges)
		// The second range should be clipped to start at 5
		#expect(result.count == 2)
		#expect(result[0].start.offset == 0)
		#expect(result[0].end.offset == 5)
		#expect(result[1].start.offset == 5)
		#expect(result[1].end.offset == 8)
	}

	@Test("out-of-bounds indices are clamped")
	func clamped() {
		let buf = TextBuffer("hi")
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0),
			head: TextPosition(line: 0, column: 100, offset: 100),
		)
		let result = sanitize(in: buf, selection: [range])
		#expect(result.count == 1)
		#expect(result[0].end.offset == 2) // buffer size is 2
	}

	@Test("columnar ranges are not merged")
	func columnarNotMerged() {
		let buf = TextBuffer("hello world")
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 5, offset: 5),
				isColumnar: true,
			),
			TextRange(
				anchor: TextPosition(line: 0, column: 3, offset: 3),
				head: TextPosition(line: 0, column: 8, offset: 8),
				isColumnar: true,
			),
		]
		let result = sanitize(in: buf, selection: ranges)
		#expect(result.count == 2)
	}

	@Test("insertion order is preserved")
	func insertionOrder() {
		let buf = TextBuffer("abcdefghij")
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 6, offset: 6),
				head: TextPosition(line: 0, column: 8, offset: 8),
			),
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 3, offset: 3),
			),
		]
		let result = sanitize(in: buf, selection: ranges)
		#expect(result.count == 2)
		// Original insertion order preserved:
		// first range should still be the 6-8 one
		#expect(result[0].start.offset == 6)
		#expect(result[1].start.offset == 0)
	}
}

// MARK: - Selection Queries

@Suite("Selection Queries")
struct SelectionQueryTests {
	@Test("notEmpty returns false for all carets")
	func allCarets() {
		let buf = TextBuffer("hello")
		let ranges = [
			TextRange(caret: TextPosition(line: 0, column: 0, offset: 0)),
			TextRange(caret: TextPosition(line: 0, column: 3, offset: 3)),
		]
		#expect(!notEmpty(in: buf, selection: ranges, tabSize: 4))
	}

	@Test("notEmpty returns true for non-empty range")
	func nonEmpty() {
		let buf = TextBuffer("hello")
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 3, offset: 3),
			),
		]
		#expect(notEmpty(in: buf, selection: ranges, tabSize: 4))
	}

	@Test("multiline returns false for single-line selections")
	func singleLine() {
		let buf = TextBuffer("hello\nworld")
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 3, offset: 3),
			),
		]
		#expect(!multiline(in: buf, selection: ranges))
	}

	@Test("multiline returns true for cross-line selection")
	func crossLine() {
		let buf = TextBuffer("hello\nworld")
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 1, column: 3, offset: 9),
			),
		]
		#expect(multiline(in: buf, selection: ranges))
	}
}

// MARK: - Toggle Columnar

@Suite("Toggle Columnar")
struct ToggleColumnarTests {
	@Test("toggles columnar on non-empty range")
	func toggle() {
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 1, column: 3, offset: 9),
			),
		]
		let toggled = toggleColumnar(ranges)
		#expect(toggled[0].isColumnar == true)

		let toggledBack = toggleColumnar(toggled)
		#expect(toggledBack[0].isColumnar == false)
	}

	@Test("empty range is not made columnar")
	func emptyNotColumnar() {
		let ranges = [TextRange(caret: TextPosition(line: 0, column: 0, offset: 0))]
		let toggled = toggleColumnar(ranges)
		#expect(toggled[0].isColumnar == false)
	}

	@Test("only last range is toggled")
	func onlyLast() {
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 3, offset: 3),
			),
			TextRange(
				anchor: TextPosition(line: 1, column: 0, offset: 6),
				head: TextPosition(line: 1, column: 3, offset: 9),
			),
		]
		let toggled = toggleColumnar(ranges)
		#expect(toggled[0].isColumnar == false)
		#expect(toggled[1].isColumnar == true)
	}
}

// MARK: - Deselect Last

@Suite("Deselect Last")
struct DeselectLastTests {
	@Test("multiple selections: removes last")
	func removesLast() {
		let ranges = [
			TextRange(caret: TextPosition(line: 0, column: 0, offset: 0)),
			TextRange(caret: TextPosition(line: 1, column: 0, offset: 6)),
			TextRange(caret: TextPosition(line: 2, column: 0, offset: 12)),
		]
		let result = deselectLast(ranges)
		#expect(result.count == 1) // all carets → return first
	}

	@Test("multiple non-empty selections: drops last")
	func dropsLast() {
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 3, offset: 3),
			),
			TextRange(
				anchor: TextPosition(line: 1, column: 0, offset: 6),
				head: TextPosition(line: 1, column: 3, offset: 9),
			),
		]
		let result = deselectLast(ranges)
		#expect(result.count == 1)
		#expect(result[0].start.offset == 0)
	}

	@Test("single non-empty selection: collapses to caret")
	func collapsesToCaret() {
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 5, offset: 5),
			),
		]
		let result = deselectLast(ranges)
		#expect(result.count == 1)
		#expect(result[0].isEmpty)
		#expect(result[0].anchor.offset == 0)
	}

	@Test("single caret: clears freehanded")
	func clearsFreehanded() {
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 0, offset: 0),
				isFreehanded: true,
			),
		]
		let result = deselectLast(ranges)
		#expect(result[0].isFreehanded == false)
	}
}

// MARK: - Selection Serialization

@Suite("Selection Serialization")
struct SelectionSerializationTests {
	@Test("caret serializes as line:column")
	func caretSerialization() {
		let buf = TextBuffer("hello\nworld")
		let sel = [TextRange(caret: TextPosition(line: 0, column: 3, offset: 3))]
		let str = selectionToString(in: buf, selection: sel)
		#expect(str == "0:3")
	}

	@Test("range serializes as from-to")
	func rangeSerialization() {
		let buf = TextBuffer("hello\nworld")
		let sel = [TextRange(
			anchor: TextPosition(line: 0, column: 1, offset: 1),
			head: TextPosition(line: 1, column: 2, offset: 8),
		)]
		let str = selectionToString(in: buf, selection: sel)
		#expect(str == "0:1-1:2")
	}

	@Test("columnar range has x suffix")
	func columnarSerialization() {
		let buf = TextBuffer("hello\nworld")
		let sel = [TextRange(
			anchor: TextPosition(line: 0, column: 1, offset: 1),
			head: TextPosition(line: 1, column: 3, offset: 9),
			isColumnar: true,
		)]
		let str = selectionToString(in: buf, selection: sel)
		#expect(str.hasSuffix("x"))
	}

	@Test("multiple selections separated by &")
	func multipleSerialization() {
		let buf = TextBuffer("hello\nworld")
		let sel = [
			TextRange(caret: TextPosition(line: 0, column: 0, offset: 0)),
			TextRange(caret: TextPosition(line: 1, column: 0, offset: 6)),
		]
		let str = selectionToString(in: buf, selection: sel)
		#expect(str.contains("&"))
	}

	@Test("roundtrip: serialize then parse")
	func roundtrip() {
		let buf = TextBuffer("hello\nworld\nfoo")
		let original = [TextRange(
			anchor: TextPosition(line: 0, column: 2, offset: 2),
			head: TextPosition(line: 1, column: 3, offset: 9),
		)]
		let str = selectionToString(in: buf, selection: original)
		let parsed = selectionFromString(in: buf, string: str)
		#expect(parsed.count == 1)
		#expect(parsed[0].anchor.offset == original[0].anchor.offset)
		#expect(parsed[0].head.offset == original[0].head.offset)
	}

	@Test("parse caret string")
	func parseCaret() {
		let buf = TextBuffer("hello\nworld")
		let result = selectionFromString(in: buf, string: "1:2")
		#expect(result.count == 1)
		#expect(result[0].isEmpty)
		#expect(result[0].anchor.line == 1)
		#expect(result[0].anchor.column == 2)
	}

	@Test("parse columnar range")
	func parseColumnar() {
		let buf = TextBuffer("hello\nworld")
		let result = selectionFromString(in: buf, string: "0:1-1:3x")
		#expect(result.count == 1)
		#expect(result[0].isColumnar)
	}

	@Test("parse freehanded with carry")
	func parseCarry() {
		let buf = TextBuffer("hello\nworld")
		let result = selectionFromString(in: buf, string: "0:5+2")
		#expect(result.count == 1)
		#expect(result[0].anchor.carry == 2)
		#expect(result[0].isFreehanded)
	}
}

// MARK: - TextRange Extensions

@Suite("TextRange Extensions")
struct TextRangeExtensionTests {
	@Test("sorted returns min as anchor, max as head")
	func sorted() {
		let range = TextRange(
			anchor: TextPosition(line: 1, column: 3, offset: 9),
			head: TextPosition(line: 0, column: 1, offset: 1),
		)
		let s = range.sorted()
		#expect(s.anchor.offset == 1)
		#expect(s.head.offset == 9)
	}

	@Test("sorted preserves flags")
	func sortedFlags() {
		let range = TextRange(
			anchor: TextPosition(line: 1, column: 0, offset: 6),
			head: TextPosition(line: 0, column: 0, offset: 0),
			isColumnar: true,
			isFreehanded: true,
			color: 42,
		)
		let s = range.sorted()
		#expect(s.isColumnar)
		#expect(s.isFreehanded)
		#expect(s.color == 42)
	}

	@Test("normalized strips carry for non-columnar non-freehanded")
	func normalizedStripCarry() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 5, offset: 5, carry: 3),
			head: TextPosition(line: 0, column: 2, offset: 2, carry: 1),
		)
		let n = range.normalized()
		#expect(n.anchor.carry == 0)
		#expect(n.head.carry == 0)
		// Also sorted
		#expect(n.anchor.offset == 2)
		#expect(n.head.offset == 5)
	}

	@Test("normalized preserves carry for columnar range")
	func normalizedColumnar() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0, carry: 2),
			head: TextPosition(line: 0, column: 5, offset: 5, carry: 1),
			isColumnar: true,
		)
		let n = range.normalized()
		#expect(n.anchor.carry == 2)
		#expect(n.head.carry == 1)
	}

	@Test("normalized preserves carry for freehanded range")
	func normalizedFreehanded() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0, carry: 4),
			head: TextPosition(line: 0, column: 5, offset: 5),
			isFreehanded: true,
		)
		let n = range.normalized()
		#expect(n.anchor.carry == 4)
	}
}
