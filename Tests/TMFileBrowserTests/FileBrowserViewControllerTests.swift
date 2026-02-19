#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import TMFileBrowser

@Suite("FileBrowserViewController initialization")
struct FileBrowserViewControllerInitTests {
	@Test("controller initializes without crashing")
	@MainActor func basicInit() {
		let vc = FileBrowserViewController()
		#expect(vc.fileItem == nil)
		#expect(vc.url == nil)
		#expect(vc.path == nil)
	}

	@Test("loadView creates composite view")
	@MainActor func loadViewCreatesComposite() {
		let vc = FileBrowserViewController()
		vc.loadView()
		#expect(vc.view as? FileBrowserCompositeView != nil)
	}

	@Test("default navigation state")
	@MainActor func defaultNavigationState() {
		let vc = FileBrowserViewController()
		#expect(!vc.canGoBack)
		#expect(!vc.canGoForward)
	}

	@Test("default preferences")
	@MainActor func defaultPreferences() {
		let vc = FileBrowserViewController()
		#expect(!vc.canExpandSymbolicLinks)
		#expect(!vc.canExpandPackages)
		#expect(!vc.sortDirectoriesBeforeFiles)
		#expect(!vc.showExcludedItems)
	}
}

@Suite("FileBrowserViewController navigation")
struct FileBrowserViewControllerNavigationTests {
	@Test("goToURL sets the file item")
	@MainActor func goToURLSetsFileItem() {
		let vc = FileBrowserViewController()
		vc.loadView()
		let url = URL(fileURLWithPath: "/tmp")
		vc.goToURL(url)
		#expect(vc.url != nil)
	}

	@Test("goToURL to same URL is a no-op")
	@MainActor func goToURLSameURL() {
		let vc = FileBrowserViewController()
		vc.loadView()
		let url = URL(fileURLWithPath: "/tmp")
		vc.goToURL(url)
		let item1 = vc.fileItem
		vc.goToURL(url)
		let item2 = vc.fileItem
		// Same URL should not recreate the file item
		#expect(item1 === item2)
	}

	@Test("navigation enables back button after second URL")
	@MainActor func navigationHistory() {
		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(URL(fileURLWithPath: "/tmp"))
		#expect(!vc.canGoBack)

		vc.goToURL(URL(fileURLWithPath: "/usr"))
		#expect(vc.canGoBack)
		#expect(!vc.canGoForward)
	}

	@Test("goBack restores previous URL")
	@MainActor func goBack() {
		let vc = FileBrowserViewController()
		vc.loadView()
		let url1 = URL(fileURLWithPath: "/tmp")
		let url2 = URL(fileURLWithPath: "/usr")

		vc.goToURL(url1)
		vc.goToURL(url2)
		vc.goBack(nil)

		#expect(vc.url == url1)
		#expect(vc.canGoForward)
	}

	@Test("goForward restores next URL")
	@MainActor func goForward() {
		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(URL(fileURLWithPath: "/tmp"))
		vc.goToURL(URL(fileURLWithPath: "/usr"))
		vc.goBack(nil)
		vc.goForward(nil)

		#expect(vc.url?.path == "/usr")
	}

	@Test("goToComputer navigates to computer URL")
	@MainActor func goToComputer() {
		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(URL(fileURLWithPath: "/tmp"))
		vc.goToComputer(nil)
		#expect(vc.url == FileBrowserLocation.computer)
	}

	@Test("goToHome navigates to home directory")
	@MainActor func goToHome() {
		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(URL(fileURLWithPath: "/tmp"))
		vc.goToHome(nil)
		#expect(vc.url?.path == NSHomeDirectory())
	}
}

