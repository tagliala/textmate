import Foundation

/// A TextMate preference definition loaded from a `.tmPreferences` plist.
///
/// Preferences specify settings that are scoped to particular contexts
/// (e.g. smart typing pairs, comment characters, indentation rules).
public struct PreferenceDefinition: Sendable {
	/// Display name.
	public let name: String

	/// UUID of the preference bundle item.
	public let uuid: String?

	/// Scope selector.
	public let scope: String?

	/// The settings dictionary containing the preference values.
	public let settings: Settings

	// MARK: - Settings

	/// Common preference settings.
	public struct Settings: @unchecked Sendable {
		/// Shell variables set when this scope is active.
		public let shellVariables: [ShellVariable]

		/// Characters that auto-complete as pairs (e.g. `["(", ")"]`).
		public let smartTypingPairs: [[String]]?

		/// Regular expression for increasing indent.
		public let increaseIndentPattern: String?

		/// Regular expression for decreasing indent.
		public let decreaseIndentPattern: String?

		/// Regular expression for lines that should be indented next.
		public let indentNextLinePattern: String?

		/// Regular expression for lines that should not be indented.
		public let unIndentedLinePattern: String?

		/// Symbol list transformation pattern.
		public let symbolTransformation: String?

		/// Highlighting pairs (e.g. `["(", ")"]`, `["{", "}"]`).
		public let highlightPairs: [[String]]?

		/// Whether to show in the symbol list.
		public let showInSymbolList: Bool?

		/// Comment characters.
		public let comment: CommentSettings?

		/// The raw settings dictionary, for keys not explicitly modeled.
		public nonisolated(unsafe) let rawSettings: [String: Any]

		public init(
			shellVariables: [ShellVariable] = [],
			smartTypingPairs: [[String]]? = nil,
			increaseIndentPattern: String? = nil,
			decreaseIndentPattern: String? = nil,
			indentNextLinePattern: String? = nil,
			unIndentedLinePattern: String? = nil,
			symbolTransformation: String? = nil,
			highlightPairs: [[String]]? = nil,
			showInSymbolList: Bool? = nil,
			comment: CommentSettings? = nil,
			rawSettings: [String: Any] = [:],
		) {
			self.shellVariables = shellVariables
			self.smartTypingPairs = smartTypingPairs
			self.increaseIndentPattern = increaseIndentPattern
			self.decreaseIndentPattern = decreaseIndentPattern
			self.indentNextLinePattern = indentNextLinePattern
			self.unIndentedLinePattern = unIndentedLinePattern
			self.symbolTransformation = symbolTransformation
			self.highlightPairs = highlightPairs
			self.showInSymbolList = showInSymbolList
			self.comment = comment
			self.rawSettings = rawSettings
		}
	}

	/// A shell variable definition.
	public struct ShellVariable: Sendable {
		public let name: String
		public let value: String

		public init(name: String, value: String) {
			self.name = name
			self.value = value
		}
	}

	/// Comment character settings.
	public struct CommentSettings: Sendable {
		public let lineComment: String?
		public let blockCommentStart: String?
		public let blockCommentEnd: String?

		public init(lineComment: String? = nil, blockCommentStart: String? = nil, blockCommentEnd: String? = nil) {
			self.lineComment = lineComment
			self.blockCommentStart = blockCommentStart
			self.blockCommentEnd = blockCommentEnd
		}
	}

	// MARK: - Parsing

	/// Loads a preference from a `.tmPreferences` plist file.
	public static func load(from url: URL) throws -> PreferenceDefinition {
		let dict = try BundlePlistParser.load(url: url)
		return try parse(dict)
	}

	/// Parses a preference from a plist dictionary.
	public static func parse(_ dict: [String: Any]) throws -> PreferenceDefinition {
		let name = BundlePlistParser.optionalString(dict, key: "name") ?? "Untitled"
		let settingsDict = BundlePlistParser.optionalDictionary(dict, key: "settings") ?? [:]

		return PreferenceDefinition(
			name: name,
			uuid: BundlePlistParser.optionalString(dict, key: "uuid"),
			scope: BundlePlistParser.optionalString(dict, key: "scope"),
			settings: parseSettings(settingsDict),
		)
	}

	// MARK: - Private

	private static func parseSettings(_ dict: [String: Any]) -> Settings {
		// Shell variables
		var shellVars: [ShellVariable] = []
		if let arr = dict["shellVariables"] as? [[String: Any]] {
			for varDict in arr {
				if let name = varDict["name"] as? String,
				   let value = varDict["value"] as? String
				{
					shellVars.append(ShellVariable(name: name, value: value))
				}
			}
		}

		// Smart typing pairs
		let smartPairs = (dict["smartTypingPairs"] as? [[String]])

		// Highlight pairs
		let highlightPairs = (dict["highlightPairs"] as? [[String]])

		// Comment settings
		var comment: CommentSettings?
		let lineComment = dict["TM_COMMENT_START"] as? String
			?? shellVars.first(where: { $0.name == "TM_COMMENT_START" })?.value
		let blockStart = dict["TM_COMMENT_START_2"] as? String
			?? shellVars.first(where: { $0.name == "TM_COMMENT_START_2" })?.value
		let blockEnd = dict["TM_COMMENT_END_2"] as? String
			?? shellVars.first(where: { $0.name == "TM_COMMENT_END_2" })?.value
		if lineComment != nil || blockStart != nil {
			comment = CommentSettings(
				lineComment: lineComment,
				blockCommentStart: blockStart,
				blockCommentEnd: blockEnd,
			)
		}

		return Settings(
			shellVariables: shellVars,
			smartTypingPairs: smartPairs,
			increaseIndentPattern: BundlePlistParser.optionalString(dict, key: "increaseIndentPattern"),
			decreaseIndentPattern: BundlePlistParser.optionalString(dict, key: "decreaseIndentPattern"),
			indentNextLinePattern: BundlePlistParser.optionalString(dict, key: "indentNextLinePattern"),
			unIndentedLinePattern: BundlePlistParser.optionalString(dict, key: "unIndentedLinePattern"),
			symbolTransformation: BundlePlistParser.optionalString(dict, key: "showInSymbolList"),
			highlightPairs: highlightPairs,
			showInSymbolList: BundlePlistParser.optionalBool(dict, key: "showInSymbolList"),
			comment: comment,
			rawSettings: dict,
		)
	}
}
