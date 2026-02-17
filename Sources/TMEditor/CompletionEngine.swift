import Foundation
import TMCore

// MARK: - Completion Info

/// Tracks the state of an active completion session.
///
/// Mirrors the C++ `completion_info_t` in `editor.h`: stores the buffer revision
/// at which completions were computed, the original selection ranges, the prefix
/// ranges being cycled, and the ranked suggestion list with a circular index.
public struct CompletionInfo: Sendable {
	/// Buffer revision when completions were last computed.
	public var revision: Int = 0

	/// Selections at the time completions were computed.
	public var ranges: [TextRange] = []

	/// The ranges between the word boundary and the cursor that are being
	/// replaced as the user cycles through completions.
	public var prefixRanges: [TextRange] = []

	/// The ranked list of completion suggestions (suffix portions only).
	public var suggestions: [String] = []

	/// Current index into `suggestions`. Wraps circularly.
	private var index: Int = 0

	public init() {}

	/// Whether the completion session is active (has suggestions).
	public var isEmpty: Bool {
		suggestions.isEmpty
	}

	/// The currently selected suggestion.
	public var current: String {
		guard !suggestions.isEmpty else { return "" }
		return suggestions[index]
	}

	/// Sets new suggestions and resets the index to the end (so the first
	/// `advance()` moves to index 0).
	public mutating func setSuggestions(_ newSuggestions: [String]) {
		suggestions = newSuggestions
		index = newSuggestions.count
	}

	/// Move to the next suggestion (wrapping at the end).
	public mutating func advance() {
		guard !suggestions.isEmpty else { return }
		index += 1
		if index >= suggestions.count {
			index = 0
		}
	}

	/// Move to the previous suggestion (wrapping at the beginning).
	public mutating func recede() {
		guard !suggestions.isEmpty else { return }
		if index <= 0 {
			index = suggestions.count - 1
		} else {
			index -= 1
		}
	}
}

// MARK: - Completion Engine

/// Collects word completions from the buffer and ranks them by proximity.
///
/// Port of `editor_t::completions()` from `Frameworks/editor/src/completion.cc`.
/// The engine:
/// 1. Scans the buffer for all words matching the prefix (and optionally suffix)
/// 2. Removes the current word itself from candidates
/// 3. Ranks candidates by distance from the cursor (nearest first)
/// 4. Returns the suffix portions (what needs to be inserted)
public struct CompletionEngine: Sendable {
	public init() {}

	/// Collect completions from the buffer.
	///
	/// - Parameters:
	///   - buffer: The text buffer to scan.
	///   - bow: Beginning-of-word offset.
	///   - eow: End-of-word offset.
	///   - prefix: Text from bow to cursor.
	///   - suffix: Text from cursor to eow.
	/// - Returns: Ranked list of completion suffixes (nearest matches first).
	public func completions(
		buffer: TextBuffer,
		bow: Int,
		eow: Int,
		prefix: String,
		suffix: String,
	) -> [String] {
		guard !prefix.isEmpty || !suffix.isEmpty else { return [] }

		let currentWord = buffer.substring(from: bow, to: eow)
		let searchPattern = prefix.count >= suffix.count ? prefix : suffix

		// Collect (position, fullWord) pairs from buffer.
		var candidates: [(position: Int, word: String)] = []
		collectWordsWithPrefix(
			buffer: buffer,
			pattern: searchPattern,
			prefix: prefix,
			suffix: suffix,
			excludeWord: currentWord,
			into: &candidates,
		)

		// If no suffix matches found, retry with prefix only.
		if candidates.isEmpty, !suffix.isEmpty {
			collectWordsWithPrefix(
				buffer: buffer,
				pattern: prefix,
				prefix: prefix,
				suffix: "",
				excludeWord: currentWord,
				into: &candidates,
			)
		}

		// Rank by distance from cursor (bow).
		return rankAndExtract(
			candidates: candidates,
			bow: bow,
			prefix: prefix,
			suffix: suffix,
			currentWord: currentWord,
		)
	}

	// MARK: - Word Collection

