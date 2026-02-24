import Foundation
import Testing
@testable import TMCore

@Suite("FileStatus — Writability")
struct FileStatusWritabilityTests {
	@Test("writable file reports writable status")
	func writableFile() {
		let path = PathUtilities.temp() + "/tm_test_status_\(ProcessInfo.processInfo.processIdentifier).txt"
		defer { PathUtilities.remove(path) }

		PathUtilities.setContent(path, string: "test")
		let result = FileStatus.status(path)
		#expect(result == .writable)
	}

	@Test("nonexistent file in writable directory reports writable")
	func creatableFile() {
		let path = PathUtilities.temp() + "/tm_test_nonexistent_\(ProcessInfo.processInfo.processIdentifier).txt"
		let result = FileStatus.status(path)
		#expect(result == .writable)
	}

	@Test("root-owned files may not be writable")
	func rootOwnedFile() {
		// /etc/hosts is typically root-owned and not writable by normal user
		let result = FileStatus.status("/etc/hosts")
		#expect(result == .readOnly || result == .writable || result == .notWritable || result == .writableByRoot)
	}

	@Test("nonexistent directory reports immutable")
	func nonexistentDirectory() {
		let result = FileStatus.status("/nonexistent_dir_12345/foo.txt")
		#expect(result == .noParent || result == .readOnly)
	}
}

@Suite("FileStatus — Path Attributes")
struct FileStatusPathAttributeTests {
	@Test("nil path returns attr.untitled plus os-version")
	func nilPath() {
		let attrs = FileStatus.pathAttributes(nil)
		#expect(attrs.hasPrefix("attr.untitled"))
		#expect(attrs.contains("attr.os-version."))
	}

	@Test("file path returns reversed dotted path")
	func filePath() {
		let attrs = FileStatus.pathAttributes("/Users/test/foo.txt")
		#expect(attrs.contains("attr.rev-path."))
		#expect(attrs.contains("txt"))
	}

	@Test("absolute path includes os.version")
	func osVersionIncluded() {
		let attrs = FileStatus.pathAttributes("/tmp/test.rb")
		#expect(attrs.contains("attr.os-version."))
	}
}

@Suite("FileStatus — BOM Detection")
struct FileStatusBOMTests {
	@Test("UTF-8 BOM detected")
	func utf8BOM() {
		let data = Data([0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C, 0x6C, 0x6F])
		let result = FileStatus.charsetFromBOM(data)
		#expect(result.charset == .utf8)
		#expect(result.bomLength == 3)
	}

	@Test("UTF-16 BE BOM detected")
	func utf16beBOM() {
		let data = Data([0xFE, 0xFF, 0x00, 0x48])
		let result = FileStatus.charsetFromBOM(data)
		#expect(result.charset == .utf16BE)
		#expect(result.bomLength == 2)
	}

	@Test("UTF-16 LE BOM detected")
	func utf16leBOM() {
		let data = Data([0xFF, 0xFE, 0x48, 0x00])
		let result = FileStatus.charsetFromBOM(data)
		#expect(result.charset == .utf16LE)
		#expect(result.bomLength == 2)
	}

	@Test("UTF-32 BE BOM detected")
	func utf32beBOM() {
		let data = Data([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x48])
		let result = FileStatus.charsetFromBOM(data)
		#expect(result.charset == .utf32BE)
		#expect(result.bomLength == 4)
	}

	@Test("UTF-32 LE BOM detected")
	func utf32leBOM() {
		let data = Data([0xFF, 0xFE, 0x00, 0x00, 0x48, 0x00, 0x00, 0x00])
		let result = FileStatus.charsetFromBOM(data)
		#expect(result.charset == .utf32LE)
		#expect(result.bomLength == 4)
	}

	@Test("no BOM returns nil charset")
	func noBOM() {
		let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])
		let result = FileStatus.charsetFromBOM(data)
		#expect(result.charset == nil)
		#expect(result.bomLength == 0)
	}

	@Test("empty data returns nil charset")
	func emptyData() {
		let result = FileStatus.charsetFromBOM(Data())
		#expect(result.charset == nil)
		#expect(result.bomLength == 0)
	}

	@Test("stringEncoding maps charset names")
	func stringEncodingMapping() {
		#expect(FileStatus.stringEncoding(for: "UTF-8") == .utf8)
		#expect(FileStatus.stringEncoding(for: "UTF-16BE") == .utf16BigEndian)
		#expect(FileStatus.stringEncoding(for: "UTF-16LE") == .utf16LittleEndian)
		#expect(FileStatus.stringEncoding(for: "ISO-8859-1") == .isoLatin1)
		#expect(FileStatus.stringEncoding(for: "UNKNOWN-X") == nil)
	}
}
