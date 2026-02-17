import Foundation
import Testing
@testable import TMCore

@Suite("UserDefaultsHistoryList")
struct UserDefaultsHistoryListTests {
	/// Returns a fresh UserDefaults backed by a volatile domain.
	private func ephemeralDefaults() -> UserDefaults {
		UserDefaults(suiteName: "com.textmate.tests.\(UUID().uuidString)")!
	}

	@Test("initialises empty when no stored value")
	func initEmpty() {
		let defaults = ephemeralDefaults()
		let list = UserDefaultsHistoryList(key: "test", defaults: defaults)
		#expect(list.isEmpty)
		#expect(list.count == 0)
		#expect(list.current == nil)
	}

	@Test("use adds item to front")
	func useAddsToFront() {
		let defaults = ephemeralDefaults()
		var list = UserDefaultsHistoryList(key: "test", defaults: defaults)
		list.use("alpha")
		list.use("beta")
		#expect(list.items == ["beta", "alpha"])
		#expect(list.current == "beta")
	}

	@Test("use moves existing item to front")
	func useMovesToFront() {
		let defaults = ephemeralDefaults()
		var list = UserDefaultsHistoryList(key: "test", defaults: defaults)
		list.use("a")
		list.use("b")
		list.use("c")
		list.use("a")
		#expect(list.items == ["a", "c", "b"])
	}

	@Test("capacity trims oldest items")
	func capacityTrim() {
		let defaults = ephemeralDefaults()
		var list = UserDefaultsHistoryList(key: "test", capacity: 3, defaults: defaults)
		list.use("1")
		list.use("2")
		list.use("3")
		list.use("4")
		#expect(list.count == 3)
		#expect(list.items == ["4", "3", "2"])
	}

	@Test("remove deletes item")
	func removeItem() {
		let defaults = ephemeralDefaults()
		var list = UserDefaultsHistoryList(key: "test", defaults: defaults)
		list.use("a")
		list.use("b")
		list.remove("a")
		#expect(list.items == ["b"])
	}

	@Test("removeAll clears list")
	func removeAll() {
		let defaults = ephemeralDefaults()
		var list = UserDefaultsHistoryList(key: "test", defaults: defaults)
		list.use("a")
		list.use("b")
		list.removeAll()
		#expect(list.isEmpty)
	}

	@Test("persistence round-trip through UserDefaults")
	func persistenceRoundTrip() {
		let defaults = ephemeralDefaults()
		let key = "persist-test"
		var list = UserDefaultsHistoryList(key: key, defaults: defaults)
		list.use("x")
		list.use("y")
		list.use("z")

		// Re-load from the same defaults.
		let reloaded = UserDefaultsHistoryList(key: key, defaults: defaults)
		#expect(reloaded.items == ["z", "y", "x"])
	}

	@Test("loads stored values up to capacity")
	func loadsTrimmedToCapacity() {
		let defaults = ephemeralDefaults()
		let key = "cap-test"
		defaults.set(["a", "b", "c", "d", "e"], forKey: key)

		let list = UserDefaultsHistoryList(key: key, capacity: 3, defaults: defaults)
		#expect(list.count == 3)
		#expect(list.items == ["a", "b", "c"])
	}

	@Test("duplicate use does not grow count")
	func duplicateUse() {
		let defaults = ephemeralDefaults()
		var list = UserDefaultsHistoryList(key: "test", defaults: defaults)
		list.use("a")
		list.use("a")
		list.use("a")
		#expect(list.count == 1)
	}

	@Test("capacity of 1 retains only latest")
	func capacityOne() {
		let defaults = ephemeralDefaults()
		var list = UserDefaultsHistoryList(key: "test", capacity: 1, defaults: defaults)
		list.use("a")
		list.use("b")
		#expect(list.items == ["b"])
	}
}
