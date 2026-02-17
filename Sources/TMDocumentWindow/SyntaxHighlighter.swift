import AppKit
import TMEditorUI
import TMGrammar
import TMTheme

/// Bridges the grammar parser and theme engine to produce `StyleRun` arrays
/// for the editor's layout manager.
///
/// This is the Swift counterpart of the scope → style resolution pipeline
/// that lives in `ct::line_t` (C++ `Frameworks/layout/src/ct.cc`).
///
/// ## Architecture
///
/// ```
/// IncrementalParser ──(scope map per line)──▶ SyntaxHighlighter
/// ThemeEngine ──(scope → ResolvedStyle)──────▶ SyntaxHighlighter
/// SyntaxHighlighter ──([StyleRun])──────────▶ EditorLayoutManager.styleProvider
/// ```
///
/// ## Thread Safety
///
/// The highlighter is designed to be called from the main thread (UI layout)
/// but the underlying `IncrementalParser` and `ThemeEngine` are thread-safe
/// and can be driven from background queues for async parsing.
@MainActor
public final class SyntaxHighlighter {
	// MARK: - Properties

	/// The incremental parser that tracks scopes per line.
	public private(set) var parser: IncrementalParser?

	/// The theme engine that resolves scopes to visual styles.
	public private(set) var themeEngine: ThemeEngine?

	/// The grammar registry used to look up grammars by scope name.
	public private(set) var grammarRegistry: GrammarRegistry?

	/// The currently active grammar scope (e.g. "source.swift").
	public private(set) var activeScope: String?

	/// Callback invoked when lines need visual invalidation after re-parsing.
	/// The parameter is the range of hard-line indices whose styles changed.
	public var onStylesChanged: ((Range<Int>) -> Void)?

	// MARK: - Init

	/// Creates a syntax highlighter.
	///
	/// - Parameters:
	///   - grammarRegistry: The registry of available grammars.
	///   - themeEngine: The theme engine for scope → style resolution.
	public init(
		grammarRegistry: GrammarRegistry? = nil,
		themeEngine: ThemeEngine? = nil,
	) {
		self.grammarRegistry = grammarRegistry
		self.themeEngine = themeEngine
	}

	// MARK: - Configuration

	/// Sets the grammar registry.
	public func setGrammarRegistry(_ registry: GrammarRegistry) {
		grammarRegistry = registry
	}

	/// Sets the theme engine (e.g. when the user switches themes).
	public func setThemeEngine(_ engine: ThemeEngine) {
		themeEngine = engine
	}

	/// Activates a grammar by scope name (e.g. "source.swift").
	///
	/// Creates a new `IncrementalParser` for the grammar. If the grammar
	/// is not found in the registry, the parser is cleared and all text
	/// will render with the default foreground color.
	///
	/// - Parameter scope: The grammar scope name, or `nil` to disable
	///   syntax highlighting.
	public func setGrammar(scope: String?) {
		activeScope = scope

		guard let scope, let registry = grammarRegistry,
		      let rule = registry.grammar(forScope: scope)
		else {
			parser = nil
			return
		}

		parser = IncrementalParser(grammar: rule)
	}

	// MARK: - Text Management

	/// Sets the full document text, triggering a synchronous parse.
	///
	/// Call this when a document is first loaded or when the entire
	/// content is replaced (e.g. external reload).
	public func setText(_ text: String) {
		parser?.setText(text)
	}

	/// Notifies the highlighter that lines were replaced.
	///
	/// Call this after every text mutation so the parser knows which
	/// lines to re-parse.
	public func replaceLines(in range: Range<Int>, with newLines: [String]) {
		parser?.replaceLines(in: range, with: newLines)
	}

	/// Marks a range of lines as needing re-parsing.
	public func invalidateLines(_ range: Range<Int>) {
		parser?.invalidateLines(range)
	}

	// MARK: - Parsing

	/// Parses all dirty lines synchronously and notifies the callback
	/// of any style changes.
	///
	/// Typically called before layout (e.g. from `layoutLines(in:)`).
	@discardableResult
	public func parseSync() -> [Range<Int>] {
		guard let parser else { return [] }
		let changedRanges = parser.parseSync()
		for range in changedRanges {
			onStylesChanged?(range)
		}
		return changedRanges
	}

