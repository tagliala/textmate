import Foundation
import Testing
@testable import TMDocumentManager

@Suite("FileWatcher - File System Monitoring")
struct FileWatcherTests {
	// MARK: - Initialization

	@Test("FileWatcher starts with no watches")
	func initialState() {
		let watcher = FileWatcher()
		#expect(watcher.watchCount == 0)
	}

	// MARK: - Watch / Unwatch

	@Test("Watch increments watch count")
	func watchIncrements() {
		let watcher = FileWatcher()
		let tmpFile = NSTemporaryDirectory() + "filewatcher_test_\(UUID().uuidString).txt"
		FileManager.default.createFile(atPath: tmpFile, contents: nil)
		defer { try? FileManager.default.removeItem(atPath: tmpFile) }

		let token = watcher.watch(tmpFile) { _, _ in }
		#expect(watcher.watchCount == 1)

		watcher.unwatch(token)
		#expect(watcher.watchCount == 0)
	}

	@Test("Multiple watches are tracked independently")
	func multipleWatches() {
		let watcher = FileWatcher()
		let file1 = NSTemporaryDirectory() + "filewatcher_multi_1_\(UUID().uuidString).txt"
		let file2 = NSTemporaryDirectory() + "filewatcher_multi_2_\(UUID().uuidString).txt"
		FileManager.default.createFile(atPath: file1, contents: nil)
		FileManager.default.createFile(atPath: file2, contents: nil)
		defer {
			try? FileManager.default.removeItem(atPath: file1)
			try? FileManager.default.removeItem(atPath: file2)
		}

		let token1 = watcher.watch(file1) { _, _ in }
		let token2 = watcher.watch(file2) { _, _ in }
		#expect(watcher.watchCount == 2)

		watcher.unwatch(token1)
		#expect(watcher.watchCount == 1)

		watcher.unwatch(token2)
		#expect(watcher.watchCount == 0)
	}

	@Test("Unwatch all removes all watches")
	func unwatchAll() {
		let watcher = FileWatcher()
		let file1 = NSTemporaryDirectory() + "filewatcher_all_1_\(UUID().uuidString).txt"
		let file2 = NSTemporaryDirectory() + "filewatcher_all_2_\(UUID().uuidString).txt"
		FileManager.default.createFile(atPath: file1, contents: nil)
		FileManager.default.createFile(atPath: file2, contents: nil)
		defer {
			try? FileManager.default.removeItem(atPath: file1)
			try? FileManager.default.removeItem(atPath: file2)
		}

		_ = watcher.watch(file1) { _, _ in }
		_ = watcher.watch(file2) { _, _ in }
		#expect(watcher.watchCount == 2)

		watcher.unwatchAll()
		#expect(watcher.watchCount == 0)
	}

	// MARK: - isWatching

	@Test("isWatching reports correctly")
	func isWatching() {
		let watcher = FileWatcher()
		let tmpFile = NSTemporaryDirectory() + "filewatcher_iswatching_\(UUID().uuidString).txt"
		FileManager.default.createFile(atPath: tmpFile, contents: nil)
		defer { try? FileManager.default.removeItem(atPath: tmpFile) }

		#expect(!watcher.isWatching(tmpFile))
		let token = watcher.watch(tmpFile) { _, _ in }
		#expect(watcher.isWatching(tmpFile))

		watcher.unwatch(token)
		#expect(!watcher.isWatching(tmpFile))
	}

	// MARK: - Non-existent file

	@Test("Watching a non-existent file doesn't crash")
	func watchNonexistent() {
		let watcher = FileWatcher()
		_ = watcher.watch("/nonexistent/file/path_\(UUID().uuidString).txt") { _, _ in }
		#expect(watcher.watchCount == 0) // Should not have added it
	}

	// MARK: - FileWatchEvent

	@Test("FileWatchEvent option set operations")
	func watchEventOptions() {
		let events: FileWatchEvent = [.written, .deleted]
		#expect(events.contains(.written))
		#expect(events.contains(.deleted))
		#expect(!events.contains(.renamed))
	}

	@Test("FileWatchEvent.all includes all events")
	func watchEventAll() {
		let all = FileWatchEvent.all
		#expect(all.contains(.written))
		#expect(all.contains(.renamed))
		#expect(all.contains(.deleted))
		#expect(all.contains(.attributesChanged))
		#expect(all.contains(.linkChanged))
		#expect(all.contains(.revoked))
	}
}

@Suite("DirectoryWatcher")
struct DirectoryWatcherTests {
	@Test("DirectoryWatcher starts and stops")
	func startStop() {
		let tmpDir = NSTemporaryDirectory() + "dirwatcher_\(UUID().uuidString)"
		try? FileManager.default.createDirectory(
			atPath: tmpDir,
			withIntermediateDirectories: true,
		)
		defer { try? FileManager.default.removeItem(atPath: tmpDir) }

		let watcher = DirectoryWatcher(path: tmpDir) { _ in }
		#expect(!watcher.isActive)

		watcher.start()
		#expect(watcher.isActive)

		watcher.stop()
		#expect(!watcher.isActive)
	}

	@Test("DirectoryWatcher double start is safe")
	func doubleStart() {
		let tmpDir = NSTemporaryDirectory() + "dirwatcher_double_\(UUID().uuidString)"
		try? FileManager.default.createDirectory(
			atPath: tmpDir,
			withIntermediateDirectories: true,
		)
		defer { try? FileManager.default.removeItem(atPath: tmpDir) }

		let watcher = DirectoryWatcher(path: tmpDir) { _ in }
		watcher.start()
		watcher.start() // Should not crash
		#expect(watcher.isActive)
		watcher.stop()
	}

	@Test("DirectoryWatcher double stop is safe")
	func doubleStop() {
		let tmpDir = NSTemporaryDirectory() + "dirwatcher_dblstop_\(UUID().uuidString)"
		try? FileManager.default.createDirectory(
			atPath: tmpDir,
			withIntermediateDirectories: true,
		)
		defer { try? FileManager.default.removeItem(atPath: tmpDir) }

		let watcher = DirectoryWatcher(path: tmpDir) { _ in }
		watcher.start()
		watcher.stop()
		watcher.stop() // Should not crash
		#expect(!watcher.isActive)
	}
}
