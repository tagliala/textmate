/// Tracks matched bracket pairs in a buffer, automatically adjusting
/// positions when the buffer content changes.
///
/// Each pair consists of two positions (opener and closer). Pairs are stored
/// in a single ``IndexedMap`` keyed by position, with a *rank* value. Paired
/// entries share the same base rank (`rank & ~1`): even rank = opener,
/// odd rank = closer. This allows O(1) counterpart lookup once an entry's
/// index is known.
///
/// Register a `BracketPairTracker` as a ``BufferCallback`` on a
/// ``TextBuffer`` to have positions auto-adjusted on edits.
///
/// Ported from C++ `pairs_t` in `Frameworks/buffer/src/pairs.cc`.
public final class BracketPairTracker: BufferCallback, @unchecked Sendable {
	/// Position → rank value. Even = opener, odd = closer.
	private var pairs: IndexedMap<Int> = IndexedMap()

	/// Monotonically increasing counter for generating unique rank values.
	/// Incremented by 2 for each new pair (even for opener, odd for closer).
	private var nextRank: Int = 0

	/// Creates an empty pair tracker.
	public init() {}

	// MARK: - Properties

	/// Whether no pairs are being tracked.
	public var isEmpty: Bool {
		pairs.isEmpty
	}

	/// The number of individual bracket positions tracked (always even when
	/// all pairs are complete).
	public var count: Int {
		pairs.count
	}

	// MARK: - Mutation

	/// Adds a bracket pair at the given positions.
	///
	/// - Parameters:
	///   - first: The opener position (byte offset).
	///   - last: The closer position (byte offset).
	public func addPair(first: Int, last: Int) {
		pairs.set(at: first, value: nextRank)
		pairs.set(at: last, value: nextRank + 1)
		nextRank += 2
	}

	/// Removes the bracket entry at the given position.
	///
	/// If the removed entry was part of a pair, the counterpart remains
	/// as an orphan. Call ``remove(at:)`` on the counterpart separately
	/// if needed.
	@discardableResult
	public func remove(at position: Int) -> Bool {
		pairs.remove(at: position)
	}

	/// Removes all tracked pairs.
	public func clear() {
		pairs.clear()
		nextRank = 0
	}

	// MARK: - Query

	/// Whether the position is an opener (first element of a pair).
	public func isFirst(at position: Int) -> Bool {
		guard let entry = pairs.find(at: position) else { return false }
		return entry.value % 2 == 0
	}

	/// Whether the position is a closer (last element of a pair).
	public func isLast(at position: Int) -> Bool {
		guard let entry = pairs.find(at: position) else { return false }
		return entry.value % 2 == 1
	}

	/// Whether the position is part of any pair (opener or closer).
	public func isPaired(at position: Int) -> Bool {
		pairs.find(at: position) != nil
	}

	/// Returns the counterpart position of the bracket at the given position.
	///
	/// If `position` is an opener, returns the closer position, and vice
	/// versa. Returns `nil` if no bracket exists at the position or if the
	/// counterpart has been removed.
	public func counterpart(of position: Int) -> Int? {
		guard let entry = pairs.find(at: position) else { return nil }
		let rank = entry.value
		// The counterpart has rank with the other parity: even ↔ odd.
		let targetRank = rank % 2 == 0 ? rank + 1 : rank - 1

		// Linear scan for the counterpart. With the tree-based implementation
		// this would be O(n) worst case regardless, since rank-based lookup
		// requires a full scan.
		for other in pairs {
			if other.value == targetRank {
				return other.position
			}
		}
		return nil
	}

	/// Returns all tracked pair entries as `(position, isOpener)` tuples,
	/// sorted by position.
	public var allEntries: [(position: Int, isOpener: Bool)] {
		pairs.map { (position: $0.position, isOpener: $0.value % 2 == 0) }
	}

	// MARK: - BufferCallback

	public func willReplace(from _: Int, to _: Int, bytes _: [UInt8]) {
		// No pre-mutation work needed.
	}

	public func didReplace(from: Int, to: Int, length: Int) {
		// Before adjusting positions, remove any pairs where one or both
		// members fall within the replaced range. The C++ implementation
		// collects affected ranks -> removes both members of those pairs.
		var affectedRanks: Set<Int> = []
		let lo = pairs.lowerBound(at: from)
		let hi = pairs.lowerBound(at: to)
		for i in lo ..< hi {
			affectedRanks.insert(pairs[i].value & ~1) // base rank (even)
		}

		if !affectedRanks.isEmpty {
			// Remove all entries whose base rank is affected.
			// Walk backwards to keep indices valid.
			var i = pairs.count - 1
			while i >= 0 {
				if affectedRanks.contains(pairs[i].value & ~1) {
					// Remove by position (since IndexedMap doesn't have
					// index-based removal).
					pairs.remove(at: pairs[i].position)
				}
				i -= 1
			}
		}

		// Adjust positions for the replacement.
		pairs.replace(from: from, to: to, newLength: length)
	}
}
