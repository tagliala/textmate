import Foundation
import Testing
@testable import TMCore

@Suite("PlistSerializer")
struct PlistSerializerTests {
	@Test func serializeString() {
		let result = PlistSerializer.serialize(.string("hello"))
		#expect(result == "\"hello\"")
	}

	@Test func serializeStringSingleQuote() {
		let result = PlistSerializer.serialize(.string("hello"), options: .preferSingleQuotedStrings)
		#expect(result == "'hello'")
	}

	@Test func serializeEmptyString() {
		let result = PlistSerializer.serialize(.string(""))
		#expect(result == "\"\"")
	}

	@Test func serializeEmptyStringSingleQuote() {
		let result = PlistSerializer.serialize(.string(""), options: .preferSingleQuotedStrings)
		#expect(result == "''")
	}

	@Test func serializeBool() {
		#expect(PlistSerializer.serialize(.bool(true)) == ":true")
		#expect(PlistSerializer.serialize(.bool(false)) == ":false")
	}

	@Test func serializeInt() {
		#expect(PlistSerializer.serialize(.int(42)) == "42")
		#expect(PlistSerializer.serialize(.int(-7)) == "-7")
	}

	@Test func serializeSimpleArray() {
		let arr = PlistValue.array([.int(1), .int(2), .int(3)])
		let result = PlistSerializer.serialize(arr)
		#expect(result.contains("1"))
		#expect(result.contains("2"))
		#expect(result.contains("3"))
		#expect(result.hasPrefix("("))
		#expect(result.hasSuffix(")"))
	}

	@Test func serializeSimpleDictionary() {
		let dict = PlistValue.dictionary(["name": .string("test")])
		let result = PlistSerializer.serialize(dict)
		#expect(result.contains("name"))
		#expect(result.contains("test"))
		#expect(result.hasPrefix("{"))
		#expect(result.hasSuffix("}"))
	}

	@Test func serializeNestedDictionary() {
		let value = PlistValue.dictionary([
			"outer": .dictionary([
				"inner": .string("value"),
			]),
		])
		let result = PlistSerializer.serialize(value)
		#expect(result.contains("outer"))
		#expect(result.contains("inner"))
		#expect(result.contains("value"))
	}

	@Test func serializeData() {
		let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
		let result = PlistSerializer.serialize(.data(data))
		#expect(result.hasPrefix("<"))
		#expect(result.hasSuffix(">"))
		#expect(result.contains("DEAD"))
		#expect(result.contains("BEEF"))
	}

	@Test func singleLineOption() {
		let dict = PlistValue.dictionary(["a": .int(1), "b": .int(2)])
		let result = PlistSerializer.serialize(dict, options: .singleLine)
		#expect(!result.contains("\n"))
	}

	@Test func keySortCustomOrder() throws {
		let dict = PlistValue.dictionary([
			"zebra": .int(1),
			"alpha": .int(2),
			"beta": .int(3),
		])
		let sortOrder = ["beta", "alpha", "zebra"]
		let result = PlistSerializer.serialize(dict, keySortOrder: sortOrder)

		// beta should appear before alpha in the output
		let betaPos = try #require(result.range(of: "beta")?.lowerBound)
		let alphaPos = try #require(result.range(of: "alpha")?.lowerBound)
		#expect(betaPos < alphaPos)
	}

	@Test func escapeSpecialCharacters() {
		let value = PlistValue.string("line1\nline2\ttab")
		let result = PlistSerializer.serialize(value)
		// Should escape newlines/tabs in the output
		#expect(result.contains("\\n") || result.contains("\\012"))
		#expect(result.contains("\\t") || result.contains("\\011"))
	}
}
