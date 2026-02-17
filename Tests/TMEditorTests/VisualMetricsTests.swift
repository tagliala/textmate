import Testing
import TMCore
import TMEditor

@Suite("Visual Distance")
struct VisualDistanceTests {
	@Test("ASCII text with no tabs")
	func asciiNoTabs() {
		let editor = Editor(text: "hello world")
		let dist = editor.visualDistance(from: 0, to: 5)
		#expect(dist == 5) // "hello" = 5 columns
	}

	@Test("tab expands to tab size")
	func tabExpansion() {
		let editor = Editor(text: "\thello")
		editor.tabSize = 4
		// Tab at position 0 → 4 columns
		let dist = editor.visualDistance(from: 0, to: 1)
		#expect(dist == 4)
	}

	@Test("tab at mid-column")
	func tabMidColumn() {
		let editor = Editor(text: "ab\thello")
		editor.tabSize = 4
		// "ab" = 2 cols, then tab rounds up to 4 → total 4
		let dist = editor.visualDistance(from: 0, to: 3) // "ab\t" is 3 bytes
		#expect(dist == 4)
	}

	@Test("multiple tabs")
	func multipleTabs() {
		let editor = Editor(text: "\t\thello")
		editor.tabSize = 4
		// First tab: 4, second tab: 4 → total 8
		let dist = editor.visualDistance(from: 0, to: 2)
		#expect(dist == 8)
	}

	@Test("empty range gives zero")
	func emptyRange() {
		let editor = Editor(text: "hello")
		let dist = editor.visualDistance(from: 3, to: 3)
		#expect(dist == 0)
	}

	@Test("East Asian wide characters count as 2")
	func eastAsianWide() {
		let editor = Editor(text: "中文") // U+4E2D, U+6587 — both CJK
		let dist = editor.visualDistance(from: 0, to: editor.buffer.size, eastAsianWidth: true)
		#expect(dist == 4) // 2 characters × 2 columns each
	}

	@Test("East Asian disabled counts as 1")
	func eastAsianDisabled() {
		let editor = Editor(text: "中文")
		let dist = editor.visualDistance(from: 0, to: editor.buffer.size, eastAsianWidth: false)
		#expect(dist == 2) // 2 characters × 1 column each
	}

	@Test("visual column at primary caret")
	func visualColumnProperty() {
		let editor = Editor(text: "\thello")
		editor.tabSize = 4
		// Move caret to after tab (offset 1 byte)
		let pos = editor.buffer.convert(offset: 1)
		editor.selections = SelectionState(caret: pos)
		#expect(editor.visualColumn == 4)
	}
}

@Suite("Visual Advance")
struct VisualAdvanceTests {
	@Test("advance past ASCII")
	func advancePastASCII() {
		let editor = Editor(text: "hello world")
		let (offset, carry) = editor.visualAdvance(from: 0, distance: 5)
		#expect(offset == 5)
		#expect(carry == 0)
	}

	@Test("advance past tab")
	func advancePastTab() {
		let editor = Editor(text: "\thello")
		editor.tabSize = 4
		// Advance 4 visual cols → lands after tab
		let (offset, carry) = editor.visualAdvance(from: 0, distance: 4)
		#expect(offset == 1)
		#expect(carry == 0)
	}

	@Test("advance mid tab leaves carry")
	func advanceMidTab() {
		let editor = Editor(text: "\thello")
		editor.tabSize = 4
		// Advance 2 visual cols → lands inside the tab with carry 2
		let (offset, carry) = editor.visualAdvance(from: 0, distance: 2)
		#expect(offset == 0)
		#expect(carry == 2)
	}

	@Test("advance beyond line end gives carry")
	func advanceBeyondLineEnd() {
		let editor = Editor(text: "hi\nworld")
		// Advance 10 from "hi" → stops at newline with carry
		let (offset, carry) = editor.visualAdvance(from: 0, distance: 10)
		#expect(offset == 2) // stops at '\n'
		#expect(carry == 8) // 10 - 2 remaining
	}

	@Test("advance zero distance returns same offset")
	func advanceZero() {
		let editor = Editor(text: "hello")
		let (offset, carry) = editor.visualAdvance(from: 3, distance: 0)
		#expect(offset == 3)
		#expect(carry == 0)
	}

	@Test("advance past East Asian wide character")
	func advancePastEastAsian() {
		let editor = Editor(text: "中文abc")
		// "中" is 3 UTF-8 bytes, wide = 2 cols
		let (offset, carry) = editor.visualAdvance(from: 0, distance: 2, eastAsianWidth: true)
		#expect(offset == 3) // past first CJK char (3 bytes)
		#expect(carry == 0)
	}
}

@Suite("East Asian Width Detection")
struct EastAsianWidthTests {
	@Test("CJK ideograph is wide")
	func cjkIdeograph() {
		let scalar: Unicode.Scalar = "中" // U+4E2D
		#expect(scalar.isEastAsianWide)
	}

	@Test("ASCII is not wide")
	func asciiNotWide() {
		let scalar: Unicode.Scalar = "A"
		#expect(!scalar.isEastAsianWide)
	}

	@Test("Hangul syllable is wide")
	func hangulWide() {
		let scalar: Unicode.Scalar = "한" // U+D55C — Hangul
		#expect(scalar.isEastAsianWide)
	}

	@Test("Hiragana is wide")
	func hiraganaWide() {
		let scalar: Unicode.Scalar = "あ" // U+3042
		#expect(scalar.isEastAsianWide)
	}

	@Test("Latin extended is not wide")
	func latinNotWide() {
		let scalar: Unicode.Scalar = "ñ" // U+00F1
		#expect(!scalar.isEastAsianWide)
	}

	@Test("Fullwidth form is wide")
	func fullwidthWide() {
		let scalar: Unicode.Scalar = "\u{FF21}" // Fullwidth Latin A
		#expect(scalar.isEastAsianWide)
	}
}
