import Foundation

// MARK: - Replacement Template

/// Expands replacement template strings with capture group references — equivalent to `format_string::expand`.
///
/// Supports:
/// - `$0` … `$9` or `${0}` … `${99}` for numbered captures
/// - `${name}` for named captures
/// - `${1:/upcase}` for case transforms (upcase, downcase, capitalize)
/// - `\n`, `\t`, `\\`, `\$` escape sequences
/// - `(?1:then:else)` conditional insertion based on capture presence
public struct ReplacementTemplate: Sendable {
	/// The raw template string.
	public let template: String

	public init(_ template: String) {
		self.template = template
	}

	/// Expand the template using the given capture groups.
	public func expand(with captures: [String: String]) -> String {
		var result = ""
		var index = template.startIndex

		while index < template.endIndex {
			let ch = template[index]

			if ch == "\\" {
				// Escape sequence
				let next = template.index(after: index)
				if next < template.endIndex {
					let escaped = template[next]
					switch escaped {
					case "n": result.append("\n")
					case "t": result.append("\t")
					case "\\": result.append("\\")
					case "$": result.append("$")
					default: result.append("\\")
						result.append(escaped)
					}
					index = template.index(after: next)
				} else {
					result.append("\\")
					index = template.index(after: index)
				}
			} else if ch == "$" {
				// Capture reference
				let afterDollar = template.index(after: index)
				if afterDollar < template.endIndex {
					if template[afterDollar] == "{" {
						// ${name} or ${1} or ${1:/transform}
						if let closeBrace = findClosingBrace(from: afterDollar) {
							let content = String(template[template.index(after: afterDollar) ..< closeBrace])
							let expanded = expandBracedCapture(content, captures: captures)
							result.append(expanded)
							index = template.index(after: closeBrace)
						} else {
							result.append("$")
							index = afterDollar
						}
					} else if template[afterDollar].isNumber {
						// $0 through $9
						let key = String(template[afterDollar])
						result.append(captures[key] ?? "")
						index = template.index(after: afterDollar)
					} else {
						result.append("$")
						index = afterDollar
					}
				} else {
					result.append("$")
					index = template.index(after: index)
				}
			} else if ch == "(", peekConditional(at: index) {
				// (?N:then:else) conditional
				let (expanded, endIndex) = expandConditional(from: index, captures: captures)
				result.append(expanded)
				index = endIndex
			} else {
				result.append(ch)
				index = template.index(after: index)
			}
		}

		return result
	}

	// MARK: - Private Helpers

	private func findClosingBrace(from index: String.Index) -> String.Index? {
		var i = template.index(after: index) // Skip {
		var depth = 1
		while i < template.endIndex {
			if template[i] == "{" { depth += 1 }
			if template[i] == "}" { depth -= 1
				if depth == 0 { return i }
			}
			i = template.index(after: i)
		}
		return nil
	}

	private func expandBracedCapture(_ content: String, captures: [String: String]) -> String {
		// Check for transform: ${1:/upcase} or ${name:/downcase}
		// The format is "captureName:/transform"
		if let colonSlashRange = content.range(of: ":/") {
			let captureName = String(content[content.startIndex ..< colonSlashRange.lowerBound])
			let transform = String(content[colonSlashRange.upperBound...])
			let value = captures[captureName] ?? ""
			return applyTransform(value, transform: transform)
		}

		// Also support ${1/transform} without colon for compatibility
		if let slashIdx = content.firstIndex(of: "/") {
			let captureName = String(content[content.startIndex ..< slashIdx])
			let transform = String(content[content.index(after: slashIdx)...])
			let value = captures[captureName] ?? ""
			return applyTransform(value, transform: transform)
		}

		// Plain capture reference: ${name} or ${0}
		return captures[content] ?? ""
	}

	private func applyTransform(_ value: String, transform: String) -> String {
		switch transform.lowercased() {
		case "upcase", "uppercase":
			value.uppercased()
		case "downcase", "lowercase":
			value.lowercased()
		case "capitalize":
			value.capitalized
		default:
			value
		}
	}

	private func peekConditional(at index: String.Index) -> Bool {
		// Check for (?N: pattern
		guard template[index] == "(" else { return false }
		let afterParen = template.index(after: index)
		guard afterParen < template.endIndex, template[afterParen] == "?" else { return false }
		let afterQ = template.index(after: afterParen)
		guard afterQ < template.endIndex, template[afterQ].isNumber else { return false }
		return true
	}

	private func expandConditional(
		from index: String.Index,
		captures: [String: String],
	) -> (String, String.Index) {
		// Parse (?N:then:else) or (?N:then)
		var i = template.index(index, offsetBy: 2) // Skip "(?"

		// Read capture number
		var numStr = ""
		while i < template.endIndex, template[i].isNumber {
			numStr.append(template[i])
			i = template.index(after: i)
		}

		// Expect ":"
		guard i < template.endIndex, template[i] == ":" else {
			return ("", template.index(after: index))
		}
		i = template.index(after: i) // Skip ":"

		// Read "then" part (until unescaped ":" or ")")
		let thenPart = readConditionalPart(from: &i)

		// Check for else part
		var elsePart = ""
		if i < template.endIndex, template[i] == ":" {
			i = template.index(after: i) // Skip ":"
			elsePart = readConditionalPart(from: &i)
		}

		// Skip closing ")"
		if i < template.endIndex, template[i] == ")" {
			i = template.index(after: i)
		}

		let hasCapture = captures[numStr] != nil && !(captures[numStr]?.isEmpty ?? true)
		let chosen = hasCapture ? thenPart : elsePart

		// Expand capture references within the chosen part
		let subTemplate = ReplacementTemplate(chosen)
		let result = subTemplate.expand(with: captures)

		return (result, i)
	}

	private func readConditionalPart(from index: inout String.Index) -> String {
		var part = ""
		var depth = 0
		while index < template.endIndex {
			let ch = template[index]
			if ch == "\\" {
				// Escaped character
				let next = template.index(after: index)
				if next < template.endIndex {
					part.append(template[next])
					index = template.index(after: next)
					continue
				}
			}
			if ch == "(" { depth += 1 }
			if ch == ")" {
				if depth > 0 { depth -= 1 } else { break }
			}
			if ch == ":", depth == 0 { break }
			part.append(ch)
			index = template.index(after: index)
		}
		return part
	}
}

// MARK: - Convenience

public extension ReplacementTemplate {
	/// Perform a full find-and-replace on a string using a regex pattern and replacement template.
	static func replaceAll(
		in text: String,
		pattern: String,
		replacement: String,
		options: FindOptions = .none,
	) throws -> String {
		let finder = try RegexFinder(pattern: pattern, options: options)
		let template = ReplacementTemplate(replacement)

		// Collect all matches
		var matches: [FindMatch] = []
		finder.eachMatch(in: text, offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}

		guard !matches.isEmpty else { return text }

		// Build result by replacing matches from end to start
		let utf8 = Array(text.utf8)
		var result = utf8
		for match in matches.reversed() {
			let expanded = template.expand(with: match.captures)
			let replacementBytes = Array(expanded.utf8)
			result.replaceSubrange(match.range, with: replacementBytes)
		}

		return String(bytes: result, encoding: .utf8) ?? text
	}
}
