import Foundation

/// A matched range within a candidate string (UTF-8 byte offsets).
public struct CoverRange: Equatable, Sendable {
	/// Start byte offset (inclusive).
	public let start: Int
	/// End byte offset (exclusive).
	public let end: Int

	public init(start: Int, end: Int) {
		self.start = start
		self.end = end
	}

	/// Length in bytes.
	public var length: Int {
		end - start
	}
}

/// Result of fuzzy ranking a filter against a candidate.
public struct RankResult: Equatable, Sendable {
	/// Score in (0, 1]. Zero means no match.
	public let score: Double
	/// Byte ranges in the candidate that matched the filter characters.
	public let coverRanges: [CoverRange]
	/// Whether this is a match (score > 0).
	public var isMatch: Bool {
		score > 0
	}

	public static let noMatch = RankResult(score: 0, coverRanges: [])
}

/// Fuzzy matching engine — port of TextMate's `oak::rank()` algorithm.
///
/// The algorithm uses a matrix-based approach to find the best alignment of filter
/// characters within a candidate string, preferring:
/// - CamelCase matches (filter chars landing on word boundaries / uppercase letters)
/// - Longer contiguous runs (fewer separate match segments)
/// - Earlier matches within the candidate
/// - Higher filter-to-candidate length ratio
public enum FuzzyRanker {
	// MARK: - Public API

	/// Normalize a filter string: lowercase and strip spaces.
	public static func normalizeFilter(_ filter: String) -> String {
		filter.lowercased().replacingOccurrences(of: " ", with: "")
	}

	/// Rank a filter against a candidate string.
	///
	/// - Parameters:
	///   - filter: The search string (should be pre-normalized via `normalizeFilter`).
	///   - candidate: The string to match against.
	/// - Returns: A `RankResult` with score in (0, 1] for matches, or `.noMatch`.
	public static func rank(filter: String, candidate: String) -> RankResult {
		// Empty filter matches everything with score 1
		if filter.isEmpty {
			return RankResult(score: 1, coverRanges: [])
		}

		// Convert to UTF-8 byte arrays for efficient indexed access
		let filterBytes = Array(filter.utf8)
		let candidateBytes = Array(candidate.utf8)

		let n = filterBytes.count
		let m = candidateBytes.count

		// Empty candidate can't match non-empty filter
		if m == 0 {
			return .noMatch
		}

		// Subsequence check — every filter char must appear in candidate in order
		if !isSubsequence(filterBytes, of: candidateBytes) {
			return .noMatch
		}

		// Exact match
		if n == m, filterBytes.elementsEqual(candidateBytes, by: { toLower($0) == toLower($1) }) {
			return RankResult(score: 1, coverRanges: [CoverRange(start: 0, end: m)])
		}

		// Overflow guard — avoid huge matrix allocations
		if n * m > 8096 {
			let ratio = Double(n) / Double(m)
			return RankResult(score: ratio, coverRanges: [])
		}

		return calculateRank(filterBytes: filterBytes, candidateBytes: candidateBytes)
	}

	// MARK: - Private Implementation

	/// Check if needle is a subsequence of haystack (case-insensitive).
	private static func isSubsequence(_ needle: [UInt8], of haystack: [UInt8]) -> Bool {
		var ni = 0
		for hi in 0 ..< haystack.count {
			guard ni < needle.count else { break }
			let nch = needle[ni]
			let hch = haystack[hi]
			if nch == toLower(hch) || toUpper(nch) == hch {
				ni += 1
			}
		}
		return ni == needle.count
	}

