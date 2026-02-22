import Foundation

/// File source for the file chooser.
public enum FileChooserSource: Int, Sendable, CaseIterable {
	/// All files in the project.
	case all = 0
	/// Currently open documents.
	case openDocuments = 1
	/// Uncommitted files (modified/added/deleted in VCS).
	case uncommitted = 2

	public var displayName: String {
		switch self {
		case .all: "All"
		case .openDocuments: "Open"
		case .uncommitted: "Uncommitted"
		}
	}
}

/// Parsed filter input — separates filter text from navigation suffixes.
public struct ParsedFilter: Equatable, Sendable {
	/// The fuzzy filter string (normalized) or nil if using glob.
	public let filterString: String?
	/// Glob pattern (if filter contains *).
	public let globString: String?
	/// Selection string (text after :) e.g. "42" for line 42.
	public let selectionString: String?
	/// Symbol string (text after @).
	public let symbolString: String?

	/// The effective filter for ranking (filterString or empty).
	public var effectiveFilter: String {
		filterString ?? ""
	}

	/// Whether this is a glob search.
	public var isGlob: Bool {
		globString != nil
	}
}

/// Manages the state and filtering logic for the file chooser (⌘T).
///
/// Port of TextMate's `FileChooser` — supports three sources (All, Open, Uncommitted),
/// fuzzy matching with learned abbreviation boosting, glob patterns, and
/// selection/symbol navigation suffixes.
public final class FileChooserState: @unchecked Sendable {
	// MARK: - Properties

	/// The project root path.
	public var projectPath: String

	/// Current document identifier (de-prioritized in results).
	public var currentDocumentPath: String?

	/// Active file source.
	public var source: FileChooserSource = .all

	/// Abbreviation store for learned bindings.
	public let abbreviations: AbbreviationStore

	/// All candidate file paths (populated by enumeration).
	public var allFiles: [String] = []

	/// Open document paths.
	public var openDocuments: [String] = []

	/// Uncommitted file paths (from SCM).
	public var uncommittedFiles: [String] = []

	/// Current filter string (raw user input).
	public var rawFilter: String = ""

	/// Parsed filter components.
	public private(set) var parsedFilter = ParsedFilter(
		filterString: nil, globString: nil,
		selectionString: nil, symbolString: nil,
	)

	/// Filtered and ranked results.
	public private(set) var filteredItems: [FileChooserItem] = []

	// MARK: - Initialization

	public init(projectPath: String) {
		self.projectPath = projectPath
		abbreviations = AbbreviationStore.named("OakFileChooserBindings")
	}

	// MARK: - Filter Parsing

	/// The regex pattern for parsing filter input.
	///
	/// Matches: `(?:(glob*pattern)|(fuzzyFilter))(?::selectionString|@symbolString)?`
	private static let filterRegex = try! NSRegularExpression(
		pattern: #"\A(?:(.*?\*.*?)|(.*?))(?::([0-9+:\-x+]*)|@(.*))?\z"#,
		options: [],
	)

	/// Parse the raw filter string into its components.
	public func parseFilter(_ raw: String) -> ParsedFilter {
		let nsRange = NSRange(raw.startIndex ..< raw.endIndex, in: raw)
		guard let match = Self.filterRegex.firstMatch(in: raw, range: nsRange) else {
			return ParsedFilter(
				filterString: FuzzyRanker.normalizeFilter(raw),
				globString: nil,
				selectionString: nil,
				symbolString: nil,
			)
		}

		let glob = extractGroup(match, group: 1, in: raw)
		let filter = extractGroup(match, group: 2, in: raw)
		let selection = extractGroup(match, group: 3, in: raw)
		let symbol = extractGroup(match, group: 4, in: raw)

		return ParsedFilter(
			filterString: filter.map { FuzzyRanker.normalizeFilter($0) },
			globString: glob,
			selectionString: selection,
			symbolString: symbol,
		)
	}

