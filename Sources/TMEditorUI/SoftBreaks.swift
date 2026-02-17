/// Compute byte offsets at which a string should be soft-wrapped.
///
/// This is the Swift port of C++ `text::soft_breaks()` from
/// `Frameworks/text/src/parse.cc`. It scans a hard line and returns
/// byte offsets where soft-break nodes should be inserted.
///
/// Break strategy:
/// - Prefer breaking after the last space that keeps the line within `width`.
/// - If no space exists, break at exactly `width` columns (word-split).
/// - After the first break, the effective width shrinks by `prefixSize`
///   to account for indented-soft-wrap fill strings.
///
/// - Parameters:
///   - string: The hard-line text (may contain tabs, no newlines expected
///     but handled gracefully as column resets).
///   - width: Wrap column (in monospaced character widths).
///   - tabSize: Tab-stop interval.
///   - prefixSize: Extra columns consumed by the fill string on
///     continuation lines.
/// - Returns: Sorted array of UTF-8 byte offsets where soft breaks occur.
public func softBreaks(
	in string: String,
	width: Int,
	tabSize: Int,
	prefixSize: Int = 0,
) -> [Int] {
	guard width > 0 else { return [] }

	var result: [Int] = []
	var col = 0
	var len = 0
	var spaceCol = 0
	var spaceLen = 0
	var effectiveWidth = width
	var prefix = prefixSize

	let utf8 = Array(string.utf8)
	var i = 0
	while i < utf8.count {
		let prevLen = len
		let prevCol = col

		// Decode one Unicode scalar and advance past its UTF-8 bytes.
		let byte = utf8[i]
		let scalarLen: Int
		let scalar: UnicodeScalar
		if byte < 0x80 {
			scalarLen = 1
			scalar = UnicodeScalar(byte)
		} else if byte < 0xC0 {
			// Continuation byte (shouldn't be first) — treat as 1 byte.
			scalarLen = 1
			scalar = UnicodeScalar(byte)
		} else if byte < 0xE0 {
			scalarLen = 2
			scalar = decodeUTF8(utf8, at: i, length: 2) ?? Unicode.Scalar(0xFFFD)!
		} else if byte < 0xF0 {
			scalarLen = 3
			scalar = decodeUTF8(utf8, at: i, length: 3) ?? Unicode.Scalar(0xFFFD)!
		} else {
			scalarLen = 4
			scalar = decodeUTF8(utf8, at: i, length: 4) ?? Unicode.Scalar(0xFFFD)!
		}

		len += scalarLen
		col += scalar == "\t"
			? (tabSize - (col % tabSize))
			: (isEastAsianWide(scalar) ? 2 : 1)

		if scalar == "\n" {
			col = 0
			spaceLen = len
			spaceCol = col
		} else if col > effectiveWidth {
			if spaceCol == 0 {
				// No word boundary — hard-break right before this character.
				result.append(prevLen)
				effectiveWidth -= prefix
				prefix = 0
				col = col - prevCol
			} else {
				// Break at the last space.
				result.append(spaceLen)
				effectiveWidth -= prefix
				prefix = 0
				col = col - spaceCol
				let savedSpaceLen = spaceLen
				spaceCol = 0

				// If continuation text is still too wide, re-scan from break.
				if col > effectiveWidth {
					i = savedSpaceLen
					len = savedSpaceLen
					col = 0
					continue
				}
			}
		} else if scalar == " " {
			spaceLen = len
			spaceCol = col
		}

		i += scalarLen
	}
	return result
}

// MARK: - Private Helpers

/// Decode a multi-byte UTF-8 scalar from raw bytes.
private func decodeUTF8(_ bytes: [UInt8], at index: Int, length: Int) -> UnicodeScalar? {
	guard index + length <= bytes.count else { return nil }
	var value: UInt32
	switch length {
	case 2:
		value = UInt32(bytes[index] & 0x1F) << 6
			| UInt32(bytes[index + 1] & 0x3F)
	case 3:
		value = UInt32(bytes[index] & 0x0F) << 12
			| UInt32(bytes[index + 1] & 0x3F) << 6
			| UInt32(bytes[index + 2] & 0x3F)
	case 4:
		value = UInt32(bytes[index] & 0x07) << 18
			| UInt32(bytes[index + 1] & 0x3F) << 12
			| UInt32(bytes[index + 2] & 0x3F) << 6
			| UInt32(bytes[index + 3] & 0x3F)
	default:
		return nil
	}
	return UnicodeScalar(value)
}

/// Simple East Asian wide character detection.
///
/// Returns `true` for CJK Unified Ideographs and other commonly
/// fullwidth ranges. This is a simplified check — a full ICU-based
/// implementation would use `EastAsianWidth` property.
private func isEastAsianWide(_ scalar: UnicodeScalar) -> Bool {
	let v = scalar.value
	// CJK Unified Ideographs
	if v >= 0x4E00, v <= 0x9FFF { return true }
	// CJK Extension A
	if v >= 0x3400, v <= 0x4DBF { return true }
	// CJK Compatibility Ideographs
	if v >= 0xF900, v <= 0xFAFF { return true }
	// Hangul Syllables
	if v >= 0xAC00, v <= 0xD7AF { return true }
	// Fullwidth Forms
	if v >= 0xFF01, v <= 0xFF60 { return true }
	if v >= 0xFFE0, v <= 0xFFE6 { return true }
	// CJK Extension B+
	if v >= 0x20000, v <= 0x2FA1F { return true }
	return false
}
