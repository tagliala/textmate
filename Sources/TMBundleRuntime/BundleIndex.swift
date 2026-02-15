import Foundation

// MARK: - Item Kind

/// The type of a bundle item, matching the C++ `kind_t` bitmask.
public struct BundleItemKind: OptionSet, Sendable, Codable, Hashable {
	public let rawValue: UInt32

	public init(rawValue: UInt32) {
		self.rawValue = rawValue
	}

	public static let command = BundleItemKind(rawValue: 1 << 0)
	public static let dragCommand = BundleItemKind(rawValue: 1 << 1)
	public static let grammar = BundleItemKind(rawValue: 1 << 2)
	public static let macro = BundleItemKind(rawValue: 1 << 3)
	public static let settings = BundleItemKind(rawValue: 1 << 4)
	public static let snippet = BundleItemKind(rawValue: 1 << 5)
	public static let proxy = BundleItemKind(rawValue: 1 << 6)
	public static let theme = BundleItemKind(rawValue: 1 << 7)
	public static let bundle = BundleItemKind(rawValue: 1 << 8)
	public static let menu = BundleItemKind(rawValue: 1 << 9)
	public static let menuSeparator = BundleItemKind(rawValue: 1 << 10)
	public static let unknown = BundleItemKind(rawValue: 1 << 11)

	/// All executable kinds.
	public static let executable: BundleItemKind = [.command, .dragCommand, .snippet, .macro]

	/// All item kinds.
	public static let all: BundleItemKind = .init(rawValue: 0xFFFF)
}

// MARK: - Menu Structure

/// A node in a bundle's menu tree.
public enum BundleMenuItem: Sendable, Equatable, Identifiable {
	case item(uuid: String)
	case separator
	case submenu(title: String, children: [BundleMenuItem])

	public var id: String {
		switch self {
		case let .item(uuid): uuid
		case .separator: UUID().uuidString
		case let .submenu(title, _): "submenu-\(title)"
		}
	}
}

// MARK: - Bundle Item

/// A single item within a bundle (command, snippet, grammar, etc.).
public final class BundleItem: @unchecked Sendable {
	public let uuid: String
	public let name: String
	public let kind: BundleItemKind
	public let scopeSelector: String
	public let bundleUUID: String
	public let tabTrigger: String?
	public let keyEquivalent: String?
	public let semanticClass: String?

	/// The raw plist dictionary, protected by a lock.
	private var _plist: [String: Any]?
	private let _plistLock = NSLock()

	/// On-disk file paths where this item is defined.
	public let paths: [String]

	/// Whether the item is disabled (hidden from menus).
	public let isDisabled: Bool

	public init(
		uuid: String,
		name: String,
		kind: BundleItemKind,
		scopeSelector: String = "",
		bundleUUID: String,
		tabTrigger: String? = nil,
		keyEquivalent: String? = nil,
		semanticClass: String? = nil,
		plist: [String: Any]? = nil,
		paths: [String] = [],
		isDisabled: Bool = false,
	) {
		self.uuid = uuid
		self.name = name
		self.kind = kind
		self.scopeSelector = scopeSelector
		self.bundleUUID = bundleUUID
		self.tabTrigger = tabTrigger
		self.keyEquivalent = keyEquivalent
		self.semanticClass = semanticClass
		_plist = plist
		self.paths = paths
		self.isDisabled = isDisabled
	}

	/// Returns the plist dictionary for this item.
	public var plist: [String: Any]? {
		_plistLock.lock()
		defer { _plistLock.unlock() }
		return _plist
	}

	/// Sets the plist dictionary (used during loading).
	public func setPlist(_ dict: [String: Any]) {
		_plistLock.lock()
		defer { _plistLock.unlock() }
		_plist = dict
	}
}

// MARK: - Bundle Descriptor

/// Metadata for a single bundle (collection of items).
public struct BundleDescriptor: Sendable, Identifiable, Equatable {
	public let uuid: String
	public let name: String
	public let path: String
	public let category: String
	public let contactName: String
	public let contactEmailRot13: String
	public let summary: String
	public let isEnabled: Bool
	public let isDependency: Bool
	public let menuItems: [BundleMenuItem]

	public var id: String {
		uuid
	}

