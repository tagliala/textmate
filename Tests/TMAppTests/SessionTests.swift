#if canImport(AppKit)
import Foundation
import Testing
@testable import TMDocumentWindow

@Suite("Session Save/Restore")
@MainActor
struct SessionTests {
	@Test("sessionInfo captures project path")
	func sessionInfoProjectPath() {
		let controller = DocumentWindowController()
		controller.defaultProjectPath = "/tmp/test-project"
		controller.projectPath = "/tmp/test-project"

		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.projectPath == "/tmp/test-project")
	}

	@Test("sessionInfo captures documents")
	func sessionInfoDocuments() {
		let controller = DocumentWindowController()
		let info = controller.sessionInfo(includeUntitled: true)
		// Default controller has one untitled document
		#expect(info.documents.count == 1)
	}

	@Test("sessionInfo excludes untitled when requested")
	func sessionInfoExcludeUntitled() {
		let controller = DocumentWindowController()
		let info = controller.sessionInfo(includeUntitled: false)
		#expect(info.documents.isEmpty)
	}

	@Test("sessionInfo captures selected tab index")
	func sessionInfoSelectedTab() {
		let controller = DocumentWindowController()
		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.selectedTabIndex == 0)
	}

	@Test("sessionInfo captures file browser visibility")
	func sessionInfoFileBrowser() {
		let controller = DocumentWindowController()
		controller.isFileBrowserVisible = false
		let info = controller.sessionInfo(includeUntitled: true)
		#expect(info.fileBrowserVisible == false)
	}

	@Test("SessionWindowInfo is Codable round-trip")
	func sessionWindowInfoCodable() throws {
		var info = DocumentWindowController.SessionWindowInfo()
		info.projectPath = "/tmp/project"
		info.fileBrowserVisible = true
		info.fileBrowserWidth = 300
		info.selectedTabIndex = 2

		var docInfo = DocumentWindowController.SessionDocumentInfo()
		docInfo.identifier = "test-uuid"
		docInfo.path = "/tmp/file.swift"
		docInfo.displayName = "file.swift"
		docInfo.isSelected = true
		info.documents = [docInfo]

		let data = try JSONEncoder().encode(info)
		let decoded = try JSONDecoder().decode(
			DocumentWindowController.SessionWindowInfo.self,
			from: data,
		)

		#expect(decoded.projectPath == "/tmp/project")
		#expect(decoded.fileBrowserVisible == true)
		#expect(decoded.fileBrowserWidth == 300)
		#expect(decoded.selectedTabIndex == 2)
		#expect(decoded.documents.count == 1)
		#expect(decoded.documents[0].path == "/tmp/file.swift")
	}

	@Test("SessionInfo Codable round-trip")
	func sessionInfoCodable() throws {
		var window = DocumentWindowController.SessionWindowInfo()
		window.projectPath = "/tmp/proj"

		var session = DocumentWindowController.SessionInfo()
		session.projects = [window]

		let data = try JSONEncoder().encode(session)
		let decoded = try JSONDecoder().decode(
			DocumentWindowController.SessionInfo.self,
			from: data,
		)
		#expect(decoded.projects.count == 1)
		#expect(decoded.projects[0].projectPath == "/tmp/proj")
	}

	@Test("sessionPath creates directory if needed")
	func sessionPathCreatesDirectory() {
		let path = DocumentWindowController.sessionPath
		#expect(!path.isEmpty)
		let dir = (path as NSString).deletingLastPathComponent
		#expect(FileManager.default.fileExists(atPath: dir))
	}
}

#endif
