#if canImport(AppKit)
import AppKit

/// Generates composite file icons with SCM status overlays.
///
/// Port of `CreateIconImageForURL` from `FileItemImage.mm`.
/// Uses the system icon as a base and composites SCM status badges.
@MainActor
public enum FileItemImage {
	/// SCM status types that can be displayed as icon badges.
	public enum SCMStatus: Sendable {
		case none
		case unknown
		case unversioned
		case modified
		case added
		case deleted
		case conflicted
		case mixed
	}

	/// Creates a composite icon image for a file item.
	///
	/// - Parameters:
	///   - url: The file URL.
	///   - isModified: Whether the file has unsaved modifications.
	///   - isMissing: Whether the file is missing from disk.
	///   - isDirectory: Whether the file is a directory.
	///   - isSymbolicLink: Whether the file is a symbolic link.
	///   - scmStatus: The SCM status for badge overlay.
	///   - size: The target icon size (default 16×16).
	/// - Returns: A composite `NSImage`.
	public static func iconImage(
		for url: URL,
		isModified: Bool = false,
		isMissing: Bool = false,
		isDirectory _: Bool = false,
		isSymbolicLink _: Bool = false,
		scmStatus: SCMStatus = .none,
		size: NSSize = NSSize(width: 16, height: 16),
	) -> NSImage {
		let baseIcon: NSImage = if isMissing, scmStatus == .none || scmStatus == .unknown {
			// Unknown file type icon for missing files
			NSWorkspace.shared.icon(for: .item)
		} else {
			NSWorkspace.shared.icon(forFile: url.path)
		}

		var icon = baseIcon.copy() as! NSImage
		icon.size = size

		// Apply SCM badge overlay
		if scmStatus != .none, scmStatus != .unknown {
			icon = compositeIcon(icon, withBadge: badgeImage(for: scmStatus, size: size), size: size)
		}

		// Dim icon for modified (unsaved) files
		if isModified {
			icon = dimmedIcon(icon, fraction: 0.4, size: size)
		}

		return icon
	}

	// MARK: - Badge Generation

	/// Returns a small badge image for the given SCM status.
	private static func badgeImage(for status: SCMStatus, size: NSSize) -> NSImage? {
		let badgeSize = NSSize(width: size.width * 0.5, height: size.height * 0.5)

		let color: NSColor
		let symbol: String

		switch status {
		case .modified:
			color = .systemOrange
			symbol = "M"
		case .added:
			color = .systemGreen
			symbol = "A"
		case .deleted:
			color = .systemRed
			symbol = "D"
		case .conflicted:
			color = .systemYellow
			symbol = "!"
		case .unversioned:
			color = .systemGray
			symbol = "?"
		case .mixed:
			color = .systemPurple
			symbol = "~"
		case .none, .unknown:
			return nil
		}

		return NSImage(size: badgeSize, flipped: false) { rect in
			color.setFill()
			let circlePath = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
			circlePath.fill()

			let attrs: [NSAttributedString.Key: Any] = [
				.font: NSFont.boldSystemFont(ofSize: badgeSize.width * 0.55),
				.foregroundColor: NSColor.white,
			]
			let str = NSAttributedString(string: symbol, attributes: attrs)
			let strSize = str.size()
			let strOrigin = NSPoint(
				x: rect.midX - strSize.width / 2,
				y: rect.midY - strSize.height / 2,
			)
			str.draw(at: strOrigin)
			return true
		}
	}

	/// Composites a badge onto the bottom-right of an icon.
	private static func compositeIcon(_ base: NSImage, withBadge badge: NSImage?, size: NSSize) -> NSImage {
		guard let badge else { return base }

		return NSImage(size: size, flipped: false) { rect in
			base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
			let badgeRect = NSRect(
				x: rect.maxX - badge.size.width,
				y: 0,
				width: badge.size.width,
				height: badge.size.height,
			)
			badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1.0)
			return true
		}
	}

	/// Dims an icon to indicate modification.
	private static func dimmedIcon(_ icon: NSImage, fraction: CGFloat, size: NSSize) -> NSImage {
		NSImage(size: size, flipped: false) { rect in
			icon.draw(in: rect, from: .zero, operation: .copy, fraction: fraction)
			return true
		}
	}
}
#endif
