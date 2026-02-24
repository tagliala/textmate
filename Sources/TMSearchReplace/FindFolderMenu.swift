#if canImport(AppKit)
import AppKit

// MARK: - Find Folder Menu

/// A menu delegate that lazily populates subfolder menus for a given root path — equivalent to `FFFolderMenu`.
///
/// Attach an instance as the delegate of a submenu. When the menu opens,
/// it enumerates visible directories at the represented path and adds items
/// for each subfolder, recursively attaching submenus for further browsing.
@MainActor
public final class FindFolderMenu: NSObject, NSMenuDelegate, Sendable {
	/// Shared singleton for reuse across popups.
	public static let shared = FindFolderMenu()

	/// The selector sent when a folder is chosen from the menu.
	public var folderAction: Selector?

	/// The target for the folder action.
	public weak var folderTarget: AnyObject?

	override private init() {
		super.init()
	}

	// MARK: - Public API

	/// Configure a menu item with a submenu that browses the given directory.
	public func addSubmenu(forDirectoryAtPath path: String, to menuItem: NSMenuItem) {
		menuItem.representedObject = path
		let sub = NSMenu()
		sub.delegate = self
		menuItem.submenu = sub
	}

	// MARK: - NSMenuDelegate

	public func menuNeedsUpdate(_ menu: NSMenu) {
		guard menu.numberOfItems == 0 else { return }

		guard let parentItem = menu.supermenu?.items.first(where: { $0.submenu === menu }),
		      let folder = parentItem.representedObject as? String
		else { return }

		let subfolders = subfolders(at: folder)
		for path in subfolders {
			let item = menu.addItem(
				withTitle: FileManager.default.displayName(atPath: path),
				action: folderAction,
				keyEquivalent: "",
			)
			item.target = folderTarget
			item.representedObject = path

			if !self.subfolders(at: path).isEmpty {
				addSubmenu(forDirectoryAtPath: path, to: item)
			}
		}

		// Add enclosing folders for root menu
		if parentItem.parent == nil, folder != "/" {
			if menu.numberOfItems > 0 {
				menu.addItem(.separator())
			}
			let header = menu.addItem(withTitle: "Enclosing Folders", action: nil, keyEquivalent: "")
			header.isEnabled = false

			var current = (folder as NSString).deletingLastPathComponent
			while !current.isEmpty {
				let item = menu.addItem(
					withTitle: FileManager.default.displayName(atPath: current),
					action: folderAction,
					keyEquivalent: "",
				)
				item.target = folderTarget
				item.representedObject = current

				if current == "/" { break }
				current = (current as NSString).deletingLastPathComponent
			}
		}
	}

	public func menuHasKeyEquivalent(
		_: NSMenu,
		for _: NSEvent,
		target _: AutoreleasingUnsafeMutablePointer<AnyObject?>,
		action _: UnsafeMutablePointer<Selector?>,
	) -> Bool {
		false
	}

	// MARK: - Private

	private func subfolders(at path: String) -> [String] {
		let fm = FileManager.default
		var isDir: ObjCBool = false
		guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return [] }

		guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }

		var folders: [String] = []
		for name in contents {
			guard !name.hasPrefix(".") else { continue }
			let fullPath = (path as NSString).appendingPathComponent(name)
			var childIsDir: ObjCBool = false
			guard fm.fileExists(atPath: fullPath, isDirectory: &childIsDir), childIsDir.boolValue else { continue }

			// Skip packages
			if NSWorkspace.shared.isFilePackage(atPath: fullPath) { continue }

			folders.append(fullPath)
		}

		folders.sort { a, b in
			let nameA = ((a as NSString).deletingPathExtension as NSString).lastPathComponent
			let nameB = ((b as NSString).deletingPathExtension as NSString).lastPathComponent
			return nameA.localizedStandardCompare(nameB) == .orderedAscending
		}

		return folders
	}
}
#endif
