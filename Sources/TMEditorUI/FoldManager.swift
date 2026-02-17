/// A code folding manager that tracks folded ranges and detects fold markers.
///
/// Swift counterpart of C++ `ng::folds_t` in `Frameworks/layout/src/folds.h`.
///
/// The fold manager tracks:
/// - Currently folded byte ranges as `(from, to)` pairs
/// - A legacy indexed map of fold start/end boundaries for the layout engine
/// - Per-line fold info (start/stop markers, indent level) computed lazily
///
/// Unlike the C++ version which is tightly coupled to `buffer_t`, this Swift
/// port uses a protocol (`FoldDataSource`) to decouple from the buffer implementation.
public final class FoldManager: @unchecked Sendable {
	/// The data source providing buffer content and fold pattern info.
	public let dataSource: FoldDataSource

	/// Currently folded ranges as (from, to) byte offset pairs, sorted.
	private var _folded: [(from: Int, to: Int)] = []

	/// Legacy indexed map: byte_offset → isFoldStart.
	/// Entries alternate between fold-start (true) and fold-end (false) at nesting level 0.
	private var _legacy: [(offset: Int, isStart: Bool)] = []

	/// Creates a fold manager with the given data source.
	public init(dataSource: FoldDataSource) {
		self.dataSource = dataSource
	}

	// MARK: - Serialization

	/// Returns a string representation of currently folded ranges.
	///
	/// Format: `((from1,to1),(from2,to2),...)` matching the C++ plist format.
	public func foldedAsString() -> String? {
		guard !_folded.isEmpty else { return nil }
		let parts = _folded.map { "(\($0.from),\($0.to))" }
		return "(" + parts.joined(separator: ",") + ")"
	}

	/// Restores folded ranges from a serialized string.
	///
	/// - Parameter str: A plist-style array string of (from, to) pairs.
	public func setFolded(fromString str: String) {
		let pairs = parseFoldedString(str)
		setFolded(pairs)
	}

	// MARK: - Query API

	/// Whether the given line number has any folded content.
	public func hasFolded(line n: Int) -> Bool {
		let bol = dataSource.lineStart(n)
		let eol = dataSource.lineEnd(n)
		for pair in _folded {
			if (pair.from <= bol && bol <= pair.to) || (pair.from <= eol && eol <= pair.to) {
				return true
			}
		}
		return false
	}

	/// Whether the given line has a fold start marker.
	public func hasStartMarker(line n: Int) -> Bool {
		let info = infoFor(line: n)
		return info.isStartMarker || info.isIndentStartMarker
	}

	/// Whether the given line has a fold stop marker.
	public func hasStopMarker(line n: Int) -> Bool {
		infoFor(line: n).isStopMarker
	}

	/// The currently folded ranges, sorted.
	public var foldedRanges: [(from: Int, to: Int)] {
		_folded
	}

	/// The legacy indexed fold boundary map.
	public var foldBoundaries: [(offset: Int, isStart: Bool)] {
		_legacy
	}

	// MARK: - Folding API

	/// Fold the range from `from` to `to`.
	public func fold(from: Int, to: Int) {
		var newFoldings = _folded
		newFoldings.append((from, to))
		setFolded(newFoldings)
	}

	/// Unfold the range matching `from`..`to`. Returns true if a match was found.
	@discardableResult
	public func unfold(from: Int, to: Int) -> Bool {
		var found = false
		var newFoldings: [(from: Int, to: Int)] = []

		for pair in _folded {
			if (from == pair.from && pair.to <= to) || (from <= pair.from && pair.to == to) {
				found = true
			} else {
				newFoldings.append(pair)
			}
		}

		if found {
			setFolded(newFoldings)
		}
		return found
	}

	/// Remove all folds enclosing the range `from`..`to`.
	/// Returns the removed fold ranges.
	@discardableResult
	public func removeEnclosing(from: Int, to: Int) -> [(from: Int, to: Int)] {
		var removed: [(from: Int, to: Int)] = []
		var newFoldings: [(from: Int, to: Int)] = []

		for pair in _folded {
			if (pair.from <= from && from < pair.to) || (pair.from < to && to <= pair.to) {
				removed.append(pair)
			} else {
				newFoldings.append(pair)
			}
		}

		setFolded(newFoldings)
		return removed
	}

