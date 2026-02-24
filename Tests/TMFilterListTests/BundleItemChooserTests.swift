import Testing
@testable import TMFilterList

@Suite("BundleSearchSource")
struct BundleSearchSourceTests {
	@Test("individual source flags")
	func individualFlags() {
		#expect(BundleSearchSource.actionItems.rawValue == 1)
		#expect(BundleSearchSource.settingsItems.rawValue == 2)
		#expect(BundleSearchSource.grammarItems.rawValue == 4)
		#expect(BundleSearchSource.themeItems.rawValue == 8)
		#expect(BundleSearchSource.dragCommandItems.rawValue == 16)
		#expect(BundleSearchSource.menuItems.rawValue == 32)
		#expect(BundleSearchSource.keyBindingItems.rawValue == 64)
	}

	@Test("composite sources")
	func compositeSources() {
		let actions = BundleSearchSource.actions
		#expect(actions.contains(.actionItems))
		#expect(actions.contains(.menuItems))
		#expect(actions.contains(.keyBindingItems))
		#expect(!actions.contains(.settingsItems))
	}

	@Test("all source contains everything")
	func allSource() {
		let all = BundleSearchSource.all
		#expect(all.contains(.actionItems))
		#expect(all.contains(.settingsItems))
		#expect(all.contains(.grammarItems))
		#expect(all.contains(.themeItems))
		#expect(all.contains(.dragCommandItems))
		#expect(all.contains(.menuItems))
		#expect(all.contains(.keyBindingItems))
	}
}

@Suite("BundleChooserItem")
struct BundleChooserItemTests {
	@Test("item creation")
	func creation() {
		let item = BundleChooserItem(
			name: "Run Script",
			bundleName: "Source",
			itemIdentifier: "UUID-123",
			tabTrigger: "run",
			keyEquivalent: "⌘R",
			kind: "Command",
		)
		#expect(item.displayName == "Run Script")
		#expect(item.detail == "Source")
		#expect(item.identifier == "UUID-123")
		#expect(item.tabTrigger == "run")
		#expect(item.keyEquivalent == "⌘R")
		#expect(item.isMatched)
	}

	@Test("update rank by title — fuzzy match")
	func updateRankByTitle() {
		var item = BundleChooserItem(
			name: "Comment Line / Selection",
			bundleName: "Source",
			itemIdentifier: "UUID-1",
		)
		item.updateRank(filter: "comment", field: .title)
		#expect(item.isMatched)
		#expect(!item.nameCoverRanges.isEmpty)
	}

	@Test("update rank by title — no match")
	func updateRankByTitleNoMatch() {
		var item = BundleChooserItem(
			name: "Run Script",
			bundleName: "Source",
			itemIdentifier: "UUID-1",
		)
		item.updateRank(filter: "zzzzz", field: .title)
		#expect(!item.isMatched)
	}

	@Test("update rank by key equivalent")
	func updateRankByKeyEquiv() {
		var item = BundleChooserItem(
			name: "Run",
			bundleName: "Source",
			itemIdentifier: "UUID-1",
			keyEquivalent: "⌘R",
		)
		item.updateRank(filter: "⌘R", field: .keyEquivalent)
		#expect(item.isMatched)
	}

	@Test("update rank by key equivalent — no key")
	func updateRankByKeyEquivNoKey() {
		var item = BundleChooserItem(
			name: "Run",
			bundleName: "Source",
			itemIdentifier: "UUID-1",
			keyEquivalent: nil,
		)
		item.updateRank(filter: "⌘R", field: .keyEquivalent)
		#expect(!item.isMatched)
	}

	@Test("update rank by tab trigger")
	func updateRankByTabTrigger() {
		var item = BundleChooserItem(
			name: "For Loop",
			bundleName: "C",
			itemIdentifier: "UUID-1",
			tabTrigger: "for",
		)
		item.updateRank(filter: "for", field: .tabTrigger)
		#expect(item.isMatched)
	}

	@Test("empty filter matches all")
	func emptyFilterMatchesAll() {
		var item = BundleChooserItem(
			name: "Any Item",
			bundleName: "Bundle",
			itemIdentifier: "UUID-1",
		)
		item.updateRank(filter: "", field: .title)
		#expect(item.isMatched)
	}

	@Test("eclipsed property")
	func eclipsed() {
		let item = BundleChooserItem(
			name: "Item",
			bundleName: "Bundle",
			itemIdentifier: "UUID-1",
			isEclipsed: true,
		)
		#expect(item.isEclipsed)
	}

