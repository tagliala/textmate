import Foundation
import Testing
@testable import TMDocumentManager

@Suite("StreamingFileReader")
struct StreamingFileReaderTests {
	// MARK: - BOM Detection

	@Test("Detects UTF-8 BOM")
	func detectUTF8BOM() {
		let data = Data([0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C, 0x6C, 0x6F])
		let bom = StreamingFileReader.detectBOM(data)
		#expect(bom.charset == "UTF-8")
		#expect(bom.length == 3)
	}

	@Test("Detects UTF-16BE BOM")
	func detectUTF16BEBOM() {
		let data = Data([0xFE, 0xFF, 0x00, 0x48])
		let bom = StreamingFileReader.detectBOM(data)
		#expect(bom.charset == "UTF-16BE")
		#expect(bom.length == 2)
	}

	@Test("Detects UTF-16LE BOM")
	func detectUTF16LEBOM() {
		let data = Data([0xFF, 0xFE, 0x48, 0x00])
		let bom = StreamingFileReader.detectBOM(data)
		#expect(bom.charset == "UTF-16LE")
		#expect(bom.length == 2)
	}

	@Test("Detects UTF-32BE BOM")
	func detectUTF32BEBOM() {
		let data = Data([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x48])
		let bom = StreamingFileReader.detectBOM(data)
		#expect(bom.charset == "UTF-32BE")
		#expect(bom.length == 4)
	}

	@Test("Detects UTF-32LE BOM")
	func detectUTF32LEBOM() {
		let data = Data([0xFF, 0xFE, 0x00, 0x00, 0x48, 0x00, 0x00, 0x00])
		let bom = StreamingFileReader.detectBOM(data)
		#expect(bom.charset == "UTF-32LE")
		#expect(bom.length == 4)
	}

