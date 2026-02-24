import Foundation
import Testing
@testable import TMSearchReplace

@Suite("FindHistory")
@MainActor
struct FindHistoryTests {
	@Test("History max capacity")
	func historyMaxCapacity() {
		let pasteboard = FindPasteboard.shared
		// Clear existing history
		for i in 0 ..< 40 {
			pasteboard.findString = "cap_\(i)_\(UUID().uuidString)"
		}
		#expect(pasteboard.findHistory.count <= 30)
	}

	@Test("Replace history max capacity")
	func replaceHistoryMaxCapacity() {
		let pasteboard = FindPasteboard.shared
		for i in 0 ..< 40 {
			pasteboard.replaceString = "repl_\(i)_\(UUID().uuidString)"
		}
		#expect(pasteboard.replaceHistory.count <= 30)
	}

	@Test("Options are preserved")
	func optionsPreserved() {
		let pasteboard = FindPasteboard.shared
		let original = pasteboard.options
		pasteboard.options = [.regularExpression, .ignoreCase]
		#expect(pasteboard.options.contains(.regularExpression))
		#expect(pasteboard.options.contains(.ignoreCase))
		#expect(!pasteboard.options.contains(.fullWords))
		pasteboard.options = original
	}

	@Test("Find string updates history")
	func findStringUpdatesHistory() {
		let pasteboard = FindPasteboard.shared
		let u = UUID().uuidString
		pasteboard.findString = "alpha_\(u)"
		pasteboard.findString = "beta_\(u)"
		pasteboard.findString = "gamma_\(u)"

		#expect(pasteboard.findHistory.count >= 3)
		#expect(pasteboard.findHistory[0] == "gamma_\(u)")
	}

	@Test("Duplicate entries moved to front")
	func duplicateMovedToFront() {
		let pasteboard = FindPasteboard.shared
		let u = UUID().uuidString
		pasteboard.findString = "first_\(u)"
		pasteboard.findString = "second_\(u)"
		pasteboard.findString = "first_\(u)"

		// "first_u" should be at front, only appearing once
		#expect(pasteboard.findHistory[0] == "first_\(u)")
		let occurrences = pasteboard.findHistory.count(where: { $0 == "first_\(u)" })
		#expect(occurrences == 1)
	}

	@Test("Empty string setting does not add to history")
	func emptyNotAdded() {
		let pasteboard = FindPasteboard.shared
		let before = pasteboard.findHistory.count
		pasteboard.findString = ""
		#expect(pasteboard.findHistory.count == before)
	}
}
