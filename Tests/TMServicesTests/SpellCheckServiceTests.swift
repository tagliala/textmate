import Foundation
import Testing
@testable import TMServices

@Suite("SpellCheckService")
@MainActor
struct SpellCheckServiceTests {
	// MARK: - Singleton

	@Test("Shared instance is available")
	func sharedInstance() {
		let service = SpellCheckService.shared
		#expect(service != nil)
	}

	// MARK: - Document Tags

	@Test("Document tag creates unique values")
	func documentTagUniqueness() {
		let tag1 = SpellCheckService.DocumentTag()
		let tag2 = SpellCheckService.DocumentTag()
		#expect(tag1.value() != tag2.value())
	}

	// MARK: - Available Languages

	@Test("Available languages includes English")
	func availableLanguages() {
		let languages = SpellCheckService.shared.availableLanguages()
		#expect(!languages.isEmpty)
		// macOS always has English
		#expect(languages.contains(where: { $0.hasPrefix("en") }))
	}

	// MARK: - Spell Checking

	@Test("Correctly spelled word is not misspelled")
	func correctWord() {
		let result = SpellCheckService.shared.isMisspelled("hello", language: "en")
		#expect(result == false)
	}

	@Test("Misspelled word is detected")
	func misspelledWord() {
		let result = SpellCheckService.shared.isMisspelled("xyzzyplugh", language: "en")
		#expect(result == true)
	}

	@Test("Spell check returns ranges for misspelled text")
	func spellCheckRanges() {
		let text = "This is xyzzyplugh text"
		let tag = SpellCheckService.DocumentTag()
		let ranges = SpellCheckService.shared.spellCheck(text, language: "en", tag: tag)
		#expect(!ranges.isEmpty)
		// The misspelled word "xyzzyplugh" starts at byte 8
		if let first = ranges.first {
			#expect(first.start == 8)
			#expect(first.end == 18)
		}
	}

	// MARK: - Suggestions

	@Test("Suggestions for misspelled word")
	func suggestions() {
		let suggestions = SpellCheckService.shared.suggestions(for: "helllo", language: "en")
		#expect(suggestions.contains("hello"))
	}

	// MARK: - MisspelledRange

	@Test("MisspelledRange equality")
	func misspelledRangeEquality() {
		let a = SpellCheckService.MisspelledRange(start: 0, end: 5)
		let b = SpellCheckService.MisspelledRange(start: 0, end: 5)
		let c = SpellCheckService.MisspelledRange(start: 1, end: 5)
		#expect(a == b)
		#expect(a != c)
	}
}