	public init(
		uuid: String,
		name: String,
		path: String = "",
		category: String = "",
		contactName: String = "",
		contactEmailRot13: String = "",
		summary: String = "",
		isEnabled: Bool = true,
		isDependency: Bool = false,
		menuItems: [BundleMenuItem] = [],
	) {
		self.uuid = uuid
		self.name = name
		self.path = path
		self.category = category
		self.contactName = contactName
		self.contactEmailRot13 = contactEmailRot13
		self.summary = summary
		self.isEnabled = isEnabled
		self.isDependency = isDependency
		self.menuItems = menuItems
	}
}

// MARK: - Query Parameters

/// Parameters for searching the bundle index.
public struct BundleQuery: Sendable {
	/// Match by field (e.g., tabTrigger, keyEquivalent, scopeSelector).
	public let field: QueryField?
	/// Match value for the field.
	public let value: String?
	/// Only match items with this scope selector.
	public let scope: String?
	/// Only match items of these kinds.
	public let kinds: BundleItemKind
	/// Only match items in this bundle.
	public let bundleUUID: String?
	/// Include disabled items in results.
	public let includeDisabled: Bool

	public init(
		field: QueryField? = nil,
		value: String? = nil,
		scope: String? = nil,
		kinds: BundleItemKind = .all,
		bundleUUID: String? = nil,
		includeDisabled: Bool = false,
	) {
		self.field = field
		self.value = value
		self.scope = scope
		self.kinds = kinds
		self.bundleUUID = bundleUUID
		self.includeDisabled = includeDisabled
	}

	/// Queryable fields on bundle items.
	public enum QueryField: String, Sendable {
		case tabTrigger
		case keyEquivalent
		case scopeSelector
		case semanticClass
		case grammarScope
		case name
		case uuid
	}
}

// MARK: - Bundle Index

/// Global queryable index of all loaded bundle items, thread-safe.
///
/// Mirrors the C++ `bundles::set_index()` / `bundles::query()` API.
/// Items are added via `setIndex(items:bundles:)` and queried
/// via `query(_:)` or `lookup(uuid:)`.
public final class BundleIndex: @unchecked Sendable {
	private var items: [BundleItem] = []
	private var bundles: [BundleDescriptor] = []
	private var itemsByUUID: [String: BundleItem] = [:]
	private var bundlesByUUID: [String: BundleDescriptor] = [:]
	private var itemsByTabTrigger: [String: [BundleItem]] = [:]
	private var itemsByKeyEquivalent: [String: [BundleItem]] = [:]
	private var itemsByBundleUUID: [String: [BundleItem]] = [:]
	private let lock = NSLock()

	/// Notifications posted when the index changes.
	public static let didChangeNotification = Notification.Name("TMBundleIndexDidChange")

	/// Callback type for index change events.
	public typealias ChangeCallback = @Sendable () -> Void
	private var callbacks: [UUID: ChangeCallback] = [:]

	public init() {}

	// MARK: - Index Population

	/// Replaces the entire index atomically.
	public func setIndex(items newItems: [BundleItem], bundles newBundles: [BundleDescriptor]) {
		lock.lock()
		items = newItems
		bundles = newBundles

		// Rebuild indices.
		itemsByUUID = [:]
		itemsByTabTrigger = [:]
		itemsByKeyEquivalent = [:]
		itemsByBundleUUID = [:]
		bundlesByUUID = [:]

		for item in newItems {
			itemsByUUID[item.uuid] = item
			if let trigger = item.tabTrigger, !trigger.isEmpty {
				itemsByTabTrigger[trigger, default: []].append(item)
			}
			if let key = item.keyEquivalent, !key.isEmpty {
				itemsByKeyEquivalent[key, default: []].append(item)
			}
			itemsByBundleUUID[item.bundleUUID, default: []].append(item)
		}
		for b in newBundles {
			bundlesByUUID[b.uuid] = b
		}

		let cbs = callbacks.values
		lock.unlock()

		for cb in cbs {
			cb()
		}
		NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
	}

