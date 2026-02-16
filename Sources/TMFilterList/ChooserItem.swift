import Foundation

/// Protocol for items displayed in a chooser panel.
public protocol ChooserItem: Sendable {
	/// Display name for the item.
	var displayName: String { get }
	/// Optional secondary text (e.g. folder path, bundle name).
	var detail: String { get }
	/// Unique identifier for the item.
	var identifier: String { get }
	/// Whether this item matched the current filter.
	var isMatched: Bool { get }
	/// Rank score (lower is better for sorting). Stored as `3 - score` for ascending sort.
	var sortRank: Double { get }
	/// Cover ranges for the display name.
	var nameCoverRanges: [CoverRange] { get }
	/// Cover ranges for the detail text.
	var detailCoverRanges: [CoverRange] { get }
}

// MARK: - File Chooser Item

/// Represents a file in the file chooser (⌘T).
public struct FileChooserItem: ChooserItem {
	/// File name (last path component).
	public let fileName: String
	/// Directory path (parent directory).
	public let directory: String
	/// Full file path.
	public let path: String
	/// Whether this is the currently open document.
	public let isCurrentDocument: Bool
	/// LRU rank (0 = most recent, higher = older).
	public let lruRank: Int

	// Ranking results (mutable during filtering)
	public var isMatched: Bool
	public var sortRank: Double
	public var nameCoverRanges: [CoverRange]
	public var detailCoverRanges: [CoverRange]

	public var displayName: String {
		fileName
	}

	public var detail: String {
		directory
	}

	public var identifier: String {
		path
	}

	public init(
		path: String,
		isCurrentDocument: Bool = false,
		lruRank: Int = 0,
	) {
		let url = URL(fileURLWithPath: path)
		self.path = path
		fileName = url.lastPathComponent
		directory = url.deletingLastPathComponent().path
		self.isCurrentDocument = isCurrentDocument
		self.lruRank = lruRank
		isMatched = true
		sortRank = 0
		nameCoverRanges = []
		detailCoverRanges = []
	}

	/// Update rank using a fuzzy filter string and optional learned bindings.
	public mutating func updateRank(
		filter: String,
		bindings: [String] = [],
	) {
		if filter.isEmpty {
			isMatched = true
			sortRank = isCurrentDocument ? 2.9 : 0
			nameCoverRanges = []
			detailCoverRanges = []
			return
		}

		// Start with base rank: current document is de-prioritized
		var rank = isCurrentDocument ? 0.1 : 3.0

		// Try filename match first
		let fileResult = FuzzyRanker.rank(filter: filter, candidate: fileName)
		if fileResult.isMatch {
			rank = (isCurrentDocument ? 0.1 : 3.0) + 1
			nameCoverRanges = fileResult.coverRanges
			detailCoverRanges = []

			// Check abbreviation bindings
			if let bindingIndex = bindings.firstIndex(of: path) {
				let positionBonus = Double(bindingIndex) / Double(max(bindings.count, 1))
				rank = 2.0 + positionBonus
			}

			isMatched = true
			sortRank = 3.0 - rank
			return
		}

		// Fallback: try full path match
		let fullPath = directory + "/" + fileName
		let pathResult = FuzzyRanker.rank(filter: filter, candidate: fullPath)
		if pathResult.isMatch {
			let boundary = directory.utf8.count + 1 // +1 for "/"
			let split = MatchHighlighter.splitCoverRanges(pathResult.coverRanges, at: boundary)
			detailCoverRanges = split.prefix
			nameCoverRanges = split.suffix
			rank = (isCurrentDocument ? 0.1 : 3.0) + pathResult.score
			isMatched = true
			sortRank = 3.0 - rank
			return
		}

		isMatched = false
		sortRank = Double.greatestFiniteMagnitude
		nameCoverRanges = []
		detailCoverRanges = []
	}

	/// Update rank using a glob pattern.
	public mutating func updateRank(glob pattern: String) {
		let globResult = matchGlob(pattern: pattern, path: path)
		isMatched = globResult
		sortRank = globResult ? 0 : Double.greatestFiniteMagnitude
		nameCoverRanges = []
		detailCoverRanges = []
	}
}

// MARK: - Bundle Chooser Item

