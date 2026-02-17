import Testing

#if canImport(AppKit)
import AppKit
import TMEditorUI

@Suite("LiveSearchBarView — Core")
@MainActor
struct LiveSearchBarCoreTests {
	@Test("bar has correct default height constant")
	func defaultBarHeight() {
		#expect(LiveSearchBarView.barHeight == 28)
	}

	@Test("initial search string is empty")
	func initialSearchString() {
		let bar = LiveSearchBarView()
		#expect(bar.searchString.isEmpty)
	}

	@Test("setting search string updates the view")
	func setSearchString() {
		let bar = LiveSearchBarView()
		bar.searchString = "hello"
		#expect(bar.searchString == "hello")
	}

	@Test("ignoreCase defaults to true from user defaults")
	func ignoreCaseDefault() {
		UserDefaults.standard.set(true, forKey: "incrementalSearchIgnoreCase")
		let bar = LiveSearchBarView()
		#expect(bar.ignoreCase == true)
	}

	@Test("wrapAround defaults to false from user defaults")
	func wrapAroundDefault() {
		UserDefaults.standard.set(false, forKey: "incrementalSearchWrapAround")
		let bar = LiveSearchBarView()
		#expect(bar.wrapAround == false)
	}

	@Test("hasNoResults starts false")
	func hasNoResultsInitially() {
		let bar = LiveSearchBarView()
		#expect(bar.hasNoResults == false)
	}

	@Test("deactivate clears search string")
	func deactivateClearsSearch() {
		let bar = LiveSearchBarView()
		bar.searchString = "test"
		bar.deactivate()
		#expect(bar.searchString.isEmpty)
	}
}

@Suite("EditorHUD — Core")
@MainActor
struct EditorHUDCoreTests {
	@Test("HUD initializer creates a panel")
	func hudCreatesPanel() {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let win = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
			styleMask: [.titled],
			backing: .buffered,
			defer: false,
		)
		win.contentView = view
		let hud = EditorHUD(view: view)
		#expect(hud.window != nil)
	}

	@Test("stringValue can be set")
	func setStringValue() {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let win = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
			styleMask: [.titled],
			backing: .buffered,
			defer: false,
		)
		win.contentView = view
		let hud = EditorHUD(view: view)
		hud.stringValue = "Tab: 4"
		#expect(hud.stringValue == "Tab: 4")
	}

	@Test("show class method returns a HUD")
	func showClassMethod() {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let win = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
			styleMask: [.titled],
			backing: .buffered,
			defer: false,
		)
		win.contentView = view
		let hud = EditorHUD.show(in: view, text: "Hello")
		#expect(hud.stringValue == "Hello")
	}

	@Test("show reuses HUD for same view")
	func showReusesSameView() {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let win = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
			styleMask: [.titled],
			backing: .buffered,
			defer: false,
		)
		win.contentView = view
		let hud1 = EditorHUD.show(in: view, text: "First")
		let hud2 = EditorHUD.show(in: view, text: "Second")
		#expect(hud1 === hud2)
		#expect(hud2.stringValue == "Second")
	}

	@Test("HUD panel is borderless and transparent")
	func hudPanelStyle() {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
		let win = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
			styleMask: [.titled],
			backing: .buffered,
			defer: false,
		)
		win.contentView = view
		let hud = EditorHUD(view: view)
		#expect(hud.window?.isOpaque == false)
		#expect(hud.window?.ignoresMouseEvents == true)
	}
}
#endif
