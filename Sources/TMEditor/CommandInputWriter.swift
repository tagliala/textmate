import Foundation
import TMCore

// MARK: - Input Unit

/// The unit of text to extract from the buffer for command input.
///
/// Matches the C++ `input::type` enum from
/// `Frameworks/command/src/parser.h`.
public enum InputUnit: String, Sendable {
	/// The current selection (or fallback if empty).
	case selection
	/// The entire document content.
	case entireDocument
	/// The word at the caret.
	case word
	/// The current line.
	case line
	/// The scope at the caret (requires grammar integration).
	case scope
	/// A single character to the right of the caret.
	case character
	/// No input.
	case nothing
}

/// The format for extracted input text.
public enum InputFormat: String, Sendable {
	/// Plain text.
	case text
	/// XML-escaped text.
	case xml
}

// MARK: - CommandInputWriter

/// Extracts text from an editor buffer for use as command input.
///
/// Port of C++ `ng::write_unit_to_fd` from
/// `Frameworks/editor/src/write.cc`. Instead of writing directly to a
/// file descriptor, this returns the extracted text and metadata so the
/// caller can pipe it to a `Process`.
///
/// The extraction logic determines actual input based on the requested
/// unit: if `selection` is requested but there is no selection, the
/// `fallback` unit is used instead (matching the C++ behavior).
public enum CommandInputWriter {
	/// Result of extracting command input text.
	public struct Extraction: Sendable {
		/// The extracted text data (UTF-8).
		public let data: Data

		/// Whether the actual input came from a selection
		/// (as opposed to a fallback unit like word/line/document).
		public let inputWasSelection: Bool

		/// Environment variables to set based on the input range
		/// (e.g., `TM_INPUT_START_LINE`, `TM_INPUT_START_COLUMN`).
		public let inputVariables: [String: String]

		/// The ranges of text that were used as input.
		/// When the command finishes, these may be replaced by its output.
		public let inputRanges: [TextRange]
	}

	/// Extract text from the buffer according to the requested input type.
	///
	/// - Parameters:
	///   - buffer: The text buffer to read from.
	///   - selections: The current selection state.
	///   - tabSize: Tab size for column calculation.
	///   - unit: The requested input unit (selection, word, line, etc.).
	///   - fallback: Fallback unit when selection is empty.
	///   - format: Whether to extract as plain text or XML.
	/// - Returns: The extracted text and metadata.
	public static func extract(
		from buffer: TextBuffer,
		selections: SelectionState,
		tabSize: Int,
		unit: InputUnit,
		fallback: InputUnit,
		format: InputFormat,
	) -> Extraction {
		let ranges = selections.selections
		let noSelection = ranges.allSatisfy(\.isEmpty)

		// Determine actual unit: if selection was requested but nothing is
		// selected, fall back (unless there are multiple cursors and the
		// fallback is entire document — match C++ logic).
		let actualUnit: InputUnit = if unit == .selection, noSelection,
		                               ranges.count == 1 || fallback != .entireDocument
		{
			fallback
		} else {
			unit
		}

		let inputWasSelection = actualUnit == .selection

		// Resolve each range to the appropriate extent.
		var resolvedRanges = ranges.map { range -> TextRange in
			switch actualUnit {
			case .character:
				return extendRight(range, in: buffer) ?? range
			case .word:
				return wordRange(at: range, in: buffer)
			case .line:
				return lineRange(at: range, in: buffer)
			case .scope:
				// Scope-based selection requires grammar integration.
				// For now, fall back to the raw range.
				return range
			case .entireDocument:
				return TextRange(
					anchor: buffer.convert(offset: 0),
					head: buffer.convert(offset: buffer.size),
				)
			case .selection:
				return range
			case .nothing:
				return TextRange(caret: range.start)
			}
		}

		// Sanitize overlapping ranges (merge and sort).
		resolvedRanges = sanitizeRanges(resolvedRanges)

		// Build the text content.
		var text = ""
		var first = true
		for range in resolvedRanges {
			if !first { text += "\n" }
			first = false
			let start = range.start.offset
			let end = range.end.offset
			if start < end {
				if format == .xml {
					// XML format: escape entities.
					text += escapeXML(buffer.substring(from: start, to: end))
				} else {
					text += buffer.substring(from: start, to: end)
				}
			}
		}

		// Build input position variables (if we have a single non-empty
		// range and it's not the entire document).
		var inputVars: [String: String] = [:]
		if resolvedRanges.count == 1,
		   let range = resolvedRanges.first,
		   !range.isEmpty,
		   actualUnit != .entireDocument
		{
			let startOffset = range.start.offset
			let pos = buffer.convert(offset: startOffset)
			inputVars["TM_INPUT_START_LINE"] = "\(pos.line + 1)"
			inputVars["TM_INPUT_START_LINE_INDEX"] = "\(pos.column)"

			let column = countColumns(
				buffer: buffer, offset: startOffset, tabSize: tabSize,
			)
			inputVars["TM_INPUT_START_COLUMN"] = "\(column + 1)"
		}

		return Extraction(
			data: Data(text.utf8),
			inputWasSelection: inputWasSelection,
			inputVariables: inputVars,
			inputRanges: resolvedRanges,
		)
	}

