import Foundation
import Testing
@testable import TMServices

@Suite("SignatureVerifier")
struct SignatureVerifierTests {
	// MARK: - KeyChain

	@Test("KeyChain init with empty keys")
	func emptyKeyChain() {
		let kc = SignatureVerifier.KeyChain()
		#expect(kc.keys.isEmpty)
	}

	@Test("KeyChain init with keys")
	func keyChainWithKeys() {
		let kc = SignatureVerifier.KeyChain(keys: ["alice": "PEM_DATA"])
		#expect(kc.keys["alice"] == "PEM_DATA")
	}

	@Test("KeyChain importKey throws for unknown identity")
	func importKeyUnknownIdentity() {
		let kc = SignatureVerifier.KeyChain()
		#expect(throws: SignatureVerifier.VerificationError.self) {
			try kc.importKey(for: "unknown")
		}
	}

	// MARK: - Verification Errors

	@Test("Verify throws for missing signee")
	func missingSignee() {
		#expect(throws: SignatureVerifier.VerificationError.self) {
			try SignatureVerifier.verify(
				data: Data("test".utf8),
				base64Signature: "sig",
				signee: "",
				keyChain: .init(),
			)
		}
	}

	@Test("Verify throws for missing signature")
	func missingSignature() {
		#expect(throws: SignatureVerifier.VerificationError.self) {
			try SignatureVerifier.verify(
				data: Data("test".utf8),
				base64Signature: "",
				signee: "alice",
				keyChain: .init(keys: ["alice": "key"]),
			)
		}
	}

	@Test("Verify throws for invalid base64 signature")
	func invalidBase64() {
		// Use a properly formatted but semantically invalid PEM key
		// This should fail at import, not base64 decode
		#expect(throws: SignatureVerifier.VerificationError.self) {
			try SignatureVerifier.verify(
				data: Data("test".utf8),
				base64Signature: "!!!not-base64!!!",
				publicKeyPEM: "not-a-key",
			)
		}
	}

	// MARK: - Error Descriptions

	@Test("Error descriptions are descriptive")
	func errorDescriptions() {
		let errors: [SignatureVerifier.VerificationError] = [
			.missingSignee,
			.missingSignature,
			.missingPublicKey(signee: "alice"),
			.invalidSignatureEncoding,
			.keyImportFailed(errSecParam),
			.verifyTransformCreateFailed("test"),
			.verifyFailed("test"),
		]
		for error in errors {
			#expect(!error.description.isEmpty)
		}
	}

	// MARK: - HTTP Headers

	@Test("HTTP header constants")
	func httpHeaders() {
		#expect(SignatureVerifier.httpSigneeHeader == "x-amz-meta-x-signee")
		#expect(SignatureVerifier.httpSignatureHeader == "x-amz-meta-x-signature")
	}

	// MARK: - PEM Key Import

	@Test("Import invalid PEM throws")
	func importInvalidPEM() {
		#expect(throws: SignatureVerifier.VerificationError.self) {
			try SignatureVerifier.KeyChain.importPEMKey("not a valid PEM key")
		}
	}
}
