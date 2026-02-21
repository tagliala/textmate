import AppKit
import Testing
@testable import TMEditorUI

@Suite("EditorView")
struct EditorViewTests {
	// MARK: - View Configuration

	@Test("EditorView is flipped")
	@MainActor
	func isFlipped() {
		let view = EditorView()
		#expect(view.isFlipped)
	}

	@Test("EditorView accepts first responder")
	@MainActor
	func acceptsFirstResponder() {
		let view = EditorView()
		#expect(view.acceptsFirstResponder)
	}

	@Test("EditorView is opaque")
	@MainActor
	func isOpaque() {
		let view = EditorView()
		#expect(view.isOpaque)
	}

	@Test("EditorView has layer backing")
	@MainActor
	func hasLayer() {
		let view = EditorView()
		#expect(view.wantsLayer)
	}

	// MARK: - Text Content

	@Test("Set and get text")
	@MainActor
	func setAndGetText() {
		let view = EditorView()
		view.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
		view.setText("Hello, TextMate!")

		#expect(view.text == "Hello, TextMate!")
	}

	@Test("Multi-line text round-trips")
	@MainActor
	func multiLineText() {
		let view = EditorView()
		view.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
		view.setText("Line 1\nLine 2\nLine 3")

		#expect(view.text == "Line 1\nLine 2\nLine 3")
	}

	@Test("Empty text produces empty string")
	@MainActor
	func emptyText() {
		let view = EditorView()
		view.setText("")

		#expect(view.text == "")
	}

	// MARK: - Carets

	@Test("Default caret at origin")
	@MainActor
	func defaultCaret() {
		let view = EditorView()
		#expect(view.carets.count == 1)
		#expect(view.carets[0].line == 0)
		#expect(view.carets[0].index == 0)
	}

	@Test("Setting text resets carets")
	@MainActor
	func setTextResetsCaret() {
		let view = EditorView()
		view.carets = [(2, 5)]
		view.setText("Hello")

		#expect(view.carets.count == 1)
		#expect(view.carets[0].line == 0)
		#expect(view.carets[0].index == 0)
	}

	@Test("Multiple carets supported")
	@MainActor
	func multipleCarets() {
		let view = EditorView()
		view.setText("Line 1\nLine 2\nLine 3")
		view.carets = [(0, 3), (1, 3), (2, 3)]

		#expect(view.carets.count == 3)
	}

	// MARK: - Selection

	@Test("Default has no selection")
	@MainActor
	func defaultNoSelection() {
		let view = EditorView()
		#expect(view.selectionRanges.isEmpty)
	}

	@Test("Setting text clears selection")
	@MainActor
	func setTextClearsSelection() {
		let view = EditorView()
		view.selectionRanges = [(start: (0, 0), end: (0, 5))]
		view.setText("New text")

		#expect(view.selectionRanges.isEmpty)
	}

	// MARK: - NSTextInputClient

	@Test("Has marked text initially false")
	@MainActor
	func initiallyNoMarkedText() {
		let view = EditorView()
		#expect(view.hasMarkedText() == false)
	}

	@Test("Valid attributes for marked text")
	@MainActor
	func validAttributesForMarkedText() {
		let view = EditorView()
		let attrs = view.validAttributesForMarkedText()
		#expect(attrs.contains(.font))
		#expect(attrs.contains(.foregroundColor))
	}

	@Test("Selected range with no selection returns caret position")
	@MainActor
	func selectedRangeNoCaret() {
		let view = EditorView()
		view.setText("Hello")
		view.carets = [(0, 3)]

		let range = view.selectedRange()
		#expect(range.location == 3)
		#expect(range.length == 0)
	}

	@Test("Unmark text clears marked state")
	@MainActor
	func unmarkText() {
		let view = EditorView()
		view.setMarkedText(
			"漢",
			selectedRange: NSRange(location: 0, length: 1),
			replacementRange: NSRange(location: 0, length: 0),
		)
		#expect(view.hasMarkedText())

		view.unmarkText()
		#expect(!view.hasMarkedText())
	}

