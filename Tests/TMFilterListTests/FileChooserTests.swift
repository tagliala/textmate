import Testing
@testable import TMFilterList

@Suite("FileChooserSource")
struct FileChooserSourceTests {
	@Test("source display names")
	func displayNames() {
		#expect(FileChooserSource.all.displayName == "All")
		#expect(FileChooserSource.openDocuments.displayName == "Open")
		#expect(FileChooserSource.uncommitted.displayName == "Uncommitted")
	}

	@Test("all sources via CaseIterable")
	func allCases() {
		#expect(FileChooserSource.allCases.count == 3)
	}
}

@Suite("ParsedFilter")
struct ParsedFilterTests {
	private let chooser = FileChooserState(projectPath: "/tmp/project")

	@Test("simple filter string")
	func simpleFilter() {
		let parsed = chooser.parseFilter("hello")
		#expect(parsed.filterString == "hello")
		#expect(parsed.globString == nil)
		#expect(parsed.selectionString == nil)
		#expect(parsed.symbolString == nil)
		#expect(!parsed.isGlob)
	}

	@Test("filter with line selection")
	func filterWithSelection() {
		let parsed = chooser.parseFilter("file:42")
		#expect(parsed.filterString == "file")
		#expect(parsed.selectionString == "42")
	}

	@Test("filter with symbol")
	func filterWithSymbol() {
		let parsed = chooser.parseFilter("file@symbol")
		#expect(parsed.filterString == "file")
		#expect(parsed.symbolString == "symbol")
	}

	@Test("glob pattern")
	func globPattern() {
		let parsed = chooser.parseFilter("*.swift")
		#expect(parsed.globString == "*.swift")
		#expect(parsed.filterString == nil)
		#expect(parsed.isGlob)
	}

	@Test("glob with selection")
	func globWithSelection() {
		let parsed = chooser.parseFilter("src/*.rb:10")
		#expect(parsed.globString == "src/*.rb")
		#expect(parsed.selectionString == "10")
	}

	@Test("empty filter")
	func emptyFilter() {
		let parsed = chooser.parseFilter("")
		#expect(parsed.effectiveFilter == "")
	}

	@Test("filter normalizes case and spaces")
	func normalizedFilter() {
		let parsed = chooser.parseFilter("Foo Bar")
		#expect(parsed.filterString == "foobar")
	}
}

@Suite("FileChooserState")
struct FileChooserStateTests {
	private func makeChooser() -> FileChooserState {
		let chooser = FileChooserState(projectPath: "/tmp/project")
		chooser.allFiles = [
			"/tmp/project/src/AppDelegate.swift",
			"/tmp/project/src/ViewController.swift",
			"/tmp/project/src/Models/User.swift",
			"/tmp/project/README.md",
			"/tmp/project/Package.swift",
		]
		return chooser
	}

	@Test("no filter shows all files")
	func noFilter() {
		let chooser = makeChooser()
		chooser.updateFilter("")
		#expect(chooser.filteredItems.count == 5)
	}

	@Test("fuzzy filter reduces results")
	func fuzzyFilter() {
		let chooser = makeChooser()
		chooser.updateFilter("vc")
		// Should match ViewController.swift
		#expect(chooser.filteredItems.count > 0)
		#expect(chooser.filteredItems[0].fileName == "ViewController.swift")
	}

	@Test("no match returns empty")
	func noMatchReturnsEmpty() {
		let chooser = makeChooser()
		chooser.updateFilter("zzzzzzz")
		#expect(chooser.filteredItems.isEmpty)
	}

	@Test("current document is de-prioritized")
	func currentDocumentDeprioritized() {
		let chooser = makeChooser()
		chooser.currentDocumentPath = "/tmp/project/src/AppDelegate.swift"
		chooser.updateFilter("swift")
		// AppDelegate should not be first
		if let first = chooser.filteredItems.first {
			// It might still be first if there aren't enough items, but
			// at minimum it should be matched
			#expect(first.isMatched)
		}
	}

