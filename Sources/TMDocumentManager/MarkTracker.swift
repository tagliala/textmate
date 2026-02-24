import Foundation

// MARK: - Mark Type

/// The type of document mark.
public enum MarkType: String, Codable, Sendable, CaseIterable {
	/// A user-set bookmark.
	case bookmark
	/// A search result highlight.
	case search
	/// A compiler error/warning location.
	case diagnostic
	/// A SCM changed line.
	case scmChange
}

// MARK: - Document Mark

/// A mark (bookmark, search result, etc.) at a specific location in a document.
public struct DocumentMark: Codable, Sendable, Equatable, Identifiable {
	/// Unique ID for the mark.
	public let id: UUID

	/// The type of mark.
	public var type: MarkType

	/// The line number (0-based).
	public var line: Int

	/// Optional column for precise positioning.
	public var column: Int?

	/// Optional label for the mark (e.g., search match text).
	public var label: String?

	public init(
		id: UUID = UUID(),
		type: MarkType,
		line: Int,
		column: Int? = nil,
		label: String? = nil,
	) {
		self.id = id
		self.type = type
		self.line = line
		self.column = column
		self.label = label
	}
}

// MARK: - Mark Tracker

/// Global mark tracker — stores marks keyed by canonical file path.
///
/// Equivalent to the C++ mark system in OakDocument. Marks survive
/// document close/reopen because they're stored globally by path.
///
/// When a document is opened, its marks are loaded from the tracker.
/// When a document is closed, its marks are saved back to the tracker.
@MainActor
public final class MarkTracker {
	/// Shared singleton instance.
	public static let shared = MarkTracker()

	// MARK: - Storage

	/// Marks keyed by canonical file path.
	private var marksByPath: [String: [DocumentMark]] = [:]

	/// Callbacks for mark changes.
	private var changeCallbacks: [UUID: (String) -> Void] = [:]

	private init() {}

	// MARK: - Querying

	/// Returns all marks for the given path.
	public func marks(forPath path: String) -> [DocumentMark] {
		marksByPath[canonicalize(path)] ?? []
	}

	/// Returns marks of a specific type for the given path.
	public func marks(forPath path: String, type: MarkType) -> [DocumentMark] {
		marks(forPath: path).filter { $0.type == type }
	}

	/// Returns the bookmarks (line numbers) for the given path.
	public func bookmarks(forPath path: String) -> [Int] {
		marks(forPath: path, type: .bookmark).map(\.line).sorted()
	}

	/// Returns all paths that have marks.
	public var allPaths: [String] {
		Array(marksByPath.keys)
	}

	/// Whether the given path has any marks of the specified type.
	public func hasMarks(forPath path: String, type: MarkType? = nil) -> Bool {
		let m = marks(forPath: path)
		guard let type else { return !m.isEmpty }
		return m.contains { $0.type == type }
	}

	/// Returns the total number of marks across all files.
	public var totalMarkCount: Int {
		marksByPath.values.reduce(0) { $0 + $1.count }
	}

	// MARK: - Mutation

	/// Adds a mark for the given path.
	@discardableResult
	public func addMark(_ mark: DocumentMark, forPath path: String) -> UUID {
		let key = canonicalize(path)
		var marks = marksByPath[key] ?? []
		marks.append(mark)
		marksByPath[key] = marks
		notifyChange(path: key)
		return mark.id
	}

	/// Adds a bookmark at the given line.
	@discardableResult
	public func addBookmark(atLine line: Int, forPath path: String) -> UUID {
		let mark = DocumentMark(type: .bookmark, line: line)
		return addMark(mark, forPath: path)
	}

	/// Removes a specific mark by ID.
	public func removeMark(id: UUID, forPath path: String) {
		let key = canonicalize(path)
		marksByPath[key]?.removeAll { $0.id == id }
		if marksByPath[key]?.isEmpty == true {
			marksByPath.removeValue(forKey: key)
		}
		notifyChange(path: key)
	}

	/// Removes all marks of a specific type for the given path.
	public func removeMarks(forPath path: String, type: MarkType) {
		let key = canonicalize(path)
		marksByPath[key]?.removeAll { $0.type == type }
		if marksByPath[key]?.isEmpty == true {
			marksByPath.removeValue(forKey: key)
		}
		notifyChange(path: key)
	}

