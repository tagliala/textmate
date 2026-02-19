import AppKit
import CoreText

/// Custom text editor view using CoreText for rendering.
///
/// Replaces the temporary `NSTextView` from Phase 1 with a fully custom
/// rendering engine. Implements `NSTextInputClient` for keyboard/IME input
/// and `NSAccessibilityStaticText` for accessibility.
///
/// Counterpart of the C++ `OakTextView` in
/// `Frameworks/OakTextView/src/OakTextView.h`.
@MainActor
public class EditorView: NSView, @preconcurrency NSTextInputClient, NSMenuItemValidation {
	// MARK: - Layout Manager

	/// The layout manager that produces laid-out lines.
	public let layoutManager = EditorLayoutManager()

	// MARK: - Appearance

	/// The insertion point (caret) color.
	public var caretColor: NSColor = .textColor {
		didSet { needsDisplay = true }
	}

	/// The selection highlight color.
	public var selectionColor: NSColor = .selectedTextBackgroundColor {
		didSet { needsDisplay = true }
	}

	/// The line highlight color (nil = no line highlighting).
	public var lineHighlightColor: NSColor?

	/// Whether to draw invisible characters (spaces, tabs, newlines).
	public var showInvisibles: Bool = false {
		didSet { needsDisplay = true }
	}

	/// Whether continuous spell checking underlines are drawn.
	public var isContinuousSpellCheckingEnabled: Bool = false {
		didSet { needsDisplay = true }
	}

	/// The spelling language (nil = auto-detect).
	public var spellingLanguage: String?

	/// Cached spelling dot image for misspelling underlines.
	private lazy var spellingDotImage: CGImage? = Self.createSpellingDotImage()

	/// The invisible character representations.
	public var invisibleSpace: String = "·"
	public var invisibleTab: String = "‣"
	public var invisibleNewline: String = "¬"
	public var invisibleColor: NSColor = .tertiaryLabelColor

	// MARK: - Selection State

	/// Current caret positions (line, character index within line).
	/// Multiple entries = multi-cursor.
	public var carets: [(line: Int, index: Int)] = [(0, 0)] {
		didSet {
			updateCaretTimer()
			needsDisplay = true
		}
	}

	/// Selection ranges as (start, end) pairs of (line, index).
	public var selectionRanges: [(start: (line: Int, index: Int), end: (line: Int, index: Int))] = []

	/// Whether the caret is currently visible (blink state).
	private var caretVisible: Bool = true

	/// Timer for caret blinking.
	private var caretBlinkTimer: Timer?

	// MARK: - Input State

	/// Marked text for IME composition.
	private var markedTextValue: NSAttributedString?
	/// Range of marked text within the document.
	private var _markedRange: NSRange = .init(location: NSNotFound, length: 0)
	/// Selected range within marked text.
	private var selectedRangeValue: NSRange = .init(location: 0, length: 0)

	// MARK: - Delegate

	/// Delegate for text input events.
	public weak var delegate: EditorViewDelegate?

	// MARK: - Scroll View Integration

	/// Whether the view is the document view of a scroll view.
	private var isInScrollView: Bool {
		enclosingScrollView != nil
	}

	// MARK: - Init

	override public init(frame: NSRect) {
		super.init(frame: frame)
		commonInit()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	private func commonInit() {
		wantsLayer = true
		layer?.isOpaque = true

		// Accept first responder for keyboard input
		// (handled via override below)

		// Register for drag-and-drop
		registerForDraggedTypes([.string, .fileURL])

		// Set up cursor tracking
		let trackingArea = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect, .cursorUpdate],
			owner: self,
		)
		addTrackingArea(trackingArea)

