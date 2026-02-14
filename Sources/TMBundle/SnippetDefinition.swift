import Foundation

/// A TextMate snippet definition loaded from a `.tmSnippet` plist.
///
/// Snippets are templates with tab stops, placeholders, mirrors, and
/// transformations. The snippet body uses TextMate's snippet syntax:
/// - `$1`, `$2`, …, `$0` — tab stops
/// - `${1:default}` — tab stop with placeholder
/// - `${1/regex/replacement/flags}` — transformation
/// - `$TM_FILENAME` — environment variable
public struct SnippetDefinition: Sendable {
	/// Display name.
	public let name: String

	/// UUID of the snippet bundle item.
	public let uuid: String?

	/// Tab trigger string (e.g. typing "fun" + Tab inserts the snippet).
	public let tabTrigger: String?

	/// Key equivalent for triggering this snippet.
	public let keyEquivalent: String?

	/// Scope selector — the snippet is only active within matching scopes.
	public let scope: String?

	/// The snippet body (template text with tab stops).
	public let content: String

	// MARK: - Parsing

	/// Loads a snippet from a `.tmSnippet` plist file.
	public static func load(from url: URL) throws -> SnippetDefinition {
		let dict = try BundlePlistParser.load(url: url)
		return try parse(dict)
	}

	/// Parses a snippet from a plist dictionary.
	public static func parse(_ dict: [String: Any]) throws -> SnippetDefinition {
		let content = try BundlePlistParser.string(dict, key: "content")
		let name = BundlePlistParser.optionalString(dict, key: "name") ?? "Untitled"

		return SnippetDefinition(
			name: name,
			uuid: BundlePlistParser.optionalString(dict, key: "uuid"),
			tabTrigger: BundlePlistParser.optionalString(dict, key: "tabTrigger"),
			keyEquivalent: BundlePlistParser.optionalString(dict, key: "keyEquivalent"),
			scope: BundlePlistParser.optionalString(dict, key: "scope"),
			content: content,
		)
	}
}
