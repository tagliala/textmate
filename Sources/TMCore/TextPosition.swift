/// A position within a text buffer, identified by line and column.
///
/// Positions are zero-indexed for both line and column. The `offset` represents
/// the absolute UTF-8 byte offset from the start of the buffer.
public struct TextPosition: Sendable, Hashable, Comparable {
	/// Zero-based line number.
	public var line: Int

	/// Zero-based column offset within the line (in UTF-8 code units).
	public var column: Int

	/// Absolute byte offset from the beginning of the buffer.
	public var offset: Int

	public init(line: Int, column: Int, offset: Int) {
		self.line = line
		self.column = column
		self.offset = offset
	}

	/// The position at the very start of a buffer.
	public static let zero = TextPosition(line: 0, column: 0, offset: 0)

	public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
		lhs.offset < rhs.offset
	}
}
