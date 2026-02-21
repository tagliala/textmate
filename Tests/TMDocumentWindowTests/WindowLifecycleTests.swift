import AppKit
import Testing
import TMBundleRuntime
@testable import TMDocumentManager
@testable import TMDocumentWindow
@testable import TMEditorUI
@testable import TMFileBrowser
@testable import TMSCM

// MARK: - NSWindowDelegate Lifecycle

@Suite("DocumentWindowController – Window Lifecycle")
@MainActor
struct WindowLifecycleTests {
	@Test("window.delegate is set to the controller")
	func windowDelegateIsSet() {
		let controller = DocumentWindowController()
		#expect(controller.window?.delegate === controller)
	}

	@Test("closing window removes controller from allControllers")
	func windowCloseRemovesFromRegistry() throws {
		let controller = DocumentWindowController()
		let id = controller.identifier
		#expect(id != nil)
		#expect(try DocumentWindowController.allControllers[#require(id)] === controller)

		// Simulate window closing.
		controller.windowWillClose(
			Notification(name: NSWindow.willCloseNotification, object: controller.window),
		)

		#expect(try DocumentWindowController.allControllers[#require(id)] == nil)
	}

	@Test("windowShouldClose returns true for clean documents")
	func shouldCloseCleanDocuments() throws {
		let controller = DocumentWindowController()
		let doc = TMDocument(path: "/tmp/clean.txt")
		doc.setContent("hello", preserveRevision: true)
		controller.documents = [doc]

		let result = try controller.windowShouldClose(#require(controller.window))
		#expect(result == true)
	}
}

// MARK: - SCM Status Mapping

@Suite("SCMStatus → FileItemImage.SCMStatus Mapping")
@MainActor
struct SCMStatusMappingTests {
	@Test("modified maps to modified")
	func modifiedMapping() {
		#expect(SCMStatus.modified.toFileBrowserStatus == .modified)
	}

	@Test("added maps to added")
	func addedMapping() {
		#expect(SCMStatus.added.toFileBrowserStatus == .added)
	}

	@Test("deleted maps to deleted")
	func deletedMapping() {
		#expect(SCMStatus.deleted.toFileBrowserStatus == .deleted)
	}

	@Test("conflicted maps to conflicted")
	func conflictedMapping() {
		#expect(SCMStatus.conflicted.toFileBrowserStatus == .conflicted)
	}

	@Test("unversioned maps to unversioned")
	func unversionedMapping() {
		#expect(SCMStatus.unversioned.toFileBrowserStatus == .unversioned)
	}

	@Test("mixed maps to mixed")
	func mixedMapping() {
		#expect(SCMStatus.mixed.toFileBrowserStatus == .mixed)
	}

	@Test("unknown maps to unknown")
	func unknownMapping() {
		#expect(SCMStatus.unknown.toFileBrowserStatus == .unknown)
	}

	@Test("none maps to none")
	func noneMapping() {
		#expect(SCMStatus.none.toFileBrowserStatus == .none)
	}

	@Test("ignored maps to none")
	func ignoredMapping() {
		#expect(SCMStatus.ignored.toFileBrowserStatus == .none)
	}

	@Test("all cases are covered")
	func allCasesCovered() {
		for status in SCMStatus.allCases {
			// Should not crash.
			_ = status.toFileBrowserStatus
		}
	}
}

// MARK: - File Browser SCM Provider

@Suite("FileBrowserViewController – SCM Status Provider")
@MainActor
struct FileBrowserSCMProviderTests {
	@Test("scmStatusProvider defaults to nil")
	func defaultProviderIsNil() {
		let fb = FileBrowserViewController()
		#expect(fb.scmStatusProvider == nil)
	}

	@Test("scmStatusProvider can be set to a closure")
	func providerCanBeSet() {
		let fb = FileBrowserViewController()
		fb.scmStatusProvider = { _ in .modified }
		let status = fb.scmStatusProvider?(URL(fileURLWithPath: "/tmp/test.txt"))
		#expect(status == .modified)
	}
}

// MARK: - TMDocumentEditor Reload

@Suite("TMDocumentEditor – Reload From Document")
@MainActor
struct DocumentEditorReloadTests {
	@Test("reloadFromDocument syncs changed content to editor")
	func reloadSyncsContent() {
		let doc = TMDocument(path: "/tmp/reload-test.txt")
		doc.setContent("original", preserveRevision: true)
		let view = EditorView()
		let editor = TMDocumentEditor(document: doc, editorView: view)

		// Simulate external content change.
		doc.setContent("updated externally", preserveRevision: true)
		editor.reloadFromDocument()

		#expect(editor.editor.text == "updated externally")
	}
}

// MARK: - Auto-Refresh Scheduler Wiring

@Suite("DocumentWindowController – Auto-Refresh Wiring")
@MainActor
struct AutoRefreshWiringTests {
	private func makeController() -> DocumentWindowController {
		let doc = TMDocument()
		doc.setContent("hello", preserveRevision: true)
		let controller = DocumentWindowController(document: doc)
		let index = BundleIndex()
		let policy = SecurityPolicy()
		controller.bundleIndex = index
		controller.commandDispatcher = CommandDispatcher(bundleIndex: index, securityPolicy: policy)
		controller.wireDocumentEditor()
		return controller
	}

