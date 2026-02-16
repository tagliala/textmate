import Testing
@testable import TMFilterList

@Suite("SymbolDescriptor")
struct SymbolDescriptorTests {
	@Test("descriptor creation")
	func creation() {
		let desc = SymbolDescriptor(name: "viewDidLoad", offset: 100, selectionString: "5")
		#expect(desc.name == "viewDidLoad")
		#expect(desc.offset == 100)
		#expect(desc.selectionString == "5")
	}

	@Test("descriptor defaults")
	func defaults() {
		let desc = SymbolDescriptor(name: "test")
		#expect(desc.offset == 0)
		#expect(desc.selectionString == "")
	}
}

@Suite("SymbolChooserItem")
struct SymbolChooserItemTests {
	@Test("item creation")
	func creation() {
		let item = SymbolChooserItem(
			symbolName: "viewDidLoad",
			section: "ViewController",
			offset: 100,
			selectionString: "5",
		)
		#expect(item.displayName == "viewDidLoad")
		#expect(item.detail == "ViewController")
		#expect(item.identifier == "5")
		#expect(item.isMatched)
	}

	@Test("update rank — fuzzy match")
	func updateRankFuzzy() {
		var item = SymbolChooserItem(symbolName: "viewDidLoad", offset: 100)
		item.updateRank(filter: "vdl")
		#expect(item.isMatched)
	}

	@Test("update rank — no match")
	func updateRankNoMatch() {
		var item = SymbolChooserItem(symbolName: "viewDidLoad", offset: 100)
		item.updateRank(filter: "zzzzz")
		#expect(!item.isMatched)
	}

	@Test("update rank — empty filter shows all")
	func emptyFilter() {
		var item = SymbolChooserItem(symbolName: "test", offset: 42)
		item.updateRank(filter: "")
		#expect(item.isMatched)
		#expect(item.sortRank == 42) // offset-based ordering
	}

	@Test("update rank — section appended to search string")
	func sectionInSearch() {
		var item = SymbolChooserItem(symbolName: "load", section: "AppDelegate", offset: 0)
		item.updateRank(filter: "appd")
		// "appd" should match "load — AppDelegate"
		#expect(item.isMatched)
	}
}

@Suite("SymbolChooserState")
struct SymbolChooserStateTests {
	private func makeChooser() -> SymbolChooserState {
		let chooser = SymbolChooserState()
		chooser.setSymbols([
			SymbolDescriptor(name: "MyClass", offset: 0, selectionString: "1"),
			SymbolDescriptor(name: "\u{2003}viewDidLoad", offset: 100, selectionString: "5"),
			SymbolDescriptor(name: "\u{2003}handleTap", offset: 200, selectionString: "10"),
			SymbolDescriptor(name: "-", offset: 0), // separator
			SymbolDescriptor(name: "OtherClass", offset: 300, selectionString: "15"),
			SymbolDescriptor(name: "\u{2003}init", offset: 350, selectionString: "17"),
		])
		return chooser
	}

	@Test("setSymbols excludes separators")
	func excludesSeparators() {
		let chooser = makeChooser()
		#expect(chooser.allSymbols.count == 5) // 6 descriptors - 1 separator
	}

	@Test("setSymbols detects sections")
	func detectsSections() {
		let chooser = makeChooser()
		// "MyClass" is top-level, has no section
		#expect(chooser.allSymbols[0].section == nil)
		// "viewDidLoad" is indented, section should be "MyClass"
		#expect(chooser.allSymbols[1].section == "MyClass")
		// "handleTap" also under "MyClass"
		#expect(chooser.allSymbols[2].section == "MyClass")
		// "OtherClass" is top-level
		#expect(chooser.allSymbols[3].section == nil)
		// "init" under "OtherClass"
		#expect(chooser.allSymbols[4].section == "OtherClass")
	}

	@Test("setSymbols strips em space prefix")
	func stripsEmSpace() {
		let chooser = makeChooser()
		#expect(chooser.allSymbols[1].symbolName == "viewDidLoad") // no leading em space
	}

	@Test("no filter shows all symbols in document order")
	func noFilter() {
		let chooser = makeChooser()
		chooser.updateFilter("")
		#expect(chooser.filteredItems.count == 5)
		#expect(chooser.filteredItems[0].symbolName == "MyClass")
		#expect(chooser.filteredItems[4].symbolName == "init")
	}

	@Test("fuzzy filter reduces results")
	func fuzzyFilter() {
		let chooser = makeChooser()
		chooser.updateFilter("vdl")
		#expect(chooser.filteredItems.count > 0)
		#expect(chooser.filteredItems[0].symbolName == "viewDidLoad")
	}

	@Test("no match returns empty")
	func noMatch() {
		let chooser = makeChooser()
		chooser.updateFilter("zzzzz")
		#expect(chooser.filteredItems.isEmpty)
	}

	@Test("best match ranks first")
	func bestMatchFirst() {
		let chooser = makeChooser()
		chooser.updateFilter("init")
		#expect(chooser.filteredItems.count > 0)
		#expect(chooser.filteredItems[0].symbolName == "init")
	}

	@Test("document name property")
	func documentName() {
		let chooser = SymbolChooserState()
		chooser.documentName = "MyFile.swift"
		#expect(chooser.documentName == "MyFile.swift")
	}

	@Test("selection string property")
	func selectionString() {
		let chooser = SymbolChooserState()
		chooser.selectionString = "42:5"
		#expect(chooser.selectionString == "42:5")
	}
}
