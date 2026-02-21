import TMCore

/// Manages active snippet sessions with tab stop navigation.
///
/// The snippet controller maintains a stack of active snippets. Each snippet
/// has numbered tab stops ($1, $2, ... $0) through which the user navigates
/// with Tab/Shift-Tab. When the last tab stop ($0) is reached, the snippet
/// session ends.
///
/// Modeled after TextMate's C++ `snippet_controller_t`.
public final class SnippetController: @unchecked Sendable {
	// MARK: - Types

	/// A single tab stop within a snippet.
	public struct TabStop: Sendable {
		/// The tab stop index (1-based; 0 means final/exit tab stop).
		public let index: Int

		/// The range this tab stop occupies in the buffer.
		public var range: TextRange

		/// Placeholder text for this tab stop.
		public let placeholder: String

		/// Available choices for this tab stop (e.g., from `${1|one,two,three|}`).
		public let choices: [String]

		public init(
			index: Int,
			range: TextRange,
			placeholder: String = "",
			choices: [String] = [],
		) {
			self.index = index
			self.range = range
			self.placeholder = placeholder
			self.choices = choices
		}
	}

	/// A single active snippet session.
	public struct Session: Sendable {
		/// The snippet text that was inserted.
		public let snippetText: String

		/// All tab stops in this snippet, ordered by index.
		public var tabStops: [TabStop]

		/// The index into `tabStops` for the currently active tab stop.
		public var currentTabStopIndex: Int

		/// The base offset in the buffer where this snippet was inserted.
		public var baseOffset: Int

		/// The underlying snippet state for mirror/transform updates.
		/// May be `nil` for snippets without mirrors.
		public nonisolated(unsafe) var snippetState: SnippetState?

		public init(
			snippetText: String,
			tabStops: [TabStop],
			currentTabStopIndex: Int = 0,
			baseOffset: Int = 0,
			snippetState: SnippetState? = nil,
		) {
			self.snippetText = snippetText
			self.tabStops = tabStops
			self.currentTabStopIndex = currentTabStopIndex
			self.baseOffset = baseOffset
			self.snippetState = snippetState
		}

		/// The currently active tab stop.
		public var currentTabStop: TabStop? {
			guard currentTabStopIndex >= 0, currentTabStopIndex < tabStops.count else {
				return nil
			}
			return tabStops[currentTabStopIndex]
		}

		/// Whether the caret is at the last (exit) tab stop.
		public var isAtLastTabStop: Bool {
			guard let current = currentTabStop else { return true }
			return current.index == 0
		}
	}

	// MARK: - State

	/// Stack of active snippet sessions (nested snippets are possible).
	private var sessions: [Session] = []

	public init() {}

	// MARK: - Query

	/// Whether any snippet session is active.
	public var isEmpty: Bool {
		sessions.isEmpty
	}

	/// Whether the active session uses SnippetState for mirror tracking.
	public var hasActiveMirrors: Bool {
		sessions.last?.snippetState != nil
	}

	/// The currently active snippet session.
	public var current: Session? {
		sessions.last
	}

	/// The choices available at the current tab stop, or empty.
	public var choices: [String] {
		current?.currentTabStop?.choices ?? []
	}

	/// Whether the caret is at the last placeholder of the innermost snippet.
	public var isAtLastPlaceholder: Bool {
		current?.isAtLastTabStop ?? true
	}

	// MARK: - Navigation

	/// Pushes a new snippet session onto the stack.
	///
	/// - Parameter session: The snippet session to activate.
	public func push(_ session: Session) {
		sessions.append(session)
		syncStateCurrentField()
	}

