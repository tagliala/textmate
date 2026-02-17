// Tab-aware visual column counting, columnar selection support,
// selection sanitization, and serialization utilities.
//
// Ports the core selection helper functions from the C++ `ng` namespace
// in `Frameworks/selection/src/selection.cc`.
import Foundation

// MARK: - East Asian Width Detection

/// Whether a Unicode scalar is considered "wide" (East Asian Width W or F).
///
/// Wide characters occupy two visual columns in a monospaced font.
/// The ranges are derived from the Unicode East_Asian_Width property
/// (categories W = Wide and F = Fullwidth).
public func isEastAsianWide(_ scalar: Unicode.Scalar) -> Bool {
	let v = scalar.value
	return (v >= 0x1100 && v <= 0x115F) // Hangul Jamo
		|| v == 0x2329 || v == 0x232A // Angle brackets
		|| (v >= 0x2E80 && v <= 0x303E) // CJK Radicals, Kangxi, Symbols
		|| (v >= 0x3040 && v <= 0x33BF) // Hiragana, Katakana, Bopomofo
		|| (v >= 0x3400 && v <= 0x4DBF) // CJK Extension A
		|| (v >= 0x4E00 && v <= 0xA4CF) // CJK Unified Ideographs, Yi
		|| (v >= 0xA960 && v <= 0xA97C) // Hangul Jamo Extended-A
		|| (v >= 0xAC00 && v <= 0xD7A3) // Hangul Syllables
		|| (v >= 0xF900 && v <= 0xFAFF) // CJK Compatibility Ideographs
		|| (v >= 0xFE10 && v <= 0xFE19) // Vertical Forms
		|| (v >= 0xFE30 && v <= 0xFE6B) // CJK Compatibility Forms
		|| (v >= 0xFF01 && v <= 0xFF60) // Fullwidth ASCII/Latin
		|| (v >= 0xFFE0 && v <= 0xFFE6) // Fullwidth Signs
		|| (v >= 0x1F000 && v <= 0x1F9FF) // Mahjong, Domino, Emoticons
		|| (v >= 0x20000 && v <= 0x2FFFF) // CJK Extension B–F
		|| (v >= 0x30000 && v <= 0x3FFFF) // CJK Extension G–I
}

/// Visual width of a single grapheme cluster in columns.
///
/// - Tab: advances to the next tab stop.
/// - East-Asian wide: 2 columns.
/// - All other printable characters: 1 column.
private func characterWidth(_ char: Character, currentColumn: Int, tabSize: Int) -> Int {
	if char == "\t" {
		return tabSize - (currentColumn % tabSize)
	}
	if let scalar = char.unicodeScalars.first, isEastAsianWide(scalar) {
		return 2
	}
	return 1
}

// MARK: - Column Counting

/// Counts the visual columns from the start of the line to the given
/// caret position, accounting for tabs and East-Asian wide characters.
///
/// The caret's `carry` (virtual offset past end-of-line) is added to
/// the result.  This is the Swift port of C++ `ng::count_columns()`.
///
/// - Parameters:
///   - buffer: The text buffer.
///   - caret: The caret position (may have non-zero carry).
///   - tabSize: Number of columns per tab stop.
/// - Returns: The visual column count.
public func countColumns(in buffer: TextBuffer, caret: TextPosition, tabSize: Int) -> Int {
	let line = buffer.convert(offset: caret.offset).line
	let bol = buffer.lineStart(line)
	guard caret.offset > bol else { return caret.carry }

	let str = buffer.substring(from: bol, to: caret.offset)
	var len = 0
	for char in str {
		len += characterWidth(char, currentColumn: len, tabSize: tabSize)
	}
	return len + caret.carry
}

/// Finds the buffer position for a given visual column on a line.
///
/// If the target column falls inside a tab or wide character, or past
/// the end of the line, the returned position includes a non-zero
/// `carry` value.  This is the Swift port of C++ `ng::at_column()`.
///
/// - Parameters:
///   - buffer: The text buffer.
///   - line: The zero-based line number.
///   - column: The target visual column.
///   - tabSize: Number of columns per tab stop.
/// - Returns: A `TextPosition` at or near the target column.
public func atColumn(in buffer: TextBuffer, line: Int, column: Int, tabSize: Int) -> TextPosition {
	let bol = buffer.lineStart(line)
	let eol = buffer.lineEnd(line)
	let str = buffer.substring(from: bol, to: eol)

	var len = 0
	var byteOffset = 0

	for char in str {
		if len == column {
			let offset = bol + byteOffset
			return TextPosition(line: line, column: byteOffset, offset: offset)
		}

		let charWidth = characterWidth(char, currentColumn: len, tabSize: tabSize)

		if len + charWidth > column {
			// Target column falls within this character (tab or wide char)
			let offset = bol + byteOffset
			return TextPosition(line: line, column: byteOffset, offset: offset, carry: column - len)
		}

		len += charWidth
		byteOffset += char.utf8.count
	}

	// Past end of line — carry stores the remaining columns
	let offset = bol + byteOffset
	return TextPosition(line: line, column: byteOffset, offset: offset, carry: column - len)
}

