import AppKit
import TMAppKit
import TMDocumentManager

// MARK: - Tab Management

/// Extension providing multi-document tab management, mirroring the C++
/// `DocumentWindowController` tab lifecycle:
///
/// - Open / insert / select / close tabs
/// - Sticky document support
/// - New tab / move to new window / merge all windows
/// - Tab bar data source and context menu support
///
/// The C++ version uses `NSArrayController` + KVO for bindings.
/// This Swift version uses a simple `[TMDocument]` array.
public extension DocumentWindowController {
	// MARK: - Sticky Documents

	/// Whether a document is marked as "sticky" (won't auto-close).
	func isDocumentSticky(_ document: TMDocument) -> Bool {
		stickyDocumentIdentifiers.contains(document.id)
	}

	/// Toggle sticky state for a document.
	func setDocument(_ document: TMDocument, sticky: Bool) {
		if sticky {
			stickyDocumentIdentifiers.insert(document.id)
		} else {
			stickyDocumentIdentifiers.remove(document.id)
		}
	}

	// MARK: - Tab Selection

	/// Opens and selects a document, wiring the editor and updating the window.
	///
	/// This is the primary method for switching between tabs. It loads the
	/// document if needed, updates the selected index, and wires the editor.
	///
	/// Mirrors C++ `openAndSelectDocument:activate:`.
	func openAndSelectDocument(_ document: TMDocument, activate: Bool) {
		// Ensure the document is in the documents array.
		if let idx = documents.firstIndex(where: { $0 === document }) {
			selectedTabIndex = idx
		}

		Self.scheduleSessionBackup()

		Task { @MainActor in
			do {
				if document.state != .loaded {
					try await document.load()
				}

				self.textDocument = document
				self.wireDocumentEditor()
				self.updateWindowTitle()

				if activate {
					self.window?.makeFirstResponder(self.editorView)
				}
			} catch {
				// Remove the tab that failed to open.
				if let idx = self.documents.firstIndex(where: { $0 === document }) {
					self.documents.remove(at: idx)
					self.selectedTabIndex = min(self.selectedTabIndex, max(self.documents.count - 1, 0))
				}

				if self.documents.isEmpty {
					self.close()
				}
			}
		}
	}

	/// Select the next tab (wrapping around).
	@IBAction func selectNextTab(_: Any?) {
		guard documents.count > 1 else { return }
		selectedTabIndex = (selectedTabIndex + 1) % documents.count
		openAndSelectDocument(documents[selectedTabIndex], activate: true)
	}

	/// Select the previous tab (wrapping around).
	@IBAction func selectPreviousTab(_: Any?) {
		guard documents.count > 1 else { return }
		selectedTabIndex = (selectedTabIndex + documents.count - 1) % documents.count
		openAndSelectDocument(documents[selectedTabIndex], activate: true)
	}

	// MARK: - Insert Documents

	/// Insert documents at a specific index, optionally closing others.
	///
	/// This mirrors the C++ `insertDocuments:atIndex:selecting:andClosing:`.
	///
	/// - Parameters:
	///   - newDocs: Documents to insert.
	///   - index: Insertion point in the tab bar.
	///   - selectDoc: Which document to select after insertion.
	///   - closeIDs: Identifiers of documents to remove.
	func insertDocuments(
		_ newDocs: [TMDocument],
		atIndex index: Int,
		selecting selectDoc: TMDocument?,
		closing closeIDs: Set<UUID> = [],
	) {
		let newUUIDs = Set(newDocs.map(\.id))

		var result: [TMDocument] = []
		var insertionDone = false

		for (i, doc) in documents.enumerated() {
			// At insertion point, insert new documents.
			if i == min(index, documents.count), !insertionDone {
				insertionDone = true
				var inserted: Set<UUID> = []
				for newDoc in newDocs where !inserted.contains(newDoc.id) {
					result.append(newDoc)
					inserted.insert(newDoc.id)
				}
			}

			// Skip documents being closed.
			if closeIDs.contains(doc.id) { continue }
			// Skip documents being reordered (already inserted above).
			if newUUIDs.contains(doc.id) { continue }

			result.append(doc)
		}

		// If we haven't inserted yet (index >= count), do it now.
		if !insertionDone {
			var inserted: Set<UUID> = []
			for newDoc in newDocs where !inserted.contains(newDoc.id) {
				result.append(newDoc)
				inserted.insert(newDoc.id)
			}
		}

		documents = result
		if let selectDoc {
			selectedTabIndex = documents.firstIndex(where: { $0 === selectDoc }) ?? 0
		}
	}

	// MARK: - New Document

