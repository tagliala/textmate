import Foundation
import Testing
@testable import TMDocumentManager

// MARK: - Session Document Info Tests

@Suite("SessionDocumentInfo")
struct SessionDocumentInfoTests {
	@Test("Session document info initialization")
	func initialization() {
		let info = SessionDocumentInfo(
			path: "/tmp/session.txt",
			fileType: "source.swift",
			selection: "1:0",
			visibleIndex: 10,
			tabSize: 2,
			softTabs: true,
		)
		#expect(info.path == "/tmp/session.txt")
		#expect(info.fileType == "source.swift")
		#expect(info.selection == "1:0")
		#expect(info.visibleIndex == 10)
		#expect(info.tabSize == 2)
		#expect(info.softTabs)
	}

	@Test("Session document info codable round-trip")
	func codableRoundTrip() throws {
		let info = SessionDocumentInfo(
			path: "/tmp/codable.txt",
			displayName: "codable.txt",
			fileType: "text.plain",
			selection: "1:0-5:3",
			visibleIndex: 42,
			isModified: false,
			tabSize: 4,
			softTabs: false,
			foldedRanges: ["10:0-20:0"],
			bookmarks: [5, 15, 25],
		)

		let encoder = JSONEncoder()
		let data = try encoder.encode(info)
		let decoder = JSONDecoder()
		let decoded = try decoder.decode(SessionDocumentInfo.self, from: data)
		#expect(decoded == info)
	}

	@Test("Session document info from TMDocument snapshot")
	@MainActor
	func fromDocument() {
		let doc = TMDocument(path: "/tmp/snapshot.swift", fileType: "source.swift")
		doc.selection = "3:5-3:10"
		doc.visibleIndex = 15
		doc.tabSize = 3
		doc.softTabs = true
		doc.bookmarks = [1, 5, 10]
		doc.foldedRanges = ["2:0-4:0"]

		let info = SessionDocumentInfo.from(document: doc)
		#expect(info.id == doc.id)
		#expect(info.path == "/tmp/snapshot.swift")
		#expect(info.fileType == "source.swift")
		#expect(info.selection == "3:5-3:10")
		#expect(info.visibleIndex == 15)
		#expect(info.tabSize == 3)
		#expect(info.softTabs)
		#expect(info.bookmarks == [1, 5, 10])
		#expect(info.foldedRanges == ["2:0-4:0"])
	}

	@Test("Untitled modified document saves content in snapshot")
	@MainActor
	func untitledModifiedSnapshot() {
		TMDocumentController.shared.removeAll()
		let doc = TMDocument(fileType: "source.ruby")
		doc.setContent("puts 'hello'")

		let info = SessionDocumentInfo.from(document: doc)
		#expect(info.path == nil)
		#expect(info.isModified)
		#expect(info.content == "puts 'hello'")
	}
}

// MARK: - Session Window Info Tests

@Suite("SessionWindowInfo")
struct SessionWindowInfoTests {
	@Test("Window info defaults")
	func defaults() {
		let info = SessionWindowInfo()
		#expect(info.documents.isEmpty)
		#expect(info.selectedDocumentIndex == 0)
		#expect(info.fileBrowserPath == nil)
		#expect(!info.fileBrowserVisible)
		#expect(!info.isMiniaturized)
	}

	@Test("Window info codable round-trip")
	func codableRoundTrip() throws {
		let docInfo = SessionDocumentInfo(
			path: "/tmp/window_test.txt",
			fileType: "text.plain",
		)
		let windowInfo = SessionWindowInfo(
			frame: WindowFrame(x: 100, y: 200, width: 900, height: 700),
			documents: [docInfo],
			selectedDocumentIndex: 0,
			fileBrowserPath: "/tmp",
			fileBrowserVisible: true,
			fileBrowserWidth: 250,
		)

		let data = try JSONEncoder().encode(windowInfo)
		let decoded = try JSONDecoder().decode(SessionWindowInfo.self, from: data)
		#expect(decoded == windowInfo)
	}
}

