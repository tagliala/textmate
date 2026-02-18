import AppKit
import TMBundleRuntime
import TMCompatibility
import TMCore
import TMEditor
import TMFileBrowser
import TMHTMLOutput

// MARK: - CommandDispatcherDelegate Conformance

/// Wires the document window into the bundle command execution pipeline.
///
/// When a bundle command is executed, the `CommandDispatcher` calls these
/// methods to gather input data from the editor, build the `TM_*`
/// environment, and route output back (replace selection, insert text,
/// show HTML, tooltip, etc.).
///
/// This is the Swift counterpart of the C++ `DocumentWindowController`'s
/// role as `command::delegate_t` in
/// `Frameworks/DocumentWindow/src/DocumentWindowController.mm`.
extension DocumentWindowController: CommandDispatcherDelegate {
	// MARK: - Input

	public func inputData(
		for source: TMBundleRuntime.CommandInput,
		fallback: TMBundleRuntime.CommandInput,
		format _: TMBundleRuntime.CommandInputFormat,
		scope: String,
	) -> Data {
		guard let editor = documentEditor?.editor else { return Data() }

		let text = resolveInput(source: source, editor: editor, scope: scope)
			?? resolveInput(source: fallback, editor: editor, scope: scope)
			?? ""
		return Data(text.utf8)
	}

	/// Resolves a `CommandInput` source to a text string from the editor.
	private func resolveInput(
		source: TMBundleRuntime.CommandInput,
		editor: Editor,
		scope _: String,
	) -> String? {
		switch source {
		case .selection:
			guard let sel = editor.selectedText, !sel.isEmpty else { return nil }
			return sel

		case .entireDocument:
			return editor.text

		case .line:
			guard let primary = editor.selections.primary else { return nil }
			let pos = editor.buffer.convert(offset: primary.head.offset)
			let lineStart = editor.buffer.lineStart(pos.line)
			let lineEnd: Int = if pos.line + 1 < editor.buffer.lines {
				editor.buffer.lineStart(pos.line + 1)
			} else {
				editor.buffer.size
			}
			return editor.buffer.substring(from: lineStart, to: lineEnd)

		case .word:
			guard let primary = editor.selections.primary else { return nil }
			let offset = primary.head.offset
			let text = editor.text
			guard !text.isEmpty else { return nil }

			// Find word boundaries around the caret offset.
			let bytes = Array(text.utf8)
			guard offset <= bytes.count else { return nil }

			var start = offset
			while start > 0 {
				let b = bytes[start - 1]
				// Simple ASCII word char detection: [a-zA-Z0-9_]
				guard isWordByte(b) else { break }
				start -= 1
			}
			var end = offset
			while end < bytes.count {
				let b = bytes[end]
				guard isWordByte(b) else { break }
				end += 1
			}

			guard end > start else { return nil }
			return editor.buffer.substring(from: start, to: end)

		case .scope:
			// Scope-based input: return the text matching the scope at the caret.
			// Simplified implementation — return the current selection or word.
			return editor.selectedText ?? resolveInput(source: .word, editor: editor, scope: "")

		case .character:
			guard let primary = editor.selections.primary else { return nil }
			let offset = primary.head.offset
			guard offset < editor.buffer.size else { return nil }
			return editor.buffer.substring(from: offset, to: offset + 1)

		case .nothing:
			return ""
		}
	}

	// MARK: - Text Output

	public func applyTextOutput(
		_ text: String,
		placement: TMBundleRuntime.CommandOutput,
		format _: TMBundleRuntime.CommandOutputFormat,
		caret _: TMBundleRuntime.CommandOutputCaret,
	) {
		guard let docEditor = documentEditor else { return }

		docEditor.beginChangeGrouping()
		defer { docEditor.endChangeGrouping() }

		let editor = docEditor.editor

		switch placement {
		case .replaceInput, .replaceSelection:
			// insertText replaces whatever is currently selected.
			editor.insertText(text)

		case .replaceDocument:
			editor.perform(.selectAll)
			editor.insertText(text)

		case .atCaret:
			// Collapse selection to caret first to avoid replacing.
			if editor.hasSelection {
				if let sel = editor.selections.primary {
					editor.selections = SelectionState(caret: sel.head)
				}
			}
			editor.insertText(text)

		case .afterInput:
			// Move caret to end of selection (if any), then insert.
			if let sel = editor.selections.primary, !sel.isEmpty {
				let endPos = sel.end
				editor.selections = SelectionState(caret: endPos)
			}
			editor.insertText(text)

		case .newWindow, .toolTip, .discard:
			// These are handled by other delegate methods.
			break
		}

		syncEditorToView()
	}

