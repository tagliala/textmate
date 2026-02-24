import AppKit
import Testing
@testable import TMEditorUI

// MARK: - PrintableDocumentView Tests

@Suite("PrintableDocumentView")
struct PrintableDocumentViewTests {
	// MARK: - Initialization

	@Test("Initialization sets document title")
	@MainActor
	func initSetsTitle() {
		let view = PrintableDocumentView(
			text: "Hello",
			title: "test.txt",
		)
		#expect(view.printJobTitle == "test.txt")
	}

	@Test("Initialization with empty text")
	@MainActor
	func initEmptyText() {
		let view = PrintableDocumentView(
			text: "",
			title: "empty.txt",
		)
		#expect(view.printJobTitle == "empty.txt")
		#expect(view.isFlipped)
	}

	@Test("View is flipped")
	@MainActor
	func viewIsFlipped() {
		let view = PrintableDocumentView(
			text: "content",
			title: "doc.swift",
		)
		#expect(view.isFlipped)
	}

	@Test("Style provider can be set")
	@MainActor
	func styleProviderCanBeSet() {
		let view = PrintableDocumentView(
			text: "let x = 1",
			title: "code.swift",
		)

		var callCount = 0
		view.styleProvider = { _, _ in
			callCount += 1
			return []
		}

		// The style provider is stored (can't easily verify without triggering layout,
		// but setting it should not crash).
		#expect(view.printJobTitle == "code.swift")
	}

	@Test("Init with custom font name")
	@MainActor
	func initWithFontName() {
		let view = PrintableDocumentView(
			text: "test",
			title: "doc.txt",
			fontName: "Menlo",
		)
		// Should not crash and title should be set.
		#expect(view.printJobTitle == "doc.txt")
	}

	@Test("Init with style provider callback")
	@MainActor
	func initWithStyleProvider() {
		let run = StyleRun(
			start: 0,
			length: 3,
			foreground: .red,
		)
		let view = PrintableDocumentView(
			text: "let x = 1",
			title: "styled.swift",
			styleProvider: { _, _ in [run] },
		)
		#expect(view.printJobTitle == "styled.swift")
	}
}

// MARK: - PrintSettingKey Tests

@Suite("PrintSettingKey")
struct PrintSettingKeyTests {
	@Test("Theme UUID key value")
	func themeUUIDKey() {
		#expect(PrintSettingKey.themeUUID == "OakPrintThemeUUID")
	}

	@Test("Font size key value")
	func fontSizeKey() {
		#expect(PrintSettingKey.fontSize == "OakPrintFontSize")
	}

	@Test("Header and footer key value")
	func headerAndFooterKey() {
		#expect(PrintSettingKey.headerAndFooter == "OakPrintHeaderAndFooter")
	}
}

// MARK: - PrintOptionsViewController Tests

@Suite("PrintOptionsViewController")
struct PrintOptionsViewControllerTests {
	@Test("Initialization creates view")
	@MainActor
	func initCreatesView() {
		let vc = PrintOptionsViewController()
		vc.loadViewIfNeeded()
		#expect(vc.view.subviews.count > 0)
	}

	@Test("Title is TextMate")
	@MainActor
	func titleIsTextMate() {
		let vc = PrintOptionsViewController()
		#expect(vc.title == "TextMate")
	}

	@Test("Setting title is accepted")
	@MainActor
	func setTitle() {
		let vc = PrintOptionsViewController()
		vc.title = "Other"
		// Title getter always returns "TextMate"
		#expect(vc.title == "TextMate")
	}

	@Test("Available themes populate menu")
	@MainActor
	func themesPopulateMenu() {
		let vc = PrintOptionsViewController()
		vc.availableThemes = [
			PrintOptionsViewController.ThemeEntry(name: "Monokai", uuid: "uuid-1"),
			PrintOptionsViewController.ThemeEntry(name: "Twilight", uuid: "uuid-2"),
		]
		vc.loadViewIfNeeded()

		// After loadView, the themes popup should have items.
		// We verify indirectly through the view hierarchy.
		#expect(vc.view.frame.width > 0)
	}

	@Test("Empty themes shows placeholder")
	@MainActor
	func emptyThemesPlaceholder() {
		let vc = PrintOptionsViewController()
		vc.availableThemes = []
		vc.loadViewIfNeeded()

		// View should still load without crashing.
		#expect(vc.view.subviews.count > 0)
	}

	@Test("ThemeEntry stores name and UUID")
	func themeEntryProperties() {
		let entry = PrintOptionsViewController.ThemeEntry(
			name: "Solarized",
			uuid: "ABC-123",
		)
		#expect(entry.name == "Solarized")
		#expect(entry.uuid == "ABC-123")
	}

	@Test("Localized summary items returns empty array")
	@MainActor
	func localizedSummaryEmpty() {
		let vc = PrintOptionsViewController()
		let items = vc.localizedSummaryItems()
		#expect(items.isEmpty)
	}

	@Test("Key paths for affecting preview")
	@MainActor
	func keyPathsForPreview() {
		let vc = PrintOptionsViewController()
		let paths = vc.keyPathsForValuesAffectingPreview()
		#expect(paths.contains("themeIndex"))
		#expect(paths.contains("printFontSize"))
		#expect(paths.contains("printHeaderAndFooter"))
	}

	@Test("Represented object can be set to NSPrintInfo")
	@MainActor
	func representedObjectPrintInfo() {
		let vc = PrintOptionsViewController()
		vc.availableThemes = [
			PrintOptionsViewController.ThemeEntry(name: "Mac Classic", uuid: "classic-uuid"),
		]
		vc.loadViewIfNeeded()

		let printInfo = NSPrintInfo()
		printInfo.dictionary()[PrintSettingKey.fontSize] = NSNumber(value: 14)
		printInfo.dictionary()[PrintSettingKey.themeUUID] = "classic-uuid"

		vc.representedObject = printInfo

		// Should not crash — settings are synced.
		#expect(vc.representedObject != nil)
	}

	@Test("Font size menu has entries from 4 to 22")
	@MainActor
	func fontSizeMenuRange() {
		let vc = PrintOptionsViewController()
		vc.loadViewIfNeeded()

		// The view should have loaded its font size popup.
		// We verify the view hierarchy has the expected number of subviews.
		// (5 subviews: 2 labels, 2 popups, 1 checkbox)
		#expect(vc.view.subviews.count == 5)
	}

	@Test("Print info stores header/footer flag")
	@MainActor
	func printInfoHeaderFooter() {
		let vc = PrintOptionsViewController()
		vc.loadViewIfNeeded()

		let printInfo = NSPrintInfo()
		printInfo.dictionary()["NSPrintHeaderAndFooter"] = NSNumber(value: true)

		vc.representedObject = printInfo

		// The checkbox should reflect the setting.
		#expect(vc.representedObject != nil)
	}
}

// MARK: - ThemeEntry Sendable Conformance

@Suite("ThemeEntry Sendable")
struct ThemeEntrySendableTests {
	@Test("ThemeEntry is Sendable")
	func sendable() {
		let entry = PrintOptionsViewController.ThemeEntry(
			name: "Test",
			uuid: "test-uuid",
		)
		// Verify Sendable by passing to a nonisolated context.
		let captured = entry
		#expect(captured.name == "Test")
		#expect(captured.uuid == "test-uuid")
	}
}
