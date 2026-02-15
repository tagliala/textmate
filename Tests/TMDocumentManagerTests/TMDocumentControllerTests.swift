import Foundation
import Testing
@testable import TMDocumentManager

@Suite("TMDocumentController - Document Registry")
@MainActor
struct TMDocumentControllerTests {
	// Helper: create a fresh controller for each test
	private func freshController() -> TMDocumentController {
		let controller = TMDocumentController.shared
		controller.removeAll()
		return controller
	}

	// MARK: - Registration

	@Test("Register and retrieve document")
	func registerAndRetrieve() {
		let controller = freshController()
		let doc = TMDocument(path: "/tmp/test_register.txt")
		controller.register(doc)

		let found = controller.documentForUUID(doc.id)
		#expect(found === doc)
	}

	@Test("Count reflects registered documents")
	func documentCount() {
		let controller = freshController()
		#expect(controller.count == 0)

		let doc1 = TMDocument(path: "/tmp/count_1.txt")
		controller.register(doc1)
		#expect(controller.count == 1)

		let doc2 = TMDocument(path: "/tmp/count_2.txt")
		controller.register(doc2)
		#expect(controller.count == 2)
	}

	// MARK: - Path Deduplication

	@Test("Same path returns same document")
	func pathDeduplication() {
		let controller = freshController()
		let doc1 = controller.documentForPath("/tmp/dedup_test.txt")
		let doc2 = controller.documentForPath("/tmp/dedup_test.txt")
		#expect(doc1 === doc2)
	}

	@Test("Different paths return different documents")
	func differentPaths() {
		let controller = freshController()
		let doc1 = controller.documentForPath("/tmp/file_a.txt")
		let doc2 = controller.documentForPath("/tmp/file_b.txt")
		#expect(doc1 !== doc2)
	}

	// MARK: - Find by Path

	@Test("Find document by path")
	func findByPath() {
		let controller = freshController()
		let doc = controller.documentForPath("/tmp/findme.txt")
		let found = controller.findByPath("/tmp/findme.txt")
		#expect(found === doc)
	}

	@Test("Find returns nil for unknown path")
	func findByPathMissing() {
		let controller = freshController()
		let found = controller.findByPath("/nonexistent/path.txt")
		#expect(found == nil)
	}

	// MARK: - UUID Lookup

	@Test("Look up by UUID returns correct document")
	func lookupByUUID() {
		let controller = freshController()
		let doc = TMDocument()
		controller.register(doc)
		#expect(controller.documentForUUID(doc.id) === doc)
	}

	@Test("Look up by unknown UUID returns nil")
	func lookupByUnknownUUID() {
		let controller = freshController()
		#expect(controller.documentForUUID(UUID()) == nil)
	}

	// MARK: - Untitled Documents

	@Test("Create untitled document")
	func createUntitled() {
		let controller = freshController()
		let doc = controller.createUntitledDocument()
		#expect(doc.path == nil)
		#expect(doc.customName == "Untitled")
	}

	@Test("Untitled documents get sequential names")
	func untitledSequence() {
		let controller = freshController()
		let doc1 = controller.createUntitledDocument()
		let doc2 = controller.createUntitledDocument()
		let doc3 = controller.createUntitledDocument()
		#expect(doc1.customName == "Untitled")
		#expect(doc2.customName == "Untitled 2")
		#expect(doc3.customName == "Untitled 3")
	}

	// MARK: - Forget

	@Test("Forget removes document from registry")
	func forgetDocument() {
		let controller = freshController()
		let doc = controller.documentForPath("/tmp/forget_me.txt")
		controller.forget(doc)
		#expect(controller.findByPath("/tmp/forget_me.txt") == nil)
		#expect(controller.documentForUUID(doc.id) == nil)
	}

	// MARK: - Path Changes

	@Test("Document path change updates index")
	func pathChange() {
		let controller = freshController()
		let doc = controller.documentForPath("/tmp/old_name.txt")
		controller.documentDidChangePath(doc, from: "/tmp/old_name.txt", to: "/tmp/new_name.txt")
		doc.setPath("/tmp/new_name.txt")

		#expect(controller.findByPath("/tmp/old_name.txt") == nil)
		#expect(controller.findByPath("/tmp/new_name.txt") === doc)
	}

