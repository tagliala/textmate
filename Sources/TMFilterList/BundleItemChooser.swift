import Foundation

/// Search sources for the bundle item chooser.
public struct BundleSearchSource: OptionSet, Sendable {
	public let rawValue: Int
	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	public static let actionItems = BundleSearchSource(rawValue: 1 << 0)
	public static let settingsItems = BundleSearchSource(rawValue: 1 << 1)
	public static let grammarItems = BundleSearchSource(rawValue: 1 << 2)
	public static let themeItems = BundleSearchSource(rawValue: 1 << 3)
	public static let dragCommandItems = BundleSearchSource(rawValue: 1 << 4)
	public static let menuItems = BundleSearchSource(rawValue: 1 << 5)
	public static let keyBindingItems = BundleSearchSource(rawValue: 1 << 6)

	/// Actions + menu items + key bindings (the "Actions" tab).
	public static let actions: BundleSearchSource = [.actionItems, .menuItems, .keyBindingItems]
	/// Settings only (the "Settings" tab).
	public static let settings: BundleSearchSource = [.settingsItems]
	/// Grammars + themes (the "Other" tab).
	public static let other: BundleSearchSource = [.grammarItems, .themeItems]
	/// All sources.
	public static let all: BundleSearchSource = [
		.actionItems,
		.settingsItems,
		.grammarItems,
		.themeItems,
		.dragCommandItems,
		.menuItems,
		.keyBindingItems,
	]
}

/// Manages the state and filtering logic for the bundle item chooser (⌃⌘T).
///
/// Port of TextMate's `BundleItemChooser` — searches bundle items by title, key equivalent,
/// tab trigger, semantic class, or scope selector. Supports multiple search sources
/// and learned abbreviation boosting.
public final class BundleItemChooserState: @unchecked Sendable {
	// MARK: - Properties

	/// Current search sources.
	public var sources: BundleSearchSource = .actions

	/// Current search field.
	public var searchField: BundleChooserItem.SearchField = .title

	/// Current scope context (for filtering by scope).
	public var scopeContext: String?

	/// Whether the editor has a text selection.
	public var hasSelection: Bool = false

	/// Abbreviation store for learned bindings.
	public let abbreviations: AbbreviationStore

	/// All candidate bundle items (with their source tag for filtering).
	public var allItems: [(item: BundleChooserItem, source: BundleSearchSource)] = []

	/// Current filter string.
	public var rawFilter: String = ""

	/// Filtered and ranked results.
	public private(set) var filteredItems: [BundleChooserItem] = []

	// MARK: - Initialization

	public init() {
		abbreviations = AbbreviationStore.named("OakBundleItemChooserBindings")
	}

	// MARK: - Filtering

	/// Update the filter and recompute results.
	public func updateFilter(_ raw: String) {
		rawFilter = raw
		refilter()
	}

	/// Set the search field and refilter.
	public func setSearchField(_ field: BundleChooserItem.SearchField) {
		searchField = field
		refilter()
	}

	/// Set the search sources and refilter.
	public func setSources(_ newSources: BundleSearchSource) {
		sources = newSources
		refilter()
	}

	/// Refilter using the current settings.
	public func refilter() {
		let filter = FuzzyRanker.normalizeFilter(rawFilter)
		let bindings = abbreviations.strings(for: filter)
		let preserveOrder = searchField != .title || sources.contains(.settingsItems)

		// Apply source filter first
		var items = allItems
			.filter { sources.contains($0.source) }
			.map(\.item)
		let totalItems = items.count

		for i in items.indices {
			items[i].updateRank(
				filter: filter,
				field: searchField,
				bindings: bindings,
				preserveOrder: preserveOrder,
				orderIndex: i,
				totalItems: totalItems,
			)
		}

		filteredItems = items.filter(\.isMatched).sorted { a, b in
			if a.sortRank != b.sortRank {
				return a.sortRank < b.sortRank
			}
			if a.displayName != b.displayName {
				return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
			}
			return a.detail.localizedCaseInsensitiveCompare(b.detail) == .orderedAscending
		}
	}

	// MARK: - Abbreviation Learning

	/// Learn the current filter as an abbreviation for the selected item.
	public func learnSelection(identifier: String) {
		let filter = FuzzyRanker.normalizeFilter(rawFilter)
		guard !filter.isEmpty, searchField == .title else { return }
		abbreviations.learn(abbreviation: filter, for: identifier)
	}

	// MARK: - Item Population

	/// Populate items from a list of bundle item descriptors.
	///
	/// Each descriptor provides the minimum information needed for filtering.
	/// The actual bundle item resolution is deferred to when the user makes a selection.
	public func populateItems(_ descriptors: [BundleItemDescriptor]) {
		allItems = descriptors.map { desc in
			let item = BundleChooserItem(
				name: desc.name,
				bundleName: desc.bundleName,
				itemIdentifier: desc.identifier,
				tabTrigger: desc.tabTrigger,
				keyEquivalent: desc.keyEquivalent,
				kind: desc.kind,
				isEclipsed: desc.isEclipsed,
			)
			return (item: item, source: desc.source)
		}
	}
}

/// Descriptor for populating the bundle item chooser.
public struct BundleItemDescriptor: Sendable {
	/// Item display name.
	public let name: String
	/// Bundle name containing this item.
	public let bundleName: String
	/// Unique identifier (UUID).
	public let identifier: String
	/// Tab trigger, if any.
	public let tabTrigger: String?
	/// Key equivalent, if any.
	public let keyEquivalent: String?
	/// Item kind (Command, Snippet, Grammar, Theme, etc.).
	public let kind: String
	/// Which search source this item belongs to.
	public let source: BundleSearchSource
	/// Whether this item is eclipsed by another with the same key.
	public let isEclipsed: Bool

	public init(
		name: String,
		bundleName: String,
		identifier: String,
		tabTrigger: String? = nil,
		keyEquivalent: String? = nil,
		kind: String = "Command",
		source: BundleSearchSource = .actionItems,
		isEclipsed: Bool = false,
	) {
		self.name = name
		self.bundleName = bundleName
		self.identifier = identifier
		self.tabTrigger = tabTrigger
		self.keyEquivalent = keyEquivalent
		self.kind = kind
		self.source = source
		self.isEclipsed = isEclipsed
	}
}
