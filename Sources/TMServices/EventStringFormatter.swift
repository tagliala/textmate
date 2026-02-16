#if canImport(AppKit)
import AppKit

// MARK: - Event String Formatter

/// Parses, normalizes, and renders TextMate's keyboard event string format.
///
/// Event strings use prefix characters for modifier flags followed by the key:
/// - `$` = Shift
/// - `^` = Control
/// - `~` = Option
/// - `@` = Command
/// - `#` = NumericPad
///
/// For example, `"@$s"` means ⌘⇧S.
///
/// Port of `Frameworks/ns/src/event.h` / `event.mm`.
public enum EventStringFormatter {
	// MARK: - Key Glyphs

	/// Named key → glyph mapping.
	private static let keyGlyphs: [(name: String, glyph: String)] = [
		("pb_enter", "⌤"),
		("left", "←"),
		("up", "↑"),
		("right", "→"),
		("down", "↓"),
		("ib_left", "⇠"),
		("ib_up", "⇡"),
		("ib_right", "⇢"),
		("ib_down", "⇣"),
		("home", "↖"),
		("end", "↘"),
		("return", "↩"),
		("pageup", "⇞"),
		("pagedown", "⇟"),
		("tab", "⇥"),
		("backtab", "⇤"),
		("shift", "⇧"),
		("control", "⌃"),
		("enter", "⌅"),
		("command", "⌘"),
		("modifier", "⌥"),
		("backspace", "⌫"),
		("delete", "⌦"),
		("escape", "⎋"),
		("numlock", "⌧"),
		("help", "?⃝"),
		("space", "Space"),
	]

	private static func glyphNamed(_ name: String) -> String {
		keyGlyphs.first(where: { $0.name == name })?.glyph ?? "�"
	}

	// MARK: - Unicode Key Code Mappings

	/// Maps Unicode function key codes to human-readable glyph names.
	private static let keyCodeNames: [(code: UInt32, name: String)] = [
		(UInt32(NSUpArrowFunctionKey), "up"),
		(UInt32(NSDownArrowFunctionKey), "down"),
		(UInt32(NSLeftArrowFunctionKey), "left"),
		(UInt32(NSRightArrowFunctionKey), "right"),
		(UInt32(NSDeleteFunctionKey), "delete"),
		(UInt32(NSHomeFunctionKey), "home"),
		(UInt32(NSEndFunctionKey), "end"),
		(UInt32(NSPageUpFunctionKey), "pageup"),
		(UInt32(NSPageDownFunctionKey), "pagedown"),
		(UInt32(NSClearLineFunctionKey), "numlock"),
		(UInt32(NSHelpFunctionKey), "help"),
		(UInt32(NSTabCharacter), "tab"),
		(UInt32(NSCarriageReturnCharacter), "return"),
		(UInt32(NSEnterCharacter), "enter"),
		(UInt32(NSBackTabCharacter), "backtab"),
		(0x1B, "escape"), // ESC
		(UInt32(NSDeleteCharacter), "backspace"),
		(0x20, "space"),
	]

	// MARK: - Modifier Flags

	/// Ordered modifier flags for string representation.
	/// The order matches the C++ `EventFlags` array: NumPad, Control, Option, Shift, Command.
	private static let eventFlags: [(flag: NSEvent.ModifierFlags, symbol: Character)] = [
		(.numericPad, "#"),
		(.control, "^"),
		(.option, "~"),
		(.shift, "$"),
		(.command, "@"),
	]

	/// Convert modifier flags to their prefix string (e.g. `"^~@"`).
	private static func flagsToString(_ flags: NSEvent.ModifierFlags) -> String {
		var result = ""
		for (flag, symbol) in eventFlags {
			if flags.contains(flag) {
				result.append(symbol)
			}
		}
		return result
	}

	/// Convert a single prefix character to its modifier flag.
	private static func charToFlag(_ ch: Character) -> NSEvent.ModifierFlags {
		switch ch {
		case "$": .shift
		case "^": .control
		case "~": .option
		case "@": .command
		case "#": .numericPad
		default: []
		}
	}

	// MARK: - Parsing

	/// Result of parsing an event string.
	public struct ParsedEventString: Sendable, Equatable {
		/// The modifier flags.
		public var flags: NSEvent.ModifierFlags
		/// The key character(s) after the modifier prefix.
		public var key: String