	/// Toggle fold at the given line. Returns the affected range.
	///
	/// If the line has a fold, it is unfolded. If it has a fold marker,
	/// the foldable range is folded.
	/// - Parameters:
	///   - n: The zero-based line number.
	///   - recursive: If true, fold/unfold all nested ranges too.
	/// - Returns: The affected range, or `(0, 0)` if nothing changed.
	public func toggleAtLine(_ n: Int, recursive: Bool) -> (from: Int, to: Int) {
		var result = (from: 0, to: 0)

		if hasFolded(line: n) {
			// Unfold
			let bol = dataSource.lineStart(n)
			let eol = dataSource.lineEnd(n)
			var newFoldings: [(from: Int, to: Int)] = []

			for pair in _folded {
				let bolClamped = max(bol, min(pair.from, pair.to))
				let eolClamped = max(eol, min(pair.from, pair.to))
				if bolClamped == bol || eolClamped == eol {
					if result.from == result.to {
						result = pair
					}
				} else if !recursive || !(result.from <= pair.from && pair.to <= result.to) {
					newFoldings.append(pair)
				}
			}
			setFolded(newFoldings)
		} else {
			// Fold
			result = foldableRangeAtLine(n)
			if result.from < result.to {
				if recursive {
					for pair in foldableRanges() {
						if result.from <= pair.from, pair.to <= result.to {
							fold(from: pair.from, to: pair.to)
						}
					}
				} else {
					fold(from: result.from, to: result.to)
				}
			}
		}

		return result
	}

	/// Toggle all folds at the specified nesting level.
	///
	/// - Parameter level: The nesting level (0 = all levels).
	/// - Returns: The ranges that were toggled.
	public func toggleAllAtLevel(_ level: Int) -> [(from: Int, to: Int)] {
		let folded = _folded

		// Compute ranges at the target nesting level
		var unfolded: [(from: Int, to: Int)] = []
		var nestingStack: [(from: Int, to: Int)] = []

		for pair in foldableRanges() {
			while let last = nestingStack.last, last.to <= pair.from {
				nestingStack.removeLast()
			}
			nestingStack.append(pair)

			if level == 0 || level == nestingStack.count {
				unfolded.append(pair)
			}
		}

		unfolded.sort { $0.from < $1.from || ($0.from == $1.from && $0.to < $1.to) }

		let sortedFolded = folded.sorted { $0.from < $1.from || ($0.from == $1.from && $0.to < $1.to) }

		// Compute set difference and intersection
		var canFoldAtLevel: [(from: Int, to: Int)] = []
		var foldedAtLevel: [(from: Int, to: Int)] = []

		let foldedSet = Set(sortedFolded.map { PairKey(from: $0.from, to: $0.to) })
		for u in unfolded {
			if foldedSet.contains(PairKey(from: u.from, to: u.to)) {
				foldedAtLevel.append(u)
			} else {
				canFoldAtLevel.append(u)
			}
		}

		if canFoldAtLevel.count >= foldedAtLevel.count {
			for pair in canFoldAtLevel {
				fold(from: pair.from, to: pair.to)
			}
			return canFoldAtLevel
		} else {
			// Unfold: remove foldedAtLevel from current folds
			let toRemove = Set(foldedAtLevel.map { PairKey(from: $0.from, to: $0.to) })
			var newFoldings: [(from: Int, to: Int)] = []
			for f in folded {
				if !toRemove.contains(PairKey(from: f.from, to: f.to)) {
					newFoldings.append(f)
				}
			}
			setFolded(newFoldings)
			return foldedAtLevel
		}
	}

	// MARK: - Buffer Callback

	/// Called before a buffer replacement. Adjusts fold positions.
	///
	/// - Parameters:
	///   - from: Start of the replaced range.
	///   - to: End of the replaced range.
	///   - newLength: Length of the replacement text.
	public func willReplace(from: Int, to: Int, newLength: Int) {
		let delta = newLength - (to - from)
		var newFoldings: [(from: Int, to: Int)] = []

		for pair in _folded {
			if to <= pair.from {
				// Fold entirely after replacement
				newFoldings.append((pair.from + delta, pair.to + delta))
			} else if pair.from <= from, to <= pair.to, delta != pair.from - pair.to {
				// Replacement fully inside fold
				newFoldings.append((pair.from, pair.to + delta))
			} else if pair.to <= from {
				// Fold entirely before replacement
				newFoldings.append(pair)
			}
			// Else: fold overlaps replacement boundary → removed
		}

		setFolded(newFoldings)
	}

