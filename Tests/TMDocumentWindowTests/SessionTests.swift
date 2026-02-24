import Foundation
import Testing
@testable import TMDocumentManager
@testable import TMDocumentWindow

@Suite("DocumentWindowController+Session")
@MainActor
struct SessionTests {
	// MARK: - SessionDocumentInfo

	@Test("SessionDocumentInfo round-trips through Codable")
	func sessionDocInfoCodable() throws {
		var info = DocumentWindowController.SessionDocumentInfo()
		info.identifier = UUID().uuidString
		info.path = "/tmp/test.swift"
		info.displayName = "test.swift"
		info.isSelected = true
		info.isSticky = false

		let data = try JSONEncoder().encode(info)
		let decoded = try JSONDecoder().decode(
			DocumentWindowController.SessionDocumentInfo.self,
			from: data,
		)

		#expect(decoded.identifier == info.identifier)
		#expect(decoded.path == info.path)
		#expect(decoded.displayName == info.displayName)
		#expect(decoded.isSelected == true)
		#expect(decoded.isSticky == false)
	}

	// MARK: - SessionWindowInfo

	@Test("SessionWindowInfo round-trips through Codable")
	func sessionWindowInfoCodable() throws {
		var info = DocumentWindowController.SessionWindowInfo()
		info.projectPath = "/tmp/project"
		info.fileBrowserVisible = true
		info.fileBrowserWidth = 300
		info.selectedTabIndex = 2
		info.isMiniaturized = false
		info.isFullScreen = true
		info.isZoomed = false

		let data = try JSONEncoder().encode(info)
		let decoded = try JSONDecoder().decode(
			DocumentWindowController.SessionWindowInfo.self,
			from: data,
		)

		#expect(decoded.projectPath == "/tmp/project")
		#expect(decoded.fileBrowserVisible == true)
		#expect(decoded.fileBrowserWidth == 300)
		#expect(decoded.selectedTabIndex == 2)
		#expect(decoded.isFullScreen == true)
		#expect(decoded.isZoomed == false)
	}

	// MARK: - SessionInfo

	@Test("SessionInfo round-trips with multiple projects")
	func sessionInfoCodable() throws {
		var session = DocumentWindowController.SessionInfo()

		var p1 = DocumentWindowController.SessionWindowInfo()
		p1.projectPath = "/tmp/project1"
		p1.documents = [
			DocumentWindowController.SessionDocumentInfo(
				identifier: UUID().uuidString,
				path: "/tmp/project1/a.txt",
			),
		]

		var p2 = DocumentWindowController.SessionWindowInfo()
		p2.projectPath = "/tmp/project2"
		p2.documents = [
			DocumentWindowController.SessionDocumentInfo(
				identifier: UUID().uuidString,
				path: "/tmp/project2/b.txt",
			),
		]

		session.projects = [p1, p2]

		let data = try JSONEncoder().encode(session)
		let decoded = try JSONDecoder().decode(
			DocumentWindowController.SessionInfo.self,
			from: data,
		)

		#expect(decoded.projects.count == 2)
		#expect(decoded.projects[0].projectPath == "/tmp/project1")
		#expect(decoded.projects[1].projectPath == "/tmp/project2")
		#expect(decoded.projects[0].documents.count == 1)
	}

	// MARK: - sessionInfo(includeUntitled:)

	@Test("sessionInfo includes documents with paths")
	func sessionInfoWithPaths() {
		let controller = DocumentWindowController()
		let doc = TMDocument(path: "/tmp/test.swift")
		controller.documents = [doc]
		controller.selectedTabIndex = 0

		let info = controller.sessionInfo(includeUntitled: false)

		#expect(info.documents.count == 1)
		#expect(info.documents[0].path == "/tmp/test.swift")
		#expect(info.documents[0].isSelected == true)
		#expect(info.selectedTabIndex == 0)
	}

	@Test("sessionInfo excludes untitled docs when includeUntitled is false")
	func sessionInfoExcludesUntitled() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument(path: "/tmp/a.txt")
		let doc2 = TMDocument() // untitled, no path
		controller.documents = [doc1, doc2]
		controller.selectedTabIndex = 0