	/// Removes all marks for the given path.
	public func removeAllMarks(forPath path: String) {
		let key = canonicalize(path)
		marksByPath.removeValue(forKey: key)
		notifyChange(path: key)
	}

	/// Sets all marks for a path, replacing any existing marks.
	public func setMarks(_ marks: [DocumentMark], forPath path: String) {
		let key = canonicalize(path)
		if marks.isEmpty {
			marksByPath.removeValue(forKey: key)
		} else {
			marksByPath[key] = marks
		}
		notifyChange(path: key)
	}

	/// Toggles a bookmark at the given line. If one exists, removes it; otherwise adds one.
	@discardableResult
	public func toggleBookmark(atLine line: Int, forPath path: String) -> Bool {
		let key = canonicalize(path)
		let existing = marks(forPath: key).filter { $0.type == .bookmark && $0.line == line }
		if let mark = existing.first {
			removeMark(id: mark.id, forPath: key)
			return false // Removed
		} else {
			addBookmark(atLine: line, forPath: key)
			return true // Added
		}
	}

	// MARK: - Line Adjustments

	/// Adjusts mark line numbers when lines are inserted or removed.
	///
	/// - Parameters:
	///   - path: The file path.
	///   - line: The line where the change occurred.
	///   - delta: Positive for insertions, negative for deletions.
	public func adjustLines(forPath path: String, atLine line: Int, delta: Int) {
		let key = canonicalize(path)
		guard var marks = marksByPath[key] else { return }

		marks = marks.compactMap { mark in
			if mark.line < line {
				return mark // Before the change — no adjustment
			}
			let newLine = mark.line + delta
			if newLine < 0 { return nil } // Deleted
			return DocumentMark(
				id: mark.id,
				type: mark.type,
				line: newLine,
				column: mark.column,
				label: mark.label,
			)
		}

		marksByPath[key] = marks
		notifyChange(path: key)
	}

	// MARK: - Path Operations

	/// Transfers marks when a file is renamed.
	public func renamePath(from oldPath: String, to newPath: String) {
		let oldKey = canonicalize(oldPath)
		let newKey = canonicalize(newPath)

		if let marks = marksByPath.removeValue(forKey: oldKey) {
			marksByPath[newKey] = marks
			notifyChange(path: oldKey)
			notifyChange(path: newKey)
		}
	}

	// MARK: - Transfer to/from Document

	/// Loads marks from the tracker into a document's bookmarks.
	public func loadIntoDocument(_ document: TMDocument) {
		guard let path = document.path else { return }
		document.bookmarks = bookmarks(forPath: path)
	}

	/// Saves a document's bookmarks back to the tracker.
	public func saveFromDocument(_ document: TMDocument) {
		guard let path = document.path else { return }

		// Remove old bookmarks, keep other mark types
		removeMarks(forPath: path, type: .bookmark)
		for line in document.bookmarks {
			addBookmark(atLine: line, forPath: path)
		}
	}

	// MARK: - Observation

	/// Registers a callback for mark changes. Returns an ID for removal.
	@discardableResult
	public func addChangeCallback(_ callback: @escaping (String) -> Void) -> UUID {
		let id = UUID()
		changeCallbacks[id] = callback
		return id
	}

	/// Removes a change callback.
	public func removeChangeCallback(id: UUID) {
		changeCallbacks.removeValue(forKey: id)
	}

	private func notifyChange(path: String) {
		for callback in changeCallbacks.values {
			callback(path)
		}
	}

	// MARK: - Serialization

	/// Exports all marks as a dictionary suitable for session serialization.
	public func exportMarks() -> [String: [DocumentMark]] {
		marksByPath
	}

	/// Imports marks from a serialized dictionary.
	public func importMarks(_ marks: [String: [DocumentMark]]) {
		for (path, pathMarks) in marks {
			let key = canonicalize(path)
			marksByPath[key] = pathMarks
		}
	}

	// MARK: - Cleanup

	/// Removes all marks. Useful for testing.
	public func removeAll() {
		marksByPath.removeAll()
	}

	// MARK: - Path Canonicalization

	private func canonicalize(_ path: String) -> String {
		let nsPath = (path as NSString).standardizingPath
		let url = URL(fileURLWithPath: nsPath)
		return url.resolvingSymlinksInPath().path
	}
}