	/// Adds items to the index incrementally.
	public func addItems(_ newItems: [BundleItem]) {
		lock.lock()
		for item in newItems {
			items.append(item)
			itemsByUUID[item.uuid] = item
			if let trigger = item.tabTrigger, !trigger.isEmpty {
				itemsByTabTrigger[trigger, default: []].append(item)
			}
			if let key = item.keyEquivalent, !key.isEmpty {
				itemsByKeyEquivalent[key, default: []].append(item)
			}
			itemsByBundleUUID[item.bundleUUID, default: []].append(item)
		}
		let cbs = callbacks.values
		lock.unlock()

		for cb in cbs {
			cb()
		}
		NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
	}

	/// Removes an item by UUID.
	public func removeItem(uuid: String) {
		lock.lock()
		if let item = itemsByUUID.removeValue(forKey: uuid) {
			items.removeAll { $0.uuid == uuid }
			if let trigger = item.tabTrigger {
				itemsByTabTrigger[trigger]?.removeAll { $0.uuid == uuid }
			}
			if let key = item.keyEquivalent {
				itemsByKeyEquivalent[key]?.removeAll { $0.uuid == uuid }
			}
			itemsByBundleUUID[item.bundleUUID]?.removeAll { $0.uuid == uuid }
		}
		let cbs = callbacks.values
		lock.unlock()

		for cb in cbs {
			cb()
		}
	}

	// MARK: - Query

	/// Finds items matching the query parameters.
	public func query(_ q: BundleQuery) -> [BundleItem] {
		lock.lock()
		defer { lock.unlock() }

		var candidates: [BundleItem]

		// Use index for specific field lookups.
		if let field = q.field, let value = q.value {
			switch field {
			case .uuid:
				if let item = itemsByUUID[value] {
					candidates = [item]
				} else {
					return []
				}
			case .tabTrigger:
				candidates = itemsByTabTrigger[value] ?? []
			case .keyEquivalent:
				candidates = itemsByKeyEquivalent[value] ?? []
			default:
				candidates = items
			}
		} else if let bundleUUID = q.bundleUUID {
			candidates = itemsByBundleUUID[bundleUUID] ?? []
		} else {
			candidates = items
		}

		return candidates.filter { item in
			// Kind filter.
			guard item.kind.intersection(q.kinds) != [] else { return false }
			// Disabled filter.
			if item.isDisabled, !q.includeDisabled { return false }
			// Bundle filter.
			if let bundleUUID = q.bundleUUID, item.bundleUUID != bundleUUID { return false }
			// Field filter (for non-indexed fields).
			if let field = q.field, let value = q.value {
				switch field {
				case .name:
					if item.name != value { return false }
				case .scopeSelector:
					if item.scopeSelector != value { return false }
				case .semanticClass:
					if item.semanticClass != value { return false }
				case .grammarScope:
					// Match on scope selector for grammars.
					if !item.kind.contains(.grammar) { return false }
					if item.scopeSelector != value { return false }
				case .uuid, .tabTrigger, .keyEquivalent:
					break // Already handled above.
				}
			}
			return true
		}
	}

	/// Looks up a single item by UUID.
	public func lookup(uuid: String) -> BundleItem? {
		lock.lock()
		defer { lock.unlock() }
		return itemsByUUID[uuid]
	}

	/// Returns all bundles.
	public var allBundles: [BundleDescriptor] {
		lock.lock()
		defer { lock.unlock() }
		return bundles
	}

	/// Returns all items in a specific bundle.
	public func items(inBundle uuid: String) -> [BundleItem] {
		lock.lock()
		defer { lock.unlock() }
		return itemsByBundleUUID[uuid] ?? []
	}

	/// Returns the bundle descriptor for a given UUID.
	public func bundle(uuid: String) -> BundleDescriptor? {
		lock.lock()
		defer { lock.unlock() }
		return bundlesByUUID[uuid]
	}

	/// Total number of items in the index.
	public var itemCount: Int {
		lock.lock()
		defer { lock.unlock() }
		return items.count
	}

	// MARK: - Change Observation

	/// Registers a callback for index changes. Returns an ID for removal.
	@discardableResult
	public func addChangeCallback(_ callback: @escaping ChangeCallback) -> UUID {
		lock.lock()
		defer { lock.unlock() }
		let id = UUID()
		callbacks[id] = callback
		return id
	}

	/// Removes a previously registered callback.
	public func removeChangeCallback(id: UUID) {
		lock.lock()
		defer { lock.unlock() }
		callbacks.removeValue(forKey: id)
	}
}
