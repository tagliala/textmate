import Foundation

// MARK: - File Watch Event

/// Events that can be reported by the file watcher.
public struct FileWatchEvent: OptionSet, Sendable {
	public let rawValue: UInt

	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	/// The file content was modified.
	public static let written = FileWatchEvent(rawValue: 1 << 0)

	/// The file was renamed.
	public static let renamed = FileWatchEvent(rawValue: 1 << 1)

	/// The file was deleted.
	public static let deleted = FileWatchEvent(rawValue: 1 << 2)

	/// The file's attributes changed (permissions, xattrs, etc.).
	public static let attributesChanged = FileWatchEvent(rawValue: 1 << 3)

	/// The file's link count changed.
	public static let linkChanged = FileWatchEvent(rawValue: 1 << 4)

	/// File was revoked (e.g., unmounted).
	public static let revoked = FileWatchEvent(rawValue: 1 << 5)

	/// All events.
	public static let all: FileWatchEvent = [
		.written, .renamed, .deleted, .attributesChanged, .linkChanged, .revoked,
	]
}

// MARK: - File Watch Callback

/// Callback type for file watch events.
public typealias FileWatchCallback = @Sendable (String, FileWatchEvent) -> Void

// MARK: - File Watcher

/// Monitors individual files for changes using kqueue via `DispatchSource`.
///
/// Equivalent to the C++ `KEventManager` — tracks files by file descriptor
/// and reports events (write, rename, delete) to registered callbacks.
///
/// Usage:
/// ```swift
/// let watcher = FileWatcher()
/// let token = watcher.watch("/path/to/file") { path, events in
///     if events.contains(.written) { /* reload */ }
/// }
/// // Later:
/// watcher.unwatch(token)
/// ```
public final class FileWatcher: @unchecked Sendable {
	/// A token identifying a watch registration.
	public struct WatchToken: Hashable, Sendable {
		let id: UUID
	}

	// MARK: - Watch Entry

	private struct WatchEntry {
		let path: String
		let fileDescriptor: Int32
		let source: DispatchSourceFileSystemObject
		let callback: FileWatchCallback
	}

	// MARK: - State

	private let queue = DispatchQueue(label: "com.macromates.FileWatcher", qos: .utility)
	private var watches: [UUID: WatchEntry] = [:]

	public init() {}

	deinit {
		// Cancel all sources
		for entry in watches.values {
			entry.source.cancel()
			close(entry.fileDescriptor)
		}
		watches.removeAll()
	}

	// MARK: - Watch

	/// Starts watching a file at the given path.
	/// Returns a token that can be used to stop watching.
	@discardableResult
	public func watch(
		_ path: String,
		events: FileWatchEvent = .all,
		callback: @escaping FileWatchCallback,
	) -> WatchToken {
		let token = WatchToken(id: UUID())

		queue.sync {
			let fd = open(path, O_EVTONLY)
			guard fd >= 0 else { return }

			var vnodeEvents: DispatchSource.FileSystemEvent = []
			if events.contains(.written) { vnodeEvents.insert(.write) }
			if events.contains(.renamed) { vnodeEvents.insert(.rename) }
			if events.contains(.deleted) { vnodeEvents.insert(.delete) }
			if events.contains(.attributesChanged) { vnodeEvents.insert(.attrib) }
			if events.contains(.linkChanged) { vnodeEvents.insert(.link) }
			if events.contains(.revoked) { vnodeEvents.insert(.revoke) }

			let source = DispatchSource.makeFileSystemObjectSource(
				fileDescriptor: fd,
				eventMask: vnodeEvents,
				queue: self.queue,
			)

			source.setEventHandler { [weak self] in
				guard let self else { return }
				let triggered = source.data
				var watchEvents = FileWatchEvent()

				if triggered.contains(.write) { watchEvents.insert(.written) }
				if triggered.contains(.rename) { watchEvents.insert(.renamed) }
				if triggered.contains(.delete) { watchEvents.insert(.deleted) }
				if triggered.contains(.attrib) { watchEvents.insert(.attributesChanged) }
				if triggered.contains(.link) { watchEvents.insert(.linkChanged) }
				if triggered.contains(.revoke) { watchEvents.insert(.revoked) }

				callback(path, watchEvents)

				// If deleted or renamed, we may need to re-watch
				if triggered.contains(.delete) || triggered.contains(.rename) {
					rewatchIfNeeded(token: token)
				}
			}

			source.setCancelHandler {
				close(fd)
			}

			let entry = WatchEntry(
				path: path,
				fileDescriptor: fd,
				source: source,
				callback: callback,
			)
			self.watches[token.id] = entry
			source.resume()
		}

		return token
	}

