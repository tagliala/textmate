import Foundation
import TMBundle
import TMBundleRuntime
import TMCore
import TMFilterList
import TMGrammar

/// Adds symbol extraction to the syntax highlighter, mirroring the C++
/// `symbols_t::did_parse` in `Frameworks/buffer/src/symbols.cc`.
///
/// After grammar parsing, scopes are inspected for `showInSymbolList`
/// bundle preference settings. Matching text runs are extracted, transformed
/// via `symbolTransformation`, and stored in a `SymbolExtractor`.
public extension SyntaxHighlighter {
	/// Extracts symbols from the parser's scope map using bundle settings.
	///
	/// Walks every line, collects scopes that match a bundle preference
	/// with `showInSymbolList: true`, extracts the text, applies any
	/// `symbolTransformation`, and returns symbol descriptors suitable
	/// for the symbol chooser.
	///
	/// - Parameters:
	///   - bundleIndex: The global bundle index to query for preference items.
	///   - lines: The document lines (matching what the parser was fed).
	/// - Returns: An array of ``SymbolDescriptor`` sorted by position.
	func extractSymbols(
		bundleIndex: BundleIndex,
		lines: [String],
	) -> [SymbolDescriptor] {
		guard let parser else { return [] }

		// Step 1: Collect all preference items with showInSymbolList
		let prefItems = bundleIndex.query(
			BundleQuery(kinds: .settings),
		)

		// Build a cache of scope selector → (showInSymbolList, transformation)
		// keyed by scope string to avoid repeated plist parsing.
		var symbolScopeCache: [Scope: SymbolTransformation?] = [:]

		func shouldShowInSymbolList(_ scope: Scope) -> (show: Bool, transform: SymbolTransformation?)? {
			if let cached = symbolScopeCache[scope] {
				return (true, cached)
			}

			let context = ScopeContext(scope)
			var bestRank: Double = -1
			var bestShow: Bool?
			var bestTransform: String?

			for item in prefItems {
				guard !item.scopeSelector.isEmpty else { continue }
				let selector = ScopeSelector(item.scopeSelector)
				guard let rank = selector.doesMatch(context), rank > bestRank else { continue }

				// Parse the plist to check showInSymbolList
				guard let plist = item.plist,
				      let settings = plist["settings"] as? [String: Any]
				else { continue }

				if let show = settings["showInSymbolList"] {
					if plistIsTruthy(show) {
						bestRank = rank
						bestShow = true
						bestTransform = settings["symbolTransformation"] as? String
					} else {
						bestRank = rank
						bestShow = false
						bestTransform = nil
					}
				}
			}

			guard let show = bestShow else { return nil }
			if show {
				let transform = SymbolTransformation(bestTransform)
				symbolScopeCache[scope] = transform
				return (true, transform)
			}
			return (false, nil)
		}

		// Step 2: Walk scope maps line by line and extract symbol text
		var symbols: [SymbolDescriptor] = []
		var byteOffset = 0

		for lineIndex in 0 ..< lines.count {
			let lineText = lines[lineIndex]
			let lineBytes = lineText.utf8.count
			let scopeMap = parser.scopeMap(forLine: lineIndex)

			if !scopeMap.isEmpty {
				// Sort transitions by offset within the line
				let sorted = scopeMap.sorted { $0.key < $1.key }

				var inSymbol = false
				var symbolStart = 0
				var currentTransform: SymbolTransformation?

				for entry in sorted {
					let localOffset = entry.key
					let scope = entry.value

					if let result = shouldShowInSymbolList(scope), result.show {
						if !inSymbol {
							symbolStart = localOffset
							currentTransform = result.transform
							inSymbol = true
						}
					} else if inSymbol {
						// End of symbol run
						let text = extractText(from: lineText, start: symbolStart, end: localOffset)
						if !text.isEmpty {
							let name = currentTransform?.apply(to: text) ?? text
							let cleanName = name.replacingOccurrences(of: "\n", with: " ")
							symbols.append(SymbolDescriptor(
								name: cleanName,
								offset: byteOffset + symbolStart,
								selectionString: "\(lineIndex + 1)",
							))
						}
						inSymbol = false
					}
				}

				// If still in a symbol at end of line
				if inSymbol {
					let text = extractText(from: lineText, start: symbolStart, end: lineBytes)
					if !text.isEmpty {
						let name = currentTransform?.apply(to: text) ?? text
						let cleanName = name.replacingOccurrences(of: "\n", with: " ")
						symbols.append(SymbolDescriptor(
							name: cleanName,
							offset: byteOffset + symbolStart,
							selectionString: "\(lineIndex + 1)",
						))
					}
				}
			}

			byteOffset += lineBytes
		}

		return symbols
	}
}

/// Extracts a substring from a line given UTF-8 byte offsets.
private func extractText(from line: String, start: Int, end: Int) -> String {
	let utf8 = line.utf8
	let startIdx = utf8.index(utf8.startIndex, offsetBy: start, limitedBy: utf8.endIndex) ?? utf8.endIndex
	let endIdx = utf8.index(utf8.startIndex, offsetBy: end, limitedBy: utf8.endIndex) ?? utf8.endIndex
	guard startIdx < endIdx else { return "" }
	return String(utf8[startIdx ..< endIdx])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

/// Checks if a plist value is truthy (handles Bool, Int, String "1"/"true"/"yes").
private func plistIsTruthy(_ value: Any) -> Bool {
	if let b = value as? Bool { return b }
	if let n = value as? Int { return n != 0 }
	if let s = value as? String {
		let lower = s.lowercased()
		return lower == "1" || lower == "true" || lower == "yes"
	}
	return false
}
