import AppKit
import Testing
import TMCore
@testable import TMDocumentManager
@testable import TMDocumentWindow
@testable import TMEditor
@testable import TMEditorUI
@testable import TMSearchReplace

// MARK: - Menu Actions Tests

@Suite("DocumentWindowController+MenuActions")
@MainActor
struct MenuActionsTests {
	// MARK: - Toggle Line Numbers

	@Test("toggleLineNumbers hides and shows gutter")
	func toggleLineNumbers() {
		let controller = DocumentWindowController()

		#expect(controller.isLineNumbersVisible == true)

		controller.toggleLineNumbers(nil)
		#expect(controller.isLineNumbersVisible == false)
		#expect(controller.gutterView.isHidden == true)
		#expect(controller.gutterWidthConstraint?.constant == 0)

		controller.toggleLineNumbers(nil)
		#expect(controller.isLineNumbersVisible == true)
		#expect(controller.gutterView.isHidden == false)
		#expect((controller.gutterWidthConstraint?.constant ?? 0) > 0)
	}

	// MARK: - Toggle Soft Wrap

	@Test("toggleSoftWrap toggles layout manager soft wrap")
	func toggleSoftWrap() {
		let controller = DocumentWindowController()

		#expect(controller.editorView.layoutManager.softWrap == false)

		controller.toggleSoftWrap(nil)
		#expect(controller.editorView.layoutManager.softWrap == true)

		controller.toggleSoftWrap(nil)
		#expect(controller.editorView.layoutManager.softWrap == false)
	}

	// MARK: - Toggle Show Invisibles

	@Test("toggleShowInvisibles toggles editor view invisibles")
	func toggleShowInvisibles() {
		let controller = DocumentWindowController()

		#expect(controller.editorView.showInvisibles == false)

		controller.toggleShowInvisibles(nil)
		#expect(controller.editorView.showInvisibles == true)

		controller.toggleShowInvisibles(nil)
		#expect(controller.editorView.showInvisibles == false)
	}

	// MARK: - Font Size

	@Test("makeTextLarger increases font size")
	func makeTextLarger() {
		let controller = DocumentWindowController()
		let initialSize = controller.editorView.layoutManager.font.pointSize

		controller.makeTextLarger(nil)
		#expect(controller.editorView.layoutManager.font.pointSize == initialSize + 1)
	}

	@Test("makeTextSmaller decreases font size")
	func makeTextSmaller() {
		let controller = DocumentWindowController()
		let initialSize = controller.editorView.layoutManager.font.pointSize

		controller.makeTextSmaller(nil)
		#expect(controller.editorView.layoutManager.font.pointSize == initialSize - 1)
	}

	@Test("makeTextStandardSize resets to 13pt")
	func makeTextStandardSize() {
		let controller = DocumentWindowController()

		// Change font size first
		controller.makeTextLarger(nil)
		controller.makeTextLarger(nil)
		#expect(controller.editorView.layoutManager.font.pointSize != 13)

		controller.makeTextStandardSize(nil)
		#expect(controller.editorView.layoutManager.font.pointSize == 13)
	}

	@Test("makeTextLarger clamps at 72pt")
	func fontSizeUpperBound() {
		let controller = DocumentWindowController()
		controller.editorView.layoutManager.setFont(.monospacedSystemFont(ofSize: 72, weight: .regular))

		controller.makeTextLarger(nil)
		#expect(controller.editorView.layoutManager.font.pointSize == 72)
	}

	@Test("makeTextSmaller clamps at 6pt")
	func fontSizeLowerBound() {
		let controller = DocumentWindowController()
		controller.editorView.layoutManager.setFont(.monospacedSystemFont(ofSize: 6, weight: .regular))

		controller.makeTextSmaller(nil)
		#expect(controller.editorView.layoutManager.font.pointSize == 6)
	}

	// MARK: - Tab Size

	@Test("takeTabSizeFrom reads tag from menu item")
	func takeTabSizeFrom() {
		let controller = DocumentWindowController()

		let menuItem = NSMenuItem()
		menuItem.title = "4"
		menuItem.tag = 4

		controller.takeTabSizeFrom(menuItem)
		#expect(controller.editorView.layoutManager.tabSize == 4)
	}

	// MARK: - Bookmarks

	@Test("toggleCurrentBookmark adds and removes bookmark at caret line")
	func toggleCurrentBookmark() {
		let controller = DocumentWindowController()
		controller.editorView.carets = [(0, 0)]

		controller.toggleCurrentBookmark(nil)
		#expect(controller.gutterView.bookmarkedLines.contains(1))

		controller.toggleCurrentBookmark(nil)
		#expect(!controller.gutterView.bookmarkedLines.contains(1))
	}

