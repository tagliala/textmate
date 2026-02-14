import Foundation
import Testing
@testable import TMDocumentWindow

@Suite("DocumentModel")
@MainActor
struct DocumentModelTests {
	@Test("new document has default values")
	func newDocumentDefaults() {
		let model = DocumentModel()
		#expect(model.fileURL == nil)
		#expect(model.encoding == .utf8)
		#expect(model.isModified == false)
		#expect(model.displayTitle == "Untitled")
		#expect(model.encodingDisplayName == "UTF-8")
	}

	@Test("display title shows filename when URL is set")
	func displayTitleWithURL() {
		let model = DocumentModel(fileURL: URL(fileURLWithPath: "/tmp/hello.swift"))
		#expect(model.displayTitle == "hello.swift")
	}

	@Test("encoding display name for various encodings")
	func encodingDisplayNames() {
		let cases: [(String.Encoding, String)] = [
			(.utf8, "UTF-8"),
			(.utf16, "UTF-16"),
			(.isoLatin1, "ISO Latin 1"),
			(.ascii, "ASCII"),
			(.macOSRoman, "Mac Roman"),
			(.shiftJIS, "Shift JIS"),
		]
		for (encoding, expected) in cases {
			let model = DocumentModel(encoding: encoding)
			#expect(model.encodingDisplayName == expected)
		}
	}

	@Test("BOM detection for UTF-8")
	func bomDetectionUTF8() throws {
		let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
		let text = "Hello"
		var data = Data(bom)
		try data.append(#require(text.data(using: .utf8)))
		let (decoded, encoding) = DocumentModel.decodeWithEncodingDetection(data)
		#expect(decoded.contains("Hello"))
		#expect(encoding == .utf8)
	}

	@Test("BOM detection for UTF-16 BE")
	func bomDetectionUTF16BE() throws {
		let bom: [UInt8] = [0xFE, 0xFF]
		var data = Data(bom)
		try data.append(#require("Hi".data(using: .utf16BigEndian)))
		let (_, encoding) = DocumentModel.decodeWithEncodingDetection(data)
		#expect(encoding == .utf16BigEndian)
	}

	@Test("BOM detection for UTF-16 LE")
	func bomDetectionUTF16LE() throws {
		let bom: [UInt8] = [0xFF, 0xFE]
		var data = Data(bom)
		try data.append(#require("Hi".data(using: .utf16LittleEndian)))
		let (_, encoding) = DocumentModel.decodeWithEncodingDetection(data)
		#expect(encoding == .utf16LittleEndian)
	}

	@Test("plain UTF-8 without BOM")
	func plainUTF8() {
		let data = "Hello, world!".data(using: .utf8)!
		let (decoded, encoding) = DocumentModel.decodeWithEncodingDetection(data)
		#expect(decoded == "Hello, world!")
		#expect(encoding == .utf8)
	}

	@Test("round-trip write and read")
	func roundTrip() throws {
		let tmpDir = FileManager.default.temporaryDirectory
		let url = tmpDir.appendingPathComponent("test_\(UUID().uuidString).txt")
		defer { try? FileManager.default.removeItem(at: url) }

		let original = "Hello, TextMate! 🎉\n日本語テスト"

		let writeModel = DocumentModel(fileURL: url)
		try writeModel.writeFile(text: original)

		let readModel = DocumentModel()
		let decoded = try readModel.readFile(at: url)
		#expect(decoded == original)
		#expect(readModel.encoding == .utf8)
		#expect(readModel.fileURL == url)
	}

	@Test("write without URL throws noFileURL")
	func writeWithoutURL() {
		let model = DocumentModel()
		#expect(throws: DocumentError.self) {
			try model.writeFile(text: "test")
		}
	}
}
