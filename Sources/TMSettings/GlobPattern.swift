import Foundation

// MARK: - Glob Pattern

/// A glob pattern matcher that compiles glob syntax into a regex.
///
/// Ports the C++ `path::glob_t` and `path::glob_list_t` from `glob.h`/`glob.cc`
/// and `parse_glob.cc`.
///
/// Supports:
/// - `?` — match one character
/// - `*` — match zero or more characters (not /)
/// - `**` — match zero or more path components
/// - `{a,b,c}` — brace expansion (alternation)
/// - `[abc]` / `[a-z]` / `[^a-z]` — character classes
/// - `\x` — literal escape
/// - `!pattern` / `~pattern` — exclude suffix
public struct GlobPattern: Sendable {
	/// The compiled regex.
	private let compiled: NSRegularExpression?
	/// The original glob string.
	private let source: String

	/// Creates a glob pattern.
	///
	/// - Parameters:
	///   - glob: The glob pattern string.
	///   - matchDotFiles: If true, `*` matches dotfiles. Default false.
	///   - caseSensitive: If true, matching is case-sensitive. Default true.
	public init(_ glob: String, matchDotFiles: Bool = false, caseSensitive: Bool = true) {
		source = glob
		if glob.isEmpty {
			compiled = nil
		} else {
			let regexStr = GlobPattern.convertToRegex(glob, matchDotFiles: matchDotFiles)
			var options: NSRegularExpression.Options = []
			if !caseSensitive { options.insert(.caseInsensitive) }
			compiled = try? NSRegularExpression(pattern: regexStr, options: options)
		}
	}

	/// Tests whether the given filename matches this glob pattern.
	public func doesMatch(_ filename: String) -> Bool {
		guard let compiled else { return false }
		let range = NSRange(location: 0, length: (filename as NSString).length)
		return compiled.firstMatch(in: filename, range: range) != nil
	}

	/// Escapes special glob characters in a string.
	public static func escape(_ src: String) -> String {
		var result = ""
		for ch in src {
			if "[\\?*{~!".contains(ch) {
				result.append("\\")
			}
			result.append(ch)
		}
		return result
	}

	/// Returns the compiled regex pattern string for debugging.
	public var regexPattern: String {
		compiled?.pattern ?? ""
	}

	// MARK: - Glob → Regex Conversion

	/// Converts a glob pattern to a regex string.
	///
	/// Ports the C++ `convert_glob_to_regexp` from `parse_glob.cc`.
	static func convertToRegex(_ glob: String, matchDotFiles: Bool = false) -> String {
		let parser = GlobParser(glob)
		guard let root = parser.parseGlob() else { return ".*" }

		let includes = root.toRegexp(matchDotFiles: matchDotFiles)
		let excludes = root.excludePattern()

		var res = "^"
		if !excludes.isEmpty {
			res += "(?!(?:.*/)?(?:\(excludes))$)"
		}
		if !includes.isEmpty {
			res += "(?:.*/)?(?:\(includes))"
		} else {
			res += ".*"
		}
		res += "$"

		return res
	}

	/// Expands brace patterns, e.g. `{a,b,c}` → `["a", "b", "c"]`.
	///
	/// Ports the C++ `expand_braces` from `parse_glob.cc`.
	public static func expandBraces(_ glob: String) -> [String] {
		let parser = BraceParser(glob)
		guard let root = parser.parseBraces() else { return [glob] }
		var result = [""]
		root.expandBraces(&result)
		return result
	}
}

// MARK: - Glob AST Node

/// Internal AST for parsed glob patterns.
private final class GlobNode {
	enum Kind {
		case text, charClass, optional, root, group, or_, any, anyRecursive, exclude
	}

	let kind: Kind
	let text: String
	var left: GlobNode?
	var right: GlobNode?

	init(_ kind: Kind, text: String = "", left: GlobNode? = nil, right: GlobNode? = nil) {
		self.kind = kind
		self.text = text
		self.left = left
		self.right = right
	}

