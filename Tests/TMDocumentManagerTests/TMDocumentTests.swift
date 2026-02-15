import Foundation
import Testing
@testable import TMDocumentManager

// MARK: - TMDocument Tests

@Suite("TMDocument - Core Document Model")
@MainActor
struct TMDocumentTests {
	// MARK: - Identity

	@Test("Document has stable UUID identity")
	func documentIdentity() {
		let id = UUID()
		let doc = TMDocument(id: id, path: "/test/file.txt")
		#expect(doc.id == id)
		#expect(doc.path == "/test/file.txt")
	}

	@Test("Two documents with same UUID are equal")
	func documentEquality() {
		let id = UUID()
		let doc1 = TMDocument(id: id)
		let doc2 = TMDocument(id: id)
		#expect(doc1 == doc2)
	}

	@Test("Documents with different UUIDs are not equal")
	func documentInequality() {
		let doc1 = TMDocument()
		let doc2 = TMDocument()
		#expect(doc1 != doc2)
	}

	@Test("Document is hashable via UUID")
	func documentHashing() {
		let id = UUID()
		let doc = TMDocument(id: id)
		var set: Set<TMDocument> = []
		set.insert(doc)
		#expect(set.contains(doc))
	}

	// MARK: - Initial State

	@Test("New document starts unloaded")
	func initialState() {
		let doc = TMDocument()
		#expect(doc.state == .unloaded)
		#expect(!doc.isOpen)
		#expect(!doc.isModified)
		#expect(doc.content == nil)
		#expect(doc.encoding == .utf8)
	}

	@Test("Untitled document has nil path")
	func untitledDocument() {
		let doc = TMDocument()
		#expect(doc.path == nil)
		#expect(!doc.isOnDisk)
	}

	// MARK: - Display Name

	@Test("Display name from path shows filename")
	func displayNameFromPath() {
		let doc = TMDocument(path: "/Users/test/hello.swift")
		#expect(doc.displayName == "hello.swift")
	}

	@Test("Display name for untitled document")
	func displayNameUntitled() {
		let doc = TMDocument()
		#expect(doc.displayName == "Untitled")
	}

	@Test("Custom name overrides path-based name")
	func customDisplayName() {
		let doc = TMDocument(path: "/test/file.txt")
		doc.customName = "My Buffer"
		#expect(doc.displayName == "My Buffer")
	}

	@Test("Virtual path provides display name when no path")
	func virtualPathDisplayName() {
		let doc = TMDocument()
		doc.virtualPath = "untitled.rb"
		#expect(doc.displayName == "untitled.rb")
	}

	// MARK: - Open / Close

	@Test("Open increments open count")
	func openDocument() {
		let doc = TMDocument()
		#expect(!doc.isOpen)
		doc.open()
		#expect(doc.isOpen)
	}

	@Test("Multiple opens require multiple closes")
	func multipleOpenClose() {
		let doc = TMDocument()
		doc.open()
		doc.open()
		#expect(doc.isOpen)
		doc.close()
		#expect(doc.isOpen) // Still open — one reference left
		doc.close()
		#expect(!doc.isOpen)
	}

	@Test("Close without open is a no-op")
	func closeWithoutOpen() {
		let doc = TMDocument()
		doc.close() // Should not crash
		#expect(!doc.isOpen)
	}

	// MARK: - Modification

	@Test("markModified increments revision")
	func markModified() {
		let doc = TMDocument()
		#expect(!doc.isModified)
		doc.markModified()
		#expect(doc.isModified)
	}

	@Test("markSaved clears modified flag")
	func markSaved() {
		let doc = TMDocument()
		doc.markModified()
		#expect(doc.isModified)
		doc.markSaved()
		#expect(!doc.isModified)
	}

	@Test("setContent increments revision by default")
	func setContentIncrementsRevision() {
		let doc = TMDocument()
		doc.setContent("Hello")
		#expect(doc.isModified)
		#expect(doc.content == "Hello")
	}

	@Test("setContent can preserve revision")
	func setContentPreservesRevision() {
		let doc = TMDocument()
		doc.setContent("Hello", preserveRevision: true)
		#expect(!doc.isModified)
		#expect(doc.content == "Hello")
	}

	// MARK: - Disposable

	@Test("Untitled, empty, unmodified document is disposable")
	func disposableDocument() {
		let doc = TMDocument()
		doc.setContent("", preserveRevision: true)
		#expect(doc.isDisposable)
	}

	@Test("Document with path is not disposable")
	func notDisposableWithPath() {
		let doc = TMDocument(path: "/tmp/test.txt")
		#expect(!doc.isDisposable)
	}

	@Test("Modified document is not disposable")
	func notDisposableWhenModified() {
		let doc = TMDocument()
		doc.setContent("content")
		#expect(!doc.isDisposable)
	}

	// MARK: - Path Updates

	@Test("setPath updates document path")
	func setPath() {
		let doc = TMDocument()
		doc.setPath("/new/path.txt")
		#expect(doc.path == "/new/path.txt")
	}

