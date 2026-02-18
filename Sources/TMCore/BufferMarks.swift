/// Buffer-level marks that automatically adjust their positions when the
/// buffer content changes.
///
/// Each mark has a *type* (an arbitrary string such as `"bookmark"`,
/// `"search"`, `"diagnostic"`) and an optional *label*. Marks of different
/// types are stored in separate ``IndexedMap`` instances so that queries can
/// be scoped to a single type.
///
/// Register a `BufferMarks` instance as a ``BufferCallback`` on a
/// ``TextBuffer`` to have positions auto-adjusted on edits.
///
/// Ported from C++ `marks_t` in `Frameworks/buffer/src/marks.cc`.
public final class BufferMarks: BufferCallback, @unchecked Sendable {
	/// The indexed map type: position → label string.
	private typealias MarkMap = IndexedMap<String>

	/// Per-type mark storage.
	private var marks: [String: MarkMap] = [:]

	/// Creates an empty mark set.
	public init() {}

	// MARK: - Query

	/// Whether there are no marks of any type.
	public var isEmpty: Bool {
		marks.values.allSatisfy(\.isEmpty)
	}

	/// Total number of marks across all types.
	public var count: Int {
		marks.values.reduce(0) { $0 + $1.count }
	}

	/// Returns the label of the mark at `position` with the given `type`,
	/// or `nil` if no such mark exists.
	public func get(at position: Int, type: String) -> String? {
		marks[type]?.find(at: position)?.value
	}

	/// Returns all marks of the given type whose positions fall in
	/// `[from, to)`.
	public func getRange(from: Int, to: Int, type: String) -> [(position: Int, label: String)] {
		guard let map = marks[type] else { return [] }
		var result: [(Int, String)] = []
		let start = map.lowerBound(at: from)
		for i in start ..< map.count {
			let entry = map[i]
			if entry.position >= to { break }
			result.append((entry.position, entry.value))
		}
		return result
	}

	/// Returns all marks whose positions fall in `[from, to)`, across all
	/// types.
	public func getRange(from: Int, to: Int) -> [(position: Int, type: String, label: String)] {
		var result: [(Int, String, String)] = []
		for (type, map) in marks {
			let start = map.lowerBound(at: from)
			for i in start ..< map.count {
				let entry = map[i]
				if entry.position >= to { break }
				result.append((entry.position, type, entry.value))
			}
		}
		return result.sorted { $0.0 < $1.0 }
	}

	/// Returns the position and label of the next mark at or after `position`
	/// that matches any of the given types, searching forward with wrapping.
	///
	/// - Parameters:
	///   - position: The byte offset to search from.
	///   - types: Mark types to consider. If empty, all types are searched.
	///   - bufferSize: Total buffer size (used for wrapping).
	/// - Returns: The nearest matching mark, or `nil` if no marks exist.
	public func next(
		after position: Int,
		types: [String] = [],
		bufferSize: Int,
	) -> (position: Int, type: String, label: String)? {
		let searchTypes = types.isEmpty ? Array(marks.keys) : types
		var best: (Int, String, String)?

		for type in searchTypes {
			guard let map = marks[type], !map.isEmpty else { continue }
			let idx = map.lowerBound(at: position)
			if idx < map.count {
				let entry = map[idx]
				if best == nil || entry.position < best!.0 {
					best = (entry.position, type, entry.value)
				}
			} else {
				// Wrap: use the first mark of this type.
				let entry = map[0]
				let wrappedPos = entry.position + bufferSize
				if best == nil || wrappedPos < best!.0 {
					best = (entry.position, type, entry.value)
				}
			}
		}

		return best
	}

	/// Returns the position and label of the previous mark before `position`
	/// that matches any of the given types, searching backward with wrapping.
	///
	/// - Parameters:
	///   - position: The byte offset to search from.
	///   - types: Mark types to consider. If empty, all types are searched.
	///   - bufferSize: Total buffer size (used for wrapping).
	/// - Returns: The nearest matching mark, or `nil` if no marks exist.
	public func prev(
		before position: Int,
		types: [String] = [],
		bufferSize _: Int,
	) -> (position: Int, type: String, label: String)? {
		let searchTypes = types.isEmpty ? Array(marks.keys) : types
		var best: (Int, String, String)?

		for type in searchTypes {
			guard let map = marks[type], !map.isEmpty else { continue }
			let idx = map.lowerBound(at: position)
			if idx > 0 {
				let entry = map[idx - 1]
				if best == nil || entry.position > best!.0 {
					best = (entry.position, type, entry.value)
				}
			} else {
				// Wrap: use the last mark of this type.
				let entry = map[map.count - 1]
				if best == nil || entry.position > best!.0 {
					best = (entry.position, type, entry.value)
				}
			}
		}

		return best
	}

	// MARK: - Mutation

	/// Sets a mark at the given position with the specified type and label.
	public func set(at position: Int, type: String, label: String = "") {
		marks[type, default: MarkMap()].set(at: position, value: label)
	}

	/// Removes the mark at the given position with the specified type.
	@discardableResult
	public func remove(at position: Int, type: String) -> Bool {
		marks[type]?.remove(at: position) ?? false
	}

	/// Removes all marks of the given type.
	///
	/// If `type` ends with `"/"`, removes all marks whose type starts with
	/// that prefix (e.g., `"search/"` removes `"search/highlight"`,
	/// `"search/current"`, etc.).
	public func removeAll(type: String) {
		if type.hasSuffix("/") {
			let keysToRemove = marks.keys.filter { $0.hasPrefix(type) }
			for key in keysToRemove {
				marks.removeValue(forKey: key)
			}
		} else {
			marks.removeValue(forKey: type)
		}
	}

	/// Removes all marks of all types.
	public func clear() {
		marks.removeAll()
	}

	// MARK: - BufferCallback

	public func willReplace(from _: Int, to _: Int, bytes _: [UInt8]) {
		// No pre-mutation work needed.
	}

	public func didReplace(from: Int, to: Int, length: Int) {
		for type in marks.keys {
			// The C++ marks_t preserves marks at `to` if there is an entry
			// exactly at the boundary (checked via upper_bound). We replicate
			// this by checking each map individually.
			guard var map = marks[type] else { continue }

			let ub = map.upperBound(at: to)
			let hasMarkAtBoundary = ub < map.count && map[ub].position == to

			if hasMarkAtBoundary {
				// Skip replace for this type — keep mark at the boundary.
				// However, we still need to remove marks that fall strictly
				// within (from, to) — the replace with bindRight would
				// handle [from, to) but we want to keep both boundaries.
				// Actually, the C++ code simply skips the replace entirely
				// when a mark exists at `to`, preserving all marks in the
				// range. This matches TextMate's behavior where marks at
				// edit boundaries are preserved.
				continue
			}

			map.replace(from: from, to: to, newLength: length)
			marks[type] = map
		}
	}
}
