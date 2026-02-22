/// A position-indexed map that automatically adjusts entry positions when the
/// underlying buffer content changes.
///
/// Entries are sorted by their buffer position. When text is inserted, deleted,
/// or replaced in the buffer, call ``replace(from:to:newLength:bindRight:)``
/// to shift or remove affected entries.
///
/// Ported from C++ `indexed_map_t` in `Frameworks/buffer/src/indexed_map.h`.
/// Uses a sorted array internally; the interface could be upgraded to an
/// augmented balanced tree for O(log n) mutations.
struct IndexedMap<Value: Sendable>: Sendable {
	/// A single entry associating a buffer position with a value.
	struct Entry: Sendable {
		/// The byte offset in the buffer.
		var position: Int
		/// The associated value.
		var value: Value

		init(position: Int, value: Value) {
			self.position = position
			self.value = value
		}
	}

	/// Entries sorted by ascending position.
	private var entries: [Entry] = []

	/// Creates an empty indexed map.
	init() {}

	// MARK: - Properties

	/// Whether the map contains no entries.
	var isEmpty: Bool {
		entries.isEmpty
	}

	/// The number of entries in the map.
	var count: Int {
		entries.count
	}

	// MARK: - Lookup

	/// Returns the index where an entry at `position` would be inserted
	/// to maintain sorted order (first index with `entry.position >= position`).
	private func insertionIndex(for position: Int) -> Int {
		var lo = 0
		var hi = entries.count
		while lo < hi {
			let mid = lo + (hi - lo) / 2
			if entries[mid].position < position {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		return lo
	}

	/// Returns the index of the first entry with `position > key`.
	private func upperBoundIndex(for key: Int) -> Int {
		var lo = 0
		var hi = entries.count
		while lo < hi {
			let mid = lo + (hi - lo) / 2
			if entries[mid].position <= key {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		return lo
	}

	/// Returns the index of the entry at the exact position, or `nil`.
	func findIndex(at position: Int) -> Int? {
		let idx = insertionIndex(for: position)
		if idx < entries.count, entries[idx].position == position {
			return idx
		}
		return nil
	}

	/// Returns the entry at the exact position, or `nil`.
	func find(at position: Int) -> Entry? {
		if let idx = findIndex(at: position) {
			return entries[idx]
		}
		return nil
	}

	/// Returns the index of the first entry with `position >= key`.
	func lowerBound(at key: Int) -> Int {
		insertionIndex(for: key)
	}

	/// Returns the index of the first entry with `position > key`.
	func upperBound(at key: Int) -> Int {
		upperBoundIndex(for: key)
	}

	/// Returns the `n`-th entry (zero-based), or `nil` if out of range.
	func nth(_ n: Int) -> Entry? {
		guard n >= 0, n < entries.count else { return nil }
		return entries[n]
	}

	/// Returns the entry at the given element index.
	///
	/// - Precondition: `index` is in `0 ..< count`.
	subscript(index: Int) -> Entry {
		entries[index]
	}

	// MARK: - Mutation

	/// Inserts or updates the value at the given position.
	mutating func set(at position: Int, value: Value) {
		let idx = insertionIndex(for: position)
		if idx < entries.count, entries[idx].position == position {
			entries[idx].value = value
		} else {
			entries.insert(Entry(position: position, value: value), at: idx)
		}
	}

	/// Removes the entry at the given position.
	///
	/// - Returns: `true` if an entry was found and removed.
	@discardableResult
	mutating func remove(at position: Int) -> Bool {
		if let idx = findIndex(at: position) {
			entries.remove(at: idx)
			return true
		}
		return false
	}

	/// Removes entries at element indices in the given range.
	mutating func removeSubrange(_ range: Range<Int>) {
		guard !range.isEmpty else { return }
		entries.removeSubrange(range)
	}

	/// Removes all entries.
	mutating func clear() {
		entries.removeAll()
	}

	/// Adjusts entry positions after a buffer replacement.
	///
	/// Entries within the replaced region are removed. Entries beyond the
	/// region are shifted by `newLength - (to - from)`.
	///
	/// - Parameters:
	///   - from: Start of the replaced range (byte offset).
	///   - to: End of the replaced range (byte offset).
	///   - newLength: Length of the replacement text in bytes.
	///   - bindRight: When `true` (default), entries at `from` are removed and
	///     entries at `to` are kept (shifted). When `false`, entries at `from`
	///     are kept and entries at `to` are removed.
	mutating func replace(from: Int, to: Int, newLength: Int, bindRight: Bool = true) {
		let delta = newLength - (to - from)

		if bindRight {
			// Remove entries with position in [from, to).
			let removeStart = lowerBound(at: from)
			let removeEnd = lowerBound(at: to)
			if removeStart < removeEnd {
				entries.removeSubrange(removeStart ..< removeEnd)
			}
			// Shift entries with position >= to.
			let shiftStart = lowerBound(at: to)
			for i in shiftStart ..< entries.count {
				entries[i].position += delta
			}
		} else {
			// Remove entries with position in (from, to].
			let removeStart = upperBound(at: from)
			let removeEnd = upperBound(at: to)
			if removeStart < removeEnd {
				entries.removeSubrange(removeStart ..< removeEnd)
			}
			// Shift entries with position > to.
			let shiftStart = upperBound(at: to)
			for i in shiftStart ..< entries.count {
				entries[i].position += delta
			}
		}
	}
}

// MARK: - Sequence

extension IndexedMap: Sequence {
	func makeIterator() -> IndexingIterator<[Entry]> {
		entries.makeIterator()
	}
}

// MARK: - CustomStringConvertible

extension IndexedMap: CustomStringConvertible where Value: CustomStringConvertible {
	var description: String {
		let items = entries.map { "\($0.position): \($0.value)" }.joined(separator: ", ")
		return "IndexedMap([\(items)])"
	}
}
