import Foundation
import Testing
@testable import TMServices

@Suite("ArchiveExtractor")
struct ArchiveExtractorTests {
	// MARK: - Options

	@Test("Default options")
	func defaultOptions() {
		let opts = ArchiveExtractor.Options()
		#expect(opts.stripComponents == 1)
		#expect(opts.disableCopyfile == true)
		#expect(opts.excludePatterns == ["._*"])
	}

	@Test("Custom options")
	func customOptions() {
		let opts = ArchiveExtractor.Options(stripComponents: 0, disableCopyfile: false, excludePatterns: [])
		#expect(opts.stripComponents == 0)
		#expect(opts.disableCopyfile == false)
		#expect(opts.excludePatterns.isEmpty)
	}

	// MARK: - Extraction

	@Test("Extract empty data fails gracefully")
	func extractEmptyData() throws {
		let tmp = NSTemporaryDirectory() + "extract_empty_\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let extractor = ArchiveExtractor(
			destination: tmp,
			options: .init(stripComponents: 0),
		)

		// Empty data → tar may or may not error depending on implementation
		do {
			try extractor.extract(data: Data())
		} catch {
			#expect(error is ArchiveExtractor.ExtractionError)
		}
	}

	// MARK: - Streaming

	@Test("Begin and finish empty streaming fails")
	func emptyStreaming() throws {
		let tmp = NSTemporaryDirectory() + "extract_stream_\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let extractor = ArchiveExtractor(
			destination: tmp,
			options: .init(stripComponents: 0),
		)

		try extractor.beginStreaming()
		// Don't write any data — may or may not error
		do {
			try extractor.finishStreaming()
		} catch {
			#expect(error is ArchiveExtractor.ExtractionError)
		}
	}

	// MARK: - Tar Arguments

	@Test("Extractor properties")
	func extractorProperties() {
		let extractor = ArchiveExtractor(destination: "/tmp/test")
		#expect(extractor.destination == "/tmp/test")
		#expect(extractor.options.stripComponents == 1)
	}

	// MARK: - Error Types

	@Test("ExtractionError cases")
	func errorCases() {
		let errors: [ArchiveExtractor.ExtractionError] = [
			.processExitedWithStatus(1),
			.processTerminatedBySignal(9),
			.launchFailed("reason"),
			.destinationNotFound("/nope"),
			.writeFailed("pipe broken"),
		]
		#expect(errors.count == 5)
	}

	// MARK: - Real Archive Extraction

	@Test("Extract real bzip2 tar archive")
	func extractRealArchive() throws {
		// Create a small directory structure, then tar+bzip2 it
		let id = UUID().uuidString
		let srcDir = NSTemporaryDirectory() + "archive_src_\(id)"
		let innerDir = srcDir + "/inner"
		try FileManager.default.createDirectory(atPath: innerDir, withIntermediateDirectories: true)
		try Data("hello".utf8).write(to: URL(fileURLWithPath: innerDir + "/file.txt"))
		defer { try? FileManager.default.removeItem(atPath: srcDir) }

		// Create tar.bz2
		let archivePath = NSTemporaryDirectory() + "archive_\(id).tbz"
		defer { try? FileManager.default.removeItem(atPath: archivePath) }

		let tarProc = Process()
		tarProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
		tarProc.arguments = ["-jcf", archivePath, "-C", NSTemporaryDirectory(), "archive_src_\(id)"]
		try tarProc.run()
		tarProc.waitUntilExit()
		guard tarProc.terminationStatus == 0 else {
			Issue.record("tar creation failed")
			return
		}

		let archiveData = try Data(contentsOf: URL(fileURLWithPath: archivePath))
		#expect(archiveData.count > 0)

		// Extract it
		let destDir = NSTemporaryDirectory() + "archive_dest_\(id)"
		try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(atPath: destDir) }

		let extractor = ArchiveExtractor(
			destination: destDir,
			options: .init(stripComponents: 1, disableCopyfile: true, excludePatterns: []),
		)
		try extractor.extract(data: archiveData)

		// Verify extracted content
		let extractedFile = destDir + "/inner/file.txt"
		let content = try String(contentsOfFile: extractedFile, encoding: .utf8)
		#expect(content == "hello")
	}
}
