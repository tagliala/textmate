import AppKit
@preconcurrency import CoreText
import TMGrammar

// MARK: - Resolved Style

/// A fully resolved style for rendering text at a specific scope.
///
/// Produced by ``ThemeEngine/stylesForScope(_:)-7r5hx`` after matching all theme
/// rules against the scope, ranking them, merging overlapping attributes, and
/// creating the appropriate `CTFont`.  This is the Swift equivalent of the C++
/// `styles_t` struct in `Frameworks/theme/src/theme.h`.
public struct ResolvedStyle: @unchecked Sendable {
	/// Foreground text color.
	public let foreground: CGColor
	/// Background color behind the text run.
	public let background: CGColor
	/// Caret (insertion point) color.
	public let caret: CGColor
	/// Selection highlight color.
	public let selection: CGColor
	/// The fully configured font, including bold/italic traits.
	public let font: CTFont
	/// Whether the text is underlined.
	public let isUnderlined: Bool
	/// Whether the text is struck through.
	public let isStrikethrough: Bool
	/// Whether the text is marked as misspelled.
	public let isMisspelled: Bool
}

// MARK: - Font Size Specification

/// Represents a font-size value parsed from a theme.
///
/// Positive values are absolute point sizes; negative `em`/`%` values
/// are resolved relative to the engine's base font size
/// (mirrors `read_font_size` in C++).
enum FontSizeSpec: Sendable {
	/// Absolute size in points.
	case absolute(CGFloat)
	/// Relative multiplier (e.g. `1.2em` → `.relative(1.2)`).
	case relative(CGFloat)

	/// Parse a font-size string that may end in "pt", "em", or "%".
	static func parse(_ string: String?) -> FontSizeSpec? {
		guard let string, !string.isEmpty else { return nil }

		let trimmed = string.trimmingCharacters(in: .whitespaces)
		if trimmed.hasSuffix("em") {
			let numStr = trimmed.dropLast(2).trimmingCharacters(in: .whitespaces)
			guard let value = Double(numStr) else { return nil }
			return .relative(CGFloat(value))
		} else if trimmed.hasSuffix("%") {
			let numStr = trimmed.dropLast(1).trimmingCharacters(in: .whitespaces)
			guard let value = Double(numStr) else { return nil }
			return .relative(CGFloat(value) / 100)
		} else {
			let numStr = trimmed.hasSuffix("pt")
				? trimmed.dropLast(2).trimmingCharacters(in: .whitespaces)
				: trimmed
			guard let value = Double(numStr), value > 0 else { return nil }
			return .absolute(CGFloat(value))
		}
	}

	/// Resolve to an absolute point size given a base size.
	func resolve(base: CGFloat) -> CGFloat {
		switch self {
		case let .absolute(size):
			size
		case let .relative(factor):
			base * factor
		}
	}
}

// MARK: - Tri-State Boolean

/// A three-valued boolean: true, false, or unset.
///
/// Used during style decomposition so that "unset" values pass through
/// without overriding previously established state — equivalent to
/// `enum bool_t { bool_true, bool_false, bool_unset }` in C++.
enum TriBool: Sendable {
	case `true`
	case `false`
	case unset

	init(_ value: Bool?) {
		switch value {
		case .some(true): self = .true
		case .some(false): self = .false
		case .none: self = .unset
		}
	}

	var boolValue: Bool {
		self == .true
	}
}

// MARK: - Decomposed Style

/// An intermediate style representation where every attribute is independently
/// optional ("unset").  Multiple decomposed styles are merged in scope-rank
/// order to produce a final ``ResolvedStyle``.
///
/// Equivalent to C++ `theme_t::decomposed_style_t`.
struct DecomposedStyle: Sendable {
	var fontName: String?
	var fontSizeSpec: FontSizeSpec?

	var foreground: ThemeColor?
	var background: ThemeColor?
	var caret: ThemeColor?
	var selection: ThemeColor?
	var invisibles: ThemeColor?

	var bold: TriBool = .unset
	var italic: TriBool = .unset
	var underlined: TriBool = .unset
	var strikethrough: TriBool = .unset
	var misspelled: TriBool = .unset

	/// Merge `rhs` into `self`.
	///
	/// - Foreground, caret, selection, invisibles: `rhs` replaces if set.
	/// - Background: `rhs` is alpha-blended on top of `self`.
	/// - Bool flags: `rhs` replaces if not `.unset`.
	/// - Font name: `rhs` replaces if set.
	/// - Font size: `rhs` replaces if set; relative sizes multiply.
	mutating func merge(_ rhs: DecomposedStyle) {
		fontName = rhs.fontName ?? fontName

		if let rhsSpec = rhs.fontSizeSpec {
			switch rhsSpec {
			case .absolute:
				fontSizeSpec = rhsSpec
			case let .relative(factor):
				if case let .absolute(base)? = fontSizeSpec {
					fontSizeSpec = .absolute(base * factor)
				} else {
					fontSizeSpec = rhsSpec
				}
			}
		}

		foreground = rhs.foreground ?? foreground
		background = blendBackground(base: background, overlay: rhs.background)
		caret = rhs.caret ?? caret
		selection = rhs.selection ?? selection
		invisibles = rhs.invisibles ?? invisibles

		bold = rhs.bold != .unset ? rhs.bold : bold
		italic = rhs.italic != .unset ? rhs.italic : italic
		underlined = rhs.underlined != .unset ? rhs.underlined : underlined
		strikethrough = rhs.strikethrough != .unset ? rhs.strikethrough : strikethrough
		misspelled = rhs.misspelled != .unset ? rhs.misspelled : misspelled
	}
}

