import Foundation

// MARK: - HTML Entity Decoding

/// HTML named entity decoding, base32/64 decoding, ROT13, URL encode/decode.
enum TextDecode {
	// swiftlint:disable comma
	private static let htmlEntityMap: [String: String] = [
		"AElig": "Æ", "Aacute": "Á", "Acirc": "Â", "Agrave": "À",
		"Alpha": "Α", "Aring": "Å", "Atilde": "Ã", "Auml": "Ä",
		"Beta": "Β", "Ccedil": "Ç", "Chi": "Χ", "Dagger": "‡",
		"Delta": "Δ", "ETH": "Ð", "Eacute": "É", "Ecirc": "Ê",
		"Egrave": "È", "Epsilon": "Ε", "Eta": "Η", "Euml": "Ë",
		"Gamma": "Γ", "Iacute": "Í", "Icirc": "Î", "Igrave": "Ì",
		"Iota": "Ι", "Iuml": "Ï", "Kappa": "Κ", "Lambda": "Λ",
		"Mu": "Μ", "Ntilde": "Ñ", "Nu": "Ν", "OElig": "Œ",
		"Oacute": "Ó", "Ocirc": "Ô", "Ograve": "Ò", "Omega": "Ω",
		"Omicron": "Ο", "Oslash": "Ø", "Otilde": "Õ", "Ouml": "Ö",
		"Phi": "Φ", "Pi": "Π", "Prime": "″", "Psi": "Ψ",
		"Rho": "Ρ", "Scaron": "Š", "Sigma": "Σ", "THORN": "Þ",
		"Tau": "Τ", "Theta": "Θ", "Uacute": "Ú", "Ucirc": "Û",
		"Ugrave": "Ù", "Upsilon": "Υ", "Uuml": "Ü", "Xi": "Ξ",
		"Yacute": "Ý", "Yuml": "Ÿ", "Zeta": "Ζ",
		"aacute": "á", "acirc": "â", "acute": "´", "aelig": "æ",
		"agrave": "à", "alefsym": "ℵ", "alpha": "α", "amp": "&",
		"and": "∧", "ang": "∠", "apos": "'", "aring": "å",
		"asymp": "≈", "atilde": "ã", "auml": "ä", "bdquo": "„",
		"beta": "β", "brvbar": "¦", "bull": "•", "cap": "∩",
		"ccedil": "ç", "cedil": "¸", "cent": "¢", "chi": "χ",
		"circ": "ˆ", "clubs": "♣", "cong": "≅", "copy": "©",
		"crarr": "↵", "cup": "∪", "curren": "¤",
		"dArr": "⇓", "dagger": "†", "darr": "↓", "deg": "°",
		"delta": "δ", "diams": "♦", "divide": "÷",
		"eacute": "é", "ecirc": "ê", "egrave": "è", "empty": "∅",
		"emsp": "\u{2003}", "ensp": "\u{2002}", "epsilon": "ε",
		"equiv": "≡", "eta": "η", "eth": "ð", "euml": "ë",
		"euro": "€", "exist": "∃", "fnof": "ƒ", "forall": "∀",
		"frac12": "½", "frac14": "¼", "frac34": "¾", "frasl": "⁄",
		"gamma": "γ", "ge": "≥", "gt": ">",
		"hArr": "⇔", "harr": "↔", "hearts": "♥", "hellip": "…",
		"iacute": "í", "icirc": "î", "iexcl": "¡", "igrave": "ì",
		"image": "ℑ", "infin": "∞", "int": "∫", "iota": "ι",
		"iquest": "¿", "isin": "∈", "iuml": "ï",
		"kappa": "κ",
		"lArr": "⇐", "lambda": "λ", "lang": "〈", "laquo": "«",
		"larr": "←", "lceil": "⌈", "ldquo": "\u{201C}", "le": "≤",
		"lfloor": "⌊", "lowast": "∗", "loz": "◊",
		"lrm": "\u{200E}", "lsaquo": "‹", "lsquo": "\u{2018}", "lt": "<",
		"macr": "¯", "mdash": "—", "micro": "µ", "middot": "·",
		"minus": "−", "mu": "μ", "nabla": "∇",
		"nbsp": "\u{00A0}", "ndash": "–", "ne": "≠", "ni": "∋",
		"not": "¬", "notin": "∉", "nsub": "⊄", "ntilde": "ñ",
		"nu": "ν",
		"oacute": "ó", "ocirc": "ô", "oelig": "œ", "ograve": "ò",
		"oline": "‾", "omega": "ω", "omicron": "ο", "oplus": "⊕",
		"or": "∨", "ordf": "ª", "ordm": "º", "oslash": "ø",
		"otilde": "õ", "otimes": "⊗", "ouml": "ö",
		"para": "¶", "part": "∂", "permil": "‰", "perp": "⊥",
		"phi": "φ", "pi": "π", "piv": "ϖ", "plusmn": "±",
		"pound": "£", "prime": "′", "prod": "∏", "prop": "∝",
		"psi": "ψ", "quot": "\"",
		"rArr": "⇒", "radic": "√", "rang": "〉", "raquo": "»",
		"rarr": "→", "rceil": "⌉", "rdquo": "\u{201D}", "real": "ℜ",
		"reg": "®", "rfloor": "⌋", "rho": "ρ",
		"rlm": "\u{200F}", "rsaquo": "›", "rsquo": "\u{2019}",
		"sbquo": "‚", "scaron": "š", "sdot": "⋅", "sect": "§",
		"shy": "\u{00AD}", "sigma": "σ", "sigmaf": "ς", "sim": "∼",
		"spades": "♠", "sub": "⊂", "sube": "⊆", "sum": "∑",
		"sup1": "¹", "sup2": "²", "sup3": "³", "sup": "⊃",
		"supe": "⊇", "szlig": "ß",
		"tau": "τ", "there4": "∴", "theta": "θ", "thetasym": "ϑ",
		"thinsp": "\u{2009}", "thorn": "þ", "tilde": "˜", "times": "×",
		"trade": "™",
		"uArr": "⇑", "uacute": "ú", "uarr": "↑", "ucirc": "û",
		"ugrave": "ù", "uml": "¨", "upsih": "ϒ", "upsilon": "υ",
		"uuml": "ü",
		"weierp": "℘", "xi": "ξ",
		"yacute": "ý", "yen": "¥", "yuml": "ÿ",
		"zeta": "ζ", "zwj": "\u{200D}", "zwnj": "\u{200C}",
	]
	// swiftlint:enable comma

