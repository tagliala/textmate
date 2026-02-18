import AppKit
import Testing
@testable import TMDocumentWindow
@testable import TMFileBrowser
@testable import TMSCM

// MARK: - ProjectLayoutView Tests

@Suite("ProjectLayoutView")
@MainActor
struct ProjectLayoutViewTests {
	@Test("documentView is required and fills available space")
	func documentViewFillsSpace() {
		let layout = ProjectLayoutView()
		let doc = NSView()
		layout.documentView = doc
		layout.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		layout.layoutSubtreeIfNeeded()

		#expect(doc.superview === layout)
	}

	@Test("fileBrowserView can be set and removed")
	func fileBrowserViewToggle() {
		let layout = ProjectLayoutView()
		let doc = NSView()
		let sidebar = NSView()
		layout.documentView = doc

		// Add
		layout.fileBrowserView = sidebar
		#expect(sidebar.superview === layout)

		// Remove
		layout.fileBrowserView = nil
		#expect(sidebar.superview == nil)
	}

	@Test("fileBrowserWidth persists through UserDefaults")
	func fileBrowserWidthPersistence() {
		let layout = ProjectLayoutView()
		layout.fileBrowserWidth = 325

		#expect(layout.fileBrowserWidth == 325)
		let stored = UserDefaults.standard.double(forKey: "fileBrowserWidth")
		#expect(stored == 325)

		// Restore
		UserDefaults.standard.set(400.0, forKey: "fileBrowserWidth")
		let layout2 = ProjectLayoutView()
		#expect(layout2.fileBrowserWidth == 400)
	}

	@Test("htmlOutputView can be added and closed")
	func htmlOutputViewLifecycle() {
		let layout = ProjectLayoutView()
		let doc = NSView()
		let html = NSView()
		layout.documentView = doc

		layout.htmlOutputView = html
		#expect(html.superview === layout)

		layout.performCloseSplit()
		#expect(layout.htmlOutputView == nil)
	}

	@Test("fileBrowserOnRight flips browser placement")
	func fileBrowserPlacement() {
		let layout = ProjectLayoutView()
		let doc = NSView()
		let sidebar = NSView()
		layout.documentView = doc
		layout.fileBrowserView = sidebar

		layout.fileBrowserOnRight = true
		#expect(layout.fileBrowserOnRight == true)

		layout.fileBrowserOnRight = false
		#expect(layout.fileBrowserOnRight == false)
	}
}

// MARK: - FileBrowser Integration Tests

@Suite("FileBrowser Integration")
@MainActor
struct FileBrowserIntegrationTests {
	@Test("DocumentWindowController has a file browser controller")
	func controllerHasFileBrowser() {
		let controller = DocumentWindowController()
		#expect(controller.fileBrowserController.delegate != nil)
	}

	@Test("toggleFileBrowser hides and shows file browser")
	func toggleFileBrowser() {
		let controller = DocumentWindowController()

		#expect(controller.isFileBrowserVisible == true)
		#expect(controller.projectLayoutView.fileBrowserView != nil)

		controller.toggleFileBrowser(nil)
		#expect(controller.isFileBrowserVisible == false)
		#expect(controller.projectLayoutView.fileBrowserView == nil)

		controller.toggleFileBrowser(nil)
		#expect(controller.isFileBrowserVisible == true)
		#expect(controller.projectLayoutView.fileBrowserView != nil)
	}

	@Test("fileBrowserWidth delegates to projectLayoutView")
	func fileBrowserWidthDelegation() {
		let controller = DocumentWindowController()
		controller.fileBrowserWidth = 350
		#expect(controller.projectLayoutView.fileBrowserWidth == 350)
	}

	@Test("setProjectRoot updates file browser and window title")
	func setProjectRoot() throws {
		let controller = DocumentWindowController()
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("TextMateTest-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		controller.setProjectRoot(tmpDir)
		#expect(controller.window?.title == tmpDir.lastPathComponent)
	}
}

// MARK: - Session State with FileBrowser

@Suite("Session FileBrowser State")
@MainActor
struct SessionFileBrowserTests {
	@Test("SessionWindowInfo includes fileBrowserState field")
	func sessionWindowInfoHasFileBrowserState() throws {
		var info = DocumentWindowController.SessionWindowInfo()
		info.fileBrowserVisible = true
		info.fileBrowserWidth = 280
		info.fileBrowserState = try PropertyListSerialization.data(
			fromPropertyList: ["rootURL": "/tmp/test"],
			format: .binary,
			options: 0,
		)

		let data = try JSONEncoder().encode(info)
		let decoded = try JSONDecoder().decode(
			DocumentWindowController.SessionWindowInfo.self,
			from: data,
		)

		#expect(decoded.fileBrowserVisible == true)
		#expect(decoded.fileBrowserWidth == 280)
		#expect(decoded.fileBrowserState != nil)

		let plist = try PropertyListSerialization.propertyList(
			from: #require(decoded.fileBrowserState), format: nil,
		) as? [String: Any]
		#expect(plist?["rootURL"] as? String == "/tmp/test")
	}

	@Test("sessionInfo captures file browser state")
	func sessionInfoCapturesFileBrowserState() {
		let controller = DocumentWindowController()
		let info = controller.sessionInfo(includeUntitled: true)

		#expect(info.fileBrowserVisible == true)
		#expect(info.fileBrowserWidth > 0)
		// fileBrowserState should be non-nil (even if empty dict)
		// The actual content depends on FileBrowserViewController defaults.
	}
}

// MARK: - SCM Badge Provider Tests

@Suite("SCM Badge Provider")
@MainActor
struct SCMBadgeProviderTests {
	@Test("FileStatusBadge provides color for modified status")
	func modifiedBadge() {
		let badge = FileStatusBadge(status: .modified)
		#expect(badge.color != nil)
		#expect(!badge.symbolName.isEmpty)
	}

	@Test("FileStatusBadge provides color for added status")
	func addedBadge() {
		let badge = FileStatusBadge(status: .added)
		#expect(badge.color != nil)
	}

	@Test("FileStatusBadge provides color for deleted status")
	func deletedBadge() {
		let badge = FileStatusBadge(status: .deleted)
		#expect(badge.color != nil)
	}

	@Test("FileStatusBadge for none is not visible")
	func noneBadge() {
		let badge = FileStatusBadge(status: .none)
		#expect(!badge.isVisible)
		#expect(badge.color == nil)
	}
}
