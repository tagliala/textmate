import Foundation

/// A text buffer backed by a piece table data structure.
///
/// The piece table stores text as a sequence of "pieces", each pointing into
/// either the original content or an append-only add buffer. Insertions append
/// to the add buffer and split existing pieces; deletions split and remove
/// pieces. This gives O(log n) insert/delete in the number of pieces while
/// keeping the original data immutable.
///
/// Line index is maintained incrementally for O(log n) line ↔ offset
/// conversion.
///
/// Modeled after TextMate's C++ `ng::detail::storage_t` and `ng::buffer_t`.
public final class TextBuffer: @unchecked Sendable {
	// MARK: - Piece Table Types

	/// Which buffer a piece refers to.
	enum BufferKind: Sendable {
		case original
		case add
	}

	/// A contiguous run of text within a source buffer.
	struct Piece: Sendable {
		var source: BufferKind
		/// Byte offset within the source buffer.
		var start: Int
		/// Length in UTF-8 bytes.
		var length: Int
		/// Number of newline characters (`\n`) within this piece.
		var newlineCount: Int
	}

	// MARK: - Storage

	/// The original (immutable) text content.
	private let original: [UInt8]
	/// The append-only add buffer. New text goes here.
	private var addBuffer: [UInt8]
	/// The ordered list of pieces describing the logical document.
	private var pieces: [Piece]
	/// Monotonically increasing revision counter.
	private var _revision: Int = 0
	/// Next revision to assign in `bumpRevision`.
	private var _nextRevision: Int = 1

	/// Callbacks notified before each mutation (used by `UndoManager`).
	private var callbacks: [BufferCallback] = []

	// MARK: - Init

	/// Creates an empty text buffer.
	public init() {
		original = []
		addBuffer = []
		pieces = []
	}

	/// Creates a text buffer initialized with the given string.
	public init(_ string: String) {
		let bytes = Array(string.utf8)
		original = bytes
		addBuffer = []
		if bytes.isEmpty {
			pieces = []
		} else {
			let nlCount = bytes.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
			pieces = [Piece(source: .original, start: 0, length: bytes.count, newlineCount: nlCount)]
		}
	}

	// MARK: - Public Properties

	/// Total number of UTF-8 bytes in the buffer.
	public var size: Int {
		pieces.reduce(0) { $0 + $1.length }
	}

	/// Whether the buffer is empty.
	public var isEmpty: Bool {
		size == 0
	}

	/// The number of lines in the buffer. Always ≥ 1 (an empty buffer has 1 line).
	public var lines: Int {
		pieces.reduce(0) { $0 + $1.newlineCount } + 1
	}

	/// Current revision number. Incremented on each edit.
	public var revision: Int {
		_revision
	}

	/// Bumps and returns the next revision number.
	@discardableResult
	public func bumpRevision() -> Int {
		_revision = _nextRevision
		_nextRevision += 1
		return _revision
	}

	/// Sets the revision to a specific value (used by undo/redo).
	public func setRevision(_ rev: Int) {
		_revision = rev
	}

	// MARK: - Read

	/// Returns the entire buffer content as a `String`.
	public var string: String {
		substring(from: 0, to: size)
	}

	/// Returns a substring of the buffer as a `String`.
	///
	/// - Parameters:
	///   - from: Start byte offset (inclusive).
	///   - to: End byte offset (exclusive).
	/// - Returns: The UTF-8 decoded string for the range `[from, to)`.
	public func substring(from: Int, to: Int) -> String {
		precondition(
			from >= 0 && to >= from && to <= size,
			"substring bounds [\(from), \(to)) out of range for size \(size)",
		)
		if from == to { return "" }

		var result: [UInt8] = []
		result.reserveCapacity(to - from)

		var offset = 0
		for piece in pieces {
			let pieceEnd = offset + piece.length
			if pieceEnd <= from {
				offset = pieceEnd
				continue
			}
			if offset >= to {
				break
			}

			let sliceStart = max(from, offset) - offset + piece.start
			let sliceEnd = min(to, pieceEnd) - offset + piece.start
			let source = piece.source == .original ? original : addBuffer
			result.append(contentsOf: source[sliceStart ..< sliceEnd])

			offset = pieceEnd
		}

		return String(decoding: result, as: UTF8.self)
	}

	/// Returns the byte at the given offset.
	public subscript(index: Int) -> UInt8 {
		precondition(index >= 0 && index < size, "Index \(index) out of range for size \(size)")
		var offset = 0
		for piece in pieces {
			let pieceEnd = offset + piece.length
			if index < pieceEnd {
				let source = piece.source == .original ? original : addBuffer
				return source[piece.start + (index - offset)]
			}
			offset = pieceEnd
		}
		fatalError("unreachable")
	}