	@Test("search field raw values")
	func searchFieldValues() {
		#expect(BundleChooserItem.SearchField.title.rawValue == 0)
		#expect(BundleChooserItem.SearchField.keyEquivalent.rawValue == 1)
		#expect(BundleChooserItem.SearchField.tabTrigger.rawValue == 2)
		#expect(BundleChooserItem.SearchField.semanticClass.rawValue == 3)
		#expect(BundleChooserItem.SearchField.scopeSelector.rawValue == 4)
	}
}

@Suite("BundleItemChooserState")
struct BundleItemChooserStateTests {
	private func makeChooser() -> BundleItemChooserState {
		let chooser = BundleItemChooserState()
		chooser.populateItems([
			BundleItemDescriptor(
				name: "Comment Line",
				bundleName: "Source",
				identifier: "UUID-A",
				tabTrigger: nil,
				keyEquivalent: "⌘/",
				source: .actionItems,
			),
			BundleItemDescriptor(
				name: "Run Script",
				bundleName: "Source",
				identifier: "UUID-B",
				tabTrigger: "run",
				source: .actionItems,
			),
			BundleItemDescriptor(
				name: "Ruby",
				bundleName: "Grammars",
				identifier: "UUID-C",
				kind: "Grammar",
				source: .grammarItems,
			),
			BundleItemDescriptor(
				name: "Monokai",
				bundleName: "Themes",
				identifier: "UUID-D",
				kind: "Theme",
				source: .themeItems,
			),
			BundleItemDescriptor(
				name: "Show Completions",
				bundleName: "Text",
				identifier: "UUID-E",
				keyEquivalent: "⎋",
				source: .menuItems,
			),
		])
		return chooser
	}

	@Test("no filter shows all items in source")
	func noFilter() {
		let chooser = makeChooser()
		chooser.sources = .all
		chooser.updateFilter("")
		#expect(chooser.filteredItems.count == 5)
	}

	@Test("filter by title")
	func filterByTitle() {
		let chooser = makeChooser()
		chooser.sources = .all
		chooser.updateFilter("comment")
		#expect(chooser.filteredItems.count > 0)
		#expect(chooser.filteredItems[0].name == "Comment Line")
	}

	@Test("filter by source — actions only")
	func filterBySourceActions() {
		let chooser = makeChooser()
		chooser.sources = .actions
		chooser.updateFilter("")
		// Should have action items + menu items + key binding items
		// From our data: Comment Line (action), Run Script (action), Show Completions (menu)
		#expect(chooser.filteredItems.count == 3)
	}

	@Test("filter by source — other")
	func filterBySourceOther() {
		let chooser = makeChooser()
		chooser.sources = .other
		chooser.updateFilter("")
		// Grammar + Theme
		#expect(chooser.filteredItems.count == 2)
	}

	@Test("set search field and refilter")
	func setSearchField() {
		let chooser = makeChooser()
		chooser.sources = .all
		chooser.updateFilter("run")
		chooser.setSearchField(.tabTrigger)
		// Only "Run Script" has tab trigger "run"
		#expect(chooser.filteredItems.count == 1)
		#expect(chooser.filteredItems[0].name == "Run Script")
	}

	@Test("learn abbreviation")
	func learnAbbreviation() {
		let chooser = makeChooser()
		chooser.updateFilter("cl")
		chooser.learnSelection(identifier: "UUID-A")
		let bindings = chooser.abbreviations.strings(for: "cl")
		#expect(bindings.contains("UUID-A"))
	}

	@Test("no learn on non-title field")
	func noLearnOnNonTitleField() {
		let chooser = makeChooser()
		chooser.searchField = .tabTrigger
		chooser.updateFilter("run")
		chooser.learnSelection(identifier: "UUID-B")
		// Should not learn since field != title
		let bindings = chooser.abbreviations.strings(for: "run")
		#expect(!bindings.contains("UUID-B"))
	}
}

@Suite("BundleItemDescriptor")
struct BundleItemDescriptorTests {
	@Test("descriptor creation")
	func creation() {
		let desc = BundleItemDescriptor(
			name: "Test",
			bundleName: "Bundle",
			identifier: "UUID",
			tabTrigger: "tt",
			keyEquivalent: "⌘T",
			kind: "Snippet",
			source: .actionItems,
			isEclipsed: false,
		)
		#expect(desc.name == "Test")
		#expect(desc.bundleName == "Bundle")
		#expect(desc.identifier == "UUID")
		#expect(desc.tabTrigger == "tt")
		#expect(desc.keyEquivalent == "⌘T")
		#expect(desc.kind == "Snippet")
		#expect(!desc.isEclipsed)
	}
}
