import Foundation
import Security

// MARK: - Signature Verifier

/// Cryptographic signature verification using Security.framework.
///
/// Port of `Frameworks/network/src/filter_check_signature.cc` and
/// `Frameworks/SoftwareUpdate/src/OakDownloadManager.mm` signature logic.
///
/// Supports RSA/DSA public key verification of data using PEM-encoded
/// public keys and base64-encoded signatures.
public enum SignatureVerifier {
	// MARK: - Errors

	/// Errors that can occur during signature verification.
	public enum VerificationError: Error, Sendable, CustomStringConvertible {
		case missingSignee
		case missingSignature
		case missingPublicKey(signee: String)
		case invalidSignatureEncoding
		case keyImportFailed(OSStatus)
		case verifyTransformCreateFailed(String)
		case verifyFailed(String)

		public var description: String {
			switch self {
			case .missingSignee: "Missing signee"
			case .missingSignature: "Missing signature"
			case let .missingPublicKey(signee): "Unknown signee: '\(signee)'"
			case .invalidSignatureEncoding: "Unable to decode signature"
			case let .keyImportFailed(status): "SecItemImport failed: \(status)"
			case let .verifyTransformCreateFailed(msg): "Error creating verify transform: \(msg)"
			case let .verifyFailed(msg): "Verification failed: \(msg)"
			}
		}
	}

	// MARK: - Key Chain

	/// A collection of named public keys for verification.
	///
	/// Port of C++ `key_chain_t`.
	public struct KeyChain: Sendable {
		/// Identity → PEM public key data mapping.
		public var keys: [String: String]

		public init(keys: [String: String] = [:]) {
			self.keys = keys
		}

		/// Import a PEM-encoded public key string and return a `SecKey`.
		public func importKey(for identity: String) throws -> SecKey {
			guard let pemString = keys[identity] else {
				throw VerificationError.missingPublicKey(signee: identity)
			}
			return try Self.importPEMKey(pemString)
		}

		/// Import a PEM-encoded public key string.
		public static func importPEMKey(_ pemString: String) throws -> SecKey {
			guard let pemData = pemString.data(using: .utf8) as CFData? else {
				throw VerificationError.keyImportFailed(errSecParam)
			}

			var format = SecExternalFormat.formatPEMSequence
			var type = SecExternalItemType.itemTypePublicKey
			var items: CFArray?

			let params = SecItemImportExportKeyParameters()

			let status = SecItemImport(
				pemData,
				nil,
				&format,
				&type,
				[],
				UnsafeMutablePointer(mutating: withUnsafePointer(to: params) { $0 }),
				nil,
				&items,
			)

			guard status == errSecSuccess,
			      let array = items,
			      CFArrayGetCount(array) > 0
			else {
				throw VerificationError.keyImportFailed(status)
			}

			// CFArray contains SecKey objects
			return Unmanaged<SecKey>.fromOpaque(
				CFArrayGetValueAtIndex(array, 0),
			).takeUnretainedValue()
		}
	}

	// MARK: - Verification

	/// Verify that `data` has a valid signature.
	///
	/// - Parameters:
	///   - data: The data that was signed.
	///   - base64Signature: The base64-encoded signature.
	///   - publicKeyPEM: The PEM-encoded public key.
	/// - Returns: `true` if the signature is valid.
	/// - Throws: `VerificationError` on failure.
	@discardableResult
	public static func verify(
		data: Data,
		base64Signature: String,
		publicKeyPEM: String,
	) throws -> Bool {
		guard let signatureData = Data(base64Encoded: base64Signature) else {
			throw VerificationError.invalidSignatureEncoding
		}

		let publicKey = try KeyChain.importPEMKey(publicKeyPEM)
		return try verify(data: data, signature: signatureData, publicKey: publicKey)
	}

	/// Verify using a key chain lookup.
	///
	/// - Parameters:
	///   - data: The data that was signed.
	///   - base64Signature: The base64-encoded signature.
	///   - signee: The signee identity for key lookup.
	///   - keyChain: The key chain containing public keys.
	/// - Returns: `true` if the signature is valid.
	@discardableResult
	public static func verify(
		data: Data,
		base64Signature: String,
		signee: String,
		keyChain: KeyChain,
	) throws -> Bool {
		guard !signee.isEmpty else { throw VerificationError.missingSignee }
		guard !base64Signature.isEmpty else { throw VerificationError.missingSignature }

		guard let signatureData = Data(base64Encoded: base64Signature) else {
			throw VerificationError.invalidSignatureEncoding
		}

		let publicKey = try keyChain.importKey(for: signee)
		return try verify(data: data, signature: signatureData, publicKey: publicKey)
	}

	/// Low-level verification using `SecVerifyTransformCreate`.
	///
	/// - Parameters:
	///   - data: The data that was signed.
	///   - signature: The raw signature bytes.
	///   - publicKey: The `SecKey` public key.
	/// - Returns: `true` if the signature is valid.
	public static func verify(
		data: Data,
		signature: Data,
		publicKey: SecKey,
	) throws -> Bool {
		var error: Unmanaged<CFError>?

		guard let verifier = SecVerifyTransformCreate(publicKey, signature as CFData, &error) else {
			let errMsg = error.map { String(describing: $0.takeRetainedValue()) } ?? "Unknown error"
			throw VerificationError.verifyTransformCreateFailed(errMsg)
		}

		guard SecTransformSetAttribute(
			verifier,
			kSecTransformInputAttributeName,
			data as CFData,
			&error,
		) else {
			let errMsg = error.map { String(describing: $0.takeRetainedValue()) } ?? "Unknown error"
			throw VerificationError.verifyFailed(errMsg)
		}

		let result = SecTransformExecute(verifier, &error)
		return (result as? Bool) == true
	}

	// MARK: - HTTP Header Constants

	/// The HTTP header name for the signee identity.
	/// Matches C++ `kHTTPSigneeHeader`.
	public static let httpSigneeHeader = "x-amz-meta-x-signee"

	/// The HTTP header name for the signature.
	/// Matches C++ `kHTTPSignatureHeader`.
	public static let httpSignatureHeader = "x-amz-meta-x-signature"
}
