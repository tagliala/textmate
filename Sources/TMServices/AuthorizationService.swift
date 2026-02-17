#if canImport(AppKit)
import AppKit
import os
import Security

// MARK: - Constants

/// Constants for the privileged helper tool.
public enum AuthorizationConstants: Sendable {
	/// The LaunchDaemon job label.
	public static let jobName = "com.macromates.auth_server"

	/// Path to the installed privileged helper tool.
	public static let toolPath = "/Library/PrivilegedHelperTools/com.macromates.auth_server"

	/// Unix socket path for communication with the auth server.
	public static let socketPath = "/var/run/com.macromates.auth_server.sock"

	/// Path to the LaunchDaemon plist.
	public static let plistPath = "/Library/LaunchDaemons/com.macromates.auth_server.plist"

	/// Authorization right name.
	public static let rightName = "com.macromates.textmate.openfile"
}

// MARK: - XPC Protocol

/// Protocol for the privileged helper XPC service.
///
/// This defines the interface for operations that require elevated privileges,
/// such as reading/writing files owned by root.
@objc public protocol PrivilegedHelperProtocol {
	/// Read the contents of a file that requires elevated privileges.
	func readFile(
		atPath path: String,
		reply: @escaping @Sendable (Data?, Error?) -> Void,
	)

	/// Write data to a file that requires elevated privileges.
	func writeFile(
		atPath path: String,
		data: Data,
		reply: @escaping @Sendable (Error?) -> Void,
	)

	/// Check if the helper tool version matches the expected version.
	func getVersion(
		reply: @escaping @Sendable (String) -> Void,
	)
}

// MARK: - Authorization Service

/// Service for managing privileged operations via macOS authorization.
///
/// Ports `Frameworks/authorization/src/authorization.h` and
/// `Frameworks/authorization/src/server.mm`.
///
/// Provides:
/// - Security.framework `AuthorizationRef` management
/// - XPC connection to privileged helper tool
/// - Authorization right checking and obtaining
///
/// The legacy C++ implementation used Unix sockets and a custom IPC protocol.
/// This Swift implementation uses `NSXPCConnection` and `SMAppService` for
/// a modern, sandboxing-compatible approach.
@MainActor
public final class AuthorizationService: Sendable {
	/// Shared singleton instance.
	public static let shared = AuthorizationService()

