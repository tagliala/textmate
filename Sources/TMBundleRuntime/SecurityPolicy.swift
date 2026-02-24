import Foundation

// MARK: - Trust Level

/// Graduated trust levels for bundle command execution.
/// Higher levels allow more system access.
public enum TrustLevel: Int, Comparable, Sendable, Codable, CaseIterable {
	/// No execution allowed.
	case blocked = 0
	/// Commands that only read (no writes, network, or subprocess spawning).
	case readOnly = 1
	/// Commands may write to the document but not the filesystem.
	case documentWrite = 2
	/// Commands may write within the project directory.
	case projectWrite = 3
	/// Unrestricted execution — matches legacy TextMate behavior.
	case full = 4

	public static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

// MARK: - Permission Request

/// A request presented to the user when a command needs higher trust.
public struct PermissionRequest: Sendable, Equatable {
	public let commandName: String
	public let bundleName: String
	public let bundleUUID: String
	public let requiredLevel: TrustLevel
	public let currentLevel: TrustLevel
	public let explanation: String

	public init(
		commandName: String,
		bundleName: String,
		bundleUUID: String,
		requiredLevel: TrustLevel,
		currentLevel: TrustLevel,
		explanation: String = "",
	) {
		self.commandName = commandName
		self.bundleName = bundleName
		self.bundleUUID = bundleUUID
		self.requiredLevel = requiredLevel
		self.currentLevel = currentLevel
		self.explanation = explanation
	}
}

/// The user's response to a permission request.
public enum PermissionResponse: Sendable, Equatable {
	/// Allow this single execution.
	case allowOnce
	/// Allow and remember for this bundle.
	case allowAlways
	/// Deny this single execution.
	case denyOnce
	/// Deny and remember for this bundle.
	case denyAlways
}

// MARK: - Security Policy

/// Manages trust decisions for bundle command execution.
///
/// The policy stores per-bundle trust levels and provides a single
/// entry point (`authorize`) that checks whether a command may run
/// at the requested trust level.
public final class SecurityPolicy: Sendable {
	/// Per-bundle trust overrides, keyed by bundle UUID.
	private let overrides: LockedBox<[String: TrustLevel]>

	/// The default trust level for bundles without an explicit override.
	public let defaultTrustLevel: TrustLevel

	/// Bundles that ship with TextMate are automatically fully trusted.
	private let builtInBundleUUIDs: LockedBox<Set<String>>

	public init(
		defaultTrustLevel: TrustLevel = .full,
		builtInBundleUUIDs: Set<String> = [],
	) {
		self.defaultTrustLevel = defaultTrustLevel
		overrides = LockedBox([:])
		self.builtInBundleUUIDs = LockedBox(builtInBundleUUIDs)
	}

	// MARK: - Query

	/// Returns the effective trust level for a bundle.
	public func trustLevel(forBundle uuid: String) -> TrustLevel {
		if builtInBundleUUIDs.value.contains(uuid) {
			return .full
		}
		return overrides.value[uuid] ?? defaultTrustLevel
	}

	/// Checks whether a command from the given bundle is authorized
	/// to run at the specified trust level.
	public func isAuthorized(bundleUUID: String, requiredLevel: TrustLevel) -> Bool {
		trustLevel(forBundle: bundleUUID) >= requiredLevel
	}

	// MARK: - Mutation

	/// Sets the trust level for a specific bundle.
	public func setTrustLevel(_ level: TrustLevel, forBundle uuid: String) {
		overrides.withLock { $0[uuid] = level }
	}

	/// Removes any per-bundle override, reverting to the default.
	public func resetTrustLevel(forBundle uuid: String) {
		_ = overrides.withLock { $0.removeValue(forKey: uuid) }
	}

	/// Registers a set of bundle UUIDs as built-in (always fully trusted).
	public func registerBuiltInBundles(_ uuids: Set<String>) {
		builtInBundleUUIDs.withLock { $0.formUnion(uuids) }
	}

	/// Returns all stored per-bundle overrides.
	public var allOverrides: [String: TrustLevel] {
		overrides.value
	}

	// MARK: - Authorization Flow

	/// Determines if a command requires a permission prompt and builds the request.
	/// Returns `nil` if the command is already authorized.
	public func permissionRequest(
		commandName: String,
		bundleName: String,
		bundleUUID: String,
		requiredLevel: TrustLevel,
	) -> PermissionRequest? {
		let current = trustLevel(forBundle: bundleUUID)
		guard current < requiredLevel else { return nil }
		return PermissionRequest(
			commandName: commandName,
			bundleName: bundleName,
			bundleUUID: bundleUUID,
			requiredLevel: requiredLevel,
			currentLevel: current,
			explanation: "'\(commandName)' from bundle '\(bundleName)' requires \(requiredLevel) access.",
		)
	}

	/// Applies a user's permission response.
	public func applyResponse(_ response: PermissionResponse, to request: PermissionRequest) {
		switch response {
		case .allowAlways:
			setTrustLevel(request.requiredLevel, forBundle: request.bundleUUID)
		case .denyAlways:
			setTrustLevel(.blocked, forBundle: request.bundleUUID)
		case .allowOnce, .denyOnce:
			break // No persistent change.
		}
	}
}

// MARK: - Thread-safe Box

/// A simple lock-protected value container for `Sendable` conformance.
final class LockedBox<Value: Sendable>: @unchecked Sendable {
	private var _value: Value
	private let lock = NSLock()

	init(_ value: Value) {
		_value = value
	}

	var value: Value {
		lock.lock()
		defer { lock.unlock() }
		return _value
	}

	func withLock<T>(_ body: (inout Value) -> T) -> T {
		lock.lock()
		defer { lock.unlock() }
		return body(&_value)
	}
}
