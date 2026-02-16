import Testing
@testable import TMPreferences

@Suite("PreferencesKeys")
struct PreferencesKeysTests {
	// MARK: - Key String Values

	@Test("File-related keys have expected values")
	func fileKeys() {
		#expect(PreferencesKeys.disableSessionRestore == "disableSessionRestore")
		#expect(PreferencesKeys.disableNewDocumentAtStartup == "disableNewDocumentAtStartup")
		#expect(PreferencesKeys.disableNewDocumentAtReactivation == "disableNewDocumentAtReactivation")
	}

	@Test("Project-related keys have expected values")
	func projectKeys() {
		#expect(PreferencesKeys.foldersOnTop == "foldersOnTop")
		#expect(PreferencesKeys.showFileExtensions == "showFileExtensions")
		#expect(PreferencesKeys.fileBrowserPlacement == "fileBrowserPlacement")
		#expect(PreferencesKeys.htmlOutputPlacement == "htmlOutputPlacement")
	}

	@Test("Terminal-related keys have expected values")
	func terminalKeys() {
		#expect(PreferencesKeys.mateInstallPath == "mateInstallPath")
		#expect(PreferencesKeys.disableRMateServer == "rmateServerDisabled")
		#expect(PreferencesKeys.rmateServerListen == "rmateServerListen")
		#expect(PreferencesKeys.rmateServerPort == "rmateServerPort")
	}

	@Test("Software update keys have expected values")
	func softwareUpdateKeys() {
		#expect(PreferencesKeys.softwareUpdateChannel == "SoftwareUpdateChannel")
		#expect(PreferencesKeys.askBeforeUpdating == "SoftwareUpdateAskBeforeUpdating")
		#expect(PreferencesKeys.lastSoftwareUpdateCheck == "SoftwareUpdateLastPoll")
	}

	// MARK: - RMateListenMode Enum

	@Test("RMateListenMode raw values")
	func rmateListenModeRawValues() {
		#expect(PreferencesKeys.RMateListenMode.localhost.rawValue == "localhost")
		#expect(PreferencesKeys.RMateListenMode.remote.rawValue == "remote")
	}

	@Test("RMateListenMode can be initialized from raw value")
	func rmateListenModeInit() {
		#expect(PreferencesKeys.RMateListenMode(rawValue: "localhost") == .localhost)
		#expect(PreferencesKeys.RMateListenMode(rawValue: "remote") == .remote)
		#expect(PreferencesKeys.RMateListenMode(rawValue: "invalid") == nil)
	}

	// MARK: - UpdateChannel Enum

	@Test("UpdateChannel raw values")
	func updateChannelRawValues() {
		#expect(PreferencesKeys.UpdateChannel.release.rawValue == "release")
		#expect(PreferencesKeys.UpdateChannel.prerelease.rawValue == "prerelease")
	}

	@Test("UpdateChannel can be initialized from raw value")
	func updateChannelInit() {
		#expect(PreferencesKeys.UpdateChannel(rawValue: "release") == .release)
		#expect(PreferencesKeys.UpdateChannel(rawValue: "prerelease") == .prerelease)
		#expect(PreferencesKeys.UpdateChannel(rawValue: "beta") == nil)
	}

	// MARK: - Default Environment Variables

	@Test("defaultEnvironmentVariables contains expected entries")
	func defaultEnvironmentVariables() {
		let vars = PreferencesKeys.defaultEnvironmentVariables
		#expect(vars.count == 9)

		// All should be disabled by default
		for v in vars {
			#expect(v.enabled == false, "Variable \(v.name) should be disabled by default")
		}

		// Check expected variable names
		let names = vars.map(\.name)
		#expect(names.contains("PATH"))
		#expect(names.contains("TM_FULLNAME"))
		#expect(names.contains("TM_ORGANIZATION"))
	}

	@Test("defaultEnvironmentVariables have non-empty names")
	func defaultVariableNamesNonEmpty() {
		for v in PreferencesKeys.defaultEnvironmentVariables {
			#expect(!v.name.isEmpty, "Variable name should not be empty")
		}
	}
}