// MARK: - Columnar Selection Dissection

/// Expands columnar (rectangular) selections into per-line ranges.
///
/// Each columnar range is replaced by one range per line spanning the
/// visual column rectangle.  Non-columnar ranges pass through with
/// their endpoints normalized to (min, max) order.
///
/// This is the Swift port of C++ `ng::dissect_columnar()`.
///
/// - Parameters:
///   - buffer: The text buffer.
///   - selection: The selection ranges (may contain columnar ranges).
///   - tabSize: Number of columns per tab stop.
/// - Returns: The dissected ranges (no columnar flags remain).
public func dissectColumnar(in buffer: TextBuffer, selection: [TextRange], tabSize: Int) -> [TextRange] {
	var result: [TextRange] = []
	for range in selection {
		if range.isColumnar, !range.isEmpty {
			let colA = countColumns(in: buffer, caret: range.anchor, tabSize: tabSize)
			let colB = countColumns(in: buffer, caret: range.head, tabSize: tabSize)

			let lineA = buffer.convert(offset: range.anchor.offset).line
			let lineB = buffer.convert(offset: range.head.offset).line

			let fromLine = min(lineA, lineB)
			let toLine = max(lineA, lineB)
			let fromCol = min(colA, colB)
			let toCol = max(colA, colB)

			for n in fromLine ... toLine {
				let from = atColumn(in: buffer, line: n, column: fromCol, tabSize: tabSize)
				let to = atColumn(in: buffer, line: n, column: toCol, tabSize: tabSize)
				result.append(TextRange(
					anchor: from,
					head: to,
					isColumnar: false,
					isFreehanded: from.carry != 0 || to.carry != 0,
					isUnanchored: range.isUnanchored,
					color: range.color,
				))
			}
		} else {
			result.append(TextRange(
				anchor: range.start,
				head: range.end,
				isColumnar: range.isColumnar,
				isFreehanded: range.isFreehanded,
				isUnanchored: range.isUnanchored,
				color: range.color,
			))
		}
	}
	return result
}

// MARK: - Selection Sanitization

/// Sanitizes a selection by clamping indices to valid buffer boundaries
/// and merging overlapping non-columnar ranges.
///
/// Ranges are sorted by position while preserving original insertion
/// order for the final result.  Columnar ranges are never merged.
///
/// This is the Swift port of C++ `ng::sanitize()`.
///
/// - Parameters:
///   - buffer: The text buffer.
///   - selection: The ranges to sanitize.
/// - Returns: Sanitized, non-overlapping ranges.
public func sanitize(in buffer: TextBuffer, selection: [TextRange]) -> [TextRange] {
	guard !selection.isEmpty else { return [] }

	// 1. Build indexed ranges with sanitized byte offsets.
	struct IndexedRange: Comparable {
		let range: TextRange
		let index: Int

		static func < (lhs: IndexedRange, rhs: IndexedRange) -> Bool {
			// Columnar ranges sort after non-columnar
			let lCol: Int = lhs.range.isColumnar ? 1 : 0
			let rCol: Int = rhs.range.isColumnar ? 1 : 0
			if lCol != rCol { return lCol < rCol }

			let lMin = lhs.range.start.offset
			let rMin = rhs.range.start.offset
			if lMin != rMin { return lMin < rMin }

			// For freehanded, compare carry at min
			let lMinCarry = lhs.range.isFreehanded ? lhs.range.start.carry : 0
			let rMinCarry = rhs.range.isFreehanded ? rhs.range.start.carry : 0
			if lMinCarry != rMinCarry { return lMinCarry < rMinCarry }

			// Wider ranges first (invert max comparison)
			let lMax = lhs.range.end.offset
			let rMax = rhs.range.end.offset
			if lMax != rMax { return lMax > rMax }

			let lMaxCarry = lhs.range.isFreehanded ? lhs.range.end.carry : 0
			let rMaxCarry = rhs.range.isFreehanded ? rhs.range.end.carry : 0
			return lMaxCarry > rMaxCarry
		}
	}

	let bufferSize = buffer.size

	var indexed: [IndexedRange] = []
	for (i, range) in selection.enumerated() {
		let sanitizedAnchorOffset = max(0, min(range.anchor.offset, bufferSize))
		let sanitizedHeadOffset = max(0, min(range.head.offset, bufferSize))

		let sanitizedAnchor = TextPosition(
			line: buffer.convert(offset: sanitizedAnchorOffset).line,
			column: buffer.convert(offset: sanitizedAnchorOffset).column,
			offset: sanitizedAnchorOffset,
			carry: range.anchor.carry,
		)
		let sanitizedHead = TextPosition(
			line: buffer.convert(offset: sanitizedHeadOffset).line,
			column: buffer.convert(offset: sanitizedHeadOffset).column,
			offset: sanitizedHeadOffset,
			carry: range.head.carry,
		)

		let sanitized = TextRange(
			anchor: sanitizedAnchor,
			head: sanitizedHead,
			isColumnar: range.isColumnar,
			isFreehanded: range.isFreehanded,
			isUnanchored: range.isUnanchored,
			color: range.color,
		)
		indexed.append(IndexedRange(range: sanitized, index: i))
	}

	indexed.sort()

	// 2. Merge overlapping non-columnar ranges.
	var map: [(index: Int, range: TextRange)] = []
	var lastMax = TextPosition(line: 0, column: 0, offset: 0, carry: 0)
	var hasLast = false

	for record in indexed {
		let range = record.range
		let rangeMax = range.end

		if !hasLast || range.isColumnar {
			map.append((record.index, range))
			lastMax = rangeMax
			hasLast = true
		} else if lastMax < rangeMax || (lastMax == rangeMax && range.isEmpty) {
			let rangeMin = range.start
			var adjusted = range
			if rangeMin < lastMax {
				// Clip the start to avoid overlap
				if adjusted.anchor <= adjusted.head {
					adjusted.anchor = lastMax
				} else {
					adjusted.head = lastMax
				}
			}
			map.append((record.index, adjusted))
			lastMax = rangeMax
		}
	}

	// 3. Return in original insertion order.
	map.sort { $0.index < $1.index }
	return map.map(\.range)
}