@Suite("FileBrowserViewController item comparator")
struct FileBrowserViewControllerComparatorTests {
	@Test("alphabetical sort by default")
	@MainActor func alphabeticalSort() {
		let vc = FileBrowserViewController()
		let comparator = vc.itemComparator()

		let a = FileItem(url: URL(fileURLWithPath: "/tmp/alpha"))
		a.localizedName = "alpha"
		let b = FileItem(url: URL(fileURLWithPath: "/tmp/beta"))
		b.localizedName = "beta"

		#expect(comparator(a, b) == .orderedAscending)
		#expect(comparator(b, a) == .orderedDescending)
		#expect(comparator(a, a) == .orderedSame)
	}

	@Test("directories before files when enabled")
	@MainActor func directoriesFirst() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-comparator-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let subdir = dir.appendingPathComponent("adir")
		try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

		let file = dir.appendingPathComponent("zfile.txt")
		FileManager.default.createFile(atPath: file.path, contents: nil)

		let vc = FileBrowserViewController()
		vc.sortDirectoriesBeforeFiles = true
		let comparator = vc.itemComparator()

		let dirItem = FileItem(url: subdir)
		dirItem.localizedName = "zdir"
		let fileItem = FileItem(url: file)
		fileItem.localizedName = "afile"

		// Directory should come first even though its name is later alphabetically
		#expect(comparator(dirItem, fileItem) == .orderedAscending)
	}
}

@Suite("FileBrowserViewController session state")
struct FileBrowserViewControllerSessionTests {
	@Test("session state roundtrip preserves URL")
	@MainActor func sessionStateRoundtrip() {
		let vc = FileBrowserViewController()
		vc.loadView()
		let url = URL(fileURLWithPath: "/tmp")
		vc.goToURL(url)

		let state = vc.sessionState

		let vc2 = FileBrowserViewController()
		vc2.loadView()
		vc2.setupView(withState: state)

		#expect(vc2.url == url)
	}

	@Test("session state contains history")
	@MainActor func sessionStateHasHistory() {
		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(URL(fileURLWithPath: "/tmp"))
		vc.goToURL(URL(fileURLWithPath: "/usr"))

		let state = vc.sessionState
		#expect(state["history"] is [[String: Any]])
		#expect((state["history"] as? [[String: Any]])?.count == 2)
	}

	@Test("session state preserves showHidden flag")
	@MainActor func sessionStateShowHidden() {
		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(URL(fileURLWithPath: "/tmp"))
		vc.showExcludedItems = true

		let state = vc.sessionState
		#expect(state["showHidden"] as? Bool == true)
	}

	@Test("variables returns dictionary")
	@MainActor func variablesReturns() {
		let vc = FileBrowserViewController()
		let env = vc.variables
		let typedEnv: [String: String] = env
		#expect(type(of: typedEnv) == [String: String].self)
	}
}

@Suite("FileBrowserCompositeView")
struct FileBrowserCompositeViewTests {
	@Test("composite view initializes subviews")
	@MainActor func initializes() {
		let view = FileBrowserCompositeView()
		#expect(view.headerView.superview == view)
		#expect(view.outlineView.superview != nil)
		#expect(view.actionsView.superview == view)
	}
}

@Suite("FileBrowserHeaderView")
struct FileBrowserHeaderViewTests {
	@Test("header view creates navigation buttons")
	@MainActor func navigationButtons() {
		let header = FileBrowserHeaderView()
		#expect(header.goBackButton.superview == header)
		#expect(header.goForwardButton.superview == header)
		#expect(header.folderPopUpButton.superview == header)
	}
}

@Suite("FileBrowserActionsView")
struct FileBrowserActionsViewTests {
	@Test("actions view creates action buttons")
	@MainActor func actionButtons() {
		let actions = FileBrowserActionsView()
		#expect(actions.createButton.superview == actions)
		#expect(actions.reloadButton.superview == actions)
		#expect(actions.favoritesButton.superview == actions)
		#expect(actions.scmButton.superview == actions)
	}
}

