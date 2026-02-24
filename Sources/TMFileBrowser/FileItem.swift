#if canImport(AppKit)
import AppKit
import QuickLookUI

/// Well-known URL constants for special locations in the file browser.
public enum FileBrowserLocation {
	/// The "Computer" root showing all mounted volumes.
	public static let computer = URL(string: "computer:///")!

	/// The user's favorites/bookmarks sidebar location.
	public static let favorites = URL(string: "favorites:///")!
}

/// A model object representing a file or directory in the file browser.
///
/// Port of the C++ `FileItem` class from `Frameworks/FileBrowser/src/FileItem.h`.
/// Supports URL resolution, file property flags, Finder tags, and an
/// observer pattern for directory content changes.
@MainActor
public final class FileItem: NSObject, @unchecked Sendable {
	/// The URL for this file item.
	@objc public dynamic var URL: Foundation.URL {
		didSet {
			updateFileProperties()
		}
	}

	/// Lowercase Swift-convention alias for the `URL` property.
	public var url: Foundation.URL {
		URL
	}

	/// A file reference URL that persists across renames.
	public var fileReferenceURL: Foundation.URL? {
		try? URL.bookmarkData(options: [.withSecurityScope]).withUnsafeBytes { _ in
			URL
		}
	}

	/// The resolved URL, following symlinks.
	public var resolvedURL: Foundation.URL {
		URL.resolvingSymlinksInPath()
	}

	/// The parent directory URL.
	public var parentURL: Foundation.URL {
		URL.deletingLastPathComponent()
	}

	/// Whether this item represents a directory.
	public var isDirectory: Bool {
		var isDir: ObjCBool = false
		FileManager.default.fileExists(atPath: URL.path, isDirectory: &isDir)
		return isDir.boolValue
	}

	/// The display name for this item.
	@objc public dynamic var displayName: String {
		if let localizedName, !localizedName.isEmpty {
			var name = localizedName
			if let suffix = disambiguationSuffix, !suffix.isEmpty {
				name += " — " + suffix
			}
			return name
		}
		return FileManager.default.displayName(atPath: URL.path)
	}

	/// The localized display name from the file system.
	public var localizedName: String?

	/// A disambiguation suffix shown when multiple items have the same name.
	public var disambiguationSuffix: String?

	/// The tooltip string for this item.
	public var toolTip: String?

	/// Whether this file can be renamed.
	public var canRename: Bool {
		URL.isFileURL && FileManager.default.isWritableFile(atPath: parentURL.path)
	}

	/// Whether this file is an application bundle.
	public var isApplication: Bool {
		guard let uti = try? URL.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
		return uti.conforms(to: .application)
	}

	/// Whether this file is missing from disk.
	@objc public dynamic var isMissing: Bool = false

	/// Whether this file is hidden (invisible).
	public var isHidden: Bool = false

	/// Whether the file extension is hidden by the OS.
	public var hasHiddenExtension: Bool = false

	/// Whether this file is a symbolic link.
	public var isSymbolicLink: Bool = false

	/// Whether this item is a package (bundle).
	public var isPackage: Bool = false

	/// Whether this item is a symbolic link pointing to a package.
	public var isLinkToPackage: Bool = false

	/// Whether this item is a symbolic link pointing to a directory.
	public var isLinkToDirectory: Bool = false

	/// Finder tags for this item.
	public var finderTags: [FinderTag] = []

	/// The direct children of this item (if a directory).
	public var children: [FileItem]?

	/// The arranged (sorted/filtered) children for display.
	public var arrangedChildren: [FileItem]?

	// MARK: - Initialization

	/// Creates a file item for the given URL.
	public init(url: Foundation.URL) {
		URL = url
		super.init()
		updateFileProperties()
	}

	/// Convenience factory method.
	public static func fileItem(with url: Foundation.URL) -> FileItem {
		FileItem(url: url)
	}