	// MARK: - LRU Tracking

	@Test("Recently used documents are in order")
	func lruOrder() {
		let controller = freshController()
		let doc1 = controller.documentForPath("/tmp/lru_1.txt")
		let doc2 = controller.documentForPath("/tmp/lru_2.txt")
		let doc3 = controller.documentForPath("/tmp/lru_3.txt")

		let recent = controller.recentlyUsed
		#expect(recent.first === doc3) // Most recently created/touched
		#expect(recent.last === doc1) // Oldest

		// Touch doc1 again
		controller.touchLRU(doc1.id)
		let updated = controller.recentlyUsed
		#expect(updated.first === doc1) // Now most recent
	}

	// MARK: - Filtering

	@Test("Open documents filter")
	func openDocumentsFilter() {
		let controller = freshController()
		let doc1 = controller.documentForPath("/tmp/open_1.txt")
		let doc2 = controller.documentForPath("/tmp/open_2.txt")

		doc1.open()
		#expect(controller.openDocuments.count == 1)
		#expect(controller.openDocuments.first === doc1)

		_ = doc2 // Suppress warning
	}

	@Test("Modified documents filter")
	func modifiedDocumentsFilter() {
		let controller = freshController()
		let doc1 = controller.documentForPath("/tmp/mod_1.txt")
		let doc2 = controller.documentForPath("/tmp/mod_2.txt")

		doc1.markModified()
		#expect(controller.modifiedDocuments.count == 1)
		#expect(controller.hasModifiedDocuments)

		_ = doc2
	}

	@Test("Find with predicate")
	func findWithPredicate() {
		let controller = freshController()
		let doc1 = controller.documentForPath("/tmp/pred_1.swift")
		let doc2 = controller.documentForPath("/tmp/pred_2.txt")

		doc1.fileType = "source.swift"
		doc2.fileType = "text.plain"

		let swiftDocs = controller.find { $0.fileType == "source.swift" }
		#expect(swiftDocs.count == 1)
		#expect(swiftDocs.first === doc1)
	}

	// MARK: - Callbacks

	@Test("Document added callback fires")
	func addedCallback() {
		let controller = freshController()
		var addedCount = 0
		controller.onDocumentAdded = { _ in addedCount += 1 }

		_ = controller.documentForPath("/tmp/callback_test.txt")
		#expect(addedCount == 1)

		controller.onDocumentAdded = nil
	}

	@Test("Document removed callback fires")
	func removedCallback() {
		let controller = freshController()
		var removedCount = 0
		controller.onDocumentRemoved = { _ in removedCount += 1 }

		let doc = controller.documentForPath("/tmp/cb_remove.txt")
		controller.forget(doc)
		#expect(removedCount == 1)

		controller.onDocumentRemoved = nil
	}

	// MARK: - Cleanup

	@Test("Remove all clears the registry")
	func removeAll() {
		let controller = freshController()
		_ = controller.documentForPath("/tmp/cleanup_1.txt")
		_ = controller.documentForPath("/tmp/cleanup_2.txt")
		#expect(controller.count == 2)

		controller.removeAll()
		#expect(controller.count == 0)
	}

	@Test("Prune removes closed, unmodified documents")
	func pruneUnused() {
		let controller = freshController()
		let doc1 = controller.documentForPath("/tmp/prune_1.txt")
		let doc2 = controller.documentForPath("/tmp/prune_2.txt")

		doc1.open()
		// doc2 is not open, not modified → should be pruned

		controller.pruneUnusedDocuments()
		#expect(controller.documentForUUID(doc1.id) != nil)
		#expect(controller.documentForUUID(doc2.id) == nil)
	}

	// MARK: - Debug Summary

	@Test("Debug summary contains counts")
	func debugSummary() {
		let controller = freshController()
		_ = controller.documentForPath("/tmp/summary_1.txt")
		let summary = controller.debugSummary
		#expect(summary.contains("1 total"))
		#expect(summary.contains("0 open"))
	}
}
