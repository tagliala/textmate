import Testing
@testable import TMCore

// MARK: - IndexedMap Tests

@Suite("IndexedMap — Position-Indexed Map")
struct IndexedMapTests {
	// MARK: - Empty Map

	@Test func emptyMap() {
		let map = IndexedMap<String>()
		#expect(map.isEmpty)
		#expect(map.count == 0)
		#expect(map.find(at: 0) == nil)
		#expect(map.nth(0) == nil)
	}

	// MARK: - Set & Find

	@Test func setAndFind() {
		var map = IndexedMap<String>()
		map.set(at: 10, value: "alpha")
		map.set(at: 20, value: "beta")
		map.set(at: 5, value: "gamma")

		#expect(map.count == 3)
		#expect(map.find(at: 10)?.value == "alpha")
		#expect(map.find(at: 20)?.value == "beta")
		#expect(map.find(at: 5)?.value == "gamma")
		#expect(map.find(at: 15) == nil)
	}

	@Test func setOverwritesExisting() {
		var map = IndexedMap<String>()
		map.set(at: 10, value: "first")
		map.set(at: 10, value: "second")

		#expect(map.count == 1)
		#expect(map.find(at: 10)?.value == "second")
	}

	// MARK: - Remove

	@Test func removeExisting() {
		var map = IndexedMap<Int>()
		map.set(at: 5, value: 1)
		map.set(at: 10, value: 2)
		map.set(at: 15, value: 3)

		let removed = map.remove(at: 10)
		#expect(removed)
		#expect(map.count == 2)
		#expect(map.find(at: 10) == nil)
		#expect(map.find(at: 5)?.value == 1)
		#expect(map.find(at: 15)?.value == 3)
	}

	@Test func removeNonExisting() {
		var map = IndexedMap<Int>()
		map.set(at: 5, value: 1)
		let removed = map.remove(at: 10)
		#expect(!removed)
		#expect(map.count == 1)
	}

	@Test func clear() {
		var map = IndexedMap<Int>()
		map.set(at: 1, value: 10)
		map.set(at: 2, value: 20)
		map.clear()
		#expect(map.isEmpty)
		#expect(map.count == 0)
	}

	// MARK: - Lower Bound & Upper Bound

	@Test func lowerBound() {
		var map = IndexedMap<Int>()
		map.set(at: 5, value: 1)
		map.set(at: 10, value: 2)
		map.set(at: 20, value: 3)

		#expect(map.lowerBound(at: 5) == 0) // first entry at position >= 5
		#expect(map.lowerBound(at: 7) == 1) // first entry at position >= 7 is at index 1 (pos 10)
		#expect(map.lowerBound(at: 10) == 1) // exact match
		#expect(map.lowerBound(at: 15) == 2) // first entry >= 15 is index 2 (pos 20)
		#expect(map.lowerBound(at: 21) == 3) // past end
		#expect(map.lowerBound(at: 0) == 0) // before all
	}

	@Test func upperBound() {
		var map = IndexedMap<Int>()
		map.set(at: 5, value: 1)
		map.set(at: 10, value: 2)
		map.set(at: 20, value: 3)

		#expect(map.upperBound(at: 5) == 1) // first entry at position > 5
		#expect(map.upperBound(at: 7) == 1) // first entry > 7 is at index 1 (pos 10)
		#expect(map.upperBound(at: 10) == 2) // first entry > 10 is at index 2 (pos 20)
		#expect(map.upperBound(at: 20) == 3) // past end
		#expect(map.upperBound(at: 0) == 0) // before all → first entry
	}

	// MARK: - Nth

	@Test func nth() {
		var map = IndexedMap<String>()
		map.set(at: 100, value: "c")
		map.set(at: 50, value: "b")
		map.set(at: 10, value: "a")

		#expect(map.nth(0)?.value == "a")
		#expect(map.nth(0)?.position == 10)
		#expect(map.nth(1)?.value == "b")
		#expect(map.nth(2)?.value == "c")
		#expect(map.nth(3) == nil)
		#expect(map.nth(-1) == nil)
	}

