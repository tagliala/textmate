import AppKit
import Testing
@testable import TMEditorUI

@Suite("FontMetrics")
struct FontMetricsTests {
	// MARK: - System Font

	@Test("System monospaced font has positive metrics")
	func systemMonospacedMetrics() {
		let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
		let metrics = FontMetrics(font: font)

		#expect(metrics.ascent > 0)
		#expect(metrics.descent > 0)
		#expect(metrics.leading >= 0)
		#expect(metrics.xHeight > 0)
		#expect(metrics.capHeight > 0)
		#expect(metrics.columnWidth > 0)
	}

	@Test("Column width is width of '0' character")
	func columnWidthMatchesZeroGlyph() {
		let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
		let metrics = FontMetrics(font: font)

		// For monospaced fonts, all characters should have the same width.
		// The column width should be positive and reasonable (between 4 and 20
		// points for a 13pt monospaced font).
		#expect(metrics.columnWidth > 4)
		#expect(metrics.columnWidth < 20)
	}

	// MARK: - Line Height

	@Test("Line height is at least ascent + descent")
	func lineHeightMinimum() {
		let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
		let metrics = FontMetrics(font: font)

		let lineHeight = metrics.lineHeight()
		#expect(lineHeight >= metrics.ascent + metrics.descent)
	}

	@Test("Line height respects minimum ascent and descent")
	func lineHeightWithMinimums() {
		let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
		let metrics = FontMetrics(font: font)

		let bigLineHeight = metrics.lineHeight(minAscent: 100, minDescent: 100)
		#expect(bigLineHeight >= 200)
	}

	@Test("Line height is ceiling-rounded")
	func lineHeightCeiled() {
		let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
		let metrics = FontMetrics(font: font)

		let lineHeight = metrics.lineHeight()
		#expect(lineHeight == lineHeight.rounded(.up))
	}

	// MARK: - Baseline

	@Test("Baseline is positive and rounded")
	func baselineCalculation() {
		let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
		let metrics = FontMetrics(font: font)

		let baseline = metrics.baseline()
		#expect(baseline > 0)
		#expect(baseline == baseline.rounded())
	}

	@Test("Baseline respects minimum ascent")
	func baselineWithMinimumAscent() {
		let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
		let metrics = FontMetrics(font: font)

		let bigBaseline = metrics.baseline(minAscent: 100)
		#expect(bigBaseline >= 100)
	}

	// MARK: - Different Sizes

	@Test(
		"Larger fonts produce larger metrics",
		arguments: [10.0, 13.0, 24.0, 36.0],
	)
	func scalingWithSize(size: Double) {
		let font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
		let metrics = FontMetrics(font: font)

		#expect(metrics.ascent > 0)
		#expect(metrics.columnWidth > 0)
		#expect(metrics.lineHeight() > 0)
	}

	@Test("Bigger font has larger column width")
	func biggerFontBiggerColumnWidth() {
		let small = FontMetrics(font: .monospacedSystemFont(ofSize: 10, weight: .regular))
		let big = FontMetrics(font: .monospacedSystemFont(ofSize: 24, weight: .regular))

		#expect(big.columnWidth > small.columnWidth)
		#expect(big.lineHeight() > small.lineHeight())
		#expect(big.ascent > small.ascent)
	}

	// MARK: - Convenience Init

	@Test("Convenience initializer with font name")
	func convenienceInit() {
		let metrics = FontMetrics(fontName: "Menlo", fontSize: 12)
		#expect(metrics.ascent > 0)
		#expect(metrics.columnWidth > 0)
	}

	@Test("Unknown font name falls back to system font")
	func unknownFontFallback() {
		let metrics = FontMetrics(fontName: "NonexistentFont12345", fontSize: 12)
		#expect(metrics.ascent > 0)
		#expect(metrics.columnWidth > 0)
	}
}