	// MARK: - Unwatch

	/// Stops watching the file associated with the given token.
	public func unwatch(_ token: WatchToken) {
		queue.sync {
			guard let entry = watches.removeValue(forKey: token.id) else { return }
			entry.source.cancel()
		}
	}

	/// Stops all watches.
	public func unwatchAll() {
		queue.sync {
			for entry in watches.values {
				entry.source.cancel()
			}
			watches.removeAll()
		}
	}

	// MARK: - Status

	/// The number of active watches.
	public var watchCount: Int {
		queue.sync { watches.count }
	}

	/// Whether a specific path is currently being watched.
	public func isWatching(_ path: String) -> Bool {
		queue.sync {
			watches.values.contains { $0.path == path }
		}
	}

	// MARK: - Re-watch

	/// Attempts to re-establish a watch after a delete or rename event.
	private func rewatchIfNeeded(token: WatchToken) {
		guard let entry = watches[token.id] else { return }

		// Cancel the old source
		entry.source.cancel()

		// Try to re-open the file (it may have been recreated)
		let fd = open(entry.path, O_EVTONLY)
		guard fd >= 0 else {
			// File is truly gone — remove the watch
			watches.removeValue(forKey: token.id)
			return
		}

		let source = DispatchSource.makeFileSystemObjectSource(
			fileDescriptor: fd,
			eventMask: [.write, .rename, .delete, .attrib, .link, .revoke],
			queue: queue,
		)

		let callback = entry.callback

		source.setEventHandler { [weak self] in
			guard let self else { return }
			let triggered = source.data
			var watchEvents = FileWatchEvent()

			if triggered.contains(.write) { watchEvents.insert(.written) }
			if triggered.contains(.rename) { watchEvents.insert(.renamed) }
			if triggered.contains(.delete) { watchEvents.insert(.deleted) }
			if triggered.contains(.attrib) { watchEvents.insert(.attributesChanged) }
			if triggered.contains(.link) { watchEvents.insert(.linkChanged) }
			if triggered.contains(.revoke) { watchEvents.insert(.revoked) }

			callback(entry.path, watchEvents)

			if triggered.contains(.delete) || triggered.contains(.rename) {
				rewatchIfNeeded(token: token)
			}
		}

		source.setCancelHandler {
			close(fd)
		}

		watches[token.id] = WatchEntry(
			path: entry.path,
			fileDescriptor: fd,
			source: source,
			callback: callback,
		)
		source.resume()
	}
}

// MARK: - Directory Watcher

/// Monitors a directory for changes using FSEvents via `DispatchSource`.
///
/// Reports when files within the directory are added, modified, or removed.
public final class DirectoryWatcher: @unchecked Sendable {
	/// Callback type: receives the directory path that changed.
	public typealias Callback = @Sendable (String) -> Void

	private let path: String
	private let callback: Callback
	private var source: DispatchSourceFileSystemObject?
	private let queue: DispatchQueue

	public init(
		path: String,
		queue: DispatchQueue = DispatchQueue(
			label: "com.macromates.DirectoryWatcher",
			qos: .utility,
		),
		callback: @escaping Callback,
	) {
		self.path = path
		self.callback = callback
		self.queue = queue
	}

	deinit {
		stop()
	}

	/// Starts monitoring the directory.
	public func start() {
		let fd = open(path, O_EVTONLY)
		guard fd >= 0 else { return }

		let src = DispatchSource.makeFileSystemObjectSource(
			fileDescriptor: fd,
			eventMask: .write,
			queue: queue,
		)

		src.setEventHandler { [weak self] in
			guard let self else { return }
			callback(path)
		}

		src.setCancelHandler {
			close(fd)
		}

		source = src
		src.resume()
	}

	/// Stops monitoring the directory.
	public func stop() {
		source?.cancel()
		source = nil
	}

	/// Whether the watcher is currently active.
	public var isActive: Bool {
		source != nil
	}
}