	// MARK: - Replace (Position Adjustment)

	@Test func replaceInsertionShiftsRight() {
		var map = IndexedMap<String>()
		map.set(at: 0, value: "a")
		map.set(at: 5, value: "b")
		map.set(at: 10, value: "c")

		// Insert 3 bytes at position 5 (replace [5,5) with 3 bytes)
		map.replace(from: 5, to: 5, newLength: 3)

		#expect(map.find(at: 0)?.value == "a")
		#expect(map.find(at: 8)?.value == "b") // 5 + 3 = 8
		#expect(map.find(at: 13)?.value == "c") // 10 + 3 = 13
	}

	@Test func replaceDeletionShiftsLeft() {
		var map = IndexedMap<String>()
		map.set(at: 0, value: "a")
		map.set(at: 5, value: "b")
		map.set(at: 10, value: "c")

		// Delete 3 bytes from position 2 to 5 (replace [2,5) with 0)
		map.replace(from: 2, to: 5, newLength: 0)

		#expect(map.find(at: 0)?.value == "a")
		#expect(map.find(at: 5) == nil) // "b" was at position 5, removed (in [2,5))
		#expect(map.find(at: 7)?.value == "c") // 10 - 3 = 7
	}

	@Test func replaceRemovesEntriesInRange() {
		var map = IndexedMap<String>()
		map.set(at: 0, value: "a")
		map.set(at: 3, value: "b")
		map.set(at: 6, value: "c")
		map.set(at: 10, value: "d")

		// Replace [2, 8) with 2 bytes → delta = 2 - (8-2) = -4
		map.replace(from: 2, to: 8, newLength: 2)

		#expect(map.count == 2) // "a" at 0, "d" shifted
		#expect(map.find(at: 0)?.value == "a")
		// "b" at 3 and "c" at 6 removed (in [2, 8))
		#expect(map.find(at: 3) == nil)
		// "d" was at 10, shifted: 10 + (2 - 6) = 6
		#expect(map.find(at: 6)?.value == "d")
	}

	@Test func replaceBindRightKeepsEntryAtTo() {
		var map = IndexedMap<String>()
		map.set(at: 5, value: "at-from")
		map.set(at: 10, value: "at-to")
		map.set(at: 15, value: "after")

		// Replace [5, 10) with 3 bytes, bindRight=true (default)
		map.replace(from: 5, to: 10, newLength: 3, bindRight: true)

		// "at-from" (pos 5) should be removed (in [5, 10))
		#expect(map.find(at: 5) == nil)
		// "at-to" (pos 10) should be kept and shifted: 10 + (3 - 5) = 8
		#expect(map.find(at: 8)?.value == "at-to")
		// "after" (pos 15) should be shifted: 15 + (3 - 5) = 13
		#expect(map.find(at: 13)?.value == "after")
	}

	@Test func replaceBindLeftKeepsEntryAtFrom() {
		var map = IndexedMap<String>()
		map.set(at: 5, value: "at-from")
		map.set(at: 10, value: "at-to")
		map.set(at: 15, value: "after")

		// Replace [5, 10) with 3 bytes, bindRight=false
		map.replace(from: 5, to: 10, newLength: 3, bindRight: false)

		// "at-from" (pos 5) should be kept (not in (5, 10])
		#expect(map.find(at: 5)?.value == "at-from")
		// "at-to" (pos 10) should be removed (in (5, 10])
		#expect(map.find(at: 8) == nil)
		// "after" (pos 15) should be shifted: 15 + (3 - 5) = 13
		#expect(map.find(at: 13)?.value == "after")
	}