	// MARK: - Change Observation

	@Test("Change callbacks fire on modification")
	func changeCallbacks() {
		let doc = TMDocument()
		var callbackCount = 0
		doc.addChangeCallback { callbackCount += 1 }
		doc.markModified()
		#expect(callbackCount == 1)
		doc.markModified()
		#expect(callbackCount == 2)
	}

	@Test("Change callback removal works")
	func removeChangeCallback() {
		let doc = TMDocument()
		var callbackCount = 0
		let id = doc.addChangeCallback { callbackCount += 1 }
		doc.markModified()
		#expect(callbackCount == 1)
		doc.removeChangeCallback(id: id)
		doc.markModified()
		#expect(callbackCount == 1) // Not incremented
	}

	// MARK: - File Type

	@Test("File type can be set at creation")
	func fileTypeAtCreation() {
		let doc = TMDocument(fileType: "source.swift")
		#expect(doc.fileType == "source.swift")
	}

	// MARK: - Editor Metadata

	@Test("Editor metadata defaults")
	func editorMetadataDefaults() {
		let doc = TMDocument()
		#expect(doc.selection == nil)
		#expect(doc.visibleIndex == 0)
		#expect(doc.tabSize == 4)
		#expect(!doc.softTabs)
		#expect(doc.foldedRanges.isEmpty)
		#expect(doc.bookmarks.isEmpty)
	}

	@Test("Editor metadata can be set")
	func editorMetadataSet() {
		let doc = TMDocument()
		doc.selection = "1:0-1:10"
		doc.visibleIndex = 42
		doc.tabSize = 2
		doc.softTabs = true
		doc.foldedRanges = ["1:0-3:0"]
		doc.bookmarks = [5, 10, 20]

		#expect(doc.selection == "1:0-1:10")
		#expect(doc.visibleIndex == 42)
		#expect(doc.tabSize == 2)
		#expect(doc.softTabs)
		#expect(doc.foldedRanges == ["1:0-3:0"])
		#expect(doc.bookmarks == [5, 10, 20])
	}

	// MARK: - Backup Flags

	@Test("Backup flags track unsaved state")
	func backupFlags() {
		let doc = TMDocument()
		#expect(!doc.needsBackup)
		doc.markModified()
		#expect(doc.needsBackup)
		doc.markSaved()
		#expect(!doc.needsBackup)
	}

	// MARK: - Viewing Mode

	@Test("Viewing mode flag")
	func viewingMode() {
		let doc = TMDocument()
		#expect(!doc.isViewingMode)
		doc.isViewingMode = true
		#expect(doc.isViewingMode)
	}
}

// MARK: - Line Ending Tests

@Suite("LineEnding Detection")
struct LineEndingTests {
	@Test("Detects LF line endings")
	func detectLF() {
		let text = "line1\nline2\nline3"
		#expect(LineEnding.detect(in: text) == .lf)
	}

	@Test("Detects CR line endings")
	func detectCR() {
		let text = "line1\rline2\rline3"
		#expect(LineEnding.detect(in: text) == .cr)
	}

	@Test("Detects CRLF line endings")
	func detectCRLF() {
		let text = "line1\r\nline2\r\nline3"
		#expect(LineEnding.detect(in: text) == .crlf)
	}

	@Test("Empty text defaults to LF")
	func detectEmpty() {
		#expect(LineEnding.detect(in: "") == .lf)
	}

	@Test("Single line defaults to LF")
	func detectSingleLine() {
		#expect(LineEnding.detect(in: "no newlines") == .lf)
	}

	@Test("Mixed line endings — dominant wins")
	func detectMixed() {
		let text = "line1\nline2\nline3\r\nline4" // 2 LF, 1 CRLF
		#expect(LineEnding.detect(in: text) == .lf)
	}

	@Test("Display names are correct")
	func displayNames() {
		#expect(LineEnding.lf.displayName == "LF")
		#expect(LineEnding.cr.displayName == "CR")
		#expect(LineEnding.crlf.displayName == "CR/LF")
	}
}

// MARK: - Document Encoding Tests

@Suite("DocumentEncoding")
struct DocumentEncodingTests {
	@Test("UTF-8 default encoding")
	func utf8Default() {
		let enc = DocumentEncoding.utf8
		#expect(enc.charset == "UTF-8")
		#expect(enc.lineEnding == .lf)
		#expect(!enc.hasBOM)
	}

	@Test("String encoding conversion round-trip")
	func encodingConversion() {
		let enc = DocumentEncoding.utf8
		#expect(enc.stringEncoding == .utf8)
	}

	@Test("Latin-1 encoding")
	func latin1() {
		let enc = DocumentEncoding.latin1
		#expect(enc.charset == "ISO-8859-1")
		#expect(enc.stringEncoding == .isoLatin1)
	}

	@Test("From Swift encoding")
	func fromSwiftEncoding() {
		let enc = DocumentEncoding.from(encoding: .utf8, lineEnding: .crlf)
		#expect(enc.charset == "UTF-8")
		#expect(enc.lineEnding == .crlf)
	}

