#if canImport(AppKit)
import AppKit
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

		// Symbol extraction from the grammar is deferred to a future phase.
		// For now, populate with an empty list; the panel still provides
		// the search UI structure.
		chooser.populate(documentName: docName, symbols: [])

		chooser.onSelectSymbol = { [weak self] selectionString in
			guard let self, let editor = documentEditor?.editor else { return }
			if let lineNumber = Int(selectionString), lineNumber > 0 {
				let targetLine = min(lineNumber - 1, editor.buffer.lines - 1)
				let offset = editor.buffer.lineStart(targetLine)
				let pos = editor.buffer.convert(offset: offset)
				editor.selections = SelectionState(caret: pos)
				editorView.carets = [(pos.line, pos.column)]
				editorView.scrollToCaret()
			}
		}

		chooser.showWindow(relativeTo: frame)
	}
}

#endif