	@Test func replaceEmptyRange() {
		var map = IndexedMap<Int>()
		map.set(at: 5, value: 1)
		map.set(at: 10, value: 2)

		// No-op replacement: same range, same length
		map.replace(from: 5, to: 5, newLength: 0)

		#expect(map.count == 2)
		#expect(map.find(at: 5)?.value == 1)
		#expect(map.find(at: 10)?.value == 2)
	}

	// MARK: - Iteration

	@Test func iterationOrder() {
		var map = IndexedMap<String>()
		map.set(at: 30, value: "c")
		map.set(at: 10, value: "a")
		map.set(at: 20, value: "b")

		let entries = Array(map)
		#expect(entries.count == 3)
		#expect(entries[0].position == 10)
		#expect(entries[0].value == "a")
		#expect(entries[1].position == 20)
		#expect(entries[1].value == "b")
		#expect(entries[2].position == 30)
		#expect(entries[2].value == "c")
	}

	// MARK: - Subscript

	@Test func subscriptAccess() {
		var map = IndexedMap<Int>()
		map.set(at: 100, value: 3)
		map.set(at: 50, value: 2)
		map.set(at: 10, value: 1)

		#expect(map[0].position == 10)
		#expect(map[0].value == 1)
		#expect(map[1].position == 50)
		#expect(map[2].position == 100)
	}

	// MARK: - Remove Subrange

	@Test func removeSubrange() {
		var map = IndexedMap<Int>()
		map.set(at: 1, value: 10)
		map.set(at: 2, value: 20)
		map.set(at: 3, value: 30)
		map.set(at: 4, value: 40)

		map.removeSubrange(1 ..< 3) // Remove entries at indices 1 and 2
		#expect(map.count == 2)
		#expect(map[0].position == 1)
		#expect(map[1].position == 4)
	}
}

// MARK: - BufferMarks Tests

@Suite("BufferMarks — Buffer-Level Marks")
struct BufferMarksTests {
	@Test func emptyMarks() {
		let marks = BufferMarks()
		#expect(marks.isEmpty)
		#expect(marks.count == 0)
		#expect(marks.get(at: 0, type: "bookmark") == nil)
	}

