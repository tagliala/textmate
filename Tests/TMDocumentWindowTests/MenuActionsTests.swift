import AppKit
import Testing
import TMCore
@testable import TMDocumentManager
@testable import TMDocumentWindow
@testable import TMEditor
@testable import TMEditorUI

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
