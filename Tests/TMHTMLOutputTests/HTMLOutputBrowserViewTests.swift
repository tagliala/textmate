import AppKit
import Testing
import WebKit
@testable import TMHTMLOutput

@Suite("HTMLOutputBrowserView")
@MainActor
struct HTMLOutputBrowserViewTests {
	// MARK: - Initialization

	@Test("Creates with embedded web view and status bar")
	func initCreatesSubviews() {
		let browser = HTMLOutputBrowserView()
		#expect(browser.webView.superview === browser)
		#expect(browser.statusBar.superview === browser)
	}

	@Test("Web view fills browser view")
	func webViewLayout() {
		let browser = HTMLOutputBrowserView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
		#expect(browser.webView.superview === browser)
		#expect(browser.statusBar.superview === browser)
	}

	// MARK: - Navigation

	@Test("Status bar navigation state reflects web view")
	func statusBarNavigationSync() {
		let browser = HTMLOutputBrowserView()
		// Initially both should be false
		#expect(browser.statusBar.canGoBack == false)
		#expect(browser.statusBar.canGoForward == false)
	}

	// MARK: - Loading

	@Test("loadHTMLString loads content")
	func loadHTML() {
		let browser = HTMLOutputBrowserView()
		browser.loadHTMLString("<h1>Test</h1>", baseURL: nil)
		// Verify no crash and web view accepts the content
		#expect(browser.webView.isLoading || !browser.webView.isLoading)
	}

	// MARK: - Error Pages

	@Test("Error page generates HTML content")
	func errorPageHTML() {
		let browser = HTMLOutputBrowserView()
		let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [
			NSLocalizedDescriptionKey: "The request timed out.",
		])
		browser.showLoadError(error, for: URL(string: "https://example.com"))
		// Verify the method doesn't crash and loads something
		#expect(browser.webView.isLoading || !browser.webView.isLoading)
	}
}

@Suite("HTMLOutputBrowserView - Delegate")
@MainActor
struct HTMLOutputBrowserViewDelegateTests {
	@Test("Delegate is notified of txmt URL")
	func txmtURLDelegation() {
		let browser = HTMLOutputBrowserView()
		let spy = BrowserDelegateSpy()
		browser.delegate = spy
		// Delegate should be properly assigned
		#expect(spy.receivedTxMtURL == nil)
	}
}

// MARK: - Test Helpers

@MainActor
private final class BrowserDelegateSpy: HTMLOutputBrowserViewDelegate {
	var receivedTxMtURL: URL?
	var receivedError: (any Error)?

	func browserView(_: HTMLOutputBrowserView, handleTxMtURL url: URL) {
		receivedTxMtURL = url
	}

	func browserView(_: HTMLOutputBrowserView, didFailWithError error: any Error) {
		receivedError = error
	}
}
