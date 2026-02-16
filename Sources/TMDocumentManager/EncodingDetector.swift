import Foundation

/// Bayesian character encoding classifier.
///
/// Ports `Frameworks/encoding/src/encoding.mm`.
/// Uses word and byte frequency analysis to estimate the probability
/// that a given byte sequence belongs to a particular character encoding.
///
/// The classifier learns from known-encoding text samples and builds
/// frequency tables. When presented with unknown-encoding text, it
/// calculates a Bayesian probability for each known charset.
///
/// ## Usage
///
/// ```swift
/// let detector = EncodingDetector.shared
///
/// // Learn from known samples
/// detector.learn(from: utf8Data, charset: "UTF-8")
/// detector.learn(from: latin1Data, charset: "ISO-8859-1")
///
/// // Detect encoding
/// let prob = detector.probability(of: unknownData, being: "UTF-8")
/// ```
///
/// Unlike the C++ version which used Cap'n Proto for serialization,
/// this Swift implementation uses `Codable` (JSON) for persistence.
public final class EncodingDetector: Sendable {
	/// Shared singleton instance.
	public static let shared = EncodingDetector()

	/// Lock-free concurrent access managed via actor isolation.
	private let state = EncodingState()

	public init() {}

	// MARK: - Public API

	/// Get all known charset names.
	public func charsets() -> [String] {
		state.charsets()
	}

	/// Calculate the probability that `data` is encoded in `charset`.
	///
	/// - Parameters:
	///   - data: The raw bytes to analyze.
	///   - charset: The charset to test (e.g., "UTF-8", "ISO-8859-1").
	/// - Returns: A probability value between 0.0 and 1.0.
	public func probability(of data: Data, being charset: String) -> Double {
		state.probability(data: data, charset: charset)
	}

	/// Learn character frequency patterns from a known-encoding sample.
	///
	/// - Parameters:
	///   - data: The raw bytes of the sample.
	///   - charset: The known charset of the sample.
	public func learn(from data: Data, charset: String) {
		state.learn(data: data, charset: charset)
	}

	/// Save the learned frequency data to a file.
	///
	/// - Parameter url: The file URL to save to.
	/// - Throws: If encoding or writing fails.
	public func save(to url: URL) throws {
		let data = try state.serialize()
		try data.write(to: url, options: .atomic)
	}

	/// Load frequency data from a file.
	///
	/// - Parameter url: The file URL to load from.
	/// - Throws: If reading or decoding fails.
	public func load(from url: URL) throws {
		let data = try Data(contentsOf: url)
		try state.deserialize(data)
	}
}

// MARK: - Internal State

/// Thread-safe mutable state for the encoding detector.
///
/// Uses `NSLock` for thread safety since the classifier needs
/// mutable shared state but doesn't need actor isolation overhead.
final class EncodingState: @unchecked Sendable {
	private let lock = NSLock()
	private var classifier = Classifier()

	func charsets() -> [String] {
		lock.lock()
		defer { lock.unlock() }
		return Array(classifier.charsets.keys.sorted())
	}

	func probability(data: Data, charset: String) -> Double {
		lock.lock()
		defer { lock.unlock() }
		return classifier.probability(data: data, charset: charset)
	}

	func learn(data: Data, charset: String) {
		lock.lock()
		defer { lock.unlock() }
		classifier.learn(data: data, charset: charset)
	}

	func serialize() throws -> Data {
		lock.lock()
		defer { lock.unlock() }
		return try JSONEncoder().encode(classifier)
	}

	func deserialize(_ data: Data) throws {
		lock.lock()
		defer { lock.unlock() }
		classifier = try JSONDecoder().decode(Classifier.self, from: data)
	}
}

// MARK: - Classifier

/// Bayesian frequency classifier for character encodings.
///
/// Maintains per-charset word and byte frequency tables plus
/// a combined table for computing Bayesian probabilities.
struct Classifier: Codable, Equatable, Sendable {
	/// Per-charset frequency records.
	var charsets: [String: FrequencyRecord] = [:]

	/// Combined frequency record across all charsets.
	var combined: FrequencyRecord = .init()

