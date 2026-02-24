import Foundation

/// A learned abbreviation→string binding, stored in MRU order.
///
/// Port of TextMate's `OakAbbreviations` — when a user selects an item from the
/// chooser, the filter string is learned as an abbreviation for that item's identifier.
/// On subsequent searches, items with learned bindings get boosted rank.
public final class AbbreviationStore: Sendable {
	/// Named singleton instances (e.g. "OakFileChooserBindings").
	private static let instances = NSLock.protect([:] as [String: AbbreviationStore])

	/// Get or create a named abbreviation store.
	public static func named(_ name: String) -> AbbreviationStore {
		instances.withLock { stores in
			if let existing = stores[name] {
				return existing
			}
			let store = AbbreviationStore(name: name)
			stores[name] = store
			return store
		}
	}

	/// Maximum number of entries to persist.
	public static let maxEntries = 50

	/// Storage name, used as UserDefaults key.
	public let name: String

	/// Internal storage: array of (abbreviation, fullString) pairs in MRU order.
	private let entries = NSLock.protect([] as [(abbreviation: String, fullString: String)])

	private init(name: String) {
		self.name = name
		loadFromDefaults()
	}

	// MARK: - Public API

	/// Look up all strings associated with an abbreviation.
	///
	/// Returns exact matches first, then prefix matches, all in MRU order.
	public func strings(for abbreviation: String) -> [String] {
		let allEntries = entries.withLock { $0 }

		var exact: [String] = []
		var prefix: [String] = []

		for entry in allEntries {
			if entry.abbreviation == abbreviation {
				exact.append(entry.fullString)
			} else if entry.abbreviation.hasPrefix(abbreviation) {
				prefix.append(entry.fullString)
			}
		}

		return exact + prefix
	}

	/// Learn an abbreviation→string binding.
	///
	/// If the binding already exists, it's moved to the front (MRU).
	/// The store is saved to UserDefaults after learning.
	public func learn(abbreviation: String, for fullString: String) {
		entries.withLock { entries in
			// Remove existing entry if present
			entries.removeAll { $0.abbreviation == abbreviation && $0.fullString == fullString }
			// Insert at front (MRU)
			entries.insert((abbreviation: abbreviation, fullString: fullString), at: 0)
			// Cap at maxEntries
			if entries.count > Self.maxEntries {
				entries.removeLast(entries.count - Self.maxEntries)
			}
		}
		saveToDefaults()
	}

	/// Remove all learned abbreviations.
	public func clear() {
		entries.withLock { $0.removeAll() }
		saveToDefaults()
	}

	/// Number of stored bindings.
	public var count: Int {
		entries.withLock(\.count)
	}

	/// All stored bindings (for testing/inspection).
	public var allBindings: [(abbreviation: String, fullString: String)] {
		entries.withLock { $0 }
	}

	/// Compute a rank boost for a candidate based on learned bindings.
	///
	/// - Parameters:
	///   - abbreviation: The current filter string.
	///   - candidate: The candidate identifier (path, UUID, etc.).
	/// - Returns: A boost value > 0 if the candidate has a learned binding, or `nil`.
	public func rankBoost(abbreviation: String, candidate: String) -> Double? {
		let matched = strings(for: abbreviation)
		guard let index = matched.firstIndex(of: candidate) else { return nil }
		let count = max(matched.count, 1)
		return 2.0 + Double(index) / Double(count)
	}

	// MARK: - Persistence

	private func loadFromDefaults() {
		guard let array = UserDefaults.standard.array(forKey: name) as? [[String: String]] else {
			return
		}
		entries.withLock { entries in
			entries = array.compactMap { dict in
				guard let short = dict["short"], let long = dict["long"] else { return nil }
				return (abbreviation: short, fullString: long)
			}
		}
	}

	private func saveToDefaults() {
		let array = entries.withLock { entries in
			entries.map { ["short": $0.abbreviation, "long": $0.fullString] }
		}
		UserDefaults.standard.set(array, forKey: name)
	}
}

// MARK: - NSLock Helper

private extension NSLock {
	/// Create a lock-protected value.
	static func protect<T>(_ value: T) -> LockedValue<T> {
		LockedValue(value)
	}
}

/// A thread-safe wrapper around a value protected by an NSLock.
final class LockedValue<T>: @unchecked Sendable {
	private var value: T
	private let lock = NSLock()

	init(_ value: T) {
		self.value = value
	}

	func withLock<R>(_ body: (inout T) throws -> R) rethrows -> R {
		lock.lock()
		defer { lock.unlock() }
		return try body(&value)
	}

	func withLock<R>(_ keyPath: KeyPath<T, R>) -> R {
		lock.lock()
		defer { lock.unlock() }
		return value[keyPath: keyPath]
	}
}