	/// Decode HTML entities in a string (e.g. `&amp;` → `&`).
	static func htmlEntities(_ src: String) -> String {
		var result = ""
		result.reserveCapacity(src.count)
		var i = src.startIndex

		while i < src.endIndex {
			guard let ampIndex = src[i...].firstIndex(of: "&") else {
				result.append(contentsOf: src[i...])
				break
			}

			// Append text before the '&'
			result.append(contentsOf: src[i ..< ampIndex])

			let afterAmp = src.index(after: ampIndex)
			guard afterAmp < src.endIndex,
			      let semiIndex = src[afterAmp...].firstIndex(of: ";")
			else {
				result.append(contentsOf: src[ampIndex...])
				break
			}

			let entityName = String(src[afterAmp ..< semiIndex])
			if let replacement = htmlEntityMap[entityName] {
				result.append(replacement)
				i = src.index(after: semiIndex)
			} else {
				// Not a known entity — keep the '&' and continue
				result.append("&")
				i = afterAmp
			}
		}

		return result
	}

	/// Decode a Base32-encoded string (RFC 4648).
	static func base32(_ src: String) -> Data {
		var result = Data()
		var value: UInt32 = 0
		var bits: UInt32 = 0

		for ch in src.uppercased() {
			let digit: UInt32
			if ch >= "A", ch <= "Z" {
				digit = UInt32(ch.asciiValue! - Character("A").asciiValue!)
			} else if ch >= "2", ch <= "7" {
				digit = 26 + UInt32(ch.asciiValue! - Character("2").asciiValue!)
			} else {
				continue
			}

			value = (value << 5) | digit
			bits += 5
			while bits >= 8 {
				bits -= 8
				result.append(UInt8((value >> bits) & 0xFF))
			}
		}

		return result
	}