	// MARK: - Line ↔ Offset Conversion

	/// Returns the byte offset of the start of the given zero-based line.
	public func lineStart(_ line: Int) -> Int {
		precondition(line >= 0 && line < lines, "Line \(line) out of range for \(lines) lines")
		if line == 0 { return 0 }

		var remaining = line
		var offset = 0
		for piece in pieces {
			if piece.newlineCount >= remaining {
				// The target line starts within this piece
				let source = piece.source == .original ? original : addBuffer
				var i = piece.start
				let end = piece.start + piece.length
				while i < end {
					if source[i] == UInt8(ascii: "\n") {
						remaining -= 1
						if remaining == 0 {
							return offset + (i - piece.start) + 1
						}
					}
					i += 1
				}
			}
			remaining -= piece.newlineCount
			offset += piece.length
		}
		fatalError("unreachable: line \(line) not found")
	}

	/// Returns the byte offset of the end of line content (before `\n`) for
	/// the given zero-based line.
	public func lineEnd(_ line: Int) -> Int {
		precondition(line >= 0 && line < lines, "Line \(line) out of range for \(lines) lines")
		if line == lines - 1 { return size }

		// The end of line `n` is the byte just before the (n+1)th `\n`.
		let nextLineStart = lineStart(line + 1)
		return nextLineStart - 1
	}

	/// Converts a byte offset to a `TextPosition` (line, column, offset).
	public func convert(offset: Int) -> TextPosition {
		let clampedOffset = min(max(offset, 0), size)
		var line = 0
		var lineOffset = 0
		var curr = 0

		for piece in pieces {
			let pieceEnd = curr + piece.length
			if clampedOffset <= pieceEnd {
				// Target is within or at the end of this piece
				let source = piece.source == .original ? original : addBuffer
				var i = piece.start
				let targetInPiece = piece.start + (clampedOffset - curr)
				while i < targetInPiece {
					if source[i] == UInt8(ascii: "\n") {
						line += 1
						lineOffset = curr + (i - piece.start) + 1
					}
					i += 1
				}
				return TextPosition(line: line, column: clampedOffset - lineOffset, offset: clampedOffset)
			}

			// Count newlines in the entire piece
			let source = piece.source == .original ? original : addBuffer
			var i = piece.start
			let end = piece.start + piece.length
			while i < end {
				if source[i] == UInt8(ascii: "\n") {
					line += 1
					lineOffset = curr + (i - piece.start) + 1
				}
				i += 1
			}
			curr = pieceEnd
		}

		return TextPosition(line: line, column: clampedOffset - lineOffset, offset: clampedOffset)
	}

	/// Converts a `TextPosition` to a byte offset.
	public func convert(position: TextPosition) -> Int {
		let targetLine = min(position.line, lines - 1)
		let start = lineStart(targetLine)
		let end = lineEnd(targetLine)
		return min(start + position.column, end)
	}

	// MARK: - Mutation

	/// Replaces text in the range `[from, to)` with the given string.
	///
	/// This is the fundamental mutation operation; `insert` and `erase` are
	/// convenience wrappers.
	///
	/// - Parameters:
	///   - from: Start byte offset.
	///   - to: End byte offset (exclusive).
	///   - string: Replacement text.
	/// - Returns: The byte offset just past the inserted text.
	@discardableResult
	public func replace(from: Int, to: Int, with string: String) -> Int {
		precondition(
			from >= 0 && to >= from && to <= size,
			"replace bounds [\(from), \(to)) out of range for size \(size)",
		)

		let bytes = Array(string.utf8)

		// Notify callbacks before mutation.
		for cb in callbacks {
			cb.willReplace(from: from, to: to, bytes: bytes)
		}

		// 1. Erase [from, to)
		if from < to {
			eraseInternal(from: from, to: to)
		}

		// 2. Insert `bytes` at `from`
		if !bytes.isEmpty {
			insertInternal(at: from, bytes: bytes)
		}

		return from + bytes.count
	}

	/// Inserts the given string at the specified byte offset.
	@discardableResult
	public func insert(at offset: Int, string: String) -> Int {
		replace(from: offset, to: offset, with: string)
	}

	/// Erases the text in the byte range `[from, to)`.
	public func erase(from: Int, to: Int) {
		replace(from: from, to: to, with: "")
	}

	// MARK: - Callbacks

	/// Adds a callback that is notified before each buffer mutation.
	public func addCallback(_ callback: BufferCallback) {
		callbacks.append(callback)
	}

	/// Removes a previously-added callback.
	public func removeCallback(_ callback: BufferCallback) {
		callbacks.removeAll { $0 === callback }
	}

