#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import TMApp
@testable import TMDocumentManager

@Suite("RecentDocumentsManager wiring")
@MainActor
struct RecentDocumentsWiringTests {
	@Test("Open Recent submenu exists in File menu")
	func openRecentSubmenu() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let fileMenu = try #require(menu.items[1].submenu)
		let recentItem = fileMenu.items.first {
			$0.submenu?.title == String(localized: "Open Recent", comment: "File menu submenu")
		}
		#expect(recentItem != nil)
		#expect(recentItem?.submenu != nil)
	}

	@Test("Clear Menu item targets clearRecentDocuments:")
	func clearMenuItem() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let fileMenu = try #require(menu.items[1].submenu)
		let recentItem = fileMenu.items.first {
			$0.submenu?.title == String(localized: "Open Recent", comment: "File menu submenu")
		}
		let clearItem = recentItem?.submenu?.items.first {
			$0.title == String(localized: "Clear Menu", comment: "Open Recent submenu item")
		}
		#expect(clearItem != nil)
		#expect(clearItem?.action == NSSelectorFromString("clearRecentDocuments:"))
	}

	@Test("noteDocumentOpened adds entry to recent list")
	func noteDocumentAddsEntry() {
		let mgr = RecentDocumentsManager.shared
		let testPath = "/tmp/test-recent-\(UUID().uuidString).swift"
		defer { mgr.removeEntry(forPath: testPath) }

		mgr.noteDocumentOpened(path: testPath)

		#expect(mgr.contains(path: testPath))
		#expect(mgr.entries.first?.displayName == (testPath as NSString).lastPathComponent)
	}

	@Test("clearAll removes all entries")
	func clearAllRemoves() {
		let mgr = RecentDocumentsManager.shared
		let saved = mgr.entries

		let p1 = "/tmp/test-recent-clear-\(UUID().uuidString).txt"
		let p2 = "/tmp/test-recent-clear-\(UUID().uuidString).txt"
		mgr.noteDocumentOpened(path: p1)
		mgr.noteDocumentOpened(path: p2)

		mgr.clearAll()
		#expect(mgr.entries.isEmpty)

		// Restore original entries
		for entry in saved.reversed() {
			mgr.noteDocumentOpened(path: entry.path, fileType: entry.fileType)
		}
	}
}
#endif