	@Test func setAndGet() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "bookmark", label: "Chapter 1")
		marks.set(at: 20, type: "bookmark", label: "Chapter 2")
		marks.set(at: 15, type: "search", label: "match")

		#expect(marks.count == 3)
		#expect(marks.get(at: 10, type: "bookmark") == "Chapter 1")
		#expect(marks.get(at: 20, type: "bookmark") == "Chapter 2")
		#expect(marks.get(at: 15, type: "search") == "match")
		#expect(marks.get(at: 10, type: "search") == nil)
	}

	@Test func removeSpecificMark() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "bookmark")
		marks.set(at: 10, type: "search")

		let removed = marks.remove(at: 10, type: "bookmark")
		#expect(removed)
		#expect(marks.get(at: 10, type: "bookmark") == nil)
		#expect(marks.get(at: 10, type: "search") == "")
	}

	@Test func removeAllByType() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "bookmark")
		marks.set(at: 20, type: "bookmark")
		marks.set(at: 30, type: "search")

		marks.removeAll(type: "bookmark")
		#expect(marks.count == 1)
		#expect(marks.get(at: 30, type: "search") == "")
	}

	@Test func removeAllByPrefix() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "search/highlight")
		marks.set(at: 20, type: "search/current")
		marks.set(at: 30, type: "bookmark")

		marks.removeAll(type: "search/")
		#expect(marks.count == 1)
		#expect(marks.get(at: 30, type: "bookmark") == "")
	}

	@Test func getRangeByType() {
		let marks = BufferMarks()
		marks.set(at: 5, type: "bookmark", label: "a")
		marks.set(at: 10, type: "bookmark", label: "b")
		marks.set(at: 15, type: "bookmark", label: "c")
		marks.set(at: 20, type: "bookmark", label: "d")

		let range = marks.getRange(from: 8, to: 18, type: "bookmark")
		#expect(range.count == 2)
		#expect(range[0].label == "b")
		#expect(range[1].label == "c")
	}

	@Test func getRangeAllTypes() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "bookmark", label: "bm")
		marks.set(at: 12, type: "search", label: "sr")

		let range = marks.getRange(from: 5, to: 20)
		#expect(range.count == 2)
		// Should be sorted by position
		#expect(range[0].position == 10)
		#expect(range[1].position == 12)
	}

	@Test func nextMark() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "bookmark", label: "a")
		marks.set(at: 30, type: "bookmark", label: "b")

		let next = marks.next(after: 15, types: ["bookmark"], bufferSize: 100)
		#expect(next?.position == 30)
		#expect(next?.label == "b")
	}

	@Test func nextMarkWraps() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "bookmark", label: "first")

		// Search from position 20 — should wrap to 10
		let next = marks.next(after: 20, types: ["bookmark"], bufferSize: 100)
		#expect(next?.position == 10)
	}

	@Test func prevMark() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "bookmark", label: "a")
		marks.set(at: 30, type: "bookmark", label: "b")

		let prev = marks.prev(before: 25, types: ["bookmark"], bufferSize: 100)
		#expect(prev?.position == 10)
		#expect(prev?.label == "a")
	}

	@Test func prevMarkWraps() {
		let marks = BufferMarks()
		marks.set(at: 50, type: "bookmark", label: "last")

		// Search from position 5 — should wrap to 50
		let prev = marks.prev(before: 5, types: ["bookmark"], bufferSize: 100)
		#expect(prev?.position == 50)
	}

	@Test func didReplaceAdjustsPositions() {
		let marks = BufferMarks()
		marks.set(at: 5, type: "bookmark", label: "a")
		marks.set(at: 15, type: "bookmark", label: "b")
		marks.set(at: 25, type: "bookmark", label: "c")

		// Insert 10 bytes at position 10 (replace [10,10) with 10)
		marks.didReplace(from: 10, to: 10, length: 10)

		#expect(marks.get(at: 5, type: "bookmark") == "a") // Before range, unchanged
		#expect(marks.get(at: 25, type: "bookmark") == "b") // 15 + 10 = 25
		#expect(marks.get(at: 35, type: "bookmark") == "c") // 25 + 10 = 35
	}

	@Test func didReplaceRemovesMarksInRange() {
		let marks = BufferMarks()
		marks.set(at: 5, type: "bookmark", label: "keep")
		marks.set(at: 10, type: "bookmark", label: "remove")
		marks.set(at: 20, type: "bookmark", label: "shift")

		// Delete [8, 15) — mark at 10 should be removed
		marks.didReplace(from: 8, to: 15, length: 0)

		#expect(marks.get(at: 5, type: "bookmark") == "keep")
		#expect(marks.get(at: 10, type: "bookmark") == nil) // removed
		#expect(marks.get(at: 13, type: "bookmark") == "shift") // 20 - 7 = 13
	}

	@Test func clear() {
		let marks = BufferMarks()
		marks.set(at: 10, type: "bookmark")
		marks.set(at: 20, type: "search")
		marks.clear()
		#expect(marks.isEmpty)
	}
}

// MARK: - BracketPairTracker Tests

@Suite("BracketPairTracker — Bracket Pair Tracking")
struct BracketPairTrackerTests {
	@Test func emptyTracker() {
		let tracker = BracketPairTracker()
		#expect(tracker.isEmpty)
		#expect(tracker.count == 0)
		#expect(!tracker.isFirst(at: 0))
		#expect(!tracker.isLast(at: 0))
	}

