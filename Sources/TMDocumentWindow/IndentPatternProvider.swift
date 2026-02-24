import Foundation
import TMBundle
import TMBundleRuntime
import TMCore
import TMEditor
import TMGrammar

/// Provides grammar-aware indentation by querying bundle preferences
/// for indent patterns and using `IndentFSM` to compute the correct
/// indent level when inserting a newline.
///
/// Mirrors the C++ `indent_t` wiring from `editor.cc` that looks up
/// `increaseIndentPattern`, `decreaseIndentPattern`, `indentNextLinePattern`,
/// and `unIndentedLinePattern` from bundle settings.
@MainActor
public final class IndentPatternProvider {
	private let buffer: TextBuffer
	private var patterns: [IndentFSM.PatternType: NSRegularExpression] = [:]
	private var tabSize: Int
	private var indentUsingSpaces: Bool

	public init(buffer: TextBuffer, tabSize: Int, indentUsingSpaces: Bool) {
		self.buffer = buffer
		self.tabSize = tabSize
		self.indentUsingSpaces = indentUsingSpaces
	}

	/// Whether any indent patterns are configured.
	public var hasPatterns: Bool {
		!patterns.isEmpty
	}

	/// Configures indent patterns from bundle preferences matching the scope.
	public func configure(bundleIndex: BundleIndex?, scope: String?) {
		patterns = [:]

		guard let bundleIndex, let scope else { return }

		let prefItems = bundleIndex.query(BundleQuery(kinds: .settings))
		let context = ScopeContext(scope)
		var bestRank: Double = -1
		var bestSettings: PreferenceDefinition.Settings?

		for item in prefItems {
			let selector = ScopeSelector(item.scopeSelector)
			guard let rank = selector.doesMatch(context) else { continue }

			guard let plist = item.plist,
			      let settingsDict = plist["settings"] as? [String: Any]
			else { continue }

			let hasIndent = settingsDict["increaseIndentPattern"] is String
				|| settingsDict["decreaseIndentPattern"] is String

			if hasIndent, rank > bestRank {
				bestRank = rank
				bestSettings = PreferenceDefinition.Settings(
					increaseIndentPattern: settingsDict["increaseIndentPattern"] as? String,
					decreaseIndentPattern: settingsDict["decreaseIndentPattern"] as? String,
					indentNextLinePattern: settingsDict["indentNextLinePattern"] as? String,
					unIndentedLinePattern: settingsDict["unIndentedLinePattern"] as? String,
				)
			}
		}

		guard let settings = bestSettings else { return }
		compilePatterns(from: settings)
	}

	/// Updates tab size and soft-tab settings.
	public func updateSettings(tabSize: Int, indentUsingSpaces: Bool) {
		self.tabSize = tabSize
		self.indentUsingSpaces = indentUsingSpaces
	}

	/// Computes the indent string for a new line inserted after `line`.
	///
	/// Walks backwards through the preceding lines to seed the `IndentFSM`,
	/// then returns the correctly computed indent.
	public func indentAfterLine(_ line: Int) -> String {
		guard !patterns.isEmpty else {
			return copyLeadingWhitespace(line: line)
		}

		var fsm = IndentFSM(indentSize: tabSize, tabSize: tabSize)

		// Seed the FSM by walking backwards from the current line.
		let maxContext = 50
		let startLine = max(0, line - maxContext)

		var anyLinesSeen = false
		for n in stride(from: line, through: startLine, by: -1) {
			let text = lineText(n)
			anyLinesSeen = true
			if fsm.isSeeded(text, patterns: patterns) {
				break
			}
		}

		if !anyLinesSeen {
			return copyLeadingWhitespace(line: line)
		}

		// Scan an empty line to get the indent level for the new line.
		let indentLevel = fsm.scanLine("", patterns: patterns)
		return IndentFSM.createIndent(
			size: indentLevel,
			tabSize: tabSize,
			softTabs: indentUsingSpaces,
		)
	}

	// MARK: - Private

	private func compilePatterns(from settings: PreferenceDefinition.Settings) {
		if let s = settings.increaseIndentPattern, let re = try? NSRegularExpression(pattern: s) {
			patterns[.increase] = re
		}
		if let s = settings.decreaseIndentPattern, let re = try? NSRegularExpression(pattern: s) {
			patterns[.decrease] = re
		}
		if let s = settings.indentNextLinePattern, let re = try? NSRegularExpression(pattern: s) {
			patterns[.increaseNext] = re
		}
		if let s = settings.unIndentedLinePattern, let re = try? NSRegularExpression(pattern: s) {
			patterns[.ignore] = re
		}
	}

	private func lineText(_ n: Int) -> String {
		guard n >= 0, n < buffer.lines else { return "" }
		return buffer.substring(from: buffer.lineStart(n), to: buffer.lineEnd(n))
	}

	private func copyLeadingWhitespace(line: Int) -> String {
		guard line >= 0, line < buffer.lines else { return "" }
		let text = lineText(line)
		var ws = ""
		for ch in text {
			if ch == "\t" || ch == " " {
				ws.append(ch)
			} else {
				break
			}
		}
		return ws
	}
}
