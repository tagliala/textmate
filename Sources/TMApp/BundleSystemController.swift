import AppKit
import TMBundleRuntime
import TMBundleUI

/// Manages the full bundle system lifecycle: discovery, indexing,
/// menu population, and command execution.
///
/// Created once by `AppDelegate` at launch time. Owns the `BundleIndex`,
/// `BundleLoader`, `BundleMenuBuilder`, and `CommandDispatcher`.
@MainActor
final class BundleSystemController {
	/// The global bundle index (queryable by all layers).
	let bundleIndex = BundleIndex()

	/// Loader that discovers `.tmbundle` directories.
	private let loader = BundleLoader()

	/// Builds and dynamically populates the Bundles menu.
	let menuBuilder: BundleMenuBuilder

	/// Dispatches bundle commands for execution.
	let commandDispatcher: CommandDispatcher

	/// Installer for managing bundle install/update/uninstall.
	lazy var bundleInstaller = BundleInstaller()

	/// Whether bundles have been loaded at least once.
	private(set) var hasLoadedBundles = false

	init() {
		menuBuilder = BundleMenuBuilder(bundleIndex: bundleIndex)
		commandDispatcher = CommandDispatcher(
			bundleIndex: bundleIndex,
			securityPolicy: SecurityPolicy(),
		)

		let permissionDialog = PermissionDialogController()
		commandDispatcher.permissionHandler = { request in
			await permissionDialog.showPermissionDialog(for: request)
		}
	}

	// MARK: - Loading

	/// Loads all bundles from standard search paths into the index.
	///
	/// Call this once from `applicationDidFinishLaunching`. The load
	/// happens on a background thread; the index is updated on `@MainActor`
	/// when complete.
	func loadBundlesAsync() async {
		let loader = loader
		let result = await Task.detached(priority: .userInitiated) {
			loader.loadAll()
		}.value
		bundleIndex.setIndex(items: result.items, bundles: result.bundles)
		hasLoadedBundles = true
		NSLog(
			"TMBundles: loaded %d items from %d bundles",
			result.items.count,
			result.bundles.count,
		)
	}

	/// Loads all bundles synchronously (for testing or fallback).
	func loadBundles() {
		let result = loader.loadAll()
		bundleIndex.setIndex(items: result.items, bundles: result.bundles)
		hasLoadedBundles = true
		NSLog(
			"TMBundles: loaded %d items from %d bundles",
			result.items.count,
			result.bundles.count,
		)
	}

	/// Loads bundles from specific paths (useful for testing).
	func loadBundles(from paths: [String]) {
		let result = loader.loadFromPaths(paths)
		bundleIndex.setIndex(items: result.items, bundles: result.bundles)
		hasLoadedBundles = true
	}

	// MARK: - Menu Wiring

	/// Installs the menu builder as delegate for the Bundles submenu.
	///
	/// Call after the main menu is built. Finds the "Bundles" menu by
	/// title and makes it dynamically populated via `menuNeedsUpdate`.
	func installBundlesMenu(in mainMenu: NSMenu) {
		guard let bundlesItem = mainMenu.items.first(where: {
			$0.submenu?.title == "Bundles"
		}),
			let bundlesMenu = bundlesItem.submenu
		else {
			return
		}

		bundlesMenu.delegate = menuBuilder
	}
}
