import Foundation

// MARK: - Recent Document Entry

/// An entry in the recent documents list.
public struct RecentDocumentEntry: Codable, Sendable, Equatable {
	/// The file path.
	public var path: String

	/// Display name (filename).
	public var displayName: String

	/// When the file was last opened.
	public var lastOpened: Date

	/// The grammar scope detected at last open.
	public var fileType: String?

	public init(
		path: String,
		displayName: String? = nil,
		lastOpened: Date = Date(),
		fileType: String? = nil,
	) {
		self.path = path
		self.displayName = displayName ?? (path as NSString).lastPathComponent
		self.lastOpened = lastOpened
		self.fileType = fileType
	}
}

// MARK: - Recent Documents Manager

/// Tracks recently opened documents in LRU order.
///
/// Mirrors NSDocumentController's recent documents functionality,
/// but independent of AppKit so it can be used anywhere.
@MainActor
public final class RecentDocumentsManager {
	/// Shared singleton.
	public static let shared = RecentDocumentsManager()

	/// Maximum number of entries to keep.
	public var maxEntries: Int = 25

	/// The recent entries, most recent first.
	public private(set) var entries: [RecentDocumentEntry] = []

	/// Callback when the entries list changes.
	public var onChanged: (() -> Void)?

	/// The key used to persist the recent list in UserDefaults.
	private let defaultsKey = "com.macromates.RecentDocuments"

	private init() {
		loadFromDefaults()
	}

	// MARK: - Tracking

	/// Records a file as recently opened. Moves it to the top if already present.
	public func noteDocumentOpened(
		path: String,
		fileType: String? = nil,
	) {
		let canonical = canonicalize(path)

		// Remove existing entry for this path
		entries.removeAll { $0.path == canonical }

		// Insert at the beginning
		let entry = RecentDocumentEntry(
			path: canonical,
			lastOpened: Date(),
			fileType: fileType,
		)
		entries.insert(entry, at: 0)

		// Trim to max size
		if entries.count > maxEntries {
			entries = Array(entries.prefix(maxEntries))
		}

		saveToDefaults()
		onChanged?()
	}

	/// Removes a specific path from the recent list.
	public func removeEntry(forPath path: String) {
		let canonical = canonicalize(path)
		entries.removeAll { $0.path == canonical }
		saveToDefaults()
		onChanged?()
	}

	/// Clears all recent documents.
	public func clearAll() {
		entries.removeAll()
		saveToDefaults()
		onChanged?()
	}

	/// Removes entries for files that no longer exist on disk.
	public func pruneStale() {
		let before = entries.count
		entries.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
		if entries.count != before {
			saveToDefaults()
			onChanged?()
		}
	}

	// MARK: - Querying

	/// The most recently opened file path, if any.
	public var mostRecent: RecentDocumentEntry? {
		entries.first
	}

	/// The most recently opened paths (as strings).
	public var recentPaths: [String] {
		entries.map(\.path)
	}

	/// Checks whether a path is in the recent list.
	public func contains(path: String) -> Bool {
		let canonical = canonicalize(path)
		return entries.contains { $0.path == canonical }
	}

	// MARK: - Persistence

	private func saveToDefaults() {
		guard let data = try? JSONEncoder().encode(entries) else { return }
		UserDefaults.standard.set(data, forKey: defaultsKey)
	}

	private func loadFromDefaults() {
		guard let data = UserDefaults.standard.data(forKey: defaultsKey),
		      let loaded = try? JSONDecoder().decode([RecentDocumentEntry].self, from: data)
		else { return }
		entries = loaded
	}

	// MARK: - Path Canonicalization

	private func canonicalize(_ path: String) -> String {
		let nsPath = (path as NSString).standardizingPath
		let url = URL(fileURLWithPath: nsPath)
		return url.resolvingSymlinksInPath().path
	}
}
