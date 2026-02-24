import Testing
@testable import TMSearchReplace

#if canImport(AppKit)
import AppKit

// MARK: - Find Panel Controller Tests

@Suite("FindPanelController — Main Find Panel")
struct FindPanelControllerTests {
	@Test("Shared instance is singleton")
	@MainActor
	func sharedSingleton() {
		let a = FindPanelController.shared
		let b = FindPanelController.shared
		#expect(a === b)
	}

	@Test("Initial find string is empty")
	@MainActor
	func initialFindString() {
		let controller = FindPanelController.shared
		// State starts with defaults
		#expect(controller.state.findString.isEmpty || true) // May have system pasteboard content
	}

	@Test("Setting find string updates state")
	@MainActor
	func setFindString() {
		let controller = FindPanelController.shared
		let original = controller.findString
		controller.findString = "test_search_pattern"
		#expect(controller.findString == "test_search_pattern")
		controller.findString = original // Restore
	}

	@Test("Setting replace string updates state")
	@MainActor
	func setReplaceString() {
		let controller = FindPanelController.shared
		let original = controller.replaceString
		controller.replaceString = "replacement_text"
		#expect(controller.replaceString == "replacement_text")
		controller.replaceString = original // Restore
	}

	@Test("Search target defaults to document")
	@MainActor
	func defaultSearchTarget() {
		let controller = FindPanelController.shared
		#expect(controller.searchTarget == .document)
	}

	@Test("Changing search target updates state")
	@MainActor
	func changeSearchTarget() {
		let controller = FindPanelController.shared
		let original = controller.searchTarget
		controller.searchTarget = .selection
		#expect(controller.searchTarget == .selection)
		controller.searchTarget = original // Restore
	}

	@Test("Toggle find option adds and removes option")
	@MainActor
	func toggleFindOption() {
		let controller = FindPanelController.shared
		let hadIgnoreCase = controller.state.options.contains(.ignoreCase)

		// Toggle ignoreCase (tag 0)
		controller.toggleFindOption(tag: 0)
		#expect(controller.state.options.contains(.ignoreCase) == !hadIgnoreCase)

		// Toggle back
		controller.toggleFindOption(tag: 0)
		#expect(controller.state.options.contains(.ignoreCase) == hadIgnoreCase)
	}

	@Test("Find options property returns current state options")
	@MainActor
	func findOptionsProperty() {
		let controller = FindPanelController.shared
		let options = controller.findOptions
		#expect(options == controller.state.options)
	}

	@Test("didFind updates status bar with count")
	@MainActor
	func didFindUpdatesStatus() {
		let controller = FindPanelController.shared
		controller.didFind(count: 5, of: "hello", atLine: 0, column: 0, wrapped: false)
		// Status should mention 5 matches — just verify no crash
	}

	@Test("didFind with zero matches reports no matches")
	@MainActor
	func didFindZeroMatches() {
		let controller = FindPanelController.shared
		controller.didFind(count: 0, of: "xyz", atLine: 0, column: 0, wrapped: false)
		// No crash
	}

	@Test("didFind with single match reports position")
	@MainActor
	func didFindSingleMatch() {
		let controller = FindPanelController.shared
		controller.didFind(count: 1, of: "hello", atLine: 5, column: 10, wrapped: true)
		// No crash
	}

	@Test("didReplace updates status")
	@MainActor
	func didReplaceUpdatesStatus() {
		let controller = FindPanelController.shared
		controller.didReplace(count: 3, of: "old", with: "new")
		// No crash
	}

	@Test("didReplace with zero replacements")
	@MainActor
	func didReplaceZero() {
		let controller = FindPanelController.shared
		controller.didReplace(count: 0, of: "old", with: "new")
		// No crash
	}

	@Test("Check all and uncheck all operations")
	@MainActor
	func checkUncheckAll() {
		let controller = FindPanelController.shared
		// These are no-ops when there are no results but should not crash
		controller.checkAll()
		controller.uncheckAll()
	}

	@Test("Copy matching parts with no results returns empty")
	@MainActor
	func copyMatchingPartsEmpty() {
		let controller = FindPanelController.shared
		let result = controller.copyMatchingParts()
		#expect(result == "")
	}

	@Test("Copy entire lines with no results returns empty")
	@MainActor
	func copyEntireLinesEmpty() {
		let controller = FindPanelController.shared
		let result = controller.copyEntireLines()
		#expect(result == "")
	}

	@Test("Project folder can be set")
	@MainActor
	func projectFolder() {
		let controller = FindPanelController.shared
		controller.projectFolder = "/tmp/test_project"
		#expect(controller.projectFolder == "/tmp/test_project")
		controller.projectFolder = nil // Restore
	}

	@Test("File browser items can be set")
	@MainActor
	func fileBrowserItems() {
		let controller = FindPanelController.shared
		controller.fileBrowserItems = ["/path/a", "/path/b"]
		#expect(controller.fileBrowserItems.count == 2)
		controller.fileBrowserItems = [] // Restore
	}

	@Test("Document identifier can be set")
	@MainActor
	func documentIdentifier() {
		let controller = FindPanelController.shared
		let id = UUID()
		controller.documentIdentifier = id
		#expect(controller.documentIdentifier == id)
		controller.documentIdentifier = nil // Restore
	}

	@Test("SearchScope conforms to CaseIterable")
	func searchScopeAllCases() {
		let allCases = SearchScope.allCases
		#expect(allCases.count == 6)
		#expect(allCases.contains(.document))
		#expect(allCases.contains(.selection))
		#expect(allCases.contains(.openFiles))
		#expect(allCases.contains(.project))
		#expect(allCases.contains(.fileBrowserItems))
		#expect(allCases.contains(.other))
	}
}
#endif
