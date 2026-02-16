import Foundation

// MARK: - Format String & Snippet Parser

/// Recursive-descent parser for TextMate format strings and snippet bodies.
///
/// Ports the C++ `parse_context_t` from `parser.cc` / `parser_base.cc`.
/// Both format string syntax (used in regex replacements) and snippet syntax
/// (`$N` placeholders, `${N:content}`, choices, code blocks) are handled by
/// the same parser with mode-specific entry points.
public struct FormatStringParser: Sendable {
	/// The full input string.
	private let input: String
	/// Current parse position.
	private var index: String.Index
	/// End of input.
	private let endIndex: String.Index

	/// Creates a parser for the given input string.
	public init(_ input: String) {
		self.input = input
		index = input.startIndex
		endIndex = input.endIndex
	}

	/// Number of characters consumed so far.
	public var bytesParsed: Int {
		input.distance(from: input.startIndex, to: index)
	}

	// MARK: - Public Entry Points

	/// Parses as a format string (regex replacement syntax).
	///
	/// Supports variables, conditionals, case changes, control codes, escapes.
	public mutating func parseFormatString(stopChars: String = "") -> [FormatStringNode] {
		var nodes: [FormatStringNode] = []
		parseFormatString(stopChars: stopChars, into: &nodes)
		return nodes
	}

	/// Parses as a snippet body.
	///
	/// Supports all format string syntax plus tab-stop placeholders, choices,
	/// transforms, and code blocks.
	public mutating func parseSnippet() -> [FormatStringNode] {
		var nodes: [FormatStringNode] = []
		parseSnippet(stopChars: "", into: &nodes)
		return nodes
	}

	/// Parses a format string from a string, returning the AST nodes.
	public static func parseFormatString(_ input: String, stopChars: String = "") -> [FormatStringNode] {
		var parser = FormatStringParser(input)
		return parser.parseFormatString(stopChars: stopChars)
	}

	/// Parses a snippet body from a string, returning the AST nodes.
	public static func parseSnippet(_ input: String) -> [FormatStringNode] {
		var parser = FormatStringParser(input)
		return parser.parseSnippet()
	}

	// MARK: - Base Parser Primitives

	/// Returns the current character without advancing, or nil if at end.
	private var peek: Character? {
		index < endIndex ? input[index] : nil
	}

	/// Returns true and advances if the current character is in `chars`.
	private mutating func parseChar(_ chars: String) -> Bool {
		guard index < endIndex, chars.contains(input[index]) else { return false }
		index = input.index(after: index)
		return true
	}

	/// Consumes and returns the previous character (after advancing in parseChar).
	private func lastChar() -> Character {
		input[input.index(before: index)]
	}

	/// Consumes characters while they are in `chars`, appending to `result`.
	/// Returns true if at least one character was consumed.
	private mutating func parseChars(_ chars: String, into result: inout String) -> Bool {
		result = ""
		while index < endIndex, chars.contains(input[index]) {
			result.append(input[index])
			index = input.index(after: index)
		}
		return !result.isEmpty
	}

	/// Parses an unsigned integer and returns it.
	private mutating func parseInt() -> Int? {
		guard index < endIndex, input[index].isNumber else { return nil }
		var value = 0
		while index < endIndex, let digit = input[index].wholeNumberValue {
			value = value * 10 + digit
			index = input.index(after: index)
		}
		return value
	}

	/// Consumes characters until one of `stopChars` is found.
	/// The stop character is consumed. Backslash-escaped stop chars are included literally.
	/// Returns the consumed string, or nil on failure.
	private mutating func parseUntil(_ stopChars: String) -> String? {
		let backtrack = index
		var result = ""
		while index < endIndex, !stopChars.contains(input[index]) {
			if input[index] == "\\", input.index(after: index) < endIndex {
				let next = input[input.index(after: index)]
				if next == "\\" || stopChars.contains(next) {
					index = input.index(after: index) // skip backslash
				}
			}
			result.append(input[index])
			index = input.index(after: index)
		}
		if parseChar(stopChars) {
			return result
		}
		index = backtrack
		return nil
	}

