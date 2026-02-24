import Foundation
import Testing
@testable import TMCore

@Suite("TextUtilities")
struct TextUtilitiesTests {
	// MARK: - HTML Entity Decoding

	@Test func decodeNamedEntities() {
		#expect(TextDecode.htmlEntities("&amp;") == "&")
		#expect(TextDecode.htmlEntities("&lt;") == "<")
		#expect(TextDecode.htmlEntities("&gt;") == ">")
		#expect(TextDecode.htmlEntities("&quot;") == "\"")
		#expect(TextDecode.htmlEntities("&apos;") == "'")
		#expect(TextDecode.htmlEntities("&nbsp;") == "\u{00A0}")
	}

	@Test func decodeMultipleEntities() {
		#expect(TextDecode.htmlEntities("a &amp; b &lt; c") == "a & b < c")
	}

	@Test func decodeUnknownEntity() {
		// Unknown entities should keep the '&' and continue
		#expect(TextDecode.htmlEntities("&unknown;rest") == "&unknown;rest")
	}

	@Test func decodeNoEntities() {
		#expect(TextDecode.htmlEntities("plain text") == "plain text")
	}

	@Test func decodeIncompleteEntity() {
		#expect(TextDecode.htmlEntities("&amp without semicolon") == "&amp without semicolon")
	}

	@Test func decodeGreekLetters() {
		#expect(TextDecode.htmlEntities("&alpha;&beta;&gamma;") == "αβγ")
	}

	// MARK: - Base32/64

	@Test func base32Decode() {
		// "JBSWY3DP" → "Hello"
		let result = TextDecode.base32("JBSWY3DP")
		#expect(String(data: result, encoding: .utf8) == "Hello")
	}

	@Test func base64Decode() {
		// "SGVsbG8=" → "Hello"
		let result = TextDecode.base64("SGVsbG8=")
		#expect(String(data: result, encoding: .utf8) == "Hello")
	}

	@Test func base64DecodeIgnoresInvalidChars() {
		let result = TextDecode.base64("SGVs bG8=")
		#expect(String(data: result, encoding: .utf8) == "Hello")
	}

	// MARK: - ROT13

	@Test func rot13() {
		#expect(TextDecode.rot13("Hello") == "Uryyb")
		#expect(TextDecode.rot13("Uryyb") == "Hello")
		#expect(TextDecode.rot13("abc") == "nop")
		#expect(TextDecode.rot13("123") == "123") // non-alpha unchanged
	}

	@Test func rot13RoundTrip() {
		let original = "The Quick Brown Fox"
		#expect(TextDecode.rot13(TextDecode.rot13(original)) == original)
	}

	// MARK: - URL Decode

	@Test func urlDecode() {
		#expect(TextDecode.urlPart("hello%20world") == "hello world")
		#expect(TextDecode.urlPart("a+b") == "a b")
		#expect(TextDecode.urlPart("100%25") == "100%")
	}

	// MARK: - URL Encode

	@Test func urlEncode() {
		#expect(TextEncode.urlPart("hello world") == "hello%20world")
		#expect(TextEncode.urlPart("abc") == "abc")
		#expect(TextEncode.urlPart("a/b", excluding: "/") == "a/b")
	}

	// MARK: - Format Size

	@Test func formatSizeBytes() {
		#expect(TextUtilities.formatSize(0) == "0 bytes")
		#expect(TextUtilities.formatSize(1) == "1 byte")
		#expect(TextUtilities.formatSize(500) == "500 bytes")
		#expect(TextUtilities.formatSize(1000) == "1000 bytes")
	}

	@Test func formatSizeKiB() {
		#expect(TextUtilities.formatSize(1001) == "1.0 KiB")
		#expect(TextUtilities.formatSize(1024) == "1.0 KiB")
	}

	@Test func formatSizeMiB() {
		#expect(TextUtilities.formatSize(1_048_576) == "1.0 MiB")
	}

	@Test func formatSizeGiB() {
		let oneGiB = 1024 * 1024 * 1024
		let result = TextUtilities.formatSize(oneGiB)
		#expect(result == "1.0 GiB")
	}

	// MARK: - East Asian Width

