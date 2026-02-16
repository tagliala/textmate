import Foundation
import Testing
@testable import TMCore

/// Benchmarks for `TextBuffer` piece-table operations.
///
/// These tests measure performance characteristics at various buffer sizes.
/// They use `ContinuousClock` for wall-clock measurements and verify that
/// basic operations complete within reasonable time bounds (guards against
/// quadratic regressions).
@Suite("TextBuffer — Benchmarks")
struct TextBufferBenchmarks {
	// MARK: - Helpers

	/// Generates a string of the given byte count filled with printable ASCII
	/// characters and scattered newlines.
	private func generateText(size: Int) -> String {
		var bytes = [UInt8](repeating: 0, count: size)
		for i in 0 ..< size {
			if i > 0, i % 80 == 0 {
				bytes[i] = UInt8(ascii: "\n")
			} else {
				// Printable ASCII range 32–126
				bytes[i] = UInt8(32 + (i % 95))
			}
		}
		return String(decoding: bytes, as: UTF8.self)
	}

	// MARK: - Sequential Insert

	@Test func sequentialInsert_10k() {
		let clock = ContinuousClock()
		let buf = TextBuffer("")
		let chunk = "Hello, world!\n"

		let elapsed = clock.measure {
			for _ in 0 ..< 10000 {
				buf.insert(at: buf.size, string: chunk)
			}
		}

		#expect(buf.lines > 10000)
		// Release-mode: should complete well under 1 second.
		#expect(elapsed < .seconds(1))
	}

	@Test func sequentialInsert_100k() {
		let clock = ContinuousClock()
		let buf = TextBuffer("")
		let chunk = "x"

		let elapsed = clock.measure {
			for _ in 0 ..< 100_000 {
				buf.insert(at: buf.size, string: chunk)
			}
		}

		#expect(buf.size == 100_000)
		#expect(elapsed < .seconds(2))
	}

	// MARK: - Random Insert

	@Test func randomInsert_2k() {
		let clock = ContinuousClock()
		let buf = TextBuffer(generateText(size: 1000))

		// Use a simple deterministic "random" position.
		var pos = 0
		let elapsed = clock.measure {
			for _ in 0 ..< 2000 {
				pos = (pos * 31 + 7) % max(buf.size, 1)
				buf.insert(at: pos, string: "a")
			}
		}

		#expect(buf.size == 3000)
		// Release-mode: piece table random insert should be fast.
		#expect(elapsed < .seconds(2))
	}

	// MARK: - Random Erase

	@Test func randomErase_2k() {
		let clock = ContinuousClock()
		let initialSize = 5000
		let buf = TextBuffer(generateText(size: initialSize))

		var pos = 0
		let elapsed = clock.measure {
			for _ in 0 ..< 2000 {
				let sz = buf.size
				if sz <= 1 { break }
				pos = (pos * 31 + 7) % (sz - 1)
				buf.erase(from: pos, to: pos + 1)
			}
		}

		#expect(buf.size == initialSize - 2000)
		#expect(elapsed < .seconds(2))
	}

	// MARK: - Substring Extraction

	@Test func substringExtraction_large() {
		let text = generateText(size: 100_000)
		let buf = TextBuffer(text)
		let clock = ContinuousClock()

		let elapsed = clock.measure {
			for i in stride(from: 0, to: 100_000, by: 1000) {
				let end = min(i + 500, buf.size)
				_ = buf.substring(from: i, to: end)
			}
		}

		#expect(elapsed < .seconds(1))
	}

	// MARK: - Line Operations

	@Test func lineStartEnd_large() {
		let text = generateText(size: 50000)
		let buf = TextBuffer(text)
		let clock = ContinuousClock()

		let lines = buf.lines
		let elapsed = clock.measure {
			for line in 0 ..< lines {
				_ = buf.lineStart(line)
				_ = buf.lineEnd(line)
			}
		}

		#expect(elapsed < .seconds(2))
	}

	// MARK: - Offset ↔ Position Conversion

	@Test func offsetPositionConversion_large() {
		let text = generateText(size: 50000)
		let buf = TextBuffer(text)
		let clock = ContinuousClock()

		let elapsed = clock.measure {
			for offset in stride(from: 0, to: buf.size, by: 100) {
				let pos = buf.convert(offset: offset)
				let roundTrip = buf.convert(position: pos)
				_ = roundTrip
			}
		}

		#expect(elapsed < .seconds(2))
	}

	// MARK: - Mixed Operations Stress Test

	@Test func mixedOperations_stress() {
		let clock = ContinuousClock()
		let buf = TextBuffer(generateText(size: 10000))
		let strictBenchmarks = ProcessInfo.processInfo.environment["TM_STRICT_BENCHMARKS"] == "1"
		let maxDuration: Duration = strictBenchmarks ? .seconds(2) : .seconds(5)

		let elapsed = clock.measure {
			for i in 0 ..< 5000 {
				let sz = buf.size
				if sz < 10 {
					buf.insert(at: 0, string: "padding text\n")
					continue
				}
				let pos = (i * 37 + 13) % (sz - 1)
				switch i % 4 {
				case 0: // insert
					buf.insert(at: pos, string: "new")
				case 1: // erase single char
					buf.erase(from: pos, to: pos + 1)
				case 2: // replace
					let end = min(pos + 3, sz)
					buf.replace(from: pos, to: end, with: "AB")
				default: // substring
					let end = min(pos + 50, sz)
					_ = buf.substring(from: pos, to: end)
				}
			}
		}

		#expect(elapsed < maxDuration)
	}
}
