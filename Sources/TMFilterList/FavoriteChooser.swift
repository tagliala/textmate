#if canImport(AppKit)
import AppKit

// MARK: - Recent Project Entry

/// An entry in the recent projects list.
public struct RecentProjectEntry: Codable, Sendable, Equatable {
	/// The folder path.
	public var path: String

	/// Display name (folder name).
	public var displayName: String

	/// When the project was last opened.
	public var lastOpened: Date

	public init(
		path: String,
		displayName: String? = nil,
		lastOpened: Date = Date(),
	) {
		self.path = path
		self.displayName = displayName ?? (path as NSString).lastPathComponent
		self.lastOpened = lastOpened
	}
}

// MARK: - Recent Projects Manager

/// Tracks recently opened project folders in LRU order.
@MainActor
public final class RecentProjectsManager {
	/// Shared singleton.
	public static let shared = RecentProjectsManager()

	/// Maximum number of entries to keep.
	public var maxEntries: Int = 25

	/// The recent entries, most recent first.
	public private(set) var entries: [RecentProjectEntry] = []

	/// Callback when the entries list changes.
	public var onChanged: (() -> Void)?

	private let defaultsKey = "com.macromates.RecentProjects"

	private init() {
		loadFromDefaults()
	}

	/// Records a folder as recently opened.
	public func noteProjectOpened(path: String) {
		let canonical = canonicalize(path)
		entries.removeAll { $0.path == canonical }
		let entry = RecentProjectEntry(path: canonical, lastOpened: Date())
		entries.insert(entry, at: 0)
		if entries.count > maxEntries {
			entries = Array(entries.prefix(maxEntries))
		}
		saveToDefaults()
		onChanged?()
	}

	/// Removes entries for folders that no longer exist.
	public func pruneStale() {
		let before = entries.count
		entries.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
		if entries.count != before {
			saveToDefaults()
			onChanged?()
		}
	}

	/// Clears all recent projects.
	public func clearAll() {
		entries.removeAll()
		saveToDefaults()
		onChanged?()
	}

	private func saveToDefaults() {
		guard let data = try? JSONEncoder().encode(entries) else { return }
		UserDefaults.standard.set(data, forKey: defaultsKey)
	}

	private func loadFromDefaults() {
		guard let data = UserDefaults.standard.data(forKey: defaultsKey),
		      let loaded = try? JSONDecoder().decode([RecentProjectEntry].self, from: data)
		else { return }
		entries = loaded
	}

	private func canonicalize(_ path: String) -> String {
		let nsPath = (path as NSString).standardizingPath
		return URL(fileURLWithPath: nsPath).resolvingSymlinksInPath().path
	}
}

// MARK: - Favorite Chooser Item

/// Represents a project folder in the favorites/recent projects chooser.
public struct FavoriteChooserItem: ChooserItem {
	public let path: String
	public let displayName: String
	public let detail: String
	public let identifier: String
	public var isMatched: Bool
	public var sortRank: Double
	public var nameCoverRanges: [CoverRange]
	public var detailCoverRanges: [CoverRange]

	public init(entry: RecentProjectEntry) {
		path = entry.path
		displayName = entry.displayName
		detail = (entry.path as NSString).abbreviatingWithTildeInPath
		identifier = entry.path
		isMatched = true
		sortRank = 0
		nameCoverRanges = []
		detailCoverRanges = []
	}
}

// MARK: - Favorite Chooser

/// Chooser panel for recent project folders (⇧⌘O).
///
/// Ports TextMate's C++ `FavoriteChooser`.
@MainActor
public final class FavoriteChooserController: ChooserPanelController, NSTableViewDataSource, NSTableViewDelegate {
	private var allItems: [FavoriteChooserItem] = []

	public init() {
		super.init(
			title: String(localized: "Open Recent Project", comment: "Favorite chooser title"),
		)
		tableView.dataSource = self
		tableView.delegate = self
		refreshItems()
	}

	/// Reloads items from the recent projects manager.
	public func refreshItems() {
		RecentProjectsManager.shared.pruneStale()
		allItems = RecentProjectsManager.shared.entries.map { FavoriteChooserItem(entry: $0) }
		updateItems(self)
	}

	override public func updateItems(_: Any?) {
		let filter = FuzzyRanker.normalizeFilter(filterString)
		if filter.isEmpty {
			items = allItems
		} else {
			items = allItems.compactMap { item in
				var ranked = item
				let nameResult = FuzzyRanker.rank(filter: filter, candidate: item.displayName)
				if nameResult.score > 0 {
					ranked.sortRank = 3.0 - nameResult.score
					ranked.nameCoverRanges = nameResult.coverRanges
					ranked.isMatched = true
					return ranked
				}
				// Also try matching against the full path.
				let pathResult = FuzzyRanker.rank(filter: filter, candidate: item.detail)
				if pathResult.score > 0 {
					ranked.sortRank = 3.0 - pathResult.score
					ranked.detailCoverRanges = pathResult.coverRanges
					ranked.isMatched = true
					return ranked
				}
				return nil
			}.sorted { $0.sortRank < $1.sortRank }
		}
	}

	override public func updateStatusText() {
		statusTextField.stringValue = ""
	}

	// MARK: - NSTableViewDataSource

	public func numberOfRows(in _: NSTableView) -> Int {
		items.count
	}

	// MARK: - NSTableViewDelegate

	public func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
		guard row < items.count else { return nil }
		let item = items[row]

		let cellID = NSUserInterfaceItemIdentifier("FavoriteCell")
		let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView
			?? NSTableCellView()
		cell.identifier = cellID

		if cell.textField == nil {
			let tf = NSTextField(labelWithString: "")
			tf.translatesAutoresizingMaskIntoConstraints = false
			cell.addSubview(tf)
			cell.textField = tf

			let detail = NSTextField(labelWithString: "")
			detail.translatesAutoresizingMaskIntoConstraints = false
			detail.font = .systemFont(ofSize: 11)
			detail.textColor = .secondaryLabelColor
			detail.tag = 100
			cell.addSubview(detail)

			NSLayoutConstraint.activate([
				tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
				tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
				tf.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
				detail.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
				detail.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
				detail.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2),
			])
		}

		cell.textField?.stringValue = item.displayName
		(cell.viewWithTag(100) as? NSTextField)?.stringValue = item.detail

		return cell
	}
}

#endif