	@Test("Encoding equality")
	func equality() {
		#expect(DocumentEncoding.utf8 == DocumentEncoding(charset: "UTF-8"))
		#expect(DocumentEncoding.utf8 != DocumentEncoding.utf8BOM)
	}

	@Test("Presets exist with correct values")
	func presets() {
		#expect(DocumentEncoding.utf8BOM.hasBOM)
		#expect(DocumentEncoding.utf16BE.hasBOM)
		#expect(DocumentEncoding.utf16LE.hasBOM)
	}
}

// MARK: - Data Decoding Tests

@Suite("TMDocument - Data Decoding")
struct DataDecodingTests {
	@Test("Decodes plain UTF-8 data")
	func decodePlainUTF8() throws {
		let text = "Hello, world!"
		let data = try #require(text.data(using: .utf8))
		let (decoded, encoding) = TMDocument.decodeData(data)
		#expect(decoded == text)
		#expect(encoding.charset == "UTF-8")
		#expect(!encoding.hasBOM)
	}

	@Test("Detects UTF-8 BOM")
	func detectUTF8BOM() throws {
		let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
		let text = "Hello"
		var data = Data(bom)
		try data.append(#require(text.data(using: .utf8)))
		let (decoded, encoding) = TMDocument.decodeData(data)
		#expect(decoded == text)
		#expect(encoding.charset == "UTF-8")
		#expect(encoding.hasBOM)
	}

	@Test("Decodes empty data")
	func decodeEmptyData() {
		let (decoded, _) = TMDocument.decodeData(Data())
		#expect(decoded == "")
	}
}

// MARK: - 3-Way Merge Tests

@Suite("TMDocument - 3-Way Merge")
struct ThreeWayMergeTests {
	@Test("No changes returns theirs")
	func noChanges() {
		let result = TMDocument.threeWayMerge(
			original: "line1\nline2\nline3",
			mine: "line1\nline2\nline3",
			theirs: "line1\nline2\nline3",
		)
		#expect(result == "line1\nline2\nline3")
	}

	@Test("Only their changes are accepted")
	func onlyTheirChanges() {
		let result = TMDocument.threeWayMerge(
			original: "line1\nline2\nline3",
			mine: "line1\nline2\nline3",
			theirs: "line1\nMODIFIED\nline3",
		)
		#expect(result == "line1\nMODIFIED\nline3")
	}

	@Test("Only my changes are kept")
	func onlyMyChanges() {
		let result = TMDocument.threeWayMerge(
			original: "line1\nline2\nline3",
			mine: "line1\nMY CHANGE\nline3",
			theirs: "line1\nline2\nline3",
		)
		#expect(result == "line1\nMY CHANGE\nline3")
	}

	@Test("Both changed different lines — both kept")
	func bothChangedDifferentLines() {
		let result = TMDocument.threeWayMerge(
			original: "line1\nline2\nline3",
			mine: "MY LINE\nline2\nline3",
			theirs: "line1\nline2\nTHEIR LINE",
		)
		#expect(result == "MY LINE\nline2\nTHEIR LINE")
	}

	@Test("Conflict — mine wins")
	func conflictMineWins() {
		let result = TMDocument.threeWayMerge(
			original: "line1\nline2\nline3",
			mine: "line1\nMY VERSION\nline3",
			theirs: "line1\nTHEIR VERSION\nline3",
		)
		#expect(result == "line1\nMY VERSION\nline3")
	}
}

// MARK: - Document IO Error Tests

@Suite("DocumentIOError")
struct DocumentIOErrorTests {
	@Test("Error descriptions are meaningful")
	func errorDescriptions() throws {
		#expect(DocumentIOError.noPath.errorDescription != nil)
		#expect(DocumentIOError.noContent.errorDescription != nil)
		#expect(try #require(DocumentIOError.encodingFailed("UTF-8").errorDescription?.contains("UTF-8")))
		#expect(try #require(DocumentIOError.fileNotFound("/tmp/x").errorDescription?.contains("/tmp/x")))
		#expect(try #require(DocumentIOError.permissionDenied("/tmp/x").errorDescription?.contains("Permission")))
		#expect(try #require(DocumentIOError.externallyModified("/tmp/x").errorDescription?.contains("externally")))
		#expect(try #require(DocumentIOError.mergeFailed.errorDescription?.contains("merge")))
	}
}

// MARK: - Document State Tests

@Suite("DocumentState")
struct DocumentStateTests {
	@Test("Document state equality")
	func stateEquality() {
		#expect(DocumentState.unloaded == DocumentState.unloaded)
		#expect(DocumentState.loading == DocumentState.loading)
		#expect(DocumentState.loaded == DocumentState.loaded)
		#expect(DocumentState.saving == DocumentState.saving)
		#expect(DocumentState.error("test") == DocumentState.error("test"))
		#expect(DocumentState.error("a") != DocumentState.error("b"))
		#expect(DocumentState.unloaded != DocumentState.loaded)
	}
}
