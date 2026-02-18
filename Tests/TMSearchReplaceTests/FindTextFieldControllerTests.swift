import Testing
@testable import TMSearchReplace

#if canImport(AppKit)
import AppKit

// MARK: - Find Text Field Controller Tests

@Suite("FindTextFieldController — Text Field with History")
struct FindTextFieldControllerTests {
	@Test("Initial state has empty string")
	@MainActor
	func initialState() {
		let vc = FindTextFieldController()
		#expect(vc.stringValue == "")
		#expect(vc.hasFocus == false)
		#expect(vc.history.isEmpty)
	}

	@Test("Setting string value updates property")
	@MainActor
	func setStringValue() {
		let vc = FindTextFieldController()
		vc.stringValue = "hello"
		#expect(vc.stringValue == "hello")
	}

	@Test("Value changed callback fires")
	@MainActor
	func valueChangedCallback() {
		let vc = FindTextFieldController()
		var received: String?
		vc.onValueChanged = { received = $0 }

		vc.stringValue = "test"
		#expect(received == "test")
	}

	@Test("Setting same value does not fire callback twice")
	@MainActor
	func noRedundantCallback() {
		let vc = FindTextFieldController()
		var callCount = 0
		vc.onValueChanged = { _ in callCount += 1 }

		vc.stringValue = "hello"
		vc.stringValue = "hello" // Same value
		#expect(callCount == 1)
	}

	@Test("History can be set")
	@MainActor
	func setHistory() {
		let vc = FindTextFieldController()
		vc.history = ["first", "second", "third"]
		#expect(vc.history.count == 3)
		#expect(vc.history.first == "first")
	}

	@Test("Show history with empty history does not crash")
	@MainActor
	func showHistoryEmpty() {
		let vc = FindTextFieldController()
		vc.history = []
		// Should not crash
		vc.showHistory()
	}
}
#endif
