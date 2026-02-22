#if canImport(AppKit)
import AppKit
import TMBundleUI
import TMCompatibility
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

	// MARK: - Revert

	@objc func revertDocumentToSaved(_: Any?) {
		guard let doc = selectedDocument, doc.path != nil else { return }
		Task { @MainActor in
			try? await doc.reload(mergeChanges: false)
			documentEditor?.reloadFromDocument()
			updateWindowTitle()
			updateTabBar()
		}
	}

	// MARK: - Undo / Redo

	@objc func undo(_: Any?) {
		guard let de = documentEditor, de.editor.canUndo else { return }
		de.undo()
		updateWindowTitle()
	}

	@objc func redo(_: Any?) {
		guard let de = documentEditor, de.editor.canRedo else { return }
		de.redo()
		updateWindowTitle()
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

	// MARK: - Scroll Past End

	@objc func toggleScrollPastEnd(_: Any?) {
		editorView.layoutManager.scrollPastEnd.toggle()
		UserDefaults.standard.set(editorView.layoutManager.scrollPastEnd, forKey: "scrollPastEnd")
		editorView.needsLayout = true
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

	// MARK: - Show Wrap Column

	@objc func toggleShowWrapColumn(_: Any?) {
		editorView.layoutManager.drawWrapColumn.toggle()
		UserDefaults.standard.set(editorView.layoutManager.drawWrapColumn, forKey: "showWrapColumn")
		editorView.needsDisplay = true
	}

	// MARK: - Show Indent Guides

	@objc func toggleShowIndentGuides(_: Any?) {
		editorView.layoutManager.drawIndentGuides.toggle()
		UserDefaults.standard.set(editorView.layoutManager.drawIndentGuides, forKey: "showIndentGuides")
		editorView.needsDisplay = true
	}

	// MARK: - Wrap Column

	@objc func takeWrapColumnFrom(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem else { return }
		let tag = menuItem.tag
		if tag == -1 {
			// "Other…" — show input dialog
			let alert = NSAlert()
			alert.messageText = String(localized: "Wrap Column", comment: "Wrap column dialog title")
			alert.informativeText = String(localized: "Enter the column number:", comment: "Wrap column dialog prompt")
			alert.addButton(withTitle: String(localized: "OK", comment: "Button"))
			alert.addButton(withTitle: String(localized: "Cancel", comment: "Button"))
			let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
			input.integerValue = editorView.layoutManager.wrapColumn > 0 ? editorView.layoutManager.wrapColumn : 80
			alert.accessoryView = input
			guard let w = window else { return }
			alert.beginSheetModal(for: w) { [weak self] response in
				guard response == .alertFirstButtonReturn else { return }
				let col = input.integerValue
				if col > 0 {
					self?.setWrapColumn(col)
				}
			}
		} else {
			setWrapColumn(tag) // 0 = Use Window Frame
		}
	}

	private func setWrapColumn(_ col: Int) {
		editorView.layoutManager.wrapColumn = col
		documentEditor?.editor.wrapColumn = max(col, 1)
		editorView.needsLayout = true
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

	// MARK: - Jump to Mark

	@objc func jumpToNextMark(_: Any?) {
		guard let path = selectedDocument?.path else { return }
		guard let caret = editorView.carets.first else { return }
		let currentLine = caret.line // 0-based
		let allLines = MarkTracker.shared.marks(forPath: path)
			.map(\.line).sorted()
		let next = allLines.first(where: { $0 > currentLine }) ?? allLines.first
		if let targetLine = next {
			goToLine(targetLine + 1) // goToLine expects 1-based
		}
	}

	@objc func jumpToPreviousMark(_: Any?) {
		guard let path = selectedDocument?.path else { return }
		guard let caret = editorView.carets.first else { return }
		let currentLine = caret.line // 0-based
		let allLines = MarkTracker.shared.marks(forPath: path)
			.map(\.line).sorted()
		let prev = allLines.last(where: { $0 < currentLine }) ?? allLines.last
		if let targetLine = prev {
			goToLine(targetLine + 1)
		}
	}

	// MARK: - Toggle Comment

	@objc func toggleComment(_: Any?) {
		documentEditor?.toggleComment()
	}

	// MARK: - Toggle HTML Output

	@objc func toggleHTMLOutput(_: Any?) {
		if let controller = htmlOutputController, controller.window?.isVisible == true {
			controller.window?.orderOut(nil)
		} else {
			let controller = htmlOutputController ?? createHTMLOutputController()
			controller.showWindow(nil)
		}
	}

	// MARK: - Sticky Tab

	@objc func toggleSticky(_: Any?) {
		guard let doc = selectedDocument else { return }
		doc.isSticky.toggle()
		updateTabBar()
	}

	// MARK: - Page Setup

	@objc func runPageLayout(_: Any?) {
		NSApp.runPageLayout(nil)
	}

	// MARK: - Move Focus

	@objc func moveFocus(_: Any?) {
		guard let w = window else { return }
		let outlineView = fileBrowserController.outlineView
		if w.firstResponder === outlineView {
			w.makeFirstResponder(editorView)
		} else {
			w.makeFirstResponder(outlineView)
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
		let findPanel = FindPanelController.shared
		findPanel.navigationDelegate = self
		findPanel.documentIdentifier = selectedDocument?.id
		findPanel.openDocumentPaths = TMDocumentController.shared.documents.compactMap(\.path)
		findPanel.fileBrowserItems = fileBrowserController.selectedFileURLs.map(\.path)
		findPanel.showPanel(withSelection: selection)
	}

	@objc func orderFrontFindInProjectPanel(_: Any?) {
		let selection = documentEditor?.editor.selectedText
		let findPanel = FindPanelController.shared
		findPanel.projectFolder = projectPath
			?? selectedDocument?.path.map { ($0 as NSString).deletingLastPathComponent }
		findPanel.documentIdentifier = selectedDocument?.id
		findPanel.navigationDelegate = self
		findPanel.openDocumentPaths = TMDocumentController.shared.documents.compactMap(\.path)
		findPanel.fileBrowserItems = fileBrowserController.selectedFileURLs.map(\.path)
		findPanel.showPanel(withSelection: selection, scope: .project)
	}

	@objc func findNext(_: Any?) {
		FindPanelController.shared.findNext()
	}

	@objc func findPrevious(_: Any?) {
		FindPanelController.shared.findPrevious()
	}

	@objc func useSelectionForFind(_: Any?) {
		guard let text = documentEditor?.editor.selectedText, !text.isEmpty else { return }
		FindPasteboard.shared.findString = text
	}

	@objc func useSelectionForReplace(_: Any?) {
		guard let text = documentEditor?.editor.selectedText, !text.isEmpty else { return }
		FindPasteboard.shared.replaceString = text
	}

	// MARK: - Incremental Search

	@objc func incrementalSearch(_: Any?) {
		showLiveSearch()
	}

	@objc func incrementalSearchPrevious(_: Any?) {
		showLiveSearch()
		liveSearchBarDidRequestPrevious(liveSearchBar)
	}

	// MARK: - Find All / Replace (delegated to FindPanel)

	@objc func findAllInSelection(_: Any?) {
		let findPanel = FindPanelController.shared
		findPanel.navigationDelegate = self
		findPanel.documentIdentifier = selectedDocument?.id
		findPanel.findAllInSelection()
	}

	@objc func replace(_: Any?) {
		FindPanelController.shared.replace()
	}

	@objc func replaceAndFind(_: Any?) {
		FindPanelController.shared.replaceAndFind()
	}

	@objc func replaceAll(_: Any?) {
		FindPanelController.shared.replaceAll()
	}

	@objc func replaceAllInSelection(_: Any?) {
		FindPanelController.shared.replaceAllInSelection()
	}

	// MARK: - Find Options

	@objc func toggleFindOption(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem else { return }
		let option = FindOptions(rawValue: UInt32(menuItem.tag))
		guard let editor = documentEditor?.editor else { return }
		if editor.findOptions.contains(option) {
			editor.findOptions.remove(option)
		} else {
			editor.findOptions.insert(option)
		}
	}

	// MARK: - Show Find History

	@objc func showFindHistory(_: Any?) {
		let findPanel = FindPanelController.shared
		findPanel.navigationDelegate = self
		findPanel.documentIdentifier = selectedDocument?.id
		findPanel.showFindHistoryPanel()
	}

	// MARK: - Clipboard History

	@objc func showClipboardHistory(_: Any?) {
		// Present a simple pasteboard history via a chooser-style alert
		let history = documentEditor?.editor.clipboards.general
		guard let history, !history.isEmpty else { return }

		// Collect all entries by navigating through the clipboard
		var entries: [String] = []
		if let current = history.current() {
			entries.append(current.text)
		}
		// Navigate backwards to collect older entries
		while let prev = history.previous() {
			if entries.contains(prev.text) { break }
			entries.append(prev.text)
		}
		// Reset position back to most recent
		while history.next() != nil {}

		guard !entries.isEmpty else { return }

		let menu = NSMenu(title: "Clipboard History")
		for (index, text) in entries.enumerated() {
			let preview = String(text.prefix(80)).replacingOccurrences(of: "\n", with: "↵")
			let item = menu.addItem(
				withTitle: preview,
				action: #selector(pasteFromClipboardHistory(_:)),
				keyEquivalent: "",
			)
			item.target = self
			item.tag = index
		}

		if let event = NSApp.currentEvent, let view = editorView as NSView? {
			NSMenu.popUpContextMenu(menu, with: event, for: view)
		}
	}

	@objc private func pasteFromClipboardHistory(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem else { return }
		let index = menuItem.tag
		guard let de = documentEditor else { return }
		let history = de.editor.clipboards.general

		// Navigate to the entry at the given index
		// Reset to newest
		while history.next() != nil {}
		for _ in 0 ..< index {
			_ = history.previous()
		}
		if let entry = history.current() {
			de.beginChangeGrouping()
			de.editor.insertText(entry.text)
			de.endChangeGrouping()
			de.syncAfterEdit()
		}
	}

	// MARK: - Tab Size Other

	@objc func showTabSizeSelectorPanel(_: Any?) {
		let alert = NSAlert()
		alert.messageText = String(localized: "Tab Size", comment: "Tab size dialog title")
		alert.informativeText = String(localized: "Enter the tab size:", comment: "Tab size dialog prompt")
		alert.addButton(withTitle: String(localized: "OK", comment: "Button"))
		alert.addButton(withTitle: String(localized: "Cancel", comment: "Button"))
		let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
		input.integerValue = editorView.layoutManager.tabSize
		alert.accessoryView = input
		guard let w = window else { return }
		alert.beginSheetModal(for: w) { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			let size = input.integerValue
			if size > 0, size <= 32 {
				self?.documentEditor?.editor.tabSize = size
				self?.editorView.layoutManager.tabSize = size
				if let doc = self?.selectedDocument {
					doc.tabSize = size
				}
				self?.editorView.needsDisplay = true
			}
		}
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

	/// Set the project folder from a menu item's represented object (responder chain target).
	@objc func takeProjectPathFrom(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem,
		      let path = menuItem.representedObject as? String
		else { return }
		projectPath = path
	}

	@objc func newDocumentInDirectory(_: Any?) {
		fileBrowserController.newFile(nil)
	}

	// MARK: - Bundle Editor

	@objc func showBundleEditor(_: Any?) {
		guard let index = bundleIndex else { return }
		let editor = BundleEditorController(bundleIndex: index)
		editor.showWindow(nil)
	}

	// MARK: - Run Command

	@objc func orderFrontRunCommandWindow(_: Any?) {
		let panel = RunCommandWindowController.shared
		panel.onExecute = { [weak self] command, output in
			guard let self, let dispatcher = commandDispatcher else { return }
			var bundleCommand = BundleCommand(
				name: "Filter Through Command",
				uuid: "",
				command: command,
				input: .selection,
				output: output,
			)
			bundleCommand.fixShebang()
			Task { @MainActor in
				await dispatcher.execute(command: bundleCommand)
			}
		}
		panel.showPanel(near: window)
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

// MARK: - FindNavigationDelegate

extension DocumentWindowController: FindNavigationDelegate {
	public func selectRange(_ range: LineColumnRange, inDocumentWithID documentID: UUID) {
		// Check if the document is already open in this window.
		if let idx = documents.firstIndex(where: { $0.id == documentID }) {
			selectedTabIndex = idx
			openAndSelectDocument(documents[idx], activate: false)
		}

		// Navigate to the line/column.
		guard let editor = documentEditor?.editor else { return }
		let targetLine = max(0, min(range.startLine, editor.buffer.lines - 1))
		let offset = editor.buffer.lineStart(targetLine) + range.startColumn
		let clampedOffset = min(offset, editor.buffer.size)
		let pos = editor.buffer.convert(offset: clampedOffset)
		editor.selections = SelectionState(caret: pos)
		editorView.carets = [(pos.line, pos.column)]
		editorView.scrollToCaret()
	}

	public func bringToFront() {
		window?.makeKeyAndOrderFront(nil)
	}
}

#endif
