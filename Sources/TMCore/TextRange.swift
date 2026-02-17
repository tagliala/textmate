/// A range within a text buffer, defined by an anchor and a head position.
///
/// The anchor is the position where the selection started, and the head is
/// where the caret currently sits. When `anchor == head`, the range represents
/// a caret (zero-width selection).
///
/// Additional flags mirror `ng::range_t` from the C++ editor:
/// - `isColumnar`: Rectangular (column) selection mode.
/// - `isFreehanded`: Cursor may sit past the end of a line.
/// - `isUnanchored`: Selection anchor floats during extend operations.
/// - `color`: Optional accent color tag for bracketed paste or diagnostics.
public struct TextRange: Sendable, Hashable {
	/// The position where the selection was initiated.
	public var anchor: TextPosition

	/// The current caret position (may be before or after anchor).
	public var head: TextPosition

	/// Whether this range represents a columnar (rectangular) selection.
	public var isColumnar: Bool

	/// Whether the cursor is allowed past the end of a line ("freehanded" mode).
	///
	/// When true, the editor allows placing the caret beyond the last
	/// character on a line, similar to block-cursor behavior in some editors.
	public var isFreehanded: Bool

	/// Whether the selection anchor is unfixed.
	///
	/// An unanchored range floats its anchor during extend operations,
	/// allowing selection growth from either end.
	public var isUnanchored: Bool

	/// Optional accent color tag for this range.
	///
	/// Used to visually distinguish ranges (e.g. bracketed paste, snippets,
	/// or diagnostic overlays).  Zero means no special color.
	public var color: UInt32

	public init(
		anchor: TextPosition,
		head: TextPosition,
		isColumnar: Bool = false,
		isFreehanded: Bool = false,
		isUnanchored: Bool = false,
		color: UInt32 = 0,
	) {
		self.anchor = anchor
		self.head = head
		self.isColumnar = isColumnar
		self.isFreehanded = isFreehanded
		self.isUnanchored = isUnanchored
		self.color = color
	}

	/// Creates a caret (zero-width selection) at the given position.
	public init(caret position: TextPosition) {
		anchor = position
		head = position
		isColumnar = false
		isFreehanded = false
		isUnanchored = false
		color = 0
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
