#if canImport(AppKit)
import TMCore
import TMSearchReplace

// MARK: - Find & Replace Operations

public extension TMDocumentEditor {
	/// Captures from the most recent regex find (for replacement expansion).
	private(set) var matchCaptures: [String: String] {
		get { _matchCaptures }
		set { _matchCaptures = newValue }
	}

	/// Performs find next from the current selection.
	///
	/// - Parameters:
	///   - pattern: The search pattern.
	///   - options: Search options.
	/// - Returns: a tuple `(count, line, column, wrapped)` for status reporting.
	func findNext(
		pattern: String,
		options: FindOptions,
	) -> (count: Int, line: Int, column: Int, wrapped: Bool) {
		let text = editor.text
		guard !pattern.isEmpty, !text.isEmpty else {
			return (0, 0, 0, false)
		}

		let searcher = BufferSearcher(text: text)
		let caretOffset = editor.selections.primary?.end.offset ?? 0

		guard let result = try? searcher.findNext(
			pattern: pattern,
			options: options,
			fromOffset: caretOffset,
		) else {
			return (0, 0, 0, false)
		}

		guard let match = result.firstMatch else {
			return (0, 0, 0, false)
		}

		_matchCaptures = match.captures
		selectMatch(match)

		let pos = editor.buffer.convert(offset: match.range.lowerBound)
		return (1, pos.line, pos.column, result.didWrap)
	}

	/// Performs find all and selects all matches.
	///
	/// - Parameters:
	///   - pattern: The search pattern.
	///   - options: Search options.
	///   - inSelection: Whether to search only within current selections.
	/// - Returns: The number of matches found.
	func findAll(
		pattern: String,
		options: FindOptions,
		inSelection: Bool = false,
	) -> Int {
		let text = editor.text
		guard !pattern.isEmpty, !text.isEmpty else { return 0 }

		let searcher = BufferSearcher(text: text)
		_matchCaptures = [:]

		if inSelection {
			var allRanges: [TMCore.TextRange] = []
			for sel in editor.selections.selections {
				let searchRange = sel.start.offset ..< sel.end.offset
				guard let result = try? searcher.findAll(
					pattern: pattern,
					options: options,
					searchRange: searchRange,
				) else { continue }
				for match in result.matches {
					allRanges.append(textRange(from: match))
				}
			}
			if !allRanges.isEmpty {
				editor.selections = SelectionState(allRanges)
				syncSelectionToView()
			}
			return allRanges.count
		} else {
			guard let result = try? searcher.findAll(
				pattern: pattern,
				options: options,
			) else { return 0 }
			let ranges = result.matches.map { textRange(from: $0) }
			if !ranges.isEmpty {
				editor.selections = SelectionState(ranges)
				syncSelectionToView()
			}
			return ranges.count
		}
	}

	/// Returns the total number of matches without altering selection.
	func countMatches(
		pattern: String,
		options: FindOptions,
	) -> Int {
		let searcher = BufferSearcher(text: editor.text)
		return (try? searcher.countMatches(pattern: pattern, options: options)) ?? 0
	}

	/// Replaces the current selection using capture-aware expansion.
	func replaceCurrent(with replacement: String) {
		guard editor.hasSelection else { return }
		let expanded: String
		if !_matchCaptures.isEmpty {
			let template = ReplacementTemplate(replacement)
			expanded = template.expand(with: _matchCaptures)
		} else {
			expanded = replacement
		}
		beginChangeGrouping()
		editor.insertText(expanded)
		endChangeGrouping()
		_matchCaptures = [:]
		syncAfterEdit()
	}

	/// Replaces all matches and returns the count of replacements.
	func replaceAll(
		pattern: String,
		replacement: String,
		options: FindOptions,
		inSelection: Bool = false,
	) -> Int {
		let text = editor.text
		guard !pattern.isEmpty, !text.isEmpty else { return 0 }

		let searcher = BufferSearcher(text: text)
		beginChangeGrouping()

		if inSelection {
			var total = 0
			let sels = editor.selections.selections.sorted { $0.start.offset > $1.start.offset }
			for sel in sels {
				let searchRange = sel.start.offset ..< sel.end.offset
				let selText = editor.buffer.substring(from: sel.start.offset, to: sel.end.offset)
				let selSearcher = BufferSearcher(text: selText)
				guard let result = try? selSearcher.replaceAll(
					pattern: pattern,
					replacement: replacement,
					options: options,
				), result.count > 0 else { continue }
				editor.buffer.replace(from: searchRange.lowerBound, to: searchRange.upperBound, with: result.text)
				total += result.count
			}
			endChangeGrouping()
			if total > 0 { syncAfterEdit() }
			return total
		} else {
			guard let result = try? searcher.replaceAll(
				pattern: pattern,
				replacement: replacement,
				options: options,
			), result.count > 0 else {
				endChangeGrouping()
				return 0
			}
			editor.buffer.replace(from: 0, to: editor.buffer.size, with: result.text)
			editor.selections = SelectionState(caret: TextPosition.zero)
			endChangeGrouping()
			syncAfterEdit()
			return result.count
		}
	}

	/// Returns all match byte ranges for highlighting (without changing selection).
	func allMatchRanges(
		pattern: String,
		options: FindOptions,
	) -> [Range<Int>] {
		let searcher = BufferSearcher(text: editor.text)
		guard let result = try? searcher.findAll(pattern: pattern, options: options) else {
			return []
		}
		return result.matches.map(\.range)
	}

	// MARK: - Private Helpers

	private func selectMatch(_ match: FindMatch) {
		let range = textRange(from: match)
		editor.selections = SelectionState([range])
		syncSelectionToView()
	}

	private func textRange(from match: FindMatch) -> TMCore.TextRange {
		let startPos = editor.buffer.convert(offset: min(match.range.lowerBound, editor.buffer.size))
		let endPos = editor.buffer.convert(offset: min(match.range.upperBound, editor.buffer.size))
		return TMCore.TextRange(anchor: startPos, head: endPos)
	}
}

// MARK: - Internal Storage for Match Captures

/// Storage for the match captures, kept as an associated-like property.
/// This avoids adding stored properties in an extension.
extension TMDocumentEditor {
	/// In Swift, extensions cannot add stored properties. Instead, we use
	/// a nonisolated(unsafe) static dictionary keyed by ObjectIdentifier.
	/// This is safe because TMDocumentEditor is @MainActor.
	private nonisolated(unsafe) static var captureStorage: [ObjectIdentifier: [String: String]] = [:]

	var _matchCaptures: [String: String] {
		get { Self.captureStorage[ObjectIdentifier(self)] ?? [:] }
		set { Self.captureStorage[ObjectIdentifier(self)] = newValue }
	}
}

#endif
