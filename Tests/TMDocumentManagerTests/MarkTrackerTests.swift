import Foundation
import Testing
@testable import TMDocumentManager

@Suite("MarkTracker - Global Bookmark System")
@MainActor
struct MarkTrackerTests {
	private func freshTracker() -> MarkTracker {
		let tracker = MarkTracker.shared
		tracker.removeAll()
		return tracker
	}

	// MARK: - Adding Marks

	@Test("Add bookmark to path")
	func addBookmark() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 10, forPath: "/tmp/marks.txt")

		let bookmarks = tracker.bookmarks(forPath: "/tmp/marks.txt")
		#expect(bookmarks == [10])
	}

	@Test("Add multiple bookmarks")
	func addMultipleBookmarks() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 5, forPath: "/tmp/marks.txt")
		tracker.addBookmark(atLine: 15, forPath: "/tmp/marks.txt")
		tracker.addBookmark(atLine: 10, forPath: "/tmp/marks.txt")

		let bookmarks = tracker.bookmarks(forPath: "/tmp/marks.txt")
		#expect(bookmarks == [5, 10, 15]) // Sorted
	}

	@Test("Add mark with custom type and label")
	func addMarkWithType() {
		let tracker = freshTracker()
		let mark = DocumentMark(
			type: .search,
			line: 20,
			column: 5,
			label: "found: hello",
		)
		tracker.addMark(mark, forPath: "/tmp/search.txt")

		let marks = tracker.marks(forPath: "/tmp/search.txt", type: .search)
		#expect(marks.count == 1)
		#expect(marks[0].line == 20)
		#expect(marks[0].column == 5)
		#expect(marks[0].label == "found: hello")
	}

	// MARK: - Querying

	@Test("Marks for unknown path returns empty")
	func marksForUnknownPath() {
		let tracker = freshTracker()
		#expect(tracker.marks(forPath: "/nonexistent").isEmpty)
	}

	@Test("Has marks check")
	func hasMarks() {
		let tracker = freshTracker()
		#expect(!tracker.hasMarks(forPath: "/tmp/check.txt"))

		tracker.addBookmark(atLine: 1, forPath: "/tmp/check.txt")
		#expect(tracker.hasMarks(forPath: "/tmp/check.txt"))
		#expect(tracker.hasMarks(forPath: "/tmp/check.txt", type: .bookmark))
		#expect(!tracker.hasMarks(forPath: "/tmp/check.txt", type: .search))
	}

	@Test("All paths with marks")
	func allPaths() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 1, forPath: "/tmp/a.txt")
		tracker.addBookmark(atLine: 2, forPath: "/tmp/b.txt")

		let paths = tracker.allPaths
		#expect(paths.count == 2)
	}

	@Test("Total mark count")
	func totalCount() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 1, forPath: "/tmp/count1.txt")
		tracker.addBookmark(atLine: 2, forPath: "/tmp/count1.txt")
		tracker.addBookmark(atLine: 3, forPath: "/tmp/count2.txt")

		#expect(tracker.totalMarkCount == 3)
	}

	// MARK: - Removing Marks

	@Test("Remove specific mark by ID")
	func removeById() {
		let tracker = freshTracker()
		let id = tracker.addBookmark(atLine: 10, forPath: "/tmp/rm.txt")
		#expect(tracker.marks(forPath: "/tmp/rm.txt").count == 1)

		tracker.removeMark(id: id, forPath: "/tmp/rm.txt")
		#expect(tracker.marks(forPath: "/tmp/rm.txt").isEmpty)
	}

	@Test("Remove marks by type")
	func removeByType() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 1, forPath: "/tmp/type.txt")
		tracker.addMark(DocumentMark(type: .search, line: 2), forPath: "/tmp/type.txt")

		tracker.removeMarks(forPath: "/tmp/type.txt", type: .bookmark)

		let remaining = tracker.marks(forPath: "/tmp/type.txt")
		#expect(remaining.count == 1)
		#expect(remaining[0].type == .search)
	}

	@Test("Remove all marks for path")
	func removeAllForPath() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 1, forPath: "/tmp/all.txt")
		tracker.addBookmark(atLine: 2, forPath: "/tmp/all.txt")

		tracker.removeAllMarks(forPath: "/tmp/all.txt")
		#expect(tracker.marks(forPath: "/tmp/all.txt").isEmpty)
	}

	// MARK: - Toggle Bookmark

	@Test("Toggle bookmark adds when missing")
	func toggleAdd() {
		let tracker = freshTracker()
		let added = tracker.toggleBookmark(atLine: 5, forPath: "/tmp/toggle.txt")
		#expect(added)
		#expect(tracker.bookmarks(forPath: "/tmp/toggle.txt") == [5])
	}

	@Test("Toggle bookmark removes when present")
	func toggleRemove() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 5, forPath: "/tmp/toggle.txt")
		let added = tracker.toggleBookmark(atLine: 5, forPath: "/tmp/toggle.txt")
		#expect(!added)
		#expect(tracker.bookmarks(forPath: "/tmp/toggle.txt").isEmpty)
	}

	// MARK: - Set Marks

	@Test("Set marks replaces existing")
	func setMarks() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 1, forPath: "/tmp/set.txt")
		tracker.addBookmark(atLine: 2, forPath: "/tmp/set.txt")

		let newMarks = [
			DocumentMark(type: .diagnostic, line: 10, label: "error"),
			DocumentMark(type: .diagnostic, line: 20, label: "warning"),
		]
		tracker.setMarks(newMarks, forPath: "/tmp/set.txt")

		let marks = tracker.marks(forPath: "/tmp/set.txt")
		#expect(marks.count == 2)
		#expect(marks[0].type == .diagnostic)
	}

	// MARK: - Line Adjustments

	@Test("Adjust lines on insert")
	func adjustInsert() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 5, forPath: "/tmp/adj.txt")
		tracker.addBookmark(atLine: 10, forPath: "/tmp/adj.txt")
		tracker.addBookmark(atLine: 15, forPath: "/tmp/adj.txt")

		// Insert 3 lines at line 7
		tracker.adjustLines(forPath: "/tmp/adj.txt", atLine: 7, delta: 3)

		let bookmarks = tracker.bookmarks(forPath: "/tmp/adj.txt")
		#expect(bookmarks == [5, 13, 18]) // 5 unchanged; 10→13; 15→18
	}

	@Test("Adjust lines on delete")
	func adjustDelete() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 5, forPath: "/tmp/adj_del.txt")
		tracker.addBookmark(atLine: 10, forPath: "/tmp/adj_del.txt")
		tracker.addBookmark(atLine: 15, forPath: "/tmp/adj_del.txt")

		// Delete 3 lines at line 7
		tracker.adjustLines(forPath: "/tmp/adj_del.txt", atLine: 7, delta: -3)

		let bookmarks = tracker.bookmarks(forPath: "/tmp/adj_del.txt")
		#expect(bookmarks == [5, 7, 12]) // 5 unchanged; 10→7; 15→12
	}

	// MARK: - Path Rename

	@Test("Rename path transfers marks")
	func renamePath() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 5, forPath: "/tmp/old.txt")

		tracker.renamePath(from: "/tmp/old.txt", to: "/tmp/new.txt")

		#expect(tracker.marks(forPath: "/tmp/old.txt").isEmpty)
		#expect(tracker.bookmarks(forPath: "/tmp/new.txt") == [5])
	}

	// MARK: - Document Transfer

	@Test("Load marks into document")
	func loadIntoDocument() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 3, forPath: "/tmp/load.txt")
		tracker.addBookmark(atLine: 7, forPath: "/tmp/load.txt")

		let doc = TMDocument(path: "/tmp/load.txt")
		tracker.loadIntoDocument(doc)

		#expect(doc.bookmarks == [3, 7])
	}

	@Test("Save marks from document")
	func saveFromDocument() {
		let tracker = freshTracker()
		let doc = TMDocument(path: "/tmp/save.txt")
		doc.bookmarks = [1, 5, 10]

		tracker.saveFromDocument(doc)

		#expect(tracker.bookmarks(forPath: "/tmp/save.txt") == [1, 5, 10])
	}

	// MARK: - Change Observation

	@Test("Change callbacks fire on mark changes")
	func changeCallbacks() {
		let tracker = freshTracker()
		var changedPaths: [String] = []
		let cbID = tracker.addChangeCallback { path in changedPaths.append(path) }

		tracker.addBookmark(atLine: 1, forPath: "/tmp/cb.txt")
		#expect(changedPaths.count == 1)

		tracker.removeChangeCallback(id: cbID)
		tracker.addBookmark(atLine: 2, forPath: "/tmp/cb.txt")
		#expect(changedPaths.count == 1) // Not incremented
	}

	// MARK: - Serialization

	@Test("Export and import marks")
	func exportImport() {
		let tracker = freshTracker()
		tracker.addBookmark(atLine: 1, forPath: "/tmp/export.txt")
		tracker.addBookmark(atLine: 2, forPath: "/tmp/export.txt")

		let exported = tracker.exportMarks()
		#expect(exported.count >= 1) // At least one path

		tracker.removeAll()
		#expect(tracker.totalMarkCount == 0)

		tracker.importMarks(exported)
		// Marks should be restored — note path canonicalization may change keys
		#expect(tracker.totalMarkCount >= 2)
	}

	// MARK: - MarkType

	@Test("MarkType cases exist")
	func markTypeCases() {
		let cases = MarkType.allCases
		#expect(cases.contains(.bookmark))
		#expect(cases.contains(.search))
		#expect(cases.contains(.diagnostic))
		#expect(cases.contains(.scmChange))
	}
}

