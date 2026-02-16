import AppKit
import os

// MARK: - Notifications

/// Posted when a file reference is about to be closed via `performClose(_:)`.
/// The `userInfo` dictionary contains a `"URL"` key with the associated `URL`.
public extension Notification.Name {
	static let fileReferenceWillClose = Notification.Name("TMURLWillCloseNotification")
}

// MARK: - SCM Badge Status

/// Lightweight SCM status used by `FileReference` for badge overlay.
///
/// Maps to the `scm::status::type` enum in the C++ codebase.
/// Kept separate from `TMSCM.SCMStatus` so that TMPreferences
/// does not depend on TMSCM; callers bridge the two at the use site.
public enum FileReferenceSCMStatus: Int, Sendable, Hashable {
	case none = 0
	case unversioned
	case modified
	case added
	case deleted
	case conflicted
	case mixed
}

// MARK: - File Reference

/// Identity-mapped file-reference object that composites a file icon with
/// optional SCM-status and symlink badges.
///
/// Each URL is represented by at most one `FileReference` — the shared cache
/// uses `NSMapTable` with strong-to-weak semantics so instances are automatically
/// reclaimed when no longer retained elsewhere.
///
/// Ports the Objective-C++ `TMFileReference` class.
@MainActor
public final class FileReference: NSObject {
	// MARK: Shared cache

	/// Identity map: one `FileReference` per absolute URL.
	private static let cache = NSMapTable<NSURL, FileReference>.strongToWeakObjects()

	/// Return the shared file reference for *url*. Returns the same instance
	/// when called with equal URLs.
	public static func fileReference(for url: URL) -> FileReference {
		let key = url.absoluteURL as NSURL
		if let existing = cache.object(forKey: key) {
			return existing
		}
		let ref = FileReference(url: url.absoluteURL)
		cache.setObject(ref, forKey: key)
		return ref
	}

	/// Create a file reference that displays a fixed *image* (no URL, no
	/// SCM badges). Not cached.
	public static func fileReference(image: NSImage) -> FileReference {
		FileReference(image: image)
	}

	/// Convenience: return a copy of the icon for *url* rendered at *size*.
	public static func image(for url: URL, size: NSSize) -> NSImage {
		let img = fileReference(for: url).image.copy() as! NSImage
		img.size = size
		return img
	}

	// MARK: Properties

	/// The URL this reference represents (`nil` for image-only refs).
	public let url: URL?

	/// The current SCM status used for badge overlay.
	public var scmStatus: FileReferenceSCMStatus = .none {
		didSet {
			guard scmStatus != oldValue else { return }
			if cachedImage != nil {
				willChangeValue(forKey: "image")
				cachedImage = nil
				didChangeValue(forKey: "image")
			}
		}
	}

	/// The composited icon: base file icon + SCM badge + optional symlink badge.
	@objc public dynamic var image: NSImage {
		if let cached = cachedImage { return cached }
		let composed = composeImage()
		cachedImage = composed
		return composed
	}

	/// The icon with alpha = 0.4 when the reference `isModified`.
	///
	/// Bindings: depends on `image` and `modified`.
	@objc public dynamic var icon: NSImage {
		let base = image
		guard isModified else { return base }
		return NSImage(size: base.size, flipped: false) { rect in
			base.draw(in: rect, from: .zero, operation: .copy, fraction: 0.4)
			return true
		}
	}

	/// Whether the file is currently open (openCount > 0).
	@objc public dynamic var isClosable: Bool {
		openCount > 0
	}

	/// Whether the file has unsaved modifications (modifiedCount > 0).
	@objc public dynamic var isModified: Bool {
		modifiedCount > 0
	}

	// MARK: Close

	/// Posts ``Notification.Name.fileReferenceWillClose`` for the receiver's URL.
	@objc public func performClose(_: Any?) {
		guard let url else { return }
		NotificationCenter.default.post(
			name: .fileReferenceWillClose,
			object: self,
			userInfo: ["URL": url],
		)
	}

	// MARK: Reference counting

	/// Increase the open-reference count (called by document owners).
	public func increaseOpenCount() {
		willChangeValue(forKey: "isClosable")
		openCount += 1
		didChangeValue(forKey: "isClosable")
	}

	/// Decrease the open-reference count.
	public func decreaseOpenCount() {
		precondition(openCount > 0, "decreaseOpenCount called when openCount is zero")
		willChangeValue(forKey: "isClosable")
		openCount -= 1
		didChangeValue(forKey: "isClosable")
	}

	/// Increase the modified-reference count (called when document becomes dirty).
	public func increaseModifiedCount() {
		precondition(openCount > 0, "increaseModifiedCount called when openCount is zero")
		willChangeValue(forKey: "isModified")
		modifiedCount += 1
		didChangeValue(forKey: "isModified")
	}

	/// Decrease the modified-reference count (called when document is saved).
	public func decreaseModifiedCount() {
		precondition(modifiedCount > 0, "decreaseModifiedCount called when modifiedCount is zero")
		willChangeValue(forKey: "isModified")
		modifiedCount -= 1
		didChangeValue(forKey: "isModified")
	}

