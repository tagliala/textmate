import Foundation

/// Port of C++ `fs::event_callback_t`, `fs::watch`, `fs::unwatch`
/// (io/src/events.h, events.cc).
/// Wraps FSEventStream for watching file system changes.
/// Default implementation for optional EventHandler method.
public extension FSEventWatcher.EventHandler {
	func setReplayingHistory(_: Bool, observedPath _: String, eventId _: UInt64) {}
}

public final class FSEventWatcher: @unchecked Sendable {
	/// Callback protocol for file system events.
	public protocol EventHandler: AnyObject, Sendable {
		/// Called when a path changes. `observedPath` is the root being watched.
		func didChange(path: String, observedPath: String, eventId: UInt64, recursive: Bool)
		/// Called when history replay starts or stops.
		func setReplayingHistory(_ flag: Bool, observedPath: String, eventId: UInt64)
	}

	// MARK: - Types

	private final class WatchedStream {
		let requestedPath: String
		var observedPath: String
		let callback: EventHandler
		var stream: FSEventStreamRef?
		var eventId: FSEventStreamEventId
		var isReplaying: Bool = false
		var requestedExists: Bool
		private var requestedInfo: FileInfo
		private var observedInfo: FileInfo

		struct FileInfo: Equatable {
			let path: String
			let exists: Bool
			let isDirectory: Bool
			let mode: mode_t
			let mtime_sec: Int
			let mtime_nsec: Int
			let ctime_sec: Int
			let ctime_nsec: Int

			init(_ path: String) {
				self.path = path
				var buf = stat()
				if lstat(path, &buf) == 0 {
					exists = true
					mode = buf.st_mode
					isDirectory = (buf.st_mode & S_IFMT) == S_IFDIR
					mtime_sec = buf.st_mtimespec.tv_sec
					mtime_nsec = buf.st_mtimespec.tv_nsec
					ctime_sec = buf.st_ctimespec.tv_sec
					ctime_nsec = buf.st_ctimespec.tv_nsec
				} else {
					exists = false
					mode = 0
					isDirectory = false
					mtime_sec = 0
					mtime_nsec = 0
					ctime_sec = 0
					ctime_nsec = 0
				}
			}
		}

		init(path: String, callback: EventHandler, eventId: FSEventStreamEventId, latency: CFTimeInterval) {
			requestedPath = path
			self.callback = callback
			self.eventId = eventId
			requestedExists = true

			// Find nearest existing parent directory for observing
			var observed = path
			requestedExists = true
			while !FileInfo(observed).isDirectory, observed != "/" {
				observed = PathUtilities.parent(observed)
				requestedExists = false
			}
			// Resolve to real path
			if let real = realpath(observed, nil) {
				observedPath = String(cString: real)
				free(real)
			} else {
				observedPath = observed
			}
			observedInfo = FileInfo(observedPath)
			requestedInfo = FileInfo(requestedPath)

			// Create FSEventStream
			var context = FSEventStreamContext()
			context.info = Unmanaged.passUnretained(self).toOpaque()

			let pathsToWatch = [observedPath] as CFArray
			stream = FSEventStreamCreate(
				kCFAllocatorDefault,
				WatchedStream.fsEventCallback,
				&context,
				pathsToWatch,
				eventId,
				latency,
				FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone),
			)

			self.eventId = FSEventsGetCurrentEventId()
		}

		deinit {
			guard let stream else { return }
			FSEventStreamStop(stream)
			FSEventStreamInvalidate(stream)
			FSEventStreamRelease(stream)
		}

		func setReplayingHistory(_ flag: Bool, eventId: FSEventStreamEventId) {
			guard flag != isReplaying else { return }
			isReplaying = flag
			self.eventId = max(eventId, self.eventId)
			callback.setReplayingHistory(
				flag, observedPath: requestedPath,
				eventId: flag ? eventId : self.eventId,
			)
		}

		func handleEvents(
			_ numEvents: Int,
			paths: UnsafeMutableRawPointer,
			flags: UnsafePointer<FSEventStreamEventFlags>,
			ids: UnsafePointer<FSEventStreamEventId>,
		) {
			let pathArray = paths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>.self)
			var lastEventId: UInt64 = 0

