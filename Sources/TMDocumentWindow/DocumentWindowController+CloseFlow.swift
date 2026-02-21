import AppKit
import TMDocumentManager

// MARK: - Close Flow & Multi-Document Save

/// Extension implementing the close-warning UI and multi-document save chain,
/// mirroring the C++ `showCloseWarningUIForDocuments:` and
/// `saveDocumentsUsingEnumerator:` patterns.
///
/// The C++ version uses an `NSEnumerator`-based recursive chain to save
/// documents one at a time, presenting alerts as needed. This Swift version
/// uses async/await for the same sequential behavior.
public extension DocumentWindowController {
	// MARK: - Document I/O Result

	/// Result of a document I/O operation, matching C++ `OakDocumentIOResult`.
	enum DocumentIOResult: Sendable {
		case success
		case failure
		case cancel
	}

	// MARK: - Close Warning UI

	/// Present a save-warning sheet for the given documents.
	///
	/// If there is one document, it is selected first. The alert offers
	/// "Save" / "Cancel" / "Don't Save" buttons matching the C++ version.
	///
	/// - Parameters:
	///   - documents: The unsaved documents to warn about.
	///   - callback: Called with `true` if the user allows closing.
	func showCloseWarning(
		for documents: [TMDocument],
		callback: @escaping @MainActor (Bool) -> Void,
	) {
		guard !documents.isEmpty else {
			callback(true)
			return
		}

		// Select the first unsaved document.
		if documents.count == 1, let doc = documents.first,
		   let idx = self.documents.firstIndex(where: { $0 === doc }),
		   idx != selectedTabIndex
		{
			selectedTabIndex = idx
			openAndSelectDocument(doc, activate: true)
		}

		let alert = Self.makeSaveAlert(for: documents)
		guard let window else {
			callback(false)
			return
		}

		alert.beginSheetModal(for: window) { [weak self] response in
			guard let self else { return }
			switch response {
			case .alertFirstButtonReturn: // "Save" / "Save All"
				saveDocuments(documents) { result in
					callback(result == .success)
				}
			case .alertThirdButtonReturn: // "Don't Save"
				callback(true)
			default: // "Cancel"
				callback(false)
			}
		}
	}

	/// Create the standard save-warning alert.
	///
	/// Mirrors C++ `saveAlertForDocuments:`.
	static func makeSaveAlert(for documents: [TMDocument]) -> NSAlert {
		let alert = NSAlert()
		alert.alertStyle = .warning

		if documents.count == 1 {
			let name = documents[0].displayName
			alert.messageText = "Do you want to save the changes you made in the document \"\(name)\"?"
			alert.informativeText = "Your changes will be lost if you don't save them."
			alert.addButton(withTitle: "Save")
			alert.addButton(withTitle: "Cancel")
			alert.addButton(withTitle: "Don't Save")
		} else {
			var body = ""
			for doc in documents {
				body += "• \"\(doc.displayName)\"\n"
			}
			alert.messageText = "Do you want to save documents with changes?"
			alert.informativeText = body
			alert.addButton(withTitle: "Save All")
			alert.addButton(withTitle: "Cancel")
			alert.addButton(withTitle: "Don't Save")
		}

		return alert
	}

	// MARK: - Multi-Document Save Chain

	/// Save an array of documents sequentially, stopping on failure or cancel.
	///
	/// Mirrors C++ `saveDocumentsUsingEnumerator:completionHandler:`.
	///
	/// - Parameters:
	///   - documents: Documents to save.
	///   - completion: Called with the aggregate result.
	func saveDocuments(
		_ documents: [TMDocument],
		completion: (@MainActor (DocumentIOResult) -> Void)? = nil,
	) {
		saveDocumentsIteratively(Array(documents), index: 0, completion: completion)
	}

