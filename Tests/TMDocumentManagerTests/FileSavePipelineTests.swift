import Foundation
import Testing
@testable import TMDocumentManager

// MARK: - Test Helpers

/// A configurable mock delegate for testing the save pipeline.
struct MockFileSaveDelegate: FileSaveDelegate {
	var pathOverride: String?
	var makeWritable: Bool = false
	var createParent: Bool = true
	var authorizeWrite: Bool = false
	var charsetOverride: String?
	var textFilterTransform: (@Sendable (String) -> String)?
	var binaryFilterTransform: (@Sendable (Data) -> Data)?

	func selectPath(
		suggestedPath: String?,
		content _: String,
	) async -> String? {
		pathOverride ?? suggestedPath
	}

	func selectMakeWritable(path _: String) async -> Bool {
		makeWritable
	}

	func selectCreateParent(path _: String) async -> Bool {
		createParent
	}

	func obtainWriteAuthorization(for _: String) async -> Bool {
		authorizeWrite
	}

	func selectCharset(
		for _: String,
		currentCharset: String,
	) async -> String? {
		charsetOverride ?? currentCharset
	}

	func runTextExportFilters(
		path _: String,
		content: String,
		pathAttributes _: String,
	) async throws -> String {
		textFilterTransform?(content) ?? content
	}

	func runBinaryExportFilters(
		path _: String,
		data: Data,
		pathAttributes _: String,
	) async throws -> Data {
		binaryFilterTransform?(data) ?? data
	}
}

@Suite("FileSavePipeline")
struct FileSavePipelineTests {
	// MARK: - Line Ending Conversion

	@Test("LF to CRLF conversion")
	func convertLFtoCRLF() {
		let pipeline = FileSavePipeline()
		let input = "line1\nline2\nline3\n"
		let result = pipeline.convertLineEndings(input, to: .crlf)
		#expect(result == "line1\r\nline2\r\nline3\r\n")
	}

	@Test("LF to CR conversion")
	func convertLFtoCR() {
		let pipeline = FileSavePipeline()
		let input = "line1\nline2\nline3\n"
		let result = pipeline.convertLineEndings(input, to: .cr)
		#expect(result == "line1\rline2\rline3\r")
	}

	@Test("LF to LF is identity")
	func convertLFtoLF() {
		let pipeline = FileSavePipeline()
		let input = "line1\nline2\n"
		let result = pipeline.convertLineEndings(input, to: .lf)
		#expect(result == input)
	}

	// MARK: - Path Attributes

	@Test("Path attributes for save path")
	func pathAttributes() {
		let pipeline = FileSavePipeline()
		let attrs = pipeline.buildPathAttributes("/Users/me/file.rb")
		#expect(attrs.contains("attr.rev-path."))
		#expect(attrs.contains("rb"))
		#expect(attrs.contains("file"))
	}

	@Test("Path attributes for nil path")
	func pathAttributesNil() {
		let pipeline = FileSavePipeline()
		let attrs = pipeline.buildPathAttributes(nil)
		#expect(attrs.hasPrefix("attr.untitled"))
	}

	// MARK: - Writability Check

	@Test("Existing writable file is writable")
	func writableFile() throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_writable_test.txt"
		try "test".write(toFile: path, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileSavePipeline()
		let status = pipeline.checkWritability(path)
		#expect(status == .writable)
	}

	@Test("Nonexistent file in writable directory is writable")
	func newFileInWritableDir() {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_nonexistent_\(UUID()).txt"

		let pipeline = FileSavePipeline()
		let status = pipeline.checkWritability(path)
		#expect(status == .writable)
	}

	@Test("Nonexistent parent directory is noParent")
	func noParentDir() {
		let pipeline = FileSavePipeline()
		let status = pipeline.checkWritability("/nonexistent/deep/path/file.txt")
		#expect(status == .noParent)
	}

	// MARK: - Full Pipeline

	@Test("Save plain UTF-8 file")
	func savePlainUTF8() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_utf8.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileSavePipeline()
		let content = "Hello, World!\nSecond line.\n"
		let result = try await pipeline.save(
			path: path,
			content: content,
			encoding: .utf8,
		)

		#expect(result.path == path)
		#expect(result.encoding.charset == "UTF-8")

