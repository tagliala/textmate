import Foundation

// MARK: - Incremental Search State

/// State for the inline incremental search bar — equivalent to TextMate's `LiveSearchView`.
///
/// The incremental search maintains an anchor position (where the search started)
/// and updates the highlight ranges on each keystroke.
@MainActor
public final class IncrementalSearchState: Observable {
	/// The current search string.
	public var searchString: String = "" {
		didSet { performSearch() }
	}

	/// Whether case is ignored.
	public var ignoreCase: Bool = true {
		didSet { performSearch() }
	}

	/// Whether to wrap around.
	public var wrapAround: Bool = true {
		didSet { performSearch() }
	}

	/// Whether the search bar is active.
	public var isActive: Bool = false

	/// The byte offset where the search started (anchor).
	public var anchorOffset: Int = 0

	/// The current match range, if any.
	public private(set) var currentMatch: FindMatch?

	/// All highlighted match ranges.
	public private(set) var highlightedRanges: [Range<Int>] = []

	/// The buffer text to search in.
	public var bufferText: String = ""

	/// Callback when the search state changes (for UI updates).
	public var onSearchUpdate: ((FindMatch?, [Range<Int>]) -> Void)?

	/// Whether the last search had no results.
	public var hasNoResults: Bool {
		!searchString.isEmpty && currentMatch == nil
	}

	public init() {}

	/// Activate incremental search at the given anchor offset.
	public func activate(anchorOffset: Int, bufferText: String) {
		isActive = true
		self.anchorOffset = anchorOffset
		self.bufferText = bufferText
		searchString = ""
		currentMatch = nil
		highlightedRanges = []
	}

	/// Deactivate incremental search.
	public func deactivate() {
		isActive = false
		searchString = ""
		currentMatch = nil
		highlightedRanges = []
		onSearchUpdate?(nil, [])
	}

	/// Find the next match from the current position.
	public func findNext() {
		guard !searchString.isEmpty, let current = currentMatch else { return }

		let searcher = BufferSearcher(text: bufferText)
		var opts: FindOptions = []
		if ignoreCase { opts.insert(.ignoreCase) }
		if wrapAround { opts.insert(.wrapAround) }

		if let result = try? searcher.findNext(
			pattern: searchString,
			options: opts,
			fromOffset: current.range.upperBound,
		), let match = result.firstMatch {
			currentMatch = match
			onSearchUpdate?(match, highlightedRanges)
		}
	}

	/// Find the previous match from the current position.
	public func findPrevious() {
		guard !searchString.isEmpty, let current = currentMatch else { return }

		let searcher = BufferSearcher(text: bufferText)
		var opts: FindOptions = [.backwards]
		if ignoreCase { opts.insert(.ignoreCase) }
		if wrapAround { opts.insert(.wrapAround) }

		if let result = try? searcher.findNext(
			pattern: searchString,
			options: opts,
			fromOffset: current.range.lowerBound,
		), let match = result.firstMatch {
			currentMatch = match
			onSearchUpdate?(match, highlightedRanges)
		}
	}

	// MARK: - Private

	private func performSearch() {
		guard !searchString.isEmpty else {
			currentMatch = nil
			highlightedRanges = []
			onSearchUpdate?(nil, [])
			return
		}

		let searcher = BufferSearcher(text: bufferText)
		var opts: FindOptions = []
		if ignoreCase { opts.insert(.ignoreCase) }
		if wrapAround { opts.insert(.wrapAround) }

		// Find from anchor
		if let result = try? searcher.findNext(
			pattern: searchString,
			options: opts,
			fromOffset: anchorOffset,
		) {
			currentMatch = result.firstMatch
		} else {
			currentMatch = nil
		}

		// Find all for highlighting
		if let allResult = try? searcher.findAll(
			pattern: searchString,
			options: opts.union(.allMatches),
		) {
			highlightedRanges = allResult.matches.map(\.range)
		} else {
			highlightedRanges = []
		}

		onSearchUpdate?(currentMatch, highlightedRanges)
	}
}
