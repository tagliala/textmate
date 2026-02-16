import Foundation

// MARK: - Format String Expander

/// Evaluates a format string AST, expanding variables, applying transforms,
/// handling case changes, and tracking snippet fields/mirrors.
///
/// Ports the C++ `expand_visitor` from `format_string.cc`.
/// Used for regex replacement strings, grammar transforms, and snippet body
/// expansion.
public final class FormatStringExpander: @unchecked Sendable {
	/// Variable lookup callback: given a name, returns its value or nil.
	public typealias VariableLookup = (String) -> String?

	/// Command execution callback for snippet code blocks.
	public typealias CommandRunner = (String) -> String

	/// The variable lookup function.
	private let variable: VariableLookup
	/// Optional command runner for `` `code` `` blocks.
	private let commandRunner: CommandRunner?

	/// Accumulated result text.
	private(set) var result: String = ""
	/// Pending case changes.
	private var caseChanges: [(Int, CaseChangeType)] = []

	/// Rank counter for snippet field ordering.
	private(set) var rankCount: Int = 0
	/// Primary snippet fields (first occurrence of each tab stop index).
	private(set) var fields: [Int: SnippetField] = [:]
	/// Mirror snippet fields (subsequent occurrences sharing the same index).
	private(set) var mirrors: [(Int, SnippetField)] = []
	/// Ambiguous fields (tab stops with empty content before we know if they are fields or mirrors).
	private(set) var ambiguous: [(Int, SnippetField)] = []

	/// Creates an expander with the given variable lookup.
	public init(variable: @escaping VariableLookup, commandRunner: CommandRunner? = nil) {
		self.variable = variable
		self.commandRunner = commandRunner
	}

	// MARK: - Public API

	/// Traverses the AST nodes, appending to the result.
	public func traverse(_ nodes: [FormatStringNode]) {
		for node in nodes {
			visit(node)
		}
	}

	/// Applies accumulated case changes to the result string.
	public func handleCaseChanges() {
		guard !caseChanges.isEmpty else { return }
		caseChanges.append((result.count, .none))

		var tmp = ""
		let chars = Array(result)
		var prev = 0
		var style: CaseChangeType = .none

		for (offset, newStyle) in caseChanges {
			if prev < offset {
				let isOnlyNext = style == .upperNext || style == .lowerNext
				let to = isOnlyNext ? min(prev + 1, offset) : offset

				let slice = String(chars[prev ..< to])
				switch style {
				case .none:
					tmp += slice
				case .upperNext, .upper:
					tmp += slice.uppercased()
				case .lowerNext, .lower:
					tmp += slice.lowercased()
				}

				// For "next" styles, copy remaining chars unchanged
				if isOnlyNext, to < offset {
					tmp += String(chars[to ..< offset])
				}
			}
			prev = offset
			style = newStyle
		}

		result = tmp
	}

	/// Performs regex replacement using format nodes.
	public func replace(
		source: String,
		pattern: NSRegularExpression,
		format: [FormatStringNode],
		repeat: Bool,
	) {
		let nsSource = source as NSString

		var searchStart = 0
		var lastMatchEnd = 0

		while searchStart <= nsSource.length {
			let searchRange = NSRange(location: searchStart, length: nsSource.length - searchStart)
			guard let match = pattern.firstMatch(in: source, range: searchRange) else {
				break
			}

			// Append text before the match
			if match.range.location > lastMatchEnd {
				let beforeRange = NSRange(location: lastMatchEnd, length: match.range.location - lastMatchEnd)
				result += nsSource.substring(with: beforeRange)
			}

			// Build captures map, tracking which captures didn't match
			var eclipsed = Set<String>()
			var captures = [String: String]()
			for i in 0 ..< match.numberOfRanges {
				let r = match.range(at: i)
				if r.location == NSNotFound {
					eclipsed.insert(String(i))
				} else {
					captures[String(i)] = nsSource.substring(with: r)
				}
			}

			// Expand the format string with captures as variables
			let getVariable: VariableLookup = { name in
				if eclipsed.contains(name) { return nil }
				return captures[name] ?? self.variable(name)
			}

			let sub = FormatStringExpander(variable: getVariable, commandRunner: commandRunner)
			sub.traverse(format)
			sub.handleCaseChanges()
			result += sub.result

			lastMatchEnd = match.range.location + match.range.length
			searchStart = lastMatchEnd

			if !`repeat` { break }

			// Handle empty matches
			if match.range.length == 0 {
				if searchStart >= nsSource.length { break }
				let charRange = NSRange(location: searchStart, length: 1)
				result += nsSource.substring(with: charRange)
				searchStart += 1
			}
		}

		// Append remaining text
		if lastMatchEnd < nsSource.length {
			let remainRange = NSRange(location: lastMatchEnd, length: nsSource.length - lastMatchEnd)
			result += nsSource.substring(with: remainRange)
		}
	}

