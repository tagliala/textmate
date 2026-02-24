import Foundation
import Testing
@testable import TMDocumentManager

// MARK: - Test Helpers

/// A configurable mock delegate for testing the open pipeline.
struct MockFileOpenDelegate: FileOpenDelegate {
	var authorizeRead: Bool = false
	var charsetOverride: String?
	var binaryFilterTransform: (@Sendable (Data) -> Data)?
	var textFilterTransform: (@Sendable (String) -> String)?

	func obtainReadAuthorization(for _: String) async -> Bool {
		authorizeRead
	}

	func selectCharset(
		for _: String,
		suggestedCharset: String,
	) async -> String? {
		charsetOverride ?? suggestedCharset
	}

	func runBinaryImportFilters(
		path _: String,
		data: Data,
		pathAttributes _: String,
	) async throws -> Data {
		binaryFilterTransform?(data) ?? data
	}

	func runTextImportFilters(
		path _: String,
		content: String,
		pathAttributes _: String,
	) async throws -> String {
		textFilterTransform?(content) ?? content
	}
}

@Suite("FileOpenPipeline")
struct FileOpenPipelineTests {
	// MARK: - Path Attributes

	@Test("Path attributes for normal file path")
	func pathAttributesNormal() {
		let pipeline = FileOpenPipeline()
		let attrs = pipeline.buildPathAttributes("/Users/me/foo.html.erb")
		#expect(attrs.hasPrefix("attr.rev-path."))
		#expect(attrs.contains("erb"))
		#expect(attrs.contains("html"))
		#expect(attrs.contains("foo"))
		#expect(attrs.contains("me"))
		#expect(attrs.contains("Users"))
		#expect(attrs.contains("attr.os-version."))
	}

	@Test("Path attributes for nil path")
	func pathAttributesNil() {
		let pipeline = FileOpenPipeline()
		let attrs = pipeline.buildPathAttributes(nil)
		#expect(attrs.hasPrefix("attr.untitled"))
		#expect(attrs.contains("attr.os-version."))
	}

	@Test("Path attributes replaces spaces with underscores")
	func pathAttributesSpaces() {
		let pipeline = FileOpenPipeline()
		let attrs = pipeline.buildPathAttributes("/Users/me/My Documents/file.txt")
		#expect(attrs.contains("My_Documents"))
	}

	// MARK: - Line Ending Harmonization

	@Test("LF content unchanged")
	func harmonizeLF() {
		let pipeline = FileOpenPipeline()
		let input = "line1\nline2\nline3\n"
		let result = pipeline.harmonizeLineEndings(input, from: .lf)
		#expect(result == input)
	}

	@Test("CRLF converted to LF")
	func harmonizeCRLF() {
		let pipeline = FileOpenPipeline()
		let input = "line1\r\nline2\r\nline3\r\n"
		let result = pipeline.harmonizeLineEndings(input, from: .crlf)
		#expect(result == "line1\nline2\nline3\n")
	}

	@Test("CR converted to LF")
	func harmonizeCR() {
		let pipeline = FileOpenPipeline()
		let input = "line1\rline2\rline3\r"
		let result = pipeline.harmonizeLineEndings(input, from: .cr)
		#expect(result == "line1\nline2\nline3\n")
	}

	// MARK: - Full Pipeline

	@Test("Open plain UTF-8 file")
	func openPlainUTF8() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/open_pipeline_test_utf8.txt"
		let text = "Hello, World!\nSecond line.\n"
		try text.write(toFile: path, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileOpenPipeline()
		let result = try await pipeline.open(path: path)

		#expect(result.content == text)
		#expect(result.lineEnding == .lf)
		#expect(result.rawByteCount == text.utf8.count)
	}

	@Test("Open file with CRLF line endings")
	func openCRLFFile() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/open_pipeline_test_crlf.txt"
		let rawText = "line1\r\nline2\r\nline3\r\n"
		try rawText.data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileOpenPipeline()
		let result = try await pipeline.open(path: path)