	/// Scans the buffer for all words matching the given prefix and suffix.
	private func collectWordsWithPrefix(
		buffer: TextBuffer,
		pattern: String,
		prefix: String,
		suffix: String,
		excludeWord: String,
		into results: inout [(position: Int, word: String)],
	) {
		let patternBytes = Array(pattern.utf8)
		let bufferSize = buffer.size
		guard !patternBytes.isEmpty, bufferSize > 0 else { return }

		// Scan the buffer for all occurrences of the pattern.
		var searchStart = 0
		while searchStart <= bufferSize - patternBytes.count {
			// Find next occurrence of pattern.
			guard let matchOffset = findBytes(patternBytes, in: buffer, from: searchStart) else {
				break
			}

			// Extend to full word boundaries.
			let wordStart = wordBoundaryLeft(in: buffer, from: matchOffset)
			let wordEnd = wordBoundaryRight(in: buffer, from: matchOffset)

			let word = buffer.substring(from: wordStart, to: wordEnd)

			// Check prefix + suffix match and not the excluded word.
			let hasPrefix = prefix.isEmpty
				|| (prefix.count < word.count && word.hasPrefix(prefix))
			let hasSuffix = suffix.isEmpty
				|| (suffix.count < word.count && word.hasSuffix(suffix))

			if hasPrefix, hasSuffix, word != excludeWord {
				results.append((wordStart, word))
			}

			// Move past this match to find more.
			searchStart = wordEnd > matchOffset ? wordEnd : matchOffset + 1
		}
	}

	/// Find bytes in buffer starting from offset.
	private func findBytes(_ pattern: [UInt8], in buffer: TextBuffer, from start: Int) -> Int? {
		let size = buffer.size
		guard pattern.count <= size - start else { return nil }
		outer: for i in start ... (size - pattern.count) {
			for j in 0 ..< pattern.count {
				if buffer[i + j] != pattern[j] {
					continue outer
				}
			}
			return i
		}
		return nil
	}

	/// Find the start of the word containing offset.
	private func wordBoundaryLeft(in buffer: TextBuffer, from offset: Int) -> Int {
		var pos = offset
		while pos > 0, isWordByte(buffer[pos - 1]) {
			pos -= 1
		}
		return pos
	}

	/// Find the end of the word containing offset.
	private func wordBoundaryRight(in buffer: TextBuffer, from offset: Int) -> Int {
		var pos = offset
		while pos < buffer.size, isWordByte(buffer[pos]) {
			pos += 1
		}
		return pos
	}

	/// Whether a byte is a word character (letter, digit, underscore, or high byte).
	private func isWordByte(_ byte: UInt8) -> Bool {
		(byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
			|| (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
			|| (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
			|| byte == UInt8(ascii: "_")
			|| byte >= 0x80
	}

	// MARK: - Ranking

	/// Rank candidates by distance from cursor and extract suffix portions.
	private func rankAndExtract(
		candidates: [(position: Int, word: String)],
		bow: Int,
		prefix: String,
		suffix: String,
		currentWord: String,
	) -> [String] {
		// Build a map of (suffix → closest distance).
		var ranked: [String: Int] = [:]

		for (position, word) in candidates {
			guard word != currentWord else { continue }
			let hasPrefix = prefix.isEmpty
				|| (prefix.count < word.count && word.hasPrefix(prefix))
			guard hasPrefix else { continue }

			let hasSuffix = !suffix.isEmpty
				&& suffix.count < word.count
				&& word.hasSuffix(suffix)

			// Distance: how far the candidate is from the cursor position.
			let rank: Int = if bow <= position {
				position - bow
			} else {
				bow - (position + word.utf8.count)
			}

			// Extract the suffix portion to insert.
			let suffixTrimLength = hasSuffix ? suffix.count : 0
			let startIndex = word.index(word.startIndex, offsetBy: prefix.count)
			let endIndex = word.index(word.endIndex, offsetBy: -suffixTrimLength)
			guard startIndex < endIndex else { continue }
			let insertionText = String(word[startIndex ..< endIndex])

			if let existing = ranked[insertionText] {
				ranked[insertionText] = min(existing, rank)
			} else {
				ranked[insertionText] = rank
			}
		}

		// Sort by distance (nearest first).
		let sorted = ranked.sorted { $0.value < $1.value }
		return sorted.map(\.key)
	}
}