	@Test func addPair() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 5, last: 20)

		#expect(tracker.count == 2)
		#expect(tracker.isFirst(at: 5))
		#expect(tracker.isLast(at: 20))
		#expect(!tracker.isFirst(at: 20))
		#expect(!tracker.isLast(at: 5))
	}

	@Test func counterpart() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 5, last: 20)

		#expect(tracker.counterpart(of: 5) == 20)
		#expect(tracker.counterpart(of: 20) == 5)
		#expect(tracker.counterpart(of: 10) == nil)
	}

	@Test func multiplePairs() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 0, last: 30) // outer
		tracker.addPair(first: 5, last: 15) // inner

		#expect(tracker.count == 4)
		#expect(tracker.counterpart(of: 0) == 30)
		#expect(tracker.counterpart(of: 30) == 0)
		#expect(tracker.counterpart(of: 5) == 15)
		#expect(tracker.counterpart(of: 15) == 5)
	}

	@Test func isPaired() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 5, last: 20)

		#expect(tracker.isPaired(at: 5))
		#expect(tracker.isPaired(at: 20))
		#expect(!tracker.isPaired(at: 10))
	}

	@Test func removeSingle() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 5, last: 20)

		let removed = tracker.remove(at: 5)
		#expect(removed)
		#expect(tracker.count == 1)
		#expect(!tracker.isPaired(at: 5))
		#expect(tracker.isPaired(at: 20))
		// Counterpart of 20 should be nil since 5 was removed
		#expect(tracker.counterpart(of: 20) == nil)
	}

	@Test func clearPairs() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 0, last: 10)
		tracker.addPair(first: 20, last: 30)
		tracker.clear()
		#expect(tracker.isEmpty)
		#expect(tracker.count == 0)
	}

	@Test func allEntries() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 10, last: 30)
		tracker.addPair(first: 15, last: 25)

		let entries = tracker.allEntries
		#expect(entries.count == 4)
		// Sorted by position
		#expect(entries[0].position == 10)
		#expect(entries[0].isOpener)
		#expect(entries[1].position == 15)
		#expect(entries[1].isOpener)
		#expect(entries[2].position == 25)
		#expect(!entries[2].isOpener)
		#expect(entries[3].position == 30)
		#expect(!entries[3].isOpener)
	}

	@Test func didReplaceShiftsPairs() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 5, last: 20)

		// Insert 5 bytes at position 10
		tracker.didReplace(from: 10, to: 10, length: 5)

		#expect(tracker.isFirst(at: 5)) // unchanged
		#expect(tracker.isLast(at: 25)) // 20 + 5 = 25
		#expect(tracker.counterpart(of: 5) == 25)
	}

	@Test func didReplaceRemovesPairsInRange() {
		let tracker = BracketPairTracker()
		tracker.addPair(first: 5, last: 20)
		tracker.addPair(first: 30, last: 40)

		// Delete [3, 25) — pair (5, 20) should be removed entirely
		tracker.didReplace(from: 3, to: 25, length: 0)

		#expect(tracker.count == 2) // Only the second pair remains
		// Second pair shifted: 30 - 22 = 8, 40 - 22 = 18
		#expect(tracker.isFirst(at: 8))
		#expect(tracker.isLast(at: 18))
	}
}

// MARK: - SymbolExtractor Tests

@Suite("SymbolExtractor — Symbol Tracking")
struct SymbolExtractorTests {
	@Test func emptyExtractor() {
		let extractor = SymbolExtractor()
		#expect(extractor.isEmpty)
		#expect(extractor.count == 0)
		#expect(extractor.allSymbols().isEmpty)
	}

	@Test func setAndQuery() {
		let extractor = SymbolExtractor()
		extractor.setSymbol(at: 10, name: "main()")
		extractor.setSymbol(at: 50, name: "helper()")

		#expect(extractor.count == 2)

		let all = extractor.allSymbols()
		#expect(all[0].position == 10)
		#expect(all[0].name == "main()")
		#expect(all[1].position == 50)
		#expect(all[1].name == "helper()")
	}