	// MARK: - Range Extension

	/// Extend an empty range one character to the right.
	private static func extendRight(
		_ range: TextRange, in buffer: TextBuffer,
	) -> TextRange? {
		guard range.isEmpty else { return range }
		let offset = range.start.offset
		guard offset < buffer.size else { return nil }
		return TextRange(
			anchor: buffer.convert(offset: offset),
			head: buffer.convert(offset: offset + 1),
		)
	}

	/// Extend range to word boundaries.
	private static func wordRange(
		at range: TextRange, in buffer: TextBuffer,
	) -> TextRange {
		guard range.isEmpty else { return range }
		let offset = range.start.offset
		let str = buffer.string
		let idx = str.index(str.startIndex, offsetBy: min(offset, str.count))

		// Scan left
		var left = idx
		while left > str.startIndex {
			let prev = str.index(before: left)
			if str[prev].isWordCharacter { left = prev } else { break }
		}

		// Scan right
		var right = idx
		while right < str.endIndex {
			if str[right].isWordCharacter { right = str.index(after: right) } else { break }
		}

		let leftOff = str.distance(from: str.startIndex, to: left)
		let rightOff = str.distance(from: str.startIndex, to: right)
		return TextRange(
			anchor: buffer.convert(offset: leftOff),
			head: buffer.convert(offset: rightOff),
		)
	}

	/// Extend range to full line (excluding trailing newline).
	private static func lineRange(
		at range: TextRange, in buffer: TextBuffer,
	) -> TextRange {
		let offset = range.isEmpty ? range.start.offset : range.start.offset
		let str = buffer.string

		guard offset <= str.count else {
			return range
		}

		let idx = str.index(str.startIndex, offsetBy: min(offset, str.count))

		// Find line start
		var lineStart = idx
		while lineStart > str.startIndex {
			let prev = str.index(before: lineStart)
			if str[prev].isNewline { break }
			lineStart = prev
		}

		// Find line end (exclude trailing newline)
		var lineEnd = idx
		while lineEnd < str.endIndex, !str[lineEnd].isNewline {
			lineEnd = str.index(after: lineEnd)
		}

		let startOff = str.distance(from: str.startIndex, to: lineStart)
		let endOff = str.distance(from: str.startIndex, to: lineEnd)
		return TextRange(
			anchor: buffer.convert(offset: startOff),
			head: buffer.convert(offset: endOff),
		)
	}

	// MARK: - Column Counting

	/// Count the display column for a given buffer offset, accounting
	/// for tab expansion and East Asian width characters.
	///
	/// Matches C++ `count_columns()` from `write.cc`.
	private static func countColumns(
		buffer: TextBuffer,
		offset: Int,
		tabSize: Int,
	) -> Int {
		let pos = buffer.convert(offset: offset)
		let lineStart = offset - pos.column
		let text = buffer.substring(from: lineStart, to: offset)

		var columns = 0
		for char in text.unicodeScalars {
			if char == "\t" {
				columns += tabSize - (columns % tabSize)
			} else {
				columns += 1
			}
		}
		return columns
	}

	// MARK: - Range Sanitization

	/// Sort and merge overlapping ranges.
	private static func sanitizeRanges(_ ranges: [TextRange]) -> [TextRange] {
		guard ranges.count > 1 else { return ranges }
		let sorted = ranges.sorted {
			$0.start.offset < $1.start.offset
		}
		var result: [TextRange] = []
		for range in sorted {
			if let last = result.last,
			   range.start.offset <= last.end.offset
			{
				// Merge overlapping ranges.
				let maxEnd = max(last.end.offset, range.end.offset)
				result[result.count - 1] = TextRange(
					anchor: last.start,
					head: TextPosition(
						line: 0, column: 0, offset: maxEnd,
					),
				)
			} else {
				result.append(range)
			}
		}
		return result
	}

	// MARK: - XML Escaping

	/// Escape text for XML output format.
	private static func escapeXML(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}
}

// MARK: - Character Extension

private extension Character {
	/// Whether this character is part of a word (alphanumeric or underscore).
	var isWordCharacter: Bool {
		isLetter || isNumber || self == "_"
	}
}
