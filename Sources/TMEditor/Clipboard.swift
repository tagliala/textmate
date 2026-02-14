import Foundation

/// A single clipboard entry containing one or more text fragments with metadata.
///
/// Modeled after TextMate's C++ `clipboard_t::entry_t`. Each entry holds a
/// list of text fragments (one per cursor in multi-cursor mode) along with
/// options describing how the text was copied (columnar, indented, etc.).
public struct ClipboardEntry: Sendable, Equatable {
	/// The text contents — one string per cursor/selection at copy time.
	public var contents: [String]

	/// Metadata about how the text was copied.
	public var options: Options

	/// Options describing how a clipboard entry was created.
	public struct Options: Sendable, Equatable {
		/// Whether the text was copied from a columnar (rectangular) selection.
		public var isColumnar: Bool

		/// The leading indentation string of the first line at copy time.
		/// Used for reindenting on paste.
		public var indent: String?

		/// Whether the selection represented a "complete" line (begin-to-end).
		public var isComplete: Bool

		public init(isColumnar: Bool = false, indent: String? = nil, isComplete: Bool = false) {
			self.isColumnar = isColumnar
			self.indent = indent
			self.isComplete = isComplete
		}
	}

	public init(contents: [String], options: Options = Options()) {
		precondition(!contents.isEmpty, "ClipboardEntry must have at least one content string")
		self.contents = contents
		self.options = options
	}

	/// Convenience for a single-fragment entry.
	public init(_ text: String, options: Options = Options()) {
		self.init(contents: [text], options: options)
	}

	/// The full joined text content.
	public var text: String {
		contents.joined()
	}
}

// MARK: - Clipboard Protocol

/// Abstract clipboard interface supporting push/current/previous/next navigation.
///
/// Modeled after TextMate's C++ `clipboard_t`. Each clipboard maintains a stack
/// of entries with history navigation.
public protocol Clipboard: AnyObject, Sendable {
	/// Pushes a new entry onto the clipboard stack.
	func push(_ entry: ClipboardEntry)

	/// Returns the current clipboard entry, or `nil` if empty.
	func current() -> ClipboardEntry?

	/// Navigates to and returns the previous entry in history, or `nil`.
	func previous() -> ClipboardEntry?

	/// Navigates to and returns the next entry in history, or `nil`.
	func next() -> ClipboardEntry?

	/// Whether the clipboard has any entries.
	var isEmpty: Bool { get }

	/// Number of entries in the history stack.
	var count: Int { get }
}

// MARK: - SimpleClipboard

/// A simple in-memory clipboard with a stack of entries and history navigation.
///
/// Modeled after TextMate's C++ `simple_clipboard_t`.
public final class SimpleClipboard: Clipboard, @unchecked Sendable {
	private var entries: [ClipboardEntry] = []
	private var index: Int = 0

	public init() {}

	public func push(_ entry: ClipboardEntry) {
		entries.append(entry)
		index = entries.count - 1
	}

	public func current() -> ClipboardEntry? {
		guard !entries.isEmpty else { return nil }
		return entries[index]
	}

	public func previous() -> ClipboardEntry? {
		guard !entries.isEmpty else { return nil }
		if index > 0 {
			index -= 1
		}
		return entries[index]
	}

	public func next() -> ClipboardEntry? {
		guard !entries.isEmpty else { return nil }
		if index < entries.count - 1 {
			index += 1
		}
		return entries[index]
	}

	public var isEmpty: Bool {
		entries.isEmpty
	}

	public var count: Int {
		entries.count
	}
}

// MARK: - Clipboard Set

/// The four clipboards used by the editor, mirroring TextMate's C++ editor_t.
///
/// - `general`: The main system clipboard (Cmd-C / Cmd-V).
/// - `find`: The search clipboard (Cmd-E  / Cmd-G).
/// - `replace`: The replacement string clipboard.
/// - `yank`: The Emacs-style yank clipboard (Ctrl-K / Ctrl-Y).
public final class ClipboardSet: @unchecked Sendable {
	public let general: Clipboard
	public let find: Clipboard
	public let replace: Clipboard
	public let yank: Clipboard

	public init(
		general: Clipboard = SimpleClipboard(),
		find: Clipboard = SimpleClipboard(),
		replace: Clipboard = SimpleClipboard(),
		yank: Clipboard = SimpleClipboard(),
	) {
		self.general = general
		self.find = find
		self.replace = replace
		self.yank = yank
	}
}