	@Test func symbolAt() {
		let extractor = SymbolExtractor()
		extractor.setSymbol(at: 0, name: "header")
		extractor.setSymbol(at: 20, name: "main()")
		extractor.setSymbol(at: 50, name: "helper()")

		// Before first symbol
		let s0 = extractor.symbol(at: 0)
		#expect(s0?.name == "header")

		// Within main()
		let s1 = extractor.symbol(at: 30)
		#expect(s1?.name == "main()")

		// Within helper()
		let s2 = extractor.symbol(at: 60)
		#expect(s2?.name == "helper()")
	}

	@Test func updateSymbolsReplacesRange() {
		let extractor = SymbolExtractor()
		extractor.setSymbol(at: 0, name: "old1")
		extractor.setSymbol(at: 10, name: "old2")
		extractor.setSymbol(at: 20, name: "old3")

		extractor.updateSymbols(from: 5, to: 25, entries: [
			(position: 8, name: "new1"),
			(position: 15, name: "new2"),
		])

		let all = extractor.allSymbols()
		#expect(all.count == 3)
		#expect(all[0].name == "old1") // position 0, outside range
		#expect(all[1].name == "new1") // replaced
		#expect(all[2].name == "new2") // replaced
	}

	@Test func removeSymbol() {
		let extractor = SymbolExtractor()
		extractor.setSymbol(at: 10, name: "test")
		let removed = extractor.removeSymbol(at: 10)
		#expect(removed)
		#expect(extractor.isEmpty)
	}

	@Test func didReplaceShiftsSymbols() {
		let extractor = SymbolExtractor()
		extractor.setSymbol(at: 10, name: "a")
		extractor.setSymbol(at: 30, name: "b")

		// Insert 5 bytes at position 20
		extractor.didReplace(from: 20, to: 20, length: 5)

		let all = extractor.allSymbols()
		#expect(all[0].position == 10) // before range, unchanged
		#expect(all[1].position == 35) // 30 + 5 = 35
	}

	@Test func clearSymbols() {
		let extractor = SymbolExtractor()
		extractor.setSymbol(at: 10, name: "test")
		extractor.clear()
		#expect(extractor.isEmpty)
	}
}

// MARK: - SymbolTransformation Tests

@Suite("SymbolTransformation — s/pattern/format/ Chains")
struct SymbolTransformationTests {
	@Test func nilInput() {
		let t = SymbolTransformation(nil)
		#expect(t == nil)
	}

	@Test func emptyInput() {
		let t = SymbolTransformation("")
		#expect(t == nil)
	}

	@Test func simpleSubstitution() {
		let t = SymbolTransformation("s/world/Swift/")
		#expect(t != nil)
		#expect(t?.apply(to: "Hello world!") == "Hello Swift!")
	}

	@Test func globalSubstitution() {
		let t = SymbolTransformation("s/o/0/g")
		#expect(t != nil)
		#expect(t?.apply(to: "foo boo") == "f00 b00")
	}

	@Test func nonGlobalReplacesOnlyFirst() {
		let t = SymbolTransformation("s/o/0/")
		#expect(t != nil)
		#expect(t?.apply(to: "foo boo") == "f0o boo")
	}

	@Test func chainedSubstitutions() {
		let t = SymbolTransformation("s/^\\s*//;s/\\s*$//")
		#expect(t != nil)
		#expect(t?.apply(to: "  hello  ") == "hello")
	}

	@Test func captureGroups() {
		let t = SymbolTransformation("s/(\\w+)\\s+(\\w+)/$2 $1/")
		#expect(t != nil)
		#expect(t?.apply(to: "first second") == "second first")
	}

	@Test func escapedDelimiter() {
		let t = SymbolTransformation("s/a\\/b/x/")
		#expect(t != nil)
		#expect(t?.apply(to: "a/b c") == "x c")
	}

	@Test func stripFunctionArgs() {
		// Common symbolTransformation: remove everything after `(`
		let t = SymbolTransformation("s/\\(.*//")
		#expect(t != nil)
		#expect(t?.apply(to: "myFunc(int x, int y)") == "myFunc")
	}