	// MARK: - Variable Parsing

	private mutating func parseVariable(
		contentParser: (inout FormatStringParser, String, inout [FormatStringNode]) -> Bool,
		into nodes: inout [FormatStringNode],
	) -> Bool {
		parseVariableSimple(into: &nodes) || parseVariableComplex(contentParser: contentParser, into: &nodes)
	}

	private mutating func parseVariableSimple(into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		guard parseChar("$") else { return false }

		if let intValue = parseInt() {
			nodes.append(.variable(name: String(intValue)))
			return true
		}

		let identChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
		var name = ""
		if parseChars(identChars, into: &name) {
			nodes.append(.variable(name: name))
			return true
		}

		index = backtrack
		return false
	}

	private mutating func parseVariableComplex(
		contentParser: (inout FormatStringParser, String, inout [FormatStringNode]) -> Bool,
		into nodes: inout [FormatStringNode],
	) -> Bool {
		let backtrack = index

		guard parseChar("$"), parseChar("{") else {
			index = backtrack
			return false
		}

		guard let name = parseUntil("/:}") else {
			index = backtrack
			return false
		}

		let delimiter = lastChar()

		if delimiter == "}" {
			// Simple variable: ${name}
			nodes.append(.variable(name: name))
			return true
		} else if delimiter == "/" {
			// Variable transform: ${name/pattern/format/options}
			var patternNodes: [FormatStringNode] = []
			while index < endIndex, peek != "/" {
				if !parseEscape("\\/", into: &patternNodes),
				   !parseVariableComplex(
				   	contentParser: { p, s, n in p.parseFormatString(stopChars: s, into: &n) },
				   	into: &patternNodes,
				   ),
				   !parseTextChar(into: &patternNodes)
				{
					break
				}
			}
			guard parseChar("/") else { index = backtrack
				return false
			}
			var formatNodes: [FormatStringNode] = []
			guard parseFormatString(stopChars: "/", into: &formatNodes) else { index = backtrack
				return false
			}
			let options = parseRegexpOptions()
			guard parseChar("}") else { index = backtrack
				return false
			}
			nodes.append(.variableTransform(name: name, pattern: patternNodes, format: formatNodes, options: options))
			return true
		} else {
			// delimiter == ":"
			if parseChar("+") {
				// ${name:+if_set}
				var ifSet: [FormatStringNode] = []
				guard contentParser(&self, "}", &ifSet) else { index = backtrack
					return false
				}
				nodes.append(.variableCondition(name: name, ifSet: ifSet, ifNotSet: []))
				return true
			} else if parseChar("?") {
				// ${name:?if_set:if_not_set}
				var ifSet: [FormatStringNode] = []
				guard contentParser(&self, ":", &ifSet) else { index = backtrack
					return false
				}
				var ifNotSet: [FormatStringNode] = []
				guard contentParser(&self, "}", &ifNotSet) else { index = backtrack
					return false
				}
				nodes.append(.variableCondition(name: name, ifSet: ifSet, ifNotSet: ifNotSet))
				return true
			} else if parseChar("/") {
				// ${name:/transform} — named transforms like upcase, downcase, etc.
				var change = TextTransformKind()
				while lastChar() == "/" || true {
					var option = ""
					guard let parsed = parseUntil("/}") else { break }
					option = parsed
					let transformMap: [(String, TextTransformKind)] = [
						("upcase", .upcase),
						("downcase", .downcase),
						("titlecase", .capitalize),
						("capitalize", .capitalize),
						("asciify", .asciify),
						("urlencode", .urlEncode),
						("shellescape", .shellEscape),
						("relative", .relative),
						("number", .number),
						("duration", .duration),
						("dirname", .dirname),
						("basename", .basename),
					]
					for (key, value) in transformMap where option == key {
						change.insert(value)
					}
					if lastChar() == "}" { break }
				}
				if lastChar() == "}" {
					nodes.append(.variableChange(name: name, change: change))
					return true
				}
				index = backtrack
				return false
			} else {
				// ${name:-fallback} or ${name:fallback}
				_ = parseChar("-") // optional for backwards compatibility
				var fallback: [FormatStringNode] = []
				guard contentParser(&self, "}", &fallback) else { index = backtrack
					return false
				}
				nodes.append(.variableFallback(name: name, fallback: fallback))
				return true
			}
		}
	}

