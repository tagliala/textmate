import AppKit
import os
import TMBundleRuntime
import TMBundleUI
import TMCompatibility
import TMDocumentManager
import TMDocumentWindow
import TMFilterList
import TMPreferences
import TMServices
import TMTheme

/// The main application delegate. Sets up the menu bar, loads the default
/// theme, installs key bindings, creates the initial document window, and
/// manages window state restoration.
///
/// Matches TextMate's initial launch behaviour: one untitled document window
/// with the default theme applied.
@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency BundleMenuActionTarget {
	private static let logger = Logger(subsystem: "com.macromates.TextMate", category: "AppDelegate")

	/// Application entry point.
	///
	/// Bootstraps `NSApplication` with our `AppDelegate`. This is functionally
	/// equivalent to the traditional `NSApplicationMain` call.
	///
	/// `setActivationPolicy(.regular)` is required for SPM-built executables
	/// so that the app appears in the Dock, owns a menu bar, and receives
	/// focus like a normal macOS GUI application.
	static func main() {
		let app = NSApplication.shared
		app.setActivationPolicy(.regular)
		let delegate = AppDelegate()
		app.delegate = delegate
		app.activate()
		app.run()
	}

	private var windowControllers: [DocumentWindowController] = []

	/// The currently loaded theme, applied to every new window.
	private var currentTheme: Theme?

	/// UUID of the selected theme, persisted in UserDefaults.
	private static let themeUUIDKey = "selectedThemeUUID"

	/// Custom key bindings loaded from `KeyBindings.dict`.
	private var keyBindings: [KeyBindingsLoader.KeyBinding] = []

	/// Event monitor for custom key bindings.
	private var keyEventMonitor: Any?

	/// Remote editing server for `rmate` connections.
	private var rmateServer: RMateServer?

	/// The bundle system: loader, index, menu builder, command dispatch.
	private let bundleSystem = BundleSystemController()

	/// Auto-backup manager for crash recovery.
	private var backupManager: DocumentBackupManager {
		DocumentBackupManager.shared
	}

	// MARK: - Application Lifecycle

	func applicationDidFinishLaunching(_: Notification) {
		NSApp.mainMenu = MainMenuBuilder.buildMainMenu()
		loadDefaultTheme()
		loadKeyBindings()
		loadBundles()
		startRMateServer()
		setupRecentDocumentsMenu()
		observeDocumentRegistry()
		recoverBackupsIfNeeded()
		AppPreferencesWindowController.shared.configure(bundleInstaller: bundleSystem.bundleInstaller)
		restoreWindowState() ?? newDocument(nil)
		backupManager.start()
	}

	func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
		DocumentWindowController.applicationShouldTerminate()
	}

	func applicationWillTerminate(_: Notification) {
		rmateServer?.stop()
		backupManager.stop()
		backupManager.backupAllModifiedDocuments()
		saveWindowState()
		if let monitor = keyEventMonitor {
			NSEvent.removeMonitor(monitor)
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
		false
	}

	// MARK: - Crash Recovery

	/// Check for backed-up documents from a previous crash and offer recovery.
	private func recoverBackupsIfNeeded() {
		guard backupManager.hasRecoverableDocuments else { return }

		let records = backupManager.recoverableDocuments
		let alert = NSAlert()
		alert.messageText = String(
			localized: "Recover unsaved documents?",
			comment: "Crash recovery dialog",
		)
		alert.informativeText = String(
			localized: "\(records.count) unsaved document(s) from a previous session were found.",
			comment: "Crash recovery dialog",
		)
		alert.addButton(withTitle: String(localized: "Recover", comment: "Crash recovery button"))
		alert.addButton(withTitle: String(localized: "Discard", comment: "Crash recovery button"))

		let response = alert.runModal()
		if response == .alertFirstButtonReturn {
			if let recovered = try? backupManager.recoverAll() {
				for doc in recovered {
					let controller = DocumentWindowController(document: doc)
					controller.bundleIndex = bundleSystem.bundleIndex
					controller.commandDispatcher = bundleSystem.commandDispatcher
					applyTheme(to: controller)
					windowControllers.append(controller)
					controller.showWindow(nil)
				}
			}
		} else {
			try? backupManager.discardAll()
		}
	}

	func applicationDidBecomeActive(_: Notification) {
		for controller in DocumentWindowController.allControllers.values {
			controller.checkForExternalChanges()
		}
	}

	func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		if !flag {
			newDocument(nil)
		}
		return true
	}

	func application(_: NSApplication, open urls: [URL]) {
		for url in urls {
			if url.scheme == "txmt" {
				handleTxmtURL(url)
			} else {
				openURL(url)
			}
		}
	}

	// MARK: - Bundles

	private func loadBundles() {
		// Install the menu delegate immediately so it's ready when menus populate.
		if let mainMenu = NSApp.mainMenu {
			bundleSystem.installBundlesMenu(in: mainMenu)
		}

		// Load bundles on a background thread to avoid blocking the UI.
		Task { @MainActor in
			await bundleSystem.loadBundlesAsync()
			populateThemeMenu()
			restorePersistedTheme()
		}
	}

	// MARK: - Bundle Item Execution (Responder Chain)

	@objc func performBundleItem(sender: Any?) {
		guard let menuItem = sender as? NSMenuItem,
		      let uuid = menuItem.representedObject as? String
		else {
			return
		}

		// Wire the active document window as the command dispatcher's delegate
		// so commands can read/write editor content and build TM_* environment.
		if let controller = currentWindowController() {
			bundleSystem.commandDispatcher.delegate = controller
		}

		Task { @MainActor in
			await bundleSystem.commandDispatcher.execute(itemUUID: uuid)
		}
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
			Self.logger.error("Failed to load default theme: \(error)")
		}
	}

	private func applyTheme(to controller: DocumentWindowController) {
		if let theme = currentTheme {
			controller.applyTheme(theme)
		}
	}

	/// Apply the current theme to all open windows.
	private func applyThemeToAllWindows() {
		for controller in DocumentWindowController.allControllers.values {
			applyTheme(to: controller)
		}
	}

	/// Populate the View > Theme submenu from bundle index.
	private func populateThemeMenu() {
		guard let mainMenu = NSApp.mainMenu,
		      let viewMenu = mainMenu.item(withTitle: "View")?.submenu,
		      let themeItem = viewMenu.item(withTitle: "Theme"),
		      let themeMenu = themeItem.submenu
		else { return }

		themeMenu.removeAllItems()

		let themeItems = bundleSystem.bundleIndex
			.query(BundleQuery(kinds: .theme))
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		for item in themeItems {
			let menuItem = NSMenuItem(
				title: item.name,
				action: #selector(selectTheme(_:)),
				keyEquivalent: "",
			)
			menuItem.target = self
			menuItem.representedObject = item.uuid
			themeMenu.addItem(menuItem)
		}
	}

	/// Handle theme selection from the View > Theme menu.
	@objc func selectTheme(_ sender: NSMenuItem) {
		guard let uuid = sender.representedObject as? String else { return }
		loadAndApplyTheme(uuid: uuid)
	}

	/// Load a theme by UUID from the bundle index and apply to all windows.
	private func loadAndApplyTheme(uuid: String) {
		guard let item = bundleSystem.bundleIndex.lookup(uuid: uuid),
		      let path = item.paths.first
		else { return }

		do {
			let theme = try ThemeLoader.load(from: URL(fileURLWithPath: path))
			currentTheme = theme
			UserDefaults.standard.set(uuid, forKey: Self.themeUUIDKey)
			applyThemeToAllWindows()
		} catch {
			Self.logger.error("Failed to load theme \(uuid): \(error)")
		}
	}

	/// Try to restore the persisted theme selection from UserDefaults.
	private func restorePersistedTheme() {
		guard let uuid = UserDefaults.standard.string(forKey: Self.themeUUIDKey) else { return }
		loadAndApplyTheme(uuid: uuid)
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
		controller.bundleIndex = bundleSystem.bundleIndex
		controller.commandDispatcher = bundleSystem.commandDispatcher
		applyTheme(to: controller)
		windowControllers.append(controller)
		controller.showWindow(nil)
	}

	@objc func newDocumentInTab(_: Any?) {
		if let controller = currentWindowController() {
			controller.newDocumentInTab(nil)
		} else {
			newDocument(nil)
		}
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
		guard let controller = currentWindowController(),
		      let frame = controller.window?.frame
		else {
			return
		}

		let projectPath = controller.projectPath
			?? controller.selectedDocument?.path.map { ($0 as NSString).deletingLastPathComponent }
			?? NSHomeDirectory()

		let chooser = FileChooserController(projectPath: projectPath)
		chooser.setOpenDocuments(controller.documents.compactMap(\.path))
		chooser.setCurrentDocumentPath(controller.selectedDocument?.path)

		chooser.onSelectFile = { [weak self] path, selectionString, symbolString in
			guard let self else { return }
			let url = URL(fileURLWithPath: path)
			// Re-use the current window if it's a project window,
			// otherwise open a new one.
			let target: DocumentWindowController
			if controller.treatAsProjectWindow {
				controller.openFile(at: url)
				RecentDocumentsManager.shared.noteDocumentOpened(path: url.path)
				target = controller
			} else {
				openURL(url)
				target = windowControllers.last ?? controller
			}
			if let sel = selectionString {
				target.navigateToSelectionString(sel)
			}
			_ = symbolString
		}

		chooser.showAndEnumerate(relativeTo: frame)
	}

	@objc func showBundleItemChooser(_: Any?) {
		guard let frame = currentWindowController()?.window?.frame ?? NSApp.keyWindow?.frame else {
			return
		}

		let chooser = BundleItemChooserController()

		// Build descriptors from the bundle index.
		let allItems = bundleSystem.bundleIndex.query(BundleQuery(kinds: .all))
		let descriptors = allItems.map { item in
			BundleItemDescriptor(
				name: item.name,
				bundleName: bundleSystem.bundleIndex.bundle(uuid: item.bundleUUID)?.name ?? "",
				identifier: item.uuid,
				tabTrigger: item.tabTrigger,
				keyEquivalent: item.keyEquivalent,
				kind: kindString(item.kind),
				source: searchSource(for: item.kind),
			)
		}
		chooser.populate(with: descriptors)

		chooser.onSelectItem = { [weak self] uuid in
			guard let self else { return }
			if let controller = currentWindowController() {
				bundleSystem.commandDispatcher.delegate = controller
			}
			Task { @MainActor in
				await self.bundleSystem.commandDispatcher.execute(itemUUID: uuid)
			}
		}

		chooser.showWindow(relativeTo: frame)
	}

	private func kindString(_ kind: BundleItemKind) -> String {
		if kind.contains(.command) { return "Command" }
		if kind.contains(.snippet) { return "Snippet" }
		if kind.contains(.grammar) { return "Grammar" }
		if kind.contains(.theme) { return "Theme" }
		if kind.contains(.macro) { return "Macro" }
		if kind.contains(.settings) { return "Settings" }
		if kind.contains(.dragCommand) { return "Drag Command" }
		return "Item"
	}

	private func searchSource(for kind: BundleItemKind) -> BundleSearchSource {
		if kind.contains(.grammar) { return .grammarItems }
		if kind.contains(.theme) { return .themeItems }
		if kind.contains(.settings) { return .settingsItems }
		if kind.contains(.dragCommand) { return .dragCommandItems }
		return .actionItems
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

	// MARK: - Bundle Manager

	private var bundleManagerController: BundleManagerController?

	@objc func showBundleManager(_: Any?) {
		if bundleManagerController == nil {
			bundleManagerController = BundleManagerController(
				installer: bundleSystem.bundleInstaller,
			)
		}
		bundleManagerController?.showWindow(nil)
		Task { @MainActor in
			await bundleManagerController?.loadCatalog()
		}
	}

	/// Manual "Check for Updates…" action — delegates to SoftwareUpdateEngine.
	@objc func checkForUpdates(_: Any?) {
		Task { @MainActor in
			do {
				let result = try await SoftwareUpdateEngine.shared.checkForUpdate()
				switch result {
				case .upToDate, .prerelease:
					let alert = NSAlert()
					alert.messageText = String(
						localized: "Up to date",
						comment: "Software update dialog",
					)
					alert.informativeText = String(
						localized: "You are running the latest version.",
						comment: "Software update dialog",
					)
					alert.runModal()
				case .updateAvailable:
					break // SoftwareUpdateEngine handles presentation
				}
			} catch {
				let alert = NSAlert(error: error)
				alert.runModal()
			}
		}
	}

	// MARK: - Window State Restoration

	private func saveWindowState() {
		DocumentWindowController.saveSession(includeUntitled: true)
	}

	/// Restore full session (documents, tabs, window frames, file browser
	/// state). Falls back to nil when no session is saved on disk.
	@discardableResult
	private func restoreWindowState() -> Void? {
		guard DocumentWindowController.restoreSession() else { return nil }
		// Populate our tracking array with the restored controllers.
		windowControllers = DocumentWindowController.sortedControllers
		// Apply theme and bundle index to all restored windows.
		for controller in windowControllers {
			controller.bundleIndex = bundleSystem.bundleIndex
			controller.commandDispatcher = bundleSystem.commandDispatcher
			applyTheme(to: controller)
		}
		return ()
	}

	// MARK: - txmt:// URL Scheme

	/// Handle a `txmt://open?url=file:///path&line=N&column=M` URL.
	private func handleTxmtURL(_ url: URL) {
		guard url.host == "open",
		      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else { return }

		let items = components.queryItems ?? []
		guard let fileURLString = items.first(where: { $0.name == "url" })?.value,
		      let fileURL = URL(string: fileURLString),
		      fileURL.isFileURL
		else { return }

		let line = items.first(where: { $0.name == "line" })?.value
		let column = items.first(where: { $0.name == "column" })?.value

		openURL(fileURL)

		if let lineStr = line {
			let sel = column.map { "\(lineStr):\($0)" } ?? lineStr
			windowControllers.last?.navigateToSelectionString(sel)
		}
	}

	// MARK: - RMate Server

	private func startRMateServer() {
		let defaults = UserDefaults.standard
		guard !defaults.bool(forKey: PreferencesKeys.disableRMateServer) else { return }

		let listenMode = defaults.string(forKey: PreferencesKeys.rmateServerListen)
		let port = defaults.integer(forKey: PreferencesKeys.rmateServerPort)
		let effectivePort = port > 0 ? UInt16(port) : RMateServer.defaultPort
		let remote = listenMode == PreferencesKeys.RMateListenMode.remote.rawValue

		let server = RMateServer(port: effectivePort, listenForRemoteClients: remote)
		server.delegate = self
		do {
			try server.start()
			rmateServer = server
		} catch {
			Self.logger.error("Failed to start rmate server: \(error)")
		}
	}

	// MARK: - Recent Documents

	private func setupRecentDocumentsMenu() {
		RecentDocumentsManager.shared.pruneStale()
		RecentDocumentsManager.shared.onChanged = { [weak self] in
			self?.rebuildRecentDocumentsMenu()
		}
		rebuildRecentDocumentsMenu()
	}

	/// Feed documents registered with TMDocumentController into Recent Documents.
	private func observeDocumentRegistry() {
		TMDocumentController.shared.onDocumentAdded = { doc in
			guard let path = doc.path else { return }
			RecentDocumentsManager.shared.noteDocumentOpened(path: path)
		}
	}

	private func rebuildRecentDocumentsMenu() {
		guard let fileMenu = NSApp.mainMenu?.item(at: 1)?.submenu else { return }
		guard let recentItem = fileMenu.items.first(where: {
			$0.submenu?.title == String(localized: "Open Recent", comment: "File menu submenu")
		}) else { return }
		guard let recentMenu = recentItem.submenu else { return }

		recentMenu.removeAllItems()

		for entry in RecentDocumentsManager.shared.entries {
			let item = NSMenuItem(
				title: entry.displayName,
				action: #selector(openRecentDocument(_:)),
				keyEquivalent: "",
			)
			item.representedObject = entry.path
			item.toolTip = entry.path
			recentMenu.addItem(item)
		}

		if !RecentDocumentsManager.shared.entries.isEmpty {
			recentMenu.addItem(.separator())
		}
		recentMenu.addItem(
			NSMenuItem(
				title: String(localized: "Clear Menu", comment: "Open Recent submenu item"),
				action: #selector(clearRecentDocuments(_:)),
				keyEquivalent: "",
			),
		)
	}

	@objc func openRecentDocument(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		let url = URL(fileURLWithPath: path)
		openURL(url)
	}

	@objc func clearRecentDocuments(_: Any?) {
		RecentDocumentsManager.shared.clearAll()
	}

	// MARK: - Helpers

	private func openURL(_ url: URL) {
		var isDir: ObjCBool = false
		FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

		let controller = DocumentWindowController()
		controller.bundleIndex = bundleSystem.bundleIndex
		controller.commandDispatcher = bundleSystem.commandDispatcher
		applyTheme(to: controller)

		if isDir.boolValue {
			controller.setProjectRoot(url)
		} else {
			controller.openFile(at: url)
			RecentDocumentsManager.shared.noteDocumentOpened(path: url.path)
		}
		windowControllers.append(controller)
		controller.showWindow(nil)
	}

	private func currentWindowController() -> DocumentWindowController? {
		guard let window = NSApp.keyWindow else { return nil }
		return windowControllers.first { $0.window === window }
	}
}

// MARK: - RMateServerDelegate

extension AppDelegate: RMateServerDelegate {
	func rmateServer(_: RMateServer, didReceiveOpenRequest request: RMateOpenRequest) {
		guard let path = request.path ?? request.realPath else { return }
		let url = URL(fileURLWithPath: path)
		openURL(url)
		NSApp.activate()
		if let sel = request.selection {
			windowControllers.last?.navigateToSelectionString(sel)
		}
	}
}