	// MARK: KVO dependencies

	@objc public class func keyPathsForValuesAffectingIcon() -> Set<String> {
		["image", "isModified"]
	}

	// MARK: Equality / Hashing

	override public var hash: Int {
		url?.hashValue ?? ObjectIdentifier(self).hashValue
	}

	override public func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? FileReference else { return false }
		return url == other.url
	}

	// MARK: Private

	private var openCount: Int = 0
	private var modifiedCount: Int = 0
	private var cachedImage: NSImage?

	private init(url: URL) {
		self.url = url
		super.init()
	}

	private init(image: NSImage) {
		url = nil
		cachedImage = image
		super.init()
	}

	deinit {
		// In debug builds, verify that the open count has been balanced.
		MainActor.assumeIsolated {
			assert(openCount == 0, "FileReference dealloc with non-zero openCount: \(openCount)")
		}
	}

	// MARK: Image composition

	/// Custom filename → icon name bindings loaded from the app bundle.
	private static let customBindings: [String: String] = {
		guard let path = Bundle.main.path(forResource: "DocumentTypes/bindings", ofType: "plist"),
		      let dict = NSDictionary(contentsOfFile: path) as? [String: [String]]
		else {
			return [:]
		}
		var result: [String: String] = [:]
		for (imageName, extensions) in dict {
			for ext in extensions {
				result[ext.lowercased()] = imageName
			}
		}
		return result
	}()

	/// Image cache for named bundle images (SCM badges, custom icons).
	private static var namedImageCache: [String: NSImage] = [:]

	/// Load a named `.icns` from the app bundle's `DocumentTypes` subdirectory.
	private static func namedImage(_ name: String) -> NSImage? {
		if let cached = namedImageCache[name] { return cached }
		guard let imageURL = Bundle.main.url(
			forResource: name, withExtension: "icns", subdirectory: "DocumentTypes",
		) else { return nil }
		guard let image = NSImage(contentsOf: imageURL) else { return nil }
		namedImageCache[name] = image
		return image
	}

	private func composeImage() -> NSImage {
		NSImage(size: NSSize(width: 16, height: 16), flipped: false) { [url, scmStatus] rect in
			var drawLinkBadge = false
			var baseImage: NSImage?

			if scmStatus == .deleted {
				// Deleted files get a generic unknown icon
				baseImage = NSWorkspace.shared.icon(for: .item)
			} else if let url, url.isFileURL {
				// Try custom bindings first (for non-directories)
				if !url.hasDirectoryPath {
					let pathName = url.lastPathComponent.lowercased()
					var imageName = FileReference.customBindings[pathName]

					if imageName == nil, let dotRange = pathName.range(of: ".") {
						let afterDot = String(pathName[dotRange.upperBound...])
						imageName = FileReference.customBindings[afterDot]
						if imageName == nil {
							imageName = FileReference.customBindings[url.pathExtension.lowercased()]
						}
					}

					if let name = imageName, let custom = FileReference.namedImage(name) {
						baseImage = custom
						// Check for symlink
						do {
							let resourceValues = try url.resourceValues(forKeys: [.fileResourceTypeKey])
							drawLinkBadge = resourceValues.fileResourceType == .symbolicLink
						} catch {
							os_log(
								.error,
								"No fileResourceType for %{public}@: %{public}@",
								url.path,
								error.localizedDescription,
							)
						}
					}
				}

				// Fall back to system-provided effective icon
				if baseImage == nil {
					do {
						let resourceValues = try url.resourceValues(forKeys: [.effectiveIconKey])
						baseImage = resourceValues.effectiveIcon as? NSImage
					} catch {
						os_log(
							.error,
							"No effectiveIcon for %{public}@: %{public}@",
							url.absoluteString,
							error.localizedDescription,
						)
						return false
					}
				}
			} else if let url {
				// Non-file URLs
				if url.scheme == "computer" {
					baseImage = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
						?? NSImage(named: NSImage.computerName)
				} else if url.hasDirectoryPath {
					baseImage = NSWorkspace.shared.icon(for: .folder)
				} else {
					baseImage = NSWorkspace.shared.icon(for: .item)
				}
			}

			// Draw base icon
			if let img = baseImage {
				img.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
			}

			// SCM badge overlay
			if scmStatus != .none {
				let badgeName: String? = switch scmStatus {
				case .conflicted: "scm-badge-conflicted"
				case .modified: "scm-badge-modified"
				case .added: "scm-badge-added"
				case .deleted: "scm-badge-deleted"
				case .unversioned: "scm-badge-unversioned"
				case .mixed: "scm-badge-mixed"
				case .none: nil
				}
				if let name = badgeName, let badge = FileReference.namedImage(name) {
					badge.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
				}
			}

			// Symlink badge
			if drawLinkBadge {
				if let badge = NSImage(systemSymbolName: "link", accessibilityDescription: "Alias") {
					badge.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
				}
			}

			return true
		}
	}
}
