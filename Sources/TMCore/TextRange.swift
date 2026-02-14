/// A range within a text buffer, defined by an anchor and a head position.
///
/// The anchor is the position where the selection started, and the head is
/// where the caret currently sits. When `anchor == head`, the range represents
/// a caret (zero-width selection).
public struct TextRange: Sendable, Hashable {
	/// The position where the selection was initiated.
	public var anchor: TextPosition

	/// The current caret position (may be before or after anchor).
	public var head: TextPosition

	/// Whether this range represents a columnar (rectangular) selection.
	public var isColumnar: Bool

	public init(anchor: TextPosition, head: TextPosition, isColumnar: Bool = false) {
		self.anchor = anchor
		self.head = head
		self.isColumnar = isColumnar
	}

	/// Creates a caret (zero-width selection) at the given position.
	public init(caret position: TextPosition) {
		self.anchor = position
		self.head = position
		self.isColumnar = false
	}

	/// The earlier of anchor and head.
	public var start: TextPosition {
		min(anchor, head)
	}

	/// The later of anchor and head.
	public var end: TextPosition {
		max(anchor, head)
	}

	/// Whether the range is empty (anchor equals head).
	public var isEmpty: Bool {
		anchor == head
	}

	/// The number of bytes covered by this range.
	public var length: Int {
		end.offset - start.offset
	}
}