	/// Core ranking algorithm — 4-phase matrix-based approach.
	private static func calculateRank(filterBytes: [UInt8], candidateBytes: [UInt8]) -> RankResult {
		let n = filterBytes.count
		let m = candidateBytes.count

		// Phase 1: Build match matrix and detect capitals
		var matrix = Array(repeating: Array(repeating: 0, count: m), count: n)
		var first = Array(repeating: m, count: n) // first matching column per filter char
		var last = Array(repeating: 0, count: n) // last matching column + 1 per filter char
		var capitals = Array(repeating: false, count: m)

		// Detect "capital" positions (word boundaries + uppercase)
		detectCapitals(candidateBytes, capitals: &capitals)

		// Fill matrix — diagonal run lengths
		for i in 0 ..< n {
			let minJ = i == 0 ? 0 : (first[i - 1] + 1)
			var foundFirst = false
			for j in minJ ..< m {
				if toLower(filterBytes[i]) == toLower(candidateBytes[j]) {
					if i > 0, j > 0, matrix[i - 1][j - 1] > 0 {
						matrix[i][j] = matrix[i - 1][j - 1] + 1
					} else {
						matrix[i][j] = 1
					}
					if !foundFirst {
						first[i] = j
						foundFirst = true
					}
					last[i] = j + 1
				}
			}
			if !foundFirst {
				return .noMatch
			}
		}

		// Phase 2: Backward propagation — tighten column bounds
		for i in stride(from: n - 1, through: 1, by: -1) {
			if last[i] - 1 < last[i - 1] {
				last[i - 1] = last[i] // can't go past the last match position of next row
			}
		}

		// Phase 3: Propagate run lengths backward then forward
		// Backward: copy run lengths up
		for i in stride(from: n - 1, through: 1, by: -1) {
			for j in first[i] ..< last[i] {
				if matrix[i][j] > 0, j > 0, matrix[i - 1][j - 1] > 0 {
					matrix[i - 1][j - 1] = matrix[i][j]
				}
			}
		}

		// Forward: propagate run continuation
		for i in 0 ..< n - 1 {
			for j in first[i] ..< last[i] {
				if matrix[i][j] > 1 {
					let ni = i + 1
					let nj = j + 1
					if ni < n, nj < m, matrix[ni][nj] > 0 {
						matrix[ni][nj] = matrix[i][j] - 1
					}
				}
			}
		}

		// Phase 4: Greedy walk — select best matching positions
		var coverRanges: [CoverRange] = []
		var capitalsTouched = 0
		var substrings = 0
		var prefixSize = 0
		var lastMatchJ = -2 // track continuity

		for i in 0 ..< n {
			var bestJ = -1
			var bestLen = 0
			var bestIsCapital = false

			for j in first[i] ..< last[i] {
				guard matrix[i][j] > 0 else { continue }

				let isCapital = capitals[j]

				// Short filter optimization: prefer capitals
				if n < 4, isCapital, !bestIsCapital {
					bestJ = j
					bestLen = matrix[i][j]
					bestIsCapital = true
					continue
				}
				if n < 4, bestIsCapital, !isCapital {
					continue
				}

				// Prefer longer runs, or capitals as tiebreaker
				if matrix[i][j] > bestLen || (matrix[i][j] == bestLen && isCapital && !bestIsCapital) {
					bestJ = j
					bestLen = matrix[i][j]
					bestIsCapital = isCapital
				}
			}

			if bestJ < 0 {
				return .noMatch
			}

			if bestIsCapital {
				capitalsTouched += 1
			}

			// Track substrings (contiguous matched segments)
			if bestJ != lastMatchJ + 1 {
				substrings += 1
			}

			if i == 0 {
				prefixSize = bestJ
			}

			// Emit cover range (extend previous if contiguous)
			if let lastRange = coverRanges.last, lastRange.end == bestJ {
				coverRanges[coverRanges.count - 1] = CoverRange(start: lastRange.start, end: bestJ + 1)
			} else {
				coverRanges.append(CoverRange(start: bestJ, end: bestJ + 1))
			}

			lastMatchJ = bestJ

			// Advance: skip consumed diagonal run positions
			if bestLen > 1, i + 1 < n {
				first[i + 1] = max(first[i + 1], bestJ + 1)
			}
		}

		// Calculate score
		let totalCapitals = capitals.filter(\.self).count
		let denom = Double(n * (n + 1) + 1)
		var score: Double

		if capitalsTouched == n {
			// Perfect CamelCase match
			score = (denom - 1) / denom
		} else {
			let subtract = Double(substrings * n + (n - capitalsTouched))
			score = (denom - subtract) / denom
		}

		// Bonus terms (tiebreakers)
		score += Double(m - prefixSize) / Double(m) / (2 * denom) // Early match bonus
		if totalCapitals > 0 {
			score += Double(capitalsTouched) / Double(totalCapitals) / (4 * denom) // Capital coverage
		}
		score += Double(n) / Double(m) / (8 * denom) // Length ratio

		// Clamp to valid range
		score = min(max(score, 0), 1)

		return RankResult(score: score, coverRanges: coverRanges)
	}

	/// Detect "capital" positions — word boundaries and uppercase letters.
	private static func detectCapitals(_ bytes: [UInt8], capitals: inout [Bool]) {
		var atBow = true // at beginning of word
		for i in 0 ..< bytes.count {
			let ch = bytes[i]
			if isAlphanumeric(ch) {
				if atBow || isUpper(ch) {
					capitals[i] = true
				}
				atBow = false
			} else {
				// Non-alphanumeric except ' and . resets BOW
				if ch != UInt8(ascii: "'"), ch != UInt8(ascii: ".") {
					atBow = true
				}
			}
		}
	}

	// MARK: - ASCII Helpers

	@inline(__always)
	private static func toLower(_ ch: UInt8) -> UInt8 {
		(ch >= 0x41 && ch <= 0x5A) ? ch + 32 : ch
	}

	@inline(__always)
	private static func toUpper(_ ch: UInt8) -> UInt8 {
		(ch >= 0x61 && ch <= 0x7A) ? ch - 32 : ch
	}

	@inline(__always)
	private static func isUpper(_ ch: UInt8) -> Bool {
		ch >= 0x41 && ch <= 0x5A
	}

	@inline(__always)
	private static func isAlphanumeric(_ ch: UInt8) -> Bool {
		(ch >= 0x30 && ch <= 0x39) || (ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A)
	}
}
