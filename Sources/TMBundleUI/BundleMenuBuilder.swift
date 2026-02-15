#if canImport(AppKit)
import AppKit
import TMBundleRuntime

// MARK: - Bundle Menu Builder

/// Builds and dynamically populates NSMenus from the bundle index,
/// mirroring the C++ `BundleMenuDelegate` pattern.
///
/// Menu items are rebuilt on each `menuNeedsUpdate:` call using
/// the current scope context. Each menu item stores the bundle
/// item UUID as its `representedObject` and uses a responder-chain
/// action for dispatch.
@MainActor
public final class BundleMenuBuilder: NSObject, NSMenuDelegate {
	/// The bundle index to query for items.
	public let bundleIndex: BundleIndex

	/// The action sent by menu items (travels up the responder chain).
	public static let bundleItemAction = #selector(
		BundleMenuActionTarget.performBundleItem(sender:)
	)

	/// Callback to get the current scope context for filtering.
	public var scopeProvider: (() -> String)?

	public init(bundleIndex: BundleIndex) {
		self.bundleIndex = bundleIndex
		super.init()
	}

	// MARK: - Menu Creation

	/// Creates the top-level "Bundles" menu.
	public func createBundlesMenu() -> NSMenu {
		let menu = NSMenu(title: "Bundles")
		menu.delegate = self
		return menu
	}

	/// Creates a submenu for a specific bundle.
	public func createBundleMenu(bundleUUID: String) -> NSMenu {
		let bundle = bundleIndex.bundle(uuid: bundleUUID)
		let menu = NSMenu(title: bundle?.name ?? "Bundle")
		menu.identifier = NSUserInterfaceItemIdentifier(bundleUUID)
		menu.delegate = self
		return menu
	}

	// MARK: - NSMenuDelegate

	public func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		let scope = scopeProvider?() ?? ""

		if let bundleUUID = menu.identifier?.rawValue, !bundleUUID.isEmpty {
			// Submenu for a specific bundle — show its menu items.
			populateBundleMenu(menu, bundleUUID: bundleUUID, scope: scope)
		} else {
			// Top-level "Bundles" menu — show all bundles with items.
			populateTopLevelMenu(menu, scope: scope)
		}
	}

	// MARK: - Population

	/// Populates the top-level Bundles menu with one submenu per bundle.
	private func populateTopLevelMenu(_ menu: NSMenu, scope _: String) {
		let bundles = bundleIndex.allBundles
			.filter(\.isEnabled)
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		for bundle in bundles {
			let items = bundleIndex.items(inBundle: bundle.uuid)
			// Only show bundles that have executable items.
			let hasExecutable = items.contains { item in
				item.kind.intersection(.executable) != []
			}
			guard hasExecutable else { continue }

			let submenu = createBundleMenu(bundleUUID: bundle.uuid)
			let item = NSMenuItem(title: bundle.name, action: nil, keyEquivalent: "")
			item.submenu = submenu
			menu.addItem(item)
		}
	}

	/// Populates a bundle's submenu following its declared menu structure.
	private func populateBundleMenu(
		_ menu: NSMenu,
		bundleUUID: String,
		scope _: String,
	) {
		guard let bundle = bundleIndex.bundle(uuid: bundleUUID) else { return }

		if bundle.menuItems.isEmpty {
			// No declared menu structure — list all executable items alphabetically.
			let items = bundleIndex.items(inBundle: bundleUUID)
				.filter { $0.kind.intersection(.executable) != [] && !$0.isDisabled }
				.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

			for item in items {
				menu.addItem(createMenuItem(for: item))
			}
		} else {
			// Follow declared menu structure.
			for menuItem in bundle.menuItems {
				addMenuItem(menuItem, to: menu, bundleUUID: bundleUUID)
			}
		}
	}

	/// Recursively adds a `BundleMenuItem` to an `NSMenu`.
	private func addMenuItem(
		_ bundleMenuItem: BundleMenuItem,
		to menu: NSMenu,
		bundleUUID: String,
	) {
		switch bundleMenuItem {
		case .separator:
			menu.addItem(.separator())

		case let .item(uuid):
			if let item = bundleIndex.lookup(uuid: uuid), !item.isDisabled {
				menu.addItem(createMenuItem(for: item))
			}

		case let .submenu(title, children):
			let submenu = NSMenu(title: title)
			submenu.identifier = NSUserInterfaceItemIdentifier(bundleUUID)
			for child in children {
				addMenuItem(child, to: submenu, bundleUUID: bundleUUID)
			}
			let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
			menuItem.submenu = submenu
			menu.addItem(menuItem)
		}
	}

	/// Creates an `NSMenuItem` for a single bundle item.
	private func createMenuItem(for item: BundleItem) -> NSMenuItem {
		let menuItem = NSMenuItem(
			title: item.name,
			action: Self.bundleItemAction,
			keyEquivalent: "",
		)
		menuItem.representedObject = item.uuid

		// Set key equivalent if present.
		if let keyEquiv = item.keyEquivalent, !keyEquiv.isEmpty {
			let (key, modifiers) = parseKeyEquivalent(keyEquiv)
			menuItem.keyEquivalent = key
			menuItem.keyEquivalentModifierMask = modifiers
		}

		// Show tab trigger in the menu item.
		if let tabTrigger = item.tabTrigger, !tabTrigger.isEmpty {
			menuItem.toolTip = "Tab trigger: \(tabTrigger)⇥"
		}

		return menuItem
	}

	// MARK: - Key Equivalent Parsing

	/// Parses a TextMate key equivalent string into an NSMenuItem key + modifiers.
	///
	/// TextMate format uses modifier prefixes:
	/// - `^` = Control
	/// - `~` = Option
	/// - `$` = Shift
	/// - `@` = Command
	func parseKeyEquivalent(_ keyEquiv: String) -> (
		String, NSEvent.ModifierFlags,
	) {
		var modifiers: NSEvent.ModifierFlags = []
		var remaining = keyEquiv

		while !remaining.isEmpty {
			let ch = remaining.first!
			switch ch {
			case "^":
				modifiers.insert(.control)
				remaining.removeFirst()
			case "~":
				modifiers.insert(.option)
				remaining.removeFirst()
			case "$":
				modifiers.insert(.shift)
				remaining.removeFirst()
			case "@":
				modifiers.insert(.command)
				remaining.removeFirst()
			default:
				return (remaining.lowercased(), modifiers)
			}
		}

		return ("", modifiers)
	}
}

