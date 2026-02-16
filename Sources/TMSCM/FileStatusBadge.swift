import Foundation

#if canImport(AppKit)
import AppKit
#endif

// MARK: - File Status Badge

/// Computes visual badge information for a file's SCM status — used by
/// the file browser to display status indicators.
public struct FileStatusBadge: Sendable, Equatable {
	/// The SCM status this badge represents.
	public let status: SCMStatus

	/// Badge color name suitable for use with NSColor/SwiftUI Color.
	public var colorName: String {
		switch status {
		case .modified: "systemOrange"
		case .added: "systemGreen"
		case .deleted: "systemRed"
		case .conflicted: "systemRed"
		case .unversioned: "systemGray"
		case .mixed: "systemYellow"
		case .ignored: "tertiaryLabel"
		case .none, .unknown: ""
		}
	}

	/// Whether this badge should be displayed.
	public var isVisible: Bool {
		status.isInteresting
	}

	/// Badge text (the short status character).
	public var text: String {
		status.shortName
	}

	/// SF Symbol name for the status, if available.
	public var symbolName: String {
		switch status {
		case .modified: "pencil.circle.fill"
		case .added: "plus.circle.fill"
		case .deleted: "minus.circle.fill"
		case .conflicted: "exclamationmark.triangle.fill"
		case .unversioned: "questionmark.circle"
		case .mixed: "ellipsis.circle.fill"
		case .ignored: "eye.slash"
		case .none, .unknown: ""
		}
	}

	public init(status: SCMStatus) {
		self.status = status
	}

	#if canImport(AppKit)
	/// Create an NSColor for this badge's color.
	public var color: NSColor? {
		switch status {
		case .modified: NSColor.systemOrange
		case .added: NSColor.systemGreen
		case .deleted: NSColor.systemRed
		case .conflicted: NSColor.systemRed
		case .unversioned: NSColor.systemGray
		case .mixed: NSColor.systemYellow
		case .ignored: NSColor.tertiaryLabelColor
		case .none, .unknown: nil
		}
	}
	#endif
}

// MARK: - File Status Badge Provider

/// Provides badges for files based on their SCM status.
///
/// Caches badge instances and integrates with `SCMManager` for live updates.
@MainActor
public final class FileStatusBadgeProvider {
	/// The SCM manager to query.
	private let manager: SCMManager

	/// Badge cache for quick lookups.
	private var cache: [String: FileStatusBadge] = [:]

	public init(manager: SCMManager = .shared) {
		self.manager = manager
	}

	/// Get the badge for a file at the given path.
	public func badge(for path: String) -> FileStatusBadge {
		let status = manager.status(for: path)
		return FileStatusBadge(status: status)
	}

	/// Get badges for multiple files.
	public func badges(for paths: [String]) -> [String: FileStatusBadge] {
		var result: [String: FileStatusBadge] = [:]
		for path in paths {
			result[path] = badge(for: path)
		}
		return result
	}

	/// Invalidate the cache for a specific path.
	public func invalidate(path: String) {
		cache.removeValue(forKey: path)
	}

	/// Invalidate all cached badges.
	public func invalidateAll() {
		cache.removeAll()
	}
}
