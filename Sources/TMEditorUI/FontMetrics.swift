import AppKit
import CoreText

/// Font metrics calculated from a CoreText font, providing the measurements
/// needed for text layout.
///
/// Counterpart of the C++ `ct::metrics_t` in `Frameworks/layout/src/ct.h`.
public struct FontMetrics: Sendable {
	/// The font ascent (distance from baseline to top of tallest glyph).
	public let ascent: CGFloat
	/// The font descent (distance from baseline to bottom of deepest glyph).
	public let descent: CGFloat
	/// The inter-line leading.
	public let leading: CGFloat
	/// The x-height (height of lowercase 'x').
	public let xHeight: CGFloat
	/// The cap height (height of uppercase letters).
	public let capHeight: CGFloat
	/// The width of a single monospace column (width of '0').
	public let columnWidth: CGFloat

	/// Additional vertical padding above the baseline.
	private let ascentDelta: CGFloat = 1
	/// Additional vertical padding in leading area.
	private let leadingDelta: CGFloat = 1

	/// Creates font metrics from an `NSFont`.
	public init(font: NSFont) {
		let ctFont = font as CTFont
		ascent = CTFontGetAscent(ctFont)
		descent = CTFontGetDescent(ctFont)
		leading = CTFontGetLeading(ctFont)
		xHeight = CTFontGetXHeight(ctFont)
		capHeight = CTFontGetCapHeight(ctFont)

		// Measure the width of '0' for column width (monospace metric)
		let zeroChar: UniChar = 0x0030 // '0'
		var glyph: CGGlyph = 0
		var advance = CGSize.zero
		_ = withUnsafePointer(to: zeroChar) { charPtr in
			CTFontGetGlyphsForCharacters(ctFont, charPtr, &glyph, 1)
		}
		CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
		columnWidth = advance.width > 0 ? advance.width : 8
	}

	/// Creates font metrics from a font name and size.
	public init(fontName: String, fontSize: CGFloat) {
		let font = NSFont(name: fontName, size: fontSize)
			?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
		self.init(font: font)
	}

	/// The baseline position, accounting for minimum ascent requirements.
	public func baseline(minAscent: CGFloat = 0) -> CGFloat {
		(max(minAscent, ascent) + ascentDelta).rounded()
	}

	/// The full line height including ascent, descent, leading, and padding.
	public func lineHeight(
		minAscent: CGFloat = 0,
		minDescent: CGFloat = 0,
		minLeading: CGFloat = 0,
	) -> CGFloat {
		let effectiveAscent = max(minAscent, ascent) + ascentDelta
		let effectiveDescent = max(minDescent, descent)
		let effectiveLeading = max(minLeading, leading) + leadingDelta
		return (effectiveAscent + effectiveDescent + effectiveLeading).rounded(.up)
	}
}