	@Test("wireDocumentEditor creates autoRefreshScheduler")
	func schedulerCreated() {
		let controller = makeController()
		#expect(controller.autoRefreshScheduler != nil)
	}

	@Test("autoRefreshScheduler is nil without commandDispatcher")
	func noSchedulerWithoutDispatcher() {
		let doc = TMDocument()
		doc.setContent("", preserveRevision: true)
		let controller = DocumentWindowController(document: doc)
		// No commandDispatcher set.
		controller.wireDocumentEditor()
		#expect(controller.autoRefreshScheduler == nil)
	}

	@Test("onContentChanged is wired to editor")
	func contentChangedWired() {
		let controller = makeController()
		#expect(controller.documentEditor?.onContentChanged != nil)
	}

	@Test("windowWillClose calls unregisterAll")
	func closeUnregisters() throws {
		let controller = makeController()
		let scheduler = try #require(controller.autoRefreshScheduler)
		let cmd = BundleCommand(
			name: "Test",
			uuid: "auto-1",
			command: "echo",
			autoRefresh: .onDocumentSave,
		)
		scheduler.register(command: cmd)
		#expect(scheduler.registeredCount == 1)

		controller.windowWillClose(
			Notification(name: NSWindow.willCloseNotification, object: controller.window),
		)
		#expect(scheduler.registeredCount == 0)
	}

	@Test("editor content change forwards to scheduler")
	func contentChangeForwards() {
		let controller = makeController()
		// Register a command that triggers on document change.
		let cmd = BundleCommand(
			name: "OnChange",
			uuid: "auto-change-1",
			command: "echo changed",
			autoRefresh: .onDocumentChange,
		)
		controller.autoRefreshScheduler?.register(command: cmd)
		#expect(controller.autoRefreshScheduler?.registeredCount == 1)

		// Trigger a content change — just verify it doesn't crash.
		controller.documentEditor?.onContentChanged?()
	}
}

// MARK: - MarkTracker Wiring

@Suite("DocumentWindowController – MarkTracker Wiring")
@MainActor
struct MarkTrackerWiringTests {
	@Test("wireDocumentEditor loads marks from tracker")
	func loadsMarksOnWire() {
		// Arrange: place a bookmark in the tracker for a known path.
		let path = "/tmp/mark-test-\(UUID()).txt"
		MarkTracker.shared.addBookmark(atLine: 5, forPath: path)

		let doc = TMDocument(path: path)
		doc.setContent("line\nline\nline\nline\nline\nline\n", preserveRevision: true)
		let controller = DocumentWindowController(document: doc)
		controller.wireDocumentEditor()

		#expect(doc.bookmarks.contains(5))

		// Cleanup
		MarkTracker.shared.removeAllMarks(forPath: path)
	}

	@Test("windowWillClose saves marks for all documents")
	func savesMarksOnClose() {
		let uniqueName = "mark-close-\(UUID()).txt"
		let path = "/tmp/\(uniqueName)"
		let doc = TMDocument(path: path)
		doc.setContent("hello", preserveRevision: true)

		let controller = DocumentWindowController(document: doc)
		controller.wireDocumentEditor()

		// Set bookmarks after wiring (which loads from tracker and finds nothing).
		doc.bookmarks = [3, 7]

		controller.windowWillClose(
			Notification(name: NSWindow.willCloseNotification, object: controller.window),
		)

		// MarkTracker canonicalizes paths (resolves symlinks), so use canonical path.
		let canonicalPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
		let stored = MarkTracker.shared.bookmarks(forPath: canonicalPath)
		#expect(stored.contains(3))
		#expect(stored.contains(7))

		// Cleanup
		MarkTracker.shared.removeAllMarks(forPath: canonicalPath)
	}
}