	// MARK: - Internal

	/// Per-line fold information.
	public struct LineInfo: Sendable {
		/// Indentation level of the line.
		public var indent: Int = 0
		/// Whether the line contains a fold start marker (e.g. `{`).
		public var isStartMarker: Bool = false
		/// Whether the line contains a fold stop marker (e.g. `}`).
		public var isStopMarker: Bool = false
		/// Whether the line is an indent-based fold start.
		public var isIndentStartMarker: Bool = false
		/// Whether the line should be ignored for folding purposes.
		public var isIgnoreLine: Bool = false
		/// Whether the line is blank/empty.
		public var isEmpty: Bool = false
	}

	/// Compute fold info for a given line.
	private func infoFor(line n: Int) -> LineInfo {
		dataSource.foldInfo(forLine: n)
	}

	/// Update the legacy fold boundary map from the current folded ranges.
	private func setFolded(_ newFoldings: [(from: Int, to: Int)]) {
		let sorted = newFoldings.sorted { $0.from < $1.from || ($0.from == $1.from && $0.to < $1.to) }
		if _folded == sorted { return }
		_folded = sorted

		// Build the legacy boundary map
		var tmp: [(offset: Int, delta: Int)] = []
		for pair in _folded {
			if let idx = tmp.firstIndex(where: { $0.offset == pair.from }) {
				tmp[idx].delta += 1
			} else {
				tmp.append((pair.from, 1))
			}
			if let idx = tmp.firstIndex(where: { $0.offset == pair.to }) {
				tmp[idx].delta -= 1
			} else {
				tmp.append((pair.to, -1))
			}
		}

		tmp.sort { $0.offset < $1.offset }
		tmp.removeAll { $0.delta == 0 }

		_legacy.removeAll()
		var level = 0
		for entry in tmp {
			if level == 0, entry.delta > 0 {
				_legacy.append((entry.offset, true))
			}
			level += entry.delta
			if level == 0 {
				_legacy.append((entry.offset, false))
			}
		}
	}

	/// Compute all foldable ranges from fold markers and indentation.
	public func foldableRanges() -> [(from: Int, to: Int)] {
		var result: [(from: Int, to: Int)] = []

		var regularStack: [(offset: Int, indent: Int)] = []
		var indentStack: [(offset: Int, indent: Int)] = []
		var emptyLineCount = 0

		let lineCount = dataSource.lineCount

		for n in 0 ..< lineCount {
			let info = infoFor(line: n)

			// Pop indent stack when indentation decreases
			while let last = indentStack.last,
			      !info.isEmpty, !info.isIgnoreLine,
			      info.indent <= last.indent
			{
				if last.offset < dataSource.lineEnd(n - 1) {
					result.append((last.offset, dataSource.lineEnd(n - 1 - emptyLineCount)))
				}
				indentStack.removeLast()
			}

			emptyLineCount = info.isEmpty && !info.isIndentStartMarker ? emptyLineCount + 1 : 0

			if info.isStartMarker {
				regularStack.append((dataSource.lineEnd(n), info.indent))
			} else if info.isIndentStartMarker {
				indentStack.append((dataSource.lineEnd(n), info.indent))
			} else if info.isStopMarker {
				for i in stride(from: regularStack.count - 1, through: 0, by: -1) {
					if regularStack[i].indent == info.indent {
						let startOffset = regularStack[i].offset
						// Find the first non-whitespace character on the stop line
						var last = dataSource.lineStart(n)
						let lineEnd = dataSource.lineEnd(n)
						let bufferSize = dataSource.bufferSize
						while last < bufferSize, last < lineEnd {
							let ch = dataSource.character(at: last)
							if ch != "\t", ch != " " { break }
							last += 1
						}
						result.append((startOffset, last))
						regularStack.removeSubrange(i...)
						break
					}
				}
			}
		}

		// Remaining indent-based folds extend to end of buffer
		for i in stride(from: indentStack.count - 1, through: 0, by: -1) {
			result.append((indentStack[i].offset, dataSource.bufferSize))
		}

		result.sort { $0.from < $1.from || ($0.from == $1.from && $0.to < $1.to) }

		// Remove improperly nested ranges
		var nestingStack: [(from: Int, to: Int)] = []
		var unique: [(from: Int, to: Int)] = []
		for pair in result {
			while let last = nestingStack.last, last.to <= pair.from {
				nestingStack.removeLast()
			}
			if let last = nestingStack.last, last.to < pair.to {
				continue
			}
			nestingStack.append(pair)
			unique.append(pair)
		}
		return unique
	}