		updateCaretTimer()
	}

	deinit {
		MainActor.assumeIsolated {
			caretBlinkTimer?.invalidate()
		}
	}

	// MARK: - View Configuration

	override public var isFlipped: Bool {
		true
	}

	override public var acceptsFirstResponder: Bool {
		true
	}

	override public var isOpaque: Bool {
		true
	}

	override public func cursorUpdate(with _: NSEvent) {
		NSCursor.iBeam.set()
	}

	override public func resetCursorRects() {
		addCursorRect(bounds, cursor: .iBeam)
	}

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window != nil {
			updateCaretTimer()
		} else {
			caretBlinkTimer?.invalidate()
			caretBlinkTimer = nil
		}
	}

	// MARK: - Content

	/// Set the full text content.
	public func setText(_ text: String) {
		layoutManager.setText(text)
		carets = [(0, 0)]
		selectionRanges = []
		invalidateIntrinsicContentSize()
		updateFrameSize()
		needsDisplay = true
	}

	/// The full text content as a string.
	public var text: String {
		var result = ""
		for i in 0 ..< layoutManager.lineCount {
			if i > 0 { result += "\n" }
			result += layoutManager.lineText(i) ?? ""
		}
		return result
	}

	// MARK: - Sizing

	override public var intrinsicContentSize: NSSize {
		NSSize(
			width: layoutManager.totalWidth,
			height: layoutManager.totalHeight,
		)
	}

	/// Update the frame size to match content (for scroll view).
	public func updateFrameSize() {
		let newSize = NSSize(
			width: max(layoutManager.totalWidth, enclosingScrollView?.contentSize.width ?? bounds.width),
			height: max(layoutManager.totalHeight, enclosingScrollView?.contentSize.height ?? bounds.height),
		)
		if frame.size != newSize {
			setFrameSize(newSize)
		}
	}

	override public func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		layoutManager.viewportSize = newSize
	}

	// MARK: - Drawing

	override public func draw(_ dirtyRect: NSRect) {
		guard let context = NSGraphicsContext.current?.cgContext else { return }

		// Background
		context.setFillColor(layoutManager.backgroundColor.cgColor)
		context.fill(dirtyRect)

		// Lay out visible lines
		let visibleLines = layoutManager.layoutLines(in: dirtyRect)

		// Line highlight
		if let highlightColor = lineHighlightColor {
			for caret in carets {
				let lineRect = layoutManager.rect(forLine: caret.line)
				if dirtyRect.intersects(lineRect) {
					context.setFillColor(highlightColor.cgColor)
					context.fill(lineRect)
				}
			}
		}

		// Draw lines
		let baseline = layoutManager.fontMetrics.baseline()
		for line in visibleLines {
			let lineRect = CGRect(
				x: line.origin.x,
				y: line.origin.y,
				width: bounds.width - line.origin.x,
				height: line.height,
			)
			guard dirtyRect.intersects(lineRect) else { continue }

			// Background runs
			line.drawBackground(
				at: line.origin,
				height: line.height,
				in: context,
				defaultBackground: layoutManager.backgroundColor.cgColor,
			)

			// Selection highlight
			for sel in selectionRanges {
				drawSelectionHighlight(
					selection: sel,
					forLine: line,
					in: context,
					baseline: baseline,
				)
			}

			// Foreground text
			// CoreText draws from baseline in a non-flipped coordinate space,
			// so we need to adjust for our flipped view.
			context.saveGState()
			// Flip the context for this line's drawing
			context.translateBy(x: 0, y: line.origin.y + line.height)
			context.scaleBy(x: 1, y: -1)
			let drawPoint = CGPoint(
				x: line.origin.x,
				y: line.height - baseline,
			)
			line.drawForeground(at: drawPoint, in: context)
			context.restoreGState()

			// Invisible characters
			if showInvisibles {
				drawInvisibles(for: line, in: context, baseline: baseline)
			}

			// Misspelling underlines
			if isContinuousSpellCheckingEnabled,
			   let provider = layoutManager.misspellingProvider
			{
				let ranges = provider(line.lineIndex)
				if !ranges.isEmpty {
					let drawPoint = CGPoint(
						x: line.origin.x,
						y: line.origin.y + baseline,
					)
					line.drawMisspellings(
						ranges,
						at: drawPoint,
						spellingDotImage: spellingDotImage,
						isFlipped: isFlipped,
						in: context,
					)
				}
			}
		}

		// Carets
		if caretVisible {
			drawCarets(in: context)
		}

		// Wrap column indicator
		if layoutManager.drawWrapColumn {
			drawWrapColumnIndicator(in: context, dirtyRect: dirtyRect)
		}
	}

	// MARK: - Drawing Helpers

	private func drawSelectionHighlight(
		selection: (start: (line: Int, index: Int), end: (line: Int, index: Int)),
		forLine line: LayoutLine,
		in context: CGContext,
		baseline _: CGFloat,
	) {
		let lineIdx = line.lineIndex
		let selStart = selection.start
		let selEnd = selection.end

		// Determine if this line is within the selection
		guard lineIdx >= selStart.line, lineIdx <= selEnd.line else { return }

		let startIdx: Int
		let endIdx: Int

		if lineIdx == selStart.line, lineIdx == selEnd.line {
			// Selection within single line
			startIdx = selStart.index
			endIdx = selEnd.index
		} else if lineIdx == selStart.line {
			// First line of multi-line selection
			startIdx = selStart.index
			endIdx = line.text.count
		} else if lineIdx == selEnd.line {
			// Last line of multi-line selection
			startIdx = 0
			endIdx = selEnd.index
		} else {
			// Middle line — fully selected
			startIdx = 0
			endIdx = line.text.count
		}

		let startX = line.offset(forIndex: startIdx) + line.origin.x
		let endX = line.offset(forIndex: endIdx) + line.origin.x
		let selRect = CGRect(
			x: startX,
			y: line.origin.y,
			width: max(endX - startX, 1),
			height: line.height,
		)

		context.setFillColor(selectionColor.cgColor)
		context.fill(selRect)
	}

	private func drawCarets(in context: CGContext) {
		context.setFillColor(caretColor.cgColor)
		for caret in carets {
			let rect = layoutManager.caretRect(forLine: caret.line, characterIndex: caret.index)
			context.fill(rect)
		}
	}

	private func drawInvisibles(for line: LayoutLine, in _: CGContext, baseline: CGFloat) {
		let attrs: [NSAttributedString.Key: Any] = [
			.font: layoutManager.font,
			.foregroundColor: invisibleColor,
		]

		for tabIdx in line.tabLocations {
			let x = line.offset(forIndex: tabIdx) + line.origin.x
			let str = invisibleTab as NSString
			let point = NSPoint(x: x, y: line.origin.y + baseline - layoutManager.fontMetrics.ascent)
			str.draw(at: point, withAttributes: attrs)
		}

		for spaceIdx in line.spaceLocations {
			let x = line.offset(forIndex: spaceIdx) + line.origin.x
			let str = invisibleSpace as NSString
			let size = str.size(withAttributes: attrs)
			let columnW = layoutManager.fontMetrics.columnWidth
			let point = NSPoint(
				x: x + (columnW - size.width) / 2,
				y: line.origin.y + baseline - layoutManager.fontMetrics.ascent,
			)
			str.draw(at: point, withAttributes: attrs)
		}
	}

	private func drawWrapColumnIndicator(in context: CGContext, dirtyRect: CGRect) {
		let x = layoutManager.effectiveWrapWidth + layoutManager.margin.left
		context.setStrokeColor(NSColor.separatorColor.cgColor)
		context.setLineWidth(1)
		context.move(to: CGPoint(x: x, y: dirtyRect.minY))
		context.addLine(to: CGPoint(x: x, y: dirtyRect.maxY))
		context.strokePath()
	}

	// MARK: - Caret Blinking

	private func updateCaretTimer() {
		caretBlinkTimer?.invalidate()
		caretVisible = true
		needsDisplay = true

		guard window != nil else { return }

		caretBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				self.caretVisible.toggle()
				// Only redraw the caret areas
				for caret in self.carets {
					let rect = self.layoutManager.caretRect(
						forLine: caret.line, characterIndex: caret.index,
					)
					self.setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
				}
			}
		}
	}

	/// Reset caret blink (called after any input to keep caret visible).
	private func resetCaretBlink() {
		caretVisible = true
		updateCaretTimer()
	}

	// MARK: - Mouse Events

	override public func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let (line, idx) = layoutManager.characterIndex(at: point)

		if event.modifierFlags.contains(.option) {
			// Add cursor
			carets.append((line, idx))
		} else {
			// Single cursor
			carets = [(line, idx)]
			selectionRanges = []
		}

		resetCaretBlink()
		delegate?.editorView(self, didClickAtLine: line, index: idx, event: event)
	}

	override public func mouseDragged(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let (line, idx) = layoutManager.characterIndex(at: point)

		guard let primaryCaret = carets.first else { return }
		selectionRanges = [(start: primaryCaret, end: (line, idx))]
		needsDisplay = true
		delegate?.editorView(self, didDragToLine: line, index: idx, event: event)
	}

	override public func mouseUp(with event: NSEvent) {
		if event.clickCount == 2 {
			// Double-click: select word
			delegate?.editorViewDidDoubleClick(self, event: event)
		} else if event.clickCount == 3 {
			// Triple-click: select line
			delegate?.editorViewDidTripleClick(self, event: event)
		}
	}

	// MARK: - Scroll & Zoom

	override public func scrollWheel(with event: NSEvent) {
		// Let the scroll view handle the scroll event natively.
		super.scrollWheel(with: event)
	}

	override public func magnify(with event: NSEvent) {
		delegate?.editorView(self, fontScaleDidChange: 1.0 + event.magnification)
	}

	// MARK: - Keyboard Events

	override public func keyDown(with event: NSEvent) {
		resetCaretBlink()
		interpretKeyEvents([event])
	}

	override public func performKeyEquivalent(with event: NSEvent) -> Bool {
		// Only handle when we are first responder in an active key window.
		guard let win = window, win.isKeyWindow, win.firstResponder === self else {
			return super.performKeyEquivalent(with: event)
		}
		if let handled = delegate?.editorView(self, performKeyEquivalent: event), handled {
			return true
		}
		return super.performKeyEquivalent(with: event)
	}

	// MARK: - NSTextInputClient

	public func insertText(_ string: Any, replacementRange: NSRange) {
		let text: String
		if let s = string as? String {
			text = s
		} else if let s = string as? NSAttributedString {
			text = s.string
		} else {
			return
		}

		// Clear marked text
		markedTextValue = nil
		_markedRange = NSRange(location: NSNotFound, length: 0)

		delegate?.editorView(self, insertText: text, replacementRange: replacementRange)
		resetCaretBlink()
		needsDisplay = true
	}

	public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange _: NSRange) {
		if let s = string as? NSAttributedString {
			markedTextValue = s
		} else if let s = string as? String {
			markedTextValue = NSAttributedString(string: s)
		}

		selectedRangeValue = selectedRange

		if let marked = markedTextValue, marked.length > 0 {
			_markedRange = NSRange(location: selectedRangeValue.location, length: marked.length)
		} else {
			_markedRange = NSRange(location: NSNotFound, length: 0)
		}

		needsDisplay = true
	}

	public func unmarkText() {
		markedTextValue = nil
		_markedRange = NSRange(location: NSNotFound, length: 0)
		needsDisplay = true
	}

	public func selectedRange() -> NSRange {
		// If we have a selection, return it; otherwise return caret position
		if let sel = selectionRanges.first {
			let startOffset = documentOffset(line: sel.start.line, index: sel.start.index)
			let endOffset = documentOffset(line: sel.end.line, index: sel.end.index)
			return NSRange(location: min(startOffset, endOffset), length: abs(endOffset - startOffset))
		}
		if let caret = carets.first {
			let offset = documentOffset(line: caret.line, index: caret.index)
			return NSRange(location: offset, length: 0)
		}
		return NSRange(location: 0, length: 0)
	}

	public func markedRange() -> NSRange {
		_markedRange
	}

	public func hasMarkedText() -> Bool {
		_markedRange.location != NSNotFound
	}

	public func attributedSubstring(
		forProposedRange range: NSRange,
		actualRange _: NSRangePointer?,
	) -> NSAttributedString? {
		let fullText = text
		guard let swiftRange = Range(range, in: fullText) else { return nil }
		return NSAttributedString(string: String(fullText[swiftRange]))
	}

	public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
		[.font, .foregroundColor, .backgroundColor, .underlineStyle]
	}

	public func firstRect(forCharacterRange range: NSRange, actualRange _: NSRangePointer?) -> NSRect {
		let (line, idx) = lineAndIndex(forDocumentOffset: range.location)
		let pt = layoutManager.point(forLine: line, characterIndex: idx)
		let screenPoint = window?.convertPoint(toScreen: convert(pt, to: nil)) ?? pt
		return NSRect(
			x: screenPoint.x,
			y: screenPoint.y - layoutManager.defaultLineHeight,
			width: layoutManager.fontMetrics.columnWidth,
			height: layoutManager.defaultLineHeight,
		)
	}

	public func characterIndex(for point: NSPoint) -> Int {
		let localPoint = convert(point, from: nil)
		let (line, idx) = layoutManager.characterIndex(at: localPoint)
		return documentOffset(line: line, index: idx)
	}

	// MARK: - NSStandardKeyBindingResponding

	override public func moveUp(_: Any?) {
		delegate?.editorView(self, performAction: .moveUp)
	}

	override public func moveDown(_: Any?) {
		delegate?.editorView(self, performAction: .moveDown)
	}

	override public func moveLeft(_: Any?) {
		delegate?.editorView(self, performAction: .moveLeft)
	}

	override public func moveRight(_: Any?) {
		delegate?.editorView(self, performAction: .moveRight)
	}

	override public func moveToBeginningOfLine(_: Any?) {
		delegate?.editorView(self, performAction: .moveToBeginningOfLine)
	}

	override public func moveToEndOfLine(_: Any?) {
		delegate?.editorView(self, performAction: .moveToEndOfLine)
	}

	override public func moveToBeginningOfDocument(_: Any?) {
		delegate?.editorView(self, performAction: .moveToBeginningOfDocument)
	}

	override public func moveToEndOfDocument(_: Any?) {
		delegate?.editorView(self, performAction: .moveToEndOfDocument)
	}

	override public func moveWordForward(_: Any?) {
		delegate?.editorView(self, performAction: .moveWordForward)
	}

	override public func moveWordBackward(_: Any?) {
		delegate?.editorView(self, performAction: .moveWordBackward)
	}

	override public func pageDown(_: Any?) {
		delegate?.editorView(self, performAction: .pageDown)
	}

	override public func pageUp(_: Any?) {
		delegate?.editorView(self, performAction: .pageUp)
	}

	override public func deleteForward(_: Any?) {
		delegate?.editorView(self, performAction: .deleteForward)
	}

	override public func deleteBackward(_: Any?) {
		delegate?.editorView(self, performAction: .deleteBackward)
	}

	override public func deleteWordForward(_: Any?) {
		delegate?.editorView(self, performAction: .deleteWordForward)
	}

	override public func deleteWordBackward(_: Any?) {
		delegate?.editorView(self, performAction: .deleteWordBackward)
	}

	override public func deleteToBeginningOfLine(_: Any?) {
		delegate?.editorView(self, performAction: .deleteToBeginningOfLine)
	}

	override public func deleteToEndOfLine(_: Any?) {
		delegate?.editorView(self, performAction: .deleteToEndOfLine)
	}

	override public func insertNewline(_: Any?) {
		delegate?.editorView(self, performAction: .insertNewline)
	}

	override public func insertTab(_: Any?) {
		delegate?.editorView(self, performAction: .insertTab)
	}

	override public func insertBacktab(_: Any?) {
		delegate?.editorView(self, performAction: .insertBacktab)
	}

	override public func selectAll(_: Any?) {
		delegate?.editorView(self, performAction: .selectAll)
	}

	/// Selection extension variants
	override public func moveUpAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveUpAndModifySelection)
	}

	override public func moveDownAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveDownAndModifySelection)
	}

	override public func moveLeftAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveLeftAndModifySelection)
	}

	override public func moveRightAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveRightAndModifySelection)
	}

	override public func moveWordForwardAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveWordForwardAndModifySelection)
	}

	override public func moveWordBackwardAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveWordBackwardAndModifySelection)
	}

	override public func moveToBeginningOfLineAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveToBeginningOfLineAndModifySelection)
	}

	override public func moveToEndOfLineAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveToEndOfLineAndModifySelection)
	}

	override public func moveToBeginningOfDocumentAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveToBeginningOfDocumentAndModifySelection)
	}

	override public func moveToEndOfDocumentAndModifySelection(_: Any?) {
		delegate?.editorView(self, performAction: .moveToEndOfDocumentAndModifySelection)
	}

	// MARK: - Undo/Redo Integration

	override public func doCommand(by selector: Selector) {
		if responds(to: selector) {
			perform(selector, with: nil)
		} else {
			delegate?.editorView(self, doCommandBySelector: selector)
		}
	}

	// MARK: - Context Menu

	override public func menu(for event: NSEvent) -> NSMenu? {
		if let menu = delegate?.editorViewNeedsContextMenu(self, for: event) {
			// Prepend spelling suggestions if spell checking is enabled.
			if isContinuousSpellCheckingEnabled {
				let point = convert(event.locationInWindow, from: nil)
				let suggestions = delegate?.editorView(self, spellingSuggestionsAt: point) ?? []
				if !suggestions.isEmpty {
					for (i, suggestion) in suggestions.prefix(5).enumerated() {
						let item = NSMenuItem(title: suggestion, action: #selector(applySuggestion(_:)), keyEquivalent: "")
						item.target = self
						item.representedObject = suggestion
						menu.insertItem(item, at: i)
					}
					menu.insertItem(.separator(), at: min(suggestions.count, 5))
				}
			}
			return menu
		}
		return super.menu(for: event)
	}

	/// Applies a spelling suggestion from the context menu.
	@objc private func applySuggestion(_ sender: NSMenuItem) {
		guard let word = sender.representedObject as? String else { return }
		delegate?.editorView(self, insertText: word, replacementRange: selectedRange())
	}

	// MARK: - Menu Validation

	@objc public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if let result = delegate?.editorView(self, validateMenuItem: menuItem) {
			return result
		}
		return true
	}

	// MARK: - Services Menu

	override public func validRequestor(
		forSendType sendType: NSPasteboard.PasteboardType?,
		returnType: NSPasteboard.PasteboardType?,
	) -> Any? {
		let canSend = (sendType == nil || sendType == .string) && !selectionRanges.isEmpty
		let canReturn = returnType == nil || returnType == .string
		if canSend, canReturn {
			return self
		}
		return super.validRequestor(forSendType: sendType, returnType: returnType)
	}

	public func writeSelection(
		to pboard: NSPasteboard,
		types: [NSPasteboard.PasteboardType],
	) -> Bool {
		guard types.contains(.string), let selectedText = accessibilitySelectedText() else {
			return false
		}
		pboard.clearContents()
		pboard.setString(selectedText, forType: .string)
		return true
	}

	public func readSelection(from pboard: NSPasteboard) -> Bool {
		guard let text = pboard.string(forType: .string), !text.isEmpty else {
			return false
		}
		delegate?.editorView(self, insertText: text, replacementRange: NSRange(location: NSNotFound, length: 0))
		return true
	}

	// MARK: - Drag Source

	/// Begins a drag session when the user drags selected text.
	public func beginDragSession(from event: NSEvent) {
		guard let selectedText = accessibilitySelectedText(), !selectedText.isEmpty else { return }

		let item = NSDraggingItem(pasteboardWriter: selectedText as NSString)
		let point = convert(event.locationInWindow, from: nil)
		item.setDraggingFrame(NSRect(origin: point, size: NSSize(width: 100, height: 20)), contents: nil)

		beginDraggingSession(with: [item], event: event, source: self)
	}

	// MARK: - Scroll Support

	/// Scroll to make the primary caret visible.
	public func scrollToCaret() {
		guard let caret = carets.first else { return }
		let rect = layoutManager.caretRect(forLine: caret.line, characterIndex: caret.index)
		scrollToVisible(rect.insetBy(dx: -20, dy: -20))
	}

	// MARK: - Document Offset Conversion

	/// Convert (line, characterIndex) to a flat document character offset.
	private func documentOffset(line: Int, index: Int) -> Int {
		var offset = 0
		for i in 0 ..< min(line, layoutManager.lineCount) {
			offset += (layoutManager.lineText(i)?.count ?? 0) + 1 // +1 for \n
		}
		return offset + index
	}

	/// Convert a flat document character offset to (line, characterIndex).
	private func lineAndIndex(forDocumentOffset offset: Int) -> (Int, Int) {
		var remaining = offset
		for i in 0 ..< layoutManager.lineCount {
			let lineLen = (layoutManager.lineText(i)?.count ?? 0) + 1 // +1 for \n
			if remaining < lineLen {
				return (i, remaining)
			}
			remaining -= lineLen
		}
		return (max(0, layoutManager.lineCount - 1), remaining)
	}

	// MARK: - Spelling Dot Image

	/// Creates the tiled red dot image used for misspelling underlines.
	private static func createSpellingDotImage() -> CGImage? {
		let width = 4
		let height = 3
		guard let ctx = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
		) else { return nil }

		ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.8)
		ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 4, height: 3))
		return ctx.makeImage()
	}

	// MARK: - NSChangeSpelling / NSIgnoreMisspelledWords

	/// Called by the spell checker when the user picks a correction.
	@objc public func changeSpelling(_ sender: Any?) {
		guard let panel = sender as? NSObject,
		      let word = panel.value(forKey: "stringValue") as? String
		else { return }
		delegate?.editorView(self, insertText: word, replacementRange: selectedRange())
	}

	/// Called by the spell checker when the user picks "Ignore Spelling".
	@objc public func ignoreSpelling(_: Any?) {
		guard let selectedText = accessibilitySelectedText(), !selectedText.isEmpty else { return }
		NSSpellChecker.shared.ignoreWord(
			selectedText,
			inSpellDocumentWithTag: delegate?.editorViewSpellDocumentTag(self) ?? 0,
		)
		needsDisplay = true
	}
}

