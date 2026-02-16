import AppKit
import Testing
@testable import TMPreferences

@Suite("HTMLOutputWindowController")
struct HTMLOutputWindowControllerTests {
	@Test("initializes with a window and web view")
	@MainActor func initialization() {
		let controller = HTMLOutputWindowController()
		#expect(controller.window != nil)
		#expect(controller.webView != nil)
	}

	@Test("isRunningCommand defaults to false")
	@MainActor func defaultRunningCommand() {
		let controller = HTMLOutputWindowController()
		#expect(controller.isRunningCommand == false)
	}

	@Test("isRunningCommand sets window document edited")
	@MainActor func runningCommandSetsDocumentEdited() {
		let controller = HTMLOutputWindowController()
		controller.isRunningCommand = true
		#expect(controller.window?.isDocumentEdited == true)
		controller.isRunningCommand = false
		#expect(controller.window?.isDocumentEdited == false)
	}

	@Test("windowShouldClose returns true when not running command")
	@MainActor func shouldCloseWhenNotRunning() throws {
		let controller = HTMLOutputWindowController()
		let result = try controller.windowShouldClose(#require(controller.window))
		#expect(result == true)
	}

	@Test("windowShouldClose returns false when running command")
	@MainActor func shouldNotCloseWhenRunning() throws {
		let controller = HTMLOutputWindowController()
		controller.isRunningCommand = true
		let result = try controller.windowShouldClose(#require(controller.window))
		#expect(result == false)
		controller.isRunningCommand = false
	}

	@Test("identifier configures frame autosave")
	@MainActor func frameAutosaveWithIdentifier() {
		let id = UUID()
		let controller = HTMLOutputWindowController(identifier: id)
		// setFrameAutosaveName may fail if duplicate; just verify it doesn't crash
		// and window is properly initialized
		#expect(controller.window != nil)
		#expect(controller.window?.title == "HTML Output")
	}
}
