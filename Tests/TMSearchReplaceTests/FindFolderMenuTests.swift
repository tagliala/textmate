import Testing
@testable import TMSearchReplace

#if canImport(AppKit)
import AppKit

// MARK: - Find Folder Menu Tests

@Suite("FindFolderMenu — Folder Browser Menu")
struct FindFolderMenuTests {
	@Test("Shared instance is singleton")
	@MainActor
	func sharedSingleton() {
		let a = FindFolderMenu.shared
		let b = FindFolderMenu.shared
		#expect(a === b)
	}

	@Test("Add submenu configures menu item")
	@MainActor
	func addSubmenu() {
		let menu = FindFolderMenu.shared
		let item = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")

		menu.addSubmenu(forDirectoryAtPath: "/tmp", to: item)

		#expect(item.representedObject as? String == "/tmp")
		#expect(item.submenu != nil)
	}

	@Test("menuHasKeyEquivalent returns false")
	@MainActor
	func menuHasKeyEquivalent() throws {
		let menu = FindFolderMenu.shared
		let nsMenu = NSMenu()
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [],
			timestamp: 0, windowNumber: 0, context: nil,
			characters: "a", charactersIgnoringModifiers: "a",
			isARepeat: false, keyCode: 0,
		))
		var target: AnyObject?
		var action: Selector?
		let result = menu.menuHasKeyEquivalent(nsMenu, for: event, target: &target, action: &action)
		#expect(result == false)
	}
}
#endif
