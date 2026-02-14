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

		public init(snippetText: String, tabStops: [TabStop], currentTabStopIndex: Int = 0) {
			self.snippetText = snippetText
			self.tabStops = tabStops
			self.currentTabStopIndex = currentTabStopIndex
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
			return sessions.last?.currentTabStop?.range
		}

		// If we hit the exit tab stop (index 0, typically last), pop after returning its range.
		if let stop = sessions.last?.currentTabStop, stop.index == 0 {
			let range = stop.range
			sessions.removeLast()
			return range
		}

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

		return sessions.last?.currentTabStop?.range
	}

	/// Replaces the text at the current tab stop.
	///
	/// - Parameter text: The replacement text.
	public func replaceCurrentTabStop(with _: String) {
		// In a full implementation this would update mirror tab stops, etc.
		// For now this is a stub — the editor handles the actual buffer edit.
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