	/// Find the foldable range at the given line.
	private func foldableRangeAtLine(_ n: Int) -> (from: Int, to: Int) {
		var result = (from: 0, to: 0)
		let bol = dataSource.lineStart(n)
		let eol = dataSource.lineEnd(n)

		for pair in foldableRanges() {
			let bolClamped = max(bol, min(pair.from, pair.to))
			let eolClamped = max(eol, min(pair.from, pair.to))
			if bolClamped == bol || eolClamped == eol {
				result = pair
			}
		}
		return result
	}

	/// Parse a plist-style folded ranges string.
	private func parseFoldedString(_ str: String) -> [(from: Int, to: Int)] {
		var result: [(from: Int, to: Int)] = []
		// Parse simple format: ((from1,to1),(from2,to2),...)
		let scanner = str.unicodeScalars
		var idx = scanner.startIndex
		let end = scanner.endIndex

		func skipWhitespace() {
			while idx < end, scanner[idx] == " " || scanner[idx] == "\n" || scanner[idx] == "\r" {
				idx = scanner.index(after: idx)
			}
		}

		func scanInt() -> Int? {
			skipWhitespace()
			var numStr = ""
			while idx < end, scanner[idx].value >= 0x30, scanner[idx].value <= 0x39 {
				numStr.append(Character(scanner[idx]))
				idx = scanner.index(after: idx)
			}
			return Int(numStr)
		}

		func expect(_ ch: Unicode.Scalar) -> Bool {
			skipWhitespace()
			if idx < end, scanner[idx] == ch {
				idx = scanner.index(after: idx)
				return true
			}
			return false
		}

		guard expect("(") else { return result }
		while idx < end {
			skipWhitespace()
			if scanner[idx] == ")" { break }
			guard expect("(") else { break }
			guard let from = scanInt() else { break }
			guard expect(",") else { break }
			guard let to = scanInt() else { break }
			guard expect(")") else { break }

			if from < dataSource.bufferSize, to <= dataSource.bufferSize {
				result.append((from, to))
			}

			_ = expect(",")
		}
		return result
	}
}

/// Hashable wrapper for fold range pairs (used in set operations).
private struct PairKey: Hashable {
	let from: Int
	let to: Int
}

// MARK: - Fold Data Source Protocol

/// Protocol for providing buffer content and fold marker information.
///
/// This decouples `FoldManager` from a specific buffer implementation,
/// allowing it to work with any buffer that provides line-level access.
public protocol FoldDataSource: Sendable {
	/// Total number of lines in the buffer.
	var lineCount: Int { get }
	/// Total size of the buffer in bytes.
	var bufferSize: Int { get }

	/// Returns the byte offset of the start of line `n` (0-based).
	func lineStart(_ n: Int) -> Int
	/// Returns the byte offset of the end of line `n` (before the newline).
	func lineEnd(_ n: Int) -> Int

	/// Returns the character at the given byte position as a single-character string.
	func character(at offset: Int) -> String

	/// Returns fold info for the given line number.
	///
	/// The fold manager calls this to determine whether a line has fold
	/// start/stop markers, its indentation level, and other properties.
	func foldInfo(forLine n: Int) -> FoldManager.LineInfo
}

/// Equality for fold range tuples.
private func == (lhs: [(from: Int, to: Int)], rhs: [(from: Int, to: Int)]) -> Bool {
	guard lhs.count == rhs.count else { return false }
	for (l, r) in zip(lhs, rhs) {
		if l.from != r.from || l.to != r.to { return false }
	}
	return true
}
