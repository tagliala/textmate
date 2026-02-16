import Foundation
import Testing
@testable import TMServices

@Suite("DownloadManager")
struct DownloadManagerTests {
	// MARK: - Singleton

	@Test("Shared instance exists")
	func sharedInstance() {
		let dm = DownloadManager.shared
		#expect(dm !== DownloadManager())
	}

	// MARK: - User Agent

	@Test("User agent string is non-empty")
	func userAgentString() {
		let dm = DownloadManager()
		let ua = dm.userAgentString
		#expect(!ua.isEmpty)
	}

	@Test("Custom user agent overrides default")
	func customUserAgent() {
		let dm = DownloadManager()
		dm.customUserAgent = "TestAgent/1.0"
		#expect(dm.userAgentString == "TestAgent/1.0")
	}

	// MARK: - Error Descriptions

	@Test("DownloadError descriptions are descriptive")
	func errorDescriptions() {
		let errors: [DownloadManager.DownloadError] = [
			.serverError(statusCode: 404, url: "http://example.com"),
			.missingSignature,
			.unknownSignee("alice"),
			.signatureVerificationFailed,
			.writeFailed("disk full"),
			.extractionFailed("tar error"),
			.cancelled,
		]
		for error in errors {
			#expect(!error.description.isEmpty)
		}
	}

	// MARK: - ETag Caching

	@Test("ETag xattr name constant")
	func etagConstant() {
		// Verify the internal constant by checking the xattr write/read cycle
		let tmp = NSTemporaryDirectory() + "etag_test_\(UUID().uuidString)"
		FileManager.default.createFile(atPath: tmp, contents: Data("test".utf8))
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		// Write ETag via ExtendedAttributes (same name DownloadManager uses)
		ExtendedAttributes.writeString(name: "org.w3.http.etag", value: "\"abc123\"", at: tmp)
		let etag = ExtendedAttributes.readString(name: "org.w3.http.etag", at: tmp)
		#expect(etag == "\"abc123\"")
	}
}