	/// Expands brace groups, appending to each string in `strings`.
	func expandBraces(_ strings: inout [String]) {
		if kind == .or_, let left, let right {
			var tmp = strings
			right.expandBraces(&tmp)
			left.expandBraces(&strings)
			strings.append(contentsOf: tmp)
			return
		}

		if kind == .text {
			for i in strings.indices {
				strings[i] += text
			}
		}
		left?.expandBraces(&strings)
		right?.expandBraces(&strings)
	}

	/// Returns the regex for exclude patterns.
	func excludePattern() -> String {
		guard kind == .exclude else { return "" }
		let leftPat = left?.toRegexp(matchDotFiles: true) ?? ""
		let rightPat = right?.excludePattern() ?? ""
		return rightPat.isEmpty ? leftPat : rightPat + "|" + leftPat
	}

	/// Converts the glob AST to a regex string.
	func toRegexp(matchDotFiles: Bool) -> String {
		var res = ""

		switch kind {
		case .text:
			// Escape regex special characters in literal text
			for ch in text {
				if "[](){}\\|.?*+^$".contains(ch) {
					res += "\\"
				}
				res.append(ch)
			}
		case .charClass:
			res = "[\(text)]"
		case .optional:
			res = "."
		case .group:
			if let left {
				res = "(?:\(left.toRegexp(matchDotFiles: matchDotFiles)))"
			}
		case .or_:
			if let left {
				res = left.toRegexp(matchDotFiles: matchDotFiles) + "|"
			}
		case .any:
			res = matchDotFiles ? "[^/]*" : "(?:(?!\\.)|(?<!^|/))[^/]*"
		case .anyRecursive:
			if matchDotFiles {
				res = "(?:.*\(text))?"
			} else {
				res = "(?:(?:(?!\\.)|(?<!^|/))[^/]*(?:/(?!\\.)[^/]*)*\(text))?"
			}
		case .root, .exclude:
			break
		}

		if let right {
			res += right.toRegexp(matchDotFiles: matchDotFiles)
		}
		return res
	}
}

// MARK: - Glob Parser Base

/// Common parser functionality shared between glob and brace parsers.
private class GlobParserBase {
	let input: String
	var index: String.Index
	let endIndex: String.Index
	var root: GlobNode?
	var lastPtr: WritableKeyPath<GlobNode, GlobNode?>?
	private var lastNode: GlobNode?

	init(_ input: String) {
		self.input = input
		index = input.startIndex
		endIndex = input.endIndex
	}

	var peek: Character? {
		index < endIndex ? input[index] : nil
	}

	func parseChar(_ chars: String) -> Bool {
		guard index < endIndex, chars.contains(input[index]) else { return false }
		index = input.index(after: index)
		return true
	}

	func parseUntil(_ stopChars: String) -> String? {
		let backtrack = index
		var result = ""
		while index < endIndex, !stopChars.contains(input[index]) {
			if input[index] == "\\", input.index(after: index) < endIndex {
				let next = input[input.index(after: index)]
				if next == "\\" || stopChars.contains(next) {
					index = input.index(after: index)
				}
			}
			result.append(input[index])
			index = input.index(after: index)
		}
		if parseChar(stopChars) { return result }
		index = backtrack
		return nil
	}

	func addNode(_ node: GlobNode) {
		if root == nil {
			root = node
		} else {
			// Append to rightmost chain
			appendToChain(node)
		}
		lastNode = node
	}

	private func appendToChain(_ node: GlobNode) {
		var current = root!
		while current.right != nil {
			current = current.right!
		}
		current.right = node
	}