	/// Create a new untitled document in a new tab.
	@IBAction func newDocumentInTab(_: Any?) {
		let doc = TMDocument()
		let closeSet: Set<UUID> = disposableDocumentID.map { [$0] } ?? []
		insertDocuments(
			[doc],
			atIndex: selectedTabIndex + 1,
			selecting: doc,
			closing: closeSet,
		)
		openAndSelectDocument(doc, activate: true)
	}

	/// Move the current tab to a new window.
	@IBAction func moveDocumentToNewWindow(_: Any?) {
		guard documents.count > 1 else { return }
		let doc = documents[selectedTabIndex]

		let controller = DocumentWindowController(document: doc)
		if let path = projectPath, let docPath = doc.path,
		   (docPath as NSString).deletingLastPathComponent.hasPrefix(path)
		{
			controller.defaultProjectPath = projectPath
		}
		controller.showWindow(self)

		closeTabsAtIndexes(
			IndexSet(integer: selectedTabIndex),
			askToSaveChanges: false,
			createDocumentIfEmpty: true,
			activate: true,
		)
	}

	/// Merge all visible windows' documents into this window.
	@IBAction func mergeAllWindows(_: Any?) {
		var allDocs = documents
		var controllersToClose: [DocumentWindowController] = []

		for controller in Self.sortedControllers {
			guard controller !== self, !(controller.window?.isMiniaturized ?? true) else { continue }
			allDocs.append(contentsOf: controller.documents)
			controllersToClose.append(controller)
		}

		documents = allDocs
		for controller in controllersToClose {
			controller.window?.close()
		}
	}

	// MARK: - Close Tabs

	/// Close the document with the given file path, prompting to save if modified.
	func closeDocument(at path: String) {
		guard let index = documents.firstIndex(where: { $0.path == path }) else { return }
		closeTabsAtIndexes(
			IndexSet(integer: index),
			askToSaveChanges: true,
			createDocumentIfEmpty: true,
			activate: true,
		)
	}

	/// Close tabs at specific indexes.
	///
	/// Mirrors C++ `closeTabsAtIndexes:askToSaveChanges:createDocumentIfEmpty:activate:`.
	///
	/// - Parameters:
	///   - indexes: The tab indexes to close.
	///   - askToSaveChanges: Whether to prompt for unsaved changes.
	///   - createDocumentIfEmpty: Whether to create an untitled document if
	///     all tabs are closed.
	///   - activate: Whether to activate the next tab after closing.
	func closeTabsAtIndexes(
		_ indexes: IndexSet,
		askToSaveChanges: Bool,
		createDocumentIfEmpty: Bool,
		activate: Bool,
	) {
		let docsToClose = indexes.compactMap { $0 < documents.count ? documents[$0] : nil }
		guard !docsToClose.isEmpty else { return }

		if askToSaveChanges {
			let unsaved = docsToClose.filter(\.isModified)
			if !unsaved.isEmpty {
				showCloseWarning(for: unsaved) { [weak self] canClose in
					guard let self, canClose else { return }
					closeTabsAtIndexes(
						indexes,
						askToSaveChanges: false,
						createDocumentIfEmpty: createDocumentIfEmpty,
						activate: activate,
					)
				}
				return
			}
		}

		let closingIDs = Set(docsToClose.map(\.id))
		let selectedID = selectedDocument?.id

		var newDocs: [TMDocument] = []
		var newSelectedIndex = selectedTabIndex

		for doc in documents where !closingIDs.contains(doc.id) {
			newDocs.append(doc)
			if doc.id == selectedID {
				newSelectedIndex = max(newDocs.count - 1, 0)
			}
		}

		if createDocumentIfEmpty, newDocs.isEmpty {
			newDocs.append(TMDocument())
		}

		documents = newDocs
		selectedTabIndex = min(newSelectedIndex, max(documents.count - 1, 0))

		if !documents.isEmpty, documents[selectedTabIndex].id != selectedID {
			openAndSelectDocument(documents[selectedTabIndex], activate: activate)
		}
	}

	/// Close the selected tab.
	@IBAction func performCloseTab(_: Any?) {
		guard !documents.isEmpty else {
			window?.performClose(self)
			return
		}

		// If only one tab and it's disposable or no file browser, close the window.
		if documents.count == 1 {
			let doc = documents[0]
			let isDisposable = doc.path == nil && !doc.isModified && (doc.content ?? "").isEmpty
			if isDisposable || !isFileBrowserVisible {
				window?.performClose(self)
				return
			}
		}

		closeTabsAtIndexes(
			IndexSet(integer: selectedTabIndex),
			askToSaveChanges: true,
			createDocumentIfEmpty: true,
			activate: true,
		)
	}

	/// Close all non-sticky, non-dirty tabs.
	@IBAction func performCloseAllTabs(_: Any?) {
		let indexes = IndexSet(
			documents.indices.filter { idx in
				let doc = documents[idx]
				return !isDocumentSticky(doc) && (!doc.isModified || doc.path != nil)
			},
		)
		closeTabsAtIndexes(indexes, askToSaveChanges: true, createDocumentIfEmpty: true, activate: true)
	}

