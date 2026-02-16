import Foundation

/// All UserDefaults keys used by TextMate preferences.
///
/// Port of `Frameworks/Preferences/src/Keys.h` / `Keys.mm`.
public enum PreferencesKeys {
	// MARK: - Files

	public static let disableSessionRestore = "disableSessionRestore"
	public static let disableNewDocumentAtStartup = "disableNewDocumentAtStartup"
	public static let disableNewDocumentAtReactivation = "disableNewDocumentAtReactivation"
	public static let showFavoritesInsteadOfUntitled = "showFavoritesInsteadOfUntitled"

	// MARK: - Projects

	public static let foldersOnTop = "foldersOnTop"
	public static let showFileExtensions = "showFileExtensions"
	public static let initialFileBrowserURL = "initialFileBrowserURL"
	public static let fileBrowserPlacement = "fileBrowserPlacement"
	public static let fileBrowserSingleClickToOpen = "fileBrowserSingleClickToOpen"
	public static let fileBrowserOpenAnimationDisabled = "fileBrowserOpenAnimationDisabled"
	public static let fileBrowserStyle = "fileBrowserStyle"
	public static let htmlOutputPlacement = "htmlOutputPlacement"
	public static let disableFileBrowserWindowResize = "disableFileBrowserWindowResize"
	public static let autoRevealFile = "autoRevealFile"
	public static let allowExpandingLinks = "allowExpandingLinks"
	public static let allowExpandingPackages = "allowExpandingPackages"
	public static let disableTabReordering = "disableTabReordering"
	public static let disableTabAutoClose = "disableTabAutoClose"
	public static let disableTabBarCollapsing = "disableTabBarCollapsing"

	// MARK: - Variables

	public static let environmentVariables = "environmentVariables"

	// MARK: - Terminal

	public static let mateInstallPath = "mateInstallPath"
	public static let mateInstallVersion = "mateInstallVersion"
	public static let disableRMateServer = "rmateServerDisabled"
	public static let rmateServerListen = "rmateServerListen"
	public static let rmateServerPort = "rmateServerPort"

	/// Possible values for `rmateServerListen`.
	public enum RMateListenMode: String, Sendable {
		case localhost
		case remote
	}

	// MARK: - Software Update

	public static let disableSoftwareUpdate = "SoftwareUpdateDisablePolling"
	public static let softwareUpdateChannel = "SoftwareUpdateChannel"
	public static let askBeforeUpdating = "SoftwareUpdateAskBeforeUpdating"
	public static let lastSoftwareUpdateCheck = "SoftwareUpdateLastPoll"

	/// Possible values for `softwareUpdateChannel`.
	public enum UpdateChannel: String, Sendable {
		case release
		case prerelease
	}

	// MARK: - Bundles

	public static let disableBundleUpdates = "disableBundleUpdates"
	public static let lastBundleUpdateCheck = "lastBundleUpdateCheck"

	// MARK: - Appearance & Misc

	public static let disableAntiAlias = "disableAntiAlias"
	public static let lineNumbers = "lineNumbers"
	public static let folderSearchFollowLinks = "folderSearchFollowLinks"

	// MARK: - Crash Reporting

	public static let disableCrashReporting = "DisableCrashReports"
	public static let crashReportsContactInfo = "CrashReportsContactInfo"

	// MARK: - Registration

	public static let licenseOwner = "licenseOwnerName"

	// MARK: - Preferences Window State

	public static let preferencesFrameTopLeft = "MASPreferences Frame Top Left"
	public static let preferencesSelectedView = "MASPreferences Selected Identifier View"

	// MARK: - Default Environment Variables

	/// Default environment variables provided by TextMate preferences.
	///
	/// Each entry is `(enabled, name, value)`. All default to disabled.
	public static let defaultEnvironmentVariables: [(enabled: Bool, name: String, value: String)] = [
		(false, "PATH", "$PATH:/opt/local/bin:/usr/local/bin:/usr/texbin"),
		(false, "TM_C_POINTER", "* "),
		(false, "TM_CXX_FLAGS", "-framework Carbon -liconv -include vector -include string -include map -include cstdio"),
		(false, "TM_FULLNAME", "Scrooge McDuck"),
		(false, "TM_ORGANIZATION", "The Billionaires Club"),
		(false, "TM_XHTML", " /"),
		(false, "TM_GIT", "/opt/local/bin/git"),
		(false, "TM_HG", "/opt/local/bin/hg"),
		(false, "TM_MAKE_FLAGS", "rj8"),
	]
}