	/// Parses dirty lines asynchronously and invokes the callback
	/// on the main thread when styles change.
	public func parseAsync() {
		guard let parser else { return }
		parser.parseAsync { [weak self] changedRanges in
			Task { @MainActor [weak self] in
				guard let self else { return }
				for range in changedRanges {
					onStylesChanged?(range)
				}
			}
		}
	}

	// MARK: - Style Resolution

	/// Produces `StyleRun` arrays for a single line, suitable for the
	/// `EditorLayoutManager.styleProvider` callback.
	///
	/// This is the core method that converts scope maps to visual styles.
	/// It mirrors the C++ `ct::line_t` constructor in `ct.cc`.
	///
	/// - Parameters:
	///   - lineIndex: The hard-line index.
	///   - lineText: The text content of the line.
	/// - Returns: An array of style runs covering the entire line.
	public func styleRuns(forLine lineIndex: Int, text lineText: String) -> [StyleRun] {
		guard let parser, let engine = themeEngine else {
			return []
		}

		let scopeMap = parser.scopeMap(forLine: lineIndex)
		guard !scopeMap.isEmpty else {
			return []
		}

		return convertScopeMapToStyleRuns(
			scopeMap: scopeMap,
			lineLength: lineText.utf8.count,
			engine: engine,
		)
	}

	/// Returns a closure suitable for assigning to
	/// `EditorLayoutManager.styleProvider`.
	///
	/// The returned closure captures `self` weakly.
	public func makeStyleProvider() -> (Int, String) -> [StyleRun] {
		{ [weak self] lineIndex, lineText in
			guard let self else { return [] }
			return styleRuns(forLine: lineIndex, text: lineText)
		}
	}

	// MARK: - Internal

	/// Converts a scope map (byte offset → Scope) into `[StyleRun]`.
	///
	/// The scope map entries mark where scope changes occur. Each entry
	/// applies from its offset until the next entry (or end of line).
	/// We query the `ThemeEngine` for each scope to get colors/fonts.
	private func convertScopeMapToStyleRuns(
		scopeMap: [Int: Scope],
		lineLength: Int,
		engine: ThemeEngine,
	) -> [StyleRun] {
		guard lineLength > 0 else { return [] }

		// Sort scope transitions by byte offset.
		let sorted = scopeMap.sorted { $0.key < $1.key }

		var runs: [StyleRun] = []

		for (i, entry) in sorted.enumerated() {
			let start = entry.key
			let end: Int = if i + 1 < sorted.count {
				sorted[i + 1].key
			} else {
				lineLength
			}

			let length = end - start
			guard length > 0 else { continue }

			let resolved = engine.stylesForScope(entry.value)

			let run = StyleRun(
				start: start,
				length: length,
				foreground: NSColor(cgColor: resolved.foreground) ?? .textColor,
				background: backgroundOrNil(resolved.background, engine: engine),
				isBold: CTFontGetSymbolicTraits(resolved.font).contains(.boldTrait),
				isItalic: CTFontGetSymbolicTraits(resolved.font).contains(.italicTrait),
				isUnderline: resolved.isUnderlined,
				isStrikethrough: resolved.isStrikethrough,
			)
			runs.append(run)
		}

		return runs
	}

	/// Returns `nil` if the background color matches the theme's global
	/// background (i.e. transparent/no-op), otherwise returns the NSColor.
	///
	/// This avoids redundant background fills for the default color.
	private func backgroundOrNil(_ color: CGColor, engine: ThemeEngine) -> NSColor? {
		let globalBg = engine.theme.globalSettings.background
		let globalCG = globalBg.cgColor

		// Compare RGBA components (fast path for identical objects).
		guard let bgComps = color.components,
		      let globalComps = globalCG.components,
		      bgComps.count == globalComps.count
		else {
			return NSColor(cgColor: color)
		}

		let isDefault = zip(bgComps, globalComps).allSatisfy { abs($0 - $1) < 0.001 }
		if isDefault { return nil }
		return NSColor(cgColor: color)
	}
}
