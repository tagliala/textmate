#if canImport(AppKit)
import AppKit

/// Protocol for preference pane view controllers.
@MainActor
public protocol PreferencesPaneProtocol: AnyObject {
	/// The toolbar item image for this pane. Nil uses the default system icon.
	var toolbarItemImage: NSImage? { get }
	/// The toolbar item label for this pane.
	var toolbarItemLabel: String { get }
	/// Unique identifier for saving selection state.
	var paneIdentifier: String { get }
}

/// Base class for preference panes that proxy KVC bindings to UserDefaults and settings strings.
///
/// Port of TextMate's `PreferencesPane` base class. Subclasses declare `defaultsProperties`
/// (view key → UserDefaults key) and `tmProperties` (view key → settings key), then use
/// standard Cocoa bindings on `self` with those keys.
@MainActor
open class PreferencesPane: NSViewController, PreferencesPaneProtocol {
	/// Maps view model keys to UserDefaults keys.
	/// Subclasses populate this in `init` or `loadView`.
	open nonisolated var defaultsProperties: [String: String] {
		[:]
	}

	/// Maps view model keys to settings keys.
	/// Subclasses populate this in `init` or `loadView`.
	open nonisolated var tmProperties: [String: String] {
		[:]
	}

	open var toolbarItemImage: NSImage? {
		nil
	}

	open var toolbarItemLabel: String {
		title ?? "Untitled"
	}

	open var paneIdentifier: String {
		String(describing: type(of: self))
	}

	// MARK: - KVC Proxy

	override open func value(forUndefinedKey key: String) -> Any? {
		if let defaultsKey = defaultsProperties[key] {
			return UserDefaults.standard.object(forKey: defaultsKey)
		}
		if let settingsKey = tmProperties[key] {
			return PreferencesSettingsBridge.shared.getValue(for: settingsKey)
		}
		return super.value(forUndefinedKey: key)
	}

	override open func setValue(_ value: Any?, forUndefinedKey key: String) {
		if let defaultsKey = defaultsProperties[key] {
			if let value {
				UserDefaults.standard.set(value, forKey: defaultsKey)
			} else {
				UserDefaults.standard.removeObject(forKey: defaultsKey)
			}
			return
		}
		if let settingsKey = tmProperties[key] {
			PreferencesSettingsBridge.shared.setValue(value, for: settingsKey)
			return
		}
		super.setValue(value, forUndefinedKey: key)
	}
}

/// Bridge to the settings system for preference panes that read/write `.tm_properties`-style keys.
///
/// This allows preference panes to read/write settings values without directly depending
/// on the TMSettings package. A concrete implementation should be provided at app launch.
public final class PreferencesSettingsBridge: @unchecked Sendable {
	public static let shared = PreferencesSettingsBridge()

	private var _getValue: @Sendable (String) -> Any? = { _ in nil }
	private var _setValue: @Sendable (Any?, String) -> Void = { _, _ in }

	/// Configure the bridge with actual settings accessors.
	public func configure(
		getValue: @escaping @Sendable (String) -> Any?,
		setValue: @escaping @Sendable (Any?, String) -> Void,
	) {
		_getValue = getValue
		_setValue = setValue
	}

	/// Read a settings value by key.
	public func getValue(for key: String) -> Any? {
		_getValue(key)
	}

	/// Write a settings value by key.
	public func setValue(_ value: Any?, for key: String) {
		_setValue(value, key)
	}
}
#endif