	/// Close all tabs except the selected one.
	@IBAction func performCloseOtherTabs(_: Any?) {
		var indexes = IndexSet(
			documents.indices.filter { idx in
				let doc = documents[idx]
				return !isDocumentSticky(doc) && (!doc.isModified || doc.path != nil)
			},
		)
		indexes.remove(selectedTabIndex)
		closeTabsAtIndexes(indexes, askToSaveChanges: true, createDocumentIfEmpty: true, activate: true)
	}

	/// Close tabs to the right of the selected tab.
	@IBAction func performCloseTabsToTheRight(_: Any?) {
		let from = selectedTabIndex + 1
		guard from < documents.count else { return }
		closeTabsAtIndexes(
			IndexSet(from ..< documents.count),
			askToSaveChanges: true,
			createDocumentIfEmpty: true,
			activate: true,
		)
	}

	/// Close tabs to the left of the selected tab.
	@IBAction func performCloseTabsToTheLeft(_: Any?) {
		guard selectedTabIndex > 0 else { return }
		closeTabsAtIndexes(
			IndexSet(0 ..< selectedTabIndex),
			askToSaveChanges: true,
			createDocumentIfEmpty: true,
			activate: true,
		)
	}

	/// Close the window.
	@IBAction func performCloseWindow(_: Any?) {
		window?.performClose(self)
	}

	// MARK: - Helpers

	/// UUID of the disposable document at the selected tab, if any.
	private var disposableDocumentID: UUID? {
		guard let idx = disposableDocumentIndex else { return nil }
		return documents[idx].id
	}
}

// MARK: - TabBarViewDelegate

extension DocumentWindowController: TabBarViewDelegate {
	public func tabBarView(_: TabBarView, didSelectTabAt index: Int) {
		guard index >= 0, index < documents.count else { return }
		openAndSelectDocument(documents[index], activate: true)
	}

	public func tabBarView(_: TabBarView, didCloseTabAt index: Int) {
		guard index >= 0, index < documents.count else { return }
		closeTabsAtIndexes(
			IndexSet(integer: index),
			askToSaveChanges: true,
			createDocumentIfEmpty: true,
			activate: true,
		)
	}

	public func tabBarView(_: TabBarView, didReorderTabFrom fromIndex: Int, to toIndex: Int) {
		guard fromIndex >= 0, fromIndex < documents.count,
		      toIndex >= 0, toIndex < documents.count,
		      fromIndex != toIndex
		else { return }
		let doc = documents.remove(at: fromIndex)
		documents.insert(doc, at: toIndex)
		selectedTabIndex = toIndex
	}

	public func tabBarView(_: TabBarView, didReceiveFileDrop urls: [URL]) {
		let newDocs = urls.filter(\.isFileURL).map { TMDocument(path: $0.path) }
		guard !newDocs.isEmpty else { return }
		insertDocuments(
			newDocs,
			atIndex: documents.count,
			selecting: newDocs.first,
		)
		if let first = newDocs.first {
			openAndSelectDocument(first, activate: true)
		}
	}

	public func tabBarView(_: TabBarView, didReceiveTabFrom sourceWindowID: UUID, tabIndex: Int, dropIndex: Int) {
		guard let source = Self.allControllers[sourceWindowID],
		      tabIndex >= 0, tabIndex < source.documents.count
		else { return }

		let doc = source.documents[tabIndex]

		// Remove from source window.
		source.closeTabsAtIndexes(
			IndexSet(integer: tabIndex),
			askToSaveChanges: false,
			createDocumentIfEmpty: true,
			activate: true,
		)

		// Insert into this window.
		let clampedIndex = min(dropIndex, documents.count)
		insertDocuments([doc], atIndex: clampedIndex, selecting: doc)
		openAndSelectDocument(doc, activate: true)
	}

	public func tabBarView(_: TabBarView, didTearOffTabAt index: Int, screenPoint: NSPoint) {
		guard documents.count > 1, index >= 0, index < documents.count else { return }

		let doc = documents[index]
		let controller = DocumentWindowController(document: doc)
		if let path = projectPath {
			controller.defaultProjectPath = path
		}

		// Position the new window at the drop point.
		if let win = controller.window {
			let origin = NSPoint(x: screenPoint.x - win.frame.width / 2, y: screenPoint.y - win.frame.height)
			win.setFrameOrigin(origin)
		}
		controller.showWindow(self)

		closeTabsAtIndexes(
			IndexSet(integer: index),
			askToSaveChanges: false,
			createDocumentIfEmpty: true,
			activate: true,
		)
	}
}
