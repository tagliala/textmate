#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import TMApp
@testable import TMPreferences

@Suite("Preferences pane callback wiring")
@MainActor
struct PreferencesWiringTests {
	@Test("All preference panes have expected count")
	func paneCount() {
		let controller = PreferencesWindowController.shared
		#expect(controller.panes.count == 6)
	}

	@Test("Panes include all expected types")
	func paneTypes() {
		let panes = PreferencesWindowController.shared.panes
		#expect(panes.contains(where: { $0 is TerminalPreferencesPane }))
		#expect(panes.contains(where: { $0 is SoftwareUpdatePreferencesPane }))
		#expect(panes.contains(where: { $0 is BundlesPreferencesPane }))
		#expect(panes.contains(where: { $0 is VariablesPreferencesPane }))
		#expect(panes.contains(where: { $0 is FilesPreferencesPane }))
		#expect(panes.contains(where: { $0 is ProjectsPreferencesPane }))
	}

	@Test("showPreferences wires terminal callback")
	func terminalCallbackWired() {
		let appController = AppPreferencesWindowController.shared
		// Trigger wiring (showPreferences wires on first call)
		appController.showPreferences()

		let terminal = PreferencesWindowController.shared.panes
			.compactMap { $0 as? TerminalPreferencesPane }.first
		#expect(terminal?.onMateInstall != nil)
	}

	@Test("showPreferences wires software update callback")
	func softwareUpdateCallbackWired() {
		let appController = AppPreferencesWindowController.shared
		appController.showPreferences()

		let pane = PreferencesWindowController.shared.panes
			.compactMap { $0 as? SoftwareUpdatePreferencesPane }.first
		#expect(pane?.onCheckNow != nil)
	}

	@Test("showPreferences wires bundles callbacks")
	func bundlesCallbacksWired() {
		let appController = AppPreferencesWindowController.shared
		appController.showPreferences()

		let pane = PreferencesWindowController.shared.panes
			.compactMap { $0 as? BundlesPreferencesPane }.first
		#expect(pane?.onInstallAction != nil)
		#expect(pane?.onBundleLinkClick != nil)
	}

	@Test("showPreferences wires variables callback")
	func variablesCallbackWired() {
		let appController = AppPreferencesWindowController.shared
		appController.showPreferences()

		let pane = PreferencesWindowController.shared.panes
			.compactMap { $0 as? VariablesPreferencesPane }.first
		#expect(pane?.onVariablesChanged != nil)
	}

	@Test("showPreferences wires files callback")
	func filesCallbackWired() {
		let appController = AppPreferencesWindowController.shared
		appController.showPreferences()

		let pane = PreferencesWindowController.shared.panes
			.compactMap { $0 as? FilesPreferencesPane }.first
		#expect(pane?.onPreferenceChanged != nil)
	}

	@Test("showPreferences wires projects callback")
	func projectsCallbackWired() {
		let appController = AppPreferencesWindowController.shared
		appController.showPreferences()

		let pane = PreferencesWindowController.shared.panes
			.compactMap { $0 as? ProjectsPreferencesPane }.first
		#expect(pane?.onPreferenceChanged != nil)
	}

	@Test("Variables callback posts environment notification")
	func variablesNotification() throws {
		let appController = AppPreferencesWindowController.shared
		appController.showPreferences()

		let pane = try #require(PreferencesWindowController.shared.panes
			.compactMap { $0 as? VariablesPreferencesPane }.first)

		nonisolated(unsafe) var received = false
		let token = NotificationCenter.default.addObserver(
			forName: .preferencesEnvironmentVariablesDidChange,
			object: nil,
			queue: .main,
		) { _ in
			received = true
		}
		defer { NotificationCenter.default.removeObserver(token) }

		pane.onVariablesChanged?([])

		// Allow notification delivery
		RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
		#expect(received)
	}

	@Test("Files callback posts preferences notification")
	func filesNotification() throws {
		let appController = AppPreferencesWindowController.shared
		appController.showPreferences()

		let pane = try #require(PreferencesWindowController.shared.panes
			.compactMap { $0 as? FilesPreferencesPane }.first)

		nonisolated(unsafe) var receivedKey: String?
		let token = NotificationCenter.default.addObserver(
			forName: .preferencesDidChange,
			object: nil,
			queue: .main,
		) { note in
			receivedKey = note.userInfo?["key"] as? String
		}
		defer { NotificationCenter.default.removeObserver(token) }

		pane.onPreferenceChanged?("encoding", "UTF-16")

		RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
		#expect(receivedKey == "encoding")
	}
}
#endif