	@Test func eastAsianWidthCJK() throws {
		// CJK Unified Ideograph
		#expect(try TextUtilities.isEastAsianWidth(#require(Unicode.Scalar(0x4E00))) == true)
		// Katakana
		#expect(try TextUtilities.isEastAsianWidth(#require(Unicode.Scalar(0x30A1))) == true)
		// Hangul
		#expect(try TextUtilities.isEastAsianWidth(#require(Unicode.Scalar(0xAC00))) == true)
	}

	@Test func eastAsianWidthASCII() throws {
		#expect(try TextUtilities.isEastAsianWidth(#require(Unicode.Scalar(0x41))) == false) // 'A'
		#expect(try TextUtilities.isEastAsianWidth(#require(Unicode.Scalar(0x7A))) == false) // 'z'
	}

	@Test func columnWidth() throws {
		#expect(TextUtilities.columnWidth(of: Unicode.Scalar("A")) == 1)
		#expect(try TextUtilities.columnWidth(of: #require(Unicode.Scalar(0x4E00))) == 2)
	}

	// MARK: - Soft Breaks

	@Test func softBreaksSimple() {
		let text = "hello world test"
		let breaks = TextUtilities.softBreaks(in: text, width: 12)
		// "hello world " is 12 chars, should break after "world "
		#expect(!breaks.isEmpty)
	}

	@Test func softBreaksNoWrap() {
		let text = "short"
		let breaks = TextUtilities.softBreaks(in: text, width: 80)
		#expect(breaks.isEmpty)
	}

	// MARK: - Opposite Case

	@Test func oppositeCase() {
		#expect(TextUtilities.oppositeCase("Hello") == "hELLO")
		#expect(TextUtilities.oppositeCase("ABC") == "abc")
		#expect(TextUtilities.oppositeCase("abc") == "ABC")
	}

	@Test func oppositeCaseMixed() {
		#expect(TextUtilities.oppositeCase("HeLLo") == "hEllO")
	}

	@Test func oppositeCaseEmpty() {
		#expect(TextUtilities.oppositeCase("") == "")
	}

	// MARK: - Character Classification

	@Test func isWordChar() {
		#expect(TextUtilities.isWordChar("a") == true)
		#expect(TextUtilities.isWordChar("Z") == true)
		#expect(TextUtilities.isWordChar("5") == true)
		#expect(TextUtilities.isWordChar("_") == true)
		#expect(TextUtilities.isWordChar(" ") == false)
		#expect(TextUtilities.isWordChar(".") == false)
	}

	@Test func isWhitespace() {
		#expect(TextUtilities.isWhitespace(" ") == true)
		#expect(TextUtilities.isWhitespace("\t") == true)
		#expect(TextUtilities.isWhitespace("\n") == true)
		#expect(TextUtilities.isWhitespace("a") == false)
	}
}

// MARK: - Indent Style Tests

@Suite("IndentStyle")
struct IndentStyleTests {
	@Test func softTabsCreate() {
		let indent = IndentStyle(tabSize: 4, indentSize: 4, softTabs: true)
		let result = indent.create(atColumn: 0, units: 1)
		#expect(result == "    ")
	}

	@Test func hardTabsCreate() {
		let indent = IndentStyle(tabSize: 4, indentSize: 4, softTabs: false)
		let result = indent.create(atColumn: 0, units: 1)
		#expect(result == "\t")
	}

	@Test func hardTabsTwoUnits() {
		let indent = IndentStyle(tabSize: 4, indentSize: 4, softTabs: false)
		let result = indent.create(atColumn: 0, units: 2)
		#expect(result == "\t\t")
	}

	@Test func softTabsAtOffset() {
		let indent = IndentStyle(tabSize: 4, indentSize: 4, softTabs: true)
		let result = indent.create(atColumn: 2, units: 1)
		// From column 2, base=0, desired=4, so 2 spaces
		#expect(result == "  ")
	}

	@Test func mixedTabsAndSpaces() {
		// indentSize != tabSize → may produce mixed tabs & spaces
		let indent = IndentStyle(tabSize: 4, indentSize: 2, softTabs: false)
		let result = indent.create(atColumn: 0, units: 1)
		#expect(result == "  ") // 2 spaces since desiredColumn=2 < tabSize=4
	}
}
