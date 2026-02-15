import Foundation

// MARK: - Bundle Locations

/// Standard paths where TextMate bundles are stored.
public enum BundleLocations {
	/// Returns all standard bundle search paths in priority order.
	/// Later paths have higher priority (user overrides system).
	public static func searchPaths() -> [String] {
		var paths: [String] = []

		// System bundles shipped with TextMate.
		if let appSupport = Bundle.main.builtInPlugInsPath {
			let bundled = (appSupport as NSString).deletingLastPathComponent + "/Bundles"
			paths.append(bundled)
		}

		// /Library/Application Support/TextMate/Bundles
		for domain in FileManager.SearchPathDomainMask.allDomains {
			let dirs = NSSearchPathForDirectoriesInDomains(
				.applicationSupportDirectory,
				domain,
				true,
			)
			for dir in dirs {
				paths.append((dir as NSString).appendingPathComponent("TextMate/Bundles"))
				paths.append(
					(dir as NSString).appendingPathComponent("TextMate/Managed/Bundles"),
				)
			}
		}

		// ~/Library/Application Support/TextMate/Pristine Copy/Bundles
		if let userAppSupport = NSSearchPathForDirectoriesInDomains(
			.applicationSupportDirectory,
			.userDomainMask,
			true,
		).first {
			paths.append(
				(userAppSupport as NSString)
					.appendingPathComponent("TextMate/Pristine Copy/Bundles"),
			)
		}

		return paths
	}

	/// The user's bundle directory for custom/edited bundles.
	public static var userBundlesPath: String {
		let appSupport = NSSearchPathForDirectoriesInDomains(
			.applicationSupportDirectory,
			.userDomainMask,
			true,
		).first ?? "~/Library/Application Support"
		return (appSupport as NSString).appendingPathComponent("TextMate/Bundles")
	}

	/// The managed bundles directory (for downloaded/installed bundles).
	public static var managedBundlesPath: String {
		let appSupport = NSSearchPathForDirectoriesInDomains(
			.applicationSupportDirectory,
			.userDomainMask,
			true,
		).first ?? "~/Library/Application Support"
		return (appSupport as NSString).appendingPathComponent("TextMate/Managed/Bundles")
	}
}

private extension FileManager.SearchPathDomainMask {
	static var allDomains: [FileManager.SearchPathDomainMask] {
		[.userDomainMask, .localDomainMask, .networkDomainMask]
	}
}

// MARK: - Bundle Loader

/// Discovers `.tmbundle` directories on disk, parses their plists,
/// and produces `BundleItem` and `BundleDescriptor` objects for the index.
public struct BundleLoader: Sendable {
	/// The file types within a `.tmbundle` and their corresponding item kinds.
	static let itemSubdirectories: [(directory: String, kind: BundleItemKind, plistKey: String)] = [
		("Commands", .command, "command"),
		("DragCommands", .dragCommand, "command"),
		("Snippets", .snippet, "content"),
		("Macros", .macro, "commands"),
		("Syntaxes", .grammar, "patterns"),
		("Preferences", .settings, "settings"),
		("Themes", .theme, "settings"),
	]

	/// File extensions recognized as bundle item plists.
	static let plistExtensions: Set<String> = [
		"tmCommand", "tmSnippet", "tmLanguage", "tmPreferences",
		"tmMacro", "tmTheme", "tmDragCommand", "plist",
	]

	public init() {}

	// MARK: - Loading

	/// Scans all standard paths and returns discovered items and bundles.
	public func loadAll() -> (items: [BundleItem], bundles: [BundleDescriptor]) {
		let paths = BundleLocations.searchPaths()
		return loadFromPaths(paths)
	}

	/// Scans specific paths for `.tmbundle` directories.
	public func loadFromPaths(_ searchPaths: [String]) -> (
		items: [BundleItem],
		bundles: [BundleDescriptor],
	) {
		let fm = FileManager.default
		var allItems: [BundleItem] = []
		var allBundles: [BundleDescriptor] = []

		for searchPath in searchPaths {
			guard fm.fileExists(atPath: searchPath) else { continue }

			let contents = (try? fm.contentsOfDirectory(atPath: searchPath)) ?? []
			for entry in contents where entry.hasSuffix(".tmbundle") {
				let bundlePath = (searchPath as NSString).appendingPathComponent(entry)
				if let (descriptor, items) = loadBundle(at: bundlePath) {
					allBundles.append(descriptor)
					allItems.append(contentsOf: items)
				}
			}
		}

		return (items: allItems, bundles: allBundles)
	}

