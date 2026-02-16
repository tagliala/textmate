import AppKit
import Testing
@testable import TMPreferences

@Suite("PreferencesPane — Property Maps")
struct PreferencesPanePropertyTests {
	@Test("FilesPreferencesPane has correct defaults properties")
	@MainActor func filesDefaults() {
		let pane = FilesPreferencesPane()
		let defaults = pane.defaultsProperties
		#expect(defaults.count == 3)
		#expect(defaults["disableSessionRestore"] == PreferencesKeys.disableSessionRestore)
		#expect(defaults["disableDocumentAtStartup"] == PreferencesKeys.disableNewDocumentAtStartup)
		#expect(defaults["disableDocumentAtReactivation"] == PreferencesKeys.disableNewDocumentAtReactivation)
	}

	@Test("FilesPreferencesPane has correct tm properties")
	@MainActor func filesTmProperties() {
		let pane = FilesPreferencesPane()
		let tm = pane.tmProperties
		#expect(tm.count == 2)
		#expect(tm.keys.contains("encoding"))
		#expect(tm.keys.contains("lineEndings"))
	}

	@Test("FilesPreferencesPane has correct identifiers")
	@MainActor func filesIdentifiers() {
		let pane = FilesPreferencesPane()
		#expect(pane.paneIdentifier == "Files")
		#expect(pane.toolbarItemLabel == "Files")
		#expect(pane.toolbarItemImage != nil)
	}

	@Test("ProjectsPreferencesPane has correct defaults properties")
	@MainActor func projectsDefaults() {
		let pane = ProjectsPreferencesPane()
		let defaults = pane.defaultsProperties
		#expect(defaults.count == 11)
		#expect(defaults.keys.contains("foldersOnTop"))
		#expect(defaults.keys.contains("showFileExtensions"))
		#expect(defaults.keys.contains("fileBrowserPlacement"))
	}

	@Test("ProjectsPreferencesPane has correct tm properties")
	@MainActor func projectsTmProperties() {
		let pane = ProjectsPreferencesPane()
		let tm = pane.tmProperties
		#expect(tm.count == 3)
		#expect(tm.keys.contains("excludePattern"))
		#expect(tm.keys.contains("includePattern"))
		#expect(tm.keys.contains("binaryPattern"))
	}

	@Test("ProjectsPreferencesPane has correct identifiers")
	@MainActor func projectsIdentifiers() {
		let pane = ProjectsPreferencesPane()
		#expect(pane.paneIdentifier == "Projects")
		#expect(pane.toolbarItemLabel == "Projects")
	}

	@Test("SoftwareUpdatePreferencesPane has correct identifiers")
	@MainActor func softwareUpdateIdentifiers() {
		let pane = SoftwareUpdatePreferencesPane()
		#expect(pane.paneIdentifier == "SoftwareUpdate")
		#expect(pane.toolbarItemLabel == "Software Update")
	}

	@Test("TerminalPreferencesPane has correct defaults properties")
	@MainActor func terminalDefaults() {
		let pane = TerminalPreferencesPane()
		let defaults = pane.defaultsProperties
		#expect(defaults.count == 4)
		#expect(defaults.keys.contains("mateInstallPath") || defaults.values.contains(PreferencesKeys.mateInstallPath))
	}

	@Test("TerminalPreferencesPane has correct identifiers")
	@MainActor func terminalIdentifiers() {
		let pane = TerminalPreferencesPane()
		#expect(pane.paneIdentifier == "Terminal")
		#expect(pane.toolbarItemLabel == "Terminal")
	}

	@Test("BundlesPreferencesPane has correct identifiers")
	@MainActor func bundlesIdentifiers() {
		let pane = BundlesPreferencesPane()
		#expect(pane.paneIdentifier == "Bundles")
		#expect(pane.toolbarItemLabel == "Bundles")
	}

	@Test("VariablesPreferencesPane has correct identifiers")
	@MainActor func variablesIdentifiers() {
		let pane = VariablesPreferencesPane()
		#expect(pane.paneIdentifier == "Variables")
		#expect(pane.toolbarItemLabel == "Variables")
	}

	// MARK: - All Pane Identifiers are Unique

	@Test("all pane identifiers are unique")
	@MainActor func uniqueIdentifiers() {
		let panes: [PreferencesPaneProtocol] = [
			FilesPreferencesPane(),
			ProjectsPreferencesPane(),
			BundlesPreferencesPane(),
			VariablesPreferencesPane(),
			SoftwareUpdatePreferencesPane(),
			TerminalPreferencesPane(),
		]
		let ids = panes.map(\.paneIdentifier)
		#expect(Set(ids).count == ids.count, "Pane identifiers must be unique")
	}
}