// MARK: - NSAccessibility

public extension EditorView {
	override func isAccessibilityElement() -> Bool {
		true
	}

	override func accessibilityRole() -> NSAccessibility.Role? {
		.textArea
	}

	override func accessibilityRoleDescription() -> String? {
		NSAccessibility.Role.textArea.description(with: nil)
	}

	override func accessibilityValue() -> Any? {
		text
	}

	override func accessibilityNumberOfCharacters() -> Int {
		text.count
	}

	override func accessibilitySelectedText() -> String? {
		guard let sel = selectionRanges.first else { return nil }
		let startOffset = documentOffset(line: sel.start.line, index: sel.start.index)
		let endOffset = documentOffset(line: sel.end.line, index: sel.end.index)
		let fullText = text
		let lo = min(startOffset, endOffset)
		let hi = max(startOffset, endOffset)
		guard let start = fullText.index(fullText.startIndex, offsetBy: lo, limitedBy: fullText.endIndex),
		      let end = fullText.index(fullText.startIndex, offsetBy: hi, limitedBy: fullText.endIndex)
		else { return nil }
		return String(fullText[start ..< end])
	}

	override func accessibilitySelectedTextRange() -> NSRange {
		selectedRange()
	}

	override func accessibilityInsertionPointLineNumber() -> Int {
		carets.first?.line ?? 0
	}