	public func showHTMLOutput(
		_ html: String,
		reuse _: TMBundleRuntime.CommandOutputReuse,
		command: TMBundleRuntime.BundleCommand,
	) {
		#if canImport(WebKit)
		let controller = htmlOutputController ?? createHTMLOutputController()
		controller.window?.title = command.name
		controller.commandView.setContent(html)
		controller.showWindow(nil)
		#endif
	}

	public func showToolTip(_ text: String) {
		showHUD(text: text)
	}

	public func showNewDocument(_ text: String) {
		let newController = DocumentWindowController()
		let doc = newController.textDocument
		doc.setContent(text)
		newController.wireDocumentEditor()
		newController.showWindow(nil)
	}

	public func showCompletions(_ text: String) {
		// Parse completion list (one completion per line).
		let completions = text.split(separator: "\n").map(String.init)
		guard !completions.isEmpty, let editor = documentEditor?.editor else { return }

		// Push completions into the editor's completion engine and trigger.
		editor.completionInfo.setSuggestions(completions)
		editor.perform(.complete)
	}

	public func insertSnippet(_ snippet: String, disableAutoIndent _: Bool) {
		guard let docEditor = documentEditor else { return }
		docEditor.beginChangeGrouping()
		defer { docEditor.endChangeGrouping() }

		// For now, insert as plain text. Full snippet expansion (tab stops,
		// mirrors, transformations) is deferred to a future phase.
		docEditor.editor.insertText(snippet)
		syncEditorToView()
	}

	public func showError(
		command: TMBundleRuntime.BundleCommand,
		exitCode: Int,
		stdout: String,
		stderr: String,
	) {
		let combined = (stderr + stdout).trimmingCharacters(in: .whitespacesAndNewlines)
		let message: String
		if combined.isEmpty {
			message = "Command returned status code \(exitCode)."
		} else {
			let lines = combined.components(separatedBy: "\n")
			if lines.count > 7 {
				let head = lines.prefix(4)
				let tail = lines.suffix(3)
				message = (Array(head) + ["\u{22EE}"] + Array(tail)).joined(separator: "\n")
			} else {
				message = combined
			}
		}

		let alert = NSAlert()
		alert.messageText = "Failure running \"\(command.name)\""
		alert.informativeText = message
		alert.alertStyle = .warning
		if let w = window {
			alert.beginSheetModal(for: w)
		} else {
			alert.runModal()
		}
	}

	public func performPreExecAction(_ action: TMBundleRuntime.PreExecAction) async -> Bool {
		switch action {
		case .nop:
			return true
		case .saveDocument:
			return saveDocument()
		case .saveProject:
			// Save all documents in this window's tab group.
			for doc in documents {
				if doc.isModified, doc.path != nil {
					documentEditor?.documentWillSave()
					doc.setContent(documentEditor?.editor.text ?? "")
					do { try await doc.save() } catch { return false }
				}
			}
			return true
		}
	}

	public var currentScope: String {
		documentEditor?.syntaxHighlighter.activeScope ?? ""
	}

	public var workingDirectory: String {
		if let dir = projectPath {
			return dir
		}
		if let path = selectedDocument?.path {
			return (path as NSString).deletingLastPathComponent
		}
		return NSTemporaryDirectory()
	}

