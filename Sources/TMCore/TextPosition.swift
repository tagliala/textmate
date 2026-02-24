/// A position within a text buffer, identified by line and column.
///
/// Positions are zero-indexed for both line and column. The `offset` represents
/// the absolute UTF-8 byte offset from the start of the buffer.
///
/// The `carry` field is a virtual column offset past the end of a line.
/// It is used to preserve the cursor's visual column during vertical movement
/// when the target line is shorter than the originating line.  This mirrors
/// `ng::index_t::carry` from the C++ editor.
public struct TextPosition: Sendable, Hashable, Comparable {
	/// Zero-based line number.
	public var line: Int

	/// Zero-based column offset within the line (in UTF-8 code units).
	public var column: Int

	/// Absolute byte offset from the beginning of the buffer.
	public var offset: Int

	/// Virtual column offset past the end of line.
	///
	/// A non-zero carry means the cursor is positioned beyond the line's
	/// last character (e.g. during up/down movement when the previous line
	/// was longer).  Most operations should clamp carry to zero before
	/// editing.
	public var carry: Int

	public init(line: Int, column: Int, offset: Int, carry: Int = 0) {
		self.line = line
		self.column = column
		self.offset = offset
		self.carry = carry
	}

	/// The position at the very start of a buffer.
	public static let zero = TextPosition(line: 0, column: 0, offset: 0)

	public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
		if lhs.offset != rhs.offset {
			return lhs.offset < rhs.offset
		}
		return lhs.carry < rhs.carry
	}
}
