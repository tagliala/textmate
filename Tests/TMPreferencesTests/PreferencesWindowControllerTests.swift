import AppKit
import Testing
@testable import TMPreferences

@Suite("PreferencesWindowController")
struct PreferencesWindowControllerTests {
	@Test("shared instance has a window")
	@MainActor func sharedHasWindow() {
		let controller = PreferencesWindowController.shared
		#expect(controller.window != nil)
	}

	@Test("shared instance has default panes")
	@MainActor func defaultPanes() {
		let controller = PreferencesWindowController.shared
		#expect(controller.panes.count == 6)
	}

	@Test("default pane identifiers match expected order")
	@MainActor func defaultPaneOrder() {
		let controller = PreferencesWindowController.shared
		let ids = controller.panes.map(\.paneIdentifier)
		#expect(ids == ["Files", "Projects", "Bundles", "Variables", "SoftwareUpdate", "Terminal"])
	}

	@Test("selectPane at valid index changes selection")
	@MainActor func selectPaneAtIndex() {
		let controller = PreferencesWindowController.shared
		controller.selectPane(at: 2, animated: false)
		#expect(controller.selectedPaneIndex == 2)
	}

	@Test("selectPane at out-of-bounds index is handled")
	@MainActor func selectPaneAtInvalidIndex() {
		let controller = PreferencesWindowController.shared
		controller.selectPane(at: 0, animated: false)
		// Select an invalid index — should not crash, stays at 0
		controller.selectPane(at: 999, animated: false)
		#expect(controller.selectedPaneIndex == 0)
	}

	@Test("selectNextTab wraps around")
	@MainActor func selectNextTabWraps() {
		let controller = PreferencesWindowController.shared
		let lastIndex = controller.panes.count - 1
		controller.selectPane(at: lastIndex, animated: false)
		controller.selectNextTab(nil)
		#expect(controller.selectedPaneIndex == 0)
	}

	@Test("selectPreviousTab wraps around")
	@MainActor func selectPreviousTabWraps() {
		let controller = PreferencesWindowController.shared
		controller.selectPane(at: 0, animated: false)
		controller.selectPreviousTab(nil)
		#expect(controller.selectedPaneIndex == controller.panes.count - 1)
	}

	@Test("selectNextTab advances forward")
	@MainActor func selectNextTabForward() {
		let controller = PreferencesWindowController.shared
		controller.selectPane(at: 0, animated: false)
		controller.selectNextTab(nil)
		#expect(controller.selectedPaneIndex == 1)
	}

	@Test("selectPreviousTab goes backward")
	@MainActor func selectPreviousTabBackward() {
		let controller = PreferencesWindowController.shared
		controller.selectPane(at: 3, animated: false)
		controller.selectPreviousTab(nil)
		#expect(controller.selectedPaneIndex == 2)
	}

	@Test("showPane by identifier")
	@MainActor func showPaneByIdentifier() {
		let controller = PreferencesWindowController.shared
		controller.showPane(identifier: "Terminal")
		#expect(controller.selectedPaneIndex == 5)
	}

	@Test("showPane with unknown identifier does not crash")
	@MainActor func showPaneUnknownIdentifier() {
		let controller = PreferencesWindowController.shared
		controller.selectPane(at: 0, animated: false)
		controller.showPane(identifier: "NonExistent")
		// Should remain at current pane
		#expect(controller.selectedPaneIndex == 0)
	}
}
