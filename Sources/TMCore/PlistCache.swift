import Foundation

// MARK: - PlistCache

/// A filesystem cache that tracks property list files and directories.
///
/// Replaces the C++ `plist::cache_t` which used Cap'n Proto for
/// serialization. This implementation uses Codable/JSON instead.
///
/// The cache tracks:
///  - Files → their parsed plist content + modification time
///  - Directories → their child entry names + FSEvent ID
///  - Symlinks → their target path
///  - Missing entries → known absent paths
public final class PlistCache: @unchecked Sendable {
	// MARK: Entry type

	public enum EntryType: String, Codable, Sendable {
		case file
		case directory
		case link
		case missing
	}

	// MARK: Entry

	public struct Entry: Sendable {
		public let path: String
		public var type: EntryType
		public var linkTarget: String?
		public var modified: TimeInterval = 0
		public var eventID: UInt64 = 0
		public var content: PlistDictionary = [:]
		public var entries: [String] = []
		public var globString: String = ""

		public init(path: String, type: EntryType = .missing) {
			self.path = path
			self.type = type
		}

		public var isFile: Bool {
			type == .file
		}

		public var isDirectory: Bool {
			type == .directory
		}

		public var isLink: Bool {
			type == .link
		}

		public var isMissing: Bool {
			type == .missing
		}

		/// Resolve the symlink target relative to this entry's parent.
		public var resolvedPath: String? {
			guard let target = linkTarget else { return nil }
			let parent = (path as NSString).deletingLastPathComponent
			return (parent as NSString).appendingPathComponent(target)
		}
	}

	// MARK: State

	private let lock = NSLock()
	private var cache: [String: Entry] = [:]
	private var _dirty: Bool = false
	private var _contentFilter: (@Sendable (PlistDictionary) -> PlistDictionary)?

	private static let cacheFormatVersion: Int = 2

	// MARK: Init

	public init() {}

	// MARK: Dirty flag

	public var isDirty: Bool {
		lock.withLock { _dirty }
	}

	public func setDirty(_ flag: Bool) {
		lock.withLock { _dirty = flag }
	}

	// MARK: Content filter

	public func setContentFilter(
		_ filter: (@Sendable (PlistDictionary) -> PlistDictionary)?,
	) {
		lock.withLock { _contentFilter = filter }
	}

	// MARK: Event ID

	public func eventID(forPath path: String) -> UInt64 {
		lock.withLock {
			cache[path]?.eventID ?? 0
		}
	}

	public func setEventID(_ eventID: UInt64, forPath path: String) {
		lock.withLock {
			guard var entry = cache[path], entry.eventID != eventID else { return }
			entry.eventID = eventID
			cache[path] = entry
			_dirty = true
		}
	}

	// MARK: Content

	public func content(forPath path: String) -> PlistDictionary {
		lock.withLock {
			if let entry = cache[path], entry.isMissing {
				cache.removeValue(forKey: path)
			}
			return resolved(path: path).content
		}
	}

	// MARK: Entries

	public func entries(forPath path: String, glob: String? = nil) -> [String] {
		lock.withLock {
			let entry = resolved(path: path, globString: glob)
			return entry.entries.map { name in
				(entry.path as NSString).appendingPathComponent(name)
			}
		}
	}

	// MARK: Erase

	@discardableResult
	public func erase(path: String) -> Bool {
		lock.withLock {
			eraseUnlocked(path: path)
		}
	}

	private func eraseUnlocked(path: String) -> Bool {
		guard let entry = cache[path] else { return false }

		if entry.isDirectory {
			// Remove from parent's entries list
			let parentPath = (path as NSString).deletingLastPathComponent
			if var parent = cache[parentPath], parent.isDirectory {
				let name = (path as NSString).lastPathComponent
				parent.entries.removeAll { $0 == name }
				cache[parentPath] = parent
			}

			// Remove all descendants: keys in [path, path + "0")
			let keysToRemove = cache.keys.filter { $0.hasPrefix(path) }
			for key in keysToRemove {
				cache.removeValue(forKey: key)
			}
		} else {
			cache.removeValue(forKey: path)
		}

		_dirty = true
		return true
	}

