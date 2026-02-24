import Foundation

// MARK: - Format String AST

/// AST node for TextMate format strings and snippet bodies.
///
/// Replaces the C++ `boost::variant`-based `parser::node_t` from `parser_fwd.h`.
/// A single enum covers both format-string nodes (used in regex replacements,
/// grammar transforms) and snippet-specific nodes (tab-stop placeholders,
/// choices, embedded code).
public indirect enum FormatStringNode: Sendable, Equatable {
	// MARK: - Common Nodes

	/// Literal text.
	case text(String)

	/// A variable reference: `$name` or `${name}`.
	case variable(name: String)

	/// Variable with regex transform: `${name/pattern/format/options}`.
	case variableTransform(name: String, pattern: [FormatStringNode], format: [FormatStringNode], options: RegexpOptions)

	/// Variable with fallback: `${name:-fallback}` or `${name:fallback}`.
	case variableFallback(name: String, fallback: [FormatStringNode])

	/// Variable conditional: `${name:?if_set:if_not_set}` or `${name:+if_set}` or `(?N:if:else)`.
	case variableCondition(name: String, ifSet: [FormatStringNode], ifNotSet: [FormatStringNode])

	/// Variable with named transform: `${name:/upcase}`, `${name:/downcase}`, etc.
	case variableChange(name: String, change: TextTransformKind)

	/// Case change escape: `\U`, `\L`, `\E`, `\u`, `\l`.
	case caseChange(CaseChangeType)

	// MARK: - Snippet-Specific Nodes

	/// Tab-stop placeholder: `$N`, `${N}`, or `${N:content}`.
	case placeholder(index: Int, content: [FormatStringNode])

	/// Tab-stop with regex transform: `${N/pattern/format/options}`.
	case placeholderTransform(index: Int, pattern: String, format: [FormatStringNode], options: RegexpOptions)

	/// Tab-stop with choice menu: `${N|choice1,...,choiceN|}`.
	case placeholderChoice(index: Int, choices: [[FormatStringNode]])

	/// Inline code execution: `` `code` ``.
	case code(String)
}

// MARK: - Supporting Types

/// Case-change modes for `\U`, `\L`, `\E`, `\u`, `\l` escapes.
public enum CaseChangeType: Sendable, Equatable {
	/// No case change (`\E`).
	case none
	/// Uppercase next character (`\u`).
	case upperNext
	/// Lowercase next character (`\l`).
	case lowerNext
	/// Uppercase all following (`\U`).
	case upper
	/// Lowercase all following (`\L`).
	case lower
}

/// Regexp option flags for format string transforms.
public struct RegexpOptions: OptionSet, Sendable, Equatable {
	public let rawValue: UInt8

	public init(rawValue: UInt8) {
		self.rawValue = rawValue
	}

	/// No special options.
	public static let none = RegexpOptions(rawValue: 1 << 0)
	/// Global replacement (`g`).
	public static let global = RegexpOptions(rawValue: 1 << 1)
	/// Case-insensitive (`i`).
	public static let ignoreCase = RegexpOptions(rawValue: 1 << 2)
	/// Extended mode (`e`).
	public static let extended = RegexpOptions(rawValue: 1 << 3)
	/// Multiline mode (`m` — `^`/`$` match at line boundaries).
	public static let multiline = RegexpOptions(rawValue: 1 << 4)
	/// Single-line / dot-all mode (`s` — `.` matches newline).
	public static let singleLine = RegexpOptions(rawValue: 1 << 5)
}

/// Named text transforms applied via `${var:/transform}`.
public struct TextTransformKind: OptionSet, Sendable, Equatable {
	public let rawValue: UInt16

	public init(rawValue: UInt16) {
		self.rawValue = rawValue
	}

	public static let upcase = TextTransformKind(rawValue: 1 << 0)
	public static let downcase = TextTransformKind(rawValue: 1 << 1)
	public static let capitalize = TextTransformKind(rawValue: 1 << 2)
	public static let asciify = TextTransformKind(rawValue: 1 << 3)
	public static let urlEncode = TextTransformKind(rawValue: 1 << 4)
	public static let shellEscape = TextTransformKind(rawValue: 1 << 5)
	public static let relative = TextTransformKind(rawValue: 1 << 6)
	public static let number = TextTransformKind(rawValue: 1 << 7)
	public static let duration = TextTransformKind(rawValue: 1 << 8)
	public static let dirname = TextTransformKind(rawValue: 1 << 9)
	public static let basename = TextTransformKind(rawValue: 1 << 10)
}
