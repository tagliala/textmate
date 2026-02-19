#if canImport(AppKit)
import AppKit
import TMCore
import TMDocumentManager
import TMEditor
import TMEditorUI
import TMSearchReplace
import TMServices

// MARK: - Menu Actions (Responder Chain)

/// Wires unimplemented menu selectors from `MainMenuBuilder` to their
/// corresponding editor, view, or file browser operations.
///
/// Actions here are discoverable via the responder chain when a
/// `DocumentWindowController` (or its editor view) is the first responder.
public extension DocumentWindowController {
	// MARK: - Scroll

	@objc func scrollColumnLeft(_: Any?) {
		let clipView = scrollView.contentView
		var origin = clipView.bounds.origin
		origin.x -= editorView.layoutManager.fontMetrics.columnWidth
		clipView.setBoundsOrigin(origin)
		scrollView.reflectScrolledClipView(clipView)
	}

	@objc func scrollColumnRight(_: Any?) {
		let clipView = scrollView.contentView
		var origin = clipView.bounds.origin
		origin.x += editorView.layoutManager.fontMetrics.columnWidth
		clipView.setBoundsOrigin(origin)
		scrollView.reflectScrolledClipView(clipView)
	}

	// MARK: - Line Numbers

	@objc func toggleLineNumbers(_: Any?) {
		isLineNumbersVisible.toggle()
		gutterWidthConstraint?.constant = isLineNumbersVisible ? gutterView.gutterWidth : 0
		gutterView.isHidden = !isLineNumbersVisible
	}

	// MARK: - Soft Wrap

	@objc func toggleSoftWrap(_: Any?) {
		editorView.layoutManager.softWrap.toggle()
		editorView.needsLayout = true
		editorView.needsDisplay = true
	}

	// MARK: - Show Invisibles (Editor)

	@objc func toggleShowInvisibles(_: Any?) {
		editorView.showInvisibles.toggle()
	}

	// MARK: - Font Size

	@objc func makeTextLarger(_: Any?) {
		let currentSize = editorView.layoutManager.font.pointSize
		let newSize = min(currentSize + 1, 72)
		editorView.layoutManager.setFont(
			.monospacedSystemFont(ofSize: newSize, weight: .regular),
		)
		gutterView.font = .monospacedSystemFont(ofSize: newSize, weight: .regular)
		editorView.needsDisplay = true
	}

	@objc func makeTextSmaller(_: Any?) {
		let currentSize = editorView.layoutManager.font.pointSize
		let newSize = max(currentSize - 1, 6)
		editorView.layoutManager.setFont(
			.monospacedSystemFont(ofSize: newSize, weight: .regular),
		)
		gutterView.font = .monospacedSystemFont(ofSize: newSize, weight: .regular)
		editorView.needsDisplay = true
	}

	@objc func makeTextStandardSize(_: Any?) {
		editorView.layoutManager.setFont(
			.monospacedSystemFont(ofSize: 13, weight: .regular),
		)
		gutterView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
		editorView.needsDisplay = true
	}

	// MARK: - Tab Size

	@objc func takeTabSizeFrom(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem, menuItem.tag > 0 else { return }
		let tabSize = menuItem.tag
		documentEditor?.editor.tabSize = tabSize
		editorView.layoutManager.tabSize = tabSize
		if let doc = selectedDocument {
			doc.tabSize = tabSize
		}
		editorView.needsDisplay = true
	}

	// MARK: - Tab Selection

	@objc func takeSelectedTabIndexFrom(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem else { return }
		let tag = menuItem.tag
		let index: Int = if tag == -1 {
			documents.count - 1
		} else {
			tag
		}
		guard index >= 0, index < documents.count else { return }
		selectedTabIndex = index
		openAndSelectDocument(documents[index], activate: true)
	}

	// MARK: - Bookmarks

	@objc func toggleCurrentBookmark(_: Any?) {
		guard let caret = editorView.carets.first else { return }
		let line = caret.line + 1 // GutterView uses 1-based
		gutterView.toggleBookmark(atLine: line)
	}

	@objc func goToNextBookmark(_: Any?) {
		guard let caret = editorView.carets.first else { return }
		let currentLine = caret.line + 1
		let sorted = gutterView.bookmarkedLines.sorted()
		let next = sorted.first(where: { $0 > currentLine }) ?? sorted.first
		if let targetLine = next {
			goToLine(targetLine)
		}
	}

	@objc func goToPreviousBookmark(_: Any?) {
		guard let caret = editorView.carets.first else { return }
		let currentLine = caret.line + 1
		let sorted = gutterView.bookmarkedLines.sorted()
		let prev = sorted.last(where: { $0 < currentLine }) ?? sorted.last
		if let targetLine = prev {
			goToLine(targetLine)
		}
	}

	// MARK: - Folding

	@objc func toggleCurrentFolding(_: Any?) {
		guard let caret = editorView.carets.first else { return }
		let line = caret.line // 0-based
		documentEditor?.toggleFold(atLine: line)
		updateGutterFoldState()
	}

	@objc func takeLevelToFoldFrom(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem else { return }
		let level = menuItem.tag
		documentEditor?.toggleAllFolds(atLevel: level)
		updateGutterFoldState()
	}

	// MARK: - Find Panel

	@objc func orderFrontFindPanel(_: Any?) {
		let selection = documentEditor?.editor.selectedText
		FindPanelController.shared.showPanel(withSelection: selection)
	}

	// MARK: - Go to Line