	// MARK: - Node Visiting

	private func visit(_ node: FormatStringNode) {
		switch node {
		case let .text(text):
			result += text

		case let .variable(name):
			if let value = variable(name) {
				result += value
			}

		case let .variableTransform(name, patternNodes, format, options):
			// Evaluate pattern nodes to get the regex string
			let patternExpander = FormatStringExpander(variable: variable, commandRunner: commandRunner)
			patternExpander.traverse(patternNodes)
			patternExpander.handleCaseChanges()
			let patternStr = patternExpander.result

			if let regex = try? NSRegularExpression(pattern: patternStr, options: convertOptions(options)) {
				let source = variable(name) ?? ""
				replace(source: source, pattern: regex, format: format, repeat: options.contains(.global))
			}

		case let .variableFallback(name, fallback):
			if let value = variable(name) {
				result += value
			} else {
				traverse(fallback)
			}

		case let .variableCondition(name, ifSet, ifNotSet):
			if variable(name) != nil {
				traverse(ifSet)
			} else {
				traverse(ifNotSet)
			}

		case let .variableChange(name, change):
			if var value = variable(name) {
				if change.contains(.upcase) { value = value.uppercased() }
				if change.contains(.downcase) { value = value.lowercased() }
				if change.contains(.capitalize) { value = Self.capitalize(value) }
				if change.contains(.asciify) { value = Self.asciify(value) }
				if change.contains(.urlEncode) { value = Self.urlEncode(value) }
				if change.contains(.shellEscape) { value = Self.shellEscape(value) }
				if change.contains(.relative) { value = Self.relativeTime(value) }
				if change.contains(.number) { value = Self.formatNumber(value) }
				if change.contains(.duration) { value = Self.formatDuration(value) }
				if change.contains(.dirname) {
					value = (value as NSString).deletingLastPathComponent
				}
				if change.contains(.basename) {
					value = (value as NSString).lastPathComponent
				}
				result += value
			}

		case let .caseChange(type):
			caseChanges.append((result.count, type))

		// MARK: Snippet Nodes

		case let .placeholder(tabIndex, content):
			let from = SnippetPosition(offset: result.count, rank: { rankCount += 1
				return rankCount
			}())
			if fields[tabIndex] == nil {
				traverse(content)
			}
			let to = SnippetPosition(offset: result.count, rank: { rankCount += 2
				return rankCount
			}())
			let field = SnippetField(index: tabIndex, range: SnippetRange(from: from, to: to))
			if fields[tabIndex] != nil {
				mirrors.append((tabIndex, field))
			} else if content.isEmpty {
				ambiguous.append((tabIndex, field))
			} else {
				fields[tabIndex] = field
			}

		case let .placeholderTransform(tabIndex, pattern, format, options):
			let pos = SnippetPosition(offset: result.count, rank: { rankCount += 1
				return rankCount
			}())
			let toPos = SnippetPosition(offset: result.count, rank: { rankCount += 2
				return rankCount
			}())
			let field = SnippetField(
				index: tabIndex,
				range: SnippetRange(from: pos, to: toPos),
				transform: SnippetTransformInfo(pattern: pattern, format: format, options: options),
			)
			mirrors.append((tabIndex, field))

		case let .placeholderChoice(tabIndex, choices):
			guard fields[tabIndex] == nil else { return }

			var allChoices: [String] = []
			for choice in choices {
				let sub = FormatStringExpander(variable: variable, commandRunner: commandRunner)
				sub.traverse(choice)
				sub.handleCaseChanges()
				allChoices.append(sub.result)
			}

			let pos = SnippetPosition(offset: result.count, rank: { rankCount += 1
				return rankCount
			}())
			result += allChoices.first ?? ""
			let toPos = SnippetPosition(offset: result.count, rank: { rankCount += 2
				return rankCount
			}())
			let field = SnippetField(index: tabIndex, range: SnippetRange(from: pos, to: toPos), choices: allChoices)
			fields[tabIndex] = field

		case let .code(code):
			if let runner = commandRunner {
				var output = runner(code)
				// Strip trailing newline to match C++ behavior
				if output.hasSuffix("\n") {
					output.removeLast()
				}
				result += output
			}
		}
	}