	/// Recursive helper for sequential document saving.
	private func saveDocumentsIteratively(
		_ documents: [TMDocument],
		index: Int,
		completion: (@MainActor (DocumentIOResult) -> Void)?,
	) {
		guard index < documents.count else {
			completion?(.success)
			return
		}

		let document = documents[index]

		// Ensure the document is the selected one when saving.
		if let idx = self.documents.firstIndex(where: { $0 === document }),
		   idx != selectedTabIndex, document === selectedDocument || document.isModified
		{
			selectedTabIndex = idx
			textDocument = document
			wireDocumentEditor()
		}

		documentEditor?.documentWillSave()
		MarkTracker.shared.saveFromDocument(document)
		document.setContent(documentEditor?.editor.text ?? "")

		Task { @MainActor in
			do {
				try await document.save()
				self.updateWindowTitle()
				self.autoRefreshScheduler?.documentDidSave()
				self.saveDocumentsIteratively(documents, index: index + 1, completion: completion)
			} catch {
				let alert = NSAlert()
				alert.alertStyle = .critical
				alert.messageText = "The document \"\(document.displayName)\" could not be saved."
				alert.informativeText = error.localizedDescription
				alert.addButton(withTitle: "OK")
				if let window = self.window {
					alert.beginSheetModal(for: window) { _ in
						completion?(.failure)
					}
				} else {
					completion?(.failure)
				}
			}
		}
	}

	// MARK: - Save All

	/// Save all documents that have unsaved changes.
	@IBAction func saveAllDocuments(_: Any?) {
		let unsaved = documents.filter(\.isModified)
		saveDocuments(unsaved)
	}

	// MARK: - Window Should Close

	/// Called by the window delegate to determine if the window can close.
	///
	/// If there are unsaved documents, presents the close warning UI and
	/// defers closing until the user responds.
	///
	/// Mirrors C++ `windowShouldClose:`.
	func handleWindowShouldClose() -> Bool {
		let unsaved = documents.filter(\.isModified)
		guard !unsaved.isEmpty else { return true }

		showCloseWarning(for: unsaved) { [weak self] canClose in
			if canClose {
				self?.window?.close()
			}
		}

		return false
	}

	// MARK: - Application Terminate Support

	/// Returns the documents that need saving before quit.
	///
	/// Mirrors C++ `documentsNeedingSaving`.
	var documentsNeedingSaving: [TMDocument]? {
		let unsaved = documents.filter { $0.isModified && $0.path != nil }
		return unsaved.isEmpty ? nil : unsaved
	}

	/// Application terminate coordination across all controllers.
	///
	/// Mirrors C++ `applicationShouldTerminate:`.
	///
	/// - Returns: `.terminateNow` if no unsaved docs, `.terminateLater` if
	///   save dialogs are being shown, `.terminateCancel` if the user cancels.
	static func applicationShouldTerminate() -> NSApplication.TerminateReply {
		var controllersWithUnsaved: [DocumentWindowController] = []
		var allUnsaved: [TMDocument] = []

		for controller in sortedControllers {
			if let docs = controller.documentsNeedingSaving {
				controllersWithUnsaved.append(controller)
				allUnsaved.append(contentsOf: docs)
			}
		}

		if controllersWithUnsaved.isEmpty {
			return .terminateNow
		}

		if controllersWithUnsaved.count == 1 {
			let controller = controllersWithUnsaved[0]
			controller.showCloseWarning(for: controller.documentsNeedingSaving ?? []) { canClose in
				NSApp.reply(toApplicationShouldTerminate: canClose)
			}
			return .terminateLater
		}

		// Multiple controllers with unsaved docs — show aggregate alert.
		let alert = makeSaveAlert(for: allUnsaved)
		switch alert.runModal() {
		case .alertFirstButtonReturn: // "Save All"
			saveControllersSequentially(controllersWithUnsaved) { result in
				NSApp.reply(toApplicationShouldTerminate: result == .success)
			}
			return .terminateLater
		case .alertThirdButtonReturn: // "Don't Save"
			return .terminateNow
		default: // "Cancel"
			return .terminateCancel
		}
	}

	/// Save all controllers' unsaved documents sequentially.
	private static func saveControllersSequentially(
		_ controllers: [DocumentWindowController],
		completion: @escaping @MainActor (DocumentIOResult) -> Void,
	) {
		saveControllerAt(index: 0, controllers: controllers, completion: completion)
	}

	private static func saveControllerAt(
		index: Int,
		controllers: [DocumentWindowController],
		completion: @escaping @MainActor (DocumentIOResult) -> Void,
	) {
		guard index < controllers.count else {
			completion(.success)
			return
		}

		let controller = controllers[index]
		let docs = controller.documentsNeedingSaving ?? []
		controller.saveDocuments(docs) { result in
			if result == .success {
				saveControllerAt(index: index + 1, controllers: controllers, completion: completion)
			} else {
				completion(result)
			}
		}
	}
}