	@Test func invalidRegex() {
		// Unbalanced group — should fail gracefully
		let t = SymbolTransformation("s/(unclosed/replacement/")
		#expect(t == nil)
	}

	@Test func patternCount() {
		let t = SymbolTransformation("s/a/b/;s/c/d/;s/e/f/")
		#expect(t != nil)
		#expect(t?.patterns.count == 3)
	}
}

// MARK: - BufferSpelling Tests

@Suite("BufferSpelling — Misspelling Tracking")
struct BufferSpellingTests {
	@Test func emptySpelling() {
		let spelling = BufferSpelling()
		#expect(spelling.isEmpty)
		#expect(!spelling.isMisspelled(at: 0))
		#expect(spelling.nextMisspelling(from: 0) == nil)
	}

	@Test func updateMisspellings() {
		let spelling = BufferSpelling()
		spelling.updateMisspellings(from: 0, to: 50, ranges: [
			(start: 5, end: 10), // "wrold"
			(start: 20, end: 28), // "mispeled"
		])

		#expect(!spelling.isMisspelled(at: 3))
		#expect(spelling.isMisspelled(at: 5))
		#expect(spelling.isMisspelled(at: 7))
		#expect(!spelling.isMisspelled(at: 10))
		#expect(!spelling.isMisspelled(at: 15))
		#expect(spelling.isMisspelled(at: 20))
		#expect(spelling.isMisspelled(at: 25))
		#expect(!spelling.isMisspelled(at: 28))
	}

	@Test func nextMisspelling() {
		let spelling = BufferSpelling()
		spelling.updateMisspellings(from: 0, to: 50, ranges: [
			(start: 10, end: 15),
			(start: 30, end: 35),
		])

		#expect(spelling.nextMisspelling(from: 0) == 10)
		#expect(spelling.nextMisspelling(from: 10) == 10) // At start of misspelling
		#expect(spelling.nextMisspelling(from: 12) == 12) // Within misspelling
		#expect(spelling.nextMisspelling(from: 15) == 30) // After first misspelling
		#expect(spelling.nextMisspelling(from: 36) == nil) // Past all
	}

	@Test func misspellingsInRange() {
		let spelling = BufferSpelling()
		spelling.updateMisspellings(from: 0, to: 100, ranges: [
			(start: 5, end: 10),
			(start: 20, end: 30),
			(start: 50, end: 60),
		])

		let result = spelling.misspellings(from: 8, to: 55)
		#expect(result.count == 3)
		// First: [8, 10) — clipped to query start
		#expect(result[0].start == 8)
		#expect(result[0].end == 10)
		// Second: [20, 30) — fully within query
		#expect(result[1].start == 20)
		#expect(result[1].end == 30)
		// Third: [50, 55) — clipped to query end
		#expect(result[2].start == 50)
		#expect(result[2].end == 55)
	}

	@Test func didReplaceShiftsMisspellings() {
		let spelling = BufferSpelling()
		spelling.updateMisspellings(from: 0, to: 50, ranges: [
			(start: 20, end: 25),
		])

		// Insert 10 bytes at position 10
		spelling.didReplace(from: 10, to: 10, length: 10)

		#expect(!spelling.isMisspelled(at: 20)) // shifted
		#expect(spelling.isMisspelled(at: 30)) // 20 + 10 = 30
		#expect(!spelling.isMisspelled(at: 35)) // 25 + 10 = 35
	}

	@Test func recheck() {
		let spelling = BufferSpelling()
		spelling.updateMisspellings(from: 0, to: 50, ranges: [
			(start: 5, end: 10),
		])
		#expect(spelling.isMisspelled(at: 7))

		spelling.recheck()
		#expect(!spelling.isMisspelled(at: 7))
		#expect(spelling.isEmpty)
	}