// MARK: - Selection Queries

/// Whether any range in the selection is non-empty.
///
/// For columnar ranges, visual column width is considered — a columnar
/// range spanning the same column on both endpoints is treated as empty.
///
/// This is the Swift port of C++ `ng::not_empty()`.
///
/// - Parameters:
///   - buffer: The text buffer.
///   - selection: The selection ranges.
///   - tabSize: Number of columns per tab stop.
/// - Returns: `true` if at least one range covers content.
public func notEmpty(in buffer: TextBuffer, selection: [TextRange], tabSize: Int) -> Bool {
	for range in selection {
		if range.isEmpty {
			continue
		}
		if range.isColumnar {
			let colA = countColumns(in: buffer, caret: range.anchor, tabSize: tabSize)
			let colB = countColumns(in: buffer, caret: range.head, tabSize: tabSize)
			if colA != colB {
				return true
			}
		} else {
			return true
		}
	}
	return false
}

/// Whether any range in the selection spans multiple lines.
///
/// This is the Swift port of C++ `ng::multiline()`.
///
/// - Parameters:
///   - buffer: The text buffer.
///   - selection: The selection ranges.
/// - Returns: `true` if at least one range covers more than one line.
public func multiline(in buffer: TextBuffer, selection: [TextRange]) -> Bool {
	for range in selection {
		let lineA = buffer.convert(offset: range.anchor.offset).line
		let lineB = buffer.convert(offset: range.head.offset).line
		if lineA != lineB {
			return true
		}
	}
	return false
}

// MARK: - Selection Manipulation

/// Toggles the columnar flag on the last range of the selection.
///
/// This is the Swift port of C++ `ng::toggle_columnar()`.
///
/// - Parameter selection: The selection ranges.
/// - Returns: A new selection with the last range's columnar flag toggled.
public func toggleColumnar(_ selection: [TextRange]) -> [TextRange] {
	guard !selection.isEmpty else { return selection }
	var result = selection
	let i = result.count - 1
	let last = result[i]
	result[i] = TextRange(
		anchor: last.anchor,
		head: last.head,
		isColumnar: !last.isEmpty && !last.isColumnar,
		isFreehanded: last.isFreehanded,
	)
	return result
}

