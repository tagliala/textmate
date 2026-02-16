import AppKit
import Testing
@testable import TMPreferences

@Suite("BundlesPreferencesPane")
struct BundlesPreferencesPaneTests {
	// MARK: - BundleInfo

	@Test("BundleInfo stores all properties")
	func bundleInfoProperties() {
		let date = Date()
		let info = BundlesPreferencesPane.BundleInfo(
			id: "com.test.bundle",
			name: "Test Bundle",
			category: "Languages",
			summary: "A test bundle",
			htmlURL: URL(string: "https://example.com/bundle"),
			lastUpdated: date,
			isInstalled: true,
		)
		#expect(info.id == "com.test.bundle")
		#expect(info.name == "Test Bundle")
		#expect(info.category == "Languages")
		#expect(info.summary == "A test bundle")
		#expect(info.htmlURL?.absoluteString == "https://example.com/bundle")
		#expect(info.lastUpdated == date)
		#expect(info.isInstalled == true)
	}

	@Test("BundleInfo is Identifiable by id")
	func bundleInfoIdentifiable() {
		let a = BundlesPreferencesPane.BundleInfo(id: "A", name: "A")
		let b = BundlesPreferencesPane.BundleInfo(id: "B", name: "B")
		#expect(a.id != b.id)
	}

	// MARK: - Category Extraction

	@Test("categories returns sorted unique categories")
	@MainActor func categoriesFromBundles() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "Go", category: "Languages"),
			makeBundle(name: "Ruby", category: "Languages"),
			makeBundle(name: "Git", category: "Source Control"),
			makeBundle(name: "Markdown", category: "Markup"),
		]
		let cats = pane.categories
		#expect(cats == ["Languages", "Markup", "Source Control"])
	}

	@Test("categories deduplicates")
	@MainActor func categoriesDedup() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "A", category: "X"),
			makeBundle(name: "B", category: "X"),
			makeBundle(name: "C", category: "Y"),
		]
		#expect(pane.categories == ["X", "Y"])
	}

	// MARK: - Filtering

	@Test("filteredBundles returns all when no filters active")
	@MainActor func noFilter() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "A", category: "X"),
			makeBundle(name: "B", category: "Y"),
		]
		pane.selectedCategory = nil
		pane.searchText = ""
		#expect(pane.filteredBundles.count == 2)
	}

	@Test("filteredBundles filters by category")
	@MainActor func filterByCategory() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "Go", category: "Languages"),
			makeBundle(name: "Git", category: "Source Control"),
			makeBundle(name: "Ruby", category: "Languages"),
		]
		pane.selectedCategory = "Languages"
		pane.searchText = ""
		#expect(pane.filteredBundles.count == 2)
		#expect(pane.filteredBundles.allSatisfy { $0.category == "Languages" })
	}

	@Test("filteredBundles filters by search text case insensitively")
	@MainActor func filterBySearchText() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "Go", category: "Languages"),
			makeBundle(name: "Git", category: "Source Control"),
			makeBundle(name: "Ruby", category: "Languages"),
		]
		pane.selectedCategory = nil
		pane.searchText = "g"
		let names = pane.filteredBundles.map(\.name)
		#expect(names.contains("Go"))
		#expect(names.contains("Git"))
		#expect(!names.contains("Ruby"))
	}

	@Test("filteredBundles combines category and search filters")
	@MainActor func combinedFilter() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "Go", category: "Languages"),
			makeBundle(name: "Git", category: "Source Control"),
			makeBundle(name: "Groovy", category: "Languages"),
		]
		pane.selectedCategory = "Languages"
		pane.searchText = "go"
		#expect(pane.filteredBundles.count == 1)
		#expect(pane.filteredBundles.first?.name == "Go")
	}

	@Test("filteredBundles are sorted by name")
	@MainActor func sortedByName() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "Zig", category: "X"),
			makeBundle(name: "Ada", category: "X"),
			makeBundle(name: "Lua", category: "X"),
		]
		pane.selectedCategory = nil
		pane.searchText = ""
		let names = pane.filteredBundles.map(\.name)
		#expect(names == ["Ada", "Lua", "Zig"])
	}

	@Test("empty search text shows all bundles in category")
	@MainActor func emptySearchShowsAll() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "A", category: "Cat"),
			makeBundle(name: "B", category: "Cat"),
			makeBundle(name: "C", category: "Other"),
		]
		pane.selectedCategory = "Cat"
		pane.searchText = ""
		#expect(pane.filteredBundles.count == 2)
	}

	@Test("search text with no matches returns empty")
	@MainActor func noSearchMatches() {
		let pane = BundlesPreferencesPane()
		pane.allBundles = [
			makeBundle(name: "Go", category: "X"),
		]
		pane.searchText = "zzzzz"
		#expect(pane.filteredBundles.isEmpty)
	}

	// MARK: - Helpers

	private func makeBundle(name: String, category: String) -> BundlesPreferencesPane.BundleInfo {
		BundlesPreferencesPane.BundleInfo(
			id: UUID().uuidString,
			name: name,
			category: category,
		)
	}
}