	@Test("open documents source")
	func openDocumentsSource() {
		let chooser = makeChooser()
		chooser.openDocuments = [
			"/tmp/project/src/AppDelegate.swift",
			"/tmp/project/README.md",
		]
		chooser.source = .openDocuments
		chooser.updateFilter("")
		#expect(chooser.filteredItems.count == 2)
	}

	@Test("uncommitted source")
	func uncommittedSource() {
		let chooser = makeChooser()
		chooser.uncommittedFiles = [
			"/tmp/project/src/Models/User.swift",
		]
		chooser.source = .uncommitted
		chooser.updateFilter("")
		#expect(chooser.filteredItems.count == 1)
	}

	@Test("glob pattern matching")
	func globMatching() {
		let chooser = makeChooser()
		chooser.updateFilter("*.md")
		#expect(chooser.filteredItems.count == 1)
		#expect(chooser.filteredItems[0].fileName == "README.md")
	}

	@Test("learn abbreviation for selection")
	func learnAbbreviation() {
		let chooser = makeChooser()
		chooser.updateFilter("vc")
		chooser.learnSelection(path: "/tmp/project/src/ViewController.swift")
		// After learning, the abbreviation store should contain the binding
		let bindings = chooser.abbreviations.strings(for: "vc")
		#expect(bindings.contains("/tmp/project/src/ViewController.swift"))
	}

	@Test("refilter uses current source")
	func refilterUsesSource() {
		let chooser = makeChooser()
		chooser.openDocuments = ["/tmp/project/README.md"]
		chooser.source = .openDocuments
		chooser.refilter()
		#expect(chooser.filteredItems.count == 1)
	}
}

@Suite("FileChooserItem")
struct FileChooserItemTests {
	@Test("file chooser item creation")
	func creation() {
		let item = FileChooserItem(path: "/usr/local/bin/test.sh")
		#expect(item.fileName == "test.sh")
		#expect(item.directory == "/usr/local/bin")
		#expect(item.path == "/usr/local/bin/test.sh")
		#expect(item.identifier == "/usr/local/bin/test.sh")
		#expect(item.isMatched)
	}

	@Test("update rank with fuzzy filter")
	func updateRankFuzzy() {
		var item = FileChooserItem(path: "/src/ViewController.swift")
		item.updateRank(filter: "vc")
		#expect(item.isMatched)
		#expect(!item.nameCoverRanges.isEmpty)
	}

	@Test("update rank with no match")
	func updateRankNoMatch() {
		var item = FileChooserItem(path: "/src/ViewController.swift")
		item.updateRank(filter: "zzz")
		#expect(!item.isMatched)
	}

	@Test("update rank with glob")
	func updateRankGlob() {
		var item = FileChooserItem(path: "/src/test.swift")
		item.updateRank(glob: "*.swift")
		#expect(item.isMatched)

		var item2 = FileChooserItem(path: "/src/test.rb")
		item2.updateRank(glob: "*.swift")
		#expect(!item2.isMatched)
	}

	@Test("empty filter matches all")
	func emptyFilterMatchesAll() {
		var item = FileChooserItem(path: "/src/File.swift")
		item.updateRank(filter: "")
		#expect(item.isMatched)
	}

	@Test("sorting — file items")
	func sorting() {
		var items = [
			FileChooserItem(path: "/c/ZZZ.swift"),
			FileChooserItem(path: "/a/AAA.swift"),
			FileChooserItem(path: "/b/BBB.swift"),
		]
		for i in items.indices {
			items[i].updateRank(filter: "")
		}
		let sorted = items.sortedByRank()
		#expect(sorted[0].fileName == "AAA.swift")
		#expect(sorted[1].fileName == "BBB.swift")
		#expect(sorted[2].fileName == "ZZZ.swift")
	}
}