/// Removes the last selection or collapses it.
///
/// Behavior:
/// - Multiple selections: removes the last range.
/// - Single selection with content: collapses to caret at anchor.
/// - Single caret: clears the freehanded flag.
///
/// This is the Swift port of C++ `ng::deselect_last()`.
///
/// - Parameter selection: The selection ranges.
/// - Returns: The reduced selection.
public func deselectLast(_ selection: [TextRange]) -> [TextRange] {
	guard !selection.isEmpty else { return selection }

	if selection.count == 1 {
		let r = selection[0]
		if r.isEmpty {
			return [TextRange(
				anchor: r.anchor,
				head: r.head,
				isColumnar: r.isColumnar,
				isFreehanded: false,
				isUnanchored: r.isUnanchored,
				color: r.color,
			)]
		} else {
			return [TextRange(caret: r.anchor)]
		}
	}

	// Check if all are single carets
	let allCarets = selection.allSatisfy(\.isEmpty)
	if allCarets {
		return [selection[0]]
	}

	return Array(selection.dropLast())
}

// MARK: - Selection Serialization

/// Parses a selection string into ranges.
///
/// The format is one or more ranges separated by `&`:
///     line:column[-line:column]
///
/// An optional `x` suffix marks a columnar range.
/// The carry (virtual offset past EOL) is encoded with `+offset`.
///
/// This is the Swift port of C++ `ng::from_string()`.
///
/// - Parameters:
///   - buffer: The text buffer (for offset conversion).
///   - string: The serialized selection string.
/// - Returns: The parsed ranges.
public func selectionFromString(in buffer: TextBuffer, string: String) -> [TextRange] {
	var result: [TextRange] = []
	let parts = string.split(separator: "&")
	for part in parts {
		let trimmed = part.trimmingCharacters(in: .whitespaces)
		if trimmed.isEmpty { continue }

		var isColumnar = false
		var working = trimmed
		if working.hasSuffix("x") {
			isColumnar = true
			working = String(working.dropLast())
		}

		let endpoints = working.split(separator: "-", maxSplits: 1)
		let fromPos = parsePosition(String(endpoints[0]), in: buffer)
		let toPos: TextPosition = if endpoints.count > 1 {
			parsePosition(String(endpoints[1]), in: buffer)
		} else {
			fromPos
		}

		let hasCarry = fromPos.carry != 0 || toPos.carry != 0
		result.append(TextRange(
			anchor: fromPos,
			head: toPos,
			isColumnar: isColumnar,
			isFreehanded: hasCarry,
		))
	}
	return result
}

/// Serializes a selection to a string.
///
/// This is the Swift port of C++ `ng::to_s()`.
///
/// - Parameters:
///   - buffer: The text buffer (for line/column conversion).
///   - selection: The selection ranges.
/// - Returns: The serialized selection string.
public func selectionToString(in buffer: TextBuffer, selection: [TextRange]) -> String {
	var parts: [String] = []
	for range in selection {
		let fromPos = buffer.convert(offset: range.anchor.offset)
		let toPos = buffer.convert(offset: range.head.offset)

		let fromCarry = range.isFreehanded ? range.anchor.carry : 0
		let toCarry = range.isFreehanded ? range.head.carry : 0

		var s = formatPosition(line: fromPos.line, column: fromPos.column, carry: fromCarry)
		if range.anchor != range.head || fromCarry != toCarry {
			s += "-" + formatPosition(line: toPos.line, column: toPos.column, carry: toCarry)
		}
		if range.isColumnar {
			s += "x"
		}
		parts.append(s)
	}
	return parts.joined(separator: "&")
}

// MARK: - Serialization Helpers

/// Parses a "line:column[+carry]" string into a TextPosition.
private func parsePosition(_ string: String, in buffer: TextBuffer) -> TextPosition {
	var carry = 0
	var working = string

	// Extract carry suffix
	if let plusIndex = working.lastIndex(of: "+") {
		let carryStr = working[working.index(after: plusIndex)...]
		carry = Int(carryStr) ?? 0
		working = String(working[..<plusIndex])
	}

	let components = working.split(separator: ":", maxSplits: 1)
	let line = Int(components[0]) ?? 0
	let column: Int = components.count > 1 ? (Int(components[1]) ?? 0) : 0

	// Clamp line to buffer range
	let clampedLine = max(0, min(line, buffer.lines - 1))
	let bol = buffer.lineStart(clampedLine)
	let eol = buffer.lineEnd(clampedLine)
	let maxCol = eol - bol
	let clampedCol = min(column, maxCol)

	let offset = bol + clampedCol

	// If the clamped position is at a newline, treat remaining as carry
	if carry != 0, offset < buffer.size, buffer[offset] == UInt8(ascii: "\n") {
		// carry is already set
	} else if column > maxCol {
		carry = column - maxCol
	}

	return TextPosition(line: clampedLine, column: clampedCol, offset: offset, carry: carry)
}

/// Formats a position as "line:column[+carry]".
private func formatPosition(line: Int, column: Int, carry: Int) -> String {
	if carry != 0 {
		return "\(line):\(column)+\(carry)"
	}
	return "\(line):\(column)"
}