	/// Decode a Base64-encoded string.
	static func base64(_ src: String) -> Data {
		let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

		var result = Data()
		var value: UInt32 = 0
		var bits: UInt32 = 0

		for ch in src {
			guard let idx = table.firstIndex(of: ch) else { continue }
			let digit = UInt32(table.distance(from: table.startIndex, to: idx))
			value = (value << 6) | digit
			bits += 6
			while bits >= 8 {
				bits -= 8
				result.append(UInt8((value >> bits) & 0xFF))
			}
		}

		return result
	}

	/// Apply ROT13 cipher to ASCII letters.
	static func rot13(_ src: String) -> String {
		var result = ""
		result.reserveCapacity(src.count)
		for ch in src {
			guard let ascii = ch.asciiValue else {
				result.append(ch)
				continue
			}
			if ascii >= 65, ascii <= 90 { // A-Z
				let rotated = ((ascii - 65 + 13) % 26) + 65
				result.append(Character(UnicodeScalar(rotated)))
			} else if ascii >= 97, ascii <= 122 { // a-z
				let rotated = ((ascii - 97 + 13) % 26) + 97
				result.append(Character(UnicodeScalar(rotated)))
			} else {
				result.append(ch)
			}
		}
		return result
	}

	/// Decode URL percent-encoded components (also converts `+` to space).
	static func urlPart(_ src: String) -> String {
		var result = ""
		result.reserveCapacity(src.count)
		let utf8 = Array(src.utf8)
		var byteIndex = 0

		while byteIndex < utf8.count {
			let byte = utf8[byteIndex]
			if byte == 0x25 /* % */, byteIndex + 2 < utf8.count {
				let hi = hexDigit(utf8[byteIndex + 1])
				let lo = hexDigit(utf8[byteIndex + 2])
				if let hi, let lo {
					result.append(Character(UnicodeScalar(hi << 4 | lo)))
					byteIndex += 3
					continue
				}
			}

			if byte == 0x2B /* + */ {
				result.append(" ")
			} else {
				result.append(Character(UnicodeScalar(byte)))
			}
			byteIndex += 1
		}
		return result
	}

	private static func hexDigit(_ byte: UInt8) -> UInt8? {
		switch byte {
		case 0x30 ... 0x39: byte - 0x30 // 0-9
		case 0x41 ... 0x46: byte - 0x41 + 10 // A-F
		case 0x61 ... 0x66: byte - 0x61 + 10 // a-f
		default: nil
		}
	}
}

// MARK: - URL Encoding

enum TextEncode {
	/// Percent-encode a string for use in a URL, preserving characters in `excluding`.
	static func urlPart(
		_ src: String, excluding: String = "",
	) -> String {
		let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
		let excl = Set(excluding)

		var result = ""
		result.reserveCapacity(src.count)
		for byte in src.utf8 {
			let ch = Character(UnicodeScalar(byte))
			if safe.contains(ch) || excl.contains(ch) {
				result.append(ch)
			} else {
				result.append(String(format: "%%%02X", byte))
			}
		}
		return result
	}
}

// MARK: - Format Size

extension TextUtilities {
	/// Format a byte count as a human-readable string (e.g. "1.5 MiB").
	///
	/// Uses binary units (KiB, MiB, GiB) matching the C++ implementation.
	static func formatSize(_ bytes: Int) -> String {
		if bytes > 1000 * 1024 * 1024 {
			String(format: "%.1f GiB", Double(bytes) / Double(1024 * 1024 * 1024))
		} else if bytes > 1000 * 1024 {
			String(format: "%.1f MiB", Double(bytes) / Double(1024 * 1024))
		} else if bytes > 1000 {
			String(format: "%.1f KiB", Double(bytes) / 1024.0)
		} else {
			"\(bytes) \(bytes == 1 ? "byte" : "bytes")"
		}
	}
}

// MARK: - East Asian Width

extension TextUtilities {
	/// Whether a Unicode scalar has East Asian Wide or Fullwidth property,
	/// occupying two columns in a monospaced terminal/editor.
	///
	/// Port of `text::is_east_asian_width()` from ctype.cc.
	static func isEastAsianWidth(_ scalar: Unicode.Scalar) -> Bool {
		let ch = scalar.value
		guard ch >= 0x1100, ch <= 0x3FFFD else { return false }
		return isInEastAsianRanges(ch)
	}
}