	// MARK: - Condition Parsing

	/// Parses `(?N:if_set:if_not_set)` or `(?N:if_set)`.
	private mutating func parseCondition(into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		guard parseChar("("), parseChar("?") else {
			index = backtrack
			return false
		}
		guard let captureIndex = parseInt() else {
			index = backtrack
			return false
		}
		guard parseChar(":") else {
			index = backtrack
			return false
		}

		let name = String(captureIndex)
		var ifSet: [FormatStringNode] = []
		guard parseFormatString(stopChars: ":)", into: &ifSet) else {
			index = backtrack
			return false
		}

		let delim = lastChar()
		if delim == ")" {
			nodes.append(.variableCondition(name: name, ifSet: ifSet, ifNotSet: []))
			return true
		} else if delim == ":" {
			var ifNotSet: [FormatStringNode] = []
			guard parseFormatString(stopChars: ")", into: &ifNotSet), lastChar() == ")" else {
				index = backtrack
				return false
			}
			nodes.append(.variableCondition(name: name, ifSet: ifSet, ifNotSet: ifNotSet))
			return true
		}

		index = backtrack
		return false
	}

	// MARK: - Case Change & Control Codes

	private mutating func parseCaseChange(into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		guard parseChar("\\"), parseChar("ULEul") else {
			index = backtrack
			return false
		}
		let type: CaseChangeType = switch lastChar() {
		case "U": .upper
		case "L": .lower
		case "E": .none
		case "u": .upperNext
		case "l": .lowerNext
		default: .none
		}
		nodes.append(.caseChange(type))
		return true
	}

	private mutating func parseControlCode(into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		guard parseChar("\\"), parseChar("trnx") else {
			index = backtrack
			return false
		}

		switch lastChar() {
		case "t":
			appendToTextNode(&nodes, "\t")
			return true
		case "r":
			appendToTextNode(&nodes, "\r")
			return true
		case "n":
			appendToTextNode(&nodes, "\n")
			return true
		case "x":
			// \x{HHHH} or \xHH
			if parseChar("{") {
				if var hexStr = parseUntil("}") {
					if hexStr.count <= 8, hexStr.allSatisfy(\.isHexDigit),
					   let codepoint = UInt32(hexStr, radix: 16),
					   let scalar = Unicode.Scalar(codepoint)
					{
						appendToTextNode(&nodes, String(scalar))
						return true
					}
				}
			} else if index < endIndex, input[index].isHexDigit {
				let nextIdx = input.index(after: index)
				if nextIdx < endIndex, input[nextIdx].isHexDigit {
					let high = input[index].hexDigitValue!
					let low = input[nextIdx].hexDigitValue!
					index = input.index(after: nextIdx)
					appendToTextNode(&nodes, String(UnicodeScalar(high << 4 | low)!))
					return true
				}
			}
		default:
			break
		}

		index = backtrack
		return false
	}

	// MARK: - Escape & Text

	private mutating func parseEscape(_ escapeChars: String, into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		guard parseChar("\\"), parseChar(escapeChars) else {
			index = backtrack
			return false
		}
		appendToTextNode(&nodes, String(lastChar()))
		return true
	}

	private mutating func parseTextChar(into nodes: inout [FormatStringNode]) -> Bool {
		guard index < endIndex else { return false }
		appendToTextNode(&nodes, String(input[index]))
		index = input.index(after: index)
		return true
	}

	// MARK: - Regexp Options

	private mutating func parseRegexpOptions() -> RegexpOptions {
		var options: RegexpOptions = .none
		while parseChar("giems") {
			switch lastChar() {
			case "g": options.insert(.global)
			case "i": options.insert(.ignoreCase)
			case "e": options.insert(.extended)
			case "m": options.insert(.multiline)
			case "s": options.insert(.singleLine)
			default: break
			}
		}
		return options
	}