		public init(flags: NSEvent.ModifierFlags = [], key: String = "") {
			self.flags = flags
			self.key = key
		}
	}

	/// Parse an event string into flags + key.
	///
	/// - Parameters:
	///   - eventString: The event string to parse (e.g. `"@s"`, `"^~x"`).
	///   - legacy: If `true`, handles backslash-escaped characters (legacy format).
	/// - Returns: The parsed result.
	public static func parse(_ eventString: String, legacy: Bool = false) -> ParsedEventString {
		var flags: NSEvent.ModifierFlags = []

		if legacy {
			var key = ""
			var scanningFlags = true
			var real = true

			for ch in eventString {
				let flag = charToFlag(ch)
				if scanningFlags, flag != [] {
					flags.insert(flag)
				} else {
					scanningFlags = false
					if real || ch != "\\" {
						key.append(ch)
						real = true
					} else {
						real = false
					}
				}
			}
			return ParsedEventString(flags: flags, key: key)
		} else {
			let flagChars: Set<Character> = ["$", "^", "~", "@", "#"]
			var i = eventString.startIndex

			while i < eventString.endIndex, flagChars.contains(eventString[i]) {
				flags.insert(charToFlag(eventString[i]))
				i = eventString.index(after: i)
			}

			// If all chars are flags, treat last one as the key
			if i == eventString.endIndex, !eventString.isEmpty {
				i = eventString.index(before: eventString.endIndex)
				// Re-parse: the last char could also be a flag char used as a key
				let lastChar = eventString[i]
				let flag = charToFlag(lastChar)
				if flag != [] {
					flags.remove(flag)
				}
			}

			let key = String(eventString[i...])
			return ParsedEventString(flags: flags, key: key)
		}
	}

	// MARK: - Create

	/// Create an event string from a key and modifier flags.
	///
	/// - Parameters:
	///   - key: The key character(s).
	///   - flags: The modifier flags.
	/// - Returns: The event string (e.g. `"@s"`).
	public static func create(key: String, flags: NSEvent.ModifierFlags) -> String {
		flagsToString(flags) + key
	}

	// MARK: - Normalize

	/// Normalize an event string by re-parsing (with legacy backslash support)
	/// and re-emitting in canonical form.
	///
	/// Also normalizes special key codes:
	/// - `NSBackspaceCharacter` → `NSDeleteCharacter`
	/// - `NSNewlineCharacter` → `NSCarriageReturnCharacter`
	///
	/// - Parameters:
	///   - eventString: The event string to normalize.
	///   - startOfKey: If non-nil, set to the index where the key begins.
	/// - Returns: The normalized event string.
	public static func normalize(_ eventString: String, startOfKey: inout Int?) -> String {
		var parsed = parse(eventString, legacy: true)

		if !parsed.key.isEmpty {
			let code = parsed.key.unicodeScalars.first?.value ?? 0
			if code == UInt32(NSBackspaceCharacter) {
				parsed.key = String(UnicodeScalar(NSDeleteCharacter)!)
			} else if code == UInt32(NSNewlineCharacter) {
				parsed.key = String(UnicodeScalar(NSCarriageReturnCharacter)!)
			}
		}

		let modifierString = parsed.key.isEmpty ? "" : flagsToString(parsed.flags)
		startOfKey = modifierString.count
		return modifierString + parsed.key
	}

	/// Normalize without tracking key start position.
	public static func normalize(_ eventString: String) -> String {
		var startOfKey: Int?
		return normalize(eventString, startOfKey: &startOfKey)
	}

	// MARK: - Glyph Rendering

	/// Convert modifier flags to their glyph representation.
	///
	/// Uses display order: ⌃ ⌥ ⇧ ⌘ (matching macOS conventions).
	public static func glyphsForFlags(_ flags: NSEvent.ModifierFlags) -> String {
		var result = ""
		if flags.contains(.control) { result += glyphNamed("control") }
		if flags.contains(.option) { result += glyphNamed("modifier") }
		if flags.contains(.shift) { result += glyphNamed("shift") }
		if flags.contains(.command) { result += glyphNamed("command") }
		return result
	}

