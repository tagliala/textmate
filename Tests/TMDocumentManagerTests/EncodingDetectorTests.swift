import Foundation
import Testing
@testable import TMDocumentManager

@Suite("EncodingDetector")
struct EncodingDetectorTests {
	// MARK: - Initialization

	@Test("Creates empty classifier")
	func emptyClassifier() {
		let detector = EncodingDetector()
		#expect(detector.charsets().isEmpty)
	}

	// MARK: - Learning

	@Test("Learning adds charset")
	func learnAddsCharset() {
		let detector = EncodingDetector()
		let sample = "Héllo wörld café".data(using: .utf8)!
		detector.learn(from: sample, charset: "UTF-8")
		#expect(detector.charsets().contains("UTF-8"))
	}

	@Test("Learning multiple charsets")
	func learnMultipleCharsets() {
		let detector = EncodingDetector()
		let utf8Sample = "Héllo wörld café résumé naïve".data(using: .utf8)!
		let latin1Sample = "Héllo wörld café résumé naïve".data(using: .isoLatin1)!
		detector.learn(from: utf8Sample, charset: "UTF-8")
		detector.learn(from: latin1Sample, charset: "ISO-8859-1")
		let charsets = detector.charsets()
		#expect(charsets.contains("UTF-8"))
		#expect(charsets.contains("ISO-8859-1"))
	}

	// MARK: - Probability

	@Test("Unknown charset returns zero probability")
	func unknownCharsetZero() {
		let detector = EncodingDetector()
		let data = "hello".data(using: .utf8)!
		let prob = detector.probability(of: data, being: "UNKNOWN")
		#expect(prob == 0)
	}

	@Test("Learned charset has non-zero probability for similar data")
	func learnedCharsetProbability() {
		let detector = EncodingDetector()
		let training = "Héllo wörld café résumé naïve über straße".data(using: .utf8)!
		detector.learn(from: training, charset: "UTF-8")
		let test = "Héllo café".data(using: .utf8)!
		let prob = detector.probability(of: test, being: "UTF-8")
		#expect(prob > 0)
	}

	@Test("ASCII-only data produces no discriminating words")
	func asciiOnlyData() {
		let detector = EncodingDetector()
		let training = "Héllo wörld".data(using: .utf8)!
		detector.learn(from: training, charset: "UTF-8")
		let asciiData = "hello world".data(using: .utf8)!
		let prob = detector.probability(of: asciiData, being: "UTF-8")
		// ASCII-only has no high bytes, so probability is based on
		// byte-level fallback — should be some finite value
		#expect(prob >= 0 && prob <= 1)
	}

	// MARK: - Persistence

	@Test("Save and load round-trips correctly")
	func saveLoadRoundTrip() throws {
		let detector = EncodingDetector()
		let sample = "Héllo wörld café résumé naïve über".data(using: .utf8)!
		detector.learn(from: sample, charset: "UTF-8")

		let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("encoding_test_\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: tmpURL) }

		try detector.save(to: tmpURL)

		let loaded = EncodingDetector()
		try loaded.load(from: tmpURL)

		#expect(loaded.charsets() == detector.charsets())

		// Probability should match for same test data
		let test = "café résumé".data(using: .utf8)!
		let origProb = detector.probability(of: test, being: "UTF-8")
		let loadedProb = loaded.probability(of: test, being: "UTF-8")
		#expect(origProb == loadedProb)
	}

	@Test("Load from non-existent file throws")
	func loadNonExistent() {
		let detector = EncodingDetector()
		let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).json")
		#expect(throws: (any Error).self) {
			try detector.load(from: url)
		}
	}

	@Test("Load from invalid JSON throws")
	func loadInvalidJSON() throws {
		let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("invalid_encoding_\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: tmpURL) }
		let invalidJSONData = try #require("not json".data(using: .utf8))
		try invalidJSONData.write(to: tmpURL)

		let detector = EncodingDetector()
		#expect(throws: (any Error).self) {
			try detector.load(from: tmpURL)
		}
	}
}

@Suite("FrequencyRecord")
struct FrequencyRecordTests {
	@Test("Default frequency record is empty")
	func defaultEmpty() {
		let record = FrequencyRecord()
		#expect(record.wordCounts.isEmpty)
		#expect(record.byteCounts.isEmpty)
		#expect(record.totalWords == 0)
		#expect(record.totalBytes == 0)
	}

	@Test("Frequency record is Codable")
	func codableRoundTrip() throws {
		var record = FrequencyRecord()
		record.wordCounts["café"] = 5
		record.byteCounts[0xC3] = 10
		record.totalWords = 5
		record.totalBytes = 10

		let data = try JSONEncoder().encode(record)
		let decoded = try JSONDecoder().decode(FrequencyRecord.self, from: data)
		#expect(decoded == record)
	}

	@Test("Frequency record equality")
	func equality() {
		var a = FrequencyRecord()
		a.wordCounts["test"] = 1
		var b = FrequencyRecord()
		b.wordCounts["test"] = 1
		#expect(a == b)
		b.wordCounts["test"] = 2
		#expect(a != b)
	}
}
