import Foundation
import TMBundle
import TMBundleRuntime
import TMCore
import TMEditorUI
import TMGrammar

/// Provides grammar-based fold info for the fold manager by compiling
/// `foldingStartMarker` / `foldingStopMarker` from grammar definitions
/// (and optionally bundle preference settings) into regular expressions.
///
/// Mirrors the C++ `setup_patterns()` in `Frameworks/layout/src/folds.cc`.
@MainActor
public final class GrammarFoldProvider {
	/// Compiled fold start marker regex.
	private var startPattern: NSRegularExpression?

	/// Compiled fold stop marker regex.
	private var stopPattern: NSRegularExpression?

	/// The text buffer for content access.
	private let buffer: TextBuffer

	/// Tab size used for indentation measurement.
	public var tabSize: Int = 4

	public init(buffer: TextBuffer) {
		self.buffer = buffer
	}

	// MARK: - Configuration

	/// Configures fold markers from a grammar definition's
	/// `foldingStartMarker` and `foldingStopMarker`.
	public func configure(
		grammarDefinition: GrammarDefinition?,
		bundleIndex: BundleIndex? = nil,
		scope: String? = nil,
	) {
		startPattern = nil
		stopPattern = nil

		// Priority 1: Bundle preferences with foldingStartMarker/foldingStopMarker
		// (scope-specific overrides, matching C++ behavior)
		if let bundleIndex, let scope {
			let prefItems = bundleIndex.query(BundleQuery(kinds: .settings))
			let context = ScopeContext(Scope(scope))
			var bestRank: Double = -1
			var bestStart: String?
			var bestStop: String?

			for item in prefItems {
				guard !item.scopeSelector.isEmpty else { continue }
				let selector = ScopeSelector(item.scopeSelector)
				guard let rank = selector.doesMatch(context), rank > bestRank else { continue }

				guard let plist = item.plist,
				      let settings = plist["settings"] as? [String: Any]
				else { continue }

				let start = settings["foldingStartMarker"] as? String
				let stop = settings["foldingStopMarker"] as? String
				if start != nil || stop != nil {
					bestRank = rank
					bestStart = start
					bestStop = stop
				}
			}

			if let bestStart {
				startPattern = try? NSRegularExpression(pattern: bestStart)
			}
			if let bestStop {
				stopPattern = try? NSRegularExpression(pattern: bestStop)
			}
		}

		// Priority 2: Grammar definition fallback
		if startPattern == nil, stopPattern == nil, let grammarDefinition {
			if let start = grammarDefinition.foldingStartMarker {
				startPattern = try? NSRegularExpression(pattern: start)
			}
			if let stop = grammarDefinition.foldingStopMarker {
				stopPattern = try? NSRegularExpression(pattern: stop)
			}
		}
	}

	/// Whether this provider has any fold markers configured.
	public var hasPatterns: Bool {
		startPattern != nil || stopPattern != nil
	}

	// MARK: - Fold Info Provider

	/// Returns fold info for a given line, suitable for use as
	/// `TextBufferFoldDataSource.foldInfoProvider`.
	public func foldInfo(forLine n: Int) -> FoldManager.LineInfo {
		guard n >= 0, n < buffer.lines else {
			return FoldManager.LineInfo()
		}

		let start = buffer.lineStart(n)
		let end = buffer.lineEnd(n)
		let lineText = buffer.substring(from: start, to: end)

		var info = FoldManager.LineInfo()

		// Compute indentation
		var indent = 0
		for ch in lineText {
			if ch == "\t" {
				indent += tabSize
			} else if ch == " " {
				indent += 1
			} else {
				break
			}
		}
		info.indent = indent

		// Check if line is blank
		let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty {
			info.isEmpty = true
			return info
		}

		// Match fold markers
		let range = NSRange(lineText.startIndex..., in: lineText)
		if let startPattern,
		   startPattern.firstMatch(in: lineText, range: range) != nil
		{
			info.isStartMarker = true
		}
		if let stopPattern,
		   stopPattern.firstMatch(in: lineText, range: range) != nil
		{
			info.isStopMarker = true
		}

		// If both regex markers match, suppress indent-based markers
		// (consistent with C++ behavior)
		if !info.isStartMarker, !info.isStopMarker {
			// Fall back to indent-based fold detection
			if n + 1 < buffer.lines {
				let nextStart = buffer.lineStart(n + 1)
				let nextEnd = buffer.lineEnd(n + 1)
				let nextLine = buffer.substring(from: nextStart, to: nextEnd)
				let nextTrimmed = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
				if !nextTrimmed.isEmpty {
					var nextIndent = 0
					for ch in nextLine {
						if ch == "\t" {
							nextIndent += tabSize
						} else if ch == " " {
							nextIndent += 1
						} else {
							break
						}
					}
					if nextIndent > indent {
						info.isIndentStartMarker = true
					}
				}
			}
		}

		return info
	}
}