/// Alpha-blend `overlay` on top of `base` (mirrors C++ `blend()`).
private func blendBackground(base: ThemeColor?, overlay: ThemeColor?) -> ThemeColor? {
	guard let overlay else { return base }
	guard let base else { return overlay }
	let a = overlay.alpha
	let ia = 1.0 - a
	return ThemeColor(
		red: ia * base.red + a * overlay.red,
		green: ia * base.green + a * overlay.green,
		blue: ia * base.blue + a * overlay.blue,
		alpha: base.alpha,
	)
}

// MARK: - Compiled Rule

/// A theme rule with its scope selector pre-compiled for fast matching.
struct CompiledRule: Sendable {
	let selector: ScopeSelector
	let style: DecomposedStyle
}

// MARK: - Theme Engine

/// Runtime engine that resolves scope-specific styles from a ``Theme``.
///
/// The engine pre-compiles all scope selectors from the theme's rules,
/// then provides ``stylesForScope(_:)-7r5hx`` which evaluates every rule
/// against the given scope, ranks matches, merges styles in rank order,
/// creates the appropriate `CTFont`, and caches the result.
///
/// This is the Swift equivalent of C++ `theme_t` and its
/// `styles_for_scope()` method.
///
/// ## Thread Safety
///
/// The engine is thread-safe: compiled rules are immutable and the
/// result cache uses `NSLock` for synchronization.
public final class ThemeEngine: @unchecked Sendable {
	/// The source theme.
	public let theme: Theme

	/// Base font name (nil → system monospace).
	public let fontName: String?

	/// Base font size in points.
	public let fontSize: CGFloat

	/// Pre-compiled rules with selectors.
	private let compiledRules: [CompiledRule]

	/// sRGB color space used for all CGColor creation.
	private let colorSpace: CGColorSpace

	// Thread-safe cache: scope string → resolved style.
	private let cacheLock = NSLock()
	private var cache: [Scope: ResolvedStyle] = [:]

	/// Creates a theme engine from a loaded theme.
	///
	/// - Parameters:
	///   - theme: The parsed theme.
	///   - fontName: Base font name, or `nil` for the system monospace font.
	///   - fontSize: Base font size in points.
	public init(theme: Theme, fontName: String? = nil, fontSize: CGFloat = 12) {
		self.theme = theme
		self.fontName = fontName
		self.fontSize = fontSize
		colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
		compiledRules = Self.compileRules(from: theme)
	}

	/// Returns a new engine with the same theme but different font settings.
	public func copyWithFont(name: String?, size: CGFloat) -> ThemeEngine {
		ThemeEngine(theme: theme, fontName: name, fontSize: size)
	}

	// MARK: - Style Resolution

	/// Resolves the fully merged style for a scope.
	///
	/// All theme rules are scored against `scope`, sorted by rank, and
	/// merged.  A `CTFont` is created with bold/italic traits applied.
	/// Results are cached by scope identity.
	///
	/// - Parameter scope: The scope to resolve styles for.
	/// - Returns: The resolved style for rendering.
	public func stylesForScope(_ scope: Scope) -> ResolvedStyle {
		cacheLock.lock()
		if let cached = cache[scope] {
			cacheLock.unlock()
			return cached
		}
		cacheLock.unlock()

		let resolved = resolveStyles(for: ScopeContext(scope))

		cacheLock.lock()
		cache[scope] = resolved
		cacheLock.unlock()

		return resolved
	}

	/// Resolves the fully merged style for a two-sided scope context.
	///
	/// - Parameter context: The scope context (left/right) to resolve.
	/// - Returns: The resolved style for rendering.
	public func stylesForScope(_ context: ScopeContext) -> ResolvedStyle {
		// For the common single-scope case, use cached version.
		if context.left == context.right {
			return stylesForScope(context.left)
		}
		return resolveStyles(for: context)
	}

	/// Clears the cached style lookup table.  Call this when the theme's
	/// backing data changes (e.g. after a bundle reload).
	public func invalidateCache() {
		cacheLock.lock()
		cache.removeAll()
		cacheLock.unlock()
	}

	// MARK: - Internal Resolution