/// Represents a bundle item in the bundle item chooser.
public struct BundleChooserItem: ChooserItem {
	/// Item name/title.
	public let name: String
	/// Bundle name or location path.
	public let bundleName: String
	/// Unique identifier (UUID or semantic class).
	public let itemIdentifier: String
	/// Tab trigger string, if any.
	public let tabTrigger: String?
	/// Key equivalent string, if any.
	public let keyEquivalent: String?
	/// Item kind description.
	public let kind: String
	/// Whether this item is eclipsed by another with same key.
	public var isEclipsed: Bool

	// Ranking results
	public var isMatched: Bool
	public var sortRank: Double
	public var nameCoverRanges: [CoverRange]
	public var detailCoverRanges: [CoverRange]

	public var displayName: String {
		name
	}

	public var detail: String {
		bundleName
	}

	public var identifier: String {
		itemIdentifier
	}

	public init(
		name: String,
		bundleName: String,
		itemIdentifier: String,
		tabTrigger: String? = nil,
		keyEquivalent: String? = nil,
		kind: String = "Command",
		isEclipsed: Bool = false,
	) {
		self.name = name
		self.bundleName = bundleName
		self.itemIdentifier = itemIdentifier
		self.tabTrigger = tabTrigger
		self.keyEquivalent = keyEquivalent
		self.kind = kind
		self.isEclipsed = isEclipsed
		isMatched = true
		sortRank = 0
		nameCoverRanges = []
		detailCoverRanges = []
	}

	/// Search field type for bundle item filtering.
	public enum SearchField: Int, Sendable {
		case title = 0
		case keyEquivalent = 1
		case tabTrigger = 2
		case semanticClass = 3
		case scopeSelector = 4
	}

	/// Update rank using a filter string and search field.
	public mutating func updateRank(
		filter: String,
		field: SearchField = .title,
		bindings: [String] = [],
		preserveOrder: Bool = false,
		orderIndex: Int = 0,
		totalItems: Int = 1,
	) {
		if filter.isEmpty {
			isMatched = true
			sortRank = 0
			nameCoverRanges = []
			detailCoverRanges = []
			return
		}

		switch field {
		case .title:
			updateRankByTitle(
				filter: filter,
				bindings: bindings,
				preserveOrder: preserveOrder,
				orderIndex: orderIndex,
				totalItems: totalItems,
			)
		case .keyEquivalent:
			updateRankByKeyEquivalent(filter: filter)
		case .tabTrigger:
			updateRankBySubstring(filter: filter, target: tabTrigger ?? "")
		case .semanticClass:
			updateRankBySubstring(filter: filter, target: kind)
		case .scopeSelector:
			updateRankBySubstring(filter: filter, target: bundleName)
		}
	}

	private mutating func updateRankByTitle(
		filter: String,
		bindings: [String],
		preserveOrder: Bool,
		orderIndex: Int,
		totalItems: Int,
	) {
		var rank = preserveOrder
			? Double(totalItems - orderIndex) / Double(max(totalItems, 1))
			: 3.0

		// Try name match
		let nameResult = FuzzyRanker.rank(filter: filter, candidate: name)
		if nameResult.isMatch {
			rank += 1
			nameCoverRanges = nameResult.coverRanges
			detailCoverRanges = []

			// Check abbreviation bindings
			if let bindingIndex = bindings.firstIndex(of: itemIdentifier) {
				let positionBonus = Double(bindingIndex) / Double(max(bindings.count, 1))
				rank = 2.0 + positionBonus
			}

			isMatched = true
			sortRank = 3.0 - rank
			return
		}

		// Fallback: path + name combined
		let combined = bundleName + " " + name
		let combinedResult = FuzzyRanker.rank(filter: filter, candidate: combined)
		if combinedResult.isMatch {
			let boundary = bundleName.utf8.count + 1
			let split = MatchHighlighter.splitCoverRanges(combinedResult.coverRanges, at: boundary)
			detailCoverRanges = split.prefix
			nameCoverRanges = split.suffix
			rank += combinedResult.score
			isMatched = true
			sortRank = 3.0 - rank
			return
		}

		isMatched = false
		sortRank = Double.greatestFiniteMagnitude
		nameCoverRanges = []
		detailCoverRanges = []
	}