@Suite("FileBrowserOutlineView")
struct FileBrowserOutlineViewTests {
	@Test("outline view initializes")
	@MainActor func initializes() {
		let ov = FileBrowserOutlineView()
		#expect(type(of: ov) == FileBrowserOutlineView.self)
	}
}

@Suite("FileItemTableCellView")
struct FileItemTableCellViewTests {
	@Test("cell view initializes with subviews")
	@MainActor func initializes() {
		let cell = FileItemTableCellView()
		#expect(cell.openButton.superview == cell)
		#expect(cell.closeButton.superview == cell)
		#expect(cell.iconView.superview == cell)
		#expect(cell.nameField.superview == cell)
	}

	@Test("configure sets name and icon")
	@MainActor func configure() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-cell-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let file = dir.appendingPathComponent("hello.txt")
		FileManager.default.createFile(atPath: file.path, contents: nil)

		let item = FileItem(url: file)
		let icon = NSWorkspace.shared.icon(forFile: file.path)
		let cell = FileItemTableCellView()
		cell.configure(with: item, icon: icon)
		#expect(cell.nameField.stringValue == item.displayName)
	}
}

// MARK: - Breadcrumb Popup Menu Tests

@Suite("FileBrowserViewController breadcrumb popup")
struct FileBrowserBreadcrumbTests {
	@MainActor private func buildMenu(for vc: FileBrowserViewController) -> NSMenu {
		let menu = NSMenu()
		menu.addItem(NSMenuItem(title: "loc", action: nil, keyEquivalent: ""))
		vc.populateFolderMenu(menu)
		return menu
	}

	@Test("populateFolderMenu builds items with nil fileItem")
	@MainActor func populateNilFileItem() {
		let vc = FileBrowserViewController()
		vc.loadView()
		let menu = buildMenu(for: vc)

		// loc + Computer + separator + Other…
		#expect(menu.numberOfItems == 4)
		#expect(menu.item(at: 1)?.title == FileManager.default.displayName(atPath: "/"))
		#expect(menu.item(at: 3)?.title == "Other\u{2026}")
	}

	@Test("populateFolderMenu builds parent chain for deep path")
	@MainActor func populateParentChain() throws {
		let base = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-bc-\(UUID())")
		let deep = base.appendingPathComponent("sub")
		try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: base) }

		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(deep)
		let menu = buildMenu(for: vc)

		// loc + parent entries (varies by depth) + Computer + separator + Other… + separator + "Use … as Project Folder"
		// The parent chain should include at least the base dir name
		let titles = (0 ..< menu.numberOfItems).compactMap { menu.item(at: $0)?.title }
		#expect(titles.contains(FileManager.default.displayName(atPath: base.path)))
	}

	@Test("populateFolderMenu includes Computer entry")
	@MainActor func populateComputerEntry() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-bc-comp-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(dir)
		let menu = buildMenu(for: vc)

		let computerTitle = FileManager.default.displayName(atPath: "/")
		let titles = (0 ..< menu.numberOfItems).compactMap { menu.item(at: $0)?.title }
		#expect(titles.contains(computerTitle))
	}

	@Test("populateFolderMenu includes Other item")
	@MainActor func populateOtherItem() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-bc-other-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(dir)
		let menu = buildMenu(for: vc)

		let titles = (0 ..< menu.numberOfItems).compactMap { menu.item(at: $0)?.title }
		#expect(titles.contains("Other\u{2026}"))
	}

	@Test("populateFolderMenu includes project folder item")
	@MainActor func populateProjectFolderItem() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-bc-proj-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let vc = FileBrowserViewController()
		vc.loadView()
		vc.goToURL(dir)
		let menu = buildMenu(for: vc)

		let displayName = FileManager.default.displayName(atPath: dir.path)
		let expected = "Use \u{201C}\(displayName)\u{201D} as Project Folder"
		let titles = (0 ..< menu.numberOfItems).compactMap { menu.item(at: $0)?.title }
		#expect(titles.contains(expected))
	}
}
#endif
