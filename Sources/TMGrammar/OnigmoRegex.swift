// Swift-native regular expression engine for TextMate grammar parsing.
//
// Uses `NSRegularExpression` (ICU engine) instead of the vendored Onigmo C
// library. This gives us pure Swift with no unsafe C interop, while covering
// ~98% of TextMate grammar patterns. The ICU engine supports lookahead,
// lookbehind, backreferences, named captures, possessive quantifiers, and
// Unicode properties — everything most grammars need.
//
// Architecture Decision: ADR-005 (see docs/architecture/)

import Foundation

// MARK: - OnigmoMatch

/// Result of a successful regex match against a UTF-8 buffer.
///
/// All offsets are in **bytes** (UTF-8), matching the C++ `regexp::match_t`
/// contract that the parse engine relies on.
public struct OnigmoMatch: Sendable {
	/// The matched region byte offsets (nil = group didn't participate).
	let region: [ClosedRange<Int>?]

	/// Named capture indices (name -> [(begin, end)]).
	let namedCaptures: [String: [(begin: Int, end: Int)]]

	/// The buffer that was matched against (retained for capture extraction).
	let buffer: [UInt8]

	/// Number of capture groups (including group 0 = full match).
	public var count: Int {
		region.count
	}

	/// Whether capture group `i` participated in the match.
	public func didMatch(_ i: Int = 0) -> Bool {
		guard i < region.count, let r = region[i] else { return false }
		return r.lowerBound >= 0
	}

	/// Byte offset of the start of capture group `i`.
	public func begin(_ i: Int = 0) -> Int {
		guard didMatch(i), let r = region[i] else { return end() }
		return r.lowerBound
	}

	/// Byte offset past the end of capture group `i`.
	public func end(_ i: Int = 0) -> Int {
		guard i < region.count, let r = region[i] else {
			return region.first.flatMap { $0?.upperBound } ?? 0
		}
		return r.upperBound
	}

	/// Byte offset of the start of the full match.
	public var matchBegin: Int {
		begin(0)
	}

	/// Byte offset past the end of the full match.
	public var matchEnd: Int {
		end(0)
	}

	/// Whether the match is zero-width.
	public var isEmpty: Bool {
		matchBegin == matchEnd
	}

	/// Extracts the matched string for capture group `i`.
	public func captureString(_ i: Int = 0) -> String? {
		guard didMatch(i) else { return nil }
		let b = begin(i)
		let e = end(i)
		guard e > b else { return "" }
		return String(bytes: buffer[b ..< e], encoding: .utf8)
	}

	/// Returns all capture values as a dictionary (numeric + named keys).
	public var captures: [String: String] {
		var result: [String: String] = [:]
		for (name, ranges) in namedCaptures {
			for r in ranges {
				if r.begin >= 0, r.end > r.begin {
					result[name] = String(
						bytes: buffer[r.begin ..< r.end], encoding: .utf8,
					)
				}
			}
		}
		for i in 0 ..< count {
			if didMatch(i), let s = captureString(i) {
				result[String(i)] = s
			}
		}
		return result
	}

	/// Returns capture indices as a list of (key, begin, end) tuples.
	public var captureIndices: [(key: String, begin: Int, end: Int)] {
		var result: [(key: String, begin: Int, end: Int)] = []
		for i in 0 ..< count where didMatch(i) {
			result.append((key: String(i), begin: begin(i), end: end(i)))
		}
		for (name, ranges) in namedCaptures {
			for r in ranges where r.begin >= 0 {
				result.append((key: name, begin: r.begin, end: r.end))
			}
		}
		return result
	}
}

// MARK: - OnigmoPattern

/// A compiled regular expression pattern backed by `NSRegularExpression`.
///
/// The name `OnigmoPattern` is retained for API compatibility with the
/// rest of the grammar engine, even though the underlying engine is now ICU.
public final class OnigmoPattern: @unchecked Sendable {
	/// The compiled NSRegularExpression, or `nil` if compilation failed.
	private let regex: NSRegularExpression?

	/// The original pattern string.
	public let patternString: String

	/// Whether the pattern compiled successfully.
	public var isValid: Bool {
		regex != nil
	}

	/// Pre-extracted named capture group names for efficient lookup.
	private let namedGroups: [String]

