import Foundation

/// A parser for TextMate's `.tm_properties` file format.
///
/// `.tm_properties` files use an INI-like syntax:
///
/// ```
/// # Comment
/// tabSize = 4
/// softTabs = true
///
/// [ *.swift ]
/// tabSize = 3
///
/// [ source.swift ]
/// showInvisibles = true
///
/// [ *.md ; *.txt ]
/// softWrap = true
/// ```
///
/// Sections can be glob patterns (file matchers) or scope selectors
/// (matching the grammar scope). Multiple section names are separated
/// by semicolons.
///
/// Modeled after TextMate's C++ `parse_ini` function.
public enum TMPropertiesParser {
	// MARK: - Data Types

	/// A parsed `.tm_properties` file.
	public struct PropertiesFile: Sendable {
		/// The file path this was loaded from.
		public let path: String
		/// The sections in document order.
		public let sections: [Section]

		public init(path: String, sections: [Section]) {
			self.path = path
			self.sections = sections
		}
	}

	/// A section within a `.tm_properties` file.
	public struct Section: Sendable {
		/// Section header names. Empty array = top-level (no header).
		public let names: [String]
		/// Key-value assignments within this section.
		public let assignments: [Assignment]

		public init(names: [String], assignments: [Assignment]) {
			self.names = names
			self.assignments = assignments
		}
	}

	/// A key = value assignment.
	public struct Assignment: Sendable {
		public let key: String
		public let value: String
		public let lineNumber: Int

		public init(key: String, value: String, lineNumber: Int = 0) {
			self.key = key
			self.value = value
			self.lineNumber = lineNumber
		}
	}

	// MARK: - Parsing

	/// Parses the contents of a `.tm_properties` file.
	///
	/// - Parameters:
	///   - content: The file content as a string.
	///   - path: The file path (used for error reporting and CWD).
	/// - Returns: A `PropertiesFile` with all parsed sections.
	public static func parse(content: String, path: String = "") -> PropertiesFile {
		var sections: [Section] = []
		var currentNames: [String] = []
		var currentAssignments: [Assignment] = []
		var hasExplicitSection = false

		let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

		for (lineIndex, line) in lines.enumerated() {
			let lineNumber = lineIndex + 1
			let trimmed = line.trimmingWhitespace()

			// Empty line or comment
			if trimmed.isEmpty || trimmed.hasPrefix("#") {
				continue
			}

			// Section header: [ name1 ; name2 ]
			if trimmed.hasPrefix("[") {
				// Save current section if it has assignments
				if !currentAssignments.isEmpty || hasExplicitSection {
					sections.append(Section(names: currentNames, assignments: currentAssignments))
				}

				// Parse section names
				currentNames = parseSectionHeader(String(trimmed))
				currentAssignments = []
				hasExplicitSection = true
				continue
			}

			// Assignment: key = value
			if let assignment = parseAssignment(String(trimmed), lineNumber: lineNumber) {
				// If no section has been started, create implicit top-level section
				if sections.isEmpty, !hasExplicitSection, currentAssignments.isEmpty {
					hasExplicitSection = false
				}
				currentAssignments.append(assignment)
			}
		}

		// Save the last section
		if !currentAssignments.isEmpty || hasExplicitSection {
			sections.append(Section(names: currentNames, assignments: currentAssignments))
		}

		return PropertiesFile(path: path, sections: sections)
	}

	/// Parses a `.tm_properties` file at the given URL.
	public static func load(url: URL) throws -> PropertiesFile {
		let content = try String(contentsOf: url, encoding: .utf8)
		return parse(content: content, path: url.path)
	}

	// MARK: - Private Parsers

	/// Parses a section header like `[ *.swift ; *.m ]`.
	private static func parseSectionHeader(_ line: String) -> [String] {
		// Strip leading `[` and trailing `]`
		var s = line.trimmingWhitespace()
		guard s.hasPrefix("[") else { return [] }
		s = String(s.dropFirst())
		if s.hasSuffix("]") {
			s = String(s.dropLast())
		}

		// Split by `;` and trim each name
		return s.split(separator: ";").map { part in
			parseStringValue(String(part).trimmingWhitespace())
		}.filter { !$0.isEmpty }
	}

	/// Parses a `key = value` assignment line.
	private static func parseAssignment(_ line: String, lineNumber: Int) -> Assignment? {
		// Strip trailing comment (# not in quotes)
		let stripped = stripTrailingComment(line)

		guard let eqIndex = stripped.firstIndex(of: "=") else {
			return nil
		}

		let key = String(stripped[stripped.startIndex ..< eqIndex]).trimmingWhitespace()
		let rawValue = String(stripped[stripped.index(after: eqIndex)...]).trimmingWhitespace()

		guard !key.isEmpty else { return nil }

		let value = parseStringValue(rawValue)
		return Assignment(key: key, value: value, lineNumber: lineNumber)
	}

	/// Strips a trailing `#`-comment from a line, respecting quotes.
	private static func stripTrailingComment(_ line: String) -> String {
		var inSingle = false
		var inDouble = false
		var escaped = false
		var result = ""

		for ch in line {
			if escaped {
				result.append(ch)
				escaped = false
				continue
			}
			if ch == "\\" {
				escaped = true
				result.append(ch)
				continue
			}
			if ch == "'", !inDouble {
				inSingle.toggle()
			} else if ch == "\"", !inSingle {
				inDouble.toggle()
			} else if ch == "#", !inSingle, !inDouble {
				break
			}
			result.append(ch)
		}

		return result
	}

	/// Parses a string value, stripping surrounding quotes and processing escapes.
	private static func parseStringValue(_ raw: String) -> String {
		let s = raw.trimmingWhitespace()
		if s.isEmpty { return s }

		// Single-quoted string
		if s.hasPrefix("'"), s.hasSuffix("'"), s.count >= 2 {
			let inner = String(s.dropFirst().dropLast())
			return processEscapes(inner, quoteChar: "'")
		}

		// Double-quoted string
		if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
			let inner = String(s.dropFirst().dropLast())
			return processEscapes(inner, quoteChar: "\"")
		}

		// Bare string
		return processEscapes(s, quoteChar: nil)
	}

	/// Processes backslash escapes.
	private static func processEscapes(_ str: String, quoteChar: Character?) -> String {
		var result = ""
		var escaped = false
		for ch in str {
			if escaped {
				// Only certain characters are escapable
				if ch == "\\" || ch == "\n" || ch == quoteChar {
					result.append(ch)
				} else {
					result.append("\\")
					result.append(ch)
				}
				escaped = false
			} else if ch == "\\" {
				escaped = true
			} else {
				result.append(ch)
			}
		}
		if escaped {
			result.append("\\")
		}
		return result
	}
}

// MARK: - String Extension

extension StringProtocol {
	/// Trims leading and trailing whitespace (spaces and tabs).
	func trimmingWhitespace() -> String {
		var start = startIndex
		var end = endIndex

		while start < end, let ch = self[start].asciiValue, ch == 0x20 || ch == 0x09 {
			start = index(after: start)
		}
		while end > start {
			let prev = index(before: end)
			guard let ch = self[prev].asciiValue, ch == 0x20 || ch == 0x09 else { break }
			end = prev
		}

		return String(self[start ..< end])
	}
}