		let info = controller.sessionInfo(includeUntitled: false)
		#expect(info.documents.count == 1)
		#expect(info.documents[0].path == "/tmp/a.txt")
	}

	@Test("sessionInfo includes untitled docs when includeUntitled is true")
	func sessionInfoIncludesUntitled() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument(path: "/tmp/a.txt")
		let doc2 = TMDocument() // untitled
		controller.documents = [doc1, doc2]
		controller.selectedTabIndex = 0

		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.documents.count == 2)
	}

	@Test("sessionInfo tracks sticky documents")
	func sessionInfoStickyDocs() {
		let controller = DocumentWindowController()
		let doc = TMDocument(path: "/tmp/sticky.txt")
		controller.documents = [doc]
		controller.setDocument(doc, sticky: true)

		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.documents[0].isSticky == true)
	}

	@Test("sessionInfo captures project path")
	func sessionInfoProjectPath() {
		let controller = DocumentWindowController()
		controller.defaultProjectPath = "/tmp/myproject"
		controller.projectPath = "/tmp/myproject"

		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.projectPath == "/tmp/myproject")
	}

	@Test("sessionInfo captures file browser state")
	func sessionInfoFileBrowser() {
		let controller = DocumentWindowController()
		controller.fileBrowserWidth = 275

		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.fileBrowserWidth == 275)
	}

	@Test("sessionInfo records selected index correctly")
	func sessionInfoSelectedIndex() {
		let controller = DocumentWindowController()
		let doc1 = TMDocument(path: "/tmp/a.txt")
		let doc2 = TMDocument(path: "/tmp/b.txt")
		controller.documents = [doc1, doc2]
		controller.selectedTabIndex = 1

		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.selectedTabIndex == 1)
		#expect(info.documents[0].isSelected == false)
		#expect(info.documents[1].isSelected == true)
	}

	// MARK: - Session Path

	@Test("sessionPath is in Application Support")
	func sessionPathLocation() {
		let path = DocumentWindowController.sessionPath
		#expect(path.contains("TextMate/Session"))
		#expect(path.hasSuffix("Info.plist"))
	}

	// MARK: - Project State

	@Test("saveProjectState and loadProjectState round-trip")
	func projectStateRoundTrip() throws {
		let controller = DocumentWindowController()
		controller.projectPath = "/tmp/test-project-\(UUID().uuidString)"
		controller.defaultProjectPath = controller.projectPath
		// Need multi-tab or file browser for treatAsProjectWindow
		let doc1 = TMDocument(path: "/tmp/file1.txt")
		let doc2 = TMDocument(path: "/tmp/file2.txt")
		controller.documents = [doc1, doc2]
		controller.selectedTabIndex = 1

		controller.saveProjectState()

		let loaded = try DocumentWindowController.loadProjectState(for: #require(controller.projectPath))
		#expect(loaded != nil)
		#expect(loaded?.selectedTabIndex == 1)
		#expect(loaded?.documents.count == 2)

		// Clean up
		let key = "ProjectState:\(controller.projectPath!)"
		UserDefaults.standard.removeObject(forKey: key)
	}

	@Test("loadProjectState returns nil for unknown path")
	func loadProjectStateUnknown() {
		let state = DocumentWindowController.loadProjectState(for: "/nonexistent/\(UUID().uuidString)")
		#expect(state == nil)
	}

	// MARK: - Disable/Enable Session Save

	@Test("disableSessionSave prevents saveSession")
	func disableSessionSavePreventsSave() {
		DocumentWindowController.disableSessionSave()
		let result = DocumentWindowController.saveSession(includeUntitled: true)
		#expect(result == false)
		DocumentWindowController.enableSessionSave()
	}

	// MARK: - View Override Persistence

	@Test("SessionWindowInfo view overrides round-trip through Codable")
	func viewOverridesCodable() throws {
		var info = DocumentWindowController.SessionWindowInfo()
		info.fontSize = 18
		info.softWrap = true
		info.showInvisibles = true
		info.lineNumbersVisible = false
		info.scrollPastEnd = true

		let data = try JSONEncoder().encode(info)
		let decoded = try JSONDecoder().decode(
			DocumentWindowController.SessionWindowInfo.self,
			from: data,
		)

		#expect(decoded.fontSize == 18)
		#expect(decoded.softWrap == true)
		#expect(decoded.showInvisibles == true)
		#expect(decoded.lineNumbersVisible == false)
		#expect(decoded.scrollPastEnd == true)
	}

	@Test("SessionWindowInfo view overrides default to nil")
	func viewOverridesDefaultNil() throws {
		let info = DocumentWindowController.SessionWindowInfo()
		let data = try JSONEncoder().encode(info)
		let decoded = try JSONDecoder().decode(
			DocumentWindowController.SessionWindowInfo.self,
			from: data,
		)

		#expect(decoded.fontSize == nil)
		#expect(decoded.softWrap == nil)
		#expect(decoded.showInvisibles == nil)
		#expect(decoded.lineNumbersVisible == nil)
		#expect(decoded.scrollPastEnd == nil)
	}

	@Test("sessionInfo captures non-default font size")
	func sessionInfoCapturesFontSize() {
		UserDefaults.standard.removeObject(forKey: "editorFontSize")
		let controller = DocumentWindowController()
		controller.editorView.layoutManager.setFont(
			.monospacedSystemFont(ofSize: 18, weight: .regular),
		)

		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.fontSize == 18)
	}

	@Test("sessionInfo omits default font size")
	func sessionInfoOmitsDefaultFontSize() {
		UserDefaults.standard.removeObject(forKey: "editorFontSize")
		let controller = DocumentWindowController()

		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.fontSize == nil)
	}
}