		// Verify the file was written
		let readBack = try String(contentsOfFile: path, encoding: .utf8)
		#expect(readBack == content)
	}

	@Test("Save with CRLF line endings")
	func saveWithCRLF() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_crlf.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileSavePipeline()
		let content = "line1\nline2\n"
		let encoding = DocumentEncoding(charset: "UTF-8", lineEnding: .crlf)
		let result = try await pipeline.save(
			path: path,
			content: content,
			encoding: encoding,
		)

		#expect(result.encoding.lineEnding == .crlf)

		// Verify CRLF was written
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		let rawText = try #require(String(data: data, encoding: .utf8))
		#expect(rawText == "line1\r\nline2\r\n")
	}

	@Test("Save with CR line endings")
	func saveWithCR() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_cr.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileSavePipeline()
		let content = "line1\nline2\n"
		let encoding = DocumentEncoding(charset: "UTF-8", lineEnding: .cr)
		_ = try await pipeline.save(
			path: path,
			content: content,
			encoding: encoding,
		)

		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		let rawText = try #require(String(data: data, encoding: .utf8))
		#expect(rawText == "line1\rline2\r")
	}

	@Test("Save with UTF-8 BOM")
	func saveWithBOM() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_bom.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileSavePipeline()
		let content = "Hello BOM"
		let result = try await pipeline.save(
			path: path,
			content: content,
			encoding: .utf8BOM,
		)

		#expect(result.encoding.hasBOM)

		// Verify BOM was written
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		#expect(data[0] == 0xEF)
		#expect(data[1] == 0xBB)
		#expect(data[2] == 0xBF)
	}

	@Test("Save with Latin-1 encoding")
	func saveWithLatin1() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_latin1.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileSavePipeline()
		let content = "café résumé"
		let result = try await pipeline.save(
			path: path,
			content: content,
			encoding: .latin1,
		)

		#expect(result.encoding.charset == "ISO-8859-1")

		// Verify the file was written in Latin-1
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		let readBack = try #require(String(data: data, encoding: .isoLatin1))
		#expect(readBack == content)
	}

	@Test("Save creates parent directory")
	func saveCreatesParent() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let dirPath = tmpDir + "/save_pipeline_parent_\(UUID())"
		let path = dirPath + "/file.txt"
		defer { try? FileManager.default.removeItem(atPath: dirPath) }

		let pipeline = FileSavePipeline()
		_ = try await pipeline.save(
			path: path,
			content: "test",
			encoding: .utf8,
		)

		#expect(FileManager.default.fileExists(atPath: path))
	}

	@Test("Save with text export filter")
	func saveWithTextFilter() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_textfilter.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let delegate = MockFileSaveDelegate(
			textFilterTransform: { $0.uppercased() },
		)
		let pipeline = FileSavePipeline(delegate: delegate)
		_ = try await pipeline.save(
			path: path,
			content: "hello world",
			encoding: .utf8,
		)

		let readBack = try String(contentsOfFile: path, encoding: .utf8)
		#expect(readBack == "HELLO WORLD")
	}

	@Test("Save with binary export filter")
	func saveWithBinaryFilter() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_binfilter.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let delegate = MockFileSaveDelegate(
			binaryFilterTransform: { _ in "REPLACED".data(using: .utf8)! },
		)
		let pipeline = FileSavePipeline(delegate: delegate)
		_ = try await pipeline.save(
			path: path,
			content: "original",
			encoding: .utf8,
		)

		let readBack = try String(contentsOfFile: path, encoding: .utf8)
		#expect(readBack == "REPLACED")
	}

	@Test("Save nil path with delegate providing path")
	func saveNilPathWithDelegate() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_nilpath.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let delegate = MockFileSaveDelegate(pathOverride: path)
		let pipeline = FileSavePipeline(delegate: delegate)
		let result = try await pipeline.save(
			path: nil,
			content: "test content",
			encoding: .utf8,
		)

		#expect(result.path == path)
		#expect(FileManager.default.fileExists(atPath: path))
	}

	@Test("Save nil path without delegate path cancels")
	func saveNilPathCancels() async {
		let delegate = MockFileSaveDelegate(pathOverride: nil)
		let pipeline = FileSavePipeline(delegate: delegate)

		do {
			_ = try await pipeline.save(
				path: nil,
				content: "test",
				encoding: .utf8,
			)
			Issue.record("Expected FileSaveError.cancelled")
		} catch let error as FileSaveError {
			if case .cancelled = error {} else {
				Issue.record("Expected cancelled, got \(error)")
			}
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	@Test("Save sets encoding xattr for non-UTF-8")
	func saveXattr() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_xattr.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileSavePipeline()
		_ = try await pipeline.save(
			path: path,
			content: "café",
			encoding: .latin1,
		)

		// Check the xattr was set
		let charset = StreamingFileReader.readTextEncodingXattr(path: path)
		#expect(charset == "ISO-8859-1")
	}

	@Test("Save removes encoding xattr for plain UTF-8")
	func saveRemovesXattr() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_rm_xattr.txt"
		try "test".write(toFile: path, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: path) }

		// Set an xattr first
		_ = "ISO-8859-1".withCString { cstr in
			setxattr(path, "com.apple.TextEncoding", cstr, strlen(cstr), 0, 0)
		}

		let pipeline = FileSavePipeline()
		_ = try await pipeline.save(
			path: path,
			content: "plain ASCII",
			encoding: .utf8,
		)

		// xattr should be removed
		let charset = StreamingFileReader.readTextEncodingXattr(path: path)
		#expect(charset == nil)
	}

	@Test("Save with custom attributes")
	func saveCustomAttributes() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_custom_attrs.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileSavePipeline(
			attributes: ["com.test.custom": "value123"],
		)
		let result = try await pipeline.save(
			path: path,
			content: "test",
			encoding: .utf8,
		)

		#expect(result.attributes["com.test.custom"] == "value123")

		// Verify the xattr was set
		var buffer = [UInt8](repeating: 0, count: 256)
		let size = getxattr(path, "com.test.custom", &buffer, 256, 0, 0)
		#expect(size > 0)
		let value = String(bytes: buffer.prefix(size), encoding: .utf8)
		#expect(value == "value123")
	}

	// MARK: - Default Delegate

	@Test("DefaultFileSaveDelegate returns expected defaults")
	func defaultDelegate() async {
		let delegate = DefaultFileSaveDelegate()

		let path = await delegate.selectPath(suggestedPath: "/test", content: "")
		#expect(path == "/test")

		let writable = await delegate.selectMakeWritable(path: "/test")
		#expect(writable == false)

		let parent = await delegate.selectCreateParent(path: "/test")
		#expect(parent == true)

		let auth = await delegate.obtainWriteAuthorization(for: "/test")
		#expect(auth == false)

		let charset = await delegate.selectCharset(for: "/test", currentCharset: "UTF-8")
		#expect(charset == "UTF-8")
	}

	// MARK: - Roundtrip

	@Test("Open-save roundtrip preserves content")
	func roundtrip() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_roundtrip.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let originalContent = "Hello, World!\nLine 2\nLine 3\n"

		// Save
		let savePipeline = FileSavePipeline()
		let saveResult = try await savePipeline.save(
			path: path,
			content: originalContent,
			encoding: .utf8,
		)

		// Open
		let openPipeline = FileOpenPipeline()
		let openResult = try await openPipeline.open(path: path)

		#expect(openResult.content == originalContent)
		#expect(saveResult.path == path)
	}

	@Test("Open-save roundtrip with CRLF preserves content")
	func roundtripCRLF() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_roundtrip_crlf.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let content = "line1\nline2\nline3\n"
		let encoding = DocumentEncoding(charset: "UTF-8", lineEnding: .crlf)

		// Save with CRLF
		let savePipeline = FileSavePipeline()
		_ = try await savePipeline.save(
			path: path,
			content: content,
			encoding: encoding,
		)

		// Open — should detect CRLF and harmonize to LF
		let openPipeline = FileOpenPipeline()
		let openResult = try await openPipeline.open(path: path)

		#expect(openResult.content == content) // LF internally
		#expect(openResult.lineEnding == .crlf) // But detected as CRLF
	}

	@Test("Open-save roundtrip with UTF-8 BOM")
	func roundtripBOM() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_roundtrip_bom.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let content = "BOM roundtrip test"

		// Save with BOM
		let savePipeline = FileSavePipeline()
		_ = try await savePipeline.save(
			path: path,
			content: content,
			encoding: .utf8BOM,
		)

		// Open — should detect BOM and strip it from content
		let openPipeline = FileOpenPipeline()
		let openResult = try await openPipeline.open(path: path)

		#expect(openResult.content == content)
		#expect(openResult.encoding.hasBOM)
	}

	@Test("Open-save roundtrip with Latin-1 encoding")
	func roundtripLatin1() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/save_pipeline_test_roundtrip_latin1.txt"
		defer { try? FileManager.default.removeItem(atPath: path) }

		let content = "café résumé naïve"

		// Save with Latin-1
		let savePipeline = FileSavePipeline()
		_ = try await savePipeline.save(
			path: path,
			content: content,
			encoding: .latin1,
		)

		// Open — xattr should tell us it's Latin-1
		let openPipeline = FileOpenPipeline()
		let openResult = try await openPipeline.open(path: path)

		#expect(openResult.content == content)
		#expect(openResult.encoding.charset == "ISO-8859-1")
	}
}