	// MARK: Reload

	@discardableResult
	public func reload(path: String, recursive: Bool = false) -> Bool {
		lock.withLock {
			reloadUnlocked(path: path, recursive: recursive)
		}
	}

	private func reloadUnlocked(path: String, recursive: Bool) -> Bool {
		guard var entry = cache[path] else {
			// If not in cache, try reloading the parent
			let p = path as NSString
			guard p.isAbsolutePath, path != "/" else { return false }
			return reloadUnlocked(path: p.deletingLastPathComponent, recursive: recursive)
		}

		var localDirty = false
		var stat_buf = stat()
		let statResult = lstat(path, &stat_buf)

		if statResult == 0 {
			if (stat_buf.st_mode & S_IFMT) == S_IFDIR, entry.isDirectory {
				let oldEntries = recursive ? [String]() : entry.entries
				updateEntries(entry: &entry, globString: entry.globString)
				cache[path] = entry
				let newEntries = entry.entries
				localDirty = oldEntries != newEntries

				for name in newEntries {
					let childPath = (path as NSString).appendingPathComponent(name)
					if let child = cache[childPath], child.isFile || recursive {
						if reloadUnlocked(path: childPath, recursive: recursive) {
							localDirty = true
						}
					}
				}
			} else if !(entry.isFile
				&& (stat_buf.st_mode & S_IFMT) == S_IFREG
				&& entry.modified == TimeInterval(stat_buf.st_mtimespec.tv_sec))
			{
				cache.removeValue(forKey: path)
				localDirty = true
			}
		} else if !entry.isMissing {
			cache.removeValue(forKey: path)
			localDirty = true
		}

		_dirty = _dirty || localDirty
		return localDirty
	}

	// MARK: Cleanup

	/// Remove cache entries not reachable from the given root paths.
	@discardableResult
	public func cleanup(rootPaths: [String]) -> Bool {
		lock.withLock {
			let allPaths = Set(cache.keys)
			var reachable = Set<String>()
			for root in rootPaths {
				collectAll(path: root, into: &reachable)
			}

			let toRemove = allPaths.subtracting(reachable)
			for path in toRemove {
				cache.removeValue(forKey: path)
			}
			_dirty = _dirty || !toRemove.isEmpty
			return !toRemove.isEmpty
		}
	}

	// MARK: Head paths

	/// Collect the given path and all symlink/directory heads reachable from it.
	public func headPaths(forPath path: String) -> [String] {
		lock.withLock {
			var result = [path]
			collectLinks(path: path, into: &result)
			return result
		}
	}

	// MARK: Load / Save (JSON)

	/// Load a cache from a JSON file at the given path.
	public func load(contentsOfFile path: String) {
		lock.withLock {
			guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
			guard let container = try? JSONDecoder().decode(CacheContainer.self, from: data) else { return }
			guard container.version == Self.cacheFormatVersion else { return }

			for saved in container.entries {
				var entry = Entry(path: saved.path, type: saved.type)
				entry.linkTarget = saved.linkTarget
				entry.modified = saved.modified
				entry.eventID = saved.eventID
				entry.entries = saved.entries
				entry.globString = saved.globString

				// Reconstruct content from saved key→value strings
				var content = PlistDictionary()
				for (k, v) in saved.content {
					if let parsed = PlistIO.parse(string: v) {
						content[k] = parsed
					} else {
						content[k] = .string(v)
					}
				}
				entry.content = content
				cache[saved.path] = entry
			}
		}
	}

	/// Save the cache as a JSON file to the given path.
	public func save(toFile path: String) {
		lock.withLock {
			var saved = [SavedEntry]()
			for (_, entry) in cache.sorted(by: { $0.key < $1.key }) {
				var se = SavedEntry(path: entry.path, type: entry.type)
				se.linkTarget = entry.linkTarget
				se.modified = entry.modified
				se.eventID = entry.eventID
				se.entries = entry.entries
				se.globString = entry.globString

				// Serialise content as key → string pairs
				for (k, v) in entry.content {
					if let s = v.stringValue {
						se.content[k] = s
					} else {
						se.content[k] = PlistSerializer.serialize(v)
					}
				}
				saved.append(se)
			}

			let container = CacheContainer(
				version: Self.cacheFormatVersion,
				entries: saved,
			)
			if let data = try? JSONEncoder().encode(container) {
				try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
			}
		}
	}