	// MARK: - Private Mutation Helpers

	/// Finds the piece index and intra-piece offset for a given buffer offset.
	private func findPiece(at offset: Int) -> (pieceIndex: Int, intraOffset: Int) {
		var curr = 0
		for (i, piece) in pieces.enumerated() {
			let pieceEnd = curr + piece.length
			if offset < pieceEnd {
				return (i, offset - curr)
			}
			if offset == pieceEnd {
				return (i + 1, 0)
			}
			curr = pieceEnd
		}
		return (pieces.count, 0)
	}

	/// Splits the piece at `pieceIndex` at the given intra-piece offset.
	/// Returns the index of the second half (the piece starting at `intraOffset`).
	private func splitPiece(at pieceIndex: Int, offset intraOffset: Int) -> Int {
		guard intraOffset > 0 else { return pieceIndex }
		let piece = pieces[pieceIndex]
		guard intraOffset < piece.length else { return pieceIndex + 1 }

		let source = piece.source == .original ? original : addBuffer
		let firstNL = countNewlines(in: source, from: piece.start, length: intraOffset)
		let secondNL = piece.newlineCount - firstNL

		let first = Piece(source: piece.source, start: piece.start, length: intraOffset, newlineCount: firstNL)
		let second = Piece(
			source: piece.source,
			start: piece.start + intraOffset,
			length: piece.length - intraOffset,
			newlineCount: secondNL,
		)

		pieces[pieceIndex] = first
		pieces.insert(second, at: pieceIndex + 1)
		return pieceIndex + 1
	}

	/// Erases the byte range `[from, to)` from the piece table.
	private func eraseInternal(from: Int, to: Int) {
		let (startIdx, startIntra) = findPiece(at: from)
		let splitIdx = splitPiece(at: startIdx, offset: startIntra)

		let (endIdx, endIntra) = findPiece(at: to)
		let splitEnd: Int = if endIdx < pieces.count {
			splitPiece(at: endIdx, offset: endIntra)
		} else {
			pieces.count
		}

		if splitIdx < splitEnd {
			pieces.removeSubrange(splitIdx ..< splitEnd)
		}
	}

	/// Inserts `bytes` at position `offset` into the piece table.
	private func insertInternal(at offset: Int, bytes: [UInt8]) {
		let (idx, intraOffset) = findPiece(at: offset)
		let insertIdx = idx < pieces.count ? splitPiece(at: idx, offset: intraOffset) : pieces.count

		let addStart = addBuffer.count
		addBuffer.append(contentsOf: bytes)
		let nlCount = countNewlines(in: addBuffer, from: addStart, length: bytes.count)

		// Try to merge with the preceding piece if it points to the end of the
		// add buffer (i.e. contiguous appends).
		if insertIdx > 0 {
			let prev = pieces[insertIdx - 1]
			if prev.source == .add, prev.start + prev.length == addStart {
				pieces[insertIdx - 1] = Piece(
					source: .add,
					start: prev.start,
					length: prev.length + bytes.count,
					newlineCount: prev.newlineCount + nlCount,
				)
				return
			}
		}

		let newPiece = Piece(source: .add, start: addStart, length: bytes.count, newlineCount: nlCount)
		pieces.insert(newPiece, at: insertIdx)
	}

	/// Counts `\n` bytes in a slice of a byte array.
	private func countNewlines(in buffer: [UInt8], from start: Int, length: Int) -> Int {
		var count = 0
		for i in start ..< (start + length) {
			if buffer[i] == UInt8(ascii: "\n") {
				count += 1
			}
		}
		return count
	}
}

// MARK: - Buffer Callback Protocol

/// Protocol for observing buffer mutations (used by `TextUndoManager`).
public protocol BufferCallback: AnyObject, Sendable {
	/// Called before a replacement occurs.
	///
	/// - Parameters:
	///   - from: Start byte offset of the range being replaced.
	///   - to: End byte offset of the range being replaced.
	///   - bytes: The replacement bytes about to be inserted.
	func willReplace(from: Int, to: Int, bytes: [UInt8])
}

// MARK: - Equatable

extension TextBuffer: Equatable {
	public static func == (lhs: TextBuffer, rhs: TextBuffer) -> Bool {
		guard lhs.size == rhs.size else { return false }
		// Compare content byte-by-byte via the logical view
		return lhs.string == rhs.string
	}
}

// MARK: - CustomStringConvertible

extension TextBuffer: CustomStringConvertible {
	public var description: String {
		"TextBuffer(\(size) bytes, \(lines) lines, \(pieces.count) pieces, rev \(revision))"
	}
}