		// Content should be harmonized to LF
		#expect(result.content == "line1\nline2\nline3\n")
		// But the detected line ending should be CRLF
		#expect(result.lineEnding == .crlf)
		#expect(result.encoding.lineEnding == .crlf)
	}

	@Test("Open file with CR line endings")
	func openCRFile() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/open_pipeline_test_cr.txt"
		let rawText = "line1\rline2\rline3\r"
		try rawText.data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileOpenPipeline()
		let result = try await pipeline.open(path: path)

		#expect(result.content == "line1\nline2\nline3\n")
		#expect(result.lineEnding == .cr)
	}

	@Test("Open file with UTF-8 BOM")
	func openUTF8BOM() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/open_pipeline_test_bom.txt"
		let text = "Hello BOM"
		let data = Data([0xEF, 0xBB, 0xBF]) + text.data(using: .utf8)!
		try data.write(to: URL(fileURLWithPath: path))
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileOpenPipeline()
		let result = try await pipeline.open(path: path)

		#expect(result.content == text)
		#expect(result.encoding.hasBOM)
	}

	@Test("Open with text import filter")
	func openWithTextFilter() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/open_pipeline_test_filter.txt"
		try "hello world".write(toFile: path, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: path) }

		let delegate = MockFileOpenDelegate(
			textFilterTransform: { $0.uppercased() },
		)
		let pipeline = FileOpenPipeline(delegate: delegate)
		let result = try await pipeline.open(path: path)

		#expect(result.content == "HELLO WORLD")
	}

	@Test("Open nonexistent file throws")
	func openNonexistent() async {
		let pipeline = FileOpenPipeline()
		do {
			_ = try await pipeline.open(path: "/nonexistent/path.txt")
			Issue.record("Expected error")
		} catch {
			// Expected
		}
	}

	@Test("Open produces path attributes")
	func openProducesPathAttrs() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/open_pipeline_test_attrs.txt"
		try "test".write(toFile: path, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileOpenPipeline()
		let result = try await pipeline.open(path: path)

		#expect(result.pathAttributes.contains("attr.rev-path."))
		#expect(result.pathAttributes.contains("txt"))
	}

	@Test("Open empty file")
	func openEmptyFile() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/open_pipeline_test_empty.txt"
		try Data().write(to: URL(fileURLWithPath: path))
		defer { try? FileManager.default.removeItem(atPath: path) }

		let pipeline = FileOpenPipeline()
		let result = try await pipeline.open(path: path)

		#expect(result.content.isEmpty)
		#expect(result.rawByteCount == 0)
	}

	@Test("Open with binary import filter")
	func openWithBinaryFilter() async throws {
		let tmpDir = FileManager.default.temporaryDirectory.path
		let path = tmpDir + "/open_pipeline_test_binfilter.txt"
		let helloData = try #require("hello".data(using: .utf8))
		try helloData.write(to: URL(fileURLWithPath: path))
		defer { try? FileManager.default.removeItem(atPath: path) }

		let delegate = MockFileOpenDelegate(
			binaryFilterTransform: { _ in "REPLACED".data(using: .utf8)! },
		)
		let pipeline = FileOpenPipeline(delegate: delegate)
		let result = try await pipeline.open(path: path)

		#expect(result.content == "REPLACED")
	}

	// MARK: - Default Delegate

	@Test("DefaultFileOpenDelegate returns expected defaults")
	func defaultDelegate() async {
		let delegate = DefaultFileOpenDelegate()

		let auth = await delegate.obtainReadAuthorization(for: "/test")
		#expect(auth == false)

		let charset = await delegate.selectCharset(for: "/test", suggestedCharset: "UTF-8")
		#expect(charset == "UTF-8")

		let data = Data([1, 2, 3])
		let filtered = try? await delegate.runBinaryImportFilters(
			path: "/test",
			data: data,
			pathAttributes: "",
		)
		#expect(filtered == data)

		let text = "hello"
		let filteredText = try? await delegate.runTextImportFilters(
			path: "/test",
			content: text,
			pathAttributes: "",
		)
		#expect(filteredText == text)
	}
}
