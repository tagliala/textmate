import Foundation

// MARK: - Indent FSM

/// Finite state machine for computing auto-indentation levels.
///
/// Ports the C++ `indent::fsm_t` from `indent.h`/`indent.cc`. Given a set of
/// indent patterns (`increase`, `decrease`, `increaseNext`, `ignore`,
/// `zeroIndent`) from a TextMate grammar, the FSM processes lines one at a time
/// and reports the correct indentation for each.
///
/// Usage:
/// ```swift
/// var fsm = IndentFSM(indentSize: 4, tabSize: 4)
/// for line in contextLines {
///     guard fsm.isSeeded(line, patterns: patterns) else { continue }
///     break
/// }
/// let indent = fsm.scanLine(newLine, patterns: patterns)
/// ```
public struct IndentFSM: Sendable {
	private let indentSize: Int
	private let tabSize: Int
	private var level: Int = 0
	private var carry: Int = 0
	private var seen: Int = 0
	private var lastType: Int = 0
	private var lastIndent: Int = 0

	/// Creates an indent FSM.
	///
	/// - Parameters:
	///   - indentSize: The number of spaces per indent level.
	///   - tabSize: The width of a tab character in spaces.
	public init(indentSize: Int, tabSize: Int) {
		self.indentSize = indentSize
		self.tabSize = tabSize
	}

	// MARK: - Pattern Types

	/// Indent pattern classification flags.
	public struct PatternType: OptionSet, Hashable, Sendable {
		public let rawValue: Int
		public init(rawValue: Int) {
			self.rawValue = rawValue
		}

		/// Line increases indent for subsequent lines.
		public static let increase = PatternType(rawValue: 1)
		/// Line decreases indent for itself.
		public static let decrease = PatternType(rawValue: 2)
		/// Line increases indent for only the next line.
		public static let increaseNext = PatternType(rawValue: 4)
		/// Line should be ignored for indentation.
		public static let ignore = PatternType(rawValue: 8)
		/// Line should have zero indentation.
		public static let zeroIndent = PatternType(rawValue: 16)
	}

	// MARK: - Scanning

	/// Seeds the FSM with context lines before the insertion point.
	///
	/// Call this for each preceding line until it returns `true`, indicating
	/// the FSM has enough context to compute indentation.
	///
	/// - Returns: `true` when the FSM is fully seeded and ready for `scanLine`.
	public mutating func isSeeded(
		_ line: String,
		patterns: [PatternType: NSRegularExpression],
	) -> Bool {
		let type = Self.classify(line, patterns: patterns)
		let ptType = PatternType(rawValue: type)

		if Self.isBlank(line) || ptType.contains(.ignore) || ptType.contains(.zeroIndent) {
			return false
		}

		seen += 1
		if seen == 1 {
			level = Self.leadingWhitespace(line, tabSize: tabSize)
			carry = 0
			lastType = type
			lastIndent = level

			if ptType.contains(.increase) {
				level += indentSize
			}
			if ptType.contains(.increaseNext) {
				carry += indentSize
			}
			return false
		}

		let lastPT = PatternType(rawValue: lastType)
		if ptType.contains(.increaseNext),
		   !lastPT.contains(.increase), !lastPT.contains(.decrease)
		{
			level = Self.leadingWhitespace(line, tabSize: tabSize)
			if lastPT.contains(.increaseNext), level < lastIndent {
				carry += lastIndent - level
			}
			lastIndent = level
			return false
		}

		return true
	}

	/// Whether the line should be ignored for indentation purposes.
	public func isIgnored(
		_ line: String,
		patterns: [PatternType: NSRegularExpression],
	) -> Bool {
		Self.isBlank(line) || PatternType(rawValue: Self.classify(line, patterns: patterns)).contains(.ignore)
	}

	/// Computes the indentation for the given line.
	///
	/// Call this after `isSeeded` returns `true` for all context lines.
	///
	/// - Returns: The indentation in spaces.
	public mutating func scanLine(
		_ line: String,
		patterns: [PatternType: NSRegularExpression],
	) -> Int {
		let type = Self.classify(line, patterns: patterns)
		let ptType = PatternType(rawValue: type)

		var result = level + carry

		if ptType.contains(.zeroIndent) {
			result = 0
		} else if !ptType.contains(.ignore) {
			if ptType.contains(.increase) || ptType.contains(.decrease) {
				carry = 0
			}
			if ptType.contains(.decrease), !ptType.contains(.increase) || level > 0 {
				level -= indentSize
			}

			result = level + carry

			if ptType.contains(.increase) {
				level += indentSize
			}
			carry = ptType.contains(.increaseNext) ? carry + indentSize : 0
		}

		return max(0, result)
	}

	// MARK: - Utilities

	/// Creates an indent string of the given size.
	public static func createIndent(size: Int, tabSize: Int, softTabs: Bool) -> String {
		if softTabs {
			return String(repeating: " ", count: size)
		}
		return String(repeating: "\t", count: size / tabSize) +
			String(repeating: " ", count: size % tabSize)
	}

	/// Counts the leading whitespace in a string, measured in spaces.
	public static func leadingWhitespace(_ line: String, tabSize: Int) -> Int {
		var result = 0
		for ch in line {
			if ch == "\t" {
				result += tabSize - (result % tabSize)
			} else if ch == " " {
				result += 1
			} else {
				break
			}
		}
		return result
	}

	// MARK: - Private

	/// Classifies a line against the indent patterns.
	private static func classify(
		_ line: String,
		patterns: [PatternType: NSRegularExpression],
	) -> Int {
		let nsLine = line as NSString
		let range = NSRange(location: 0, length: nsLine.length)
		var result = 0

		for (patternType, regex) in patterns {
			if regex.firstMatch(in: line, range: range) != nil {
				result |= patternType.rawValue
			}
		}

		let pt = PatternType(rawValue: result)
		if pt.contains(.ignore) {
			return PatternType.ignore.rawValue
		}
		if pt.contains(.zeroIndent) {
			return PatternType.zeroIndent.rawValue
		}
		if pt.contains(.increase) {
			return result & ~PatternType.increaseNext.rawValue
		}

		return result
	}

	/// Whether the line is blank (only whitespace).
	private static func isBlank(_ line: String) -> Bool {
		line.allSatisfy(\.isWhitespace)
	}
}
