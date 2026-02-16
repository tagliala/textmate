import AppKit
import Testing
@testable import TMHTMLOutput

@Suite("HTMLOutputStatusBar")
@MainActor
struct HTMLOutputStatusBarTests {
	// MARK: - Initialization

	@Test("Creates with default state")
	func defaultState() {
		let bar = HTMLOutputStatusBar()
		#expect(bar.statusText == "")
		#expect(bar.progress == 0)
		#expect(bar.busy == false)
		#expect(bar.canGoBack == false)
		#expect(bar.canGoForward == false)
	}

	// MARK: - Status Text

	@Test("Setting status text updates display")
	func statusTextUpdates() {
		let bar = HTMLOutputStatusBar()
		bar.statusText = "Loading…"
		#expect(bar.statusText == "Loading…")
	}

	@Test("Empty status text clears display")
	func emptyStatusText() {
		let bar = HTMLOutputStatusBar()
		bar.statusText = "hello"
		bar.statusText = ""
		#expect(bar.statusText == "")
	}

	// MARK: - Progress

	@Test("Setting progress to positive value")
	func positiveProgress() {
		let bar = HTMLOutputStatusBar()
		bar.progress = 0.5
		#expect(bar.progress == 0.5)
	}

	@Test("Progress clamped to valid range")
	func progressClamping() {
		let bar = HTMLOutputStatusBar()
		bar.progress = 1.5
		#expect(bar.progress <= 1.0)
		bar.progress = -0.5
		#expect(bar.progress >= 0.0)
	}

	// MARK: - Busy State

	@Test("Busy state toggles correctly")
	func busyToggle() {
		let bar = HTMLOutputStatusBar()
		bar.busy = true
		#expect(bar.busy == true)
		bar.busy = false
		#expect(bar.busy == false)
	}

	// MARK: - Navigation State

	@Test("Navigation button state reflects properties")
	func navigationState() {
		let bar = HTMLOutputStatusBar()
		bar.canGoBack = true
		#expect(bar.canGoBack == true)
		bar.canGoForward = true
		#expect(bar.canGoForward == true)
	}

	// MARK: - Delegate

	@Test("Delegate receives back action")
	func delegateGoBack() {
		let bar = HTMLOutputStatusBar()
		let spy = StatusBarDelegateSpy()
		bar.delegate = spy
		bar.canGoBack = true
		bar.goBackButton.performClick(nil)
		#expect(spy.wentBack)
	}

	@Test("Delegate receives forward action")
	func delegateGoForward() {
		let bar = HTMLOutputStatusBar()
		let spy = StatusBarDelegateSpy()
		bar.delegate = spy
		bar.canGoForward = true
		bar.goForwardButton.performClick(nil)
		#expect(spy.wentForward)
	}
}

// MARK: - Test Helpers

@MainActor
private final class StatusBarDelegateSpy: HTMLOutputStatusBarDelegate {
	var wentBack = false
	var wentForward = false

	func statusBarGoBack(_: HTMLOutputStatusBar) {
		wentBack = true
	}

	func statusBarGoForward(_: HTMLOutputStatusBar) {
		wentForward = true
	}
}
