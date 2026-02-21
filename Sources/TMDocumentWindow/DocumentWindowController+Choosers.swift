#if canImport(AppKit)
import AppKit
import TMAppKit
import TMCore
import TMFilterList

// MARK: - Chooser Panel Actions (Responder Chain)

/// Wires the symbol chooser into the document window's responder chain.
///
/// "Jump to Symbol…" (⌘⇧T) uses the syntax highlighter's symbol list
/// from the currently active document.
public extension DocumentWindowController {
	@objc func showSymbolChooser(_: Any?) {
		guard let frame = window?.frame else { return }

		let chooser = SymbolChooserController()
		let docName = selectedDocument?.displayName ?? "Untitled"

		let symbols = extractCurrentSymbols()
		chooser.populate(documentName: docName, symbols: symbols)

		chooser.onSelectSymbol = { [weak self] selectionString in
			self?.navigateToSelectionString(selectionString)
		}

		chooser.showWindow(relativeTo: frame)
	}

	/// Extracts symbols from the current document's parsed scopes.
	func extractCurrentSymbols() -> [SymbolDescriptor] {
		guard let de = documentEditor, let idx = bundleIndex else { return [] }
		let text = de.editor.text
		let lines = text.components(separatedBy: "\n").enumerated().map { i, line in
			i < text.components(separatedBy: "\n").count - 1 ? line + "\n" : line
		}
		return de.syntaxHighlighter.extractSymbols(bundleIndex: idx, lines: lines)
	}

	/// Navigates to a selection string (line number or line:column).
	func navigateToSelectionString(_ selectionString: String) {
		guard let editor = documentEditor?.editor else { return }
		let parts = selectionString.split(separator: ":", maxSplits: 1)
		guard let lineNumber = Int(parts[0]), lineNumber > 0 else { return }
		let targetLine = min(lineNumber - 1, editor.buffer.lines - 1)
		let lineStart = editor.buffer.lineStart(targetLine)
		var offset = lineStart
		if parts.count > 1, let col = Int(parts[1]), col > 0 {
			let lineEnd = editor.buffer.lineEnd(targetLine)
			offset = min(lineStart + col - 1, lineEnd)
		}
		let pos = editor.buffer.convert(offset: offset)
		editor.selections = SelectionState(caret: pos)
		editorView.carets = [(pos.line, pos.column)]
		editorView.scrollToCaret()
	}
}

// MARK: - Status Bar Symbol Menu

extension DocumentWindowController {
	/// Populates the status bar symbol popup with extracted symbols.
	public func populateSymbolMenu(_ popup: NSPopUpButton) {
		popup.removeAllItems()

		let symbols = extractCurrentSymbols()
		if symbols.isEmpty {
			popup.addItem(withTitle: "No Symbols")
			popup.lastItem?.isEnabled = false
			return
		}

		for symbol in symbols {
			popup.addItem(withTitle: symbol.name)
			popup.lastItem?.representedObject = symbol.selectionString
			popup.lastItem?.target = self
			popup.lastItem?.action = #selector(symbolMenuItemSelected(_:))
		}

		// Select the symbol at the current caret position
		if let de = documentEditor {
			let caretOffset = de.editor.selections.selections.first?.head.offset ?? 0
			var bestIndex = 0
			for (i, sym) in symbols.enumerated() {
				if sym.offset <= caretOffset {
					bestIndex = i
				}
			}
			popup.selectItem(at: bestIndex)
		}
	}

	@objc private func symbolMenuItemSelected(_ sender: NSMenuItem) {
		guard let selectionString = sender.representedObject as? String else { return }
		navigateToSelectionString(selectionString)
	}
}

#endif
