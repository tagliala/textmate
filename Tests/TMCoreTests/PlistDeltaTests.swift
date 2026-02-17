import Foundation
import Testing
@testable import TMCore

@Suite("PlistDelta")
struct PlistDeltaTests {
	// MARK: - createDelta

	@Test func deltaNoChanges() {
		let dict: PlistDictionary = ["a": .string("hello"), "b": .int(1)]
		let delta = PlistDelta.createDelta(old: dict, new: dict)
		// No changes → delta should have isDelta key but empty changed/deleted
		#expect(delta["isDelta"]?.boolValue == true)
		let changed = delta["changed"]?.dictionaryValue ?? [:]
		let deleted = delta["deleted"]?.arrayValue ?? []
		#expect(changed.isEmpty)
		#expect(deleted.isEmpty)
	}

	@Test func deltaSimpleChange() {
		let old: PlistDictionary = ["a": .string("hello"), "b": .int(1)]
		let new: PlistDictionary = ["a": .string("world"), "b": .int(1)]
		let delta = PlistDelta.createDelta(old: old, new: new)

		#expect(delta["isDelta"]?.boolValue == true)
		let changed = delta["changed"]?.dictionaryValue ?? [:]
		#expect(changed["a"]?.stringValue == "world")
	}

	@Test func deltaDeletion() {
		let old: PlistDictionary = ["a": .string("hello"), "b": .int(1)]
		let new: PlistDictionary = ["a": .string("hello")]
		let delta = PlistDelta.createDelta(old: old, new: new)

		#expect(delta["isDelta"]?.boolValue == true)
		let deleted = delta["deleted"]?.arrayValue ?? []
		let deletedStrings = deleted.compactMap(\.stringValue)
		#expect(deletedStrings.contains("b"))
	}

	@Test func deltaAddition() {
		let old: PlistDictionary = ["a": .string("hello")]
		let new: PlistDictionary = ["a": .string("hello"), "b": .int(2)]
		let delta = PlistDelta.createDelta(old: old, new: new)

		let changed = delta["changed"]?.dictionaryValue ?? [:]
		#expect(changed["b"]?.intValue == 2)
	}

	@Test func deltaNestedChange() {
		let old: PlistDictionary = [
			"settings": .dictionary([
				"tabSize": .int(4),
				"theme": .string("dark"),
			]),
		]
		let new: PlistDictionary = [
			"settings": .dictionary([
				"tabSize": .int(3),
				"theme": .string("dark"),
			]),
		]
		let delta = PlistDelta.createDelta(old: old, new: new)
		let changed = delta["changed"]?.dictionaryValue ?? [:]
		// Nested changes should be encoded with dot-separated key paths
		let hasTabSizeChange = changed.keys
			.contains { $0.contains("tabSize") }
		#expect(hasTabSizeChange)
	}

	// MARK: - mergeDelta

	@Test func mergeEmptyDelta() {
		let base: PlistDictionary = ["a": .string("hello")]
		let delta: PlistDictionary = [
			"isDelta": .bool(true),
			"changed": .dictionary([:]),
			"deleted": .array([]),
		]
		let result = PlistDelta.mergeDelta(plists: [delta, base])
		#expect(result["a"]?.stringValue == "hello")
	}

	@Test func mergeAppliesChanges() {
		let base: PlistDictionary = ["a": .string("old"), "b": .int(1)]
		let delta: PlistDictionary = [
			"isDelta": .bool(true),
			"changed": .dictionary(["a": .string("new")]),
			"deleted": .array([]),
		]
		let result = PlistDelta.mergeDelta(plists: [delta, base])
		#expect(result["a"]?.stringValue == "new")
		#expect(result["b"]?.intValue == 1)
	}

	@Test func mergeAppliesDeletion() {
		let base: PlistDictionary = ["a": .string("hello"), "b": .int(1)]
		let delta: PlistDictionary = [
			"isDelta": .bool(true),
			"changed": .dictionary([:]),
			"deleted": .array([.string("b")]),
		]
		let result = PlistDelta.mergeDelta(plists: [delta, base])
		#expect(result["a"]?.stringValue == "hello")
		#expect(result["b"] == nil)
	}

	@Test func mergeChainOfDeltas() {
		let base: PlistDictionary = ["x": .int(1), "y": .int(2), "z": .int(3)]
		let delta1: PlistDictionary = [
			"isDelta": .bool(true),
			"changed": .dictionary(["x": .int(10)]),
			"deleted": .array([]),
		]
		let delta2: PlistDictionary = [
			"isDelta": .bool(true),
			"changed": .dictionary(["y": .int(20)]),
			"deleted": .array([.string("z")]),
		]
		let result = PlistDelta.mergeDelta(plists: [delta2, delta1, base])
		#expect(result["x"]?.intValue == 10)
		#expect(result["y"]?.intValue == 20)
		#expect(result["z"] == nil)
	}

	@Test func mergeNonDelta() {
		// If the head is not a delta, it should be returned as-is
		let dict: PlistDictionary = ["a": .string("hello")]
		let base: PlistDictionary = ["b": .int(1)]
		let result = PlistDelta.mergeDelta(plists: [dict, base])
		#expect(result["a"]?.stringValue == "hello")
		// "b" should not appear since first item is not a delta
		#expect(result["b"] == nil)
	}
}