// Using Set<ClosedRange> for the east-asian-width is not efficient for
// `contains` lookups (each ClosedRange is a distinct element). Instead
// we use a flat sorted array of (lo, hi) pairs and binary search.

extension TextUtilities {
	/// Efficient check for East Asian Width using binary search on sorted ranges.
	private static let eastAsianRanges: [(lo: UInt32, hi: UInt32)] = {
		// Fixed code points
		let fixed: [UInt32] = [
			0x2329, 0x232A, 0x23F0, 0x23F3, 0x267F, 0x2693, 0x26A1, 0x26CE,
			0x26D4, 0x26EA, 0x26F5, 0x26FA, 0x26FD, 0x2705, 0x2728, 0x274C,
			0x274E, 0x2757, 0x27B0, 0x27BF, 0x2B50, 0x2B55, 0x3004, 0x3005,
			0x3006, 0x3007, 0x3008, 0x3009, 0x300A, 0x300B, 0x300C, 0x300D,
			0x300E, 0x300F, 0x3010, 0x3011, 0x3014, 0x3015, 0x3016, 0x3017,
			0x3018, 0x3019, 0x301A, 0x301B, 0x301C, 0x301D, 0x3020, 0x3030,
			0x303B, 0x303C, 0x303D, 0x303E, 0x309F, 0x30A0, 0x30FB, 0x30FF,
			0x3250, 0xA015, 0xFE17, 0xFE18, 0xFE19, 0xFE30, 0xFE35, 0xFE36,
			0xFE37, 0xFE38, 0xFE39, 0xFE3A, 0xFE3B, 0xFE3C, 0xFE3D, 0xFE3E,
			0xFE3F, 0xFE40, 0xFE41, 0xFE42, 0xFE43, 0xFE44, 0xFE47, 0xFE48,
			0xFE58, 0xFE59, 0xFE5A, 0xFE5B, 0xFE5C, 0xFE5D, 0xFE5E, 0xFE62,
			0xFE63, 0xFE68, 0xFE69, 0x16FE0, 0x1F004, 0x1F0CF, 0x1F18E,
			0x1F3F4, 0x1F440, 0x1F57A, 0x1F5A4, 0x1F6CC, 0x1F930, 0x1F9C0,
		]
		// Ranges
		let ranges: [(UInt32, UInt32)] = [
			(0x1100, 0x115F), (0x231A, 0x231B), (0x23E9, 0x23EC),
			(0x25FD, 0x25FE), (0x2614, 0x2615), (0x2648, 0x2653),
			(0x26AA, 0x26AB), (0x26BD, 0x26BE), (0x26C4, 0x26C5),
			(0x26F2, 0x26F3), (0x270A, 0x270B), (0x2753, 0x2755),
			(0x2795, 0x2797), (0x2B1B, 0x2B1C), (0x2E80, 0x2E99),
			(0x2E9B, 0x2EF3), (0x2F00, 0x2FD5), (0x2FF0, 0x2FFB),
			(0x3001, 0x3003), (0x3012, 0x3013), (0x301E, 0x301F),
			(0x3021, 0x3029), (0x302A, 0x302D), (0x302E, 0x302F),
			(0x3031, 0x3035), (0x3036, 0x3037), (0x3038, 0x303A),
			(0x3041, 0x3096), (0x3099, 0x309A), (0x309B, 0x309C),
			(0x309D, 0x309E), (0x30A1, 0x30FA), (0x30FC, 0x30FE),
			(0x3105, 0x312D), (0x3131, 0x318E), (0x3190, 0x3191),
			(0x3192, 0x3195), (0x3196, 0x319F), (0x31A0, 0x31BA),
			(0x31C0, 0x31E3), (0x31F0, 0x31FF), (0x3200, 0x321E),
			(0x3220, 0x3229), (0x322A, 0x3247), (0x3251, 0x325F),
			(0x3260, 0x327F), (0x3280, 0x3289), (0x328A, 0x32B0),
			(0x32B1, 0x32BF), (0x32C0, 0x32FE), (0x3300, 0x33FF),
			(0x3400, 0x4DB5), (0x4DB6, 0x4DBF), (0x4E00, 0x9FD5),
			(0x9FD6, 0x9FFF), (0xA000, 0xA014), (0xA016, 0xA48C),
			(0xA490, 0xA4C6), (0xA960, 0xA97C), (0xAC00, 0xD7A3),
			(0xF900, 0xFA6D), (0xFA6E, 0xFA6F), (0xFA70, 0xFAD9),
			(0xFADA, 0xFAFF), (0xFE10, 0xFE16), (0xFE31, 0xFE32),
			(0xFE33, 0xFE34), (0xFE45, 0xFE46), (0xFE49, 0xFE4C),
			(0xFE4D, 0xFE4F), (0xFE50, 0xFE52), (0xFE54, 0xFE57),
			(0xFE5F, 0xFE61), (0xFE64, 0xFE66), (0xFE6A, 0xFE6B),
			(0x17000, 0x187EC), (0x18800, 0x18AF2), (0x1B000, 0x1B001),
			(0x1F191, 0x1F19A), (0x1F200, 0x1F202), (0x1F210, 0x1F23B),
			(0x1F240, 0x1F248), (0x1F250, 0x1F251), (0x1F300, 0x1F320),
			(0x1F32D, 0x1F335), (0x1F337, 0x1F37C), (0x1F37E, 0x1F393),
			(0x1F3A0, 0x1F3CA), (0x1F3CF, 0x1F3D3), (0x1F3E0, 0x1F3F0),
			(0x1F3F8, 0x1F3FA), (0x1F3FB, 0x1F3FF), (0x1F400, 0x1F43E),
			(0x1F442, 0x1F4FC), (0x1F4FF, 0x1F53D), (0x1F54B, 0x1F54E),
			(0x1F550, 0x1F567), (0x1F595, 0x1F596), (0x1F5FB, 0x1F5FF),
			(0x1F600, 0x1F64F), (0x1F680, 0x1F6C5), (0x1F6D0, 0x1F6D2),
			(0x1F6EB, 0x1F6EC), (0x1F6F4, 0x1F6F6), (0x1F910, 0x1F91E),
			(0x1F920, 0x1F927), (0x1F933, 0x1F93E), (0x1F940, 0x1F94B),
			(0x1F950, 0x1F95E), (0x1F980, 0x1F991), (0x20000, 0x2A6D6),
			(0x2A6D7, 0x2A6FF), (0x2A700, 0x2B734), (0x2B735, 0x2B73F),
			(0x2B740, 0x2B81D), (0x2B81E, 0x2B81F), (0x2B820, 0x2CEA1),
			(0x2CEA2, 0x2F7FF), (0x2F800, 0x2FA1D), (0x2FA1E, 0x2FFFD),
			(0x30000, 0x3FFFD),
		]

		var all = ranges.map { (lo: $0.0, hi: $0.1) }
		for ch in fixed {
			all.append((lo: ch, hi: ch))
		}
		return all.sorted { $0.lo < $1.lo }
	}()