	// MARK: - Option Conversion

	private func convertOptions(_ options: RegexpOptions) -> NSRegularExpression.Options {
		var result: NSRegularExpression.Options = []
		if options.contains(.ignoreCase) { result.insert(.caseInsensitive) }
		if options.contains(.singleLine) { result.insert(.dotMatchesLineSeparators) }
		if options.contains(.multiline) { result.insert(.anchorsMatchLines) }
		if options.contains(.extended) { result.insert(.allowCommentsAndWhitespace) }
		return result
	}

	// MARK: - Text Transforms

	/// Title-case / capitalize: first word + words >= 4 chars, except certain stop words.
	static func capitalize(_ src: String) -> String {
		let words = src.components(separatedBy: .whitespacesAndNewlines)
		let stopWords: Set<String> = [
			"a", "an", "and", "as", "at", "but", "by", "else", "for", "from",
			"if", "in", "nor", "of", "on", "or", "over", "so", "the", "then",
			"to", "up", "via", "vs", "when", "with", "yet",
		]
		var result: [String] = []

		for (i, word) in words.enumerated() {
			if i == 0 || i == words.count - 1 || word.count >= 4 || !stopWords.contains(word.lowercased()) {
				if !word.isEmpty {
					result.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
				} else {
					result.append(word)
				}
			} else {
				result.append(word.lowercased())
			}
		}

		return result.joined(separator: " ")
	}

	/// Strip diacritics and transliterate to ASCII.
	static func asciify(_ src: String) -> String {
		let mutable = NSMutableString(string: src)
		CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
		CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
		if let data = (mutable as String).data(using: .ascii, allowLossyConversion: true) {
			return String(data: data, encoding: .ascii) ?? mutable as String
		}
		return mutable as String
	}

	/// Percent-encode for URLs.
	static func urlEncode(_ src: String) -> String {
		src.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? src
	}

	/// Shell-escape a string using single quotes.
	static func shellEscape(_ src: String) -> String {
		let special = "|&;<>()$`\\\" \t\n*?[#˜=%"
		var res = ""
		var bow = src.startIndex

		while true {
			let eow = src[bow...].firstIndex(of: "'")
			let word = String(src[bow ..< (eow ?? src.endIndex)])

			let needsQuotes = word.contains(where: { special.contains($0) })
			if needsQuotes { res += "'" }
			res += word
			if needsQuotes { res += "'" }

			guard let eow else { break }
			res += "\\'"
			bow = src.index(after: eow)
		}

		return res
	}

	/// Describe a timestamp relative to now.
	static func relativeTime(_ src: String) -> String {
		let formats = ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "HH:mm:ss"]
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")