	private func extractGroup(_ match: NSTextCheckingResult, group: Int, in string: String) -> String? {
		let range = match.range(at: group)
		guard range.location != NSNotFound else { return nil }
		guard let swiftRange = Range(range, in: string) else { return nil }
		let value = String(string[swiftRange])
		return value.isEmpty ? nil : value
	}

	// MARK: - Filtering

	/// Update the filter and recompute filtered results.
	public func updateFilter(_ raw: String) {
		rawFilter = raw
		parsedFilter = parseFilter(raw)
		refilter()
	}

	/// Refilter using the current parsed filter and source.
	public func refilter() {
		let candidatePaths: [String] = switch source {
		case .all:
			allFiles
		case .openDocuments:
			openDocuments
		case .uncommitted:
			uncommittedFiles
		}

		let filter = parsedFilter.effectiveFilter
		let bindings = abbreviations.strings(for: filter)

		var items = candidatePaths.enumerated().map { index, path in
			FileChooserItem(
				path: path,
				isCurrentDocument: path == currentDocumentPath,
				isOpenDocument: source == .openDocuments,
				lruRank: source == .openDocuments ? index : 0,
			)
		}

		if parsedFilter.isGlob, let glob = parsedFilter.globString {
			for i in items.indices {
				items[i].updateRank(glob: glob)
			}
		} else {
			for i in items.indices {
				items[i].updateRank(filter: filter, bindings: bindings)
			}
		}

		filteredItems = items.filter(\.isMatched).sortedByRank()
	}

	// MARK: - Abbreviation Learning

	/// Learn the current filter as an abbreviation for the selected item.
	public func learnSelection(path: String) {
		let filter = parsedFilter.effectiveFilter
		guard !filter.isEmpty else { return }
		abbreviations.learn(abbreviation: filter, for: path)
	}

	// MARK: - File Enumeration

	/// Asynchronously enumerate files in the project directory.
	///
	/// - Parameters:
	///   - includePatterns: Glob patterns for files to include (empty = all).
	///   - excludePatterns: Glob patterns for files to exclude.
	///   - progress: Called periodically with the number of files found so far.
	public func enumerateFiles(
		includePatterns: [String] = [],
		excludePatterns: [String] = [".*", "*.o", "*.pyc", "__pycache__", "node_modules", ".git", ".svn", ".hg"],
		progress: ((Int) -> Void)? = nil,
	) async {
		var files: [String] = []
		let fileManager = FileManager.default

		let enumerator = fileManager.enumerator(
			at: URL(fileURLWithPath: projectPath),
			includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
			options: [.skipsHiddenFiles],
		)

		let excludeRegexes = excludePatterns.compactMap { pattern -> NSRegularExpression? in
			let regex = globToRegexPattern(pattern)
			return try? NSRegularExpression(pattern: regex, options: .caseInsensitive)
		}

		let includeRegexes = includePatterns.compactMap { pattern -> NSRegularExpression? in
			let regex = globToRegexPattern(pattern)
			return try? NSRegularExpression(pattern: regex, options: .caseInsensitive)
		}

		var count = 0
		while let url = enumerator?.nextObject() as? URL {
			let name = url.lastPathComponent

			// Check exclusions on filename
			let nameRange = NSRange(name.startIndex ..< name.endIndex, in: name)
			let excluded = excludeRegexes.contains { regex in
				regex.firstMatch(in: name, range: nameRange) != nil
			}
			if excluded {
				// If it's a directory, skip its contents
				let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
				if isDir {
					enumerator?.skipDescendants()
				}
				continue
			}

			let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
			guard isFile else { continue }

			// Check inclusions
			if !includeRegexes.isEmpty {
				let included = includeRegexes.contains { regex in
					regex.firstMatch(in: name, range: nameRange) != nil
				}
				if !included { continue }
			}

			files.append(url.path)
			count += 1

			if count % 100 == 0 {
				progress?(count)
				await Task.yield() // Allow cancellation and UI updates
			}
		}

		allFiles = files
		progress?(files.count)
	}
}

// MARK: - Glob Helper

private func globToRegexPattern(_ glob: String) -> String {
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