	/// Logger for authorization events.
	private nonisolated let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "com.macromates.TextMate",
		category: "Authorization",
	)

	/// The active XPC connection, if established.
	private var xpcConnection: NSXPCConnection?

	private init() {}

	// MARK: - Authorization Rights

	/// Check whether the user has a specific authorization right without prompting.
	///
	/// - Parameter right: The authorization right name to check.
	/// - Returns: `true` if the right is currently authorized.
	public nonisolated func checkRight(_ right: String = AuthorizationConstants.rightName) -> Bool {
		var authRef: AuthorizationRef?
		let status = AuthorizationCreate(nil, nil, [], &authRef)
		guard status == errAuthorizationSuccess, let authRef else { return false }
		defer { AuthorizationFree(authRef, []) }

		let copyStatus: OSStatus = right.withCString { rightCString in
			var item = AuthorizationItem(
				name: rightCString,
				valueLength: 0,
				value: nil,
				flags: 0,
			)
			return withUnsafeMutablePointer(to: &item) { itemPointer in
				var rights = AuthorizationRights(count: 1, items: itemPointer)
				return AuthorizationCopyRights(
					authRef,
					&rights,
					nil,
					[],
					nil,
				)
			}
		}
		return copyStatus == errAuthorizationSuccess
	}

	/// Obtain an authorization right, prompting the user if needed.
	///
	/// - Parameter right: The authorization right name.
	/// - Returns: `true` if the right was obtained.
	public nonisolated func obtainRight(_ right: String = AuthorizationConstants.rightName) -> Bool {
		var authRef: AuthorizationRef?
		let status = AuthorizationCreate(nil, nil, [], &authRef)
		guard status == errAuthorizationSuccess, let authRef else { return false }
		defer { AuthorizationFree(authRef, []) }

		let copyStatus: OSStatus = right.withCString { rightCString in
			var item = AuthorizationItem(
				name: rightCString,
				valueLength: 0,
				value: nil,
				flags: 0,
			)
			return withUnsafeMutablePointer(to: &item) { itemPointer in
				var rights = AuthorizationRights(count: 1, items: itemPointer)
				return AuthorizationCopyRights(
					authRef,
					&rights,
					nil,
					[.interactionAllowed, .extendRights],
					nil,
				)
			}
		}

		switch copyStatus {
		case errAuthorizationSuccess:
			return true
		case errAuthorizationCanceled:
			logger.info("Authorization canceled by user")
			return false
		case errAuthorizationDenied:
			logger.info("Authorization denied")
			return false
		case errAuthorizationInteractionNotAllowed:
			logger.info("Authorization interaction not allowed")
			return false
		default:
			logger.error("Authorization error: \(copyStatus)")
			return false
		}
	}

	// MARK: - External Form Serialization

	/// Serialize an `AuthorizationRef` to a hex string for IPC.
	///
	/// - Parameter authRef: The authorization reference.
	/// - Returns: Hex-encoded string, or `nil` if serialization fails.
	public nonisolated func serializeAuthorization(_ authRef: AuthorizationRef) -> String? {
		var extForm = AuthorizationExternalForm()
		guard AuthorizationMakeExternalForm(authRef, &extForm) == errAuthorizationSuccess else {
			return nil
		}

		return withUnsafeBytes(of: &extForm) { bytes in
			bytes.map { String(format: "%02X", $0) }.joined()
		}
	}

	/// Deserialize a hex string back to an `AuthorizationRef`.
	///
	/// - Parameter hex: Hex-encoded authorization external form.
	/// - Returns: The reconstructed `AuthorizationRef`, or `nil`.
	public nonisolated func deserializeAuthorization(_ hex: String) -> AuthorizationRef? {
		var bytes: [UInt8] = []
		var index = hex.startIndex
		while index < hex.endIndex {
			let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
			guard nextIndex != index else { break }
			let hexByte = String(hex[index ..< nextIndex])
			guard let byte = UInt8(hexByte, radix: 16) else { return nil }
			bytes.append(byte)
			index = nextIndex
		}

		guard bytes.count == MemoryLayout<AuthorizationExternalForm>.size else { return nil }

		var authRef: AuthorizationRef?
		let result: OSStatus = bytes.withUnsafeBufferPointer { buffer in
			buffer.baseAddress!.withMemoryRebound(
				to: AuthorizationExternalForm.self,
				capacity: 1,
			) { extForm in
				AuthorizationCreateFromExternalForm(extForm, &authRef)
			}
		}

		return result == errAuthorizationSuccess ? authRef : nil
	}

	// MARK: - XPC Connection

	/// Establish an XPC connection to the privileged helper tool.
	///
	/// - Returns: The XPC connection proxy, or `nil` if connection fails.
	public func connectToHelper() -> (any PrivilegedHelperProtocol)? {
		if let existing = xpcConnection {
			return existing.remoteObjectProxy as? any PrivilegedHelperProtocol
		}

		let connection = NSXPCConnection(
			machServiceName: AuthorizationConstants.jobName,
			options: .privileged,
		)
		connection.remoteObjectInterface = NSXPCInterface(
			with: PrivilegedHelperProtocol.self,
		)
		connection.invalidationHandler = { [weak self] in
			Task { @MainActor [weak self] in
				self?.xpcConnection = nil
			}
		}
		connection.interruptionHandler = { [weak self] in
			Task { @MainActor [weak self] in
				self?.xpcConnection = nil
			}
		}
		connection.resume()

		xpcConnection = connection
		return connection.remoteObjectProxy as? any PrivilegedHelperProtocol
	}

	/// Disconnect from the privileged helper tool.
	public func disconnect() {
		xpcConnection?.invalidate()
		xpcConnection = nil
	}

	// MARK: - Convenience Methods

	/// Read a privileged file using the helper tool.
	///
	/// - Parameter path: The file path to read.
	/// - Returns: The file data.
	/// - Throws: If reading fails or the helper is unavailable.
	public func readPrivilegedFile(atPath path: String) async throws -> Data {
		guard let helper = connectToHelper() else {
			throw AuthorizationError.helperNotAvailable
		}

		return try await withCheckedThrowingContinuation { continuation in
			helper.readFile(atPath: path) { data, error in
				if let error {
					continuation.resume(throwing: error)
				} else if let data {
					continuation.resume(returning: data)
				} else {
					continuation.resume(throwing: AuthorizationError.unknownError)
				}
			}
		}
	}

	/// Write to a privileged file using the helper tool.
	///
	/// - Parameters:
	///   - data: The data to write.
	///   - path: The file path to write to.
	/// - Throws: If writing fails or the helper is unavailable.
	public func writePrivilegedFile(data: Data, toPath path: String) async throws {
		guard let helper = connectToHelper() else {
			throw AuthorizationError.helperNotAvailable
		}

		return try await withCheckedThrowingContinuation { continuation in
			helper.writeFile(atPath: path, data: data) { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}
	}
}

// MARK: - Authorization Errors

/// Errors related to authorization operations.
public enum AuthorizationError: Error, LocalizedError, Sendable {
	case helperNotAvailable
	case authorizationDenied
	case authorizationCanceled
	case unknownError

	public var errorDescription: String? {
		switch self {
		case .helperNotAvailable:
			"The privileged helper tool is not available."
		case .authorizationDenied:
			"Authorization was denied."
		case .authorizationCanceled:
			"Authorization was canceled by the user."
		case .unknownError:
			"An unknown authorization error occurred."
		}
	}
}
#endif
