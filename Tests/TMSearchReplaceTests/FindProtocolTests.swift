import Foundation
import Testing
@testable import TMSearchReplace

// MARK: - FindState Tests

@Suite("FindState")
@MainActor
struct FindStateTests {
	@Test("Default state")
	func defaultState() {
		let state = FindState()
		#expect(state.findString.isEmpty)
		#expect(state.replaceString.isEmpty)
		#expect(state.options == .default)
		#expect(state.searchScope == .document)
		#expect(state.fileGlob.isEmpty)
		#expect(!state.isPanelVisible)
		#expect(state.findHistory.isEmpty)
		#expect(state.replaceHistory.isEmpty)
	}

	@Test("Push find history")
	func pushFindHistory() {
		let state = FindState()
		state.findString = "hello"
		state.pushFindHistory()
		state.findString = "world"
		state.pushFindHistory()

		#expect(state.findHistory.count == 2)
		#expect(state.findHistory[0] == "world") // Most recent first
		#expect(state.findHistory[1] == "hello")
	}

	@Test("Find history deduplication")
	func findHistoryDedup() {
		let state = FindState()
		state.findString = "hello"
		state.pushFindHistory()
		state.findString = "world"
		state.pushFindHistory()
		state.findString = "hello"
		state.pushFindHistory()

		#expect(state.findHistory.count == 2)
		#expect(state.findHistory[0] == "hello") // Moved to front
		#expect(state.findHistory[1] == "world")
	}

	@Test("Empty find string not added to history")
	func emptyNotAddedToHistory() {
		let state = FindState()
		state.findString = ""
		state.pushFindHistory()
		#expect(state.findHistory.isEmpty)
	}

	@Test("Push replace history")
	func pushReplaceHistory() {
		let state = FindState()
		state.replaceString = "replacement1"
		state.pushReplaceHistory()
		state.replaceString = "replacement2"
		state.pushReplaceHistory()

		#expect(state.replaceHistory.count == 2)
		#expect(state.replaceHistory[0] == "replacement2")
	}

	@Test("Match references storage")
	func matchReferences() {
		let state = FindState()
		let ref = DocumentMatchReference(
			documentID: UUID(),
			firstRange: LineColumnRange(startLine: 0, startColumn: 0, endLine: 0, endColumn: 5),
			lastRange: LineColumnRange(startLine: 10, startColumn: 0, endLine: 10, endColumn: 5),
		)
		state.matchReferences = [ref]
		#expect(state.matchReferences.count == 1)
	}
}

// MARK: - DocumentMatchReference Tests

@Suite("DocumentMatchReference")
struct DocumentMatchReferenceTests {
	@Test("Creation and equality")
	func creation() {
		let id = UUID()
		let first = LineColumnRange(startLine: 0, startColumn: 0, endLine: 0, endColumn: 5)
		let last = LineColumnRange(startLine: 10, startColumn: 0, endLine: 10, endColumn: 5)

		let ref1 = DocumentMatchReference(documentID: id, firstRange: first, lastRange: last)
		let ref2 = DocumentMatchReference(documentID: id, firstRange: first, lastRange: last)

		#expect(ref1 == ref2)
	}

	@Test("Inequality for different documents")
	func inequality() {
		let first = LineColumnRange(startLine: 0, startColumn: 0, endLine: 0, endColumn: 5)
		let last = LineColumnRange(startLine: 10, startColumn: 0, endLine: 10, endColumn: 5)

		let ref1 = DocumentMatchReference(documentID: UUID(), firstRange: first, lastRange: last)
		let ref2 = DocumentMatchReference(documentID: UUID(), firstRange: first, lastRange: last)

		#expect(ref1 != ref2)
	}
}

// MARK: - FindPasteboard Tests

@Suite("FindPasteboard")
@MainActor
struct FindPasteboardTests {
	@Test("Shared instance exists")
	func sharedInstance() {
		let pasteboard = FindPasteboard.shared
		let pasteboard2 = FindPasteboard.shared
		#expect(pasteboard === pasteboard2) // Same singleton instance
	}

	@Test("Find history management")
	func findHistory() {
		let pasteboard = FindPasteboard.shared
		let originalHistory = pasteboard.findHistory

		pasteboard.findString = "test_find_\(UUID().uuidString)"
		#expect(pasteboard.findHistory.first == pasteboard.findString)

		// Restore
		pasteboard.findString = originalHistory.first ?? ""
	}

	@Test("Replace history management")
	func replaceHistory() {
		let pasteboard = FindPasteboard.shared
		let unique = "repl_\(UUID().uuidString)"
		pasteboard.replaceString = unique
		#expect(pasteboard.replaceHistory.first == unique)
	}
}
