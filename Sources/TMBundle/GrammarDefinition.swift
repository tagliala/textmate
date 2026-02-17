import Foundation

/// A TextMate grammar definition loaded from a `.tmLanguage` plist.
///
/// Grammars define syntax highlighting rules via hierarchical patterns
/// with scope names. Each pattern can be a simple `match` pattern or a
/// `begin`/`end` region with nested patterns.
public struct GrammarDefinition: Sendable {
	/// The top-level scope name (e.g. `"source.swift"`).
	public let scopeName: String

	/// Display name for the grammar (e.g. `"Swift"`).
	public let name: String

	/// File extensions associated with this grammar.
	public let fileTypes: [String]

	/// UUID of the grammar bundle item.
	public let uuid: String?

	/// First-line match pattern (for filetype detection).
	public let firstLineMatch: String?

	/// The top-level patterns array.
	public let patterns: [Pattern]

	/// Named repository of reusable pattern groups.
	public let repository: [String: PatternGroup]

	/// The fold start marker regular expression.
	public let foldingStartMarker: String?

	/// The fold end marker regular expression.
	public let foldingStopMarker: String?

	public init(
		scopeName: String,
		name: String,
		fileTypes: [String] = [],
		uuid: String? = nil,
		firstLineMatch: String? = nil,
		patterns: [Pattern] = [],
		repository: [String: PatternGroup] = [:],
		foldingStartMarker: String? = nil,
		foldingStopMarker: String? = nil,
	) {
		self.scopeName = scopeName
		self.name = name
		self.fileTypes = fileTypes
		self.uuid = uuid
		self.firstLineMatch = firstLineMatch
		self.patterns = patterns
		self.repository = repository
		self.foldingStartMarker = foldingStartMarker
		self.foldingStopMarker = foldingStopMarker
	}

	// MARK: - Pattern Types

	/// A single grammar pattern.
	public struct Pattern: Sendable {
		/// Simple match regex.
		public let match: String?
		/// Begin regex for a region.
		public let begin: String?
		/// End regex for a region.
		public let end: String?
		/// While regex for a region.
		public let whilePattern: String?
		/// Scope name assigned to this match/region.
		public let name: String?
		/// Content name for the text between begin and end.
		public let contentName: String?
		/// Capture groups for `match`, keyed by capture index string.
		public let captures: [String: CaptureAttributes]?
		/// Capture groups for `begin`.
		public let beginCaptures: [String: CaptureAttributes]?
		/// Capture groups for `end`.
		public let endCaptures: [String: CaptureAttributes]?
		/// Nested patterns within a begin/end region.
		public let patterns: [Pattern]?
		/// Include reference (e.g. `"#repository_name"`, `"source.other"`, `"$self"`).
		public let include: String?

		public init(
			match: String? = nil, begin: String? = nil, end: String? = nil,
			whilePattern: String? = nil, name: String? = nil,
			contentName: String? = nil, captures: [String: CaptureAttributes]? = nil,
			beginCaptures: [String: CaptureAttributes]? = nil,
			endCaptures: [String: CaptureAttributes]? = nil,
			patterns: [Pattern]? = nil, include: String? = nil,
		) {
			self.match = match
			self.begin = begin
			self.end = end
			self.whilePattern = whilePattern
			self.name = name
			self.contentName = contentName
			self.captures = captures
			self.beginCaptures = beginCaptures
			self.endCaptures = endCaptures
			self.patterns = patterns
			self.include = include
		}
	}

	/// Attributes for a regex capture group.
	public struct CaptureAttributes: Sendable {
		public let name: String?
		public let patterns: [Pattern]?

		public init(name: String? = nil, patterns: [Pattern]? = nil) {
			self.name = name
			self.patterns = patterns
		}
	}

	/// A named group of patterns (used in the repository).
	public struct PatternGroup: Sendable {
		public let patterns: [Pattern]?
		/// If the repository entry is itself a single pattern.
		public let pattern: Pattern?

