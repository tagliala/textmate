import Foundation

// MARK: - Find Options

/// Option set controlling find behavior — equivalent to `find::options_t`.
public struct FindOptions: OptionSet, Sendable, Hashable, Codable {
	public let rawValue: UInt32

	public init(rawValue: UInt32) {
		self.rawValue = rawValue
	}

	/// Match only whole words (word boundaries around match).
	public static let fullWords = FindOptions(rawValue: 1 << 0)

	/// Case-insensitive matching.
	public static let ignoreCase = FindOptions(rawValue: 1 << 1)

	/// Ignore differences in whitespace.
	public static let ignoreWhitespace = FindOptions(rawValue: 1 << 2)

	/// Interpret the search string as a regular expression.
	public static let regularExpression = FindOptions(rawValue: 1 << 3)

	/// Search backwards from the current position.
	public static let backwards = FindOptions(rawValue: 1 << 4)

	/// Wrap around to the beginning/end when reaching the boundary.
	public static let wrapAround = FindOptions(rawValue: 1 << 7)

	/// Find all matches (not just next/previous).
	public static let allMatches = FindOptions(rawValue: 1 << 8)

	/// Extend the selection to include the match.
	public static let extendSelection = FindOptions(rawValue: 1 << 9)

	/// Common presets.
	public static let `default`: FindOptions = [.ignoreCase, .wrapAround]
	public static let none: FindOptions = []
}

// MARK: - Find Operation

/// The type of find/replace operation to perform — equivalent to `find_operation_t`.
public enum FindOperation: Int, Sendable {
	/// Count matches in the document.
	case count

	/// Count matches in the current selection.
	case countInSelection

	/// Find the next/previous match.
	case find

	/// Find matches within the selection.
	case findInSelection

	/// Replace the current match.
	case replace

	/// Replace the current match and find the next.
	case replaceAndFind

	/// Replace all matches in the document.
	case replaceAll

	/// Replace all matches in the current selection.
	case replaceAllInSelection
}

// MARK: - Search Scope

/// Where to search — equivalent to `FFSearchTarget`.
public enum SearchScope: Int, Sendable, Hashable {
	/// Search in the current document.
	case document

	/// Search in the current selection.
	case selection

	/// Search across all open documents.
	case openFiles

	/// Search across the project directory.
	case project

	/// Search in file browser selected items.
	case fileBrowserItems

	/// Search in a custom folder.
	case other
}

// MARK: - Find Match

/// A single match result with its location and captures.
public struct FindMatch: Sendable, Equatable, Identifiable {
	public let id = UUID()

	/// The byte range of the match in the source text.
	public var range: Range<Int>

	/// Named and numbered capture groups from a regex match.
	public var captures: [String: String]

	public init(range: Range<Int>, captures: [String: String] = [:]) {
		self.range = range
		self.captures = captures
	}

	/// The length of the match.
	public var length: Int {
		range.count
	}

	/// Whether this is a zero-length match.
	public var isEmpty: Bool {
		range.isEmpty
	}

	public static func == (lhs: FindMatch, rhs: FindMatch) -> Bool {
		lhs.range == rhs.range && lhs.captures == rhs.captures
	}
}

// MARK: - Document Match

/// A match within a specific document, including context excerpt — equivalent to `OakDocumentMatch`.
struct DocumentMatch: Sendable, Identifiable {
	let id = UUID()

	/// The document identifier (UUID).
	var documentID: UUID

	/// The document path, if any.
	var documentPath: String?

	/// The document display name.
	var displayName: String

	/// The byte range of the match.
	var byteRange: Range<Int>

	/// The line:column range for display.
	var lineRange: LineColumnRange

	/// The 0-based line number of the match.
	var lineNumber: Int

	/// Regex captures (named groups).
	var captures: [String: String]

	/// Context excerpt around the match.
	var excerpt: String

	/// Byte offset of the excerpt start within the document.
	var excerptOffset: Int

	/// Whether the excerpt was truncated at the beginning.
	var headTruncated: Bool

	/// Whether the excerpt was truncated at the end.
	var tailTruncated: Bool

	init(
		documentID: UUID,
		documentPath: String? = nil,
		displayName: String,
		byteRange: Range<Int>,
		lineRange: LineColumnRange = .zero,
		lineNumber: Int = 0,
		captures: [String: String] = [:],
		excerpt: String = "",
		excerptOffset: Int = 0,
		headTruncated: Bool = false,
		tailTruncated: Bool = false,
	) {
		self.documentID = documentID
		self.documentPath = documentPath
		self.displayName = displayName
		self.byteRange = byteRange
		self.lineRange = lineRange
		self.lineNumber = lineNumber
		self.captures = captures
		self.excerpt = excerpt
		self.excerptOffset = excerptOffset
		self.headTruncated = headTruncated
		self.tailTruncated = tailTruncated
	}
}

// MARK: - Line Column Range

/// A line:column range for display purposes.
public struct LineColumnRange: Sendable, Equatable, Hashable {
	public var startLine: Int
	public var startColumn: Int
	public var endLine: Int
	public var endColumn: Int

	public init(startLine: Int = 0, startColumn: Int = 0, endLine: Int = 0, endColumn: Int = 0) {
		self.startLine = startLine
		self.startColumn = startColumn
		self.endLine = endLine
		self.endColumn = endColumn
	}

	public static let zero = LineColumnRange()

	public var description: String {
		if startLine == endLine {
			return "\(startLine + 1):\(startColumn)-\(endColumn)"
		}
		return "\(startLine + 1):\(startColumn)-\(endLine + 1):\(endColumn)"
	}
}