	/// Advances to the next tab stop. If at the last tab stop, pops the session.
	///
	/// - Returns: The text range of the new current tab stop, or `nil` if
	///   the snippet session ended.
	@discardableResult
	public func next() -> TextRange? {
		guard !sessions.isEmpty else { return nil }

		sessions[sessions.count - 1].currentTabStopIndex += 1

		// If we've gone past all tab stops, the session is done.
		if sessions[sessions.count - 1].currentTabStopIndex >= sessions[sessions.count - 1].tabStops.count {
			sessions.removeLast()
			syncStateCurrentField()
			return sessions.last?.currentTabStop?.range
		}

		// If we hit the exit tab stop (index 0, typically last), pop after returning its range.
		if let stop = sessions.last?.currentTabStop, stop.index == 0 {
			let range = stop.range
			sessions.removeLast()
			syncStateCurrentField()
			return range
		}

		syncStateCurrentField()
		return sessions.last?.currentTabStop?.range
	}

	/// Goes back to the previous tab stop.
	///
	/// - Returns: The text range of the new current tab stop, or `nil`.
	@discardableResult
	public func previous() -> TextRange? {
		guard !sessions.isEmpty else { return nil }

		if sessions[sessions.count - 1].currentTabStopIndex > 0 {
			sessions[sessions.count - 1].currentTabStopIndex -= 1
		}

		syncStateCurrentField()
		return sessions.last?.currentTabStop?.range
	}

	/// Keeps `SnippetState.currentField` in sync with the active tab stop index.
	private func syncStateCurrentField() {
		guard let session = sessions.last,
		      let state = session.snippetState,
		      let tabStop = session.currentTabStop
		else { return }
		state.currentField = tabStop.index
	}

	/// A mirror replacement to be applied to the buffer.
	public struct MirrorUpdate: Sendable {
		/// Byte offset range in the buffer.
		public let from: Int
		public let to: Int
		/// Text to insert at the range.
		public let text: String
	}

	/// Replaces the current field content in the snippet state and returns mirror updates.
	///
	/// The caller should pass the full new content of the current tab stop as read
	/// from the buffer. This replaces the entire current field range in `SnippetState`,
	/// which cascades to mirrors. Returns mirror updates with buffer-adjusted ranges
	/// and new text, sorted from end to start so the caller can apply them without
	/// offset invalidation.
	///
	/// - Parameter newContent: The full text now at the current tab stop.
	/// - Returns: Mirror updates to apply to the buffer, sorted end-to-start.
	public func replaceCurrentField(with newContent: String) -> [MirrorUpdate] {
		guard !sessions.isEmpty else { return [] }
		let session = sessions[sessions.count - 1]
		guard let state = session.snippetState else { return [] }
		let base = session.baseOffset

		// Sync SnippetState's currentField to match our tab stop index.
		if let tabStop = session.currentTabStop {
			state.currentField = tabStop.index
		}

		guard let fieldRange = state.currentRange else { return [] }

		// Compute the delta between the buffer (already edited) and the state (not yet).
		// The primary edit replaced fieldRange with newContent in the buffer,
		// so positions after the field are shifted by this delta.
		let primaryDelta = newContent.utf8.count - fieldRange.size
		let fieldEnd = fieldRange.to.offset

		// Capture pre-replacement mirror ranges (in snippet-local coords)
		// and adjust them by the primary edit delta to match buffer positions.
		// Skip mirrors inside the current field (they'll be removed by replace()).
		var preMirrorRanges: [(index: Int, bufFrom: Int, bufTo: Int)] = []
		for (mirrorIdx, mirror) in state.mirrors {
			if fieldRange.contains(mirror.range.from) || fieldRange.contains(mirror.range.to) {
				continue
			}
			var from = mirror.range.from.offset
			var to = mirror.range.to.offset
			// If the mirror is after the field edit, adjust for primary delta.
			if from >= fieldEnd {
				from += primaryDelta
				to += primaryDelta
			}
			preMirrorRanges.append((
				index: mirrorIdx,
				bufFrom: base + from,
				bufTo: base + to,
			))
		}

		// Replace the entire current field with the new content.
		// This updates state.text and cascades to mirrors.
		_ = state.replace(range: fieldRange, with: newContent)

		// Collect the new mirror text from the updated state.
		var postMirrorText: [Int: [String]] = [:]
		for (mirrorIdx, mirror) in state.mirrors {
			postMirrorText[mirrorIdx, default: []].append(mirror.range.substring(of: state.text))
		}

		// Match pre-replacement buffer ranges with post-replacement text.
		var result: [MirrorUpdate] = []
		var textIndexByMirror: [Int: Int] = [:]
		for pre in preMirrorRanges {
			let idx = textIndexByMirror[pre.index, default: 0]
			if let texts = postMirrorText[pre.index], idx < texts.count {
				result.append(MirrorUpdate(from: pre.bufFrom, to: pre.bufTo, text: texts[idx]))
				textIndexByMirror[pre.index] = idx + 1
			}
		}

		// Sort from end to start so applying them doesn't invalidate offsets.
		result.sort { $0.from > $1.from }

		// Note: caller must call refreshTabStops() after applying mirror updates to the buffer.
		return result
	}