	override func accessibilityString(for range: NSRange) -> String? {
		attributedSubstring(forProposedRange: range, actualRange: nil)?.string
	}

	override func accessibilityLine(for index: Int) -> Int {
		lineAndIndex(forDocumentOffset: index).0
	}

	override func accessibilityRange(forLine lineNumber: Int) -> NSRange {
		let startOffset = documentOffset(line: lineNumber, index: 0)
		let lineLen = layoutManager.lineText(lineNumber)?.count ?? 0
		return NSRange(location: startOffset, length: lineLen)
	}

	override func accessibilityFrame(for range: NSRange) -> NSRect {
		firstRect(forCharacterRange: range, actualRange: nil)
	}

	override func setAccessibilitySelectedTextRange(_ range: NSRange) {
		let (startLine, startIdx) = lineAndIndex(forDocumentOffset: range.location)
		let (endLine, endIdx) = lineAndIndex(forDocumentOffset: range.location + range.length)
		selectionRanges = [(start: (startLine, startIdx), end: (endLine, endIdx))]
		carets = [(startLine, startIdx)]
		needsDisplay = true
	}

	override func accessibilityVisibleCharacterRange() -> NSRange {
		guard let scrollView = enclosingScrollView else {
			return NSRange(location: 0, length: text.count)
		}
		let visibleRect = scrollView.documentVisibleRect
		let firstLine = layoutManager.lineIndex(atY: visibleRect.minY)
		let lastLine = layoutManager.lineIndex(atY: visibleRect.maxY)
		let startOffset = documentOffset(line: firstLine, index: 0)
		let endOffset = documentOffset(line: lastLine + 1, index: 0)
		return NSRange(location: startOffset, length: endOffset - startOffset)
	}
}