	// MARK: Private — resolve

	private func resolved(path: String, globString: String? = nil) -> Entry {
		if let existing = cache[path] {
			if existing.isLink, let target = existing.resolvedPath {
				return resolved(path: target, globString: globString)
			}
			return existing
		}

		// Not cached — probe file system
		var entry = Entry(path: path, type: .missing)

		var stat_buf = stat()
		if lstat(path, &stat_buf) == 0 {
			let mode = stat_buf.st_mode & S_IFMT
			if mode == S_IFREG {
				entry.type = .file
			} else if mode == S_IFLNK {
				entry.type = .link
				entry.linkTarget = readLink(path)
			} else if mode == S_IFDIR {
				entry.type = .directory
			}
		}

		if entry.isFile {
			var content = PlistIO.load(contentsOfFile: path) ?? [:]
			if let filter = _contentFilter {
				content = filter(content)
			}
			entry.content = content
			entry.modified = TimeInterval(stat_buf.st_mtimespec.tv_sec)
		} else if entry.isDirectory {
			updateEntries(entry: &entry, globString: globString ?? "")
		}

		cache[path] = entry
		_dirty = true

		if entry.isLink, let target = entry.resolvedPath {
			return resolved(path: target, globString: globString)
		}
		return entry
	}

	// MARK: Private — directory entries

	private func updateEntries(entry: inout Entry, globString: String) {
		let fm = FileManager.default
		var names = [String]()
		if let enumerator = fm.enumerator(
			at: URL(fileURLWithPath: entry.path),
			includingPropertiesForKeys: nil,
			options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants],
		) {
			for case let url as URL in enumerator {
				let name = url.lastPathComponent
				if !globString.isEmpty {
					// Simple glob filtering: check if the name matches
					if fnmatch(globString, name, 0) == 0 {
						names.append(name)
					}
				} else {
					names.append(name)
				}
			}
		}
		names.sort()
		entry.entries = names
		entry.globString = globString
	}

	// MARK: Private — link traversal

	private func collectLinks(path: String, into result: inout [String]) {
		guard let entry = cache[path] else { return }

		if entry.isLink, let target = entry.resolvedPath {
			result.append(target)
			collectLinks(path: target, into: &result)
		} else if entry.isDirectory {
			let childPaths = entry.entries.map { name in
				(entry.path as NSString).appendingPathComponent(name)
			}
			for child in childPaths {
				collectLinks(path: child, into: &result)
			}
		}
	}

	private func collectAll(path: String, into result: inout Set<String>) {
		guard let entry = cache[path] else { return }
		result.insert(path)

		if entry.isDirectory {
			for name in entry.entries {
				let child = (entry.path as NSString).appendingPathComponent(name)
				collectAll(path: child, into: &result)
			}
		} else if entry.isLink, let target = entry.resolvedPath {
			collectAll(path: target, into: &result)
		}
	}

	// MARK: Private — readlink

	private func readLink(_ path: String) -> String? {
		var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
		let len = readlink(path, &buf, buf.count)
		guard len > 0, len < buf.count else { return nil }
		return buf.withUnsafeBufferPointer { ptr in
			let uptr = UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: UInt8.self)
			return String(decoding: UnsafeBufferPointer(start: uptr, count: len), as: UTF8.self)
		}
	}
}

// MARK: - Codable containers

private struct SavedEntry: Codable {
	var path: String
	var type: PlistCache.EntryType
	var linkTarget: String?
	var modified: TimeInterval = 0
	var eventID: UInt64 = 0
	var content: [String: String] = [:]
	var entries: [String] = []
	var globString: String = ""

	init(path: String, type: PlistCache.EntryType) {
		self.path = path
		self.type = type
	}
}

private struct CacheContainer: Codable {
	var version: Int
	var entries: [SavedEntry]
}