	/// Loads a single `.tmbundle` directory.
	public func loadBundle(at path: String) -> (
		BundleDescriptor,
		[BundleItem],
	)? {
		let fm = FileManager.default
		let infoPlist = (path as NSString).appendingPathComponent("info.plist")

		guard fm.fileExists(atPath: infoPlist),
		      let data = fm.contents(atPath: infoPlist),
		      let dict = parsePlist(data)
		else {
			return nil
		}

		guard let uuid = dict["uuid"] as? String,
		      let name = dict["name"] as? String
		else {
			return nil
		}

		// Parse menu structure.
		let menuItems = parseMenuStructure(
			dict["mainMenu"] as? [String: Any],
			allItems: nil,
		)

		let descriptor = BundleDescriptor(
			uuid: uuid,
			name: name,
			path: path,
			category: dict["category"] as? String ?? "",
			contactName: dict["contactName"] as? String ?? "",
			contactEmailRot13: dict["contactEmailRot13"] as? String ?? "",
			summary: dict["description"] as? String ?? "",
			isEnabled: !(dict["isDisabled"] as? Bool ?? false),
			isDependency: dict["isDependency"] as? Bool ?? false,
			menuItems: menuItems,
		)

		// Load all items in subdirectories.
		var items: [BundleItem] = []
		for (subdir, kind, _) in Self.itemSubdirectories {
			let subdirPath = (path as NSString).appendingPathComponent(subdir)
			guard fm.fileExists(atPath: subdirPath) else { continue }

			let entries = (try? fm.contentsOfDirectory(atPath: subdirPath)) ?? []
			for entry in entries {
				let ext = (entry as NSString).pathExtension
				guard Self.plistExtensions.contains(ext) || ext == "plist" else { continue }

				let itemPath = (subdirPath as NSString).appendingPathComponent(entry)
				if let item = loadItem(at: itemPath, kind: kind, bundleUUID: uuid) {
					items.append(item)
				}
			}
		}

		return (descriptor, items)
	}

	/// Loads a single bundle item plist.
	public func loadItem(
		at path: String,
		kind: BundleItemKind,
		bundleUUID: String,
	) -> BundleItem? {
		guard let data = FileManager.default.contents(atPath: path),
		      let dict = parsePlist(data)
		else {
			return nil
		}

		guard let uuid = dict["uuid"] as? String,
		      let name = dict["name"] as? String
		else {
			return nil
		}

		return BundleItem(
			uuid: uuid,
			name: name,
			kind: kind,
			scopeSelector: dict["scope"] as? String ?? "",
			bundleUUID: bundleUUID,
			tabTrigger: dict["tabTrigger"] as? String,
			keyEquivalent: dict["keyEquivalent"] as? String,
			semanticClass: dict["semanticClass"] as? String,
			plist: dict,
			paths: [path],
			isDisabled: dict["isDisabled"] as? Bool ?? false,
		)
	}

	// MARK: - Menu Parsing

	/// Parses the `mainMenu` dictionary into a `BundleMenuItem` tree.
	func parseMenuStructure(
		_ mainMenu: [String: Any]?,
		allItems _: [String: BundleItem]?,
	) -> [BundleMenuItem] {
		guard let mainMenu,
		      let items = mainMenu["items"] as? [String]
		else {
			return []
		}

		let submenus = mainMenu["submenus"] as? [String: [String: Any]] ?? [:]

		return items.compactMap { uuid -> BundleMenuItem? in
			if uuid == "----" || uuid == "-" {
				return .separator
			}
			if let submenu = submenus[uuid] {
				let title = submenu["name"] as? String ?? "Untitled"
				let childUUIDs = submenu["items"] as? [String] ?? []
				let children = childUUIDs.compactMap { childUUID -> BundleMenuItem? in
					if childUUID == "----" || childUUID == "-" {
						return .separator
					}
					return .item(uuid: childUUID)
				}
				return .submenu(title: title, children: children)
			}
			return .item(uuid: uuid)
		}
	}

	// MARK: - Plist Parsing

	/// Parses a plist file into a dictionary.
	private func parsePlist(_ data: Data) -> [String: Any]? {
		// Try binary/XML plist first.
		if let dict = try? PropertyListSerialization.propertyList(
			from: data,
			options: [],
			format: nil,
		) as? [String: Any] {
			return dict
		}
		return nil
	}
}