	func parseBraceExpansion(nodeParser: (String, Bool) -> GlobNode?) -> Bool {
		let backtrack = index
		let oldRoot = root

		guard parseChar("{") else { return false }

		var hasComma = false
		var localRoot: GlobNode?

		while true {
			let savedRoot = root
			root = nil
			let content = nodeParser(",}", true)
			let contentNode = content ?? root
			root = savedRoot

			localRoot = GlobNode(.or_, left: localRoot, right: contentNode)

			if parseChar("}") {
				if hasComma {
					addNode(GlobNode(.group, left: localRoot))
					return true
				}
				// Not a brace expansion, treat as literal text
				root = oldRoot
				let savedIdx = index
				index = backtrack
				let endSaved = savedIdx
				// Re-parse as text
				while index < endSaved {
					if let ch = peek {
						addNode(GlobNode(.text, text: String(ch)))
						index = input.index(after: index)
					}
				}
				return true
			} else if parseChar(",") {
				hasComma = true
			} else {
				break
			}
		}

		root = oldRoot
		index = backtrack
		return false
	}

	func parseText(_ stopChars: String) -> Bool {
		let backtrack = index
		guard index < endIndex, !stopChars.contains(input[index]) else { return false }

		var text = ""
		while index < endIndex, !stopChars.contains(input[index]) {
			text.append(input[index])
			index = input.index(after: index)
		}
		if !text.isEmpty {
			addNode(GlobNode(.text, text: text))
			return true
		}
		index = backtrack
		return false
	}
}

// MARK: - Brace Parser

/// Parses brace expansion patterns.
private final class BraceParser: GlobParserBase {
	func parseBraces() -> GlobNode? {
		root = nil
		parseBracesContent(stopChars: "")
		return root
	}

	@discardableResult
	private func parseBracesContent(stopChars: String) -> GlobNode? {
		let saved = root
		root = nil
		while index < endIndex, !stopChars.contains(input[index]) {
			if parseEscape() { continue }
			if parseBraceExpansion(nodeParser: { [self] s, _ in parseBracesContent(stopChars: s) }) { continue }
			if parseText("\\{" + stopChars) { continue }
			break
		}
		let result = root
		root = saved
		if let result {
			addNode(result)
		}
		return result
	}

	private func parseEscape() -> Bool {
		let backtrack = index
		guard parseChar("\\"), index < endIndex, "\\{,}".contains(input[index]) else {
			index = backtrack
			return false
		}
		addNode(GlobNode(.text, text: String(input[index])))
		index = input.index(after: index)
		return true
	}
}

// MARK: - Glob Parser

/// Parses full glob patterns with wildcards, character classes, and excludes.
private final class GlobParser: GlobParserBase {
	func parseGlob(stopChars: String = "", parsingBraces: Bool = false) -> GlobNode? {
		root = nil
		let stop = parsingBraces ? "\\?*{[,}" : "\\?*{[!~"

		while index < endIndex, !stopChars.contains(input[index]) {
			if parseEscape() { continue }
			if parseOptional() { continue }
			if parseAnyRecursive() { continue }
			if parseAny() { continue }
			if parseBraceExpansion(nodeParser: { [self] s, pb in parseGlob(stopChars: s, parsingBraces: pb) }) { continue }
			if parseCharacterClass() { continue }
			if !parsingBraces, parseExclude() { continue }
			if parseText(stop) { continue }
			break
		}

		return root
	}

	private func parseEscape() -> Bool {
		let backtrack = index
		guard parseChar("\\"), index < endIndex else {
			index = backtrack
			return false
		}

		let ch = input[index]
		switch ch {
		case "t":
			addNode(GlobNode(.text, text: "\t"))
			index = input.index(after: index)
			return true
		case "r":
			addNode(GlobNode(.text, text: "\r"))
			index = input.index(after: index)
			return true
		case "n":
			addNode(GlobNode(.text, text: "\n"))
			index = input.index(after: index)
			return true
		default:
			addNode(GlobNode(.text, text: String(ch)))
			index = input.index(after: index)
			return true
		}
	}

	private func parseOptional() -> Bool {
		guard parseChar("?") else { return false }
		addNode(GlobNode(.optional))
		return true
	}

