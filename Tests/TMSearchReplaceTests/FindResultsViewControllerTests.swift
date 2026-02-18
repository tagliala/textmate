import Testing
@testable import TMSearchReplace

#if canImport(AppKit)
import AppKit

// MARK: - Find Results View Controller Tests

@Suite("FindResultsViewController — Results Outline View")
struct FindResultsViewControllerTests {
	// MARK: - Helpers

	@MainActor
	private func makeResultTree(fileCount: Int = 2, matchesPerFile: Int = 3) -> SearchResultNode {
		let root = SearchResultNode(type: .root)
		for f in 0 ..< fileCount {
			let group = root.fileGroup(forPath: "/path/file\(f).swift", displayName: "file\(f).swift")
			for m in 0 ..< matchesPerFile {
				let match = DocumentMatch(
					documentID: UUID(),
					documentPath: "/path/file\(f).swift",
					displayName: "file\(f).swift",
					byteRange: (m * 10) ..< (m * 10 + 5),
					lineNumber: m,
					excerpt: "line \(m) content here",
					excerptOffset: m * 10,
				)
				group.addMatch(match)
			}
		}
		return root
	}

	// MARK: - Tests

	@Test("Initial state has nil results")
	@MainActor
	func initialState() {
		let vc = FindResultsViewController()
		#expect(vc.results == nil)
		#expect(vc.replaceString == "")
		#expect(vc.showReplacementPreviews == false)
		#expect(vc.hideCheckBoxes == false)
	}

	@Test("Setting results updates property")
	@MainActor
	func setResults() {
		let vc = FindResultsViewController()
		let root = makeResultTree()
		vc.results = root

		#expect(vc.results === root)
	}

	@Test("isCollapsed returns false when no results")
	@MainActor
	func isCollapsedNoResults() {
		let vc = FindResultsViewController()
		#expect(vc.isCollapsed == false)
	}

	@Test("Replace string property works")
	@MainActor
	func replaceStringProperty() {
		let vc = FindResultsViewController()
		vc.replaceString = "replacement"
		#expect(vc.replaceString == "replacement")
	}

	@Test("Show replacement previews property works")
	@MainActor
	func showReplacementPreviewsProperty() {
		let vc = FindResultsViewController()
		vc.showReplacementPreviews = true
		#expect(vc.showReplacementPreviews == true)
	}

	@Test("Hide checkboxes property works")
	@MainActor
	func hideCheckBoxesProperty() {
		let vc = FindResultsViewController()
		vc.hideCheckBoxes = true
		#expect(vc.hideCheckBoxes == true)
	}

	@Test("Attributed excerpt builds correct string structure")
	@MainActor
	func attributedExcerpt() {
		let match = DocumentMatch(
			documentID: UUID(),
			documentPath: "/test.swift",
			displayName: "test.swift",
			byteRange: 5 ..< 10,
			lineNumber: 3,
			excerpt: "hello world here",
			excerptOffset: 0,
		)
		let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
		let attributed = FindResultsViewController.attributedExcerpt(for: match, font: font)

		// Should contain line number prefix
		#expect(attributed.string.hasPrefix("4:\t"))
		// Should contain excerpt text
		#expect(attributed.string.contains("hello"))
	}

	@Test("Attributed excerpt with zero-range match")
	@MainActor
	func attributedExcerptZeroRange() {
		let match = DocumentMatch(
			documentID: UUID(),
			displayName: "test.swift",
			byteRange: 0 ..< 0,
			lineNumber: 0,
			excerpt: "some text",
			excerptOffset: 0,
		)
		let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
		let attributed = FindResultsViewController.attributedExcerpt(for: match, font: font)

		#expect(attributed.string.hasPrefix("1:\t"))
		#expect(attributed.string.contains("some text"))
	}

	@Test("Callback properties can be set")
	@MainActor
	func callbackProperties() {
		let vc = FindResultsViewController()
		var selectCalled = false
		var doubleClickCalled = false
		var removeCalled = false

		vc.onSelectResult = { _ in selectCalled = true }
		vc.onDoubleClickResult = { _ in doubleClickCalled = true }
		vc.onRemoveResult = { _ in removeCalled = true }

		// Invoke callbacks directly to verify they're set
		let node = SearchResultNode(type: .root)
		vc.onSelectResult?(node)
		vc.onDoubleClickResult?(node)
		vc.onRemoveResult?(node)

		#expect(selectCalled)
		#expect(doubleClickCalled)
		#expect(removeCalled)
	}
}
#endif
