import Foundation

// MARK: - SCM Status

/// Represents the version-control status of a file — maps to `scm::status::type`.
public enum SCMStatus: Int, Sendable, Codable, Hashable, CaseIterable {
	case unknown = 0
	case none = 1
	case unversioned = 2
	case modified = 3
	case added = 4
	case deleted = 5
	case conflicted = 6
	case ignored = 7
	case mixed = 8

	/// Short string representation used in commit messages and UI badges.
	public var shortName: String {
		switch self {
		case .unknown: "?"
		case .none: " "
		case .unversioned: "?"
		case .modified: "M"
		case .added: "A"
		case .deleted: "D"
		case .conflicted: "C"
		case .ignored: "!"
		case .mixed: "~"
		}
	}

	/// Display-friendly name.
	public var displayName: String {
		switch self {
		case .unknown: "Unknown"
		case .none: "Clean"
		case .unversioned: "Unversioned"
		case .modified: "Modified"
		case .added: "Added"
		case .deleted: "Deleted"
		case .conflicted: "Conflicted"
		case .ignored: "Ignored"
		case .mixed: "Mixed"
		}
	}

	/// Whether this status indicates a tracked, changed file.
	public var isModified: Bool {
		switch self {
		case .modified, .added, .deleted, .conflicted: true
		default: false
		}
	}

	/// Whether this status is suitable for display (filters out none/unknown/ignored).
	public var isInteresting: Bool {
		switch self {
		case .modified, .added, .deleted, .conflicted, .unversioned, .mixed: true
		default: false
		}
	}
}

// MARK: - SCM Status Map

/// Maps file paths to their SCM status — equivalent to `scm::status_map_t`.
public struct SCMStatusMap: Sendable, Equatable {
	/// The underlying path→status dictionary.
	public private(set) var entries: [String: SCMStatus]

	public init(_ entries: [String: SCMStatus] = [:]) {
		self.entries = entries
	}

	/// Get the status for a specific path.
	public func status(for path: String) -> SCMStatus {
		entries[path] ?? .unknown
	}

	/// All paths with a given status.
	public func paths(with status: SCMStatus) -> [String] {
		entries.filter { $0.value == status }.map(\.key).sorted()
	}

	/// All paths that are modified (added, modified, deleted, conflicted).
	public var modifiedPaths: [String] {
		entries.filter(\.value.isModified).map(\.key).sorted()
	}

	/// All paths with interesting status (excludes none, unknown, ignored).
	public var interestingPaths: [String] {
		entries.filter(\.value.isInteresting).map(\.key).sorted()
	}

	/// Merge another status map into this one (other takes precedence).
	public mutating func merge(_ other: SCMStatusMap) {
		entries.merge(other.entries) { _, new in new }
	}

	/// Number of entries.
	public var count: Int {
		entries.count
	}

	/// Whether the map is empty.
	public var isEmpty: Bool {
		entries.isEmpty
	}

	/// Compute directory-level mixed status.
	///
	/// If a directory contains files with different statuses, the directory
	/// gets `.mixed` status. If all files share the same status, the directory
	/// gets that status.
	public func directoryStatus(for dirPath: String) -> SCMStatus {
		let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
		let childStatuses = entries
			.filter { $0.key.hasPrefix(prefix) && $0.value.isInteresting }
			.map(\.value)

		guard let first = childStatuses.first else { return .none }

		if childStatuses.allSatisfy({ $0 == first }) {
			return first
		}
		return .mixed
	}
}

// MARK: - SCM Variables

/// Environment variables provided by the SCM system — maps to `scm::info_t::variables()`.
public struct SCMVariables: Sendable, Equatable {
	/// The VCS name (e.g., "git", "hg", "svn").
	public let scmName: String

	/// The repository root path.
	public let rootPath: String

	/// The current branch name, if any.
	public let branch: String?

	/// Additional variables provided by the driver.
	public let variables: [String: String]

	public init(scmName: String, rootPath: String, branch: String? = nil, variables: [String: String] = [:]) {
		self.scmName = scmName
		self.rootPath = rootPath
		self.branch = branch
		self.variables = variables
	}

	/// All variables as a flat dictionary suitable for environment export.
	public var environmentVariables: [String: String] {
		var env = variables
		env["TM_SCM_NAME"] = scmName
		env["TM_SCM_BRANCH"] = branch ?? ""
		return env
	}
}