// MARK: - Drag and Drop

public extension EditorView {
	override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
		let pb = sender.draggingPasteboard
		if pb.types?.contains(.string) == true || pb.types?.contains(.fileURL) == true {
			return .copy
		}
		return []
	}

	override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
		let point = convert(sender.draggingLocation, from: nil)
		let hit = layoutManager.characterIndex(at: point)
		carets = [(hit.line, hit.index)]
		return .copy
	}

	override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		let pb = sender.draggingPasteboard
		let point = convert(sender.draggingLocation, from: nil)
		let hit = layoutManager.characterIndex(at: point)

		// Handle file URL drops.
		if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
			delegate?.editorView(self, didReceiveFileDrop: urls, atLine: hit.line, index: hit.index)
			return true
		}

		// Handle text drops.
		if let text = pb.string(forType: .string), !text.isEmpty {
			delegate?.editorView(self, insertText: text, replacementRange: NSRange(location: NSNotFound, length: 0))
			return true
		}

		return false
	}
}

// MARK: - NSDraggingSource

extension EditorView: NSDraggingSource {
	public func draggingSession(
		_: NSDraggingSession,
		sourceOperationMaskFor _: NSDraggingContext,
	) -> NSDragOperation {
		.copy
	}
}

// MARK: - Editor View Delegate