// MARK: - Action Target Protocol

/// Protocol for objects in the responder chain that handle bundle items.
@objc
public protocol BundleMenuActionTarget {
	@objc
	func performBundleItem(sender: Any?)
}

// MARK: - Disambiguation Menu

/// Shows a popup menu for disambiguating multiple bundle items
/// that match the same trigger, numbered 1–0 for quick selection.
@MainActor
public struct BundleDisambiguationMenu {
	/// Shows a popup menu at the given point and returns the selected UUID.
	/// Returns `nil` if the user cancels.
	public static func show(
		items: [BundleItem],
		at _: NSPoint,
		in view: NSView?,
	) -> String? {
		guard !items.isEmpty else { return nil }
		if items.count == 1 { return items[0].uuid }

		let menu = NSMenu(title: "")
		for (index, item) in items.enumerated() {
			let keyEquiv = if index < 9 {
				"\(index + 1)"
			} else if index == 9 {
				"0"
			} else {
				""
			}

			let menuItem = NSMenuItem(
				title: item.name,
				action: nil,
				keyEquivalent: keyEquiv,
			)
			menuItem.representedObject = item.uuid
			menu.addItem(menuItem)
		}

		guard let view else {
			return items.first?.uuid
		}

		let event = NSApplication.shared.currentEvent
		NSMenu.popUpContextMenu(menu, with: event ?? NSEvent(), for: view)
		return menu.highlightedItem?.representedObject as? String
	}
}
#endif