	private func parseAny() -> Bool {
		guard parseChar("*") else { return false }
		addNode(GlobNode(.any))
		return true
	}

	private func parseAnyRecursive() -> Bool {
		let backtrack = index
		guard parseChar("*"), parseChar("*") else {
			index = backtrack
			return false
		}
		let text = parseChar("/") ? "/" : ""
		addNode(GlobNode(.anyRecursive, text: text))
		return true
	}

	private func parseCharacterClass() -> Bool {
		let backtrack = index
		guard parseChar("["), let content = parseUntil("]") else {
			index = backtrack
			return false
		}
		addNode(GlobNode(.charClass, text: content))
		return true
	}

	private func parseExclude() -> Bool {
		let backtrack = index
		guard parseChar("~") || parseChar("!"), index < endIndex else {
			index = backtrack
			return false
		}
		let oldRoot = root

		// Parse the exclusion pattern (rest of the string)
		root = nil
		while index < endIndex {
			if parseEscape() { continue }
			if parseOptional() { continue }
			if parseAnyRecursive() { continue }
			if parseAny() { continue }
			if parseBraceExpansion(nodeParser: { [self] s, pb in parseGlob(stopChars: s, parsingBraces: pb) }) { continue }
			if parseCharacterClass() { continue }
			if parseText("\\?*{[") { continue }
			break
		}
		let excludePattern = root

		root = GlobNode(.exclude, left: excludePattern, right: oldRoot)
		return true
	}
}

// MARK: - Glob List

/// Path item type flags for glob list filtering.
public struct PathItemType: OptionSet, Sendable {
	public let rawValue: UInt
	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	/// Matches any item type.
	public static let any: PathItemType = []
	/// Matches files.
	public static let file = PathItemType(rawValue: 0x0001)
	/// Matches directories.
	public static let directory = PathItemType(rawValue: 0x0002)
	/// Mask for item type bits.
	static let mask = PathItemType(rawValue: 0x007F)
	/// Flag indicating this is an exclude glob.
	static let exclude = PathItemType(rawValue: 0x0080)
}

/// A list of glob patterns for include/exclude filtering.
///
/// Ports the C++ `path::glob_list_t`.
public struct GlobList: Sendable {
	private struct Record: Sendable {
		let glob: GlobPattern
		let itemType: PathItemType
	}

	private var globs: [Record] = []

	public init() {}

	public init(_ glob: String) {
		addIncludeGlob(glob)
	}

	/// Adds a glob pattern with the given item type flags.
	public mutating func addGlob(_ glob: String, itemType: PathItemType = .any) {
		globs.append(Record(glob: GlobPattern(glob, matchDotFiles: itemType.contains(.exclude)), itemType: itemType))
	}

	/// Adds an include glob.
	public mutating func addIncludeGlob(_ glob: String, itemType: PathItemType = .any) {
		addGlob(glob, itemType: itemType)
	}

	/// Adds an exclude glob (sets the exclude flag).
	public mutating func addExcludeGlob(_ glob: String, itemType: PathItemType = .any) {
		addGlob(glob, itemType: itemType.union(.exclude))
	}

	/// Returns `true` if the path should be included.
	public func include(_ path: String, itemType: PathItemType = .any, defaultResult: Bool = false) -> Bool {
		!exclude(path, itemType: itemType, defaultResult: !defaultResult)
	}

	/// Returns `true` if the path should be excluded.
	public func exclude(_ path: String, itemType: PathItemType = .any, defaultResult: Bool = true) -> Bool {
		if globs.isEmpty { return false }

		for record in globs {
			let recordType = record.itemType.intersection(.mask)
			let matchType = itemType == .any || recordType == .any || recordType == itemType
			if matchType, record.glob.doesMatch(path) {
				return record.itemType.contains(.exclude)
			}
		}
		return defaultResult
	}
}
