import Foundation

// MARK: - Text Finder Protocol

/// Protocol for streaming text search — equivalent to `find::find_t`.
///
/// Implementations process text in chunks via `eachMatch(in:moreToCome:callback:)`.
/// After all text has been fed, call with an empty buffer and `moreToCome: false`
/// to flush pending matches (important for regex patterns that match at end-of-input).
protocol TextFinder: Sendable {
	/// Feed a chunk of text. The callback receives each match range (byte offsets
	/// within the cumulative input) and its capture groups. Return `false` from
	/// the callback to stop searching.
	func eachMatch(
		in text: String,
		offset: Int,
		moreToCome: Bool,
		callback: (FindMatch, inout Bool) -> Void,
	)
}

// MARK: - Plain Text Finder

/// A plain-text search engine with Unicode normalization — equivalent to `regular_find_t`.
struct PlainTextFinder: TextFinder {
	/// The search string.
	let searchString: String

	/// Search options.
	let options: FindOptions

	/// The comparison options derived from FindOptions.
	private let comparisonOptions: String.CompareOptions

	init(searchString: String, options: FindOptions = .none) {
		self.searchString = searchString
		self.options = options

		var opts: String.CompareOptions = [.literal]
		if options.contains(.ignoreCase) {
			opts.insert(.caseInsensitive)
		}
		if options.contains(.backwards) {
			opts.insert(.backwards)
		}
		comparisonOptions = opts
	}

	func eachMatch(
		in text: String,
		offset: Int,
		moreToCome _: Bool,
		callback: (FindMatch, inout Bool) -> Void,
	) {
		guard !searchString.isEmpty else { return }

		let searchText = options.contains(.ignoreWhitespace)
			? normalizeWhitespace(text)
			: text

		let needle = options.contains(.ignoreWhitespace)
			? normalizeWhitespace(searchString)
			: searchString

		guard !needle.isEmpty else { return }

		var searchRange = searchText.startIndex ..< searchText.endIndex
		var stop = false

		while !stop, let range = searchText.range(of: needle, options: comparisonOptions, range: searchRange) {
			// Convert String range to byte offset
			let matchStart = offset + searchText.utf8.distance(from: searchText.startIndex, to: range.lowerBound)
			let matchEnd = offset + searchText.utf8.distance(from: searchText.startIndex, to: range.upperBound)

			// Check full-word boundary
			if options.contains(.fullWords) {
				let isWordBound = isWordBoundary(searchText, at: range.lowerBound, isStart: true)
					&& isWordBoundary(searchText, at: range.upperBound, isStart: false)
				if !isWordBound {
					// Advance past this non-word match
					if range.lowerBound < searchText.endIndex {
						searchRange = searchText.index(after: range.lowerBound) ..< searchText.endIndex
					} else {
						break
					}
					continue
				}
			}

			let match = FindMatch(range: matchStart ..< matchEnd)
			callback(match, &stop)

			// Advance search range (handle zero-length matches)
			if range.lowerBound == range.upperBound {
				if range.upperBound < searchText.endIndex {
					searchRange = searchText.index(after: range.upperBound) ..< searchText.endIndex
				} else {
					break
				}
			} else {
				searchRange = range.upperBound ..< searchText.endIndex
			}

			if options.contains(.backwards) {
				break // Only find one match when searching backwards
			}
		}
	}

	/// Normalize whitespace: collapse runs of whitespace to a single space.
	private func normalizeWhitespace(_ text: String) -> String {
		text.replacing(/\s+/, with: " ")
	}

	/// Check if position is a word boundary.
	private func isWordBoundary(_ text: String, at index: String.Index, isStart: Bool) -> Bool {
		if isStart {
			if index == text.startIndex { return true }
			let prev = text[text.index(before: index)]
			return !prev.isWordCharacter
		} else {
			if index == text.endIndex { return true }
			let next = text[index]
			return !next.isWordCharacter
		}
	}
}

private extension Character {
	var isWordCharacter: Bool {
		isLetter || isNumber || self == "_"
	}
}

// MARK: - Regex Finder

/// A regex-based search engine — equivalent to `regexp_find_t`.
struct RegexFinder: TextFinder {
	/// The compiled regex pattern.
	let regex: NSRegularExpression

	/// Search options.
	let options: FindOptions

	/// The original pattern string.
	let patternString: String

	init(pattern: String, options: FindOptions = .none) throws {
		patternString = pattern
		self.options = options

		var regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
		if options.contains(.ignoreCase) {
			regexOptions.insert(.caseInsensitive)
		}
		regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
	}

	func eachMatch(
		in text: String,
		offset: Int,
		moreToCome _: Bool,
		callback: (FindMatch, inout Bool) -> Void,
	) {
		let nsText = text as NSString
		let fullRange = NSRange(location: 0, length: nsText.length)

		let results: [NSTextCheckingResult] = if options.contains(.backwards) {
			// For backwards search, find all and take the last
			regex.matches(in: text, range: fullRange)
		} else {
			regex.matches(in: text, range: fullRange)
		}

		let orderedResults = options.contains(.backwards) ? results.reversed() : Array(results)

		var stop = false
		for result in orderedResults {
			guard !stop else { break }

			let matchRange = result.range
			guard matchRange.location != NSNotFound else { continue }

			// Convert NSRange to byte offsets
			let matchStartUTF16 = matchRange.location
			let matchEndUTF16 = matchRange.location + matchRange.length

			let matchStartIdx = String.Index(utf16Offset: matchStartUTF16, in: text)
			let matchEndIdx = String.Index(utf16Offset: matchEndUTF16, in: text)

			let matchStart = offset + text.utf8.distance(from: text.startIndex, to: matchStartIdx)
			let matchEnd = offset + text.utf8.distance(from: text.startIndex, to: matchEndIdx)

			// Extract captures
			var captures: [String: String] = [:]
			for i in 0 ..< result.numberOfRanges {
				let captureRange = result.range(at: i)
				if captureRange.location != NSNotFound {
					let value = nsText.substring(with: captureRange)
					captures["\(i)"] = value
				}
			}

			// Check full-word boundary for regex matches too
			if options.contains(.fullWords) {
				let isWordBound = isWordBoundary(text, at: matchStartIdx, isStart: true)
					&& isWordBoundary(text, at: matchEndIdx, isStart: false)
				if !isWordBound { continue }
			}

			let match = FindMatch(range: matchStart ..< matchEnd, captures: captures)
			callback(match, &stop)

			if options.contains(.backwards) {
				break // Only return one result when searching backwards
			}
		}
	}

	/// Check if position is a word boundary.
	private func isWordBoundary(_ text: String, at index: String.Index, isStart: Bool) -> Bool {
		if isStart {
			if index == text.startIndex { return true }
			let prev = text[text.index(before: index)]
			return !prev.isWordCharacter
		} else {
			if index == text.endIndex { return true }
			let next = text[index]
			return !next.isWordCharacter
		}
	}
}

// MARK: - Factory

/// Creates the appropriate TextFinder for the given options.
func makeTextFinder(pattern: String, options: FindOptions) throws -> TextFinder {
	if options.contains(.regularExpression) {
		try RegexFinder(pattern: pattern, options: options)
	} else {
		PlainTextFinder(searchString: pattern, options: options)
	}
}

// MARK: - Regex Validation

/// Validate a regex pattern string. Returns nil if valid, or an error message.
func validateRegexPattern(_ pattern: String) -> String? {
	do {
		_ = try NSRegularExpression(pattern: pattern)
		return nil
	} catch {
		return error.localizedDescription
	}
}
