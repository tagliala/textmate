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
}