	public var environment: [String: String] {
		guard let editor = documentEditor?.editor else {
			return EnvironmentBuilder.buildFull()
		}

		let primary = editor.selections.primary
		let headOffset = primary?.head.offset ?? 0
		let headPos = editor.buffer.convert(offset: headOffset)

		let editorCtx = EnvironmentBuilder.EditorContext(
			tabSize: editor.tabSize,
			softTabs: editor.indentUsingSpaces,
			selectionString: serializeSelections(editor: editor),
			scope: currentScope,
			lineIndex: headPos.column,
			lineNumber: headPos.line + 1,
			columnNumber: headPos.column + 1,
			currentLine: currentLine(editor: editor, line: headPos.line),
			currentWord: resolveInput(source: .word, editor: editor, scope: ""),
			selectedText: editor.selectedText,
		)

		let doc = selectedDocument ?? textDocument
		let docCtx = EnvironmentBuilder.DocumentContext(
			filePath: doc.path,
			displayName: doc.displayName,
			directory: doc.path.map { ($0 as NSString).deletingLastPathComponent },
		)

		let projCtx = EnvironmentBuilder.ProjectContext(
			projectDirectory: projectPath,
		)

		let appCtx = EnvironmentBuilder.AppContext(
			appPath: Bundle.main.bundlePath,
			pid: ProcessInfo.processInfo.processIdentifier,
		)

		var env = EnvironmentBuilder.buildFull(
			editor: editorCtx,
			document: docCtx,
			project: projCtx,
			app: appCtx,
		)

		// Merge file browser variables (TM_SELECTED_FILE, TM_SELECTED_FILES).
		for (key, value) in fileBrowserController.variables {
			env[key] = value
		}

		return env
	}

	// MARK: - Helpers

	/// Returns true if a UTF-8 byte is an ASCII word character [a-zA-Z0-9_].
	private func isWordByte(_ b: UInt8) -> Bool {
		(b >= 0x61 && b <= 0x7A) || // a-z
			(b >= 0x41 && b <= 0x5A) || // A-Z
			(b >= 0x30 && b <= 0x39) || // 0-9
			b == 0x5F // _
	}

	/// Serializes editor selections into the TextMate format: "line:col[-line:col][&…]".
	private func serializeSelections(editor: Editor) -> String {
		let sels = editor.selections.selections
		guard !sels.isEmpty else { return "" }

		return sels.map { sel in
			let from = editor.buffer.convert(offset: sel.start.offset)
			let to = editor.buffer.convert(offset: sel.end.offset)
			if sel.isEmpty {
				return "\(from.line + 1):\(from.column)"
			} else {
				return "\(from.line + 1):\(from.column)-\(to.line + 1):\(to.column)"
			}
		}.joined(separator: "&")
	}

	/// Returns the text of the given line index.
	private func currentLine(editor: Editor, line: Int) -> String {
		let start = editor.buffer.lineStart(line)
		let end: Int = if line + 1 < editor.buffer.lines {
			editor.buffer.lineStart(line + 1)
		} else {
			editor.buffer.size
		}
		return editor.buffer.substring(from: start, to: end)
	}

	/// Re-syncs editor content to the view after a command output edit.
	private func syncEditorToView() {
		guard let docEditor = documentEditor, let view = docEditor.editorView else { return }
		let text = docEditor.editor.text
		docEditor.document.setContent(text)
		view.setText(text)
		docEditor.syntaxHighlighter.setText(text)
		docEditor.syntaxHighlighter.parseSync()

		let sels = docEditor.editor.selections.selections
		var carets: [(line: Int, index: Int)] = []
		for sel in sels {
			let pos = docEditor.editor.buffer.convert(offset: sel.head.offset)
			carets.append((pos.line, pos.column))
		}
		view.carets = carets.isEmpty ? [(0, 0)] : carets
		view.scrollToCaret()
	}

	// MARK: - HTML Output Window

	#if canImport(WebKit)
	/// Lazily-created HTML output window.
	private static var _htmlOutputControllerKey = false

	var htmlOutputController: HTMLOutputWindowController? {
		get { objc_getAssociatedObject(self, &Self._htmlOutputControllerKey) as? HTMLOutputWindowController }
		set {
			objc_setAssociatedObject(self, &Self._htmlOutputControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}
	}

	private func createHTMLOutputController() -> HTMLOutputWindowController {
		let controller = HTMLOutputWindowController()
		htmlOutputController = controller
		return controller
	}
	#endif
}
