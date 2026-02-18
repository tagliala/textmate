import Foundation
import Testing
@testable import TMDocumentManager
@testable import TMDocumentWindow

@Suite("DocumentWindowController+TabManagement")
@MainActor
struct TabManagementTests {
	// MARK: - Sticky Documents

	@Test("sticky documents are tracked by UUID")
	func stickyDocuments() {
		let controller = DocumentWindowController()
		let doc = TMDocument()
		controller.documents = [doc]
		controller.selectedTabIndex = 0

		#expect(!controller.isDocumentSticky(doc))
		controller.setDocument(doc, sticky: true)
		#expect(controller.isDocumentSticky(doc))
		controller.setDocument(doc, sticky: false)
		#expect(!controller.isDocumentSticky(doc))
	}

	@Test("sticky state persists when document is in different position")
	func stickyPersistsAcrossReorder() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument()
		let doc2 = TMDocument()
		controller.documents = [doc1, doc2]

		controller.setDocument(doc1, sticky: true)
		#expect(controller.isDocumentSticky(doc1))
		#expect(!controller.isDocumentSticky(doc2))

		// Reorder documents
		controller.documents = [doc2, doc1]
		#expect(controller.isDocumentSticky(doc1))
		#expect(!controller.isDocumentSticky(doc2))
	}

	// MARK: - Tab Selection

	@Test("selectNextTab wraps around")
	func selectNextTabWraps() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument(path: "/tmp/a.txt")
		let doc2 = TMDocument(path: "/tmp/b.txt")
		let doc3 = TMDocument(path: "/tmp/c.txt")
		controller.documents = [doc1, doc2, doc3]
		controller.selectedTabIndex = 2

		controller.selectNextTab(nil)
		#expect(controller.selectedTabIndex == 0)
	}

	@Test("selectPreviousTab wraps around")
	func selectPreviousTabWraps() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument(path: "/tmp/a.txt")
		let doc2 = TMDocument(path: "/tmp/b.txt")
		controller.documents = [doc1, doc2]
		controller.selectedTabIndex = 0

		controller.selectPreviousTab(nil)
		#expect(controller.selectedTabIndex == 1)
	}

	@Test("selectNextTab noop for single document")
	func selectNextTabSingleDoc() {
		let controller = DocumentWindowController()
		controller.selectedTabIndex = 0

		controller.selectNextTab(nil)
		#expect(controller.selectedTabIndex == 0)
	}

	// MARK: - Insert Documents

	@Test("insertDocuments at index adds documents")
	func insertDocumentsAtIndex() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument()
		controller.documents = [doc1]

		let doc2 = TMDocument()
		let doc3 = TMDocument()
		controller.insertDocuments([doc2, doc3], atIndex: 1, selecting: doc2)

		#expect(controller.documents.count == 3)
		#expect(controller.documents[0] === doc1)
		#expect(controller.documents[1] === doc2)
		#expect(controller.documents[2] === doc3)
		#expect(controller.selectedTabIndex == 1)
	}

	@Test("insertDocuments with closing removes specified documents")
	func insertDocumentsWithClosing() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument()
		let doc2 = TMDocument()
		controller.documents = [doc1, doc2]

		let doc3 = TMDocument()
		controller.insertDocuments(
			[doc3],
			atIndex: 1,
			selecting: doc3,
			closing: [doc1.id],
		)

		#expect(controller.documents.count == 2)
		#expect(controller.documents[0] === doc3)
		#expect(controller.documents[1] === doc2)
	}

	@Test("insertDocuments at end when index exceeds count")
	func insertDocumentsAtEnd() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument()
		controller.documents = [doc1]

		let doc2 = TMDocument()
		controller.insertDocuments([doc2], atIndex: 100, selecting: doc2)

		#expect(controller.documents.count == 2)
		#expect(controller.documents[1] === doc2)
	}

	// MARK: - Disposable Document

	@Test("disposable document index returns selected empty untitled doc")
	func disposableDocumentIndex() {
		let controller = DocumentWindowController()
		let doc = TMDocument()
		doc.setContent("", preserveRevision: true)
		controller.documents = [doc]
		controller.selectedTabIndex = 0

		#expect(controller.disposableDocumentIndex == 0)
	}

	@Test("disposable document index returns nil for non-empty doc")
	func disposableDocumentIndexNonEmpty() {
		let controller = DocumentWindowController()
		let doc = TMDocument()
		doc.setContent("hello")
		controller.documents = [doc]
		controller.selectedTabIndex = 0

		#expect(controller.disposableDocumentIndex == nil)
	}

	@Test("disposable document index returns nil for doc with path")
	func disposableDocumentIndexWithPath() {
		let controller = DocumentWindowController()
		let doc = TMDocument(path: "/tmp/test.txt")
		doc.setContent("", preserveRevision: true)
		controller.documents = [doc]
		controller.selectedTabIndex = 0

		#expect(controller.disposableDocumentIndex == nil)
	}

	// MARK: - Close Tabs

	@Test("closeTabsAtIndexes removes specified tabs")
	func closeTabsAtIndexes() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument(path: "/tmp/a.txt")
		let doc2 = TMDocument(path: "/tmp/b.txt")
		let doc3 = TMDocument(path: "/tmp/c.txt")
		controller.documents = [doc1, doc2, doc3]
		controller.selectedTabIndex = 0

		controller.closeTabsAtIndexes(
			IndexSet([1]),
			askToSaveChanges: false,
			createDocumentIfEmpty: false,
			activate: false,
		)

		#expect(controller.documents.count == 2)
		#expect(controller.documents[0] === doc1)
		#expect(controller.documents[1] === doc3)
	}

	@Test("closeTabsAtIndexes creates empty doc when all tabs closed")
	func closeTabsCreatesEmpty() {
		let controller = DocumentWindowController()
		let doc = TMDocument(path: "/tmp/a.txt")
		controller.documents = [doc]
		controller.selectedTabIndex = 0

		controller.closeTabsAtIndexes(
			IndexSet([0]),
			askToSaveChanges: false,
			createDocumentIfEmpty: true,
			activate: false,
		)

		#expect(controller.documents.count == 1)
		#expect(controller.documents[0].path == nil)
	}

	@Test("closeTabsAtIndexes adjusts selected index")
	func closeTabsAdjustsSelection() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument(path: "/tmp/a.txt")
		let doc2 = TMDocument(path: "/tmp/b.txt")
		let doc3 = TMDocument(path: "/tmp/c.txt")
		controller.documents = [doc1, doc2, doc3]
		controller.selectedTabIndex = 2

		controller.closeTabsAtIndexes(
			IndexSet([2]),
			askToSaveChanges: false,
			createDocumentIfEmpty: false,
			activate: false,
		)

		#expect(controller.documents.count == 2)
		#expect(controller.selectedTabIndex <= 1)
	}

	// MARK: - treatAsProjectWindow

	@Test("treatAsProjectWindow requires project path and browser or multi-tab")
	func treatAsProjectWindow() {
		let controller = DocumentWindowController()
		controller.projectPath = nil
		#expect(!controller.treatAsProjectWindow)

		controller.projectPath = "/tmp/project"
		// Single tab, no file browser → not a project window (browser visibility
		// depends on private state, so we test the combination).
		let doc2 = TMDocument()
		controller.documents.append(doc2)
		#expect(controller.treatAsProjectWindow) // multi-tab with project path
	}

	// MARK: - AllControllers Registry

	@Test("controller registers in allControllers on init")
	func controllerRegistration() {
		let controller = DocumentWindowController()
		guard let id = controller.identifier else {
			Issue.record("Controller should have an identifier")
			return
		}
		#expect(DocumentWindowController.allControllers[id] === controller)
	}

	@Test("controller deregisters when identifier changes")
	func controllerDeregistration() throws {
		let controller = DocumentWindowController()
		let oldID = try #require(controller.identifier)
		controller.identifier = nil
		#expect(DocumentWindowController.allControllers[oldID] == nil)
	}

	// MARK: - Tab Bar Sync

	@Test("updateTabBar creates tabs matching documents")
	func updateTabBarSync() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument(path: "/tmp/alpha.txt")
		let doc2 = TMDocument(path: "/tmp/beta.txt")
		controller.documents = [doc1, doc2]
		controller.selectedTabIndex = 1
		controller.updateTabBar()

		#expect(controller.tabBarView.tabs.count == 2)
		#expect(controller.tabBarView.tabs[0].title == doc1.displayName)
		#expect(controller.tabBarView.tabs[1].title == doc2.displayName)
		#expect(controller.tabBarView.selectedIndex == 1)
	}
}
