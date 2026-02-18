#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import TMBundleRuntime
@testable import TMBundleUI

// MARK: - Bundle Menu Builder Integration Tests

@Suite("BundleMenuBuilder — Menu Population")
@MainActor
struct BundleMenuBuilderMenuTests {
	private func makeIndex(
		items: [BundleItem] = [],
		bundles: [BundleDescriptor] = [],
	) -> BundleIndex {
		let index = BundleIndex()
		index.setIndex(items: items, bundles: bundles)
		return index
	}

	@Test("Creates Bundles menu with correct title")
	func createBundlesMenu() {
		let index = makeIndex()
		let builder = BundleMenuBuilder(bundleIndex: index)
		let menu = builder.createBundlesMenu()
		#expect(menu.title == "Bundles")
		#expect(menu.delegate === builder)
	}

	@Test("Creates bundle submenu with identifier")
	func createBundleSubmenu() {
		let index = makeIndex(bundles: [
			BundleDescriptor(uuid: "b1", name: "Ruby"),
		])
		let builder = BundleMenuBuilder(bundleIndex: index)
		let submenu = builder.createBundleMenu(bundleUUID: "b1")
		#expect(submenu.title == "Ruby")
		#expect(submenu.identifier?.rawValue == "b1")
	}

	@Test("Top-level menu shows enabled bundles with executable items")
	func topLevelMenuPopulation() {
		let items = [
			BundleItem(uuid: "c1", name: "Run", kind: .command, bundleUUID: "b1"),
			BundleItem(uuid: "g1", name: "Grammar", kind: .grammar, bundleUUID: "b2"),
		]
		let bundles = [
			BundleDescriptor(uuid: "b1", name: "Ruby"),
			BundleDescriptor(uuid: "b2", name: "PlainText"),
		]
		let index = makeIndex(items: items, bundles: bundles)
		let builder = BundleMenuBuilder(bundleIndex: index)
		let menu = builder.createBundlesMenu()

		// Trigger population.
		builder.menuNeedsUpdate(menu)

		// Only Ruby has executable items (commands).
		#expect(menu.items.count == 1)
		#expect(menu.items[0].title == "Ruby")
		#expect(menu.items[0].submenu != nil)
	}

	@Test("Disabled bundles are excluded")
	func disabledBundlesExcluded() {
		let items = [
			BundleItem(uuid: "c1", name: "Run", kind: .command, bundleUUID: "b1"),
		]
		let bundles = [
			BundleDescriptor(uuid: "b1", name: "Disabled", isEnabled: false),
		]
		let index = makeIndex(items: items, bundles: bundles)
		let builder = BundleMenuBuilder(bundleIndex: index)
		let menu = builder.createBundlesMenu()
		builder.menuNeedsUpdate(menu)

		#expect(menu.items.isEmpty)
	}

	@Test("Bundle submenu lists executable items alphabetically when no menu structure")
	func bundleSubmenuAlphabetical() {
		let items = [
			BundleItem(uuid: "c2", name: "Zebra", kind: .command, bundleUUID: "b1"),
			BundleItem(uuid: "c1", name: "Alpha", kind: .command, bundleUUID: "b1"),
			BundleItem(uuid: "g1", name: "Grammar", kind: .grammar, bundleUUID: "b1"),
		]
		let bundles = [BundleDescriptor(uuid: "b1", name: "Test")]
		let index = makeIndex(items: items, bundles: bundles)
		let builder = BundleMenuBuilder(bundleIndex: index)

		let submenu = NSMenu(title: "Test")
		submenu.identifier = NSUserInterfaceItemIdentifier("b1")
		builder.menuNeedsUpdate(submenu)

		// Only commands, sorted alphabetically.
		#expect(submenu.items.count == 2)
		#expect(submenu.items[0].title == "Alpha")
		#expect(submenu.items[1].title == "Zebra")
	}

	@Test("Bundle submenu follows declared menu structure")
	func bundleSubmenuStructured() {
		let items = [
			BundleItem(uuid: "c1", name: "First", kind: .command, bundleUUID: "b1"),
			BundleItem(uuid: "c2", name: "Second", kind: .command, bundleUUID: "b1"),
		]
		let menuItems: [BundleMenuItem] = [
			.item(uuid: "c2"),
			.separator,
			.item(uuid: "c1"),
		]
		let bundles = [BundleDescriptor(uuid: "b1", name: "Test", menuItems: menuItems)]
		let index = makeIndex(items: items, bundles: bundles)
		let builder = BundleMenuBuilder(bundleIndex: index)

		let submenu = NSMenu(title: "Test")
		submenu.identifier = NSUserInterfaceItemIdentifier("b1")
		builder.menuNeedsUpdate(submenu)

		#expect(submenu.items.count == 3)
		#expect(submenu.items[0].title == "Second")
		#expect(submenu.items[1].isSeparatorItem)
		#expect(submenu.items[2].title == "First")
	}

