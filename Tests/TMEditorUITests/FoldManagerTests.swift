import Testing
@testable import TMEditorUI

/// Mock data source for FoldManager tests.
struct MockFoldDataSource: FoldDataSource {
	let lines: [String]

	var lineCount: Int {
		lines.count
	}

	var bufferSize: Int {
		lines.reduce(0) { $0 + $1.utf8.count }
	}

	func lineStart(_ n: Int) -> Int {
		lines.prefix(n).reduce(0) { $0 + $1.utf8.count }
	}

	func lineEnd(_ n: Int) -> Int {
		guard n < lineCount else { return bufferSize }
		// End is before the newline
		let start = lineStart(n)
		let line = lines[n]
		// If line ends with \n, exclude it
		if line.hasSuffix("\n") {
			return start + line.utf8.count - 1
		}
		return start + line.utf8.count
	}

	func character(at offset: Int) -> String {
		var remaining = offset
		for line in lines {
			if remaining < line.utf8.count {
				let idx = line.utf8.index(line.utf8.startIndex, offsetBy: remaining)
				return String(line[idx])
			}
			remaining -= line.utf8.count
		}
		return ""
	}

	func foldInfo(forLine n: Int) -> FoldManager.LineInfo {
		guard n < lines.count else { return FoldManager.LineInfo() }
		let line = lines[n]
		var info = FoldManager.LineInfo()

		// Count leading tabs as indent
		var indent = 0
		for ch in line {
			if ch == "\t" { indent += 1 } else { break }
		}
		info.indent = indent

		// Detect { as start marker and } as stop marker
		if line.contains("{") { info.isStartMarker = true }
		if line.contains("}") { info.isStopMarker = true }

		// Empty lines
		let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
		info.isEmpty = trimmed.isEmpty

		return info
	}
}

@Suite("FoldManager")
struct FoldManagerTests {
	// MARK: - Basic Properties

	@Test("Empty fold manager has no folded ranges")
	func emptyFoldsEmpty() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n"])
		let fm = FoldManager(dataSource: ds)
		#expect(fm.foldedRanges.isEmpty)
		#expect(fm.foldBoundaries.isEmpty)
	}

	// MARK: - Fold/Unfold

	@Test("Fold and unfold a range")
	func foldAndUnfold() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 3, to: 8)
		#expect(fm.foldedRanges.count == 1)
		#expect(fm.foldedRanges[0].from == 3)
		#expect(fm.foldedRanges[0].to == 8)

		let unfolded = fm.unfold(from: 3, to: 8)
		#expect(unfolded == true)
		#expect(fm.foldedRanges.isEmpty)
	}

	@Test("Unfold non-existent range returns false")
	func unfoldNonexistent() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n"])
		let fm = FoldManager(dataSource: ds)

		let result = fm.unfold(from: 0, to: 5)
		#expect(result == false)
	}

	@Test("Multiple folds are sorted")
	func multipleFoldsSorted() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n", "test\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 10, to: 15)
		fm.fold(from: 2, to: 5)
		#expect(fm.foldedRanges.count == 2)
		#expect(fm.foldedRanges[0].from == 2)
		#expect(fm.foldedRanges[1].from == 10)
	}

	// MARK: - Serialization

	@Test("Serialized format matches expected plist format")
	func serialization() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n", "test\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 2, to: 5)
		fm.fold(from: 10, to: 14)

		let str = fm.foldedAsString()
		#expect(str == "((2,5),(10,14))")
	}

	@Test("Empty folds serialize to nil")
	func emptySerializesToNil() {
		let ds = MockFoldDataSource(lines: ["hello\n"])
		let fm = FoldManager(dataSource: ds)
		#expect(fm.foldedAsString() == nil)
	}

	@Test("Deserialization round-trip")
	func deserializationRoundTrip() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n", "test\n"])
		let fm = FoldManager(dataSource: ds)

		fm.setFolded(fromString: "((2,5),(10,14))")
		#expect(fm.foldedRanges.count == 2)
		#expect(fm.foldedRanges[0].from == 2)
		#expect(fm.foldedRanges[0].to == 5)
		#expect(fm.foldedRanges[1].from == 10)
		#expect(fm.foldedRanges[1].to == 14)
	}

	// MARK: - willReplace

	@Test("willReplace adjusts folds after insertion")
	func willReplaceInsertion() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 6, to: 10)
		// Insert 3 bytes at position 1 (before the fold)
		fm.willReplace(from: 1, to: 1, newLength: 3)
		#expect(fm.foldedRanges.count == 1)
		#expect(fm.foldedRanges[0].from == 9) // 6 + 3 (delta = 3 - 0 = 3)
		#expect(fm.foldedRanges[0].to == 13)
	}

	@Test("willReplace removes overlapping folds")
	func willReplaceOverlap() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 3, to: 8)
		// Delete from position 2 to 5 (overlaps fold start)
		fm.willReplace(from: 2, to: 5, newLength: 0)
		#expect(fm.foldedRanges.isEmpty)
	}

	@Test("willReplace preserves folds before change")
	func willReplacePreserves() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 1, to: 3)
		// Replace at position 10 (after the fold)
		fm.willReplace(from: 10, to: 11, newLength: 2)
		#expect(fm.foldedRanges.count == 1)
		#expect(fm.foldedRanges[0].from == 1)
		#expect(fm.foldedRanges[0].to == 3)
	}

	// MARK: - Remove Enclosing

	@Test("removeEnclosing removes fold containing range")
	func removeEnclosing() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 2, to: 10)
		let removed = fm.removeEnclosing(from: 5, to: 7)
		#expect(removed.count == 1)
		#expect(removed[0].from == 2)
		#expect(removed[0].to == 10)
		#expect(fm.foldedRanges.isEmpty)
	}

	// MARK: - Legacy Boundary Map

	@Test("Legacy boundaries are computed from folds")
	func legacyBoundaries() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n", "test\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 2, to: 5)
		let boundaries = fm.foldBoundaries
		#expect(boundaries.count == 2)
		#expect(boundaries[0].offset == 2)
		#expect(boundaries[0].isStart == true)
		#expect(boundaries[1].offset == 5)
		#expect(boundaries[1].isStart == false)
	}

	// MARK: - Query API

	@Test("hasFolded detects folded lines")
	func hasFoldedDetects() {
		let ds = MockFoldDataSource(lines: ["hello\n", "world\n"])
		let fm = FoldManager(dataSource: ds)

		fm.fold(from: 0, to: 5)
		#expect(fm.hasFolded(line: 0) == true)
		#expect(fm.hasFolded(line: 1) == false)
	}

	// MARK: - Foldable Ranges

	@Test("Foldable ranges computed from markers")
	func foldableRangesFromMarkers() {
		let ds = MockFoldDataSource(lines: [
			"func foo() {\n",
			"\tbar()\n",
			"}\n",
		])
		let fm = FoldManager(dataSource: ds)

		let ranges = fm.foldableRanges()
		// Should find a foldable range from the { to the }
		#expect(!ranges.isEmpty)
	}
}
