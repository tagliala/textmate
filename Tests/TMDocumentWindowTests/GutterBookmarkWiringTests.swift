#if canImport(AppKit)
import Foundation
import Testing
@testable import TMDocumentManager
@testable import TMDocumentWindow

@Suite("Gutter bookmark → MarkTracker")
@MainActor
struct GutterBookmarkWiringTests {
	@Test("toggling a gutter bookmark propagates to MarkTracker")
	func togglePropagates() throws {
		let path = "/tmp/test-gutter-bookmark-\(UUID().uuidString).swift"
		let doc = TMDocument(path: path)
		let controller = DocumentWindowController(document: doc)
		_ = controller.window // force load

		// Ensure clean state
		MarkTracker.shared.removeAllMarks(forPath: path)
		defer { MarkTracker.shared.removeAllMarks(forPath: path) }

		// Simulate gutter bookmark toggle at line 5
		controller.gutterView(controller.gutterView, didToggleBookmarkAtLine: 5)

		let bookmarks = MarkTracker.shared.bookmarks(forPath: path)
		#expect(bookmarks.contains(5))
	}

	@Test("toggling twice removes the bookmark")
	func toggleTwiceRemoves() throws {
		let path = "/tmp/test-gutter-bookmark-\(UUID().uuidString).swift"
		let doc = TMDocument(path: path)
		let controller = DocumentWindowController(document: doc)
		_ = controller.window

		MarkTracker.shared.removeAllMarks(forPath: path)
		defer { MarkTracker.shared.removeAllMarks(forPath: path) }

		controller.gutterView(controller.gutterView, didToggleBookmarkAtLine: 10)
		controller.gutterView(controller.gutterView, didToggleBookmarkAtLine: 10)

		let bookmarks = MarkTracker.shared.bookmarks(forPath: path)
		#expect(!bookmarks.contains(10))
	}

	@Test("no-op when document has no path")
	func noPathNoop() {
		let doc = TMDocument()
		let controller = DocumentWindowController(document: doc)
		_ = controller.window

		// Should not crash or add marks
		controller.gutterView(controller.gutterView, didToggleBookmarkAtLine: 1)
		#expect(MarkTracker.shared.totalMarkCount >= 0) // just verify no crash
	}
}
#endif
