#if canImport(AppKit)
import AppKit
import Testing
@testable import TMApp

@Suite("MainMenuBuilder")
@MainActor
struct MainMenuBuilderTests {
	// MARK: - Top-Level Menu Structure

	@Test("builds main menu with 10 top-level items")
	func topLevelMenuCount() {
		let menu = MainMenuBuilder.buildMainMenu()
		#expect(menu.items.count == 10)
	}

	@Test("top-level menu names match TextMate order")
	func topLevelMenuOrder() {
		let menu = MainMenuBuilder.buildMainMenu()
		let titles = menu.items.map(\.title)
		#expect(titles[0] == "TextMate")
		#expect(titles[1] == String(localized: "File", comment: "Menu title"))
		#expect(titles[2] == String(localized: "Edit", comment: "Menu title"))
		#expect(titles[3] == String(localized: "View", comment: "Menu title"))
		#expect(titles[4] == String(localized: "Navigate", comment: "Menu title"))
		#expect(titles[5] == String(localized: "Text", comment: "Menu title"))
		#expect(titles[6] == String(localized: "File Browser", comment: "Menu title"))
		#expect(titles[7] == String(localized: "Bundles", comment: "Menu title"))
		#expect(titles[8] == String(localized: "Window", comment: "Menu title"))
		#expect(titles[9] == String(localized: "Help", comment: "Menu title"))
	}

	@Test("each top-level item has a submenu")
	func topLevelSubmenus() {
		let menu = MainMenuBuilder.buildMainMenu()
		for item in menu.items {
			#expect(item.submenu != nil, "'\(item.title)' should have a submenu")
		}
	}

	// MARK: - File Menu

	@Test("File menu contains New, Open, Save, Print")
	func fileMenuEssentials() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let fileMenu = try #require(menu.items[1].submenu)
		let titles = fileMenu.items.map(\.title)
		#expect(titles.contains(String(localized: "New", comment: "File menu item")))
		#expect(titles.contains(String(localized: "Open…", comment: "File menu item")))
		#expect(titles.contains(String(localized: "Save", comment: "File menu item")))
		#expect(titles.contains(String(localized: "Print…", comment: "File menu item")))
	}

	@Test("New has ⌘N key equivalent")
	func newKeyEquivalent() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let fileMenu = try #require(menu.items[1].submenu)
		let newItem = fileMenu.items.first {
			$0.title == String(localized: "New", comment: "File menu item")
		}
		#expect(newItem?.keyEquivalent == "n")
		#expect(newItem?.keyEquivalentModifierMask == .command)
	}

	@Test("Save has ⌘S key equivalent")
	func saveKeyEquivalent() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let fileMenu = try #require(menu.items[1].submenu)
		let saveItem = fileMenu.items.first {
			$0.title == String(localized: "Save", comment: "File menu item")
		}
		#expect(saveItem?.keyEquivalent == "s")
		#expect(saveItem?.keyEquivalentModifierMask == .command)
	}

	// MARK: - Edit Menu

	@Test("Edit menu has Find and Spelling submenus")
	func editMenuSubmenus() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let editMenu = try #require(menu.items[2].submenu)
		let subMenuTitles = editMenu.items.compactMap(\.submenu?.title)
		#expect(subMenuTitles.contains(String(localized: "Find", comment: "Edit menu submenu")))
		#expect(subMenuTitles.contains(String(localized: "Spelling", comment: "Edit menu submenu")))
	}

	@Test("Spelling submenu has checkSpelling: action")
	func spellingSubMenuAction() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let editMenu = try #require(menu.items[2].submenu)
		let spellingItem = editMenu.items.first { $0.submenu?.title == String(
			localized: "Spelling",
			comment: "Edit menu submenu",
		) }
		let spellingMenu = spellingItem?.submenu
		let checkItem = spellingMenu?.items.first {
			$0.title == String(localized: "Check Document Now", comment: "Spelling submenu item")
		}
		#expect(checkItem?.action == #selector(NSText.checkSpelling(_:)))
	}

	// MARK: - View Menu

	@Test("View menu has tab size submenu with sizes 2-8")
	func tabSizeSubmenu() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let viewMenu = try #require(menu.items[3].submenu)
		let tabSizeItem = viewMenu.items.first { $0.submenu?.title == String(
			localized: "Tab Size",
			comment: "View menu submenu",
		) }
		let tabSizeMenu = tabSizeItem?.submenu
		#expect(tabSizeMenu != nil)
		let tags = try #require(tabSizeMenu?.items.map(\.tag))
		#expect(tags == Array(2 ... 8))
	}

	@Test("View menu has fold submenu with levels 0-9")
	func foldSubmenu() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let viewMenu = try #require(menu.items[3].submenu)
		let foldItem = viewMenu.items.first {
			$0.submenu?.title == String(localized: "Toggle Foldings at Level", comment: "View menu submenu")
		}
		let foldMenu = foldItem?.submenu
		#expect(foldMenu != nil)
		let tags = try #require(foldMenu?.items.map(\.tag))
		#expect(tags == Array(0 ... 9))
	}

	@Test("View menu has Theme submenu placeholder")
	func themeSubmenu() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let viewMenu = try #require(menu.items[3].submenu)
		let themeItem = viewMenu.items.first {
			$0.submenu?.title == String(localized: "Theme", comment: "View menu submenu")
		}
		#expect(themeItem != nil)
		// Submenu is initially empty (populated dynamically by AppDelegate).
		#expect(themeItem?.submenu?.items.isEmpty == true)
	}

	// MARK: - Window Menu

	@Test("Window menu has ⌘1-⌘8 tab shortcuts and ⌘9 for last tab")
	func windowTabShortcuts() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let windowMenu = try #require(menu.items[8].submenu)
		// ⌘1 through ⌘8
		for i in 1 ... 8 {
			let item = windowMenu.items.first {
				$0.keyEquivalent == "\(i)" && $0.tag == i - 1
			}
			#expect(item != nil, "Tab shortcut ⌘\(i) should exist")
			#expect(item?.action == NSSelectorFromString("takeSelectedTabIndexFrom:"))
		}
		// ⌘9 = last tab
		let lastItem = windowMenu.items.first {
			$0.keyEquivalent == "9" && $0.tag == -1
		}
		#expect(lastItem != nil)
	}

	// MARK: - Navigate Menu

	@Test("Navigate menu has Jump to Line action")
	func navigateJumpToLine() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let navMenu = try #require(menu.items[4].submenu)
		let jumpItem = navMenu.items.first {
			$0.action == NSSelectorFromString("orderFrontGoToLinePanel:")
		}
		#expect(jumpItem != nil)
		#expect(jumpItem?.keyEquivalent == "l")
	}

	// MARK: - Bundles Menu

	@Test("Bundles menu has Select Bundle Item and Edit Bundles actions")
	func bundlesMenuItems() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let bundlesMenu = try #require(menu.items[7].submenu)
		let selectItem = bundlesMenu.items.first {
			$0.action == NSSelectorFromString("showBundleItemChooser:")
		}
		let editItem = bundlesMenu.items.first {
			$0.action == NSSelectorFromString("showBundleEditor:")
		}
		#expect(selectItem != nil)
		#expect(editItem != nil)
	}
}
#endif