// MARK: - DocumentMark Tests

@Suite("DocumentMark")
struct DocumentMarkTests {
	@Test("DocumentMark initialization")
	func initialization() {
		let mark = DocumentMark(type: .bookmark, line: 42)
		#expect(mark.type == .bookmark)
		#expect(mark.line == 42)
		#expect(mark.column == nil)
		#expect(mark.label == nil)
	}

	@Test("DocumentMark with all fields")
	func allFields() {
		let mark = DocumentMark(
			type: .diagnostic,
			line: 10,
			column: 5,
			label: "unused variable",
		)
		#expect(mark.type == .diagnostic)
		#expect(mark.line == 10)
		#expect(mark.column == 5)
		#expect(mark.label == "unused variable")
	}

	@Test("DocumentMark equality by ID")
	func equality() {
		let id = UUID()
		let mark1 = DocumentMark(id: id, type: .bookmark, line: 1)
		let mark2 = DocumentMark(id: id, type: .bookmark, line: 1)
		#expect(mark1 == mark2)
	}

	@Test("DocumentMark codable round-trip")
	func codable() throws {
		let mark = DocumentMark(
			type: .search,
			line: 15,
			column: 3,
			label: "match",
		)
		let data = try JSONEncoder().encode(mark)
		let decoded = try JSONDecoder().decode(DocumentMark.self, from: data)
		#expect(decoded.type == .search)
		#expect(decoded.line == 15)
		#expect(decoded.column == 3)
		#expect(decoded.label == "match")
	}
}
