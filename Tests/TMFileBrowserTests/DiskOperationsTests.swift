#if canImport(AppKit)
import Foundation
import Testing
@testable import TMFileBrowser

@Suite("DiskOperation OptionSet")
struct DiskOperationTests {
	@Test("individual raw values are distinct powers of two")
	func distinctRawValues() {
		let all: [DiskOperation] = [
			.link, .copy, .duplicate, .move, .rename, .trash, .newFile, .newFolder,
		]
		let rawValues = all.map(\.rawValue)
		#expect(Set(rawValues).count == all.count)
		for raw in rawValues {
			#expect(raw > 0)
			#expect(raw & (raw - 1) == 0, "Raw value \(raw) is not a power of two")
		}
	}

	@Test("option set union works correctly")
	func optionSetUnion() {
		let combined: DiskOperation = [.link, .copy]
		#expect(combined.contains(.link))
		#expect(combined.contains(.copy))
		#expect(!combined.contains(.move))
	}

	@Test("option set intersection works correctly")
	func optionSetIntersection() {
		let a: DiskOperation = [.link, .copy, .move]
		let b: DiskOperation = [.copy, .trash]
		let result = a.intersection(b)
		#expect(result.contains(.copy))
		#expect(!result.contains(.link))
		#expect(!result.contains(.trash))
	}

	@Test("empty option set contains nothing")
	func emptySet() {
		let empty = DiskOperation(rawValue: 0)
		#expect(!empty.contains(.link))
		#expect(!empty.contains(.copy))
		#expect(!empty.contains(.trash))
	}
}

@Suite("DiskOperationHandler.incrementedName")
struct IncrementedNameTests {
	@Test("simple filename gets counter appended")
	@MainActor func simpleFilename() {
		#expect(DiskOperationHandler.incrementedName("file.txt", counter: 2) == "file 2.txt")
	}

	@Test("counter replaces existing counter")
	@MainActor func existingCounter() {
		#expect(DiskOperationHandler.incrementedName("file 2.txt", counter: 3) == "file 3.txt")
	}

	@Test("filename without extension")
	@MainActor func noExtension() {
		#expect(DiskOperationHandler.incrementedName("Makefile", counter: 2) == "Makefile 2")
	}

	@Test("filename with multiple dots")
	@MainActor func multipleDots() {
		let result = DiskOperationHandler.incrementedName("archive.tar.gz", counter: 2)
		// The regex matches the last `.xxx` as the extension
		#expect(result.contains("2"))
	}

	@Test("counter 1 still produces output")
	@MainActor func counterOne() {
		let result = DiskOperationHandler.incrementedName("readme.md", counter: 1)
		#expect(result.contains("1"))
	}

	@Test("higher counter values work")
	@MainActor func highCounter() {
		#expect(DiskOperationHandler.incrementedName("doc.pdf", counter: 99) == "doc 99.pdf")
	}
}

@Suite("DiskOperationHandler unique destination URLs")
struct UniqueDestinationURLsTests {
	@Test("unique URLs for non-conflicting paths")
	@MainActor func nonConflicting() {
		let handler = DiskOperationHandler()
		let urls = [
			URL(fileURLWithPath: "/tmp/tmfb-test-\(UUID())/a.txt"),
			URL(fileURLWithPath: "/tmp/tmfb-test-\(UUID())/b.txt"),
		]
		let result = handler.uniqueDestinationURLs(urls)
		#expect(result.count == 2)
		#expect(Set(result).count == 2)
	}

	@Test("unique URLs handle existing files", .disabled("requires disk access"))
	@MainActor func existingFiles() {
		// This test would require creating files on disk
	}
}
#endif
