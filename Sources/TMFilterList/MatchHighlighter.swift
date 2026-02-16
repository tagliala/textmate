#if canImport(AppKit)
import AppKit
#endif

/// Builds attributed strings with highlighted match ranges from fuzzy ranking results.
public enum MatchHighlighter {
	/// Style configuration for match highlighting.
	public struct Style: Sendable {
		/// Background color for matched ranges.
		public var matchBackgroundColor: String
		/// Underline color for matched ranges.
		public var matchUnderlineColor: String
		/// Font for the base text.
		public var font: String
		/// Font size.
		public var fontSize: Double

		public static let `default` = Style(
			matchBackgroundColor: "tmMatchedTextBackgroundColor",
			matchUnderlineColor: "tmMatchedTextUnderlineColor",
			font: "system",
			fontSize: 13,
		)

		public init(
			matchBackgroundColor: String = "tmMatchedTextBackgroundColor",
			matchUnderlineColor: String = "tmMatchedTextUnderlineColor",
			font: String = "system",
			fontSize: Double = 13,
		) {
			self.matchBackgroundColor = matchBackgroundColor
			self.matchUnderlineColor = matchUnderlineColor
			self.font = font
			self.fontSize = fontSize
		}
	}

	#if canImport(AppKit)

	/// Create an attributed string with highlighted match ranges.
	///
	/// - Parameters:
	///   - text: The full candidate text.
	///   - coverRanges: Byte-offset ranges from `FuzzyRanker.rank()`.
	///   - lineBreakMode: Line break mode for the paragraph style.
	///   - style: Visual style configuration.
	/// - Returns: An `NSMutableAttributedString` with highlight attributes on matched ranges.
	public static func attributedString(
		for text: String,
		coverRanges: [CoverRange],
		lineBreakMode: NSLineBreakMode = .byTruncatingTail,
		style _: Style = .default,
	) -> NSMutableAttributedString {
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.lineBreakMode = lineBreakMode

		let baseAttributes: [NSAttributedString.Key: Any] = [
			.paragraphStyle: paragraphStyle,
		]

		let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)

		// Convert byte offsets to String.Index ranges and apply highlight
		let utf8 = text.utf8
		for cover in coverRanges {
			guard cover.start >= 0, cover.end <= utf8.count, cover.start < cover.end else {
				continue
			}

			let startIndex = utf8.index(utf8.startIndex, offsetBy: cover.start)
			let endIndex = utf8.index(utf8.startIndex, offsetBy: cover.end)

			// Convert UTF-8 indices to NSRange
			let nsStart = text.distance(from: text.startIndex, to: startIndex)
			let nsEnd = text.distance(from: text.startIndex, to: endIndex)
			let nsRange = NSRange(location: nsStart, length: nsEnd - nsStart)

			let matchColor = NSColor.controlAccentColor.withAlphaComponent(0.2)
			let underlineColor = NSColor.controlAccentColor

			attributed.addAttributes([
				.backgroundColor: matchColor,
				.underlineStyle: NSUnderlineStyle.single.rawValue,
				.underlineColor: underlineColor,
			], range: nsRange)
		}

		return attributed
	}

	#endif

	/// Split cover ranges at a boundary offset into two groups.
	///
	/// This is used by FileChooser and BundleItemChooser to split match ranges
	/// between a path prefix and a filename suffix.
	///
	/// - Parameters:
	///   - coverRanges: The full cover ranges from ranking.
	///   - boundary: The byte offset where the split occurs (e.g. directory.utf8.count + 1).
	/// - Returns: A tuple of (prefixRanges, suffixRanges) with offsets adjusted.
	public static func splitCoverRanges(
		_ coverRanges: [CoverRange],
		at boundary: Int,
	) -> (prefix: [CoverRange], suffix: [CoverRange]) {
		var prefixRanges: [CoverRange] = []
		var suffixRanges: [CoverRange] = []

		for range in coverRanges {
			if range.end <= boundary {
				// Entirely in prefix
				prefixRanges.append(range)
			} else if range.start >= boundary {
				// Entirely in suffix — adjust offset
				suffixRanges.append(CoverRange(
					start: range.start - boundary,
					end: range.end - boundary,
				))
			} else {
				// Spans the boundary — split it
				prefixRanges.append(CoverRange(start: range.start, end: boundary))
				suffixRanges.append(CoverRange(start: 0, end: range.end - boundary))
			}
		}

		return (prefixRanges, suffixRanges)
	}
}
