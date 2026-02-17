import Testing
import TMCore
import TMDocumentManager
import TMDocumentWindow

#if canImport(AppKit)
import AppKit

@Suite("DocumentWindowController — Live Search")
@MainActor
struct DocumentWindowLiveSearchTests {
	/// Creates a window controller with a document containing the given text.
	private func makeController(text: String) -> DocumentWindowController {
		let doc = TMDocument()
		doc.setContent(text, preserveRevision: true)
		return DocumentWindowController(document: doc)
	}

	@Test("live search bar is initially hidden")
	func initiallyHidden() {
		let ctrl = makeController(text: "hello world")
		#expect(ctrl.isLiveSearchVisible == false)
	}

	@Test("showLiveSearch makes the bar visible")
	func showMakesVisible() {
		let ctrl = makeController(text: "hello world")
		ctrl.showLiveSearch()
		#expect(ctrl.isLiveSearchVisible == true)
	}

	@Test("hideLiveSearch hides the bar")
	func hideHidesBar() {
		let ctrl = makeController(text: "hello world")
		ctrl.showLiveSearch()
		ctrl.hideLiveSearch()
		#expect(ctrl.isLiveSearchVisible == false)
	}

	@Test("showLiveSearch activates incremental search state")
	func activatesIncrementalSearch() {
		let ctrl = makeController(text: "hello world")
		ctrl.showLiveSearch()
		#expect(ctrl.incrementalSearch.isActive == true)
	}

	@Test("hideLiveSearch deactivates incremental search state")
	func deactivatesIncrementalSearch() {
		let ctrl = makeController(text: "hello world")
		ctrl.showLiveSearch()
		ctrl.hideLiveSearch()
		#expect(ctrl.incrementalSearch.isActive == false)
	}

	@Test("incremental search takes buffer text on activation")
	func capturesBufferText() {
		let ctrl = makeController(text: "hello world")
		ctrl.showLiveSearch()
		#expect(ctrl.incrementalSearch.bufferText == "hello world")
	}

	@Test("showHUD creates a HUD (does not crash)")
	func showHUDNoCrash() {
		let ctrl = makeController(text: "hello")
		// Ensure window is loaded so the editor view exists.
		_ = ctrl.window
		ctrl.showHUD(text: "Tab: 3")
		// Just verifying it doesn't crash — no assertion on UI.
	}
}
#endif
