#if canImport(AppKit)
import AppKit

/// Spell checking service wrapping `NSSpellChecker`.
///
/// Ports `Frameworks/ns/src/spellcheck.h/.mm`.
/// Provides spell-checking of text strings, returning byte ranges
/// of misspelled words. Supports document-specific spell tags
/// and language selection.
@MainActor
public final class SpellCheckService: Sendable {
	/// Shared singleton instance.
	public static let shared = SpellCheckService()

	private init() {}

	// MARK: - Document Tag

	/// A document-scoped spell check tag for tracking learned words.
	///
	/// Wraps `NSSpellChecker.uniqueSpellDocumentTag()` with automatic
	/// cleanup on deallocation.
	public final class DocumentTag: @unchecked Sendable {
		private var tag: Int = 0
		private var didSetup = false

		public init() {}

		deinit {
			if didSetup {
				let capturedTag = tag
				DispatchQueue.main.async {
					NSSpellChecker.shared.closeSpellDocument(withTag: capturedTag)
				}
			}
		}

		/// Get or create the underlying spell document tag.
		///
		/// Must be called on the main thread.
		@MainActor
		public func value() -> Int {
			if !didSetup {
				tag = NSSpellChecker.uniqueSpellDocumentTag()
				didSetup = true
			}
			return tag
		}
	}

	// MARK: - Spell Check Types

	/// A range of bytes in a string identified as misspelled.
	public struct MisspelledRange: Sendable, Equatable {
		/// The start index (UTF-8 offset) of the misspelled word.
		public let start: Int
		/// The end index (UTF-8 offset, exclusive) of the misspelled word.
		public let end: Int

		public init(start: Int, end: Int) {
			self.start = start
			self.end = end
		}
	}

	// MARK: - Spell Checking

	/// Check a string for misspelled words.
	///
	/// - Parameters:
	///   - text: The text to spell-check.
	///   - language: The language to use (e.g., "en_US"). Pass `nil` for auto-detect.
	///   - tag: A document tag for tracking context. Pass `nil` for a default tag.
	/// - Returns: An array of ranges identifying misspelled words.
	public func spellCheck(
		_ text: String,
		language: String? = nil,
		tag: DocumentTag? = nil,
	) -> [MisspelledRange] {
		let checker = NSSpellChecker.shared
		let tagValue = tag?.value() ?? 0
		let nsString = text as NSString

		var results: [MisspelledRange] = []
		var searchStart = 0

		while searchStart < nsString.length {
			let range = checker.checkSpelling(
				of: text,
				startingAt: searchStart,
				language: language,
				wrap: false,
				inSpellDocumentWithTag: tagValue,
				wordCount: nil,
			)

			guard range.location != NSNotFound, range.length > 0 else { break }

			// Convert NSRange (UTF-16) to byte offsets (UTF-8)
			let utf16Start = range.location
			let utf16End = range.location + range.length
			let startIdx = String.Index(utf16Offset: utf16Start, in: text)
			let endIdx = String.Index(utf16Offset: utf16End, in: text)
			let utf8Start = text.utf8.distance(from: text.startIndex, to: startIdx)
			let utf8End = text.utf8.distance(from: text.startIndex, to: endIdx)

			results.append(MisspelledRange(start: utf8Start, end: utf8End))
			searchStart = NSMaxRange(range)
		}

		return results
	}

	/// Check whether any part of a string is misspelled.
	///
	/// - Parameters:
	///   - text: The text to check.
	///   - language: The language (optional).
	///   - tag: The document tag (optional).
	/// - Returns: `true` if any word is misspelled.
	public func isMisspelled(
		_ text: String,
		language: String? = nil,
		tag: DocumentTag? = nil,
	) -> Bool {
		!spellCheck(text, language: language, tag: tag).isEmpty
	}

	/// Get spelling suggestions for a word.
	///
	/// - Parameters:
	///   - word: The misspelled word.
	///   - language: The language (optional).
	/// - Returns: An array of suggested corrections.
	public func suggestions(
		for word: String,
		language: String? = nil,
	) -> [String] {
		let checker = NSSpellChecker.shared
		let range = NSRange(location: 0, length: (word as NSString).length)
		return checker.guesses(
			forWordRange: range,
			in: word,
			language: language,
			inSpellDocumentWithTag: 0,
		) ?? []
	}

	/// Learn a word so it is no longer flagged as misspelled.
	///
	/// - Parameter word: The word to learn.
	public func learnWord(_ word: String) {
		NSSpellChecker.shared.learnWord(word)
	}

	/// Forget a previously learned word.
	///
	/// - Parameter word: The word to forget.
	public func unlearnWord(_ word: String) {
		NSSpellChecker.shared.unlearnWord(word)
	}

	/// Get the list of available spell-checking languages.
	///
	/// - Returns: Language identifiers (e.g., "en_US", "fr_FR").
	public func availableLanguages() -> [String] {
		NSSpellChecker.shared.availableLanguages
	}
}
#endif