			for i in 0 ..< numEvents {
				var eventPath = String(cString: pathArray[i])

				// Remap path if observed dir differs from requested
				if requestedExists, requestedPath != observedPath {
					if let rel = PathUtilities.relativeTo(eventPath, base: observedPath) {
						eventPath = PathUtilities.join(requestedPath, rel)
					}
				}

				// Strip trailing slash
				if eventPath.count > 1, eventPath.hasSuffix("/") {
					eventPath = String(eventPath.dropLast())
				}

				if flags[i] & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 {
					setReplayingHistory(false, eventId: ids[i])
				} else {
					processChangeEvent(
						path: eventPath,
						eventId: ids[i],
						recursive: flags[i] & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0,
					)
					lastEventId = ids[i]
				}
			}

			if !isReplaying, lastEventId > 0 {
				eventId = lastEventId
			}
		}

		private func processChangeEvent(path: String, eventId: UInt64, recursive: Bool) {
			if !requestedInfo.exists {
				// Check if requested path was created
				let parentPath = PathUtilities.parent(requestedPath)
				if path.hasPrefix(parentPath) {
					requestedInfo = FileInfo(requestedPath)
					if requestedInfo.exists {
						if !requestedInfo.isDirectory {
							callback.didChange(
								path: requestedPath,
								observedPath: requestedPath,
								eventId: eventId,
								recursive: recursive,
							)
						} else if path.hasPrefix(requestedPath) {
							callback.didChange(path: path, observedPath: requestedPath, eventId: eventId, recursive: recursive)
						}
					}
				}
			} else if !requestedInfo.isDirectory {
				// File watch: check if modified
				if path == PathUtilities.parent(requestedPath) {
					let newInfo = FileInfo(requestedPath)
					if requestedInfo != newInfo {
						requestedInfo = newInfo
						callback.didChange(
							path: requestedPath,
							observedPath: requestedPath,
							eventId: eventId,
							recursive: recursive,
						)
					}
				}
			} else if path.hasPrefix(requestedPath) {
				// Directory watch: event inside our directory
				callback.didChange(path: path, observedPath: requestedPath, eventId: eventId, recursive: recursive)
			}
		}

		/// C callback for FSEventStream
		private static let fsEventCallback: FSEventStreamCallback =
			{ _, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds in
				guard let info = clientCallBackInfo else { return }
				let stream = Unmanaged<WatchedStream>.fromOpaque(info).takeUnretainedValue()
				stream.handleEvents(numEvents, paths: eventPaths, flags: eventFlags, ids: eventIds)
			}
	}

	// MARK: - Properties

	private var streams: [WatchedStream] = []
	private let lock = NSLock()

	// MARK: - Singleton

	/// Shared FSEventWatcher instance.
	public static let shared = FSEventWatcher()

	public init() {}

	// MARK: - Public API

	/// Start watching a path for changes.
	/// - Parameters:
	///   - path: The path to watch (file or directory).
	///   - callback: Handler to receive change notifications.
	///   - eventId: Start from this event ID (`FSEventStreamEventId.max` for "since now").
	///   - latency: Coalescing latency in seconds (default 1.0).
	public func watch(
		_ path: String,
		callback: EventHandler,
		eventId: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 1.0,
	) {
		let stream = WatchedStream(path: path, callback: callback, eventId: eventId, latency: latency)

		lock.lock()
		streams.append(stream)
		lock.unlock()

		guard let fsStream = stream.stream else { return }
		FSEventStreamSetDispatchQueue(fsStream, DispatchQueue.main)

		if eventId != FSEventStreamEventId(kFSEventStreamEventIdSinceNow) {
			stream.setReplayingHistory(true, eventId: eventId)
		}

		FSEventStreamStart(fsStream)
		FSEventStreamFlushSync(fsStream)
	}

	/// Stop watching a path for a specific callback.
	public func unwatch(_ path: String, callback: EventHandler) {
		lock.lock()
		defer { lock.unlock() }
		if let idx = streams.firstIndex(where: { $0.requestedPath == path && $0.callback === callback }) {
			streams.remove(at: idx)
		}
	}
}
