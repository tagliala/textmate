#if canImport(AppKit)
import AppKit
import Testing
@testable import TMApp
@testable import TMBundleRuntime
@testable import TMBundleUI

@Suite("BundleManagerController wiring")
@MainActor
struct BundleManagerWiringTests {
	@Test("Bundles menu contains Manage Bundles… item")
	func manageBundlesMenuItem() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let bundlesMenu = try #require(menu.items[7].submenu)
		let item = bundlesMenu.items.first {
			$0.title == String(localized: "Manage Bundles…", comment: "Bundles menu item")
		}
		#expect(item != nil)
		#expect(item?.action == NSSelectorFromString("showBundleManager:"))
	}

	@Test("BundleManagerController initialises with BundleInstaller")
	func controllerInit() {
		let installer = BundleInstaller()
		let controller = BundleManagerController(installer: installer)
		#expect(controller.installer === installer)
		#expect(controller.window != nil)
		#expect(controller.window?.title == "Bundle Manager")
	}

	@Test("BundleSystemController exposes bundleInstaller")
	func bundleSystemExposesInstaller() {
		let system = BundleSystemController()
		let installer = system.bundleInstaller
		#expect(installer is BundleInstaller)
	}

	@Test("Manage Bundles… item has no key equivalent")
	func manageBundlesNoKeyEquivalent() throws {
		let menu = MainMenuBuilder.buildMainMenu()
		let bundlesMenu = try #require(menu.items[7].submenu)
		let item = bundlesMenu.items.first {
			$0.action == NSSelectorFromString("showBundleManager:")
		}
		#expect(item?.keyEquivalent == "")
	}
}
#endif