	private func resolveStyles(for context: ScopeContext) -> ResolvedStyle {
		// Score each rule against the scope and collect matches.
		var scored: [(rank: Double, style: DecomposedStyle)] = []
		for rule in compiledRules {
			if let rank = rule.selector.doesMatch(context) {
				scored.append((rank, rule.style))
			}
		}

		// Sort by rank (ascending) so higher-specificity rules merge last.
		scored.sort { $0.rank < $1.rank }

		// Start with base style from the engine's font settings.
		var base = DecomposedStyle(fontName: fontName, fontSizeSpec: .absolute(fontSize))

		// Merge in rank order.
		for (_, style) in scored {
			base.merge(style)
		}

		return buildResolvedStyle(from: base)
	}

	private func buildResolvedStyle(from style: DecomposedStyle) -> ResolvedStyle {
		let foreground = cgColor(from: style.foreground, fallback: theme.globalSettings.foreground)
		let background = cgColor(from: style.background, fallback: theme.globalSettings.background)
		let caret = cgColor(from: style.caret, fallback: theme.globalSettings.caret)
		let selection = cgColor(from: style.selection, fallback: theme.globalSettings.selection)

		let resolvedFontSize: CGFloat = if let spec = style.fontSizeSpec {
			spec.resolve(base: fontSize)
		} else {
			fontSize
		}

		let font = createFont(
			name: style.fontName ?? fontName,
			size: resolvedFontSize,
			bold: style.bold.boolValue,
			italic: style.italic.boolValue,
		)

		return ResolvedStyle(
			foreground: foreground,
			background: background,
			caret: caret,
			selection: selection,
			font: font,
			isUnderlined: style.underlined.boolValue,
			isStrikethrough: style.strikethrough.boolValue,
			isMisspelled: style.misspelled.boolValue,
		)
	}

	// MARK: - CTFont Creation

	/// Creates a CTFont, applying bold and/or italic symbolic traits.
	///
	/// Mirrors the C++ logic in `styles_for_scope`:
	/// 1. Create base font from name (or system monospace).
	/// 2. Apply bold/italic traits via `CTFontCreateCopyWithSymbolicTraits`.
	private func createFont(
		name: String?,
		size: CGFloat,
		bold: Bool,
		italic: Bool,
	) -> CTFont {
		let baseFont: CTFont = if let name {
			CTFontCreateWithName(name as CFString, size, nil)
		} else {
			CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)!
		}

		var traits: CTFontSymbolicTraits = []
		if bold { traits.insert(.boldTrait) }
		if italic { traits.insert(.italicTrait) }

		guard !traits.isEmpty else { return baseFont }

		if let styled = CTFontCreateCopyWithSymbolicTraits(
			baseFont,
			size,
			nil,
			traits,
			[.boldTrait, .italicTrait],
		) {
			return styled
		}
		return baseFont
	}

	// MARK: - Color Helpers

	private func cgColor(from color: ThemeColor?, fallback: ThemeColor) -> CGColor {
		let c = color ?? fallback
		var components: [CGFloat] = [c.red, c.green, c.blue, c.alpha]
		return CGColor(colorSpace: colorSpace, components: &components)
			?? c.cgColor
	}

	// MARK: - Rule Compilation

	/// Compiles theme rules into pairs of (ScopeSelector, DecomposedStyle).
	///
	/// The first (global/unscoped) rule is included with an empty selector
	/// so it always matches with rank 0.  If a rule specifies an invisibles
	/// color, an additional synthetic rule is emitted for `deco.invisible`
	/// (matching the C++ behavior in `setup_styles`).
	private static func compileRules(from theme: Theme) -> [CompiledRule] {
		var rules: [CompiledRule] = []

		// Emit generic global style (always matches at rank 0).
		let globalStyle = DecomposedStyle(
			foreground: theme.globalSettings.foreground,
			background: theme.globalSettings.background,
			caret: theme.globalSettings.caret,
			selection: theme.globalSettings.selection,
			invisibles: theme.globalSettings.invisibles,
		)
		rules.append(CompiledRule(
			selector: ScopeSelector(),
			style: globalStyle,
		))

		// Compile each scope-specific rule.
		for rule in theme.rules {
			let selector = ScopeSelector(rule.scopeSelector)
			let style = DecomposedStyle(
				fontName: rule.fontName,
				fontSizeSpec: FontSizeSpec.parse(rule.fontSize.map { String(format: "%g", $0) }),
				foreground: rule.foreground,
				background: rule.background,
				caret: rule.caret,
				selection: rule.selection,
				invisibles: rule.invisibles,
				bold: TriBool(rule.isBold),
				italic: TriBool(rule.isItalic),
				underlined: TriBool(rule.isUnderlined),
				strikethrough: TriBool(rule.isStrikethrough),
			)
			rules.append(CompiledRule(selector: selector, style: style))

			// Synthetic rule for deco.invisible (mirrors C++ setup_styles).
			if let invisibles = rule.invisibles {
				var invisibleStyle = DecomposedStyle()
				invisibleStyle.foreground = invisibles
				rules.append(CompiledRule(
					selector: ScopeSelector("deco.invisible"),
					style: invisibleStyle,
				))
			}
		}

		return rules
	}
}
