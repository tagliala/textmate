import Foundation

/// Error types for theme loading.
public enum ThemeLoadError: Error, Sendable {
	case fileNotFound(String)
	case invalidPlist(String)
	case missingSettings
}

/// Loads `.tmTheme` plist files into `Theme` values.
public enum ThemeLoader {
	/// Load a theme from a `.tmTheme` file at the given path.
	public static func load(from url: URL) throws -> Theme {
		guard FileManager.default.fileExists(atPath: url.path) else {
			throw ThemeLoadError.fileNotFound(url.path)
		}

		let data = try Data(contentsOf: url)
		return try load(from: data)
	}

	/// Load a theme from plist data.
	public static func load(from data: Data) throws -> Theme {
		guard let plist = try PropertyListSerialization.propertyList(
			from: data,
			options: [],
			format: nil,
		) as? [String: Any] else {
			throw ThemeLoadError.invalidPlist("Root is not a dictionary")
		}

		return try parse(plist: plist)
	}

	// MARK: - Private

	private static func parse(plist: [String: Any]) throws -> Theme {
		let name = plist["name"] as? String ?? "Untitled"
		let semanticClass = plist["semanticClass"] as? String ?? ""
		let uuid = plist["uuid"] as? String ?? ""

		guard let settingsArray = plist["settings"] as? [[String: Any]],
		      !settingsArray.isEmpty
		else {
			throw ThemeLoadError.missingSettings
		}

		// First entry with no "scope" key is the global settings
		let globalDict = settingsArray[0]["settings"] as? [String: String] ?? [:]
		let globalSettings = parseGlobalSettings(globalDict)

		// Gutter settings
		let gutterDict = plist["gutterSettings"] as? [String: String] ?? [:]
		let gutterSettings = parseGutterSettings(gutterDict, global: globalSettings)

		// Remaining entries are scope-specific rules
		var rules: [ThemeStyleRule] = []
		for entry in settingsArray.dropFirst() {
			guard let settings = entry["settings"] as? [String: String] else {
				continue
			}
			let scope = entry["scope"] as? String ?? ""
			let ruleName = entry["name"] as? String ?? ""
			let rule = parseStyleRule(
				scopeSelector: scope,
				name: ruleName,
				settings: settings,
			)
			rules.append(rule)
		}

		return Theme(
			name: name,
			semanticClass: semanticClass,
			uuid: uuid,
			globalSettings: globalSettings,
			gutterSettings: gutterSettings,
			rules: rules,
		)
	}

	private static func parseGlobalSettings(_ dict: [String: String]) -> ThemeGlobalSettings {
		ThemeGlobalSettings(
			foreground: ThemeColor(hex: dict["foreground"] ?? "#000000") ?? ThemeColor(red: 0, green: 0, blue: 0),
			background: ThemeColor(hex: dict["background"] ?? "#FFFFFF") ?? ThemeColor(red: 1, green: 1, blue: 1),
			caret: ThemeColor(hex: dict["caret"] ?? "#000000") ?? ThemeColor(red: 0, green: 0, blue: 0),
			selection: ThemeColor(hex: dict["selection"] ?? "#B5D5FF") ?? ThemeColor(red: 0.71, green: 0.84, blue: 1),
			invisibles: ThemeColor(hex: dict["invisibles"] ?? "#DADADAFF")
				?? ThemeColor(red: 0.85, green: 0.85, blue: 0.85),
			lineHighlight: ThemeColor(hex: dict["lineHighlight"] ?? ""),
		)
	}

	private static func parseGutterSettings(
		_ dict: [String: String],
		global: ThemeGlobalSettings,
	) -> ThemeGutterSettings {
		let defaultFg = ThemeColor(red: 0.55, green: 0.55, blue: 0.55)
		let defaultBg = if global.background.isDark {
			ThemeColor(red: 0.18, green: 0.18, blue: 0.19)
		} else {
			ThemeColor(red: 0.93, green: 0.93, blue: 0.93)
		}

		return ThemeGutterSettings(
			foreground: ThemeColor(hex: dict["foreground"] ?? "") ?? defaultFg,
			background: ThemeColor(hex: dict["background"] ?? "") ?? defaultBg,
			divider: ThemeColor(hex: dict["divider"] ?? "") ?? defaultBg,
			selectionForeground: ThemeColor(hex: dict["selectionForeground"] ?? "")
				?? global.foreground,
			selectionBackground: ThemeColor(hex: dict["selectionBackground"] ?? "")
				?? defaultBg,
			selectionBorder: ThemeColor(hex: dict["selectionBorder"] ?? "")
				?? defaultBg,
		)
	}

	private static func parseStyleRule(
		scopeSelector: String,
		name: String,
		settings: [String: String],
	) -> ThemeStyleRule {
		let fontStyle = settings["fontStyle"] ?? ""
		let fontStyles = fontStyle.split(separator: " ").map(String.init)

		return ThemeStyleRule(
			scopeSelector: scopeSelector,
			name: name,
			foreground: ThemeColor(hex: settings["foreground"] ?? ""),
			background: ThemeColor(hex: settings["background"] ?? ""),
			fontName: settings["fontName"],
			fontSize: settings["fontSize"].flatMap { Double($0).map { CGFloat($0) } },
			isBold: fontStyles.contains("bold") ? true : nil,
			isItalic: fontStyles.contains("italic") ? true : nil,
			isUnderlined: fontStyles.contains("underline") ? true : nil,
			isStrikethrough: fontStyles.contains("strikethrough") ? true : nil,
		)
	}
}
