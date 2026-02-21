import AppKit
import TMTheme

/// Builds the main menu bar, matching TextMate's menu structure exactly.
///
/// The complete menu structure is built programmatically (as in the original
/// TextMate). Key equivalents are preserved identically — see
/// `docs/architecture/03-compatibility.md#keyboard-shortcuts`.
///
/// All user-facing strings use `String(localized:)` for localization.
@MainActor
enum MainMenuBuilder {
	/// Build and return the full main menu bar.
	static func buildMainMenu() -> NSMenu {
		let mainMenu = NSMenu()

		mainMenu.addItem(buildAppMenu())
		mainMenu.addItem(buildFileMenu())
		mainMenu.addItem(buildEditMenu())
		mainMenu.addItem(buildViewMenu())
		mainMenu.addItem(buildNavigateMenu())
		mainMenu.addItem(buildTextMenu())
		mainMenu.addItem(buildFileBrowserMenu())
		mainMenu.addItem(buildBundlesMenu())
		mainMenu.addItem(buildWindowMenu())
		mainMenu.addItem(buildHelpMenu())

		return mainMenu
	}

	// MARK: - TextMate Menu

	private static func buildAppMenu() -> NSMenuItem {
		let menu = NSMenu(title: "TextMate")
		let item = NSMenuItem(title: "TextMate", action: nil, keyEquivalent: "")
		item.submenu = menu

		menu.addItem(
			title: String(localized: "About TextMate", comment: "App menu: about"),
			action: #selector(AppDelegate.showAboutPanel(_:)),
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Preferences…", comment: "App menu: preferences"),
			action: #selector(AppDelegate.showPreferences(_:)),
			key: ",",
		)
		menu.addItem(.separator())

		let servicesMenu = NSMenu(title: String(localized: "Services", comment: "App menu: services submenu"))
		let servicesItem = menu.addItem(
			title: String(localized: "Services", comment: "App menu: services"),
			action: nil,
		)
		servicesItem.submenu = servicesMenu
		NSApp.servicesMenu = servicesMenu

		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Hide TextMate", comment: "App menu: hide"),
			action: #selector(NSApplication.hide(_:)),
			key: "h",
		)
		menu.addItem(
			title: String(localized: "Hide Others", comment: "App menu: hide others"),
			action: #selector(NSApplication.hideOtherApplications(_:)),
			key: "h",
			modifiers: [.command, .option],
		)
		menu.addItem(
			title: String(localized: "Show All", comment: "App menu: show all"),
			action: #selector(NSApplication.unhideAllApplications(_:)),
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Quit TextMate", comment: "App menu: quit"),
			action: #selector(NSApplication.terminate(_:)),
			key: "q",
		)

