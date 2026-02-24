import Foundation
import Testing
@testable import TMCore

@Suite("PlistValue")
struct PlistValueTests {
	// MARK: - Type accessors

	@Test func boolAccessor() {
		let v = PlistValue.bool(true)
		#expect(v.boolValue == true)
		#expect(v.intValue == nil)
		#expect(v.stringValue == nil)
	}

	@Test func intAccessor() {
		let v = PlistValue.int(42)
		#expect(v.intValue == 42)
		#expect(v.boolValue == nil)
	}

	@Test func stringAccessor() {
		let v = PlistValue.string("hello")
		#expect(v.stringValue == "hello")
	}

	@Test func dataAccessor() {
		let d = Data([0x01, 0x02, 0x03])
		let v = PlistValue.data(d)
		#expect(v.dataValue == d)
		#expect(v.stringValue == nil)
	}

	@Test func dateAccessor() {
		let date = Date(timeIntervalSince1970: 1000)
		let v = PlistValue.date(date)
		#expect(v.dateValue == date)
	}

	@Test func arrayAccessor() {
		let v = PlistValue.array([.int(1), .int(2)])
		#expect(v.arrayValue?.count == 2)
	}

	@Test func dictionaryAccessor() {
		let v = PlistValue.dictionary(["key": .string("val")])
		#expect(v.dictionaryValue?["key"]?.stringValue == "val")
	}

	// MARK: - isTruthy

	@Test func isTruthy() {
		#expect(PlistValue.bool(true).isTruthy == true)
		#expect(PlistValue.bool(false).isTruthy == false)
		#expect(PlistValue.int(1).isTruthy == true)
		#expect(PlistValue.int(0).isTruthy == false)
		#expect(PlistValue.string("YES").isTruthy == true)
		#expect(PlistValue.string("true").isTruthy == true)
		#expect(PlistValue.string("1").isTruthy == true)
		// In C++, only "0" and "" are falsy for strings
		#expect(PlistValue.string("NO").isTruthy == true)
		#expect(PlistValue.string("false").isTruthy == true)
		#expect(PlistValue.string("random").isTruthy == true)
		#expect(PlistValue.string("0").isTruthy == false)
		#expect(PlistValue.string("").isTruthy == false)
	}

	// MARK: - Coercion

	@Test func coercionAsBool() {
		#expect(PlistValue.bool(true).asBool() == true)
		#expect(PlistValue.int(1).asBool() == true)
		#expect(PlistValue.int(0).asBool() == false)
		// C++: convert_to(string, bool) → only "0" is false
		#expect(PlistValue.string("YES").asBool() == true)
		#expect(PlistValue.string("false").asBool() == true)
		#expect(PlistValue.string("0").asBool() == false)
	}

	@Test func coercionAsInt() {
		#expect(PlistValue.int(42).asInt() == 42)
		#expect(PlistValue.bool(true).asInt() == 1)
		#expect(PlistValue.bool(false).asInt() == 0)
		#expect(PlistValue.string("99").asInt() == 99)
		#expect(PlistValue.string("abc").asInt() == nil)
	}

	@Test func coercionAsString() {
		#expect(PlistValue.string("hello").asString() == "hello")
		#expect(PlistValue.int(42).asString() == "42")
		#expect(PlistValue.bool(true).asString() == "1")
		#expect(PlistValue.bool(false).asString() == "0")
	}

	// MARK: - Key path

	@Test func valueForKeyPath() {
		let plist = PlistValue.dictionary([
			"a": .dictionary([
				"b": .dictionary([
					"c": .string("deep"),
				]),
			]),
			"x": .int(10),
		])

		#expect(plist.valueForKeyPath("x")?.intValue == 10)
		#expect(plist.valueForKeyPath("a.b.c")?.stringValue == "deep")
		#expect(plist.valueForKeyPath("a.b")?.dictionaryValue != nil)
		#expect(plist.valueForKeyPath("nonexistent") == nil)
	}

	@Test func valueForKeyPathWithDottedKeys() {
		// C++ tries shortest segment first, so "a" is found before "a.b"
		let plist = PlistValue.dictionary([
			"a.b": .string("dotted_key"),
			"a": .dictionary([
				"b": .string("nested"),
			]),
		])

		// Shortest-first: finds "a" → recurses → finds "b" → "nested"
		#expect(plist.valueForKeyPath("a.b")?.stringValue == "nested")
	}

	@Test func valueForKeyPathWithOnlyDottedKey() {
		// When there's only a dotted key (no short match), it falls through
		let plist = PlistValue.dictionary([
			"a.b": .string("dotted_key"),
		])
		#expect(plist.valueForKeyPath("a.b")?.stringValue == "dotted_key")
	}

	// MARK: - Foundation bridge

	@Test func fromFoundation() {
		let dict: [String: Any] = [
			"name": "TextMate",
			"version": NSNumber(value: 2),
			"active": NSNumber(value: true),
			"tags": ["editor", "macOS"],
		]

		let pv = PlistValue.from(foundation: dict)
		guard case let .dictionary(d) = pv else {
			#expect(Bool(false), "Expected dictionary")
			return
		}
		#expect(d["name"]?.stringValue == "TextMate")
		#expect(d["version"]?.intValue == 2)
		#expect(d["active"]?.boolValue == true)
		#expect(d["tags"]?.arrayValue?.count == 2)
	}

	@Test func toFoundation() {
		let pv = PlistValue.dictionary([
			"key": .string("value"),
			"num": .int(42),
		])

		let obj = pv.toFoundation()
		guard let dict = obj as? [String: Any] else {
			#expect(Bool(false), "Expected dictionary")
			return
		}
		#expect(dict["key"] as? String == "value")
		#expect(dict["num"] as? Int == 42)
	}

	@Test func roundTripFoundation() {
		let original = PlistValue.dictionary([
			"string": .string("hello"),
			"int": .int(42),
			"bool": .bool(true),
			"nested": .dictionary([
				"key": .string("val"),
			]),
			"array": .array([.int(1), .int(2)]),
		])

		let foundation = original.toFoundation()
		let roundTripped = PlistValue.from(foundation: foundation)
		#expect(roundTripped == original)
	}

	// MARK: - PlistIO

	@Test func parseXMLPlist() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
			<key>name</key>
			<string>test</string>
			<key>count</key>
			<integer>5</integer>
		</dict>
		</plist>
		"""
		let data = try #require(xml.data(using: .utf8))
		let result = PlistIO.parse(data: data)
		#expect(result != nil)
		#expect(result?.dictionaryValue?["name"]?.stringValue == "test")
		#expect(result?.dictionaryValue?["count"]?.intValue == 5)
	}

	@Test func saveAndLoadFile() {
		let tmp = NSTemporaryDirectory() + "plist_test_\(UUID().uuidString).plist"
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let dict = PlistValue.dictionary([
			"greeting": .string("hello"),
			"number": .int(7),
		])
		let saved = PlistIO.save(dict, toFile: tmp)
		#expect(saved)

		let loaded = PlistIO.load(contentsOfFile: tmp)
		#expect(loaded?["greeting"]?.stringValue == "hello")
		#expect(loaded?["number"]?.intValue == 7)
	}

	// MARK: - Equality

	@Test func equality() {
		let a = PlistValue.dictionary(["x": .int(1)])
		let b = PlistValue.dictionary(["x": .int(1)])
		let c = PlistValue.dictionary(["x": .int(2)])
		#expect(a == b)
		#expect(a != c)
	}
}
