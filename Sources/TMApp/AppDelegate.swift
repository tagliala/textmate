import AppKit
import TMDocumentWindow
import TMTheme

/// The main application delegate. Sets up the menu bar, creates the initial
/// document window, and loads the default theme.
///
/// Matches TextMate's initial launch behaviour: one untitled document window
/// with the default theme applied.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
	private var windowControllers: [DocumentWindowController] = []

	// MARK: - Application Lifecycle

	func applicationDidFinishLaunching(_: Notification) {
		NSApp.mainMenu = MainMenuBuilder.buildMainMenu()
		newDocument(nil)
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

	// MARK: - File Actions

	@objc func newDocument(_: Any?) {
		let controller = DocumentWindowController()
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

	@objc func saveAllDocuments(_: Any?) {
		// Placeholder — iterate open documents and save each.
	}

	@objc func performCloseWindow(_: Any?) {
		NSApp.keyWindow?.close()
	}

	// MARK: - Preferences

	@objc func showPreferences(_: Any?) {
		// Placeholder — Preferences window (Iteration 3).
	}

	// MARK: - Helpers

	private func openURL(_ url: URL) {
		var isDir: ObjCBool = false
		FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

		let controller = DocumentWindowController()
		if isDir.boolValue {
			controller.setProjectRoot(url)
		} else {
			if let text = try? String(contentsOf: url, encoding: .utf8) {
				controller.textView.string = text
				controller.window?.title = url.lastPathComponent
			}
		}
		windowControllers.append(controller)
		controller.showWindow(nil)
	}
}