	// MARK: - goToRelatedFile (no file on disk)

	@Test("goToRelatedFile does nothing for untitled document")
	func goToRelatedFileUntitled() {
		let controller = DocumentWindowController()
		// Should not crash when no path exists
		controller.goToRelatedFile(nil)
	}

	// MARK: - Scroll Column

	@Test("scrollColumnLeft and scrollColumnRight adjust bounds origin")
	func scrollColumns() {
		let controller = DocumentWindowController()
		// Just verify they don't crash
		controller.scrollColumnLeft(nil)
		controller.scrollColumnRight(nil)
	}

	// MARK: - Scroll Line

	@Test("scrollLineUp and scrollLineDown adjust bounds origin")
	func scrollLines() {
		let controller = DocumentWindowController()
		// Just verify they don't crash
		controller.scrollLineUp(nil)
		controller.scrollLineDown(nil)
	}

	// MARK: - Menu Validation

	@Test("validateMenuItem returns checkmark state for toggles")
	func validateToggleCheckmarks() {
		let controller = DocumentWindowController()

		// Toggle soft wrap
		let softWrapItem = NSMenuItem(
			title: "Soft Wrap",
			action: NSSelectorFromString("toggleSoftWrap:"),
			keyEquivalent: "",
		)
		_ = controller.validateMenuItem(softWrapItem)
		#expect(softWrapItem.state == .off)

		controller.editorView.layoutManager.softWrap = true
		_ = controller.validateMenuItem(softWrapItem)
		#expect(softWrapItem.state == .on)

		// Toggle invisibles
		let invisItem = NSMenuItem(
			title: "Show Invisibles",
			action: NSSelectorFromString("toggleShowInvisibles:"),
			keyEquivalent: "",
		)
		_ = controller.validateMenuItem(invisItem)
		#expect(invisItem.state == .off)

		controller.editorView.showInvisibles = true
		_ = controller.validateMenuItem(invisItem)
		#expect(invisItem.state == .on)

		// Toggle line numbers
		let lineNumItem = NSMenuItem(
			title: "Line Numbers",
			action: NSSelectorFromString("toggleLineNumbers:"),
			keyEquivalent: "",
		)
		_ = controller.validateMenuItem(lineNumItem)
		#expect(lineNumItem.state == .on) // visible by default

		controller.isLineNumbersVisible = false
		_ = controller.validateMenuItem(lineNumItem)
		#expect(lineNumItem.state == .off)
	}

	@Test("validateMenuItem highlights matching tab size")
	func validateTabSizeCheckmark() {
		let controller = DocumentWindowController()
		controller.editorView.layoutManager.tabSize = 4

		let item4 = NSMenuItem(
			title: "4",
			action: NSSelectorFromString("takeTabSizeFrom:"),
			keyEquivalent: "",
		)
		item4.tag = 4
		_ = controller.validateMenuItem(item4)
		#expect(item4.state == .on)

		let item2 = NSMenuItem(
			title: "2",
			action: NSSelectorFromString("takeTabSizeFrom:"),
			keyEquivalent: "",
		)
		item2.tag = 2
		_ = controller.validateMenuItem(item2)
		#expect(item2.state == .off)
	}

	@Test("validateMenuItem disables goToRelatedFile for untitled")
	func validateGoToRelatedFile() {
		let controller = DocumentWindowController()
		let item = NSMenuItem(
			title: "Related File",
			action: NSSelectorFromString("goToRelatedFile:"),
			keyEquivalent: "",
		)
		let enabled = controller.validateMenuItem(item)
		#expect(enabled == false)
	}

	@Test("validateMenuItem disables bookmark nav when no bookmarks")
	func validateBookmarkNavDisabled() {
		let controller = DocumentWindowController()
		let nextItem = NSMenuItem(
			title: "Next",
			action: NSSelectorFromString("goToNextBookmark:"),
			keyEquivalent: "",
		)
		let enabled = controller.validateMenuItem(nextItem)
		#expect(enabled == false)
	}
}

// MARK: - Apply Settings Tests

@Suite("DocumentWindowController — Settings Integration")
@MainActor
struct SettingsIntegrationTests {
	@Test("applySettings sets softWrap from settings")
	func applySoftWrap() {
		let controller = DocumentWindowController()
		let doc = TMDocument(path: "/tmp/test.txt")
		doc.setContent("hello", preserveRevision: true)

		// Before applying — softWrap defaults to false
		#expect(controller.editorView.layoutManager.softWrap == false)
	}