	// MARK: - Learning

	/// Learn from a data sample with known encoding.
	mutating func learn(data: Data, charset: String) {
		let words = extractWords(from: data)
		for word in words {
			charsets[charset, default: FrequencyRecord()].wordCounts[word, default: 0] += 1
			charsets[charset, default: FrequencyRecord()].totalWords += 1
			combined.wordCounts[word, default: 0] += 1
			combined.totalWords += 1

			// Track high-byte frequencies
			for byte in word.utf8 where byte > 0x7F {
				charsets[charset, default: FrequencyRecord()].byteCounts[byte, default: 0] += 1
				charsets[charset, default: FrequencyRecord()].totalBytes += 1
				combined.byteCounts[byte, default: 0] += 1
				combined.totalBytes += 1
			}
		}
	}

	// MARK: - Probability

	/// Calculate the Bayesian probability that data belongs to a charset.
	func probability(data: Data, charset: String) -> Double {
		guard let record = charsets[charset] else { return 0 }

		let words = extractWords(from: data)
		var seen = Set<String>()
		var a: Double = 1
		var b: Double = 1

		for word in words {
			if let globalCount = combined.wordCounts[word], seen.insert(word).inserted {
				if let localCount = record.wordCounts[word] {
					let pWT = Double(localCount) / Double(record.totalWords)
					let pWF = Double(globalCount - localCount) / Double(combined.totalWords)
					let p = pWT / (pWT + pWF)
					a *= p
					b *= (1 - p)
				} else {
					a = 0
				}
			} else {
				// Fall back to byte-level analysis for unseen words
				for byte in word.utf8 where byte > 0x7F {
					if let globalByteCount = combined.byteCounts[byte] {
						if let localByteCount = record.byteCounts[byte] {
							let pWT = Double(localByteCount) / Double(record.totalBytes)
							let pWF = Double(globalByteCount - localByteCount) / Double(combined.totalBytes)
							let p = pWT / (pWT + pWF)
							a *= p
							b *= (1 - p)
						} else {
							a = 0
						}
					}
				}
			}
		}

		return (a + b) == 0 ? 0 : a / (a + b)
	}

	// MARK: - Word Extraction

	/// Extract words containing non-ASCII bytes from raw data.
	///
	/// A "word" starts with an alphabetic or high-byte character and extends
	/// until a non-alphanumeric low-ASCII character. Only words containing
	/// at least one byte > 0x7F are included, as those are the discriminating
	/// features for encoding detection.
	private func extractWords(from data: Data) -> [String] {
		var words: [String] = []
		var current: [UInt8] = []
		var hasHighByte = false

		for byte in data {
			let isAlpha = (byte >= 0x41 && byte <= 0x5A)
				|| (byte >= 0x61 && byte <= 0x7A)
			let isAlnum = isAlpha || (byte >= 0x30 && byte <= 0x39)
			let isHigh = byte > 0x7F

			if isAlpha || isHigh || (isAlnum && !current.isEmpty) {
				current.append(byte)
				if isHigh { hasHighByte = true }
			} else {
				if hasHighByte, !current.isEmpty,
				   let word = String(bytes: current, encoding: .utf8)
				   ?? String(bytes: current, encoding: .isoLatin1)
				{
					words.append(word)
				}
				current.removeAll()
				hasHighByte = false
			}
		}

		// Handle trailing word
		if hasHighByte, !current.isEmpty,
		   let word = String(bytes: current, encoding: .utf8)
		   ?? String(bytes: current, encoding: .isoLatin1)
		{
			words.append(word)
		}

		return words
	}
}

// MARK: - Frequency Record

/// Frequency counts for words and bytes within a charset.
struct FrequencyRecord: Codable, Equatable, Sendable {
	/// Word occurrence counts.
	var wordCounts: [String: Int] = [:]

	/// High-byte (> 0x7F) occurrence counts.
	var byteCounts: [UInt8: Int] = [:]

	/// Total number of words processed.
	var totalWords: Int = 0

	/// Total number of high bytes processed.
	var totalBytes: Int = 0
}