		public init(patterns: [Pattern]? = nil, pattern: Pattern? = nil) {
			self.patterns = patterns
			self.pattern = pattern
		}
	}

	// MARK: - Parsing

	/// Loads a grammar from a `.tmLanguage` plist file.
	public static func load(from url: URL) throws -> GrammarDefinition {
		let dict = try BundlePlistParser.load(url: url)
		return try parse(dict)
	}

	/// Parses a grammar from a plist dictionary.
	public static func parse(_ dict: [String: Any]) throws -> GrammarDefinition {
		let scopeName = try BundlePlistParser.string(dict, key: "scopeName")
		let name = BundlePlistParser.optionalString(dict, key: "name") ?? scopeName

		return GrammarDefinition(
			scopeName: scopeName,
			name: name,
			fileTypes: BundlePlistParser.optionalStringArray(dict, key: "fileTypes") ?? [],
			uuid: BundlePlistParser.optionalString(dict, key: "uuid"),
			firstLineMatch: BundlePlistParser.optionalString(dict, key: "firstLineMatch"),
			patterns: parsePatterns(BundlePlistParser.optionalArrayOfDicts(dict, key: "patterns") ?? []),
			repository: parseRepository(BundlePlistParser.optionalDictionary(dict, key: "repository") ?? [:]),
			foldingStartMarker: BundlePlistParser.optionalString(dict, key: "foldingStartMarker"),
			foldingStopMarker: BundlePlistParser.optionalString(dict, key: "foldingStopMarker"),
		)
	}

	// MARK: - Private Parsers

	private static func parsePatterns(_ arr: [[String: Any]]) -> [Pattern] {
		arr.map { parsePattern($0) }
	}

	private static func parsePattern(_ dict: [String: Any]) -> Pattern {
		Pattern(
			match: BundlePlistParser.optionalString(dict, key: "match"),
			begin: BundlePlistParser.optionalString(dict, key: "begin"),
			end: BundlePlistParser.optionalString(dict, key: "end"),
			whilePattern: BundlePlistParser.optionalString(dict, key: "while"),
			name: BundlePlistParser.optionalString(dict, key: "name"),
			contentName: BundlePlistParser.optionalString(dict, key: "contentName"),
			captures: parseCaptures(BundlePlistParser.optionalDictionary(dict, key: "captures")),
			beginCaptures: parseCaptures(BundlePlistParser.optionalDictionary(dict, key: "beginCaptures")),
			endCaptures: parseCaptures(BundlePlistParser.optionalDictionary(dict, key: "endCaptures")),
			patterns: {
				if let arr = BundlePlistParser.optionalArrayOfDicts(dict, key: "patterns") {
					return parsePatterns(arr)
				}
				return nil
			}(),
			include: BundlePlistParser.optionalString(dict, key: "include"),
		)
	}

	private static func parseCaptures(_ dict: [String: Any]?) -> [String: CaptureAttributes]? {
		guard let dict else { return nil }
		var result: [String: CaptureAttributes] = [:]
		for (key, value) in dict {
			guard let capDict = value as? [String: Any] else { continue }
			let name = BundlePlistParser.optionalString(capDict, key: "name")
			let patterns: [Pattern]? = {
				if let arr = BundlePlistParser.optionalArrayOfDicts(capDict, key: "patterns") {
					return parsePatterns(arr)
				}
				return nil
			}()
			result[key] = CaptureAttributes(name: name, patterns: patterns)
		}
		return result.isEmpty ? nil : result
	}

	private static func parseRepository(_ dict: [String: Any]) -> [String: PatternGroup] {
		var result: [String: PatternGroup] = [:]
		for (key, value) in dict {
			guard let repoDict = value as? [String: Any] else { continue }
			if let patternsArr = BundlePlistParser.optionalArrayOfDicts(repoDict, key: "patterns") {
				result[key] = PatternGroup(patterns: parsePatterns(patternsArr))
			} else {
				// The repository entry is itself a single pattern.
				result[key] = PatternGroup(pattern: parsePattern(repoDict))
			}
		}
		return result
	}
}
