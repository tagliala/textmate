import Testing
@testable import TMPreferences

private typealias EnvironmentVariable = VariablesPreferencesPane.EnvironmentVariable

@Suite("EnvironmentVariable")
struct EnvironmentVariableTests {
	// MARK: - Initialization

	@Test("default initializer creates enabled empty variable")
	func defaultInit() {
		let v = EnvironmentVariable()
		#expect(v.enabled == true)
		#expect(v.name == "")
		#expect(v.value == "")
	}

	@Test("custom initializer sets all properties")
	func customInit() {
		let v = EnvironmentVariable(enabled: false, name: "PATH", value: "/usr/bin")
		#expect(v.enabled == false)
		#expect(v.name == "PATH")
		#expect(v.value == "/usr/bin")
	}

	// MARK: - Dictionary Representation

	@Test("dictionaryRepresentation encodes all fields")
	func toDict() {
		let v = EnvironmentVariable(enabled: true, name: "TM_FULLNAME", value: "John Doe")
		let dict = v.dictionaryRepresentation
		#expect(dict["enabled"] as? Bool == true)
		#expect(dict["name"] as? String == "TM_FULLNAME")
		#expect(dict["value"] as? String == "John Doe")
	}

	@Test("dictionaryRepresentation encodes disabled state")
	func toDictDisabled() {
		let v = EnvironmentVariable(enabled: false, name: "FOO", value: "bar")
		let dict = v.dictionaryRepresentation
		#expect(dict["enabled"] as? Bool == false)
	}

	// MARK: - Dictionary Initialization

	@Test("init from valid dictionary succeeds")
	func fromValidDict() {
		let dict: [String: Any] = ["enabled": true, "name": "FOO", "value": "bar"]
		let v = EnvironmentVariable(dictionary: dict)
		#expect(v != nil)
		#expect(v?.enabled == true)
		#expect(v?.name == "FOO")
		#expect(v?.value == "bar")
	}

	@Test("init from dictionary without enabled defaults to false")
	func fromDictWithoutEnabled() {
		let dict: [String: Any] = ["name": "FOO", "value": "bar"]
		let v = EnvironmentVariable(dictionary: dict)
		#expect(v != nil)
		#expect(v?.enabled == false)
	}

	@Test("init from dictionary without name returns nil")
	func fromDictWithoutName() {
		let dict: [String: Any] = ["value": "bar"]
		let v = EnvironmentVariable(dictionary: dict)
		#expect(v == nil)
	}

	@Test("init from dictionary without value returns nil")
	func fromDictWithoutValue() {
		let dict: [String: Any] = ["name": "FOO"]
		let v = EnvironmentVariable(dictionary: dict)
		#expect(v == nil)
	}

	@Test("init from empty dictionary returns nil")
	func fromEmptyDict() {
		let v = EnvironmentVariable(dictionary: [:])
		#expect(v == nil)
	}

	// MARK: - Round-trip

	@Test("dictionary round-trip preserves values")
	func roundTrip() {
		let original = EnvironmentVariable(enabled: true, name: "TM_SCM", value: "git")
		let dict = original.dictionaryRepresentation
		let restored = EnvironmentVariable(dictionary: dict)
		#expect(restored == original)
	}

	@Test("disabled variable round-trips correctly")
	func roundTripDisabled() {
		let original = EnvironmentVariable(enabled: false, name: "EDITOR", value: "mate -w")
		let dict = original.dictionaryRepresentation
		let restored = EnvironmentVariable(dictionary: dict)
		#expect(restored == original)
	}

	// MARK: - Equatable

	@Test("equal variables compare as equal")
	func equality() {
		let a = EnvironmentVariable(enabled: true, name: "X", value: "Y")
		let b = EnvironmentVariable(enabled: true, name: "X", value: "Y")
		#expect(a == b)
	}

	@Test("variables with different names compare as not equal")
	func inequalityName() {
		let a = EnvironmentVariable(enabled: true, name: "X", value: "Y")
		let b = EnvironmentVariable(enabled: true, name: "Z", value: "Y")
		#expect(a != b)
	}

	@Test("variables with different values compare as not equal")
	func inequalityValue() {
		let a = EnvironmentVariable(enabled: true, name: "X", value: "Y")
		let b = EnvironmentVariable(enabled: true, name: "X", value: "Z")
		#expect(a != b)
	}

	@Test("variables with different enabled state compare as not equal")
	func inequalityEnabled() {
		let a = EnvironmentVariable(enabled: true, name: "X", value: "Y")
		let b = EnvironmentVariable(enabled: false, name: "X", value: "Y")
		#expect(a != b)
	}
}
