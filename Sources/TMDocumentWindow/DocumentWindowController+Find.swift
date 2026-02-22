#if canImport(AppKit)
import AppKit
import TMEditor
import TMEditorUI
import TMSearchReplace

// MARK: - FindClient Conformance

extension DocumentWindowController: FindClient {
	public func performFindOperation(_ server: FindServer) {
		guard let de = documentEditor else { return }
		let pattern = server.findString
		let options = server.findOptions
		let replacement = server.replaceString

		switch server.findOperation {
		case .find:
			let result = de.findNext(pattern: pattern, options: options)
			updateHighlights(pattern: pattern, options: options)
			server.didFind(
				count: result.count,
				of: pattern,
				atLine: result.line,
				column: result.column,
				wrapped: result.wrapped,
			)

		case .findInSelection:
			let count = de.findAll(pattern: pattern, options: options, inSelection: true)
			updateHighlights(pattern: pattern, options: options)
			server.didFind(count: count, of: pattern, atLine: 0, column: 0, wrapped: false)

		case .count:
			let count = de.countMatches(pattern: pattern, options: options)
			server.didFind(count: count, of: pattern, atLine: 0, column: 0, wrapped: false)

		case .countInSelection:
			let count = de.countMatches(pattern: pattern, options: options)
			server.didFind(count: count, of: pattern, atLine: 0, column: 0, wrapped: false)

		case .replace:
			de.replaceCurrent(with: replacement)
			updateHighlights(pattern: pattern, options: options)
			server.didReplace(count: 1, of: pattern, with: replacement)

		case .replaceAndFind:
			de.replaceCurrent(with: replacement)
			let result = de.findNext(pattern: pattern, options: options)
			updateHighlights(pattern: pattern, options: options)
			server.didFind(
				count: result.count,
				of: pattern,
				atLine: result.line,
				column: result.column,
				wrapped: result.wrapped,
			)

		case .replaceAll:
			let count = de.replaceAll(
				pattern: pattern,
				replacement: replacement,
				options: options,
			)
			clearHighlights()
			server.didReplace(count: count, of: pattern, with: replacement)

		case .replaceAllInSelection:
			let count = de.replaceAll(
				pattern: pattern,
				replacement: replacement,
				options: options,
				inSelection: true,
			)
			clearHighlights()
			server.didReplace(count: count, of: pattern, with: replacement)
		}
	}

	// MARK: - Highlight Wiring

	/// Updates the editor view's highlight ranges to show all matches.
	private func updateHighlights(pattern: String, options: FindOptions) {
		guard let de = documentEditor else { return }
		let byteRanges = de.allMatchRanges(pattern: pattern, options: options)
		editorView.highlightRanges = byteRanges.map { range in
			let start = de.editor.buffer.convert(offset: range.lowerBound)
			let end = de.editor.buffer.convert(offset: range.upperBound)
			return (start: (line: start.line, index: start.column), end: (line: end.line, index: end.column))
		}
	}

	/// Clears all find highlight ranges.
	private func clearHighlights() {
		editorView.highlightRanges = []
	}
}

#endif