	private mutating func updateRankByKeyEquivalent(filter: String) {
		guard let keyEq = keyEquivalent, !keyEq.isEmpty else {
			isMatched = false
			sortRank = Double.greatestFiniteMagnitude
			return
		}
		isMatched = keyEq.localizedCaseInsensitiveContains(filter)
		sortRank = isMatched ? 0 : Double.greatestFiniteMagnitude
		nameCoverRanges = []
		detailCoverRanges = []
	}

	private mutating func updateRankBySubstring(filter: String, target: String) {
		isMatched = target.localizedCaseInsensitiveContains(filter)
		sortRank = isMatched ? 0 : Double.greatestFiniteMagnitude
		nameCoverRanges = []
		detailCoverRanges = []
	}
}

// MARK: - Symbol Chooser Item

/// Represents a symbol in the symbol chooser (⌘⇧T).
public struct SymbolChooserItem: ChooserItem {
	/// Symbol name.
	public let symbolName: String
	/// Section/group name (e.g. class name for methods).
	public let section: String?
	/// Character offset of the symbol in the document.
	public let offset: Int
	/// Selection string for navigating to this symbol.
	public let selectionString: String

	// Ranking results
	public var isMatched: Bool
	public var sortRank: Double
	public var nameCoverRanges: [CoverRange]
	public var detailCoverRanges: [CoverRange]

	public var displayName: String {
		symbolName
	}

	public var detail: String {
		section ?? ""
	}

	public var identifier: String {
		selectionString
	}

	public init(
		symbolName: String,
		section: String? = nil,
		offset: Int = 0,
		selectionString: String = "",
	) {
		self.symbolName = symbolName
		self.section = section
		self.offset = offset
		self.selectionString = selectionString
		isMatched = true
		sortRank = Double(offset) // sorted by document position by default
		nameCoverRanges = []
		detailCoverRanges = []
	}

	/// Update rank using a fuzzy filter string.
	public mutating func updateRank(filter: String) {
		if filter.isEmpty {
			isMatched = true
			sortRank = Double(offset)
			nameCoverRanges = []
			detailCoverRanges = []
			return
		}

		// Build search string: "symbol — section" if section exists
		let searchString: String = if let section, !section.isEmpty {
			symbolName + " — " + section
		} else {
			symbolName
		}

		let result = FuzzyRanker.rank(filter: filter, candidate: searchString)
		if result.isMatch {
			isMatched = true
			sortRank = 1.0 - result.score // inverted for ascending sort (best first)
			// Only take cover ranges within the symbol name portion
			nameCoverRanges = result.coverRanges.compactMap { range in
				if range.end <= symbolName.utf8.count {
					return range
				} else if range.start < symbolName.utf8.count {
					return CoverRange(start: range.start, end: symbolName.utf8.count)
				}
				return nil
			}
			detailCoverRanges = []
		} else {
			isMatched = false
			sortRank = Double.greatestFiniteMagnitude
			nameCoverRanges = []
			detailCoverRanges = []
		}
	}
}

// MARK: - Sorting

public extension Array where Element: ChooserItem {
	/// Sort items by rank (ascending), then by display name alphabetically.
	func sortedByRank() -> [Element] {
		sorted { a, b in
			if a.sortRank != b.sortRank {
				return a.sortRank < b.sortRank
			}
			return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
		}
	}
}

public extension [FileChooserItem] {
	/// Sort file items by rank, then LRU, then name.
	func sortedByRank() -> [FileChooserItem] {
		sorted { a, b in
			if a.sortRank != b.sortRank {
				return a.sortRank < b.sortRank
			}
			if a.lruRank != b.lruRank {
				return a.lruRank < b.lruRank
			}
			return a.fileName.localizedCaseInsensitiveCompare(b.fileName) == .orderedAscending
		}
	}
}

// MARK: - Glob Matching Helper

/// Simple glob pattern matching.
private func matchGlob(pattern: String, path: String) -> Bool {
	let regex = globToRegex(pattern)
	guard let re = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else {
		return false
	}
	let range = NSRange(path.startIndex ..< path.endIndex, in: path)
	return re.firstMatch(in: path, range: range) != nil
}

/// Convert a simple glob pattern to a regex.
private func globToRegex(_ glob: String) -> String {
	var result = "^"
	for ch in glob {
		switch ch {
		case "*":
			result += ".*"
		case "?":
			result += "."
		case ".":
			result += "\\."
		case "\\":
			result += "\\\\"
		default:
			result.append(ch)
		}
	}
	result += "$"
	return result
}
