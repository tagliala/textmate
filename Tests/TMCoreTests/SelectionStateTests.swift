import Testing
@testable import TMCore

@Suite("SelectionState")
struct SelectionStateTests {
	@Test("single caret creates one selection")
	func singleCaret() {
		let state = SelectionState(caret: TextPosition.zero)
		#expect(state.count == 1)
		#expect(state.isSingleCaret)
		#expect(state.primary?.isEmpty == true)
	}

	@Test("multiple non-overlapping selections are preserved")
	func multipleSelections() {
		let ranges = [
			TextRange(caret: TextPosition(line: 0, column: 0, offset: 0)),
			TextRange(caret: TextPosition(line: 2, column: 0, offset: 20)),
			TextRange(caret: TextPosition(line: 4, column: 0, offset: 40)),
		]
		let state = SelectionState(ranges)
		#expect(state.count == 3)
		#expect(!state.isSingleCaret)
	}

	@Test("selections are sorted by offset")
	func sortedSelections() {
		let ranges = [
			TextRange(caret: TextPosition(line: 4, column: 0, offset: 40)),
			TextRange(caret: TextPosition(line: 0, column: 0, offset: 0)),
			TextRange(caret: TextPosition(line: 2, column: 0, offset: 20)),
		]
		let state = SelectionState(ranges)
		#expect(state.selections[0].start.offset == 0)
		#expect(state.selections[1].start.offset == 20)
		#expect(state.selections[2].start.offset == 40)
	}

	@Test("overlapping selections are merged")
	func mergeOverlapping() {
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 10, offset: 10),
			),
			TextRange(
				anchor: TextPosition(line: 0, column: 5, offset: 5),
				head: TextPosition(line: 0, column: 15, offset: 15),
			),
		]
		let state = SelectionState(ranges)
		#expect(state.count == 1)
		#expect(state.selections[0].start.offset == 0)
		#expect(state.selections[0].end.offset == 15)
	}

	@Test("adjacent selections are merged")
	func mergeAdjacent() {
		let ranges = [
			TextRange(
				anchor: TextPosition(line: 0, column: 0, offset: 0),
				head: TextPosition(line: 0, column: 5, offset: 5),
			),
			TextRange(
				anchor: TextPosition(line: 0, column: 5, offset: 5),
				head: TextPosition(line: 0, column: 10, offset: 10),
			),
		]
		let state = SelectionState(ranges)
		#expect(state.count == 1)
		#expect(state.selections[0].length == 10)
	}

	@Test("empty selections array is handled")
	func emptySelections() {
		let state = SelectionState([])
		#expect(state.count == 0)
		#expect(state.primary == nil)
		#expect(!state.isSingleCaret)
	}

	@Test("single range does not need merging")
	func singleRange() {
		let range = TextRange(
			anchor: TextPosition(line: 0, column: 0, offset: 0),
			head: TextPosition(line: 1, column: 0, offset: 10),
		)
		let state = SelectionState([range])
		#expect(state.count == 1)
		#expect(state.selections[0] == range)
	}

	@Test("primary returns first selection")
	func primarySelection() {
		let ranges = [
			TextRange(caret: TextPosition(line: 0, column: 5, offset: 5)),
			TextRange(caret: TextPosition(line: 2, column: 0, offset: 20)),
		]
		let state = SelectionState(ranges)
		#expect(state.primary?.start.offset == 5)
	}
}