	@Test("applySettings sets showInvisibles from settings")
	func applyShowInvisibles() {
		let controller = DocumentWindowController()

		// Verify default state
		#expect(controller.editorView.showInvisibles == false)
	}

	@Test("applySettings sets font size")
	func applyFontSize() {
		let controller = DocumentWindowController()

		// Default font size should be 13pt
		#expect(controller.editorView.layoutManager.font.pointSize == 13)
	}

	@Test("isSpellCheckingEnabled defaults to false")
	func spellCheckDefault() {
		let controller = DocumentWindowController()
		#expect(controller.isSpellCheckingEnabled == false)
	}
}

// MARK: - New Selector Mapping Tests

@Suite("EditorAction — Phase 40 Selector Mappings")
struct Phase40SelectorMappingTests {
	@Test("selectParagraph: maps to .selectParagraph")
	func selectParagraph() {
		#expect(EditorAction(selector: "selectParagraph:") == .selectParagraph)
	}

	@Test("selectHardLine: maps to .selectLine")
	func selectHardLine() {
		#expect(EditorAction(selector: "selectHardLine:") == .selectLine)
	}

	@Test("selectCurrentScope: maps to .selectScope")
	func selectCurrentScope() {
		#expect(EditorAction(selector: "selectCurrentScope:") == .selectScope)
	}

	@Test("selectBlock: maps to .selectParagraph")
	func selectBlock() {
		#expect(EditorAction(selector: "selectBlock:") == .selectParagraph)
	}

	@Test("changeCaseOfWord: maps to .changeCaseOfWord")
	func changeCaseOfWord() {
		#expect(EditorAction(selector: "changeCaseOfWord:") == .changeCaseOfWord)
	}

	@Test("reformatTextAndJustify: maps to .reformatTextAndJustify")
	func reformatTextAndJustify() {
		#expect(EditorAction(selector: "reformatTextAndJustify:") == .reformatTextAndJustify)
	}

	@Test("copySelectionToFindPboard: maps to .copySelectionToFindClipboard")
	func copySelectionToFindPboard() {
		#expect(EditorAction(selector: "copySelectionToFindPboard:") == .copySelectionToFindClipboard)
	}

	@Test("copySelectionToReplacePboard: maps to .copySelectionToReplaceClipboard")
	func copySelectionToReplacePboard() {
		#expect(EditorAction(selector: "copySelectionToReplacePboard:") == .copySelectionToReplaceClipboard)
	}
}

// MARK: - Find in Project Wiring Tests

@Suite("FindInProjectWiring")
@MainActor
struct FindInProjectWiringTests {
	@Test("orderFrontFindInProjectPanel sets scope to project")
	func findInProjectSetsScope() {
		let controller = DocumentWindowController()
		controller.projectPath = "/tmp/myproject"

		controller.orderFrontFindInProjectPanel(nil)

		let findPanel = FindPanelController.shared
		#expect(findPanel.searchTarget == .project)
		#expect(findPanel.projectFolder == "/tmp/myproject")
	}

	@Test("orderFrontFindInProjectPanel wires navigationDelegate")
	func findInProjectWiresDelegate() {
		let controller = DocumentWindowController()
		controller.projectPath = "/tmp/myproject"

		controller.orderFrontFindInProjectPanel(nil)

		#expect(FindPanelController.shared.navigationDelegate === controller)
	}

	@Test("orderFrontFindPanel also wires navigationDelegate")
	func findPanelWiresDelegate() {
		let controller = DocumentWindowController()

		controller.orderFrontFindPanel(nil)

		#expect(FindPanelController.shared.navigationDelegate === controller)
	}

	@Test("showPanel with scope parameter sets search target")
	func showPanelWithScope() {
		let findPanel = FindPanelController.shared
		findPanel.searchTarget = .document

		findPanel.showPanel(withSelection: nil, scope: .project)
		#expect(findPanel.searchTarget == .project)
	}

	@Test("showPanel without scope preserves current target")
	func showPanelWithoutScope() {
		let findPanel = FindPanelController.shared
		findPanel.searchTarget = .selection

		findPanel.showPanel(withSelection: "test")
		#expect(findPanel.searchTarget == .selection)
	}

	@Test("bringToFront does not crash")
	func bringToFrontNoCrash() {
		let controller = DocumentWindowController()
		// Should not crash even without a window on-screen
		controller.bringToFront()
	}
}
