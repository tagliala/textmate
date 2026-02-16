import Foundation

// MARK: - Version Comparison

/// Semantic-aware version string comparison.
///
/// Port of `Frameworks/SoftwareUpdate/src/OakCompareVersionStrings.mm`.
///
/// Splits version strings on `.`, `-`, `+` separators, strips trailing
/// zeroes, and compares components segment by segment.  Understands
/// semver precedence:
/// - `-` denotes a prerelease (sorts before a release).
/// - `+` denotes build metadata (ignored after the first `+`).
public enum VersionComparison {
	/// Compare two version strings.
	///
	/// - Returns: `.orderedAscending` if `lhs < rhs`, `.orderedDescending`
	///   if `lhs > rhs`, `.orderedSame` if equal.
	public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
		if less(lhs, rhs) {
			return .orderedAscending
		} else if less(rhs, lhs) {
			return .orderedDescending
		}
		return .orderedSame
	}

	/// Whether `lhs` is strictly less than `rhs`.
	///
	/// Direct port of C++ `version::less`.
	public static func less(_ lhs: String, _ rhs: String) -> Bool {
		let lhsV = stripTrailingZeroes(components(lhs))
		let rhsV = stripTrailingZeroes(components(rhs))

		var lhsIt = lhsV.makeIterator()
		var rhsIt = rhsV.makeIterator()

		var lhsVal = lhsIt.next()
		var rhsVal = rhsIt.next()

		while let l = lhsVal, let r = rhsVal {
			let lIsNumeric = isNumeric(l)
			let rIsNumeric = isNumeric(r)

			if l != r {
				if lIsNumeric, rIsNumeric {
					guard let ln = Int(l), let rn = Int(r) else { return l < r }
					if ln != rn { return ln < rn }
					// Same numeric value, different string representation
				} else {
					let lIsSep = isSeparator(l)
					if lIsSep {
						// `-` (prerelease) sorts before `.` (release)
						// `+` (build meta) sorts before `.`
						return l == "-" || (l == "+" && r == ".")
					}
					return l < r
				}
			} else if l == "+" {
				// Build metadata: everything after `+` is ignored
				return false
			}

			lhsVal = lhsIt.next()
			rhsVal = rhsIt.next()
		}

		// One or both exhausted
		if let l = lhsVal {
			return l == "-" // Extra components starting with `-` = prerelease
		}
		if let r = rhsVal {
			return r == "." // rhs has more version components = rhs is greater
		}
		return false
	}

	// MARK: - Private Helpers

	/// Split a version string into components, keeping separators as
	/// separate elements.
	///
	/// `"1.2.3-beta+build"` → `["1", ".", "2", ".", "3", "-", "beta", "+", "build"]`
	private static func components(_ str: String) -> [String] {
		var result: [String] = []
		var current = str.startIndex

		while current < str.endIndex {
			if let sepRange = str.range(
				of: "[.\\-+]",
				options: .regularExpression,
				range: current ..< str.endIndex,
			) {
				if current < sepRange.lowerBound {
					result.append(String(str[current ..< sepRange.lowerBound]))
				}
				result.append(String(str[sepRange]))
				current = sepRange.upperBound
			} else {
				result.append(String(str[current...]))
				break
			}
		}

		return result
	}

	/// Strip trailing zero segments (before any non-numeric segment).
	///
	/// `["1", ".", "2", ".", "0"]` → `["1", ".", "2"]`
	/// `["1", ".", "0", "-", "beta"]` → `["1", "-", "beta"]`
	private static func stripTrailingZeroes(_ src: [String]) -> [String] {
		// Find where non-numeric segments start
		var lastIdx = src.count
		for (i, s) in src.enumerated() {
			if !isNumeric(s), !isSeparatorDot(s) {
				lastIdx = i
				break
			}
		}

		// Strip trailing zeroes from the numeric prefix
		var end = lastIdx
		while end > 0 {
			let prev = src[end - 1]
			if isNumeric(prev), (Int(prev) ?? 0) == 0 {
				end -= 1
				// Also remove the preceding dot separator
				if end > 0, src[end - 1] == "." {
					end -= 1
				}
			} else {
				break
			}
		}

		var result = Array(src[..<end])
		if lastIdx < src.count {
			result += Array(src[lastIdx...])
		}
		return result
	}

	private static func isNumeric(_ str: String) -> Bool {
		!str.isEmpty && str.allSatisfy(\.isNumber)
	}

	private static func isSeparator(_ str: String) -> Bool {
		str == "." || str == "-" || str == "+"
	}

	private static func isSeparatorDot(_ str: String) -> Bool {
		str == "."
	}
}
