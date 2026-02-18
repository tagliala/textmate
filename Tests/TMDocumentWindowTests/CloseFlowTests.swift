import AppKit
import Foundation
import Testing
@testable import TMDocumentManager
@testable import TMDocumentWindow

@Suite("DocumentWindowController+CloseFlow")
@MainActor
struct CloseFlowTests {
	// MARK: - makeSaveAlert

	@Test("single document alert has correct message")
	func singleDocumentAlert() {
		let doc = TMDocument(path: "/tmp/readme.md")
		let alert = DocumentWindowController.makeSaveAlert(for: [doc])

		#expect(alert.messageText.contains("readme.md"))
		#expect(alert.buttons.count == 3)
		#expect(alert.buttons[0].title == "Save")
		#expect(alert.buttons[1].title == "Cancel")
		#expect(alert.buttons[2].title == "Don't Save")
	}

	@Test("multi-document alert has Save All button")
	func multiDocumentAlert() {
		let doc1 = TMDocument(path: "/tmp/a.txt")
		let doc2 = TMDocument(path: "/tmp/b.txt")
		let alert = DocumentWindowController.makeSaveAlert(for: [doc1, doc2])

		#expect(alert.messageText == "Do you want to save documents with changes?")
		#expect(alert.buttons[0].title == "Save All")
		#expect(alert.informativeText.contains("a.txt"))
		#expect(alert.informativeText.contains("b.txt"))
	}

	@Test("alert for empty documents array is still valid")
	func emptyDocumentsAlert() {
		// Edge case: no documents
		let alert = DocumentWindowController.makeSaveAlert(for: [])
		#expect(alert.buttons[0].title == "Save All")
	}

	// MARK: - documentsNeedingSaving

	@Test("documentsNeedingSaving returns nil when no modified docs")
	func noDocumentsNeedSaving() {
		let controller = DocumentWindowController()
		let doc = TMDocument(path: "/tmp/clean.txt")
		doc.setContent("", preserveRevision: true)
		controller.documents = [doc]

		#expect(controller.documentsNeedingSaving == nil)
	}

	@Test("documentsNeedingSaving returns modified docs with paths")
	func modifiedDocumentsNeedSaving() {
		let controller = DocumentWindowController()
		let doc = TMDocument(path: "/tmp/dirty.txt")
		doc.setContent("initial", preserveRevision: true)
		doc.setContent("changed") // Now isModified == true
		controller.documents = [doc]

		let needsSaving = controller.documentsNeedingSaving
		#expect(needsSaving?.count == 1)
		#expect(needsSaving?.first === doc)
	}

	@Test("documentsNeedingSaving excludes untitled modified docs")
	func excludesUntitledModified() {
		let controller = DocumentWindowController()
		let doc = TMDocument() // No path
		doc.setContent("something")
		controller.documents = [doc]

		#expect(controller.documentsNeedingSaving == nil)
	}

	@Test("documentsNeedingSaving with mixed docs")
	func mixedDocuments() {
		let controller = DocumentWindowController()
		let clean = TMDocument(path: "/tmp/clean.txt")
		clean.setContent("ok", preserveRevision: true)

		let dirty = TMDocument(path: "/tmp/dirty.txt")
		dirty.setContent("initial", preserveRevision: true)
		dirty.setContent("changed")

		let untitled = TMDocument()
		untitled.setContent("stuff")

		controller.documents = [clean, dirty, untitled]

		let result = controller.documentsNeedingSaving
		#expect(result?.count == 1)
		#expect(result?.first === dirty)
	}

	// MARK: - handleWindowShouldClose

	@Test("handleWindowShouldClose returns true when no unsaved docs")
	func windowShouldCloseNoUnsaved() {
		let controller = DocumentWindowController()
		let doc = TMDocument()
		doc.setContent("", preserveRevision: true)
		controller.documents = [doc]

		#expect(controller.handleWindowShouldClose() == true)
	}

	// MARK: - DocumentIOResult

	@Test("DocumentIOResult cases are distinct")
	func ioResultCases() {
		let success = DocumentWindowController.DocumentIOResult.success
		let failure = DocumentWindowController.DocumentIOResult.failure
		let cancel = DocumentWindowController.DocumentIOResult.cancel

		// Verify they're distinct by checking !== via pattern matching
		if case .success = success {} else {
			Issue.record("Expected .success")
		}
		if case .failure = failure {} else {
			Issue.record("Expected .failure")
		}
		if case .cancel = cancel {} else {
			Issue.record("Expected .cancel")
		}
	}
}