	/// Convert a key string to its glyph representation.
	///
	/// Maps function keys (arrows, delete, etc.) to symbols, and
	/// F1–F35 to their names.
	private static func glyphsForKey(_ key: String, numpad: Bool = false) -> String {
		guard !key.isEmpty else { return key }

		var result = key
		let code = key.unicodeScalars.first?.value ?? 0

		for (keyCode, keyName) in keyCodeNames {
			if code == keyCode {
				result = glyphNamed(keyName)
				break
			}
		}

		if code == 0xA0 {
			result = "nbsp"
		} else if code >= UInt32(NSF1FunctionKey), code <= UInt32(NSF35FunctionKey) {
			result = "F\(code - UInt32(NSF1FunctionKey) + 1)"
		}

		if numpad {
			result += "\u{20E3}" // COMBINING ENCLOSING KEYCAP
		}

		return result
	}

	/// Convert an event string to human-readable glyph form.
	///
	/// For example:
	/// - `"@s"` → `"⌘S"`
	/// - `"^~\u{F700}"` → `"⌃⌥↑"` (Ctrl+Option+Up)
	///
	/// - Parameters:
	///   - eventString: The event string.
	///   - startOfKey: If non-nil, set to the index where the key glyph begins.
	/// - Returns: The glyph string.
	public static func glyphsForEventString(
		_ eventString: String,
		startOfKey: inout Int?,
	) -> String {
		var parsed = parse(eventString)

		// Auto-detect shift for uppercase letters
		if !parsed.flags.contains(.shift) {
			let lowered = parsed.key.lowercased()
			if parsed.key != lowered {
				// Key is uppercase — add shift flag
				parsed.flags.insert(.shift)
			} else {
				// Try to uppercase it
				let uppered = parsed.key.uppercased()
				if parsed.key != uppered {
					parsed.key = uppered
				}
			}
		}

		let modifierGlyphs = glyphsForFlags(parsed.flags)
		startOfKey = modifierGlyphs.count

		let keyGlyph = glyphsForKey(
			parsed.key,
			numpad: parsed.flags.contains(.numericPad),
		)
		return modifierGlyphs + keyGlyph
	}

	/// Convert an event string to human-readable glyph form (without tracking key position).
	public static func glyphsForEventString(_ eventString: String) -> String {
		var startOfKey: Int?
		return glyphsForEventString(eventString, startOfKey: &startOfKey)
	}

	// MARK: - Attributed String for Menu Display

	/// Create a right-aligned attributed string suitable for menu
	/// key equivalent display.
	///
	/// Port of C++ `OakAttributedStringForEventString`.
	public static func attributedString(
		for eventString: String,
		font: NSFont,
	) -> NSAttributedString {
		let functionKeys: Set<String> = [
			"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8",
			"F9", "F10", "F11", "F12", "F13", "F14", "F15",
		]

		var keyStart: Int? = 0
		let glyphString = glyphsForEventString(eventString, startOfKey: &keyStart)
		let keyStartIndex = keyStart ?? 0

		let flagsStr = String(glyphString.prefix(keyStartIndex))
		let keyStr = String(glyphString.dropFirst(keyStartIndex))

		let style: [NSAttributedString.Key: Any] = [.font: font]
		let str = NSMutableAttributedString(
			string: "\(flagsStr)\(keyStr)\t",
			attributes: style,
		)

		let flagsRange = NSRange(location: 0, length: (flagsStr as NSString).length)
		let keyRange = NSRange(location: NSMaxRange(flagsRange), length: (keyStr as NSString).length)

		if functionKeys.contains(keyStr) {
			if let glyphInfo = NSGlyphInfo(glyphName: keyStr, for: font, baseString: keyStr) {
				str.addAttribute(.glyphInfo, value: glyphInfo, range: keyRange)
			}
		}

		let flagsWidth = str.attributedSubstring(from: flagsRange).size().width
		let keyWidth = font.maximumAdvancement.width

		let pStyle = NSMutableParagraphStyle()
		pStyle.alignment = .right
		pStyle.tabStops = [
			NSTextTab(type: .leftTabStopType, location: ceil(flagsWidth + keyWidth)),
		]
		str.addAttribute(
			.paragraphStyle,
			value: pStyle,
			range: NSRange(location: 0, length: str.length),
		)

		return str
	}
}
#endif