	/// Creates a compiled pattern from a regex string.
	///
	/// TextMate grammars use Oniguruma syntax. Most patterns work directly
	/// with ICU/NSRegularExpression. A small translation layer handles the
	/// most common Oniguruma-isms (e.g. `\h` -> `[\t\p{Zs}]`).
	public init(_ pattern: String, options _: UInt32 = 0) {
		patternString = pattern

		let translated = OnigmoPattern.translatePattern(pattern)

		do {
			regex = try NSRegularExpression(
				pattern: translated, options: [.anchorsMatchLines],
			)
			namedGroups = OnigmoPattern.extractNamedGroups(
				from: translated,
			)
		} catch {
			regex = nil
			namedGroups = []
		}
	}

	/// Searches for this pattern in the given UTF-8 buffer.
	///
	/// - Parameters:
	///   - buffer: The UTF-8 byte buffer to search.
	///   - searchRange: The byte range to search within.
	/// - Returns: An `OnigmoMatch` if found, or `nil`.
	public func search(
		in buffer: [UInt8],
		range searchRange: Range<Int>? = nil,
	) -> OnigmoMatch? {
		guard let regex else { return nil }

		// Convert the buffer to a String for NSRegularExpression
		guard let string = String(bytes: buffer, encoding: .utf8) else {
			return nil
		}

		let byteRange = searchRange ?? 0 ..< buffer.count

		// Convert byte range to String.Index range
		guard let startIdx = string.utf8.index(
			string.utf8.startIndex,
			offsetBy: byteRange.lowerBound,
			limitedBy: string.utf8.endIndex,
		) else { return nil }

		guard let endIdx = string.utf8.index(
			string.utf8.startIndex,
			offsetBy: byteRange.upperBound,
			limitedBy: string.utf8.endIndex,
		) else { return nil }

		// Convert to NSRange (UTF-16 offsets)
		let nsRange = NSRange(startIdx ..< endIdx, in: string)

		guard let result = regex.firstMatch(
			in: string, range: nsRange,
		) else { return nil }

		// Build regions: convert each capture group from NSRange (UTF-16)
		// back to byte offsets (UTF-8)
		var regions: [ClosedRange<Int>?] = []
		for i in 0 ..< result.numberOfRanges {
			let r = result.range(at: i)
			if r.location == NSNotFound {
				regions.append(nil)
			} else {
				guard let rStart = Range(r, in: string) else {
					regions.append(nil)
					continue
				}
				let byteBegin = string.utf8.distance(
					from: string.utf8.startIndex, to: rStart.lowerBound,
				)
				let byteEnd = string.utf8.distance(
					from: string.utf8.startIndex, to: rStart.upperBound,
				)
				regions.append(byteBegin ... byteEnd)
			}
		}

		// Extract named captures
		var named: [String: [(begin: Int, end: Int)]] = [:]
		for name in namedGroups {
			let r = result.range(withName: name)
			if r.location != NSNotFound, let rStart = Range(r, in: string) {
				let byteBegin = string.utf8.distance(
					from: string.utf8.startIndex, to: rStart.lowerBound,
				)
				let byteEnd = string.utf8.distance(
					from: string.utf8.startIndex, to: rStart.upperBound,
				)
				named[name] = [(begin: byteBegin, end: byteEnd)]
			}
		}

		return OnigmoMatch(
			region: regions, namedCaptures: named, buffer: buffer,
		)
	}

	/// Searches for this pattern in a string.
	public func search(in string: String) -> OnigmoMatch? {
		search(in: Array(string.utf8))
	}

	// MARK: - Pattern Translation