	/// Binary search on sorted ranges.
	fileprivate static func isInEastAsianRanges(_ ch: UInt32) -> Bool {
		var lo = 0
		var hi = eastAsianRanges.count - 1
		while lo <= hi {
			let mid = (lo + hi) / 2
			let r = eastAsianRanges[mid]
			if ch < r.lo {
				hi = mid - 1
			} else if ch > r.hi {
				lo = mid + 1
			} else {
				return true
			}
		}
		return false
	}
}

// MARK: - Text Utilities Namespace

/// Namespace for text processing utilities.
enum TextUtilities {
	/// Column width of a Unicode scalar (1 or 2 for east-asian-width characters).
	static func columnWidth(of scalar: Unicode.Scalar) -> Int {
		isEastAsianWidth(scalar) ? 2 : 1
	}

	/// Calculate soft line break positions for word-wrapping text.
	///
	/// Port of `text::soft_breaks()` from parse.cc.
	///
	/// - Parameters:
	///   - string: The text to wrap.
	///   - width: Maximum column width.
	///   - tabSize: Number of columns per tab stop.
	///   - prefixSize: Additional indent applied after the first break.
	/// - Returns: UTF-8 byte offsets where soft line breaks should be inserted.
	static func softBreaks(
		in string: String, width: Int, tabSize: Int = 4, prefixSize: Int = 0,
	) -> [Int] {
		var result = [Int]()
		var remainingWidth = width
		var currentPrefixSize = prefixSize

		var col = 0
		var len = 0
		var spaceCol = 0
		var spaceLen = 0

		for scalar in string.unicodeScalars {
			let prevLen = len
			let prevCol = col

			let scalarLen = Int(scalar.utf8.count)
			len += scalarLen

			if scalar == "\t" {
				col += tabSize - (col % tabSize)
			} else if scalar == "\n" {
				col = 0
				spaceLen = len
				spaceCol = col
				continue
			} else {
				col += isEastAsianWidth(scalar) ? 2 : 1
			}

			if col > remainingWidth {
				if spaceCol == 0 {
					// No space found — break at current position
					result.append(prevLen)
					remainingWidth -= currentPrefixSize
					currentPrefixSize = 0
					col = col - prevCol
				} else {
					result.append(spaceLen)
					remainingWidth -= currentPrefixSize
					currentPrefixSize = 0
					col = col - spaceCol
					spaceCol = 0
				}
			} else if scalar == " " {
				spaceLen = len
				spaceCol = col
			}
		}

		return result
	}

