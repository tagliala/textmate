import Foundation

// MARK: - Search Result Node

/// A tree node for organizing search results — equivalent to `FFResultNode`.
///
/// Results are organized as: Root → File parents → Match children.
@MainActor
public final class SearchResultNode: Identifiable, Sendable {
	public nonisolated let id = UUID()

	/// The type of node.
	public enum NodeType: Sendable {
		/// Root node containing file groups.
		case root

		/// File group containing matches.
		case file(path: String, displayName: String)

		/// Individual match within a file.
		case match(DocumentMatch)
	}

	public let type: NodeType

	/// Child nodes (file groups for root, matches for file).
	public var children: [SearchResultNode] = []

	/// Whether this result is excluded from replacement.
	public var isExcluded: Bool = false

	/// Whether this result has already been replaced (prevents double-replace).
	public var isReadOnly: Bool = false

	/// Parent node (weak to avoid retain cycles).
	public weak var parent: SearchResultNode?

	public init(type: NodeType) {
		self.type = type
	}

	/// Total number of match leaves.
	public var matchCount: Int {
		switch type {
		case .root, .file:
			children.reduce(0) { $0 + $1.matchCount }
		case .match:
			1
		}
	}

	/// Number of excluded matches.
	public var excludedCount: Int {
		switch type {
		case .root, .file:
			children.reduce(0) { $0 + $1.excludedCount }
		case .match:
			isExcluded ? 1 : 0
		}
	}

	/// Number of active (non-excluded) matches.
	public var activeMatchCount: Int {
		matchCount - excludedCount
	}

	/// Add a match to a file group node.
	public func addMatch(_ match: DocumentMatch) {
		let child = SearchResultNode(type: .match(match))
		child.parent = self
		children.append(child)
	}

	/// Find or create a file group for the given path.
	public func fileGroup(forPath path: String, displayName: String) -> SearchResultNode {
		if let existing = children.first(where: {
			if case let .file(p, _) = $0.type { return p == path }
			return false
		}) {
			return existing
		}

		let group = SearchResultNode(type: .file(path: path, displayName: displayName))
		group.parent = self
		children.append(group)
		return group
	}

	/// All matches across all file groups (flattened).
	public var allMatches: [DocumentMatch] {
		switch type {
		case .root, .file:
			children.flatMap(\.allMatches)
		case let .match(m):
			[m]
		}
	}

	/// All file paths that have matches.
	public var filePaths: [String] {
		children.compactMap {
			if case let .file(path, _) = $0.type { return path }
			return nil
		}
	}
}

// MARK: - Project Search Configuration

/// Configuration for a project-wide search.
public struct ProjectSearchConfig: Sendable {
	/// The search pattern.
	public var pattern: String

	/// Search options.
	public var options: FindOptions

	/// Root paths to search in.
	public var searchPaths: [String]

	/// File glob patterns to include (e.g., "*.swift").
	public var includeGlobs: [String]

	/// File glob patterns to exclude (e.g., "*.o", ".git").
	public var excludeGlobs: [String]

	/// Directory glob patterns to exclude.
	public var excludeDirectoryGlobs: [String]

	/// Whether to follow symbolic links for files.
	public var followFileLinks: Bool

	/// Whether to follow symbolic links for directories.
	public var followDirectoryLinks: Bool

	/// Whether to search hidden files and folders.
	public var searchHidden: Bool

	/// Whether to search binary files.
	public var searchBinary: Bool

	/// Maximum file size in bytes (0 = no limit).
	public var maxFileSize: Int

	public init(
		pattern: String,
		options: FindOptions = .default,
		searchPaths: [String] = [],
		includeGlobs: [String] = [],
		excludeGlobs: [String] = [
			"*.o", "*.pyc", "*.pyo", "*.class", "*.exe", "*.dll",
			"*.dylib", "*.so", "*.a", "*.dSYM", "*.pbxuser",
		],
		excludeDirectoryGlobs: [String] = [
			".git", ".svn", ".hg", "node_modules", ".build",
			"DerivedData", "build", ".bundle",
		],
		followFileLinks: Bool = true,
		followDirectoryLinks: Bool = false,
		searchHidden: Bool = false,
		searchBinary: Bool = false,
		maxFileSize: Int = 10_000_000,
	) {
		self.pattern = pattern
		self.options = options
		self.searchPaths = searchPaths
		self.includeGlobs = includeGlobs
		self.excludeGlobs = excludeGlobs
		self.excludeDirectoryGlobs = excludeDirectoryGlobs
		self.followFileLinks = followFileLinks
		self.followDirectoryLinks = followDirectoryLinks
		self.searchHidden = searchHidden
		self.searchBinary = searchBinary
		self.maxFileSize = maxFileSize
	}
}

