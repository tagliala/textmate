import Foundation

/// A most-recently-used (MRU) list backed by `UserDefaults`.
///
/// Items are stored in insertion-recency order: the most recently
/// used item is always at the front.  A maximum capacity keeps the
/// list bounded — when the limit is exceeded the least recently
/// used item is evicted.
///
/// This is the Swift equivalent of `OakHistoryList` from the C++
/// `OakFoundation` framework.
///
/// ## Thread Safety
///
/// Access is **not** synchronised.  Callers must serialise mutations
/// when used from multiple threads.
///
/// ## Persistence
///
/// Changes are automatically written to `UserDefaults` under the
/// key given at initialisation.  The stored representation is a
/// property-list–compatible array of strings.
public struct UserDefaultsHistoryList: @unchecked Sendable {
	/// Current items in MRU order (most recent first).
	public private(set) var items: [String]

	/// Maximum number of items stored.
	public let capacity: Int

	/// The `UserDefaults` key under which the list is persisted.
	public let defaultsKey: String

	/// The `UserDefaults` instance used for persistence.
	private let defaults: UserDefaults

	/// Creates a history list backed by the given `UserDefaults` key.
	///
	/// - Parameters:
	///   - key: The `UserDefaults` key for persistence.
	///   - capacity: Maximum number of items to retain.
	///   - defaults: The `UserDefaults` instance (default: `.standard`).
	public init(
		key: String,
		capacity: Int = 25,
		defaults: UserDefaults = .standard,
	) {
		defaultsKey = key
		self.capacity = max(capacity, 1)
		self.defaults = defaults
		items = (defaults.stringArray(forKey: key) ?? []).prefix(max(capacity, 1)).map(\.self)
	}

	/// Records `item` as the most recently used.
	///
	/// If `item` is already in the list it moves to the front.
	/// Otherwise, it is inserted at the front and the list is
	/// trimmed to ``capacity``.
	public mutating func use(_ item: String) {
		items.removeAll { $0 == item }
		items.insert(item, at: 0)
		if items.count > capacity {
			items = Array(items.prefix(capacity))
		}
		persist()
	}

	/// Removes `item` from the list if present.
	public mutating func remove(_ item: String) {
		items.removeAll { $0 == item }
		persist()
	}

	/// Removes all items.
	public mutating func removeAll() {
		items.removeAll()
		persist()
	}

	/// The most recently used item, or `nil` if empty.
	public var current: String? {
		items.first
	}

	/// Whether the list is empty.
	public var isEmpty: Bool {
		items.isEmpty
	}

	/// The number of items in the list.
	public var count: Int {
		items.count
	}

	// MARK: - Private

	private func persist() {
		defaults.set(items, forKey: defaultsKey)
	}
}