// MARK: - Window Frame Tests

@Suite("WindowFrame")
struct WindowFrameTests {
	@Test("Window frame defaults")
	func defaults() {
		let frame = WindowFrame()
		#expect(frame.x == 0)
		#expect(frame.y == 0)
		#expect(frame.width == 800)
		#expect(frame.height == 600)
	}

	@Test("Window frame custom values")
	func customValues() {
		let frame = WindowFrame(x: 50, y: 100, width: 1200, height: 800)
		#expect(frame.x == 50)
		#expect(frame.y == 100)
		#expect(frame.width == 1200)
		#expect(frame.height == 800)
	}
}

// MARK: - Document Session Tests

@Suite("DocumentSession")
struct DocumentSessionTests {
	@Test("Session codable round-trip")
	func codableRoundTrip() throws {
		let session = DocumentSession(
			windows: [
				SessionWindowInfo(
					documents: [
						SessionDocumentInfo(path: "/tmp/s1.txt"),
						SessionDocumentInfo(path: "/tmp/s2.txt"),
					],
					selectedDocumentIndex: 1,
					fileBrowserPath: "/tmp",
				),
			],
			globalMarks: ["/tmp/marks.txt": [1, 5, 10]],
			recentFiles: ["/tmp/recent.txt"],
		)

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(session)

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let decoded = try decoder.decode(DocumentSession.self, from: data)

		#expect(decoded.version == 1)
		#expect(decoded.windows.count == 1)
		#expect(decoded.windows[0].documents.count == 2)
		#expect(decoded.globalMarks.count == 1)
		#expect(decoded.recentFiles.count == 1)
	}
}

// MARK: - Session Manager Tests

@Suite("SessionManager - Persistence")
@MainActor
struct SessionManagerTests {
	private func tempSessionDir() -> URL {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("tm_session_test_\(UUID().uuidString)")
	}

	@Test("Save and restore session")
	func saveAndRestore() throws {
		let dir = tempSessionDir()
		defer { try? FileManager.default.removeItem(at: dir) }

		let manager = SessionManager(directory: dir)

		let session = DocumentSession(
			windows: [
				SessionWindowInfo(
					documents: [SessionDocumentInfo(path: "/tmp/session_sr.txt")],
					selectedDocumentIndex: 0,
				),
			],
			recentFiles: ["/tmp/session_sr.txt"],
		)

		try manager.save(session)
		#expect(manager.hasSavedSession)

		let restored = try manager.restore()
		#expect(restored.windows.count == 1)
		#expect(restored.windows[0].documents.count == 1)
		#expect(restored.windows[0].documents[0].path == "/tmp/session_sr.txt")
		#expect(restored.recentFiles == ["/tmp/session_sr.txt"])
	}

	@Test("Has saved session returns false when no file")
	func noSavedSession() {
		let dir = tempSessionDir()
		let manager = SessionManager(directory: dir)
		#expect(!manager.hasSavedSession)
	}

	@Test("Delete session removes file")
	func deleteSession() throws {
		let dir = tempSessionDir()
		defer { try? FileManager.default.removeItem(at: dir) }

		let manager = SessionManager(directory: dir)
		let session = DocumentSession()
		try manager.save(session)
		#expect(manager.hasSavedSession)

		try manager.deleteSavedSession()
		#expect(!manager.hasSavedSession)
	}

	@Test("Capture session creates snapshot")
	func captureSession() {
		let dir = tempSessionDir()
		let manager = SessionManager(directory: dir)

		let session = manager.captureSession(
			windows: [SessionWindowInfo()],
			recentFiles: ["/tmp/capture.txt"],
			globalMarks: ["/tmp/m.txt": [1, 2]],
		)

		#expect(session.windows.count == 1)
		#expect(session.recentFiles.count == 1)
		#expect(session.globalMarks.count == 1)
	}
}
