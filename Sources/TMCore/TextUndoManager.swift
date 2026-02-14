import Foundation

/// An undo/redo manager for `TextBuffer` that supports edit coalescing.
///
/// Coalescing merges consecutive similar edits into a single undo step.
/// For example, typing several characters in a row produces one undo step
/// rather than one per character. A whitespace-only edit will not merge
/// with a non-whitespace edit, and an insertion will not merge with a
/// deletion.
///
/// Modeled after TextMate's C++ `ng::undo_manager_t`.
public final class TextUndoManager: @unchecked Sendable {
	// MARK: - Record

	/// A single atomic edit recorded for undo/redo.
	struct Record {
		/// Byte offset where the edit occurred.
		var offset: Int
		/// The text that was at `[offset, offset+before.count)` before the edit.
		var before: [UInt8]
		/// The text that replaced `before` after the edit.
		var after: [UInt8]

		/// The selection state before this record's undo group began.
		var preSelection: SelectionState?
		/// The buffer revision before this record's undo group began.
		var preRevision: Int

		/// The selection state after this record's undo group ended.
		var postSelection: SelectionState?
		/// The buffer revision after this record's undo group ended.
		var postRevision: Int = 0
	}

	// MARK: - Storage

	/// The buffer this undo manager observes.
	private let buffer: TextBuffer
	/// Internal callback that captures `willReplace` from the buffer.
	private let observer: Observer
	/// The undo/redo record stack.
	private var records: [Record] = []
	/// Index into `records` — records `[0..<index]` are undo-able,
	/// `[index..<count]` are redo-able.
	private var index: Int = 0

	/// Undo-group nesting depth.
	private var nestingCount: Int = 0
	/// Selection state captured at `beginUndoGroup`.
	private var preSelection: SelectionState?
	/// Buffer revision captured at `beginUndoGroup`.
	private var preRevision: Int = 0
	/// Number of `willReplace` calls within the current undo group.
	private var changeCount: Int = 0

	// MARK: - Init

	/// Creates an undo manager attached to the given buffer.
	public init(buffer: TextBuffer) {
		self.buffer = buffer
		observer = Observer()
		observer.owner = self
		buffer.addCallback(observer)
	}

	deinit {
		buffer.removeCallback(observer)
	}

	// MARK: - Public API

	/// Whether there are any actions that can be undone.
	public var canUndo: Bool {
		index != 0
	}

	/// Whether there are any actions that can be redone.
	public var canRedo: Bool {
		index != records.count
	}

	/// Whether we are currently inside an undo group.
	public var inUndoGroup: Bool {
		nestingCount != 0
	}

	/// Begins an undo group. Multiple calls nest; the group is only finalized
	/// when the outermost `endUndoGroup` is called.
	///
	/// - Parameter selections: The current selection state (saved as the
	///   "before" state for this undo group).
	public func beginUndoGroup(selections: SelectionState? = nil) {
		nestingCount += 1
		if nestingCount == 1 {
			preSelection = selections
			preRevision = buffer.revision
			changeCount = 0
		}
	}

	/// Ends the current undo group.
	///
	/// - Parameters:
	///   - selections: The current selection state (saved as the "after" state).
	///   - force: If `true`, ends the group even if nesting count > 1.
	public func endUndoGroup(selections: SelectionState? = nil, force: Bool = false) {
		nestingCount -= 1
		if nestingCount == 0 || force, changeCount > 0 {
			records[index - 1].postSelection = selections
			records[index - 1].postRevision = buffer.bumpRevision()
			changeCount = 0
		}
	}

	/// Undoes the last edit group, returning the selection state to restore.
	///
	/// Records without `preSelection` are part of the same undo group and
	/// are undone together.
	@discardableResult
	public func undo() -> SelectionState? {
		precondition(canUndo, "Nothing to undo")

		buffer.removeCallback(observer)
		defer { buffer.addCallback(observer)
			changeCount = 0
		}

		var result: SelectionState?
		var rev = 0

		repeat {
			precondition(index > 0)
			index -= 1
			let r = records[index]
			let afterLen = r.after.count
			let beforeStr = String(decoding: r.before, as: UTF8.self)
			buffer.replace(from: r.offset, to: r.offset + afterLen, with: beforeStr)
			if let sel = r.preSelection {
				result = sel
				rev = r.preRevision
			}
		} while result == nil

		buffer.setRevision(rev)
		return result
	}

	/// Redoes the next edit group, returning the selection state to restore.
	@discardableResult
	public func redo() -> SelectionState? {
		precondition(canRedo, "Nothing to redo")

		buffer.removeCallback(observer)
		defer { buffer.addCallback(observer)
			changeCount = 0
		}

		var result: SelectionState?
		var rev = 0

		repeat {
			precondition(index < records.count)
			let r = records[index]
			let beforeLen = r.before.count
			let afterStr = String(decoding: r.after, as: UTF8.self)
			buffer.replace(from: r.offset, to: r.offset + beforeLen, with: afterStr)
			if let sel = r.postSelection {
				result = sel
				rev = r.postRevision
			}
			index += 1
		} while result == nil

		buffer.setRevision(rev)
		return result
	}

	// MARK: - Coalescing

	/// Determines whether two consecutive records should be merged into one
	/// undo step. Records merge when they are the same kind (both inserts or
	/// both deletes) and both are either all-whitespace or all-non-whitespace.
	private func shouldMerge(_ r: Record, _ t: Record) -> Bool {
		let rIsInsert = r.before.isEmpty && !r.after.isEmpty
		let rIsErase = !r.before.isEmpty && r.after.isEmpty
		let tIsInsert = t.before.isEmpty && !t.after.isEmpty
		let tIsErase = !t.before.isEmpty && t.after.isEmpty

		// Must be the same kind of operation.
		if rIsInsert != tIsInsert || rIsErase != tIsErase {
			return false
		}

		let rText = rIsInsert ? r.after : r.before
		let tText = tIsInsert ? t.after : t.before

		let rAllWhitespace = rText.allSatisfy { isWhitespace($0) }
		let rNoWhitespace = !rText.contains(where: { isWhitespace($0) })
		let tAllWhitespace = tText.allSatisfy { isWhitespace($0) }
		let tNoWhitespace = !tText.contains(where: { isWhitespace($0) })

		return (rAllWhitespace || rNoWhitespace) &&
			rAllWhitespace == tAllWhitespace &&
			rNoWhitespace == tNoWhitespace
	}

	private func isWhitespace(_ byte: UInt8) -> Bool {
		byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\t")
	}

	// MARK: - Buffer Callback

	/// Called by the buffer before each `replace` to record the edit.
	fileprivate func willReplace(from: Int, to: Int, bytes: [UInt8]) {
		// Discard any redo history beyond current index.
		if index < records.count {
			records.removeSubrange(index ..< records.count)
		}

		let before: [UInt8]
		if from < to {
			let beforeStr = buffer.substring(from: from, to: to)
			before = Array(beforeStr.utf8)
		} else {
			before = []
		}

		records.append(Record(
			offset: from,
			before: before,
			after: bytes,
			preSelection: preSelection,
			preRevision: preRevision,
		))
		preSelection = nil
		changeCount += 1
		index += 1
	}

	// MARK: - Observer

	/// Internal `BufferCallback` implementation.
	private final class Observer: BufferCallback, @unchecked Sendable {
		weak var owner: TextUndoManager?
		func willReplace(from: Int, to: Int, bytes: [UInt8]) {
			owner?.willReplace(from: from, to: to, bytes: bytes)
		}
	}
}
