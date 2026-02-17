import Foundation

// MARK: - PlistSerializer

/// Serializes `PlistValue` into the ASCII (OpenStep) plist format.
///
/// Replaces the C++ `boost::to_s(plist::any_t)` and related pretty‑printing code.
public enum PlistSerializer {
	/// Formatting options for serialization.
	public struct Options: OptionSet, Sendable {
		public let rawValue: Int
		public init(rawValue: Int) {
			self.rawValue = rawValue
		}

		/// Prefer single‑quoted strings where possible.
		public static let preferSingleQuotedStrings = Options(rawValue: 1 << 0)
		/// Emit everything on a single line.
		public static let singleLine = Options(rawValue: 1 << 1)
	}

	/// Serialize a plist value to an ASCII plist string.
	///
	/// - Parameters:
	///   - value: The plist value to serialize.
	///   - options: Formatting options.
	///   - keySortOrder: Optional key ordering for dictionary output.
	/// - Returns: ASCII plist string representation.
	public static func serialize(
		_ value: PlistValue,
		options: Options = [],
		keySortOrder: [String] = [],
	) -> String {
		let ctx = Context(
			options: options,
			keySortOrder: keySortOrder,
			indent: 0,
			isKey: false,
		)
		return format(value, context: ctx)
	}
}

// MARK: - Internal formatting

private struct Context {
	let options: PlistSerializer.Options
	let keySortOrder: [String]
	let indent: Int
	let isKey: Bool

	var isSingleLine: Bool {
		options.contains(.singleLine)
	}

	var indentString: String {
		String(repeating: "\t", count: indent)
	}

	func withIndent(_ n: Int, isKey: Bool = false) -> Context {
		Context(options: options, keySortOrder: keySortOrder, indent: n, isKey: isKey)
	}

	func withSingleLine() -> Context {
		Context(
			options: options.union(.singleLine),
			keySortOrder: keySortOrder,
			indent: indent,
			isKey: isKey,
		)
	}
}

// MARK: Composite / single‑line checks

private func isComposite(_ value: PlistValue) -> Bool {
	switch value {
	case .array, .dictionary: true
	default: false
	}
}

private func fitsSingleLine(_ value: PlistValue) -> Bool {
	switch value {
	case let .array(arr):
		let allSingle = arr.allSatisfy { fitsSingleLine($0) }
		let anyComposite = arr.contains(where: { isComposite($0) })
		return allSingle && (arr.count <= 1 || !anyComposite)
	case let .dictionary(dict):
		if dict.count > 1 { return false }
		return dict.values.allSatisfy { fitsSingleLine($0) }
	default:
		return true
	}
}

// MARK: String escaping

private func doubleQuoteEscape(_ ch: Character) -> String {
	switch ch {
	case "\0": return "\\000"
	case "\t": return "\\t"
	case "\n": return "\\n"
	case "\u{0C}": return "\\f"
	case "\r": return "\\r"
	case "\u{1B}": return "\\033"
	case "\\": return "\\\\"
	case "\"": return "\\\""
	default:
		let scalars = ch.unicodeScalars
		guard let scalar = scalars.first, scalars.count == 1 else {
			return String(ch)
		}
		let val = scalar.value
		if val >= 0x20 && val <= 0x7E {
			return String(ch)
		} else if val < 0x20 || (val > 0x7F && scalar.properties.generalCategory == .control) {
			return String(format: "\\x%02X", val)
		} else if val >= 0xE000 && val <= 0xF8FF {
			return String(format: "\\U%04X", val)
		} else if (val >= 0x0F0000 && val <= 0x0FFFFD) || (val >= 0x100000 && val <= 0x10FFFD) {
			return String(format: "\\U%06X", val)
		}
		return String(ch)
	}
}

private func singleQuoteEscape(_ ch: Character) -> String {
	ch == "'" ? "''" : String(ch)
}

private func escapeString(
	_ str: String,
	escaper: (Character) -> String,
	quote: String = "",
) -> String {
	var result = quote
	for ch in str {
		result += escaper(ch)
	}
	result += quote
	return result
}

private func prettyString(_ str: String, options: PlistSerializer.Options) -> String {
	if options.contains(.preferSingleQuotedStrings) {
		let noSingleQuotes = !str.contains("'")
		let doubleEscaped = escapeString(str, escaper: doubleQuoteEscape)
		if noSingleQuotes || str != doubleEscaped {
			return escapeString(str, escaper: singleQuoteEscape, quote: "'")
		}
	}
	return escapeString(str, escaper: doubleQuoteEscape, quote: "\"")
}