	/// Refreshes all tab stop ranges from the underlying SnippetState.
	///
	/// Call this after applying mirror updates to the buffer so that
	/// tab stop ranges match the final buffer state.
	public func refreshTabStops() {
		refreshTabStopsFromState()
	}

	/// Updates a single tab stop range in the current session.
	public func updateTabStopRange(at index: Int, to range: TextRange) {
		guard !sessions.isEmpty,
		      index >= 0,
		      index < sessions[sessions.count - 1].tabStops.count
		else { return }
		sessions[sessions.count - 1].tabStops[index].range = range
	}

	/// Refreshes tab stop ranges from the underlying SnippetState.
	private func refreshTabStopsFromState() {
		guard !sessions.isEmpty else { return }
		let session = sessions[sessions.count - 1]
		guard let state = session.snippetState else { return }
		let base = session.baseOffset

		for stopIdx in sessions[sessions.count - 1].tabStops.indices {
			let tabStop = sessions[sessions.count - 1].tabStops[stopIdx]
			if let field = state.fields[tabStop.index] {
				let startOff = base + field.range.from.offset
				let endOff = base + field.range.to.offset
				sessions[sessions.count - 1].tabStops[stopIdx].range = TextRange(
					anchor: TextPosition(line: 0, column: 0, offset: startOff),
					head: TextPosition(line: 0, column: 0, offset: endOff),
				)
			}
		}
	}

	/// Clears all active snippet sessions.
	public func clear() {
		sessions.removeAll()
	}

	// MARK: - Buffer Update Support

	/// Updates tab stop ranges after a buffer edit.
	///
	/// When text is inserted or deleted, tab stop ranges that come after the
	/// edit point must be adjusted.
	///
	/// - Parameters:
	///   - offset: The byte offset where the edit occurred.
	///   - oldLength: Number of bytes removed.
	///   - newLength: Number of bytes inserted.
	public func adjustForEdit(at offset: Int, oldLength: Int, newLength: Int) {
		let delta = newLength - oldLength

		for sessionIdx in sessions.indices {
			for stopIdx in sessions[sessionIdx].tabStops.indices {
				var stop = sessions[sessionIdx].tabStops[stopIdx]
				let range = stop.range

				// If the edit is entirely before this tab stop, shift it.
				if offset + oldLength <= range.start.offset {
					let newStartOffset = range.start.offset + delta
					let newEndOffset = range.end.offset + delta
					stop.range = TextRange(
						anchor: TextPosition(
							line: range.anchor.line,
							column: range.anchor.column,
							offset: range.anchor == range.start ? newStartOffset : newEndOffset,
						),
						head: TextPosition(
							line: range.head.line,
							column: range.head.column,
							offset: range.head == range.start ? newStartOffset : newEndOffset,
						),
					)
					sessions[sessionIdx].tabStops[stopIdx] = stop
				}
				// If the edit is within this tab stop, expand/shrink it.
				else if offset >= range.start.offset, offset <= range.end.offset {
					let newEndOffset = range.end.offset + delta
					stop.range = TextRange(
						anchor: range.anchor,
						head: TextPosition(
							line: range.head.line,
							column: range.head.column,
							offset: range.head == range.end ? newEndOffset : range.head.offset,
						),
					)
					sessions[sessionIdx].tabStops[stopIdx] = stop
				}
			}
		}
	}
}
