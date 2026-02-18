import Foundation

/// Extracts and tracks source-code symbols (function names, class names, etc.)
/// within a buffer, automatically adjusting positions on edits.
///
/// Symbols are stored as position → name pairs. The extraction itself is
/// driven by the parsing subsystem: after grammar parsing completes on a
/// range, the caller invokes ``updateSymbols(from:to:entries:)`` with the
/// newly-computed symbol data. ``SymbolExtractor`` handles the storage,
/// position adjustment, and query interface.
///
/// Includes ``SymbolTransformation`` for parsing and applying
/// `s/pattern/format/options;` chains used in TextMate's
/// `symbolTransformation` bundle setting.
///
/// Ported from C++ `symbols_t` in `Frameworks/buffer/src/symbols.cc`.
public final class SymbolExtractor: BufferCallback, @unchecked Sendable {
	/// Position → symbol display name.
	private var symbols: IndexedMap<String> = IndexedMap()

	/// Creates an empty symbol extractor.
	public init() {}

	// MARK: - Query

	/// Whether there are no symbols.
	public var isEmpty: Bool {
		symbols.isEmpty
	}

	/// The number of tracked symbols.
	public var count: Int {
		symbols.count
	}

	/// Returns all symbols as `(position, name)` pairs sorted by position.
	public func allSymbols() -> [(position: Int, name: String)] {
		symbols.map { ($0.position, $0.value) }
	}

	/// Returns the symbol whose range contains the given offset.
	///
	/// A symbol's range extends from its position to the position of the
	/// next symbol (or end of buffer). Returns `nil` if `offset` is before
	/// the first symbol.
	public func symbol(at offset: Int) -> (position: Int, name: String)? {
		// Find the last symbol whose position <= offset.
		let idx = symbols.upperBound(at: offset)
		if idx > 0 {
			let entry = symbols[idx - 1]
			return (entry.position, entry.value)
		}
		return nil
	}

	// MARK: - Batch Update

	/// Replaces symbols in the range `[from, to)` with new entries.
	///
	/// Called by the parsing subsystem after re-parsing a region. Existing
	/// symbols within the range are removed and replaced with the provided
	/// entries.
	///
	/// - Parameters:
	///   - from: Start of the reparsed range (byte offset).
	///   - to: End of the reparsed range (byte offset).
	///   - entries: New symbols computed from the freshly-parsed scopes.
	public func updateSymbols(from: Int, to: Int, entries: [(position: Int, name: String)]) {
		// Remove existing symbols in [from, to).
		let lo = symbols.lowerBound(at: from)
		var toRemove: [Int] = []
		for i in lo ..< symbols.count {
			let pos = symbols[i].position
			if pos >= to { break }
			toRemove.append(pos)
		}
		for pos in toRemove.reversed() {
			symbols.remove(at: pos)
		}

		// Insert new symbols.
		for entry in entries {
			symbols.set(at: entry.position, value: entry.name)
		}
	}

	/// Sets a single symbol at the given position.
	public func setSymbol(at position: Int, name: String) {
		symbols.set(at: position, value: name)
	}

	/// Removes the symbol at the given position.
	@discardableResult
	public func removeSymbol(at position: Int) -> Bool {
		symbols.remove(at: position)
	}

	/// Removes all symbols.
	public func clear() {
		symbols.clear()
	}

	// MARK: - BufferCallback

	public func willReplace(from _: Int, to _: Int, bytes _: [UInt8]) {}

	public func didReplace(from: Int, to: Int, length: Int) {
		symbols.replace(from: from, to: to, newLength: length)
	}
}

// MARK: - Symbol Transformation

/// Parses and applies `s/pattern/format/options;` substitution chains used
/// in TextMate's `symbolTransformation` bundle setting.
///
/// Example input: `"s/^\\s*//;s/\\s*\\(.*//"`
/// This would strip leading whitespace, then remove everything from the
/// first parenthesis onward.
///
/// Ported from C++ `transform_t` in `Frameworks/buffer/src/symbols.cc`.
public struct SymbolTransformation: Sendable {
	/// A single substitution pattern.
	public struct Pattern: Sendable {
		/// The compiled regular expression.
		public let regex: NSRegularExpression
		/// The replacement template (supports `$0`, `$1`, etc.).
		public let template: String
		/// Whether to replace all matches (`g` flag) or just the first.
		public let isGlobal: Bool
	}

	/// The ordered list of substitution patterns.
	public let patterns: [Pattern]

	/// Parses a `symbolTransformation` string into a chain of patterns.
	///
	/// - Parameter string: A semicolon-separated list of `s/pattern/format/options`
	///   entries. Returns an empty transformation if `nil` or unparseable.
	public init?(_ string: String?) {
		guard let string, !string.isEmpty else { return nil }
		var parsed: [Pattern] = []

		// Split on `;` and parse each `s/pattern/format/options` entry.
		let components = string.split(separator: ";", omittingEmptySubsequences: true)
		for component in components {
			let trimmed = component.trimmingCharacters(in: .whitespaces)
			guard trimmed.hasPrefix("s/") else { continue }

			// Find the delimiter positions after the initial `s`.
			// Format: s/PATTERN/REPLACEMENT/OPTIONS
			let body = String(trimmed.dropFirst(2)) // Drop "s/"
			guard let parts = splitSubstitution(body) else { continue }

			let patternStr = parts.pattern
			let templateStr = parts.replacement
			let isGlobal = parts.options.contains("g")

			guard let regex = try? NSRegularExpression(pattern: patternStr) else {
				continue
			}

			parsed.append(Pattern(regex: regex, template: templateStr, isGlobal: isGlobal))
		}

		guard !parsed.isEmpty else { return nil }
		patterns = parsed
	}

	/// Applies the transformation chain to the given string.
	public func apply(to source: String) -> String {
		var result = source
		for pattern in patterns {
			let range = NSRange(result.startIndex..., in: result)
			if pattern.isGlobal {
				result = pattern.regex.stringByReplacingMatches(
					in: result,
					range: range,
					withTemplate: pattern.template,
				)
			} else {
				// Replace only the first match.
				if let match = pattern.regex.firstMatch(in: result, range: range) {
					let replacement = pattern.regex.replacementString(
						for: match,
						in: result,
						offset: 0,
						template: pattern.template,
					)
					let matchRange = Range(match.range, in: result)!
					result = result.replacingCharacters(in: matchRange, with: replacement)
				}
			}
		}
		return result
	}
}

// MARK: - Substitution Parsing Helper

/// Splits a substitution body `PATTERN/REPLACEMENT/OPTIONS` on the `/`
/// delimiter, respecting backslash escapes.
private func splitSubstitution(
	_ body: String,
) -> (pattern: String, replacement: String, options: String)? {
	var parts: [String] = []
	var current = ""
	var escaped = false

	for ch in body {
		if escaped {
			current.append(ch)
			escaped = false
		} else if ch == "\\" {
			current.append(ch)
			escaped = true
		} else if ch == "/", parts.count < 2 {
			parts.append(current)
			current = ""
		} else {
			current.append(ch)
		}
	}

	// `current` now holds the options string (may be empty).
	guard parts.count == 2 else { return nil }
	return (pattern: parts[0], replacement: parts[1], options: current)
}
