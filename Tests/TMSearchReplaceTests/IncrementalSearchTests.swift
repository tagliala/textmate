import Foundation
import Testing
@testable import TMSearchReplace

@Suite("IncrementalSearchState")
@MainActor
struct IncrementalSearchStateTests {
	@Test("Default state is inactive")
	func defaultState() {
		let state = IncrementalSearchState()
		#expect(!state.isActive)
		#expect(state.searchString.isEmpty)
		#expect(state.currentMatch == nil)
		#expect(state.highlightedRanges.isEmpty)
		#expect(state.anchorOffset == 0)
	}

	@Test("Activate sets anchor and active")
	func activate() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 5, bufferText: "Hello world")

		#expect(state.isActive)
		#expect(state.anchorOffset == 5)
		#expect(state.searchString.isEmpty)
	}

	@Test("Deactivate clears state")
	func deactivate() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 5, bufferText: "Hello world")
		state.searchString = "world" // triggers performSearch via didSet
		state.deactivate()

		#expect(!state.isActive)
		#expect(state.searchString.isEmpty)
		#expect(state.currentMatch == nil)
		#expect(state.highlightedRanges.isEmpty)
	}

	@Test("Setting searchString triggers search automatically")
	func automaticSearch() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 0, bufferText: "hello world hello there")
		state.searchString = "hello"

		#expect(state.currentMatch != nil)
		#expect(!state.highlightedRanges.isEmpty)
	}

	@Test("Search with no results")
	func searchNoResults() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 0, bufferText: "hello world")
		state.searchString = "xyz"

		#expect(state.currentMatch == nil)
		#expect(state.highlightedRanges.isEmpty)
		#expect(state.hasNoResults)
	}

	@Test("Find next cycles through matches")
	func findNext() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 0, bufferText: "aaa bbb aaa bbb aaa")
		state.searchString = "aaa"

		let first = state.currentMatch
		#expect(first != nil)

		state.findNext()
		let second = state.currentMatch
		#expect(second != nil)
		#expect(second != first)
	}

	@Test("Find previous goes backward")
	func findPrevious() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 10, bufferText: "aaa bbb aaa bbb aaa")
		state.searchString = "aaa"

		let initial = state.currentMatch
		state.findNext()
		state.findPrevious()
		let backtrack = state.currentMatch
		#expect(backtrack == initial)
	}

	@Test("Case sensitivity toggle")
	func caseSensitivity() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 0, bufferText: "Hello HELLO hello")
		state.ignoreCase = true
		state.searchString = "hello"

		let allMatches = state.highlightedRanges.count
		#expect(allMatches == 3)

		state.ignoreCase = false
		// didSet on ignoreCase re-triggers performSearch
		let caseSensitive = state.highlightedRanges.count
		#expect(caseSensitive == 1)
	}

	@Test("Empty search string clears results")
	func emptySearch() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 0, bufferText: "hello world")
		state.searchString = "hello"
		#expect(state.currentMatch != nil)

		state.searchString = ""
		#expect(state.currentMatch == nil)
		#expect(state.highlightedRanges.isEmpty)
	}

	@Test("Callback fires after search update")
	func searchUpdateCallback() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 0, bufferText: "hello world")

		var callbackFired = false
		state.onSearchUpdate = { _, _ in callbackFired = true }
		state.searchString = "hello"
		#expect(callbackFired)
	}

	@Test("Has no results is false when inactive")
	func hasNoResultsInactive() {
		let state = IncrementalSearchState()
		#expect(!state.hasNoResults)
	}

	@Test("Wrap around wraps to beginning")
	func wrapAround() {
		let state = IncrementalSearchState()
		state.activate(anchorOffset: 5, bufferText: "abc def abc")
		state.wrapAround = true
		state.searchString = "abc"

		// Should find the one after anchor first, then wrap
		let first = state.currentMatch
		state.findNext()
		let second = state.currentMatch
		#expect(first != second)
	}
}