	@Test("Menu items use bundle item action")
	func menuItemAction() {
		let items = [
			BundleItem(uuid: "c1", name: "Run", kind: .command, bundleUUID: "b1"),
		]
		let bundles = [BundleDescriptor(uuid: "b1", name: "Test")]
		let index = makeIndex(items: items, bundles: bundles)
		let builder = BundleMenuBuilder(bundleIndex: index)

		let submenu = NSMenu(title: "Test")
		submenu.identifier = NSUserInterfaceItemIdentifier("b1")
		builder.menuNeedsUpdate(submenu)

		let item = submenu.items[0]
		#expect(item.action == BundleMenuBuilder.bundleItemAction)
		#expect(item.representedObject as? String == "c1")
	}

	@Test("Menu item has key equivalent from bundle item")
	func menuItemKeyEquivalent() {
		let items = [
			BundleItem(
				uuid: "c1", name: "Run", kind: .command,
				bundleUUID: "b1", keyEquivalent: "@r",
			),
		]
		let bundles = [BundleDescriptor(uuid: "b1", name: "Test")]
		let index = makeIndex(items: items, bundles: bundles)
		let builder = BundleMenuBuilder(bundleIndex: index)

		let submenu = NSMenu(title: "Test")
		submenu.identifier = NSUserInterfaceItemIdentifier("b1")
		builder.menuNeedsUpdate(submenu)

		let item = submenu.items[0]
		#expect(item.keyEquivalent == "r")
		#expect(item.keyEquivalentModifierMask.contains(.command))
	}

	@Test("Menu item shows tab trigger tooltip")
	func menuItemTabTrigger() {
		let items = [
			BundleItem(
				uuid: "s1", name: "For Loop", kind: .snippet,
				bundleUUID: "b1", tabTrigger: "for",
			),
		]
		let bundles = [BundleDescriptor(uuid: "b1", name: "Test")]
		let index = makeIndex(items: items, bundles: bundles)
		let builder = BundleMenuBuilder(bundleIndex: index)

		let submenu = NSMenu(title: "Test")
		submenu.identifier = NSUserInterfaceItemIdentifier("b1")
		builder.menuNeedsUpdate(submenu)

		#expect(submenu.items[0].toolTip?.contains("for") == true)
	}

	@Test("Disabled items are excluded from menu")
	func disabledItemsExcluded() {
		let items = [
			BundleItem(
				uuid: "c1", name: "Visible", kind: .command,
				bundleUUID: "b1",
			),
			BundleItem(
				uuid: "c2", name: "Hidden", kind: .command,
				bundleUUID: "b1", isDisabled: true,
			),
		]
		let bundles = [BundleDescriptor(uuid: "b1", name: "Test")]
		let index = makeIndex(items: items, bundles: bundles)
		let builder = BundleMenuBuilder(bundleIndex: index)

		let submenu = NSMenu(title: "Test")
		submenu.identifier = NSUserInterfaceItemIdentifier("b1")
		builder.menuNeedsUpdate(submenu)

		#expect(submenu.items.count == 1)
		#expect(submenu.items[0].title == "Visible")
	}

	@Test("Scope provider is available")
	func scopeProvider() {
		let index = makeIndex()
		let builder = BundleMenuBuilder(bundleIndex: index)
		builder.scopeProvider = { "source.ruby" }
		#expect(builder.scopeProvider?() == "source.ruby")
	}

	@Test("Disambiguation menu returns nil for empty items")
	func disambiguationEmpty() {
		let result = BundleDisambiguationMenu.show(items: [], at: .zero, in: nil)
		#expect(result == nil)
	}

	@Test("Disambiguation menu returns UUID for single item")
	func disambiguationSingle() {
		let item = BundleItem(
			uuid: "only-one", name: "Only", kind: .command, bundleUUID: "b1",
		)
		let result = BundleDisambiguationMenu.show(items: [item], at: .zero, in: nil)
		#expect(result == "only-one")
	}
}

// MARK: - Bundle Loader + Index Integration

@Suite("BundleLoader — Index Integration")
struct BundleLoaderIndexIntegrationTests {
	@Test("Load from empty paths produces empty index")
	func emptyPaths() {
		let loader = BundleLoader()
		let index = BundleIndex()
		let result = loader.loadFromPaths([])
		index.setIndex(items: result.items, bundles: result.bundles)
		#expect(index.itemCount == 0)
		#expect(index.allBundles.isEmpty)
	}

	@Test("Search paths include user and system locations")
	func searchPaths() {
		let paths = BundleLocations.searchPaths()
		// Should have at least some paths configured.
		#expect(!paths.isEmpty)
	}

	@Test("User bundles path is in Application Support")
	func userBundlesPath() {
		let path = BundleLocations.userBundlesPath
		#expect(path.contains("Application Support"))
		#expect(path.contains("TextMate"))
		#expect(path.hasSuffix("Bundles"))
	}

	@Test("Managed bundles path is in Application Support")
	func managedBundlesPath() {
		let path = BundleLocations.managedBundlesPath
		#expect(path.contains("Application Support"))
		#expect(path.contains("Managed"))
	}

	@Test("Item subdirectories cover all expected types")
	func itemSubdirectories() {
		let dirs = BundleLoader.itemSubdirectories.map(\.directory)
		#expect(dirs.contains("Commands"))
		#expect(dirs.contains("Snippets"))
		#expect(dirs.contains("Syntaxes"))
		#expect(dirs.contains("Themes"))
		#expect(dirs.contains("Preferences"))
		#expect(dirs.contains("Macros"))
		#expect(dirs.contains("DragCommands"))
	}
}
#endif