	@Test("Attributed substring for proposed range")
	@MainActor
	func attributedSubstring() {
		let view = EditorView()
		view.setText("Hello, world!")

		let sub = view.attributedSubstring(
			forProposedRange: NSRange(location: 7, length: 5),
			actualRange: nil,
		)

		#expect(sub?.string == "world")
	}

	// MARK: - Appearance

	@Test("Default caret color is text color")
	@MainActor
	func defaultCaretColor() {
		let view = EditorView()
		#expect(view.caretColor == .textColor)
	}

	@Test("Default selection color is system selection color")
	@MainActor
	func defaultSelectionColor() {
		let view = EditorView()
		#expect(view.selectionColor == .selectedTextBackgroundColor)
	}

	@Test("Show invisibles defaults to false")
	@MainActor
	func showInvisiblesDefault() {
		let view = EditorView()
		#expect(view.showInvisibles == false)
	}

	// MARK: - Accessibility

	@Test("Accessibility role is text area")
	@MainActor
	func accessibilityRole() {
		let view = EditorView()
		#expect(view.accessibilityRole() == .textArea)
	}

	@Test("Accessibility value returns text")
	@MainActor
	func accessibilityValue() {
		let view = EditorView()
		view.setText("Hello")

		let value = view.accessibilityValue() as? String
		#expect(value == "Hello")
	}

	@Test("Accessibility character count")
	@MainActor
	func accessibilityNumberOfCharacters() {
		let view = EditorView()
		view.setText("Hello")

		#expect(view.accessibilityNumberOfCharacters() == 5)
	}

	@Test("Accessibility insertion point line number")
	@MainActor
	func accessibilityInsertionPoint() {
		let view = EditorView()
		view.setText("A\nB\nC")
		view.carets = [(2, 0)]

		#expect(view.accessibilityInsertionPointLineNumber() == 2)
	}

	@Test("Accessibility line for offset")
	@MainActor
	func accessibilityLineForOffset() {
		let view = EditorView()
		view.setText("Hello\nWorld")

		// Offset 6 is first char of line 1 ("World")
		let line = view.accessibilityLine(for: 6)
		#expect(line == 1)
	}

	@Test("Accessibility range for line")
	@MainActor
	func accessibilityRangeForLine() {
		let view = EditorView()
		view.setText("Hello\nWorld")

		// Line 1 starts at offset 6 (after "Hello\n") and has length 5
		let range = view.accessibilityRange(forLine: 1)
		#expect(range.location == 6)
		#expect(range.length == 5)
	}

	@Test("Accessibility string for range")
	@MainActor
	func accessibilityStringForRange() {
		let view = EditorView()
		view.setText("Hello, world!")

		let str = view.accessibilityString(for: NSRange(location: 0, length: 5))
		#expect(str == "Hello")
	}

	@Test("Set accessibility selected text range updates selection")
	@MainActor
	func setAccessibilitySelectedRange() {
		let view = EditorView()
		view.setText("Hello, world!")

		view.setAccessibilitySelectedTextRange(NSRange(location: 7, length: 5))

		#expect(view.selectionRanges.count == 1)
		#expect(view.selectionRanges[0].start.line == 0)
		#expect(view.selectionRanges[0].start.index == 7)
		#expect(view.selectionRanges[0].end.line == 0)
		#expect(view.selectionRanges[0].end.index == 12)
	}

	// MARK: - EditorViewAction Enum

	@Test("EditorViewAction has all expected movement cases")
	func actionCases() {
		let movements: [EditorViewAction] = [
			.moveUp, .moveDown, .moveLeft, .moveRight,
			.moveToBeginningOfLine, .moveToEndOfLine,
			.moveToBeginningOfDocument, .moveToEndOfDocument,
			.moveWordForward, .moveWordBackward,
			.pageUp, .pageDown,
		]
		#expect(movements.count == 12)
	}

