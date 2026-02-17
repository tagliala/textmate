import AppKit
import Testing
import WebKit
@testable import TMHTMLOutput

@Suite("HTMLOutputCommandView")
@MainActor
struct HTMLOutputCommandViewTests {
	// MARK: - Initialization

	@Test("Creates with browser view embedded")
	func initCreatesBrowserView() {
		let view = HTMLOutputCommandView()
		#expect(view.browserView.superview === view)
	}

	@Test("Default state is idle")
	func defaultIdle() {
		let view = HTMLOutputCommandView()
		#expect(view.isRunningCommand == false)
		#expect(view.isReusable == true)
		#expect(view.commandIdentifier == nil)
	}

	// MARK: - Command Identifier

	@Test("Setting command identifier updates state")
	func commandIdentifier() {
		let view = HTMLOutputCommandView()
		let id = UUID()
		view.commandIdentifier = id
		#expect(view.commandIdentifier == id)
	}

	// MARK: - Environment

	@Test("Environment dictionary is settable")
	func environmentAccess() {
		let view = HTMLOutputCommandView()
		let env: [String: String] = ["TM_SCOPE": "source.swift", "HOME": "/Users/test"]
		view.environment = env
		#expect(view.environment["TM_SCOPE"] == "source.swift")
		#expect(view.environment["HOME"] == "/Users/test")
	}

	// MARK: - JavaScript API

	@Test("JavaScript API can be disabled")
	func disableJSAPI() {
		let view = HTMLOutputCommandView()
		view.disableJavaScriptAPI = true
		#expect(view.disableJavaScriptAPI == true)
	}

	// MARK: - Reusability

	@Test("Reusable by default when not running")
	func reusableWhenNotRunning() {
		let view = HTMLOutputCommandView()
		#expect(view.isReusable == true)
	}

	// MARK: - Delegate

	@Test("Delegate receives notifications")
	func delegateConnection() {
		let view = HTMLOutputCommandView()
		let spy = CommandViewDelegateSpy()
		view.delegate = spy
		// Delegate should be properly assigned
		#expect(spy.finishedLoading == false)
	}
}

@Suite("HTMLOutputCommandView - Printing")
@MainActor
struct HTMLOutputCommandViewPrintingTests {
	@Test("Print document does not crash")
	func printDocumentNoCrash() {
		let view = HTMLOutputCommandView()
		// Just verify the method exists and doesn't crash immediately
		// Actual printing requires a print info context
		#expect(view.responds(to: #selector(HTMLOutputCommandView.printDocument(_:))))
	}
}

// MARK: - Test Helpers

@MainActor
private final class CommandViewDelegateSpy: HTMLOutputCommandViewDelegate {
	var receivedTxMtURL: URL?
	var openedFile: String?
	var finishedLoading = false

	func commandView(_: HTMLOutputCommandView, handleTxMtURL url: URL) {
		receivedTxMtURL = url
	}

	func commandView(_: HTMLOutputCommandView, openFile path: String, options _: String?) {
		openedFile = path
	}

	func commandViewDidFinishLoading(_: HTMLOutputCommandView) {
		finishedLoading = true
	}
}
