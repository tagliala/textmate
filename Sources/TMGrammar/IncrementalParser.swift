import Foundation

/// Manages incremental parsing of a document using TextMate grammars.
///
/// Tracks dirty regions and re-parses only the lines that need updating.
/// Parsing stops early when the parser state at a line boundary converges
/// with the previously stored state (i.e., no further lines are affected).
///
/// Mirrors C++ `buffer_parser_t` from `Frameworks/buffer/src/parsing.cc`.
public final class IncrementalParser: @unchecked Sendable {
	/// The compiled root grammar rule.
	public let grammar: GrammarRule

	/// Per-line parser state (state at the *end* of each line).
	private var lineStates: [ParserState] = []

	/// Per-line scope maps (byte offset → Scope).
	private var lineScopeMaps: [[Int: Scope]] = []

	/// Lines that need re-parsing (sorted, unique).
	private var dirtyLines: IndexSet = .init()

	/// The text lines of the document.
	private var lines: [String] = []

	/// Lock for thread safety.
	private let lock = NSLock()

	/// Creates a parser for the given grammar.
	public init(grammar: GrammarRule) {
		self.grammar = grammar
	}

	// MARK: - Document Management

	/// Sets the entire document text, triggering a full parse.
	public func setText(_ text: String) {
		lock.lock()
		defer { lock.unlock() }

		lines = text.components(separatedBy: "\n").enumerated().map { i, line in
			i < text.components(separatedBy: "\n").count - 1 ? line + "\n" : line
		}
		// Remove trailing empty line if it resulted from a trailing newline
		if lines.last == "", text.hasSuffix("\n") {
			lines.removeLast()
		}

		lineStates = []
		lineScopeMaps = []
		dirtyLines = IndexSet(integersIn: 0 ..< lines.count)
	}

	/// Replaces a range of lines with new content.
	///
	/// - Parameters:
	///   - range: The range of line indices to replace.
	///   - newLines: The replacement lines.
	public func replaceLines(
		in range: Range<Int>,
		with newLines: [String],
	) {
		lock.lock()
		defer { lock.unlock() }

		lines.replaceSubrange(range, with: newLines)

		// Adjust state arrays
		if range.count != newLines.count {
			let delta = newLines.count - range.count
			if delta > 0 {
				let emptyStates = [ParserState?](
					repeating: nil, count: delta,
				)
				lineStates.insert(
					contentsOf: emptyStates.compactMap(\.self),
					at: min(range.lowerBound, lineStates.count),
				)
				lineScopeMaps.insert(
					contentsOf: [[Int: Scope]](
						repeating: [:], count: delta,
					),
					at: min(range.lowerBound, lineScopeMaps.count),
				)
			} else {
				let removeRange = range.lowerBound ..< min(
					range.lowerBound - delta, lineStates.count,
				)
				if !removeRange.isEmpty {
					lineStates.removeSubrange(removeRange)
					lineScopeMaps.removeSubrange(removeRange)
				}
			}
		}

		// Mark affected lines as dirty
		let dirtyStart = range.lowerBound
		let dirtyEnd = min(dirtyStart + newLines.count, lines.count)
		dirtyLines.insert(integersIn: dirtyStart ..< max(dirtyEnd, dirtyStart + 1))
	}

	/// Marks a range of lines as needing re-parsing.
	public func invalidateLines(_ range: Range<Int>) {
		lock.lock()
		defer { lock.unlock() }
		dirtyLines.insert(integersIn: range)
	}

	// MARK: - Parsing

	/// Parses all dirty lines synchronously.
	///
	/// Returns the ranges of lines whose scopes actually changed.
	@discardableResult
	public func parseSync() -> [Range<Int>] {
		lock.lock()
		let dirty = dirtyLines
		lock.unlock()

		guard let firstDirty = dirty.first else { return [] }

		var changedRanges: [Range<Int>] = []
		var lineIndex = firstDirty
		var changeStart = lineIndex

		// Ensure state arrays are large enough
		lock.lock()
		while lineStates.count < lines.count {
			lineStates.append(
				ParserState(rule: grammar, scope: grammar.scopeString ?? ""),
			)
		}
		while lineScopeMaps.count < lines.count {
			lineScopeMaps.append([:])
		}
		lock.unlock()

		while lineIndex < lines.count {
			lock.lock()
			let isDirty = dirtyLines.contains(lineIndex)
			lock.unlock()

			if !isDirty, lineIndex > firstDirty {
				// Not dirty and past the first dirty line — we've converged
				if changeStart < lineIndex {
					changedRanges.append(changeStart ..< lineIndex)
				}
				break
			}

			// Get state from previous line
			let prevState: ParserState
			if lineIndex > 0 {
				lock.lock()
				prevState = lineStates[lineIndex - 1]
				lock.unlock()
			} else {
				prevState = ParserState(
					rule: grammar, scope: grammar.scopeString ?? "",
				)
			}

			let line = lines[lineIndex]
			let (newState, newScopes) = GrammarParser.parseLine(
				line, state: prevState, firstLine: lineIndex == 0,
			)

			lock.lock()
			let oldState = lineStates[lineIndex]
			let stateChanged = !(newState == oldState)

			lineStates[lineIndex] = newState
			lineScopeMaps[lineIndex] = newScopes
			dirtyLines.remove(lineIndex)

			// If state changed, the next line needs re-parsing too
			if stateChanged, lineIndex + 1 < lines.count {
				dirtyLines.insert(lineIndex + 1)
			}
			lock.unlock()

			if !stateChanged, !isDirty {
				// Converged — no more changes propagate
				if changeStart < lineIndex {
					changedRanges.append(changeStart ..< lineIndex)
				}
				changeStart = lineIndex + 1
			}

			lineIndex += 1
		}

		// Handle case where we parsed to end of document
		if changeStart < lineIndex, lineIndex >= lines.count {
			changedRanges.append(changeStart ..< lineIndex)
		}

		return changedRanges
	}

	/// Parses dirty lines asynchronously on a background queue.
	///
	/// - Parameter completion: Called on the main queue with ranges of
	///   lines whose scopes changed.
	public func parseAsync(
		completion: @escaping @Sendable ([Range<Int>]) -> Void,
	) {
		DispatchQueue.global(qos: .userInitiated).async {
			let changes = self.parseSync()
			DispatchQueue.main.async {
				completion(changes)
			}
		}
	}

	// MARK: - Queries

	/// Returns the scope map for a specific line.
	public func scopeMap(forLine line: Int) -> [Int: Scope] {
		lock.lock()
		defer { lock.unlock() }
		guard line < lineScopeMaps.count else { return [:] }
		return lineScopeMaps[line]
	}

	/// Returns the scope at a specific position (line + byte offset).
	public func scope(atLine line: Int, byteOffset: Int) -> Scope {
		let map = scopeMap(forLine: line)
		var bestScope = Scope()

		for (offset, scope) in map.sorted(by: { $0.key < $1.key }) {
			if offset <= byteOffset {
				bestScope = scope
			}
		}

		return bestScope
	}

	/// Returns the parser state at the end of a specific line.
	public func state(afterLine line: Int) -> ParserState? {
		lock.lock()
		defer { lock.unlock() }
		guard line < lineStates.count else { return nil }
		return lineStates[line]
	}

	/// The number of lines in the document.
	public var lineCount: Int {
		lock.lock()
		defer { lock.unlock() }
		return lines.count
	}

	/// Whether there are dirty lines needing parsing.
	public var hasDirtyLines: Bool {
		lock.lock()
		defer { lock.unlock() }
		return !dirtyLines.isEmpty
	}
}
