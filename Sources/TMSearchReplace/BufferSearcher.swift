import Foundation

// MARK: - Buffer Search Result

/// Result of a buffer search with optional wrap-around indicator.
public struct BufferSearchResult: Sendable {
	/// The matches found, keyed by their byte range.
	public var matches: [FindMatch]

	/// Whether the search wrapped around.
	public var didWrap: Bool

	/// Whether any matches were found.
	public var hasMatches: Bool {
		!matches.isEmpty
	}

	/// The first match, if any.
	public var firstMatch: FindMatch? {
		matches.first
	}

	/// The number of matches.
	var count: Int {
		matches.count
	}

	init(matches: [FindMatch] = [], didWrap: Bool = false) {
		self.matches = matches
		self.didWrap = didWrap
	}
}

// MARK: - Buffer Searcher

/// Searches within a text buffer — equivalent to `ng::find()` and `ng::find_all()`.
///
/// Operates on a plain `String` (the buffer content). For integration with
/// `TextBuffer` from TMCore, convert to/from string as needed.
public struct BufferSearcher: Sendable {
	/// The text to search in.
	public let text: String

	/// Precomputed UTF-8 bytes for byte-offset operations.
	private let utf8Bytes: [UInt8]

	public init(text: String) {
		self.text = text
		utf8Bytes = Array(text.utf8)
	}

	// MARK: - Find Next/Previous

	/// Find the next (or previous) match from the given byte offset.
	///
	/// - Parameters:
	///   - pattern: The search pattern.
	///   - options: Search options (`.backwards` for previous).
	///   - fromOffset: The byte offset to start from.
	///   - searchRange: Optional range to limit the search (for "find in selection").
	/// - Returns: A `BufferSearchResult` with at most one match.
	public func findNext(
		pattern: String,
		options: FindOptions,
		fromOffset: Int = 0,
		searchRange: Range<Int>? = nil,
	) throws -> BufferSearchResult {
		guard !pattern.isEmpty else {
			return BufferSearchResult()
		}

		let finder = try makeTextFinder(pattern: pattern, options: options)

		// Determine the text range to search
		let effectiveRange = searchRange ?? (0 ..< utf8Bytes.count)
		let searchText = extractUTF8Substring(effectiveRange)

		if options.contains(.backwards) {
			return findPrevious(
				finder: finder,
				text: searchText,
				offset: effectiveRange.lowerBound,
				fromOffset: fromOffset,
				options: options,
			)
		} else {
			return findForward(
				finder: finder,
				text: searchText,
				offset: effectiveRange.lowerBound,
				fromOffset: fromOffset,
				wrapAround: options.contains(.wrapAround),
				options: options,
			)
		}
	}

	// MARK: - Find All

	/// Find all matches in the buffer.
	///
	/// - Parameters:
	///   - pattern: The search pattern.
	///   - options: Search options.
	///   - searchRange: Optional range to limit the search.
	/// - Returns: A `BufferSearchResult` with all matches.
	public func findAll(
		pattern: String,
		options: FindOptions,
		searchRange: Range<Int>? = nil,
	) throws -> BufferSearchResult {
		guard !pattern.isEmpty else {
			return BufferSearchResult()
		}

		let finder = try makeTextFinder(pattern: pattern, options: options)
		let effectiveRange = searchRange ?? (0 ..< utf8Bytes.count)
		let searchText = extractUTF8Substring(effectiveRange)

		var matches: [FindMatch] = []
		finder.eachMatch(in: searchText, offset: effectiveRange.lowerBound, moreToCome: false) { match, _ in
			matches.append(match)
		}

		return BufferSearchResult(matches: matches)
	}

	// MARK: - Replace All

	/// Find and replace all matches, returning the modified text and replacement count.
	///
	/// - Parameters:
	///   - pattern: The search pattern.
	///   - replacement: The replacement template string.
	///   - options: Search options.
	///   - searchRange: Optional range to limit the search.
	/// - Returns: A tuple of (modified text, replacement count, replacement ranges).
	public func replaceAll(
		pattern: String,
		replacement: String,
		options: FindOptions,
		searchRange: Range<Int>? = nil,
	) throws -> (text: String, count: Int, ranges: [Range<Int>]) {
		let result = try findAll(pattern: pattern, options: options, searchRange: searchRange)
		guard !result.matches.isEmpty else {
			return (text, 0, [])
		}

		let template = ReplacementTemplate(replacement)
		var modifiedBytes = utf8Bytes
		var replacementRanges: [Range<Int>] = []
		var offset = 0

		for match in result.matches {
			let expanded = template.expand(with: match.captures)
			let replacementBytes = Array(expanded.utf8)

			let adjustedStart = match.range.lowerBound + offset
			let adjustedEnd = match.range.upperBound + offset

			modifiedBytes.replaceSubrange(adjustedStart ..< adjustedEnd, with: replacementBytes)

			let newEnd = adjustedStart + replacementBytes.count
			replacementRanges.append(adjustedStart ..< newEnd)

			offset += replacementBytes.count - match.range.count
		}

		let modifiedText = String(bytes: modifiedBytes, encoding: .utf8) ?? text
		return (modifiedText, result.matches.count, replacementRanges)
	}

