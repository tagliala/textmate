import Foundation
import Testing
@testable import TMFilterList

@Suite("AbbreviationStore")
struct AbbreviationStoreTests {
	private func makeStore() -> AbbreviationStore {
		// Use unique names to avoid cross-test interference
		let name = "TestAbbreviations_\(UUID().uuidString)"
		return AbbreviationStore.named(name)
	}

	@Test("empty store returns no strings")
	func emptyStore() {
		let store = makeStore()
		#expect(store.strings(for: "anything").isEmpty)
		#expect(store.count == 0)
	}

	@Test("learn and retrieve abbreviation")
	func learnAndRetrieve() {
		let store = makeStore()
		store.learn(abbreviation: "vc", for: "/src/ViewController.swift")
		let results = store.strings(for: "vc")
		#expect(results.count == 1)
		#expect(results[0] == "/src/ViewController.swift")
	}

	@Test("MRU ordering — latest learned is first")
	func mruOrdering() {
		let store = makeStore()
		store.learn(abbreviation: "vc", for: "/src/ViewA.swift")
		store.learn(abbreviation: "vc", for: "/src/ViewB.swift")
		let results = store.strings(for: "vc")
		#expect(results.count == 2)
		#expect(results[0] == "/src/ViewB.swift")
		#expect(results[1] == "/src/ViewA.swift")
	}

	@Test("re-learning moves to front")
	func relearningMoves() {
		let store = makeStore()
		store.learn(abbreviation: "vc", for: "/src/A.swift")
		store.learn(abbreviation: "vc", for: "/src/B.swift")
		store.learn(abbreviation: "vc", for: "/src/A.swift") // re-learn A
		let results = store.strings(for: "vc")
		#expect(results.count == 2)
		#expect(results[0] == "/src/A.swift") // A is now first
	}

	@Test("prefix matching returns results")
	func prefixMatching() {
		let store = makeStore()
		store.learn(abbreviation: "viewc", for: "/src/ViewController.swift")
		// "view" is a prefix of "viewc"
		let results = store.strings(for: "view")
		#expect(results.count == 1)
		#expect(results[0] == "/src/ViewController.swift")
	}

	@Test("exact matches before prefix matches")
	func exactBeforePrefix() {
		let store = makeStore()
		store.learn(abbreviation: "vc", for: "/src/Exact.swift")
		store.learn(abbreviation: "vcfoo", for: "/src/Prefix.swift")
		let results = store.strings(for: "vc")
		#expect(results.count == 2)
		#expect(results[0] == "/src/Exact.swift") // exact first
		#expect(results[1] == "/src/Prefix.swift") // prefix second
	}

	@Test("max entries cap")
	func maxEntriesCap() {
		let store = makeStore()
		for i in 0 ..< 60 {
			store.learn(abbreviation: "key\(i)", for: "value\(i)")
		}
		#expect(store.count == AbbreviationStore.maxEntries) // 50
	}

	@Test("clear removes all")
	func clearRemovesAll() {
		let store = makeStore()
		store.learn(abbreviation: "a", for: "b")
		store.learn(abbreviation: "c", for: "d")
		store.clear()
		#expect(store.count == 0)
		#expect(store.strings(for: "a").isEmpty)
	}

	@Test("named returns same instance")
	func namedSameInstance() {
		let name = "TestSingleton_\(UUID().uuidString)"
		let a = AbbreviationStore.named(name)
		let b = AbbreviationStore.named(name)
		#expect(a === b)
	}

	@Test("rankBoost returns boost for known candidate")
	func rankBoostKnown() throws {
		let store = makeStore()
		store.learn(abbreviation: "vc", for: "/src/File.swift")
		let boost = store.rankBoost(abbreviation: "vc", candidate: "/src/File.swift")
		#expect(boost != nil)
		#expect(try #require(boost) >= 2.0)
	}

	@Test("rankBoost returns nil for unknown candidate")
	func rankBoostUnknown() {
		let store = makeStore()
		let boost = store.rankBoost(abbreviation: "vc", candidate: "/src/Unknown.swift")
		#expect(boost == nil)
	}

	@Test("allBindings returns all entries")
	func allBindingsReturnsAll() {
		let store = makeStore()
		store.learn(abbreviation: "a", for: "1")
		store.learn(abbreviation: "b", for: "2")
		let all = store.allBindings
		#expect(all.count == 2)
	}
}
