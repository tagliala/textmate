import AppKit

/// A style rule from a `.tmTheme`, matching a scope selector to visual attributes.
public struct ThemeStyleRule: Sendable {
	/// The scope selector string (e.g. `"comment"`, `"string.quoted"`).
	/// Empty for the global (unscoped) rule.
	public let scopeSelector: String

	/// Display name from the theme (e.g. `"Comment"`, `"String"`).
	public let name: String

	public let foreground: ThemeColor?
	public let background: ThemeColor?
	public let caret: ThemeColor?
	public let selection: ThemeColor?
	public let invisibles: ThemeColor?
	public let fontName: String?
	public let fontSize: CGFloat?
	public let isBold: Bool?
	public let isItalic: Bool?
	public let isUnderlined: Bool?
	public let isStrikethrough: Bool?

	public init(
		scopeSelector: String = "",
		name: String = "",
		foreground: ThemeColor? = nil,
		background: ThemeColor? = nil,
		caret: ThemeColor? = nil,
		selection: ThemeColor? = nil,
		invisibles: ThemeColor? = nil,
		fontName: String? = nil,
		fontSize: CGFloat? = nil,
		isBold: Bool? = nil,
		isItalic: Bool? = nil,
		isUnderlined: Bool? = nil,
		isStrikethrough: Bool? = nil,
	) {
		self.scopeSelector = scopeSelector
		self.name = name
		self.foreground = foreground
		self.background = background
		self.caret = caret
		self.selection = selection
		self.invisibles = invisibles
		self.fontName = fontName
		self.fontSize = fontSize
		self.isBold = isBold
		self.isItalic = isItalic
		self.isUnderlined = isUnderlined
		self.isStrikethrough = isStrikethrough
	}
}
