import Foundation

/// Text transformation functions applied to selections.
///
/// Each transform takes a string and returns a transformed version.
/// Modeled after TextMate's C++ `transform.h` / `transform.cc`.
public enum TextTransform: String, Sendable, CaseIterable {
	case none
	case uppercase
	case lowercase
	case capitalize
	case toggleCase
	case transpose
	case unwrap
	case shiftLeft
	case shiftRight
	case reformat
	case reformatAndJustify

	/// Applies this transform to the given text.
	///
	/// - Parameters:
	///   - text: The input text to transform.
	///   - tabSize: The tab width (used for shift operations).
	///   - indentUsingSpaces: Whether to indent with spaces (true) or tabs (false).
	///   - wrapColumn: The column at which to wrap text (for reformat).
	/// - Returns: The transformed text.
	public func apply(
		to text: String,
		tabSize: Int = 4,
		indentUsingSpaces: Bool = false,
		wrapColumn: Int = 80,
	) -> String {
		switch self {
		case .none:
			text
		case .uppercase:
			text.uppercased()
		case .lowercase:
			text.lowercased()
		case .capitalize:
			Self.capitalizeWords(text)
		case .toggleCase:
			Self.toggleCase(text)
		case .transpose:
			text // transpose is handled at the editor level (swaps adjacent chars/words)
		case .unwrap:
			Self.unwrapText(text)
		case .shiftLeft:
			Self.shiftLeft(text, tabSize: tabSize)
		case .shiftRight:
			Self.shiftRight(text, tabSize: tabSize, useSpaces: indentUsingSpaces)
		case .reformat:
			Self.reformatText(text, wrapColumn: wrapColumn, justify: false)
		case .reformatAndJustify:
			Self.reformatText(text, wrapColumn: wrapColumn, justify: true)
		}
	}
}

// MARK: - Transform Implementations

extension TextTransform {
	/// Capitalizes the first letter of each word.
	static func capitalizeWords(_ text: String) -> String {
		var result = ""
		var capitalizeNext = true

		for char in text {
			if char.isWhitespace || char.isPunctuation {
				result.append(char)
				capitalizeNext = true
			} else if capitalizeNext {
				result.append(contentsOf: char.uppercased())
				capitalizeNext = false
			} else {
				result.append(contentsOf: char.lowercased())
				capitalizeNext = false
			}
		}
		return result
	}

	/// Toggles the case of each character.
	static func toggleCase(_ text: String) -> String {
		var result = ""
		for char in text {
			if char.isUppercase {
				result.append(contentsOf: char.lowercased())
			} else if char.isLowercase {
				result.append(contentsOf: char.uppercased())
			} else {
				result.append(char)
			}
		}
		return result
	}

	/// Unwraps text by replacing single newlines with spaces while preserving
	/// paragraph breaks (double newlines).
	static func unwrapText(_ text: String) -> String {
		// Replace single newlines (not followed by another newline) with space.
		var result = ""
		let chars = Array(text)
		var i = 0
		while i < chars.count {
			if chars[i] == "\n" {
				// Look ahead: if the next char is also \n, preserve paragraph break.
				if i + 1 < chars.count, chars[i + 1] == "\n" {
					result.append("\n\n")
					i += 2
					// Skip additional blank lines
					while i < chars.count, chars[i] == "\n" {
						result.append("\n")
						i += 1
					}
				} else {
					// Single newline → space (unless previous char was space or we're at start)
					if !result.isEmpty, result.last != " " {
						result.append(" ")
					}
					i += 1
				}
			} else {
				result.append(chars[i])
				i += 1
			}
		}
		return result
	}

	/// Shifts text left by removing one level of indentation from each line.
	static func shiftLeft(_ text: String, tabSize: Int) -> String {
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
		var result: [String] = []

		for line in lines {
			var removed = 0
			var dropCount = 0
			for char in line {
				if removed >= tabSize { break }
				if char == "\t" {
					dropCount += 1
					removed = tabSize // Tab counts as full indent level
				} else if char == " " {
					dropCount += 1
					removed += 1
				} else {
					break
				}
			}
			result.append(String(line.dropFirst(dropCount)))
		}

		return result.joined(separator: "\n")
	}

	/// Shifts text right by adding one level of indentation to each line.
	static func shiftRight(_ text: String, tabSize: Int, useSpaces: Bool) -> String {
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
		let indent = useSpaces ? String(repeating: " ", count: tabSize) : "\t"
		var result: [String] = []

		for line in lines {
			if line.isEmpty {
				result.append("")
			} else {
				result.append(indent + line)
			}
		}

		return result.joined(separator: "\n")
	}

	/// Reformats text to wrap at the specified column.
	static func reformatText(_ text: String, wrapColumn: Int, justify: Bool) -> String {
		guard wrapColumn > 0 else { return text }

		// Split into paragraphs (separated by blank lines)
		let paragraphs = text.components(separatedBy: "\n\n")
		var result: [String] = []

		for paragraph in paragraphs {
			let words = paragraph.split(separator: /\s+/).map(String.init)
			if words.isEmpty {
				result.append("")
				continue
			}

			var lines: [String] = []
			var currentLine = ""

			for word in words {
				if currentLine.isEmpty {
					currentLine = word
				} else if currentLine.count + 1 + word.count <= wrapColumn {
					currentLine += " " + word
				} else {
					lines.append(currentLine)
					currentLine = word
				}
			}
			if !currentLine.isEmpty {
				lines.append(currentLine)
			}

			if justify {
				lines = lines.enumerated().map { index, line in
					// Don't justify the last line of a paragraph
					if index == lines.count - 1 { return line }
					return Self.justifyLine(line, to: wrapColumn)
				}
			}

			result.append(lines.joined(separator: "\n"))
		}

		return result.joined(separator: "\n\n")
	}

	/// Justifies a single line by distributing extra spaces between words.
	private static func justifyLine(_ line: String, to column: Int) -> String {
		let words = line.split(separator: " ").map(String.init)
		guard words.count > 1 else { return line }

		let totalChars = words.reduce(0) { $0 + $1.count }
		let totalSpaces = column - totalChars
		let gaps = words.count - 1
		guard gaps > 0, totalSpaces > 0 else { return line }

		let baseSpaces = totalSpaces / gaps
		let extraSpaces = totalSpaces % gaps

		var result = words[0]
		for i in 1 ..< words.count {
			let spaces = baseSpaces + (i <= extraSpaces ? 1 : 0)
			result += String(repeating: " ", count: spaces) + words[i]
		}

		return result
	}
}