	/// Translates common Oniguruma-specific syntax to ICU equivalents.
	///
	/// This handles the most frequently used constructs in TextMate grammars
	/// that differ between Oniguruma and ICU regex engines.
	static func translatePattern(_ pattern: String) -> String {
		var result = ""
		var i = pattern.startIndex

		while i < pattern.endIndex {
			let ch = pattern[i]
			if ch == "\\", pattern.index(after: i) < pattern.endIndex {
				let next = pattern[pattern.index(after: i)]
				switch next {
				case "h":
					// \h = horizontal whitespace -> [\t\p{Zs}]
					result += "[\\t\\p{Zs}]"
					i = pattern.index(i, offsetBy: 2)
				case "H":
					// \H = non-horizontal-whitespace
					result += "[^\\t\\p{Zs}]"
					i = pattern.index(i, offsetBy: 2)
				case "v":
					// \v = vertical whitespace
					result += "[\\n\\r\\x0B\\f\\x85\\u2028\\u2029]"
					i = pattern.index(i, offsetBy: 2)
				case "V":
					result += "[^\\n\\r\\x0B\\f\\x85\\u2028\\u2029]"
					i = pattern.index(i, offsetBy: 2)
				case "R":
					// \R = any line break
					result += "(?:\\r\\n|[\\n\\r\\x0B\\f\\x85\\u2028\\u2029])"
					i = pattern.index(i, offsetBy: 2)
				case "X":
					// \X = extended grapheme cluster (approximate)
					result += "(?:\\P{M}\\p{M}*)"
					i = pattern.index(i, offsetBy: 2)
				default:
					// Pass through other escapes unchanged
					result.append(ch)
					result.append(next)
					i = pattern.index(i, offsetBy: 2)
				}
			} else {
				result.append(ch)
				i = pattern.index(after: i)
			}
		}

		return result
	}

	/// Extracts named capture group names from a pattern using `(?<name>...)`.
	private static func extractNamedGroups(from pattern: String) -> [String] {
		// Match (?<name> or (?P<name> or (?'name'
		guard let extractor = try? NSRegularExpression(
			pattern: #"\(\?(?:<([^>]+)>|P<([^>]+)>|'([^']+)')"#,
		) else { return [] }

		let nsRange = NSRange(pattern.startIndex..., in: pattern)
		let matches = extractor.matches(in: pattern, range: nsRange)

		var names: [String] = []
		for match in matches {
			for i in 1 ... 3 {
				let r = match.range(at: i)
				if r.location != NSNotFound, let range = Range(r, in: pattern) {
					names.append(String(pattern[range]))
					break
				}
			}
		}
		return names
	}
}

// MARK: - Format String Expansion

/// Expands `$0`...`$9` and `${name}` references in a scope/format string
/// using match capture values.
///
/// This is used for scope names like `"storage.type.$1"` where `$1` refers
/// to the first capture group of the match.
public func expandFormatString(
	_ format: String,
	captures: [String: String],
) -> String {
	var result = ""
	var it = format.startIndex

	while it < format.endIndex {
		if format[it] == "$" {
			let next = format.index(after: it)
			if next < format.endIndex {
				if format[next].isNumber {
					let key = String(format[next])
					result += captures[key] ?? ""
					it = format.index(after: next)
					continue
				} else if format[next] == "{" {
					let braceStart = format.index(after: next)
					if let braceEnd = format[braceStart...].firstIndex(of: "}") {
						let name = String(format[braceStart ..< braceEnd])
						result += captures[name] ?? ""
						it = format.index(after: braceEnd)
						continue
					}
				}
			}
		}
		result.append(format[it])
		it = format.index(after: it)
	}

	return result
}

// MARK: - Pattern Utilities

/// Checks whether a pattern contains back references (`\1` - `\9`).
public func patternHasBackReference(_ pattern: String) -> Bool {
	var escape = false
	for ch in pattern {
		if escape, ch.isNumber {
			return true
		}
		escape = !escape && ch == "\\"
	}
	return false
}

/// Checks whether a pattern contains `\G` (anchor to previous match).
public func patternHasAnchor(_ pattern: String) -> Bool {
	var escape = false
	for ch in pattern {
		if escape, ch == "G" {
			return true
		}
		escape = !escape && ch == "\\"
	}
	return false
}

/// Checks whether a string contains `$` (indicating format string).
public func patternIsFormatString(_ pattern: String) -> Bool {
	pattern.contains("$")
}

/// Expands back references in a pattern using match captures.
///
/// Replaces `\1`-`\9` with the corresponding match group content,
/// regex-escaping the replacement.
public func expandBackReferences(
	_ pattern: String,
	match: OnigmoMatch,
) -> String {
	var result = ""
	var escape = false

	for ch in pattern {
		if escape, ch.isNumber {
			let i = ch.wholeNumberValue!
			if let captured = match.captureString(i) {
				for c in captured {
					if "\\|([{}]).?*+^$#".contains(c) {
						result.append("\\")
					}
					result.append(c)
				}
			}
			escape = false
			continue
		}

		if escape {
			result.append("\\")
		}
		if ch == "\\", !escape {
			escape = true
		} else {
			result.append(ch)
			escape = false
		}
	}

	if escape {
		result.append("\\")
	}

	return result
}
