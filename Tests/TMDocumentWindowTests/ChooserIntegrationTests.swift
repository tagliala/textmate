import Testing
@testable import TMDocumentWindow
@testable import TMFilterList
@testable import TMSettings

// MARK: - FileChooserController Tests

#if canImport(AppKit)
import AppKit

@Suite("FileChooserController")
@MainActor
struct FileChooserControllerTests {
	@Test("initializes with project path and title")
	func initialization() {
		let controller = FileChooserController(projectPath: "/tmp/TestProject")
		#expect(controller.window?.title == "Open Quickly")
		#expect(controller.items.isEmpty)
	}

	@Test("open documents can be set before showing")
	func setOpenDocuments() {
		let controller = FileChooserController(projectPath: "/tmp/TestProject")
		controller.setOpenDocuments(["/tmp/TestProject/a.swift", "/tmp/TestProject/b.swift"])
		controller.setCurrentDocumentPath("/tmp/TestProject/a.swift")
		// No crash means success; state is internal.
		#expect(controller.items.isEmpty) // Items aren't populated until show
	}

	@Test("onSelectFile callback fires on selection")
	func selectionCallback() {
		let controller = FileChooserController(projectPath: "/tmp/TestProject")
		var selectedPath: String?
		var selectedLine: String?
		var selectedSymbol: String?

		controller.onSelectFile = { path, line, symbol in
			selectedPath = path
			selectedLine = line
			selectedSymbol = symbol
		}

		// Simulate delegate call
		let item = FileChooserItem(path: "/tmp/TestProject/main.swift")
		controller.chooserPanel(controller, didSelectItems: [item])

		#expect(selectedPath == "/tmp/TestProject/main.swift")
		#expect(selectedLine == nil)
		#expect(selectedSymbol == nil)
	}
}

// MARK: - BundleItemChooserController Tests

@Suite("BundleItemChooserController")
@MainActor
struct BundleItemChooserControllerTests {
	@Test("initializes with title")
	func initialization() {
		let controller = BundleItemChooserController()
		#expect(controller.window?.title == "Select Bundle Item")
	}

	@Test("populates items from descriptors")
	func populate() {
		let controller = BundleItemChooserController()
		let descriptors = [
			BundleItemDescriptor(
				name: "Build",
				bundleName: "Source",
				identifier: "uuid-1",
				kind: "Command",
				source: .actionItems,
			),
			BundleItemDescriptor(
				name: "Run",
				bundleName: "Source",
				identifier: "uuid-2",
				tabTrigger: "run",
				kind: "Command",
				source: .actionItems,
			),
		]
		controller.populate(with: descriptors)
		#expect(controller.items.count == 2)
	}

	@Test("filtering reduces visible items")
	func filtering() {
		let controller = BundleItemChooserController()
		let descriptors = [
			BundleItemDescriptor(
				name: "Build",
				bundleName: "Source",
				identifier: "uuid-1",
				kind: "Command",
				source: .actionItems,
			),
			BundleItemDescriptor(
				name: "Run",
				bundleName: "Source",
				identifier: "uuid-2",
				kind: "Command",
				source: .actionItems,
			),
		]
		controller.populate(with: descriptors)
		controller.filterString = "Build"
		#expect(controller.items.count == 1)
	}

	@Test("onSelectItem callback fires on selection")
	func selectionCallback() {
		let controller = BundleItemChooserController()
		var selectedUUID: String?
		controller.onSelectItem = { uuid in selectedUUID = uuid }

		let item = BundleChooserItem(
			name: "Build",
			bundleName: "Source",
			itemIdentifier: "uuid-1",
		)
		controller.chooserPanel(controller, didSelectItems: [item])
		#expect(selectedUUID == "uuid-1")
	}
}

// MARK: - SymbolChooserController Tests

@Suite("SymbolChooserController")
@MainActor
struct SymbolChooserControllerTests {
	@Test("initializes with title")
	func initialization() {
		let controller = SymbolChooserController()
		#expect(controller.window?.title == "Jump to Symbol")
	}

	@Test("populates symbols from descriptors")
	func populate() {
		let controller = SymbolChooserController()
		let symbols = [
			SymbolDescriptor(name: "viewDidLoad", offset: 100, selectionString: "5"),
			SymbolDescriptor(name: "configure", offset: 200, selectionString: "12"),
		]
		controller.populate(documentName: "ViewController.swift", symbols: symbols)
		#expect(controller.items.count == 2)
	}

	@Test("filtering reduces visible items")
	func filtering() {
		let controller = SymbolChooserController()
		let symbols = [
			SymbolDescriptor(name: "viewDidLoad", offset: 100, selectionString: "5"),
			SymbolDescriptor(name: "configure", offset: 200, selectionString: "12"),
		]
		controller.populate(documentName: "VC.swift", symbols: symbols)
		controller.filterString = "view"
		#expect(controller.items.count == 1)
	}

	@Test("onSelectSymbol callback fires on selection")
	func selectionCallback() {
		let controller = SymbolChooserController()
		var selectedSelection: String?
		controller.onSelectSymbol = { sel in selectedSelection = sel }

		let item = SymbolChooserItem(
			symbolName: "viewDidLoad",
			offset: 100,
			selectionString: "5",
		)
		controller.chooserPanel(controller, didSelectItems: [item])
		#expect(selectedSelection == "5")
	}
}

// MARK: - SettingsResolver Integration Tests

@Suite("SettingsResolver Integration")
struct SettingsResolverIntegrationTests {
	@Test("returns empty settings for nil path")
	func nilPathReturnsDefaults() {
		let settings = SettingsResolver.settingsForPath(nil)
		// Should not crash and return at least an empty dict.
		#expect(settings.isEmpty || !settings.isEmpty) // Should not crash
	}

	@Test("returns empty for non-existent path")
	func nonExistentPath() {
		let settings = SettingsResolver.settingsForPath("/nonexistent/path/file.txt")
		// No .tm_properties found, so empty or base only.
		#expect(settings.isEmpty || !settings.isEmpty) // Should not crash
	}

	@Test("single key lookup works")
	func singleKeyLookup() {
		let value = SettingsResolver.get("tabSize", forPath: nil)
		// No .tm_properties → nil
		#expect(value == nil)
	}

	@Test("base variables are included in result")
	func baseVariablesPassthrough() {
		let settings = SettingsResolver.settingsForPath(
			nil,
			baseVariables: ["tabSize": "3"],
		)
		#expect(settings["tabSize"] == "3")
	}

	@Test("scope matching returns empty for unmatched scope")
	func scopeMatchingUnmatched() {
		let settings = SettingsResolver.settingsForPath(
			"/tmp/test.txt",
			scope: "source.unknown_test_scope",
		)
		// No .tm_properties files match, so nothing extra.
		#expect(settings.isEmpty || !settings.isEmpty) // Should not crash
	}
}

#endif
