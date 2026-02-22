@preconcurrency import CoreGraphics

/// Configuration for rendering invisible characters and decorative elements.
///
/// Swift counterpart of C++ `ng::context_t` in `Frameworks/layout/src/ct.h`.
/// Manages:
/// - Invisible character glyphs (space, tab, newline) with configurable mapping
/// - Spelling dot image (for misspelling underlines)
/// - Folding dots image factory with size-based caching
public final class RenderContext: @unchecked Sendable {
	/// The CGContext for drawing.
	public let cgContext: CGContext

	/// The glyph string to draw for space characters (empty = don't draw).
	public private(set) var spaceGlyph: String = "·"
	/// The glyph string to draw for tab characters (empty = don't draw).
	public private(set) var tabGlyph: String = "‣"
	/// The glyph string to draw for newline characters (empty = don't draw).
	public private(set) var newlineGlyph: String = "¬"

	/// The spelling dot image used for misspelling underlines.
	public let spellingDotImage: CGImage?

	/// Factory function that creates a folding dots image for a given (width, height).
	private let foldingDotsFactory: ((Double, Double) -> CGImage?)?

	/// Cache of folding dots images keyed by (width, height).
	private var foldingDotsCache: [SizePair: CGImage] = [:]

	/// Hashable pair of doubles for cache keys.
	private struct SizePair: Hashable {
		let width: Double
		let height: Double
	}

	/// Creates a render context.
	///
	/// - Parameters:
	///   - context: The Core Graphics context for drawing.
	///   - invisibleMap: A configuration string that maps invisible characters
	///     to their visual representation. Format: pairs of characters where
	///     the first is the invisible type (`' '`, `'\t'`, `'\n'`) and the second
	///     is its replacement glyph. Prefix with `~` to exclude a type.
	///     Default: `"~ ~\t~\n"` (use defaults for all).
	///   - spellingDot: Optional image for spelling dot decoration.
	///   - foldingDotsFactory: Optional factory for creating folding dots images.
	public init(
		context: CGContext,
		invisibleMap: String? = nil,
		spellingDot: CGImage? = nil,
		foldingDotsFactory: ((Double, Double) -> CGImage?)? = nil,
	) {
		cgContext = context
		spellingDotImage = spellingDot
		self.foldingDotsFactory = foldingDotsFactory
		setupInvisiblesMapping(invisibleMap ?? "~ ~\t~\n")
	}

	/// Returns a cached folding dots image for the given dimensions.
	///
	/// The image is created once per unique (width, height) pair and cached
	/// for subsequent calls.
	public func foldingDots(width: Double, height: Double) -> CGImage? {
		guard let factory = foldingDotsFactory else { return nil }

		let key = SizePair(width: width, height: height)
		if let cached = foldingDotsCache[key] {
			return cached
		}

		if let image = factory(width, height) {
			foldingDotsCache[key] = image
			return image
		}
		return nil
	}

	// MARK: - Private

	/// Parse the invisibles mapping string.
	///
	/// The C++ version uses a state machine that processes diacritics-aware
	/// characters. The mapping format is:
	/// - `~` followed by a type char means "exclude" (set glyph to empty)
	/// - A type char (` `, `\t`, `\n`) followed by a replacement glyph
	///
	/// Example: `" ·\t‣\n¬"` maps space→·, tab→‣, newline→¬
	/// Example: `"~ "` excludes space (no glyph drawn)
	private func setupInvisiblesMapping(_ str: String) {
		enum State {
			case waiting
			case exclude
			case space
			case tab
			case newline
		}

		var state: State = .waiting

		for ch in str.unicodeScalars {
			switch state {
			case .waiting:
				switch ch {
				case "~": state = .exclude
				case " ": state = .space
				case "\t": state = .tab
				case "\n": state = .newline
				default: break
				}
			case .exclude:
				switch ch {
				case " ": spaceGlyph = ""
				case "\t": tabGlyph = ""
				case "\n": newlineGlyph = ""
				default: break
				}
				state = .waiting
			case .space:
				spaceGlyph = String(ch)
				state = .waiting
			case .tab:
				tabGlyph = String(ch)
				state = .waiting
			case .newline:
				newlineGlyph = String(ch)
				state = .waiting
			}
		}
	}
}

// MARK: - Unprintable Character Representation

/// Returns a display representation for unprintable/control characters.
///
/// Port of the C++ `representation_for()` helper in `paragraph.cc`.
///
/// - Parameter scalar: The Unicode scalar value to check.
/// - Returns: A string representation, or `nil` if the character is printable.
func unprintableRepresentation(for scalar: Unicode.Scalar) -> String? {
	let ch = scalar.value

	// Standard printable ASCII + tab + newline → no special representation
	if (ch >= 0x20 && ch <= 0x7E) || ch == 0x09 || ch == 0x0A {
		return nil
	}

	switch ch {
	case 0x0C: return "<NP>"
	case 0x0D: return "<CR>"
	case 0x08: return "<BS>"
	case 0x00: return "<NUL>"
	case 0x1B: return "<ESC>"
	case 0x1C: return "<FS>"
	case 0x1D: return "<GS>"
	case 0x1E: return "<RS>"
	case 0x1F: return "<US>"
	case 0xA0: return "·" // Non-breaking space
	default:
		// Ctrl+A .. Ctrl+Z
		if ch > 0x00 && ch <= UInt32(Character("Z").asciiValue! - Character("A").asciiValue! + 1) {
			let letter = Character(UnicodeScalar(ch - 1 + UInt32(Character("A").asciiValue!))!)
			return "^\(letter)"
		}
		// Other C1 control characters
		if ch < 0x20 || (ch > 0x7E && ch < 0xA0) {
			return "◆"
		}
		// Unicode space characters
		let spaceChars: Set<UInt32> = [
			0x2028, // LINE SEPARATOR
			0x2029, // PARAGRAPH SEPARATOR
			0x2060, // WORD JOINER
			0xFEFF, // ZERO WIDTH NO-BREAK SPACE
		]
		if spaceChars.contains(ch) {
			return String(format: "<U+%04X>", ch)
		}
		return nil
	}
}
