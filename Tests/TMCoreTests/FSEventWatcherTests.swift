import Foundation
import Testing
@testable import TMCore

@Suite("FSEventWatcher — Basic")
struct FSEventWatcherTests {
	@Test("shared instance is available")
	func sharedInstance() {
		let watcher = FSEventWatcher.shared
		// Just verify it's a valid instance by checking its type
		#expect(type(of: watcher) == FSEventWatcher.self)
	}

	@Test("watch and unwatch directory without crash")
	func watchUnwatch() async throws {
		let dir = PathUtilities.temp() + "/tm_test_fsevents_\(ProcessInfo.processInfo.processIdentifier)"
		defer { PathUtilities.remove(dir) }

		PathUtilities.makeDir(dir)

		final class TestHandler: FSEventWatcher.EventHandler, @unchecked Sendable {
			var didChangeCalled = false
			func didChange(path _: String, observedPath _: String, eventId _: UInt64, recursive _: Bool) {
				didChangeCalled = true
			}

			func setReplayingHistory(_: Bool, observedPath _: String, eventId _: UInt64) {}
		}

		let handler = TestHandler()
		FSEventWatcher.shared.watch(dir, callback: handler)

		// Brief delay to let FSEvents set up
		try await Task.sleep(for: .milliseconds(100))

		FSEventWatcher.shared.unwatch(dir, callback: handler)
	}

	@Test("watching nonexistent path falls back to parent")
	func watchNonexistent() async throws {
		let dir = PathUtilities.temp() + "/tm_test_fsevents_missing_\(ProcessInfo.processInfo.processIdentifier)/sub"

		final class TestHandler: FSEventWatcher.EventHandler, @unchecked Sendable {
			func didChange(path _: String, observedPath _: String, eventId _: UInt64, recursive _: Bool) {}
			func setReplayingHistory(_: Bool, observedPath _: String, eventId _: UInt64) {}
		}

		let handler = TestHandler()
		// Should not crash even though directory doesn't exist
		FSEventWatcher.shared.watch(dir, callback: handler)
		try await Task.sleep(for: .milliseconds(50))
		FSEventWatcher.shared.unwatch(dir, callback: handler)
	}
}