	@objc func orderFrontGoToLinePanel(_: Any?) {
		let alert = NSAlert()
		alert.messageText = String(localized: "Go to Line", comment: "Alert title")
		alert.informativeText = String(localized: "Enter a line number:", comment: "Alert info")
		alert.addButton(withTitle: String(localized: "Go", comment: "Button"))
		alert.addButton(withTitle: String(localized: "Cancel", comment: "Button"))

		let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
		input.placeholderString = "1"
		alert.accessoryView = input

		guard let win = window else { return }
		alert.beginSheetModal(for: win) { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			if let lineNumber = Int(input.stringValue), lineNumber > 0 {
				self?.goToLine(lineNumber)
			}
		}
		// Focus the text field after sheet is presented.
		win.makeFirstResponder(input)
	}

	// MARK: - Related File (Header ↔ Implementation)

	@objc func goToRelatedFile(_: Any?) {
		guard let path = selectedDocument?.path else { return }
		let url = URL(fileURLWithPath: path)
		let ext = url.pathExtension.lowercased()
		let base = url.deletingPathExtension()

		let relatedExtensions: [String]
		switch ext {
		case "h":
			relatedExtensions = ["m", "mm", "c", "cc", "cpp", "swift"]
		case "m", "mm", "c", "cc", "cpp":
			relatedExtensions = ["h"]
		case "swift":
			relatedExtensions = ["h"]
		default:
			return
		}

		for relExt in relatedExtensions {
			let relatedURL = base.appendingPathExtension(relExt)
			if FileManager.default.fileExists(atPath: relatedURL.path) {
				openFile(at: relatedURL)
				return
			}
		}
	}

	// MARK: - File Browser Integration

	@objc func revealFileInProject(_: Any?) {
		guard let path = selectedDocument?.path else { return }
		let url = URL(fileURLWithPath: path)
		fileBrowserController.goToURL(url.deletingLastPathComponent())
	}

	@objc func goToProjectFolder(_: Any?) {
		if let path = projectPath {
			fileBrowserController.goToURL(URL(fileURLWithPath: path))
		}
	}

	@objc func newDocumentInDirectory(_: Any?) {
		fileBrowserController.newFile(nil)
	}

	// MARK: - Bundle Editor (stub)

	@objc func showBundleEditor(_: Any?) {
		// Bundle editor UI deferred to a future phase.
	}

	// MARK: - Run Command (stub)

	@objc func orderFrontRunCommandWindow(_: Any?) {
		// Run command window deferred to a future phase.
	}

	// MARK: - Spell Checking

	/// Opens the macOS Spelling panel.
	@objc func showGuessPanel(_: Any?) {
		NSSpellChecker.shared.spellingPanel.orderFront(nil)
	}

	/// Toggles continuous (live) spell checking underlines.
	@objc func toggleContinuousSpellChecking(_: Any?) {
		isSpellCheckingEnabled.toggle()
		documentEditor?.isContinuousSpellCheckingEnabled = isSpellCheckingEnabled
	}

	/// Finds the next misspelled word from the caret and selects it.
	@objc func checkSpelling(_: Any?) {
		guard let editor = documentEditor?.editor else { return }
		let text = editor.text
		guard !text.isEmpty else { return }

		let caretOffset = editor.selections.primary?.head.offset ?? 0

		// Search from caret to end, then wrap from start to caret.
		let results = SpellCheckService.shared.spellCheck(
			text,
			tag: spellDocumentTag,
		)
		guard !results.isEmpty else { return }

		// Find the first misspelled range starting at or after the caret.
		let match = results.first(where: { $0.start >= caretOffset })
			?? results.first // wrap around

		guard let misspelled = match else { return }

		let startPos = editor.buffer.convert(offset: min(misspelled.start, editor.buffer.size))
		let endPos = editor.buffer.convert(offset: min(misspelled.end, editor.buffer.size))
		let range = TMCore.TextRange(anchor: startPos, head: endPos)
		editor.selections = SelectionState([range])
		editorView.carets = [(endPos.line, endPos.column)]
		editorView.selectionRanges = [
			(start: (startPos.line, startPos.column), end: (endPos.line, endPos.column)),
		]
		editorView.scrollToCaret()

		// Update the spelling panel with the misspelled word.
		let startIdx = text.utf8.index(text.startIndex, offsetBy: misspelled.start)
		let endIdx = text.utf8.index(text.startIndex, offsetBy: misspelled.end)
		let word = String(text[startIdx ..< endIdx])
		NSSpellChecker.shared.updateSpellingPanel(withMisspelledWord: word)
	}

	// MARK: - Helpers

	/// Navigate the editor caret to a 1-based line number.
	internal func goToLine(_ lineNumber: Int) {
		guard let editor = documentEditor?.editor else { return }
		let targetLine = max(0, min(lineNumber - 1, editor.buffer.lines - 1))
		let offset = editor.buffer.lineStart(targetLine)
		let pos = editor.buffer.convert(offset: offset)
		editor.selections = SelectionState(caret: pos)
		editorView.carets = [(pos.line, pos.column)]
		editorView.scrollToCaret()
	}

	// MARK: - Macro Recording

	/// Toggles macro recording on/off.
	@objc func toggleMacroRecording(_: Any?) {
		guard let docEditor = documentEditor else { return }
		docEditor.toggleMacroRecording()
		statusBarView.isRecordingMacro = docEditor.macroRecorder.isRecording
	}

	/// Replays the last recorded macro.
	@objc func replayMacro(_: Any?) {
		documentEditor?.replayMacro()
	}
}

#endif
