import Foundation

/// A loaded TextMate theme parsed from a `.tmTheme` plist file.
///
/// The theme contains global settings (background, foreground, caret, selection,
/// etc.) and an ordered list of scope-specific style rules.
public struct Theme: Sendable {
	/// The display name of the theme (e.g. "Twilight", "Monokai").
	public let name: String

	/// The semantic class (e.g. "theme.dark.twilight").
	public let semanticClass: String

	/// The UUID of the theme bundle item.
	public let uuid: String

	/// The global (unscoped) settings — background, foreground, caret, etc.
	public let globalSettings: ThemeGlobalSettings

	/// Gutter-specific settings.
	public let gutterSettings: ThemeGutterSettings

	/// Ordered list of scope-specific style rules.
	public let rules: [ThemeStyleRule]

	public init(
		name: String,
		semanticClass: String,
		uuid: String,
		globalSettings: ThemeGlobalSettings,
		gutterSettings: ThemeGutterSettings = ThemeGutterSettings(),
		rules: [ThemeStyleRule] = [],
	) {
		self.name = name
		self.semanticClass = semanticClass
		self.uuid = uuid
		self.globalSettings = globalSettings
		self.gutterSettings = gutterSettings
		self.rules = rules
	}
}

/// Global (unscoped) settings from a `.tmTheme` file.
public struct ThemeGlobalSettings: Sendable {
	public let foreground: ThemeColor
	public let background: ThemeColor
	public let caret: ThemeColor
	public let selection: ThemeColor
	public let invisibles: ThemeColor
	public let lineHighlight: ThemeColor?

	public init(
		foreground: ThemeColor = ThemeColor(red: 0, green: 0, blue: 0),
		background: ThemeColor = ThemeColor(red: 1, green: 1, blue: 1),
		caret: ThemeColor = ThemeColor(red: 0, green: 0, blue: 0),
		selection: ThemeColor = ThemeColor(red: 0.71, green: 0.84, blue: 1),
		invisibles: ThemeColor = ThemeColor(red: 0.85, green: 0.85, blue: 0.85),
		lineHighlight: ThemeColor? = nil,
	) {
		self.foreground = foreground
		self.background = background
		self.caret = caret
		self.selection = selection
		self.invisibles = invisibles
		self.lineHighlight = lineHighlight
	}
}

/// Gutter settings from a `.tmTheme` file.
public struct ThemeGutterSettings: Sendable {
	public let foreground: ThemeColor
	public let background: ThemeColor
	public let divider: ThemeColor
	public let selectionForeground: ThemeColor
	public let selectionBackground: ThemeColor
	public let selectionBorder: ThemeColor

	public init(
		foreground: ThemeColor = ThemeColor(red: 0.55, green: 0.55, blue: 0.55),
		background: ThemeColor = ThemeColor(red: 0.93, green: 0.93, blue: 0.93),
		divider: ThemeColor = ThemeColor(red: 0.8, green: 0.8, blue: 0.8),
		selectionForeground: ThemeColor = ThemeColor(red: 0, green: 0, blue: 0),
		selectionBackground: ThemeColor = ThemeColor(red: 0.82, green: 0.82, blue: 0.82),
		selectionBorder: ThemeColor = ThemeColor(red: 0.7, green: 0.7, blue: 0.7),
	) {
		self.foreground = foreground
		self.background = background
		self.divider = divider
		self.selectionForeground = selectionForeground
		self.selectionBackground = selectionBackground
		self.selectionBorder = selectionBorder
	}
}

extension Theme {
	/// Whether this theme has a dark background.
	var isDark: Bool {
		globalSettings.background.isDark
	}
}