private func prettyKey(_ key: String, options: PlistSerializer.Options) -> String {
	var shouldQuote = false
	var allDigits = true
	var first = true

	for ch in key {
		let scalars = ch.unicodeScalars
		guard let scalar = scalars.first else { continue }
		let val = scalar.value

		if !val.isDigit { allDigits = false }

		var localShouldQuote = true
		if (0x61 ... 0x7A).contains(val) // a-z
			|| (0x41 ... 0x5A).contains(val) // A-Z
			|| val == 0x5F // _
		{
			localShouldQuote = false
		}

		if !first && (val == 0x2E || val == 0x2D) { // . or -
			localShouldQuote = false
		}
		first = false
		shouldQuote = shouldQuote || localShouldQuote
	}

	if shouldQuote, !allDigits {
		return prettyString(key, options: options)
	}
	return key
}

private extension UInt32 {
	var isDigit: Bool {
		0x30 ... 0x39 ~= self
	}
}

// MARK: Data formatting

private func prettyData(_ data: Data) -> String {
	var res = "<"
	var i = 3
	for byte in data {
		i += 1
		if i != 4, i % 4 == 0 { res.append(" ") }
		res += String(format: "%02X", byte)
	}
	return res + ">"
}

// MARK: Key sort comparator

private struct KeyComparator {
	let ranks: [String: Int]

	init(_ order: [String]) {
		var r = [String: Int]()
		for (i, k) in order.enumerated() {
			r[k] = i
		}
		ranks = r
	}

	func compare(_ lhs: String, _ rhs: String) -> Bool {
		let lhsRank = ranks[lhs]
		let rhsRank = ranks[rhs]
		if let lr = lhsRank, let rr = rhsRank { return lr < rr }
		if lhsRank != nil { return true }
		if rhsRank != nil { return false }
		if let li = Int(lhs), let ri = Int(rhs) { return li < ri }
		return lhs < rhs
	}
}

// MARK: Main format function

private func format(_ value: PlistValue, context ctx: Context) -> String {
	switch value {
	case let .bool(v):
		return v ? ":true" : ":false"

	case let .int(v):
		return String(v)

	case let .string(v):
		return prettyString(v, options: ctx.options)

	case let .data(v):
		return prettyData(v)

	case let .date(v):
		let fmt = DateFormatter()
		fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
		fmt.locale = Locale(identifier: "en_US_POSIX")
		return "@" + fmt.string(from: v)

	case let .array(arr):
		return formatArray(arr, context: ctx)

	case let .dictionary(dict):
		return formatDictionary(dict, context: ctx)
	}
}

private func formatArray(_ arr: [PlistValue], context ctx: Context) -> String {
	let singleLine = ctx.isSingleLine

	if arr.isEmpty {
		return "( )"
	}

	if singleLine || fitsSingleLine(.array(arr)) {
		var parts = [String]()
		var line = ""
		var wrap = 0

		for (i, item) in arr.enumerated() {
			if i > 0 { line += ", " }

			if !singleLine, line.count - wrap > 80 {
				// Remove trailing space, add newline
				if line.hasSuffix(" ") {
					line.removeLast()
				}
				line += "\n" + ctx.indentString + "\t"
				wrap = line.count
			}

			line += format(item, context: ctx.withSingleLine())
		}

		var body = " " + line + " "
		if !singleLine, body.contains("\n") {
			if body.hasSuffix(" ") { body.removeLast() }
			body += "\n" + ctx.indentString
		}
		_ = parts // suppress warning
		return "(" + body + ")"
	} else {
		var lines = [String]()
		for item in arr {
			let s = ctx.indentString + "\t"
				+ format(item, context: ctx.withIndent(ctx.indent + 1))
				+ ","
			lines.append(s)
		}
		return "(\n" + lines.joined(separator: "\n") + "\n" + ctx.indentString + ")"
	}
}

private func formatDictionary(
	_ dict: PlistDictionary,
	context ctx: Context,
) -> String {
	let singleLine = ctx.isSingleLine

	if dict.isEmpty {
		return "{ }"
	}

	if singleLine || fitsSingleLine(.dictionary(dict)) {
		var prefix = if singleLine || ctx.indent == 0 || ctx.isKey {
			" "
		} else {
			"\t"
		}

		var res = prefix
		for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
			let k = prettyKey(key, options: ctx.options.union(.singleLine))
			let v = format(value, context: ctx.withSingleLine())
			res += "\(k) = \(v); "
		}
		return "{" + res + "}"
	} else {
		let comp = KeyComparator(ctx.keySortOrder)
		let sorted = dict.sorted { comp.compare($0.key, $1.key) }

		var lines = [String]()
		for (key, value) in sorted {
			let k = prettyKey(key, options: ctx.options)
			let v = format(
				value,
				context: ctx.withIndent(ctx.indent + 1, isKey: true),
			)
			lines.append("\t\(k) = \(v);")
		}

		let prefix = ctx.isKey ? "\n" + ctx.indentString : ""
		var body = ""
		for line in lines {
			body += ctx.indentString + line + "\n"
		}
		return "{" + prefix + body + ctx.indentString + "}"
	}
}
