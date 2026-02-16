import Foundation

/// Manages the state and filtering logic for the symbol chooser (⌘⇧T / ⌃6).
///
/// Port of TextMate's `SymbolChooser` — lists all document symbols with
/// fuzzy matching and section grouping. No abbreviation learning.
public final class SymbolChooserState: @unchecked Sendable {
	// MARK: - Properties

	/// Document identifier (for display).
	public var documentName: String = ""

	/// All symbols in the document.
	public var allSymbols: [SymbolChooserItem] = []

	/// Current filter string.
	public var rawFilter: String = ""

	/// Filtered and ranked results.
	public private(set) var filteredItems: [SymbolChooserItem] = []

	/// Current selection string (for navigating back to the original position).
	public var selectionString: String = ""

	// MARK: - Initialization

	public init() {}

	// MARK: - Symbol Population

	/// Set symbols from a list of descriptors.
	///
	/// Symbols named `"-"` are treated as section separators and excluded.
	/// Symbols prefixed with `\u{2003}` (em space) indicate they belong to a sub-section.
	public func setSymbols(_ symbols: [SymbolDescriptor]) {
		var currentSection: String?
		var items: [SymbolChooserItem] = []

		for desc in symbols {
			// Skip separator entries
			if desc.name == "-" {
				continue
			}

			// Detect sub-section (content indented with em space)
			var symbolName = desc.name
			var section = currentSection

			if symbolName.hasPrefix("\u{2003}") {
				// Indented — belongs to current section
				symbolName = String(symbolName.dropFirst())
			} else {
				// Top-level — this becomes the section
				currentSection = symbolName
				section = nil // top-level items have no section
			}

			items.append(SymbolChooserItem(
				symbolName: symbolName,
				section: section,
				offset: desc.offset,
				selectionString: desc.selectionString,
			))
		}

		allSymbols = items
	}

	// MARK: - Filtering

	/// Update the filter and recompute results.
	public func updateFilter(_ raw: String) {
		rawFilter = raw
		refilter()
	}

	/// Refilter using the current settings.
	public func refilter() {
		let filter = FuzzyRanker.normalizeFilter(rawFilter)

		if filter.isEmpty {
			// No filter — show all symbols in document order
			filteredItems = allSymbols
			return
		}

		var items = allSymbols
		for i in items.indices {
			items[i].updateRank(filter: filter)
		}

		filteredItems = items.filter(\.isMatched).sorted { a, b in
			if a.sortRank != b.sortRank {
				return a.sortRank < b.sortRank
			}
			return a.symbolName.localizedCaseInsensitiveCompare(b.symbolName) == .orderedAscending
		}
	}
}

/// Descriptor for populating the symbol chooser.
public struct SymbolDescriptor: Sendable {
	/// Symbol name. Use `"-"` for separators, prefix with `\u{2003}` for indented symbols.
	public let name: String
	/// Character offset in the document.
	public let offset: Int
	/// Selection string for navigating to this symbol (e.g. line number).
	public let selectionString: String

	public init(
		name: String,
		offset: Int = 0,
		selectionString: String = "",
	) {
		self.name = name
		self.offset = offset
		self.selectionString = selectionString
	}
}