// MARK: - Search Progress

/// Progress information for an ongoing search.
public struct SearchProgress: Sendable {
	/// Number of files scanned so far.
	public var filesScanned: Int

	/// Number of files with matches.
	public var filesMatched: Int

	/// Total number of matches found.
	public var totalMatches: Int

	/// The file currently being scanned, if any.
	public var currentFile: String?

	/// Whether the search is complete.
	public var isComplete: Bool

	public init(
		filesScanned: Int = 0,
		filesMatched: Int = 0,
		totalMatches: Int = 0,
		currentFile: String? = nil,
		isComplete: Bool = false,
	) {
		self.filesScanned = filesScanned
		self.filesMatched = filesMatched
		self.totalMatches = totalMatches
		self.currentFile = currentFile
		self.isComplete = isComplete
	}
}

// MARK: - Project Search Engine

/// Async multi-file search engine — equivalent to `FFDocumentSearch`.
///
/// Enumerates files in the search paths, applies glob filters, and searches
/// each matching file using a `TextFinder`. Reports results via callbacks.
@MainActor
public final class ProjectSearchEngine: Sendable {
	/// Configuration for this search.
	public let config: ProjectSearchConfig

	/// The results tree (root → file groups → matches).
	public private(set) var results: SearchResultNode

	/// Current progress.
	public private(set) var progress: SearchProgress

	/// Whether the search has been cancelled.
	public private(set) var isCancelled: Bool = false

	/// Callback when new matches are found.
	public var onMatchesFound: (([DocumentMatch]) -> Void)?

	/// Callback when progress updates.
	public var onProgressUpdate: ((SearchProgress) -> Void)?

	/// Callback when search completes.
	public var onComplete: ((SearchProgress) -> Void)?

	/// The background search task.
	private var searchTask: Task<Void, Never>?

	public init(config: ProjectSearchConfig) {
		self.config = config
		results = SearchResultNode(type: .root)
		progress = SearchProgress()
	}

	/// Start the search. Can be awaited for completion.
	public func start() {
		isCancelled = false
		results = SearchResultNode(type: .root)
		progress = SearchProgress()

		searchTask = Task { [config, weak self] in
			await self?.performSearch(config: config)
		}
	}

	/// Cancel the ongoing search.
	public func cancel() {
		isCancelled = true
		searchTask?.cancel()
	}

	// MARK: - Private

	private func performSearch(config: ProjectSearchConfig) async {
		let finder: TextFinder
		do {
			finder = try makeTextFinder(pattern: config.pattern, options: config.options)
		} catch {
			progress.isComplete = true
			onComplete?(progress)
			return
		}

		for searchPath in config.searchPaths {
			guard !isCancelled else { break }
			await searchDirectory(at: searchPath, finder: finder, config: config)
		}

		progress.isComplete = true
		onProgressUpdate?(progress)
		onComplete?(progress)
	}

	private func searchDirectory(at path: String, finder: TextFinder, config: ProjectSearchConfig) async {
		let fileManager = FileManager.default
		let url = URL(fileURLWithPath: path)

		guard let enumerator = fileManager.enumerator(
			at: url,
			includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isDirectoryKey],
			options: config.searchHidden ? [] : [.skipsHiddenFiles],
		) else { return }