		return item
	}

	// MARK: - File Menu

	private static func buildFileMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "File", comment: "Menu title"))
		let item = NSMenuItem(title: String(localized: "File", comment: "Menu title"), action: nil, keyEquivalent: "")
		item.submenu = menu

		menu.addItem(
			title: String(localized: "New", comment: "File menu item"),
			action: #selector(AppDelegate.newDocument(_:)),
			key: "n",
		)
		menu.addItem(
			title: String(localized: "New Tab", comment: "File menu item"),
			action: #selector(AppDelegate.newDocumentInTab(_:)),
			key: "n",
			modifiers: [.command, .option],
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Open…", comment: "File menu item"),
			action: #selector(AppDelegate.openDocument(_:)),
			key: "o",
		)
		menu.addItem(
			title: String(localized: "Open Quickly…", comment: "File menu item"),
			action: #selector(AppDelegate.goToFile(_:)),
			key: "t",
		)

		// Open Recent submenu
		let recentMenu = NSMenu(title: String(localized: "Open Recent", comment: "File menu submenu"))
		recentMenu.performSelector(inBackground: NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
		let recentItem = menu.addItem(
			title: String(localized: "Open Recent", comment: "File menu item"),
			action: nil,
		)
		recentItem.submenu = recentMenu
		recentMenu.addItem(
			title: String(localized: "Clear Menu", comment: "Open Recent submenu item"),
			action: #selector(NSDocumentController.clearRecentDocuments(_:)),
		)

		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Close", comment: "File menu item"),
			action: #selector(NSWindow.performClose(_:)),
			key: "w",
		)
		menu.addItem(
			title: String(localized: "Close Window", comment: "File menu item"),
			action: #selector(AppDelegate.performCloseWindow(_:)),
			key: "w",
			modifiers: [.command, .shift],
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Save", comment: "File menu item"),
			action: #selector(AppDelegate.saveDocument(_:)),
			key: "s",
		)
		menu.addItem(
			title: String(localized: "Save As…", comment: "File menu item"),
			action: #selector(AppDelegate.saveDocumentAs(_:)),
			key: "s",
			modifiers: [.command, .shift],
		)
		menu.addItem(
			title: String(localized: "Save All", comment: "File menu item"),
			action: #selector(AppDelegate.saveAllDocuments(_:)),
			key: "s",
			modifiers: [.command, .option],
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Print…", comment: "File menu item"),
			action: #selector(NSView.printView(_:)),
			key: "p",
		)

		return item
	}

	// MARK: - Edit Menu

	private static func buildEditMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "Edit", comment: "Menu title"))
		let item = NSMenuItem(
			title: String(localized: "Edit", comment: "Menu title"),
			action: nil,
			keyEquivalent: "",
		)
		item.submenu = menu

		menu.addItem(
			title: String(localized: "Undo", comment: "Edit menu item"),
			action: NSSelectorFromString("undo:"),
			key: "z",
		)
		menu.addItem(
			title: String(localized: "Redo", comment: "Edit menu item"),
			action: NSSelectorFromString("redo:"),
			key: "z",
			modifiers: [.command, .shift],
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Cut", comment: "Edit menu item"),
			action: #selector(NSText.cut(_:)),
			key: "x",
		)
		menu.addItem(
			title: String(localized: "Copy", comment: "Edit menu item"),
			action: #selector(NSText.copy(_:)),
			key: "c",
		)

		// Paste submenu
		let pasteMenu = NSMenu(title: String(localized: "Paste", comment: "Edit menu submenu"))
		pasteMenu.addItem(
			title: String(localized: "Paste", comment: "Edit menu item"),
			action: #selector(NSText.paste(_:)),
			key: "v",
		)
		pasteMenu.addItem(
			title: String(localized: "Paste Next", comment: "Edit menu item"),
			action: NSSelectorFromString("pasteNext:"),
			key: "v",
			modifiers: [.command, .option],
		)
		pasteMenu.addItem(
			title: String(localized: "Paste Previous", comment: "Edit menu item"),
			action: NSSelectorFromString("pastePrevious:"),
			key: "v",
			modifiers: [.command, .shift],
		)
		let pasteItem = menu.addItem(
			title: String(localized: "Paste", comment: "Edit menu item"),
			action: nil,
		)
		pasteItem.submenu = pasteMenu

		menu.addItem(
			title: String(localized: "Delete", comment: "Edit menu item"),
			action: #selector(NSText.delete(_:)),
		)
		menu.addItem(.separator())

		// Select submenu
		let selectMenu = NSMenu(title: String(localized: "Select", comment: "Edit menu submenu"))
		selectMenu.addItem(
			title: String(localized: "Word", comment: "Select submenu item"),
			action: NSSelectorFromString("selectWord:"),
		)
		selectMenu.addItem(
			title: String(localized: "Line", comment: "Select submenu item"),
			action: NSSelectorFromString("selectHardLine:"),
		)
		selectMenu.addItem(
			title: String(localized: "Paragraph", comment: "Select submenu item"),
			action: NSSelectorFromString("selectParagraph:"),
		)
		selectMenu.addItem(
			title: String(localized: "Current Scope", comment: "Select submenu item"),
			action: NSSelectorFromString("selectCurrentScope:"),
		)
		selectMenu.addItem(
			title: String(localized: "Enclosing Typing Pairs", comment: "Select submenu item"),
			action: NSSelectorFromString("selectBlock:"),
			key: "b",
			modifiers: [.command, .shift],
		)
		selectMenu.addItem(
			title: String(localized: "All", comment: "Select submenu item"),
			action: #selector(NSText.selectAll(_:)),
			key: "a",
		)
		let selectItem = menu.addItem(
			title: String(localized: "Select", comment: "Edit menu item"),
			action: nil,
		)
		selectItem.submenu = selectMenu

		// Find submenu
		let findMenu = NSMenu(title: String(localized: "Find", comment: "Edit menu submenu"))
		findMenu.addItem(
			title: String(localized: "Find and Replace…", comment: "Find submenu item"),
			action: NSSelectorFromString("orderFrontFindPanel:"),
			key: "f",
		)
		findMenu.addItem(
			title: String(localized: "Find in Project…", comment: "Find submenu item"),
			action: NSSelectorFromString("orderFrontFindInProjectPanel:"),
			key: "f",
			modifiers: [.command, .shift],
		)
		findMenu.addItem(.separator())
		findMenu.addItem(
			title: String(localized: "Find Next", comment: "Find submenu item"),
			action: NSSelectorFromString("findNext:"),
			key: "g",
		)
		findMenu.addItem(
			title: String(localized: "Find Previous", comment: "Find submenu item"),
			action: NSSelectorFromString("findPrevious:"),
			key: "g",
			modifiers: [.command, .shift],
		)
		findMenu.addItem(.separator())
		findMenu.addItem(
			title: String(localized: "Use Selection for Find", comment: "Find submenu item"),
			action: NSSelectorFromString("copySelectionToFindPboard:"),
			key: "e",
		)
		findMenu.addItem(
			title: String(localized: "Use Selection for Replace", comment: "Find submenu item"),
			action: NSSelectorFromString("copySelectionToReplacePboard:"),
			key: "e",
			modifiers: [.command, .shift],
		)
		let findItem = menu.addItem(
			title: String(localized: "Find", comment: "Edit menu item"),
			action: nil,
		)
		findItem.submenu = findMenu

		// Spelling submenu
		let spellingMenu = NSMenu(title: String(localized: "Spelling", comment: "Edit menu submenu"))
		spellingMenu.addItem(
			title: String(localized: "Spelling…", comment: "Spelling submenu item"),
			action: #selector(NSText.showGuessPanel(_:)),
			key: ":",
		)
		spellingMenu.addItem(
			title: String(localized: "Check Document Now", comment: "Spelling submenu item"),
			action: #selector(NSText.checkSpelling(_:)),
			key: ";",
		)
		spellingMenu.addItem(.separator())
		spellingMenu.addItem(
			title: String(localized: "Check Spelling as You Type", comment: "Spelling submenu item"),
			action: NSSelectorFromString("toggleContinuousSpellChecking:"),
		)
		let spellingItem = menu.addItem(
			title: String(localized: "Spelling", comment: "Edit menu item"),
			action: nil,
		)
		spellingItem.submenu = spellingMenu

		return item
	}

	// MARK: - View Menu

	private static func buildViewMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "View", comment: "Menu title"))
		let item = NSMenuItem(
			title: String(localized: "View", comment: "Menu title"),
			action: nil,
			keyEquivalent: "",
		)
		item.submenu = menu

		// Font submenu
		let fontMenu = NSMenu(title: String(localized: "Font", comment: "View menu submenu"))
		fontMenu.addItem(
			title: String(localized: "Show Fonts", comment: "Font submenu item"),
			action: #selector(NSFontManager.orderFrontFontPanel(_:)),
		)
		fontMenu.addItem(
			title: String(localized: "Bigger", comment: "Font submenu item"),
			action: NSSelectorFromString("makeTextLarger:"),
			key: "+",
		)
		fontMenu.addItem(
			title: String(localized: "Smaller", comment: "Font submenu item"),
			action: NSSelectorFromString("makeTextSmaller:"),
			key: "-",
		)
		fontMenu.addItem(
			title: String(localized: "Default Size", comment: "Font submenu item"),
			action: NSSelectorFromString("makeTextStandardSize:"),
			key: "0",
		)
		let fontItem = menu.addItem(
			title: String(localized: "Font", comment: "View menu item"),
			action: nil,
		)
		fontItem.submenu = fontMenu

		menu.addItem(
			title: String(localized: "Show File Browser", comment: "View menu item"),
			action: NSSelectorFromString("toggleFileBrowser:"),
			key: "d",
			modifiers: [.command, .option, .control],
		)
		menu.addItem(
			title: String(localized: "Show Line Numbers", comment: "View menu item"),
			action: NSSelectorFromString("toggleLineNumbers:"),
			key: "l",
			modifiers: [.command, .option],
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Show Invisibles", comment: "View menu item"),
			action: NSSelectorFromString("toggleShowInvisibles:"),
			key: "i",
			modifiers: [.command, .option],
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Enable Soft Wrap", comment: "View menu item"),
			action: NSSelectorFromString("toggleSoftWrap:"),
			key: "w",
			modifiers: [.command, .option],
		)
		menu.addItem(.separator())

		// Tab Size submenu
		let tabSizeMenu = NSMenu(title: String(localized: "Tab Size", comment: "View menu submenu"))
		for size in 2 ... 8 {
			let tabItem = tabSizeMenu.addItem(
				title: "\(size)",
				action: NSSelectorFromString("takeTabSizeFrom:"),
			)
			tabItem.tag = size
		}
		let tabSizeItem = menu.addItem(
			title: String(localized: "Tab Size", comment: "View menu item"),
			action: nil,
		)
		tabSizeItem.submenu = tabSizeMenu

		// Theme submenu (populated dynamically by AppDelegate)
		let themeMenu = NSMenu(title: String(localized: "Theme", comment: "View menu submenu"))
		let themeItem = menu.addItem(
			title: String(localized: "Theme", comment: "View menu item"),
			action: nil,
		)
		themeItem.submenu = themeMenu

		menu.addItem(.separator())

		// Fold Current Block
		menu.addItem(
			title: String(localized: "Fold Current Block", comment: "View menu item"),
			action: NSSelectorFromString("toggleCurrentFolding:"),
			key: String(Character(UnicodeScalar(NSF1FunctionKey)!)),
			modifiers: [],
		)

		// Toggle Foldings at Level submenu
		let foldMenu = NSMenu(
			title: String(localized: "Toggle Foldings at Level", comment: "View menu submenu"),
		)
		let allFoldItem = foldMenu.addItem(
			title: String(localized: "All Levels", comment: "Foldings submenu item"),
			action: NSSelectorFromString("takeLevelToFoldFrom:"),
			key: "0",
			modifiers: [.command, .option],
		)
		allFoldItem.tag = 0
		for level in 1 ... 9 {
			let levelItem = foldMenu.addItem(
				title: "\(level)",
				action: NSSelectorFromString("takeLevelToFoldFrom:"),
				key: "\(level)",
				modifiers: [.command, .option],
			)
			levelItem.tag = level
		}
		let foldItem = menu.addItem(
			title: String(localized: "Toggle Foldings at Level", comment: "View menu item"),
			action: nil,
		)
		foldItem.submenu = foldMenu

		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Enter Full Screen", comment: "View menu item"),
			action: #selector(NSWindow.toggleFullScreen(_:)),
			key: "f",
			modifiers: [.command, .control],
		)

		return item
	}

	// MARK: - Navigate Menu

	private static func buildNavigateMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "Navigate", comment: "Menu title"))
		let item = NSMenuItem(
			title: String(localized: "Navigate", comment: "Menu title"),
			action: nil,
			keyEquivalent: "",
		)
		item.submenu = menu

		menu.addItem(
			title: String(localized: "Jump to Line…", comment: "Navigate menu item"),
			action: NSSelectorFromString("orderFrontGoToLinePanel:"),
			key: "l",
		)
		menu.addItem(
			title: String(localized: "Jump to Symbol…", comment: "Navigate menu item"),
			action: NSSelectorFromString("showSymbolChooser:"),
			key: "t",
			modifiers: [.command, .shift],
		)
		menu.addItem(
			title: String(localized: "Jump to Selection", comment: "Navigate menu item"),
			action: #selector(NSTextView.centerSelectionInVisibleArea(_:)),
			key: "j",
		)
		menu.addItem(.separator())

		menu.addItem(
			title: String(localized: "Set Bookmark", comment: "Navigate menu item"),
			action: NSSelectorFromString("toggleCurrentBookmark:"),
			key: String(Character(UnicodeScalar(NSF2FunctionKey)!)),
			modifiers: [],
		)
		menu.addItem(
			title: String(localized: "Jump to Next Bookmark", comment: "Navigate menu item"),
			action: NSSelectorFromString("goToNextBookmark:"),
			key: String(Character(UnicodeScalar(NSF2FunctionKey)!)),
			modifiers: [],
		)
		menu.addItem(
			title: String(localized: "Jump to Previous Bookmark", comment: "Navigate menu item"),
			action: NSSelectorFromString("goToPreviousBookmark:"),
			key: String(Character(UnicodeScalar(NSF2FunctionKey)!)),
			modifiers: [.shift],
		)
		menu.addItem(.separator())

		// Scroll submenu
		let scrollMenu = NSMenu(title: String(localized: "Scroll", comment: "Navigate menu submenu"))
		scrollMenu.addItem(
			title: String(localized: "Line Up", comment: "Scroll submenu item"),
			action: NSSelectorFromString("scrollLineUp:"),
			key: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
			modifiers: [.command, .option, .control],
		)
		scrollMenu.addItem(
			title: String(localized: "Line Down", comment: "Scroll submenu item"),
			action: NSSelectorFromString("scrollLineDown:"),
			key: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)),
			modifiers: [.command, .option, .control],
		)
		scrollMenu.addItem(
			title: String(localized: "Column Left", comment: "Scroll submenu item"),
			action: NSSelectorFromString("scrollColumnLeft:"),
			key: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
			modifiers: [.command, .option, .control],
		)
		scrollMenu.addItem(
			title: String(localized: "Column Right", comment: "Scroll submenu item"),
			action: NSSelectorFromString("scrollColumnRight:"),
			key: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)),
			modifiers: [.command, .option, .control],
		)
		let scrollItem = menu.addItem(
			title: String(localized: "Scroll", comment: "Navigate menu item"),
			action: nil,
		)
		scrollItem.submenu = scrollMenu

		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Go to Related File", comment: "Navigate menu item"),
			action: NSSelectorFromString("goToRelatedFile:"),
			key: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
			modifiers: [.command, .option],
		)

		return item
	}

	// MARK: - Text Menu

	private static func buildTextMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "Text", comment: "Menu title"))
		let item = NSMenuItem(
			title: String(localized: "Text", comment: "Menu title"),
			action: nil,
			keyEquivalent: "",
		)
		item.submenu = menu

		menu.addItem(
			title: String(localized: "Transpose", comment: "Text menu item"),
			action: NSSelectorFromString("transpose:"),
		)
		menu.addItem(.separator())

		// Move Selection submenu
		let moveMenu = NSMenu(
			title: String(localized: "Move Selection", comment: "Text menu submenu"),
		)
		moveMenu.addItem(
			title: String(localized: "Up", comment: "Move Selection submenu item"),
			action: NSSelectorFromString("moveSelectionUp:"),
			key: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
			modifiers: [.command, .control],
		)
		moveMenu.addItem(
			title: String(localized: "Down", comment: "Move Selection submenu item"),
			action: NSSelectorFromString("moveSelectionDown:"),
			key: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)),
			modifiers: [.command, .control],
		)
		moveMenu.addItem(
			title: String(localized: "Left", comment: "Move Selection submenu item"),
			action: NSSelectorFromString("moveSelectionLeft:"),
			key: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
			modifiers: [.command, .control],
		)
		moveMenu.addItem(
			title: String(localized: "Right", comment: "Move Selection submenu item"),
			action: NSSelectorFromString("moveSelectionRight:"),
			key: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)),
			modifiers: [.command, .control],
		)
		let moveItem = menu.addItem(
			title: String(localized: "Move Selection", comment: "Text menu item"),
			action: nil,
		)
		moveItem.submenu = moveMenu

		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Toggle Case of Character / Selection", comment: "Text menu item"),
			action: NSSelectorFromString("changeCaseOfLetter:"),
		)
		menu.addItem(
			title: String(localized: "Toggle Case of Word / Selection", comment: "Text menu item"),
			action: NSSelectorFromString("changeCaseOfWord:"),
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Uppercase Word / Selection", comment: "Text menu item"),
			action: NSSelectorFromString("uppercaseWord:"),
		)
		menu.addItem(
			title: String(localized: "Lowercase Word / Selection", comment: "Text menu item"),
			action: NSSelectorFromString("lowercaseWord:"),
		)
		menu.addItem(
			title: String(localized: "Titlecase Line / Selection", comment: "Text menu item"),
			action: NSSelectorFromString("capitalizeWord:"),
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Shift Left", comment: "Text menu item"),
			action: NSSelectorFromString("shiftLeft:"),
			key: "[",
		)
		menu.addItem(
			title: String(localized: "Shift Right", comment: "Text menu item"),
			action: NSSelectorFromString("shiftRight:"),
			key: "]",
		)
		menu.addItem(
			title: String(localized: "Indent Line / Selection", comment: "Text menu item"),
			action: NSSelectorFromString("indent:"),
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Reformat Text", comment: "Text menu item"),
			action: NSSelectorFromString("reformatText:"),
		)
		menu.addItem(
			title: String(localized: "Reformat Text and Justify", comment: "Text menu item"),
			action: NSSelectorFromString("reformatTextAndJustify:"),
		)
		menu.addItem(
			title: String(localized: "Unwrap Paragraph", comment: "Text menu item"),
			action: NSSelectorFromString("unwrapText:"),
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Filter Through Command…", comment: "Text menu item"),
			action: NSSelectorFromString("orderFrontRunCommandWindow:"),
			key: "|",
		)

		return item
	}

	// MARK: - File Browser Menu

	private static func buildFileBrowserMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "File Browser", comment: "Menu title"))
		let item = NSMenuItem(
			title: String(localized: "File Browser", comment: "Menu title"),
			action: nil,
			keyEquivalent: "",
		)
		item.submenu = menu

		menu.addItem(
			title: String(localized: "New File", comment: "File Browser menu item"),
			action: NSSelectorFromString("newDocumentInDirectory:"),
			key: "n",
			modifiers: [.command, .control],
		)
		menu.addItem(
			title: String(localized: "New Folder", comment: "File Browser menu item"),
			action: NSSelectorFromString("newFolder:"),
			key: "n",
			modifiers: [.command, .shift],
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Back", comment: "File Browser menu item"),
			action: NSSelectorFromString("goBack:"),
		)
		menu.addItem(
			title: String(localized: "Forward", comment: "File Browser menu item"),
			action: NSSelectorFromString("goForward:"),
		)
		menu.addItem(
			title: String(localized: "Enclosing Folder", comment: "File Browser menu item"),
			action: NSSelectorFromString("goToParentFolder:"),
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Select Document", comment: "File Browser menu item"),
			action: NSSelectorFromString("revealFileInProject:"),
			key: "r",
			modifiers: [.command, .control],
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Project Folder", comment: "File Browser menu item"),
			action: NSSelectorFromString("goToProjectFolder:"),
			key: "p",
			modifiers: [.command, .shift],
		)
		menu.addItem(
			title: String(localized: "SCM Status", comment: "File Browser menu item"),
			action: NSSelectorFromString("goToSCMDataSource:"),
			key: "y",
			modifiers: [.command, .shift],
		)
		menu.addItem(
			title: String(localized: "Computer", comment: "File Browser menu item"),
			action: NSSelectorFromString("goToComputer:"),
			key: "c",
			modifiers: [.command, .shift],
		)
		menu.addItem(
			title: String(localized: "Home", comment: "File Browser menu item"),
			action: NSSelectorFromString("goToHome:"),
			key: "h",
			modifiers: [.command, .shift],
		)
		menu.addItem(
			title: String(localized: "Desktop", comment: "File Browser menu item"),
			action: NSSelectorFromString("goToDesktop:"),
			key: "d",
			modifiers: [.command, .shift],
		)
		menu.addItem(
			title: String(localized: "Favorites", comment: "File Browser menu item"),
			action: NSSelectorFromString("goToFavorites:"),
		)

		return item
	}

	// MARK: - Bundles Menu

	private static func buildBundlesMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "Bundles", comment: "Menu title"))
		let item = NSMenuItem(
			title: String(localized: "Bundles", comment: "Menu title"),
			action: nil,
			keyEquivalent: "",
		)
		item.submenu = menu

		menu.addItem(
			title: String(localized: "Select Bundle Item…", comment: "Bundles menu item"),
			action: NSSelectorFromString("showBundleItemChooser:"),
			key: "t",
			modifiers: [.command, .control],
		)
		menu.addItem(
			title: String(localized: "Edit Bundles…", comment: "Bundles menu item"),
			action: NSSelectorFromString("showBundleEditor:"),
			key: "b",
			modifiers: [.command, .option, .control],
		)
		menu.addItem(
			title: String(localized: "Manage Bundles…", comment: "Bundles menu item"),
			action: NSSelectorFromString("showBundleManager:"),
			key: "",
		)
		menu.addItem(.separator())
		// Bundle submenus will be dynamically populated later

		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Start/Stop Recording", comment: "Bundles menu item"),
			action: NSSelectorFromString("toggleMacroRecording:"),
			key: "m",
			modifiers: [.command, .option],
		)
		menu.addItem(
			title: String(localized: "Replay Macro", comment: "Bundles menu item"),
			action: NSSelectorFromString("replayMacro:"),
			key: "m",
			modifiers: [.command, .option, .shift],
		)

		return item
	}

	// MARK: - Window Menu

	private static func buildWindowMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "Window", comment: "Menu title"))
		let item = NSMenuItem(
			title: String(localized: "Window", comment: "Menu title"),
			action: nil,
			keyEquivalent: "",
		)
		item.submenu = menu

		menu.addItem(
			title: String(localized: "Minimize", comment: "Window menu item"),
			action: #selector(NSWindow.miniaturize(_:)),
			key: "m",
		)
		menu.addItem(
			title: String(localized: "Zoom", comment: "Window menu item"),
			action: #selector(NSWindow.performZoom(_:)),
		)
		menu.addItem(.separator())

		// Tab navigation — visible items
		menu.addItem(
			title: String(localized: "Show Previous Tab", comment: "Window menu item"),
			action: NSSelectorFromString("selectPreviousTab:"),
			key: String(Character(UnicodeScalar(0x19))), // backtab
			modifiers: [.control, .shift],
		)
		menu.addItem(
			title: String(localized: "Show Next Tab", comment: "Window menu item"),
			action: NSSelectorFromString("selectNextTab:"),
			key: "\t",
			modifiers: [.control],
		)

		// Hidden alternate key equivalents for tab switching
		let prevAlt1 = menu.addItem(
			title: String(localized: "Show Previous Tab", comment: "Window menu item"),
			action: NSSelectorFromString("selectPreviousTab:"),
			key: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
			modifiers: [.command, .option],
		)
		prevAlt1.isHidden = true
		prevAlt1.allowsKeyEquivalentWhenHidden = true

		let nextAlt1 = menu.addItem(
			title: String(localized: "Show Next Tab", comment: "Window menu item"),
			action: NSSelectorFromString("selectNextTab:"),
			key: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)),
			modifiers: [.command, .option],
		)
		nextAlt1.isHidden = true
		nextAlt1.allowsKeyEquivalentWhenHidden = true

		let prevAlt2 = menu.addItem(
			title: String(localized: "Show Previous Tab", comment: "Window menu item"),
			action: NSSelectorFromString("selectPreviousTab:"),
			key: "{",
		)
		prevAlt2.isHidden = true
		prevAlt2.allowsKeyEquivalentWhenHidden = true

		let nextAlt2 = menu.addItem(
			title: String(localized: "Show Next Tab", comment: "Window menu item"),
			action: NSSelectorFromString("selectNextTab:"),
			key: "}",
		)
		nextAlt2.isHidden = true
		nextAlt2.allowsKeyEquivalentWhenHidden = true

		menu.addItem(.separator())

		// ⌘1–⌘8 for tabs, ⌘9 for last tab
		for i in 1 ... 8 {
			let tabItem = menu.addItem(
				title: String(
					localized: "Tab \(i)",
					comment: "Window menu: switch to tab by number",
				),
				action: NSSelectorFromString("takeSelectedTabIndexFrom:"),
				key: "\(i)",
			)
			tabItem.tag = i - 1
			tabItem.isHidden = true
			tabItem.allowsKeyEquivalentWhenHidden = true
		}
		let lastTabItem = menu.addItem(
			title: String(localized: "Last Tab", comment: "Window menu item"),
			action: NSSelectorFromString("takeSelectedTabIndexFrom:"),
			key: "9",
		)
		lastTabItem.tag = -1 // Convention: -1 means "last"
		lastTabItem.isHidden = true
		lastTabItem.allowsKeyEquivalentWhenHidden = true

		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Move Tab to New Window", comment: "Window menu item"),
			action: NSSelectorFromString("moveDocumentToNewWindow:"),
		)
		menu.addItem(
			title: String(localized: "Merge All Windows", comment: "Window menu item"),
			action: NSSelectorFromString("mergeAllWindows:"),
		)
		menu.addItem(.separator())
		menu.addItem(
			title: String(localized: "Bring All to Front", comment: "Window menu item"),
			action: #selector(NSApplication.arrangeInFront(_:)),
		)

		NSApp.windowsMenu = menu
		return item
	}

	// MARK: - Help Menu

	private static func buildHelpMenu() -> NSMenuItem {
		let menu = NSMenu(title: String(localized: "Help", comment: "Menu title"))
		let item = NSMenuItem(
			title: String(localized: "Help", comment: "Menu title"),
			action: nil,
			keyEquivalent: "",
		)
		item.submenu = menu

		menu.addItem(
			title: String(localized: "TextMate Help", comment: "Help menu item"),
			action: #selector(NSApplication.showHelp(_:)),
			key: "?",
		)

		NSApp.helpMenu = menu
		return item
	}
}

// MARK: - NSMenu Convenience Helpers

extension NSMenu {
	/// Add a menu item with title, action, and optional key equivalent.
	@discardableResult
	func addItem(
		title: String,
		action: Selector?,
		key: String = "",
		modifiers: NSEvent.ModifierFlags = .command,
	) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
		if !key.isEmpty {
			item.keyEquivalentModifierMask = modifiers
		} else {
			item.keyEquivalentModifierMask = []
		}
		addItem(item)
		return item
	}
}
