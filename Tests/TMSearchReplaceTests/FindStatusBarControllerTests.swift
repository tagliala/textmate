import Testing
@testable import TMSearchReplace

#if canImport(AppKit)
import AppKit

// MARK: - Find Status Bar Controller Tests

@Suite("FindStatusBarController — Status Bar UI")
struct FindStatusBarControllerTests {
	@Test("Initial state has empty status text")
	@MainActor
	func initialState() {
		let vc = FindStatusBarController()

		#expect(vc.statusText == "")
		#expect(vc.alternateStatusText == "")
		#expect(vc.isProgressVisible == false)
	}

	@Test("Setting status text updates property")
	@MainActor
	func setStatusText() {
		let vc = FindStatusBarController()
		vc.statusText = "42 matches in 7 files"

		#expect(vc.statusText == "42 matches in 7 files")
	}

	@Test("Setting alternate status text updates property")
	@MainActor
	func setAlternateStatusText() {
		let vc = FindStatusBarController()
		vc.alternateStatusText = "120 files scanned"

		#expect(vc.alternateStatusText == "120 files scanned")
	}

	@Test("Progress visibility can be toggled")
	@MainActor
	func toggleProgressVisibility() {
		let vc = FindStatusBarController()

		vc.isProgressVisible = true
		#expect(vc.isProgressVisible == true)

		vc.isProgressVisible = false
		#expect(vc.isProgressVisible == false)
	}

	@Test("Stop callback fires on stop")
	@MainActor
	func stopCallback() {
		let vc = FindStatusBarController()
		var stopCalled = false
		vc.onStop = { stopCalled = true }

		// Simulate stop by calling the callback directly
		vc.onStop?()
		#expect(stopCalled)
	}

	@Test("Format status string with plain text")
	@MainActor
	func formatPlainStatus() {
		let attributed = FindStatusBarController.formatStatusString("Hello World")
		#expect(attributed.string == "Hello World")
	}

	@Test("Format status string replaces newlines with ¬")
	@MainActor
	func formatNewlines() {
		let attributed = FindStatusBarController.formatStatusString("Line1\nLine2")
		#expect(attributed.string == "Line1¬Line2")
	}

	@Test("Format status string replaces tabs with ‣")
	@MainActor
	func formatTabs() {
		let attributed = FindStatusBarController.formatStatusString("Col1\tCol2")
		#expect(attributed.string == "Col1‣Col2")
	}

	@Test("Format status string handles mixed newlines and tabs")
	@MainActor
	func formatMixed() {
		let attributed = FindStatusBarController.formatStatusString("A\tB\nC\tD")
		#expect(attributed.string == "A‣B¬C‣D")
	}

	@Test("Format empty string produces empty attributed string")
	@MainActor
	func formatEmpty() {
		let attributed = FindStatusBarController.formatStatusString("")
		#expect(attributed.string == "")
	}
}
#endif