		while let itemURL = enumerator.nextObject() as? URL {
			guard !isCancelled else { break }

			let resourceValues = try? itemURL.resourceValues(forKeys: [
				.isRegularFileKey,
				.isSymbolicLinkKey,
				.fileSizeKey,
				.isDirectoryKey,
			])

			// Skip directories that match exclude patterns
			if resourceValues?.isDirectory == true {
				let dirName = itemURL.lastPathComponent
				if config.excludeDirectoryGlobs.contains(where: { globMatches(dirName, pattern: $0) }) {
					enumerator.skipDescendants()
					continue
				}
				continue
			}

			// Skip symlinks if configured
			if resourceValues?.isSymbolicLink == true, !config.followFileLinks {
				continue
			}

			guard resourceValues?.isRegularFile == true else { continue }

			// Check file size limit
			if config.maxFileSize > 0,
			   let fileSize = resourceValues?.fileSize,
			   fileSize > config.maxFileSize
			{
				continue
			}

			let fileName = itemURL.lastPathComponent

			// Check exclude globs
			if config.excludeGlobs.contains(where: { globMatches(fileName, pattern: $0) }) {
				continue
			}

			// Check include globs (if any specified)
			if !config.includeGlobs.isEmpty {
				let matchesInclude = config.includeGlobs.contains { globMatches(fileName, pattern: $0) }
				if !matchesInclude { continue }
			}

			// Search the file
			await searchFile(at: itemURL.path, finder: finder)
		}
	}

	private func searchFile(at path: String, finder: TextFinder) async {
		progress.filesScanned += 1
		progress.currentFile = path

		guard let data = FileManager.default.contents(atPath: path),
		      let content = String(data: data, encoding: .utf8)
		else { return }

		var matches: [FindMatch] = []
		finder.eachMatch(in: content, offset: 0, moreToCome: false) { match, _ in
			matches.append(match)
		}

		guard !matches.isEmpty else { return }

		progress.filesMatched += 1
		progress.totalMatches += matches.count

		let displayName = URL(fileURLWithPath: path).lastPathComponent
		let documentID = UUID()

		// Build document matches with excerpts
		var docMatches: [DocumentMatch] = []
		for match in matches {
			let (excerpt, excerptOffset, lineNumber, lineRange, headTrunc, tailTrunc) =
				buildExcerpt(content: content, matchRange: match.range)

			let docMatch = DocumentMatch(
				documentID: documentID,
				documentPath: path,
				displayName: displayName,
				byteRange: match.range,
				lineRange: lineRange,
				lineNumber: lineNumber,
				captures: match.captures,
				excerpt: excerpt,
				excerptOffset: excerptOffset,
				headTruncated: headTrunc,
				tailTruncated: tailTrunc,
			)
			docMatches.append(docMatch)
		}

		// Add to results tree
		let group = results.fileGroup(forPath: path, displayName: displayName)
		for dm in docMatches {
			group.addMatch(dm)
		}

		onMatchesFound?(docMatches)
		onProgressUpdate?(progress)
	}

	/// Build a context excerpt around a match.
	private func buildExcerpt(
		content: String,
		matchRange: Range<Int>,
	)
		-> (
			excerpt: String,
			offset: Int,
			lineNumber: Int,
			lineRange: LineColumnRange,
			headTruncated: Bool,
			tailTruncated: Bool,
		)
	{
		let utf8 = Array(content.utf8)
		let contextChars = 80 // Characters of context on each side

		// Find line boundaries
		var lineStart = matchRange.lowerBound
		while lineStart > 0, utf8[lineStart - 1] != UInt8(ascii: "\n") {
			lineStart -= 1
		}

		var lineEnd = matchRange.upperBound
		while lineEnd < utf8.count, utf8[lineEnd] != UInt8(ascii: "\n") {
			lineEnd += 1
		}

		// Calculate line number (0-based)
		var lineNumber = 0
		for i in 0 ..< matchRange.lowerBound where i < utf8.count {
			if utf8[i] == UInt8(ascii: "\n") { lineNumber += 1 }
		}

		// Calculate column
		let column = matchRange.lowerBound - lineStart
		let endColumn = matchRange.upperBound - lineStart

		// Build excerpt with context
		let excerptStart = max(0, lineStart - contextChars)
		let excerptEnd = min(utf8.count, lineEnd + contextChars)

		let headTruncated = excerptStart > 0
		let tailTruncated = excerptEnd < utf8.count

		let excerptBytes = utf8[excerptStart ..< excerptEnd]
		let excerpt = String(bytes: excerptBytes, encoding: .utf8) ?? ""

		let lineRange = LineColumnRange(
			startLine: lineNumber,
			startColumn: column,
			endLine: lineNumber,
			endColumn: endColumn,
		)

		return (excerpt, excerptStart, lineNumber, lineRange, headTruncated, tailTruncated)
	}

	/// Simple glob matching (supports * and ? only).
	private nonisolated func globMatches(_ name: String, pattern: String) -> Bool {
		let regexPattern = "^"
			+ pattern
			.replacingOccurrences(of: ".", with: "\\.")
			.replacingOccurrences(of: "*", with: ".*")
			.replacingOccurrences(of: "?", with: ".")
			+ "$"
		return name.range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
	}
}