	/// Updates file property flags by reading resource values.
	public func updateFileProperties() {
		guard URL.isFileURL else { return }

		let keys: Set<URLResourceKey> = [
			.isHiddenKey, .isSymbolicLinkKey, .isPackageKey,
			.hasHiddenExtensionKey, .localizedNameKey, .tagNamesKey,
		]

		guard let values = try? URL.resourceValues(forKeys: keys) else {
			isMissing = true
			return
		}

		isMissing = false
		isHidden = values.isHidden ?? false
		isSymbolicLink = values.isSymbolicLink ?? false
		isPackage = values.isPackage ?? false
		hasHiddenExtension = values.hasHiddenExtension ?? false
		localizedName = values.localizedName

		if let tagNames = values.tagNames {
			finderTags = tagNames.compactMap { FinderTag(name: $0) }
		}

		if isSymbolicLink {
			let resolved = URL.resolvingSymlinksInPath()
			var isDir: ObjCBool = false
			if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) {
				isLinkToDirectory = isDir.boolValue
				if let resolvedValues = try? resolved.resourceValues(forKeys: [.isPackageKey]) {
					isLinkToPackage = resolvedValues.isPackage ?? false
				}
			}
		}
	}

	// MARK: - Observer Pattern

	/// Observer token for directory content changes.
	public class DirectoryObserver {
		let url: Foundation.URL
		let handler: ([Foundation.URL]) -> Void
		var fsEventObserver: Any?

		init(url: Foundation.URL, handler: @escaping ([Foundation.URL]) -> Void) {
			self.url = url
			self.handler = handler
		}
	}

	private static var directoryObservers: [Foundation.URL: [DirectoryObserver]] = [:]

	/// Adds an observer for directory content changes at the given URL.
	///
	/// - Parameters:
	///   - url: The directory URL to observe.
	///   - handler: Called with an array of child URLs when the directory changes.
	/// - Returns: An opaque observer token. Pass to ``removeObserver(_:)`` to stop.
	public static func addObserver(
		toDirectoryAt url: Foundation.URL,
		handler: @escaping ([Foundation.URL]) -> Void,
	) -> DirectoryObserver {
		let observer = DirectoryObserver(url: url, handler: handler)

		var observers = directoryObservers[url] ?? []
		observers.append(observer)
		directoryObservers[url] = observers

		return observer
	}

	/// Removes a directory observer.
	public static func removeObserver(_ observer: DirectoryObserver) {
		guard var observers = directoryObservers[observer.url] else { return }
		observers.removeAll { $0 === observer }
		if observers.isEmpty {
			directoryObservers.removeValue(forKey: observer.url)
		} else {
			directoryObservers[observer.url] = observers
		}
	}

	/// Notifies all observers for the given URL with updated child URLs.
	public static func notifyObservers(for url: Foundation.URL, children: [Foundation.URL]) {
		guard let observers = directoryObservers[url] else { return }
		for observer in observers {
			observer.handler(children)
		}
	}
}

// MARK: - QLPreviewItem

extension FileItem: QLPreviewItem {
	public nonisolated var previewItemURL: Foundation.URL? {
		MainActor.assumeIsolated { URL }
	}

	public nonisolated var previewItemTitle: String? {
		MainActor.assumeIsolated { displayName }
	}
}

// MARK: - Finder Tags

/// Represents a macOS Finder tag with a name and optional color.
public struct FinderTag: Sendable, Equatable, Hashable {
	/// The display name of the tag.
	public let name: String

	/// The tag's label color, if any.
	public let labelColor: NSColor?

	/// All favorite (system-defined) Finder tags.
	public static var favoriteTags: [FinderTag] {
		let workspace = NSWorkspace.shared
		let tags = workspace.fileLabels
		let colors = workspace.fileLabelColors

		return zip(tags, colors).compactMap { name, color in
			name.isEmpty ? nil : FinderTag(name: name, labelColor: color)
		}
	}

	/// Creates a Finder tag from a name, looking up the system color.
	public init(name: String, labelColor: NSColor? = nil) {
		self.name = name
		if let color = labelColor {
			self.labelColor = color
		} else {
			// Try to find this tag's color from system favorites
			let workspace = NSWorkspace.shared
			let tags = workspace.fileLabels
			let colors = workspace.fileLabelColors
			if let index = tags.firstIndex(of: name) {
				self.labelColor = colors[index]
			} else {
				self.labelColor = nil
			}
		}
	}

	public var displayName: String {
		name
	}
}
#endif