	// MARK: - Format String Parser

	@discardableResult
	private mutating func parseFormatString(stopChars: String, into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		let escChars = "\\$(" + stopChars

		while index < endIndex, !stopChars.contains(input[index]) {
			if parseVariable(contentParser: { p, s, n in
				p.parseFormatString(stopChars: s, into: &n)
			}, into: &nodes) { continue }
			if parseCondition(into: &nodes) { continue }
			if parseControlCode(into: &nodes) { continue }
			if parseCaseChange(into: &nodes) { continue }
			if parseEscape(escChars, into: &nodes) { continue }
			if parseTextChar(into: &nodes) { continue }
			break
		}

		if (index == endIndex && stopChars.isEmpty) || parseChar(stopChars) {
			return true
		}
		index = backtrack
		return false
	}

	// MARK: - Snippet Parser

	private mutating func parsePlaceholder(into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		guard parseChar("$") else { return false }

		if parseChar("{") {
			guard let tabIndex = parseInt() else {
				index = backtrack
				return false
			}

			if parseChar(":") {
				// ${N:content}
				var content: [FormatStringNode] = []
				guard parseSnippet(stopChars: "}", into: &content) else {
					index = backtrack
					return false
				}
				nodes.append(.placeholder(index: tabIndex, content: content))
				return true
			} else if parseChar("/") {
				// ${N/pattern/format/options}
				guard let regexp = parseUntil("/") else {
					index = backtrack
					return false
				}
				var format: [FormatStringNode] = []
				guard parseFormatString(stopChars: "/", into: &format) else {
					index = backtrack
					return false
				}
				let options = parseRegexpOptions()
				guard parseChar("}") else {
					index = backtrack
					return false
				}
				nodes.append(.placeholderTransform(index: tabIndex, pattern: regexp, format: format, options: options))
				return true
			} else if parseChar("|") {
				// ${N|choice1,...,choiceN|}
				var choices: [[FormatStringNode]] = []
				var currentChoice: [FormatStringNode] = []
				while parseFormatString(stopChars: ",|", into: &currentChoice) {
					choices.append(currentChoice)
					if lastChar() == "|" { break }
					currentChoice = []
				}
				guard lastChar() == "|", parseChar("}") else {
					index = backtrack
					return false
				}
				nodes.append(.placeholderChoice(index: tabIndex, choices: choices))
				return true
			} else if parseChar("}") {
				// ${N}
				nodes.append(.placeholder(index: tabIndex, content: []))
				return true
			}

			index = backtrack
			return false
		}

		// $N
		if let tabIndex = parseInt() {
			nodes.append(.placeholder(index: tabIndex, content: []))
			return true
		}

		index = backtrack
		return false
	}

	private mutating func parseCode(into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		guard parseChar("`") else { return false }
		guard let code = parseUntil("`") else {
			index = backtrack
			return false
		}
		nodes.append(.code(code))
		return true
	}

	@discardableResult
	private mutating func parseSnippet(stopChars: String, into nodes: inout [FormatStringNode]) -> Bool {
		let backtrack = index
		let escChars = "\\$`" + stopChars

		while index < endIndex, !stopChars.contains(input[index]) {
			if parsePlaceholder(into: &nodes) { continue }
			if parseVariable(contentParser: { p, s, n in
				p.parseSnippet(stopChars: s, into: &n)
			}, into: &nodes) { continue }
			if parseCode(into: &nodes) { continue }
			if parseEscape(escChars, into: &nodes) { continue }
			if parseTextChar(into: &nodes) { continue }
			break
		}

		if (index == endIndex && stopChars.isEmpty) || parseChar(stopChars) {
			return true
		}
		index = backtrack
		return false
	}

	// MARK: - Text Node Helpers

	/// Appends a character to the last text node, or creates a new one.
	private func appendToTextNode(_ nodes: inout [FormatStringNode], _ text: String) {
		if case let .text(existing) = nodes.last {
			nodes[nodes.count - 1] = .text(existing + text)
		} else {
			nodes.append(.text(text))
		}
	}
}