/// Delegate protocol for `EditorView` events.
///
/// The delegate bridges between the view layer and the `Editor` engine.
@MainActor
public protocol EditorViewDelegate: AnyObject {
	/// Called when text is typed or pasted.
	func editorView(_ view: EditorView, insertText text: String, replacementRange: NSRange)

	/// Called for standard key bindings (movement, deletion, etc.).
	func editorView(_ view: EditorView, performAction action: EditorViewAction)

	/// Called when the user clicks in the editor.
	func editorView(_ view: EditorView, didClickAtLine line: Int, index: Int, event: NSEvent)

	/// Called during mouse drag for selection extension.
	func editorView(_ view: EditorView, didDragToLine line: Int, index: Int, event: NSEvent)

	/// Called for double-click (word selection).
	func editorViewDidDoubleClick(_ view: EditorView, event: NSEvent)

	/// Called for triple-click (line selection).
	func editorViewDidTripleClick(_ view: EditorView, event: NSEvent)

	/// Called for unhandled selectors (passed through from the key binding system).
	func editorView(_ view: EditorView, doCommandBySelector selector: Selector)

	/// Called when files are dropped onto the editor.
	func editorView(_ view: EditorView, didReceiveFileDrop urls: [URL], atLine line: Int, index: Int)

	/// Called for key equivalents (Cmd+key shortcuts for bundle dispatch).
	/// Return `true` if handled, `false` to pass through.
	func editorView(_ view: EditorView, performKeyEquivalent event: NSEvent) -> Bool