		for fmt in formats {
			formatter.dateFormat = fmt
			if let date = formatter.date(from: src) {
				let duration = Date().timeIntervalSince(date)
				if duration < 0 { return "in the future" }
				if duration < 2 { return "just now" }
				if duration < 60 { return "\(Int(duration)) seconds ago" }
				if duration < 90 { return "a minute ago" }
				if duration < 3570 { return "\(Int(duration / 60)) minutes ago" }
				if duration < 5400 { return "an hour ago" }
				if duration < 86400 { return "\(Int(duration / 3600)) hours ago" }
				if duration < 129_600 { return "a day ago" }
				if duration < 561_600 { return "\(Int(duration / 86400)) days ago" }
				if duration < 1_036_800 { return "a week ago" }
				if duration < 2_419_200 { return "\(Int(duration / 604_800)) weeks ago" }
				if duration < 3_952_800 { return "a month ago" }
				if duration < 30_304_800 { return "\(Int(duration / 2_635_200)) months ago" }
				if duration < 47_304_000 { return "a year ago" }
				return "\(Int(duration / 31_536_000)) years ago"
			}
		}
		return src
	}

	/// Insert thousands separators in numeric strings.
	static func formatNumber(_ src: String) -> String {
		// Simple implementation: add commas to digit groups
		guard let dotIdx = src.firstIndex(of: ".") ?? Optional(src.endIndex) else { return src }
		let intPart = String(src[src.startIndex ..< dotIdx])
		let decPart = dotIdx < src.endIndex ? String(src[dotIdx...]) : ""

		let digits = Array(intPart)
		var result: [Character] = []
		for (i, d) in digits.reversed().enumerated() {
			if i > 0, i % 3 == 0, d != "-", d != "+" {
				result.append(",")
			}
			result.append(d)
		}
		return String(result.reversed()) + decPart
	}

	/// Format seconds as a human-readable duration.
	static func formatDuration(_ src: String) -> String {
		guard let total = Double(src) else { return src }
		let seconds = Int(total.rounded())
		var parts: [String] = []

		let days = seconds / 86400
		let hours = (seconds / 3600) % 24
		let minutes = (seconds / 60) % 60
		let secs = seconds % 60

		if days > 0 { parts.append("\(days) \(days == 1 ? "day" : "days")") }
		if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
		if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
		if secs > 0, seconds < 600 {
			parts.append("\(secs) \(secs == 1 ? "second" : "seconds")")
		}

		return parts.joined(separator: ", ")
	}
}

// MARK: - Convenience API

/// Top-level format string expansion functions matching the C++ API.
public enum FormatString {
	/// Expands a format string template using the given variables.
	public static func expand(_ format: String, variables: [String: String] = [:]) -> String {
		// Fast path: no special characters
		if !format.contains("$"), !format.contains("("), !format.contains("\\") {
			return format
		}

		let nodes = FormatStringParser.parseFormatString(format)
		let expander = FormatStringExpander { name in variables[name] }
		expander.traverse(nodes)
		expander.handleCaseChanges()
		return expander.result
	}

	/// Expands a format string template using a variable lookup callback.
	public static func expand(_ format: String, lookup: @escaping (String) -> String?) -> String {
		if !format.contains("$"), !format.contains("("), !format.contains("\\") {
			return format
		}

		let nodes = FormatStringParser.parseFormatString(format)
		let expander = FormatStringExpander(variable: lookup)
		expander.traverse(nodes)
		expander.handleCaseChanges()
		return expander.result
	}

	/// Replaces matches of a regex pattern in `source` using the format string.
	public static func replace(
		_ source: String,
		pattern: String,
		format: String,
		repeat: Bool = true,
		variables: [String: String] = [:],
	) -> String {
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
		let nodes = FormatStringParser.parseFormatString(format)
		let expander = FormatStringExpander { name in variables[name] }
		expander.replace(source: source, pattern: regex, format: nodes, repeat: `repeat`)
		expander.handleCaseChanges()
		return expander.result
	}

	/// Escape special characters in a format string.
	public static func escape(_ format: String) -> String {
		var res = ""
		let chars = Array(format)
		for i in 0 ..< chars.count {
			switch chars[i] {
			case "\t": res += "\\t"
			case "\r": res += "\\r"
			case "\n": res += "\\n"
			case "$", "(":
				res += "\\"
				res.append(chars[i])
			case "\\":
				if i + 1 < chars.count, "\\$(trn".contains(chars[i + 1]) {
					res += "\\"
				}
				res.append(chars[i])
			default:
				res.append(chars[i])
			}
		}
		return res
	}
}
