import AppKit
import Testing
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
