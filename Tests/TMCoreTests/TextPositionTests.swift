import Testing
@testable import TMCore

@Suite("TextPosition")
struct TextPositionTests {
	@Test("zero position has all fields at zero")
	func zeroPosition() {
		let pos = TextPosition.zero
		#expect(pos.line == 0)
		#expect(pos.column == 0)
		#expect(pos.offset == 0)
	}

	@Test("init sets all fields correctly")
	func initFields() {
		let pos = TextPosition(line: 5, column: 10, offset: 42)
		#expect(pos.line == 5)
		#expect(pos.column == 10)
		#expect(pos.offset == 42)
	}

	@Test("positions compare by offset")
	func comparison() {
		let a = TextPosition(line: 0, column: 0, offset: 10)
		let b = TextPosition(line: 1, column: 0, offset: 20)
		#expect(a < b)
		#expect(!(b < a))
		#expect(!(a < a))
	}

	@Test("equal positions are equal")
	func equality() {
		let a = TextPosition(line: 3, column: 7, offset: 50)
		let b = TextPosition(line: 3, column: 7, offset: 50)
		#expect(a == b)
	}

	@Test("different positions are not equal")
	func inequality() {
		let a = TextPosition(line: 3, column: 7, offset: 50)
		let b = TextPosition(line: 3, column: 8, offset: 51)
		#expect(a != b)
	}

	@Test("position is hashable")
	func hashable() {
		let a = TextPosition(line: 1, column: 2, offset: 10)
		let b = TextPosition(line: 1, column: 2, offset: 10)
		let set: Set<TextPosition> = [a, b]
		#expect(set.count == 1)
	}
}