	/// Called when pinch-to-zoom changes the font scale.
	func editorView(_ view: EditorView, fontScaleDidChange scale: CGFloat)

	/// Called to build the right-click context menu.
	func editorViewNeedsContextMenu(_ view: EditorView, for event: NSEvent) -> NSMenu?

	/// Called to validate a menu item's enabled state.
	func editorView(_ view: EditorView, validateMenuItem menuItem: NSMenuItem) -> Bool

	/// Returns the spell document tag for the editor's document.
	func editorViewSpellDocumentTag(_ view: EditorView) -> Int

	/// Returns misspelled ranges for a specific line index.
	func editorView(_ view: EditorView, misspellingsForLine lineIndex: Int) -> [MisspelledRange]

	/// Called to build spelling suggestions for the context menu.
	func editorView(_ view: EditorView, spellingSuggestionsAt point: NSPoint) -> [String]
}

/// Default no-op implementations.
public extension EditorViewDelegate {
	func editorView(_: EditorView, insertText _: String, replacementRange _: NSRange) {}
	func editorView(_: EditorView, performAction _: EditorViewAction) {}
	func editorView(_: EditorView, didClickAtLine _: Int, index _: Int, event _: NSEvent) {}
	func editorView(_: EditorView, didDragToLine _: Int, index _: Int, event _: NSEvent) {}
	func editorViewDidDoubleClick(_: EditorView, event _: NSEvent) {}
	func editorViewDidTripleClick(_: EditorView, event _: NSEvent) {}
	func editorView(_: EditorView, doCommandBySelector _: Selector) {}
	func editorView(_: EditorView, didReceiveFileDrop _: [URL], atLine _: Int, index _: Int) {}
	func editorView(_: EditorView, performKeyEquivalent _: NSEvent) -> Bool {
		false
	}

