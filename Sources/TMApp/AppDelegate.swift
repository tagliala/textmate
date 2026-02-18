import AppKit
import TMBundleRuntime
import TMBundleUI
import TMDocumentWindow
import TMTheme

/// The main application delegate. Sets up the menu bar, loads the default
/// theme, installs key bindings, creates the initial document window, and
/// manages window state restoration.
///
/// Matches TextMate's initial launch behaviour: one untitled document window
/// with the default theme applied.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency BundleMenuActionTarget {
	private var windowControllers: [DocumentWindowController] = []

	/// The currently loaded theme, applied to every new window.
	private var currentTheme: Theme?

	/// Custom key bindings loaded from `KeyBindings.dict`.
	private var keyBindings: [KeyBindingsLoader.KeyBinding] = []

	/// Event monitor for custom key bindings.
	private var keyEventMonitor: Any?

	/// The bundle system: loader, index, menu builder, command dispatch.
	private let bundleSystem = BundleSystemController()

	// MARK: - Application Lifecycle

	func applicationDidFinishLaunching(_: Notification) {
		NSApp.mainMenu = MainMenuBuilder.buildMainMenu()
		loadDefaultTheme()
		loadKeyBindings()
		loadBundles()
		restoreWindowState() ?? newDocument(nil)
	}

	func applicationWillTerminate(_: Notification) {
		saveWindowState()
		if let monitor = keyEventMonitor {
			NSEvent.removeMonitor(monitor)
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
		false
	}

	func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		if !flag {
			newDocument(nil)
		}
		return true
	}

	// MARK: - Bundles

	private func loadBundles() {
		bundleSystem.loadBundles()
		if let mainMenu = NSApp.mainMenu {
			bundleSystem.installBundlesMenu(in: mainMenu)
		}
	}

	// MARK: - Bundle Item Execution (Responder Chain)

	@objc func performBundleItem(sender: Any?) {
		guard let menuItem = sender as? NSMenuItem,
		      let uuid = menuItem.representedObject as? String
		else {
			return
		}
		bundleSystem.executeItem(uuid: uuid)
	}

	// MARK: - Theme

	private func loadDefaultTheme() {
		guard let url = Bundle.module.url(
			forResource: "Mac Classic",
			withExtension: "tmTheme",
		) else {
			return
		}
		do {
			currentTheme = try ThemeLoader.load(from: url)
		} catch {
			NSLog("Failed to load default theme: \(error)")
		}
	}

	private func applyTheme(to controller: DocumentWindowController) {
		if let theme = currentTheme {
			controller.applyTheme(theme)
		}
	}

	// MARK: - Key Bindings

	private func loadKeyBindings() {
		if let url = Bundle.module.url(
			forResource: "KeyBindings",
			withExtension: "dict",
		) {
			keyBindings = KeyBindingsLoader.load(from: url)
		}

		guard !keyBindings.isEmpty else { return }

		let bindings = keyBindings
		keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
			let parsed = KeyBindingsLoader.parseEvent(event)
			if let binding = bindings.first(where: { $0.keyString == parsed }) {
				let selector = NSSelectorFromString(binding.action)
				if let responder = NSApp.keyWindow?.firstResponder,
				   responder.responds(to: selector)
				{
					responder.perform(selector, with: nil)
					return nil // event consumed
				}
			}
			return event // not consumed
		}
	}

	// MARK: - File Actions

	@objc func newDocument(_: Any?) {
		let controller = DocumentWindowController()
		applyTheme(to: controller)
		windowControllers.append(controller)
		controller.showWindow(nil)
	}

	@objc func newDocumentInTab(_: Any?) {
		// Placeholder — will add to current window's tab group in Iteration 2.
		newDocument(nil)
	}

	@objc func openDocument(_: Any?) {
		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = true
		panel.begin { [weak self] response in
			guard response == .OK else { return }
			for url in panel.urls {
				self?.openURL(url)
			}
		}
	}

	@objc func goToFile(_: Any?) {
		// Placeholder — Open Quickly panel (Iteration 3).
	}

	@objc func saveDocument(_: Any?) {
		guard let controller = currentWindowController() else { return }
		controller.saveDocument()
	}

	@objc func saveDocumentAs(_: Any?) {
		guard let controller = currentWindowController() else { return }
		controller.saveDocumentAs()
	}

	@objc func saveAllDocuments(_: Any?) {
		for controller in windowControllers {
			if controller.textDocument.path != nil {
				controller.saveDocument()
			}
		}
	}

	@objc func performCloseWindow(_: Any?) {
		NSApp.keyWindow?.close()
	}

	// MARK: - About & Preferences

	@objc func showAboutPanel(_: Any?) {
		AboutPanelController.shared.showAboutPanel()
	}

	@objc func showPreferences(_: Any?) {
		AppPreferencesWindowController.shared.showPreferences()
	}

	// MARK: - Window State Restoration

	private static let restorationKey = "TMOpenDocumentURLs"

	private func saveWindowState() {
		let urls = windowControllers.compactMap { ctrl -> String? in
			guard let path = ctrl.textDocument.path else { return nil }
			return URL(fileURLWithPath: path).absoluteString
		}
		UserDefaults.standard.set(urls, forKey: Self.restorationKey)
	}

	/// Restore previously open document windows. Calls `newDocument` if
	/// no state is saved, and returns non-nil to indicate restoration occurred.
	@discardableResult
	private func restoreWindowState() -> Void? {
		guard let urls = UserDefaults.standard.stringArray(forKey: Self.restorationKey),
		      !urls.isEmpty
		else {
			return nil
		}

		var restoredAny = false
		for string in urls {
			if let url = URL(string: string),
			   FileManager.default.fileExists(atPath: url.path)
			{
				openURL(url)
				restoredAny = true
			}
		}
		return restoredAny ? () : nil
	}

	// MARK: - Helpers

	private func openURL(_ url: URL) {
		var isDir: ObjCBool = false
		FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

		let controller = DocumentWindowController()
		applyTheme(to: controller)

		if isDir.boolValue {
			controller.setProjectRoot(url)
		} else {
			controller.openFile(at: url)
		}
		windowControllers.append(controller)
		controller.showWindow(nil)
	}

	private func currentWindowController() -> DocumentWindowController? {
		guard let window = NSApp.keyWindow else { return nil }
		return windowControllers.first { $0.window === window }
	}
}
