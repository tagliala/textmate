#if canImport(AppKit)
import TMCore
import TMEditorUI

/// Adapts a `TextBuffer` to the `FoldDataSource` protocol used by `FoldManager`.
///
/// This bridges the TMCore buffer into the fold manager's line-level query API.
/// Fold markers are provided via an external callback that can be connected to
/// grammar/bundle settings for the current scope.
@MainActor
public final class TextBufferFoldDataSource: FoldDataSource {
	/// The text buffer providing line content.
	private let buffer: TextBuffer

	/// Callback returning fold info for a given line index.
	/// Defaults to indent-based folding when no regex markers are available.
	public var foldInfoProvider: (@MainActor (Int) -> FoldManager.LineInfo)?

	public init(buffer: TextBuffer) {
		self.buffer = buffer
	}

	// MARK: - FoldDataSource

	public nonisolated var lineCount: Int {
		MainActor.assumeIsolated { buffer.lines }
	}

	public nonisolated var bufferSize: Int {
		MainActor.assumeIsolated { buffer.size }
	}

	public nonisolated func lineStart(_ n: Int) -> Int {
		MainActor.assumeIsolated { buffer.lineStart(n) }
	}

	public nonisolated func lineEnd(_ n: Int) -> Int {
		MainActor.assumeIsolated { buffer.lineEnd(n) }
	}

	public nonisolated func character(at offset: Int) -> String {
		MainActor.assumeIsolated {
			guard offset >= 0, offset < buffer.size else { return "" }
			let byte = buffer[offset]
			return String(UnicodeScalar(byte))
		}
	}

	public nonisolated func foldInfo(forLine n: Int) -> FoldManager.LineInfo {
		MainActor.assumeIsolated {
			if let provider = foldInfoProvider {
				return provider(n)
			}
			return defaultFoldInfo(forLine: n)
		}
	}

	// MARK: - Default Indent-Based Fold Info

	/// Computes basic fold info from indentation when no regex markers are available.
	private func defaultFoldInfo(forLine n: Int) -> FoldManager.LineInfo {
		guard n >= 0, n < buffer.lines else {
			return FoldManager.LineInfo()
		}

		let start = buffer.lineStart(n)
		let end = buffer.lineEnd(n)

		var info = FoldManager.LineInfo()

		// Compute indentation level
		var indent = 0
		var offset = start
		while offset < end {
			let byte = buffer[offset]
			if byte == 0x09 { // tab
				indent += 1
			} else if byte == 0x20 { // space
				indent += 1
			} else {
				break
			}
			offset += 1
		}
		info.indent = indent

		// Check if line is blank
		if offset >= end {
			info.isEmpty = true
			return info
		}

		// Indent-based folding: a line that is followed by a more-indented
		// non-blank line is an indent-start marker.
		if n + 1 < buffer.lines {
			let nextInfo = peekIndent(line: n + 1)
			if !nextInfo.isEmpty, nextInfo.indent > indent {
				info.isIndentStartMarker = true
			}
		}

		return info
	}

	/// Peek at indentation of a line without full fold info recursion.
	private func peekIndent(line n: Int) -> (indent: Int, isEmpty: Bool) {
		guard n >= 0, n < buffer.lines else { return (0, true) }
		let start = buffer.lineStart(n)
		let end = buffer.lineEnd(n)

		var indent = 0
		var offset = start
		while offset < end {
			let byte = buffer[offset]
			if byte == 0x09 || byte == 0x20 {
				indent += 1
			} else {
				break
			}
			offset += 1
		}
		return (indent, offset >= end)
	}
}
#endif