	@Test func clearSpelling() {
		let spelling = BufferSpelling()
		spelling.updateMisspellings(from: 0, to: 50, ranges: [(start: 5, end: 10)])
		spelling.clear()
		#expect(spelling.isEmpty)
	}
}

// MARK: - Integration: TextBuffer + BufferCallback

@Suite("Buffer Metadata — TextBuffer Integration")
struct BufferMetadataIntegrationTests {
	@Test func marksAutoAdjustOnInsert() {
		let buffer = TextBuffer("Hello World")
		let marks = BufferMarks()
		buffer.addCallback(marks)

		marks.set(at: 6, type: "bookmark", label: "W")

		// Insert ", Beautiful" at position 5
		buffer.replace(from: 5, to: 5, with: ", Beautiful")

		// Mark should shift right by 11 bytes
		#expect(marks.get(at: 6, type: "bookmark") == nil)
		#expect(marks.get(at: 17, type: "bookmark") == "W")
	}

	@Test func pairsAutoAdjustOnInsert() {
		let buffer = TextBuffer("()")
		let tracker = BracketPairTracker()
		buffer.addCallback(tracker)

		tracker.addPair(first: 0, last: 1)

		// Insert "hello" between the brackets
		buffer.replace(from: 1, to: 1, with: "hello")

		#expect(tracker.isFirst(at: 0))
		#expect(tracker.isLast(at: 6)) // 1 + 5 = 6
		#expect(tracker.counterpart(of: 0) == 6)
	}

	@Test func symbolsAutoAdjustOnDelete() {
		let buffer = TextBuffer("int main() {}\nvoid helper() {}")
		let symbols = SymbolExtractor()
		buffer.addCallback(symbols)

		symbols.setSymbol(at: 0, name: "main")
		symbols.setSymbol(at: 15, name: "helper")

		// Delete "int " (4 bytes at position 0)
		buffer.erase(from: 0, to: 4)

		let all = symbols.allSymbols()
		#expect(all.count == 1) // "main" at 0 was in [0,4) → removed
		#expect(all[0].name == "helper")
		#expect(all[0].position == 11) // 15 - 4 = 11
	}

	@Test func spellingAutoAdjustOnReplace() {
		let buffer = TextBuffer("The wrold is big")
		let spelling = BufferSpelling()
		buffer.addCallback(spelling)

		spelling.updateMisspellings(from: 0, to: 16, ranges: [
			(start: 4, end: 9), // "wrold"
		])

		// Replace "wrold" with "world" (same length)
		buffer.replace(from: 4, to: 9, with: "world")

		// The misspelling entry at position 4 was in [4,9) and got removed
		// by the replace adjustment. The spelling subsystem would need to
		// re-check the region to restore correct data.
		// For now just verify the auto-adjustment didn't crash.
		#expect(!spelling.isMisspelled(at: 4))
	}

	@Test func multipleCallbacksOnSameBuffer() {
		let buffer = TextBuffer("function test() { return 42; }")
		let marks = BufferMarks()
		let pairs = BracketPairTracker()
		let symbols = SymbolExtractor()
		buffer.addCallback(marks)
		buffer.addCallback(pairs)
		buffer.addCallback(symbols)

		marks.set(at: 0, type: "bookmark")
		pairs.addPair(first: 14, last: 15)
		symbols.setSymbol(at: 0, name: "test")

		// Insert "async " before "function"
		buffer.insert(at: 0, string: "async ")

		#expect(marks.get(at: 0, type: "bookmark") == nil) // at [0,0), removed by bindRight
		#expect(pairs.isFirst(at: 20)) // 14 + 6 = 20
		#expect(pairs.isLast(at: 21)) // 15 + 6 = 21
		// Symbol at 0 was in [0,0) range — empty range insert at same position
		// With bindRight=true, lowerBound(0) to lowerBound(0) is empty range, nothing removed
		// Then shift: entries >= 0 shift by 6
		let all = symbols.allSymbols()
		#expect(all[0].position == 6) // 0 + 6 = 6
	}
}