	@Test("EditorViewAction has deletion cases")
	func deletionCases() {
		let deletions: [EditorViewAction] = [
			.deleteForward, .deleteBackward,
			.deleteWordForward, .deleteWordBackward,
			.deleteToBeginningOfLine, .deleteToEndOfLine,
		]
		#expect(deletions.count == 6)
	}

	@Test("EditorViewAction has insertion cases")
	func insertionCases() {
		let insertions: [EditorViewAction] = [
			.insertNewline, .insertTab, .insertBacktab,
		]
		#expect(insertions.count == 3)
	}

	@Test("EditorViewAction has selection extension cases")
	func selectionExtensionCases() {
		let selExtensions: [EditorViewAction] = [
			.moveUpAndModifySelection, .moveDownAndModifySelection,
			.moveLeftAndModifySelection, .moveRightAndModifySelection,
			.moveWordForwardAndModifySelection, .moveWordBackwardAndModifySelection,
			.moveToBeginningOfLineAndModifySelection, .moveToEndOfLineAndModifySelection,
			.moveToBeginningOfDocumentAndModifySelection, .moveToEndOfDocumentAndModifySelection,
		]
		#expect(selExtensions.count == 10)
	}
}

// MARK: - Trampoline Selectors

@Suite("EditorView Trampoline Selectors")
@MainActor
struct EditorViewTrampolineTests {
	/// All trampoline selectors that EditorView must respond to so that
	/// AppKit can route the corresponding menu items through the responder chain.
	nonisolated static let trampolineSelectors: [Selector] = [
		#selector(EditorView.selectWord(_:)),
		#selector(EditorView.selectParagraph(_:)),
		#selector(EditorView.selectHardLine(_:)),
		#selector(EditorView.selectCurrentScope(_:)),
		#selector(EditorView.selectBlock(_:)),
		#selector(EditorView.transpose(_:)),
		#selector(EditorView.pasteNext(_:)),
		#selector(EditorView.pastePrevious(_:)),
		#selector(EditorView.uppercaseWord(_:)),
		#selector(EditorView.lowercaseWord(_:)),
		#selector(EditorView.capitalizeWord(_:)),
		#selector(EditorView.changeCaseOfLetter(_:)),
		#selector(EditorView.changeCaseOfWord(_:)),
		#selector(EditorView.shiftLeft(_:)),
		#selector(EditorView.shiftRight(_:)),
		#selector(EditorView.indent(_:)),
		#selector(EditorView.reformatText(_:)),
		#selector(EditorView.reformatTextAndJustify(_:)),
		#selector(EditorView.unwrapText(_:)),
		#selector(EditorView.moveSelectionUp(_:)),
		#selector(EditorView.moveSelectionDown(_:)),
		#selector(EditorView.moveSelectionLeft(_:)),
		#selector(EditorView.moveSelectionRight(_:)),
	]

	@Test("EditorView responds to all trampoline selectors", arguments: trampolineSelectors)
	func respondsToTrampoline(selector: Selector) {
		let view = EditorView()
		#expect(view.responds(to: selector))
	}

	@Test("Trampoline forwards to delegate", arguments: trampolineSelectors)
	func trampolineForwardsToDelegate(selector: Selector) {
		let view = EditorView()
		let spy = DelegateSpy()
		view.delegate = spy
		view.perform(selector, with: nil)
		#expect(spy.lastCommandSelector != nil, "Expected delegate call for \(selector)")
	}
}

/// Minimal spy that records the last ``doCommandBySelector`` call.
@MainActor
private final class DelegateSpy: EditorViewDelegate {
	var lastCommandSelector: Selector?

	func editorView(_: EditorView, doCommandBySelector selector: Selector) {
		lastCommandSelector = selector
	}
}
