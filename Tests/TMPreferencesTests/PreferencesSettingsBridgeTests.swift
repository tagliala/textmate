import AppKit
import Testing
@testable import TMPreferences

/// Thread-safe store for use with `@Sendable` closures in tests.
private final class SendableStore: @unchecked Sendable {
	private var data: [String: Any] = [:]

	func get(_ key: String) -> Any? {
		data[key]
	}

	func set(_ value: Any?, for key: String) {
		data[key] = value
	}
}

@Suite("PreferencesSettingsBridge")
struct PreferencesSettingsBridgeTests {
	@Test("bridge returns nil before configuration")
	@MainActor func bridgeBeforeConfiguration() {
		let bridge = PreferencesSettingsBridge()
		#expect(bridge.getValue(for: "anyKey") == nil)
	}

	@Test("bridge round-trips values after configuration")
	@MainActor func bridgeRoundTrip() {
		let bridge = PreferencesSettingsBridge()
		let store = SendableStore()

		bridge.configure(
			getValue: { key in store.get(key) },
			setValue: { value, key in store.set(value, for: key) },
		)

		bridge.setValue("hello", for: "testKey")
		let result = bridge.getValue(for: "testKey") as? String
		#expect(result == "hello")
	}

	@Test("bridge supports multiple keys")
	@MainActor func multipleKeys() {
		let bridge = PreferencesSettingsBridge()
		let store = SendableStore()

		bridge.configure(
			getValue: { key in store.get(key) },
			setValue: { value, key in store.set(value, for: key) },
		)

		bridge.setValue(42, for: "intKey")
		bridge.setValue(true, for: "boolKey")
		bridge.setValue("text", for: "strKey")

		#expect(bridge.getValue(for: "intKey") as? Int == 42)
		#expect(bridge.getValue(for: "boolKey") as? Bool == true)
		#expect(bridge.getValue(for: "strKey") as? String == "text")
	}

	@Test("bridge overwrites existing values")
	@MainActor func overwrite() {
		let bridge = PreferencesSettingsBridge()
		let store = SendableStore()

		bridge.configure(
			getValue: { key in store.get(key) },
			setValue: { value, key in store.set(value, for: key) },
		)

		bridge.setValue("first", for: "key")
		bridge.setValue("second", for: "key")
		#expect(bridge.getValue(for: "key") as? String == "second")
	}

	@Test("bridge returns nil for unknown keys")
	@MainActor func unknownKey() {
		let bridge = PreferencesSettingsBridge()
		let store = SendableStore()
		store.set(1, for: "exists")

		bridge.configure(
			getValue: { key in store.get(key) },
			setValue: { _, _ in },
		)

		#expect(bridge.getValue(for: "exists") as? Int == 1)
		#expect(bridge.getValue(for: "missing") == nil)
	}
}