	@Test("No BOM in plain ASCII")
	func noBOM() {
		let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])
		let bom = StreamingFileReader.detectBOM(data)
		#expect(bom.charset == nil)
		#expect(bom.length == 0)
	}

	@Test("Empty data has no BOM")
	func emptyNoBOM() {
		let bom = StreamingFileReader.detectBOM(Data())
		#expect(bom.charset == nil)
		#expect(bom.length == 0)
	}

	// MARK: - ASCII Detection

	@Test("ASCII data detected correctly")
	func isASCII() {
		let data = "Hello, World!".data(using: .ascii)!
		#expect(StreamingFileReader.isASCII(data))
	}

	@Test("Non-ASCII data detected correctly")
	func isNotASCII() {
		let data = "Héllo café".data(using: .utf8)!
		#expect(!StreamingFileReader.isASCII(data))
	}

	@Test("Empty data is ASCII")
	func emptyIsASCII() {
		#expect(StreamingFileReader.isASCII(Data()))
	}

	// MARK: - Encoding Detection

	@Test("Detects UTF-8 BOM in encoding cascade")
	func encodingCascadeBOM() {
		let data = Data([0xEF, 0xBB, 0xBF]) + "Hello".data(using: .utf8)!
		let encoding = StreamingFileReader.detectEncoding(data: data, path: "/tmp/test.txt")
		#expect(encoding.charset == "UTF-8")
		#expect(encoding.hasBOM)
	}

	@Test("Detects ASCII content")
	func encodingCascadeASCII() {
		let data = "Hello World 123".data(using: .ascii)!
		let encoding = StreamingFileReader.detectEncoding(data: data, path: "/tmp/test.txt")
		#expect(encoding.charset == "ASCII")
		#expect(!encoding.hasBOM)
	}

	@Test("Detects UTF-8 for non-ASCII content")
	func encodingCascadeUTF8() {
		let data = "Héllo wörld café".data(using: .utf8)!
		let encoding = StreamingFileReader.detectEncoding(data: data, path: "/tmp/test.txt")
		#expect(encoding.charset == "UTF-8")
		#expect(!encoding.hasBOM)
	}

	@Test("Hint overrides auto-detection")
	func encodingCascadeHint() {
		let data = "Hello".data(using: .ascii)!
		let options = EncodingCascadeOptions(charsetHint: "ISO-8859-1", checkXattr: false)
		let encoding = StreamingFileReader.detectEncoding(
			data: data,
			path: "/tmp/test.txt",
			options: options,
		)
		#expect(encoding.charset == "ISO-8859-1")
	}

	@Test("BOM takes precedence over hint")
	func bomBeatsHint() {
		let data = Data([0xFE, 0xFF, 0x00, 0x48])
		let options = EncodingCascadeOptions(charsetHint: "ISO-8859-1")
		let encoding = StreamingFileReader.detectEncoding(
			data: data,
			path: "/tmp/test.txt",
			options: options,
		)
		#expect(encoding.charset == "UTF-16BE")
		#expect(encoding.hasBOM)
	}

	// MARK: - File Reading

	@Test("Read plain UTF-8 file")
	func readUTF8File() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/streaming_reader_test_utf8.txt"
		let text = "Hello, Swift!\nSecond line.\n"
		// Use Data.write to avoid macOS setting com.apple.TextEncoding xattr
		try text.data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
		// Remove any xattr
		removexattr(path, "com.apple.TextEncoding", 0)
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try StreamingFileReader.read(path: path)
		#expect(result.content == text)
		// All-ASCII content should be detected as ASCII
		#expect(result.encoding.charset == "ASCII")
		#expect(result.rawByteCount == text.utf8.count)
	}

	@Test("Read UTF-8 file with non-ASCII content")
	func readUTF8NonASCII() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/streaming_reader_test_nonascii.txt"
		let text = "Héllo café résumé naïve über"
		// Use Data.write to avoid macOS setting com.apple.TextEncoding xattr
		try text.data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
		// Remove any xattr
		removexattr(path, "com.apple.TextEncoding", 0)
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try StreamingFileReader.read(path: path)
		#expect(result.content == text)
		#expect(result.encoding.charset == "UTF-8")
	}

	@Test("Read file with UTF-8 BOM")
	func readUTF8BOMFile() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/streaming_reader_test_bom.txt"
		let text = "Hello BOM"
		let bom = Data([0xEF, 0xBB, 0xBF])
		let data = bom + text.data(using: .utf8)!
		try data.write(to: URL(fileURLWithPath: path))
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try StreamingFileReader.read(path: path)
		#expect(result.encoding.charset == "UTF-8")
		#expect(result.encoding.hasBOM)
	}

	@Test("Read empty file")
	func readEmptyFile() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/streaming_reader_test_empty.txt"
		try Data().write(to: URL(fileURLWithPath: path))
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try StreamingFileReader.read(path: path)
		#expect(result.content.isEmpty)
		#expect(result.rawByteCount == 0)
	}

	@Test("Read with byte limit")
	func readWithLimit() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/streaming_reader_test_limit.txt"
		let text = String(repeating: "A", count: 1000)
		try text.write(toFile: path, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try StreamingFileReader.read(path: path, limit: 100)
		#expect(result.content.count == 100)
		#expect(result.rawByteCount == 1000)
	}

	@Test("Read nonexistent file throws")
	func readNonexistentThrows() {
		#expect(throws: Error.self) {
			try StreamingFileReader.read(path: "/nonexistent/path/file.txt")
		}
	}

	// MARK: - Chunked Reading

	@Test("Chunked reading produces same content as full read")
	func chunkedMatchesFull() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/streaming_reader_test_chunked.txt"
		// Create content larger than chunk size
		let text = String(repeating: "Hello, World! ", count: 1000)
		try text.write(toFile: path, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: path) }

		var chunks: [String] = []
		_ = try StreamingFileReader.readChunked(path: path) { chunk in
			chunks.append(chunk)
		}

		let chunkedContent = chunks.joined()
		#expect(chunkedContent == text)
	}

	// MARK: - Xattr Reading

	@Test("Read TextEncoding xattr")
	func readXattr() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/streaming_reader_test_xattr.txt"
		let text = "Hello"
		try text.write(toFile: path, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: path) }

		// Set the xattr
		let value = "ISO-8859-1;1536"
		_ = value.withCString { cstr in
			setxattr(path, "com.apple.TextEncoding", cstr, strlen(cstr), 0, 0)
		}

		let charset = StreamingFileReader.readTextEncodingXattr(path: path)
		#expect(charset == "ISO-8859-1")
	}

	@Test("No TextEncoding xattr returns nil for file without xattr")
	func noXattr() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/streaming_reader_test_noxattr.txt"
		// Write raw data without going through NSString to avoid macOS setting the xattr
		try Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]).write(to: URL(fileURLWithPath: path))
		defer { try? FileManager.default.removeItem(atPath: path) }

		// Remove any xattr that might have been set
		removexattr(path, "com.apple.TextEncoding", 0)

		let charset = StreamingFileReader.readTextEncodingXattr(path: path)
		#expect(charset == nil)
	}

	// MARK: - Encoding Cascade Options

	@Test("Disabled ASCII check falls through to UTF-8")
	func disableASCII() {
		let data = "Hello".data(using: .ascii)!
		let options = EncodingCascadeOptions(checkXattr: false, checkASCII: false)
		let encoding = StreamingFileReader.detectEncoding(
			data: data,
			path: "/tmp/test.txt",
			options: options,
		)
		#expect(encoding.charset == "UTF-8")
	}

	@Test("Settings provider is consulted")
	func settingsProvider() {
		let data = "Hello".data(using: .ascii)!
		let options = EncodingCascadeOptions(
			settingsCharsetProvider: { _, _ in "windows-1252" },
			checkXattr: false,
			checkASCII: false,
		)
		let encoding = StreamingFileReader.detectEncoding(
			data: data,
			path: "/tmp/test.txt",
			options: options,
		)
		#expect(encoding.charset == "windows-1252")
	}
}
