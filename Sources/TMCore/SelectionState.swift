/// An ordered collection of selections within a text buffer.
///
/// Supports multiple cursors and maintains selections in document order.
/// Overlapping selections are automatically merged after operations.
public struct SelectionState: Sendable, Hashable {
	/// The individual selections, maintained in document order by start offset.
	public private(set) var selections: [TextRange]

	/// Creates a selection state with the given ranges.
	///
	/// Ranges are sorted and overlapping ranges are merged automatically.
	public init(_ ranges: [TextRange]) {
		selections = Self.normalized(ranges)
	}

	/// Creates a selection state with a single caret at the given position.
	public init(caret position: TextPosition) {
		selections = [TextRange(caret: position)]
	}

	/// The number of active selections (carets or ranges).
	public var count: Int {
		selections.count
	}

	/// Whether there is exactly one selection and it is a caret.
	public var isSingleCaret: Bool {
		selections.count == 1 && selections[0].isEmpty
	}

	/// The primary (first) selection.
	public var primary: TextRange? {
		selections.first
	}

	/// The first selection (alias for `primary`).
	///
	/// Mirrors the C++ `ranges_t::first()` accessor.
	public var first: TextRange? {
		selections.first
	}

	/// The last selection.
	///
	/// Mirrors the C++ `ranges_t::last()` accessor.
	public var last: TextRange? {
		selections.last
	}

	/// Sorts and merges overlapping selections.
	private static func normalized(_ ranges: [TextRange]) -> [TextRange] {
		guard ranges.count > 1 else { return ranges }

		let sorted = ranges.sorted { $0.start.offset < $1.start.offset }
		var merged: [TextRange] = [sorted[0]]

		for range in sorted.dropFirst() {
			let last = merged[merged.count - 1]
			if range.start.offset <= last.end.offset {
				// Merge overlapping ranges: keep the wider span
				let newStart = min(last.start, range.start)
				let newEnd = max(last.end, range.end)
				merged[merged.count - 1] = TextRange(
					anchor: newStart,
					head: newEnd,
					isColumnar: last.isColumnar || range.isColumnar,
				)
			} else {
				merged.append(range)
			}
		}

		return merged
	}
}
