import AppKit
import TMPreferences

/// Thin wrapper that delegates to `TMPreferences.PreferencesWindowController`.
///
/// The full preferences implementation lives in the TMPreferences package.
/// This shim exists so that the TMApp target can open the preferences
/// window without exposing TMPreferences internals.
@MainActor
final class AppPreferencesWindowController {
	static let shared = AppPreferencesWindowController()
	private let controller = TMPreferences.PreferencesWindowController.shared

	func showPreferences() {
		controller.showWindow(nil)
	}
}