	func editorView(_: EditorView, fontScaleDidChange _: CGFloat) {}
	func editorViewNeedsContextMenu(_: EditorView, for _: NSEvent) -> NSMenu? {
		nil
	}

	func editorView(_: EditorView, validateMenuItem _: NSMenuItem) -> Bool {
		true
	}

	func editorViewSpellDocumentTag(_: EditorView) -> Int {
		0
	}

	func editorView(_: EditorView, misspellingsForLine _: Int) -> [MisspelledRange] {
		[]
	}

	func editorView(_: EditorView, spellingSuggestionsAt _: NSPoint) -> [String] {
		[]
	}
}

// MARK: - Editor View Action

/// Actions that can be performed via key bindings in the editor view.
///
/// These map to `NSStandardKeyBindingResponding` methods and will be
/// translated to `EditorAction` values by the delegate.
public enum EditorViewAction: String, Sendable {
	// Movement
	case moveUp
	case moveDown
	case moveLeft
	case moveRight
	case moveToBeginningOfLine
	case moveToEndOfLine
	case moveToBeginningOfDocument
	case moveToEndOfDocument
	case moveWordForward
	case moveWordBackward
	case pageUp
	case pageDown

	// Selection extension
	case moveUpAndModifySelection
	case moveDownAndModifySelection
	case moveLeftAndModifySelection
	case moveRightAndModifySelection
	case moveWordForwardAndModifySelection
	case moveWordBackwardAndModifySelection
	case moveToBeginningOfLineAndModifySelection
	case moveToEndOfLineAndModifySelection
	case moveToBeginningOfDocumentAndModifySelection
	case moveToEndOfDocumentAndModifySelection

	// Deletion
	case deleteForward
	case deleteBackward
	case deleteWordForward
	case deleteWordBackward
	case deleteToBeginningOfLine
	case deleteToEndOfLine

	// Insertion
	case insertNewline
	case insertTab
	case insertBacktab

	/// Selection
	case selectAll
}
