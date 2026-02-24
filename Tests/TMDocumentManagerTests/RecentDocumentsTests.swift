import Foundation
import Testing
@testable import TMDocumentManager

@Suite("RecentDocumentsManager - LRU Recent Files")
@MainActor
struct RecentDocumentsTests {
	private func freshManager() -> RecentDocumentsManager {
		let manager = RecentDocumentsManager.shared
		manager.clearAll()
		return manager
	}

	// MARK: - Tracking

	@Test("Note document opened adds to recent list")
	func noteOpened() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/recent1.txt")

		#expect(manager.entries.count == 1)
		#expect(manager.entries[0].path.hasSuffix("recent1.txt"))
	}

	@Test("Most recently opened is first")
	func lruOrder() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/recent_a.txt")
		manager.noteDocumentOpened(path: "/tmp/recent_b.txt")
		manager.noteDocumentOpened(path: "/tmp/recent_c.txt")

		#expect(manager.entries[0].path.hasSuffix("recent_c.txt"))
		#expect(manager.entries[1].path.hasSuffix("recent_b.txt"))
		#expect(manager.entries[2].path.hasSuffix("recent_a.txt"))
	}

	@Test("Opening same file moves it to top")
	func reopenMovesToTop() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/reopen_a.txt")
		manager.noteDocumentOpened(path: "/tmp/reopen_b.txt")
		manager.noteDocumentOpened(path: "/tmp/reopen_a.txt") // Re-open

		#expect(manager.entries.count == 2)
		#expect(manager.entries[0].path.hasSuffix("reopen_a.txt"))
	}

	@Test("Max entries is respected")
	func maxEntries() {
		let manager = freshManager()
		manager.maxEntries = 3

		for i in 0 ..< 5 {
			manager.noteDocumentOpened(path: "/tmp/max_\(i).txt")
		}

		#expect(manager.entries.count == 3)
	}

	// MARK: - Querying

	@Test("Most recent returns first entry")
	func mostRecent() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/mr_first.txt")
		manager.noteDocumentOpened(path: "/tmp/mr_second.txt")

		#expect(manager.mostRecent?.path.hasSuffix("mr_second.txt") == true)
	}

	@Test("Most recent returns nil when empty")
	func mostRecentEmpty() {
		let manager = freshManager()
		#expect(manager.mostRecent == nil)
	}

	@Test("Recent paths returns ordered string list")
	func recentPaths() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/rp_1.txt")
		manager.noteDocumentOpened(path: "/tmp/rp_2.txt")

		let paths = manager.recentPaths
		#expect(paths.count == 2)
		#expect(paths[0].hasSuffix("rp_2.txt"))
	}

	@Test("Contains checks for known path")
	func contains() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/contains_test.txt")

		#expect(manager.contains(path: "/tmp/contains_test.txt"))
		#expect(!manager.contains(path: "/tmp/unknown.txt"))
	}

	// MARK: - Removal

	@Test("Remove entry by path")
	func removeEntry() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/remove_me.txt")
		manager.noteDocumentOpened(path: "/tmp/keep_me.txt")

		manager.removeEntry(forPath: "/tmp/remove_me.txt")
		#expect(manager.entries.count == 1)
		#expect(manager.entries[0].path.hasSuffix("keep_me.txt"))
	}

	@Test("Clear all removes everything")
	func clearAll() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/clear_1.txt")
		manager.noteDocumentOpened(path: "/tmp/clear_2.txt")

		manager.clearAll()
		#expect(manager.entries.isEmpty)
	}

	// MARK: - File Type

	@Test("File type is stored in entry")
	func fileType() {
		let manager = freshManager()
		manager.noteDocumentOpened(path: "/tmp/typed.swift", fileType: "source.swift")

		#expect(manager.entries[0].fileType == "source.swift")
	}

	// MARK: - Callback

	@Test("onChange callback fires on changes")
	func onChange() {
		let manager = freshManager()
		var callCount = 0
		manager.onChanged = { callCount += 1 }

		manager.noteDocumentOpened(path: "/tmp/callback.txt")
		#expect(callCount == 1)

		manager.removeEntry(forPath: "/tmp/callback.txt")
		#expect(callCount == 2)

		manager.onChanged = nil
	}
}

// MARK: - RecentDocumentEntry Tests

@Suite("RecentDocumentEntry")
struct RecentDocumentEntryTests {
	@Test("Entry initialization with default display name")
	func defaultDisplayName() {
		let entry = RecentDocumentEntry(path: "/Users/test/hello.swift")
		#expect(entry.displayName == "hello.swift")
	}

	@Test("Entry initialization with custom display name")
	func customDisplayName() {
		let entry = RecentDocumentEntry(
			path: "/tmp/file.txt",
			displayName: "Custom Name",
		)
		#expect(entry.displayName == "Custom Name")
	}

	@Test("Entry codable round-trip")
	func codableRoundTrip() throws {
		let entry = RecentDocumentEntry(
			path: "/tmp/codable.txt",
			displayName: "codable.txt",
			fileType: "text.plain",
		)

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(entry)

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let decoded = try decoder.decode(RecentDocumentEntry.self, from: data)

		#expect(decoded.path == entry.path)
		#expect(decoded.displayName == entry.displayName)
		#expect(decoded.fileType == entry.fileType)
	}
}
