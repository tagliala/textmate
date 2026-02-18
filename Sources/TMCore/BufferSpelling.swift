/// Tracks misspelled word ranges within a buffer, automatically adjusting
/// positions when the buffer content changes.
///
/// Misspellings are stored as position-indexed boolean ranges: `true` marks
/// the start of a misspelled segment, `false` marks a return to correctly-
/// spelled text. The parsing subsystem calls
/// ``updateMisspellings(from:to:ranges:)`` after re-checking a region.
///
/// Register a `BufferSpelling` instance as a ``BufferCallback`` on a
/// ``TextBuffer`` to have positions auto-adjusted on edits.
///
/// Ported from C++ `spelling_t` in `Frameworks/buffer/src/spelling.cc`.
public final class BufferSpelling: BufferCallback, @unchecked Sendable {
	/// Position → misspelled flag. `true` = misspelled region starts,
	/// `false` = properly-spelled region starts.
	private var misspellings: IndexedMap<Bool> = IndexedMap()

	/// Creates an empty spelling tracker.
	public init() {}

	// MARK: - Query

	/// Whether there are no misspelling records.
	public var isEmpty: Bool {
		misspellings.isEmpty
	}

	/// Returns `true` if the text at `offset` is within a misspelled region.
	public func isMisspelled(at offset: Int) -> Bool {
		// Find the last entry at or before `offset`.
		let idx = misspellings.upperBound(at: offset)
		if idx > 0 {
			return misspellings[idx - 1].value
		}
		return false
	}

	/// Returns the position of the next misspelling at or after `from`.
	///
	/// - Returns: The byte offset of the start of the next misspelled region,
	///   or `nil` if no misspellings exist at or after `from`.
	public func nextMisspelling(from: Int) -> Int? {
		// Use upperBound so a `false` entry at exactly `from` is
		// correctly treated as "not misspelled".
		let ubIdx = misspellings.upperBound(at: from)

		// If `from` is already within a misspelled region, return `from`.
		if ubIdx > 0, misspellings[ubIdx - 1].value {
			return from
		}

		// Otherwise find the next `true` entry at or after `from`.
		let lbIdx = misspellings.lowerBound(at: from)
		for i in lbIdx ..< misspellings.count {
			if misspellings[i].value {
				return misspellings[i].position
			}
		}
		return nil
	}

	/// Returns all misspelled ranges within `[from, to)`.
	///
	/// Each returned tuple represents a contiguous misspelled region with
	/// its start and end byte offsets.
	public func misspellings(from: Int, to: Int) -> [(start: Int, end: Int)] {
		var result: [(Int, Int)] = []

		// Determine the initial misspelling state at `from`.
		let startIdx = misspellings.upperBound(at: from)
		var inMisspelling = startIdx > 0 && misspellings[startIdx - 1].value
		var regionStart = inMisspelling ? from : 0

		let scanStart = misspellings.lowerBound(at: from)
		for i in scanStart ..< misspellings.count {
			let entry = misspellings[i]
			if entry.position >= to {
				break
			}

			if entry.value, !inMisspelling {
				// Start of misspelled region.
				regionStart = max(entry.position, from)
				inMisspelling = true
			} else if !entry.value, inMisspelling {
				// End of misspelled region.
				result.append((start: regionStart, end: entry.position))
				inMisspelling = false
			}
		}

		// Close any open region at `to`.
		if inMisspelling {
			result.append((start: regionStart, end: to))
		}

		return result
	}

	// MARK: - Batch Update

	/// Replaces misspelling data in the range `[from, to)` with new ranges.
	///
	/// Called by the spell-checking subsystem after re-checking a region.
	///
	/// - Parameters:
	///   - from: Start of the rechecked range (byte offset).
	///   - to: End of the rechecked range (byte offset).
	///   - ranges: Misspelled sub-ranges within `[from, to)`, each specified
	///     as `(start, end)` byte offsets.
	public func updateMisspellings(from: Int, to: Int, ranges: [(start: Int, end: Int)]) {
		// Remove existing entries in [from, to).
		let lo = misspellings.lowerBound(at: from)
		var toRemove: [Int] = []
		for i in lo ..< misspellings.count {
			let pos = misspellings[i].position
			if pos >= to { break }
			toRemove.append(pos)
		}
		for pos in toRemove.reversed() {
			misspellings.remove(at: pos)
		}

		// Insert new misspelling ranges.
		for range in ranges {
			misspellings.set(at: range.start, value: true)
			misspellings.set(at: range.end, value: false)
		}
	}

	/// Marks the entire contents as needing a recheck by clearing all data.
	public func recheck() {
		misspellings.clear()
	}

	/// Removes all misspelling data.
	public func clear() {
		misspellings.clear()
	}

	// MARK: - BufferCallback

	public func willReplace(from _: Int, to _: Int, bytes _: [UInt8]) {}

	public func didReplace(from: Int, to: Int, length: Int) {
		misspellings.replace(from: from, to: to, newLength: length)
	}
}
