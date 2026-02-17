import Testing
@testable import TMCore

@Suite("TextRange")
struct TextRangeTests {
	@Test("caret creates zero-width range")
	func caretRange() {
		let pos = TextPosition(line: 5, column: 3, offset: 42)
		let range = TextRange(caret: pos)
		#expect(range.isEmpty)
		#expect(range.length == 0)
		#expect(range.anchor == pos)
		#expect(range.head == pos)
		#expect(range.start == pos)
		#expect(range.end == pos)
		#expect(!range.isColumnar)
	}

	@Test("forward selection has start before end")
	func forwardSelection() {
		let anchor = TextPosition(line: 1, column: 0, offset: 10)
		let head = TextPosition(line: 1, column: 5, offset: 15)
		let range = TextRange(anchor: anchor, head: head)
		#expect(range.start == anchor)
		#expect(range.end == head)
		#expect(range.length == 5)
		#expect(!range.isEmpty)
	}

	@Test("backward selection has start before end")
	func backwardSelection() {
		let anchor = TextPosition(line: 1, column: 5, offset: 15)
		let head = TextPosition(line: 1, column: 0, offset: 10)
		let range = TextRange(anchor: anchor, head: head)
		#expect(range.start == head)
		#expect(range.end == anchor)
		#expect(range.length == 5)
	}

	@Test("columnar flag is preserved")
	func columnarFlag() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0),
			head: TextPosition(line: 3, column: 5, offset: 30),
			isColumnar: true,
		)
		#expect(range.isColumnar)
	}

	@Test("range is hashable")
	func hashable() {
		let a = TextRange(caret: TextPosition(line: 0, column: 0, offset: 0))
		let b = TextRange(caret: TextPosition(line: 0, column: 0, offset: 0))
		let set: Set<TextRange> = [a, b]
		#expect(set.count == 1)
	}

	@Test("freehanded flag defaults false")
	func freehandedDefault() {
		let range = TextRange(caret: TextPosition(line: 0, column: 0, offset: 0))
		#expect(!range.isFreehanded)
	}

	@Test("freehanded flag is preserved")
	func freehandedFlag() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0),
			head: TextPosition(line: 0, column: 5, offset: 5),
			isFreehanded: true,
		)
		#expect(range.isFreehanded)
	}

	@Test("unanchored flag defaults false")
	func unanchoredDefault() {
		let range = TextRange(caret: TextPosition(line: 0, column: 0, offset: 0))
		#expect(!range.isUnanchored)
	}

	@Test("unanchored flag is preserved")
	func unanchoredFlag() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0),
			head: TextPosition(line: 0, column: 5, offset: 5),
			isUnanchored: true,
		)
		#expect(range.isUnanchored)
	}

	@Test("color tag defaults zero")
	func colorDefault() {
		let range = TextRange(caret: TextPosition(line: 0, column: 0, offset: 0))
		#expect(range.color == 0)
	}

	@Test("color tag is preserved")
	func colorPreserved() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0),
			head: TextPosition(line: 0, column: 5, offset: 5),
			color: 42,
		)
		#expect(range.color == 42)
	}

	@Test("all flags combined")
	func allFlags() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0),
			head: TextPosition(line: 1, column: 3, offset: 10),
			isColumnar: true,
			isFreehanded: true,
			isUnanchored: true,
			color: 0xFF,
		)
		#expect(range.isColumnar)
		#expect(range.isFreehanded)
		#expect(range.isUnanchored)
		#expect(range.color == 0xFF)
	}
}

@Suite("TextPosition carry")
struct TextPositionCarryTests {
	@Test("carry defaults to zero")
	func carryDefault() {
		let pos = TextPosition(line: 0, column: 5, offset: 5)
		#expect(pos.carry == 0)
	}

	@Test("carry is stored")
	func carryStored() {
		let pos = TextPosition(line: 2, column: 10, offset: 25, carry: 3)
		#expect(pos.carry == 3)
	}

	@Test("positions with same offset but different carry compare correctly")
	func carryComparison() {
		let a = TextPosition(line: 0, column: 5, offset: 5, carry: 0)
		let b = TextPosition(line: 0, column: 5, offset: 5, carry: 3)
		#expect(a < b)
		#expect(a != b)
	}

	@Test("positions with different offset ignore carry for ordering")
	func offsetTakesPrecedence() {
		let a = TextPosition(line: 0, column: 5, offset: 5, carry: 100)
		let b = TextPosition(line: 1, column: 0, offset: 10, carry: 0)
		#expect(a < b)
	}

	@Test("carry participates in equality")
	func carryEquality() {
		let a = TextPosition(line: 0, column: 5, offset: 5, carry: 0)
		let b = TextPosition(line: 0, column: 5, offset: 5, carry: 0)
		let c = TextPosition(line: 0, column: 5, offset: 5, carry: 1)
		#expect(a == b)
		#expect(a != c)
	}

	@Test("carry participates in hashing")
	func carryHashing() {
		let a = TextPosition(line: 0, column: 5, offset: 5, carry: 0)
		let c = TextPosition(line: 0, column: 5, offset: 5, carry: 1)
		let set: Set<TextPosition> = [a, c]
		#expect(set.count == 2)
	}

	@Test("zero static has carry zero")
	func zeroCarry() {
		#expect(TextPosition.zero.carry == 0)
	}
}
