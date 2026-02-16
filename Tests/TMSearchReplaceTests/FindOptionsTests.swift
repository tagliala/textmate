import Foundation
import Testing
@testable import TMSearchReplace

// MARK: - FindOptions Tests

@Suite("FindOptions")
struct FindOptionsTests {
	@Test("Default options include ignoreCase and wrapAround")
	func defaultOptions() {
		let opts = FindOptions.default
		#expect(opts.contains(.ignoreCase))
		#expect(opts.contains(.wrapAround))
		#expect(!opts.contains(.regularExpression))
		#expect(!opts.contains(.fullWords))
	}

	@Test("None has no options")
	func noneOptions() {
		let opts = FindOptions.none
		#expect(opts.rawValue == 0)
	}

	@Test("Options are combinable")
	func combinable() {
		let opts: FindOptions = [.ignoreCase, .regularExpression, .fullWords]
		#expect(opts.contains(.ignoreCase))
		#expect(opts.contains(.regularExpression))
		#expect(opts.contains(.fullWords))
		#expect(!opts.contains(.backwards))
	}

	@Test("Options are Codable")
	func codable() throws {
		let opts: FindOptions = [.ignoreCase, .wrapAround, .regularExpression]
		let data = try JSONEncoder().encode(opts)
		let decoded = try JSONDecoder().decode(FindOptions.self, from: data)
		#expect(decoded == opts)
	}

	@Test("Options are Hashable")
	func hashable() {
		let a: FindOptions = [.ignoreCase, .fullWords]
		let b: FindOptions = [.ignoreCase, .fullWords]
		let c: FindOptions = [.ignoreCase]
		#expect(a == b)
		#expect(a != c)
		#expect(a.hashValue == b.hashValue)
	}

	@Test("Backwards option")
	func backwards() {
		let opts: FindOptions = [.backwards]
		#expect(opts.contains(.backwards))
		#expect(!opts.contains(.ignoreCase))
	}

	@Test("ExtendSelection option")
	func extendSelection() {
		let opts: FindOptions = [.extendSelection]
		#expect(opts.contains(.extendSelection))
	}
}

// MARK: - FindOperation Tests

@Suite("FindOperation")
struct FindOperationTests {
	@Test("All operations have distinct raw values")
	func distinctValues() {
		let operations: [FindOperation] = [
			.count, .countInSelection, .find, .findInSelection,
			.replace, .replaceAndFind, .replaceAll, .replaceAllInSelection,
		]
		let rawValues = Set(operations.map(\.rawValue))
		#expect(rawValues.count == operations.count)
	}

	@Test("Operations have expected raw values")
	func rawValues() {
		#expect(FindOperation.count.rawValue == 0)
		#expect(FindOperation.find.rawValue == 2)
		#expect(FindOperation.replace.rawValue == 4)
		#expect(FindOperation.replaceAll.rawValue == 6)
	}
}

// MARK: - SearchScope Tests

@Suite("SearchScope")
struct SearchScopeTests {
	@Test("All scopes have distinct raw values")
	func distinctValues() {
		let scopes: [SearchScope] = [
			.document, .selection, .openFiles, .project, .fileBrowserItems, .other,
		]
		let rawValues = Set(scopes.map(\.rawValue))
		#expect(rawValues.count == scopes.count)
	}

	@Test("Document is default (0)")
	func documentDefault() {
		#expect(SearchScope.document.rawValue == 0)
	}
}

// MARK: - FindMatch Tests

@Suite("FindMatch")
struct FindMatchTests {
	@Test("Basic match creation")
	func basic() {
		let match = FindMatch(range: 10 ..< 20)
		#expect(match.range == 10 ..< 20)
		#expect(match.captures.isEmpty)
		#expect(match.length == 10)
		#expect(!match.isEmpty)
	}

	@Test("Match with captures")
	func withCaptures() {
		let match = FindMatch(range: 0 ..< 5, captures: ["0": "hello", "1": "ell"])
		#expect(match.captures["0"] == "hello")
		#expect(match.captures["1"] == "ell")
	}

	@Test("Empty match")
	func empty() {
		let match = FindMatch(range: 5 ..< 5)
		#expect(match.isEmpty)
		#expect(match.length == 0)
	}

	@Test("Match equality ignores ID")
	func equality() {
		let a = FindMatch(range: 0 ..< 10, captures: ["0": "hello"])
		let b = FindMatch(range: 0 ..< 10, captures: ["0": "hello"])
		#expect(a == b)
		#expect(a.id != b.id) // Different UUIDs
	}

	@Test("Match inequality for different ranges")
	func inequality() {
		let a = FindMatch(range: 0 ..< 10)
		let b = FindMatch(range: 5 ..< 15)
		#expect(a != b)
	}
}

// MARK: - DocumentMatch Tests

@Suite("DocumentMatch")
struct DocumentMatchTests {
	@Test("Basic document match")
	func basic() {
		let docID = UUID()
		let match = DocumentMatch(
			documentID: docID,
			documentPath: "/tmp/test.swift",
			displayName: "test.swift",
			byteRange: 10 ..< 20,
			lineNumber: 5,
			excerpt: "let x = 42",
		)
		#expect(match.documentID == docID)
		#expect(match.documentPath == "/tmp/test.swift")
		#expect(match.displayName == "test.swift")
		#expect(match.byteRange == 10 ..< 20)
		#expect(match.lineNumber == 5)
		#expect(match.excerpt == "let x = 42")
	}

	@Test("Document match with truncated excerpt")
	func truncated() {
		let match = DocumentMatch(
			documentID: UUID(),
			displayName: "test.swift",
			byteRange: 0 ..< 10,
			headTruncated: true,
			tailTruncated: true,
		)
		#expect(match.headTruncated)
		#expect(match.tailTruncated)
	}
}

// MARK: - LineColumnRange Tests

@Suite("LineColumnRange")
struct LineColumnRangeTests {
	@Test("Zero range")
	func zero() {
		let range = LineColumnRange.zero
		#expect(range.startLine == 0)
		#expect(range.startColumn == 0)
		#expect(range.endLine == 0)
		#expect(range.endColumn == 0)
	}

	@Test("Same line description")
	func sameLineDescription() {
		let range = LineColumnRange(startLine: 0, startColumn: 5, endLine: 0, endColumn: 15)
		#expect(range.description == "1:5-15")
	}

	@Test("Multi-line description")
	func multiLineDescription() {
		let range = LineColumnRange(startLine: 2, startColumn: 0, endLine: 5, endColumn: 10)
		#expect(range.description == "3:0-6:10")
	}

	@Test("Equality")
	func equality() {
		let a = LineColumnRange(startLine: 1, startColumn: 2, endLine: 3, endColumn: 4)
		let b = LineColumnRange(startLine: 1, startColumn: 2, endLine: 3, endColumn: 4)
		#expect(a == b)
	}

	@Test("Hashable")
	func hashable() {
		let a = LineColumnRange(startLine: 1, startColumn: 2, endLine: 3, endColumn: 4)
		let b = LineColumnRange(startLine: 1, startColumn: 2, endLine: 3, endColumn: 4)
		#expect(a.hashValue == b.hashValue)
	}
}