	// MARK: - Count

	/// Count the number of matches without collecting them.
	public func countMatches(
		pattern: String,
		options: FindOptions,
		searchRange: Range<Int>? = nil,
	) throws -> Int {
		let result = try findAll(pattern: pattern, options: options, searchRange: searchRange)
		return result.count
	}

	// MARK: - Private Helpers

	private func findForward(
		finder: TextFinder,
		text: String,
		offset: Int,
		fromOffset: Int,
		wrapAround: Bool,
		options _: FindOptions,
	) -> BufferSearchResult {
		// Search from fromOffset to end
		let adjustedFrom = max(0, fromOffset - offset)
		let afterText = extractSubstring(of: text, fromUTF8Offset: adjustedFrom)

		var firstMatch: FindMatch?
		finder.eachMatch(in: afterText, offset: fromOffset, moreToCome: false) { match, stop in
			firstMatch = match
			stop = true
		}

		if let match = firstMatch {
			return BufferSearchResult(matches: [match])
		}

		// Wrap around: search from beginning to fromOffset
		if wrapAround, adjustedFrom > 0 {
			let beforeText = extractSubstring(of: text, toUTF8Offset: adjustedFrom)
			finder.eachMatch(in: beforeText, offset: offset, moreToCome: false) { match, stop in
				firstMatch = match
				stop = true
			}
			if let match = firstMatch {
				return BufferSearchResult(matches: [match], didWrap: true)
			}
		}

		return BufferSearchResult()
	}

	private func findPrevious(
		finder: TextFinder,
		text: String,
		offset: Int,
		fromOffset: Int,
		options: FindOptions,
	) -> BufferSearchResult {
		// For backwards search, find all matches before fromOffset and take the last
		let adjustedFrom = max(0, fromOffset - offset)
		let beforeText = extractSubstring(of: text, toUTF8Offset: adjustedFrom)

		var allMatches: [FindMatch] = []
		let forwardFinder: TextFinder = if let rf = finder as? RegexFinder {
			// Create a forward version for collecting all matches
			(try? RegexFinder(pattern: rf.patternString, options: options.subtracting(.backwards))) ?? rf
		} else if let pf = finder as? PlainTextFinder {
			PlainTextFinder(searchString: pf.searchString, options: options.subtracting(.backwards))
		} else {
			finder
		}

		forwardFinder.eachMatch(in: beforeText, offset: offset, moreToCome: false) { match, _ in
			allMatches.append(match)
		}

		if let lastMatch = allMatches.last {
			return BufferSearchResult(matches: [lastMatch])
		}

		// Wrap around: search from fromOffset to end
		if options.contains(.wrapAround) {
			let afterText = extractSubstring(of: text, fromUTF8Offset: adjustedFrom)
			forwardFinder.eachMatch(in: afterText, offset: fromOffset, moreToCome: false) { match, _ in
				allMatches.append(match)
			}
			if let lastMatch = allMatches.last {
				return BufferSearchResult(matches: [lastMatch], didWrap: true)
			}
		}

		return BufferSearchResult()
	}

	/// Extract a substring from UTF-8 bytes.
	private func extractUTF8Substring(_ range: Range<Int>) -> String {
		let clampedStart = max(0, min(range.lowerBound, utf8Bytes.count))
		let clampedEnd = max(clampedStart, min(range.upperBound, utf8Bytes.count))
		let slice = utf8Bytes[clampedStart ..< clampedEnd]
		return String(bytes: slice, encoding: .utf8) ?? ""
	}

	/// Extract a substring from a given UTF-8 byte offset to the end.
	private func extractSubstring(of text: String, fromUTF8Offset offset: Int) -> String {
		let utf8 = Array(text.utf8)
		guard offset >= 0, offset < utf8.count else { return "" }
		return String(bytes: utf8[offset...], encoding: .utf8) ?? ""
	}

	/// Extract a substring from the beginning to a given UTF-8 byte offset.
	private func extractSubstring(of text: String, toUTF8Offset offset: Int) -> String {
		let utf8 = Array(text.utf8)
		guard offset > 0 else { return "" }
		let clampedEnd = min(offset, utf8.count)
		return String(bytes: utf8[..<clampedEnd], encoding: .utf8) ?? ""
	}
}