	/// Toggle the case of characters in a string.
	///
	/// Runs of uppercase characters become lowercase and vice versa.
	/// Port of `text::opposite_case()` from case.cc.
	static func oppositeCase(_ string: String) -> String {
		guard !string.isEmpty else { return "" }

		var result = ""
		result.reserveCapacity(string.count)
		var currentRun = ""
		var isCurrentUpper = true

		func flushRun() {
			if !currentRun.isEmpty {
				result += isCurrentUpper
					? currentRun.lowercased()
					: currentRun.uppercased()
				currentRun = ""
			}
		}

		for ch in string {
			if ch.isUppercase {
				if !isCurrentUpper {
					flushRun()
					isCurrentUpper = true
				}
				currentRun.append(ch)
			} else if ch.isLowercase {
				if isCurrentUpper {
					flushRun()
					isCurrentUpper = false
				}
				currentRun.append(ch)
			} else {
				currentRun.append(ch)
			}
		}
		flushRun()
		return result
	}

	/// Whether a character is a "word character" (letter, digit, or underscore).
	static func isWordChar(_ ch: Character) -> Bool {
		ch.isLetter || ch.isNumber || ch == "_"
	}

	/// Whether a character is whitespace (space, tab, newline, etc.).
	static func isWhitespace(_ ch: Character) -> Bool {
		ch.isWhitespace
	}
}

// MARK: - Indent Style

/// Describes an indentation style (tabs or spaces, with size configuration).
///
/// Port of `text::indent_t` from indent.{h,cc}.
struct IndentStyle: Sendable, Equatable {
	/// Number of columns each visual tab stop occupies.
	var tabSize: Int
	/// Number of columns per indent level.
	var indentSize: Int
	/// If true, use spaces instead of tabs.
	var softTabs: Bool

	init(tabSize: Int = 4, indentSize: Int = 4, softTabs: Bool = false) {
		self.tabSize = tabSize
		self.indentSize = indentSize
		self.softTabs = softTabs
	}

	/// Create an indent string at the given column for a number of indent units.
	///
	/// Port of `text::indent_t::create()` from indent.cc.
	func create(atColumn: Int = 0, units: Int = 1) -> String {
		let baseColumn = atColumn - (atColumn % indentSize)
		let desiredColumn = baseColumn + units * indentSize

		if softTabs {
			return String(repeating: " ", count: desiredColumn - atColumn)
		} else if indentSize == tabSize {
			return String(repeating: "\t", count: units)
		} else {
			let desiredBase = desiredColumn - (desiredColumn % tabSize)
			if desiredBase <= atColumn {
				return String(repeating: " ", count: desiredColumn - atColumn)
			}
			let tabs = desiredBase / tabSize - baseColumn / tabSize
			let spaces = desiredColumn - desiredBase
			return String(repeating: "\t", count: tabs)
				+ String(repeating: " ", count: spaces)
		}
	}
}
