import AppKit

/// A sidebar file browser view displaying a directory tree.
///
/// For Iteration 1, this provides an outline view with file/folder icons,
/// disclosure triangles, `.gitignore` filtering, single-click to open
/// (transient), double-click to keep open, and a context menu.
/// Uses system appearance colors — follows light/dark mode automatically.
@MainActor
public class FileBrowserView: NSView {
	private let outlineView = NSOutlineView()
	private let scrollView = NSScrollView()
	private let headerLabel = NSTextField(labelWithString: "")
	private var dataSource: FileBrowserDataSource?

	public weak var delegate: FileBrowserViewDelegate?

	/// The root URL displayed in the file browser.
	public var rootURL: URL? {
		didSet {
			if let url = rootURL {
				let filter = GitignoreFilter(rootURL: url)
				dataSource = FileBrowserDataSource(rootURL: url, filter: filter)
				dataSource?.selectionHandler = { [weak self] node in
					guard let self, !node.isDirectory else { return }
					delegate?.fileBrowserView(self, didSelectFileAt: node.url)
				}
				outlineView.dataSource = dataSource
				outlineView.delegate = dataSource
				headerLabel.stringValue = url.lastPathComponent
				outlineView.reloadData()
			}
		}
	}

	override public init(frame: NSRect) {
		super.init(frame: frame)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	/// Reload the file browser contents (e.g. after file system changes).
	public func reloadData() {
		if let url = rootURL {
			dataSource?.rootNode.invalidateChildren()
			outlineView.reloadData()
			_ = url // suppress unused warning
		}
	}

	// MARK: - Private

	private func setupViews() {
		wantsLayer = true

		// Header
		headerLabel.font = .boldSystemFont(ofSize: 11)
		headerLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(headerLabel)

		// Column for the outline view
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
		column.title = ""
		column.isEditable = false
		outlineView.addTableColumn(column)
		outlineView.outlineTableColumn = column
		outlineView.headerView = nil
		outlineView.rowHeight = 20
		outlineView.indentationPerLevel = 16
		outlineView.autoresizesOutlineColumn = true
		outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

		// Double-click opens file permanently
		outlineView.doubleAction = #selector(outlineViewDoubleClicked(_:))
		outlineView.target = self

		// Context menu
		outlineView.menu = buildContextMenu()

		scrollView.documentView = outlineView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scrollView)

		NSLayoutConstraint.activate([
			headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			headerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

			scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@objc private func outlineViewDoubleClicked(_: Any?) {
		let row = outlineView.clickedRow
		guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
		if node.isDirectory {
			if outlineView.isItemExpanded(node) {
				outlineView.collapseItem(node)
			} else {
				outlineView.expandItem(node)
			}
		} else {
			delegate?.fileBrowserView(self, didDoubleClickFileAt: node.url)
		}
	}

	// MARK: - Context Menu

	private func buildContextMenu() -> NSMenu {
		let menu = NSMenu()
		menu.addItem(
			withTitle: String(localized: "New File", comment: "File browser context menu"),
			action: #selector(contextNewFile(_:)),
			keyEquivalent: "",
		)
		menu.addItem(
			withTitle: String(localized: "New Folder", comment: "File browser context menu"),
			action: #selector(contextNewFolder(_:)),
			keyEquivalent: "",
		)
		menu.addItem(.separator())
		menu.addItem(
			withTitle: String(localized: "Reveal in Finder", comment: "File browser context menu"),
			action: #selector(contextRevealInFinder(_:)),
			keyEquivalent: "",
		)
		menu.addItem(.separator())
		menu.addItem(
			withTitle: String(localized: "Delete", comment: "File browser context menu"),
			action: #selector(contextDelete(_:)),
			keyEquivalent: "",
		)
		for item in menu.items {
			item.target = self
		}
		return menu
	}

	/// The URL of the clicked item, or the root URL for context operations.
	private func contextTargetURL() -> URL? {
		let row = outlineView.clickedRow
		if row >= 0, let node = outlineView.item(atRow: row) as? FileNode {
			return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
		}
		return rootURL
	}

	@objc private func contextNewFile(_: Any?) {
		guard let parentURL = contextTargetURL() else { return }
		let alert = NSAlert()
		alert.messageText = String(localized: "New File", comment: "New file dialog title")
		alert.addButton(withTitle: String(localized: "Create", comment: "New file dialog button"))
		alert.addButton(withTitle: String(localized: "Cancel", comment: "New file dialog button"))
		let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		input.stringValue = "untitled.txt"
		alert.accessoryView = input
		alert.window.initialFirstResponder = input
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let name = input.stringValue.trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty else { return }
		let fileURL = parentURL.appendingPathComponent(name)
		FileManager.default.createFile(atPath: fileURL.path, contents: nil)
		reloadData()
	}

	@objc private func contextNewFolder(_: Any?) {
		guard let parentURL = contextTargetURL() else { return }
		let alert = NSAlert()
		alert.messageText = String(localized: "New Folder", comment: "New folder dialog title")
		alert.addButton(withTitle: String(localized: "Create", comment: "New folder dialog button"))
		alert.addButton(withTitle: String(localized: "Cancel", comment: "New folder dialog button"))
		let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		input.stringValue = "untitled"
		alert.accessoryView = input
		alert.window.initialFirstResponder = input
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let name = input.stringValue.trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty else { return }
		let folderURL = parentURL.appendingPathComponent(name)
		try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
		reloadData()
	}

	@objc private func contextRevealInFinder(_: Any?) {
		let row = outlineView.clickedRow
		if row >= 0, let node = outlineView.item(atRow: row) as? FileNode {
			NSWorkspace.shared.activateFileViewerSelecting([node.url])
		} else if let url = rootURL {
			NSWorkspace.shared.activateFileViewerSelecting([url])
		}
	}

	@objc private func contextDelete(_: Any?) {
		let row = outlineView.clickedRow
		guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = "Delete \"\(node.url.lastPathComponent)\"?"
		alert.informativeText = String(
			localized: "This will move the item to the Trash.",
			comment: "Delete confirmation message",
		)
		alert.addButton(withTitle: String(localized: "Move to Trash", comment: "Delete confirmation button"))
		alert.addButton(withTitle: String(localized: "Cancel", comment: "Delete confirmation button"))
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		try? FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
		reloadData()
	}
}

/// Delegate for file browser events.
@MainActor
public protocol FileBrowserViewDelegate: AnyObject {
	/// Called on single-click: open file as transient (preview).
	func fileBrowserView(_ view: FileBrowserView, didSelectFileAt url: URL)
	/// Called on double-click: open file permanently (keep tab).
	func fileBrowserView(_ view: FileBrowserView, didDoubleClickFileAt url: URL)
}

// MARK: - GitignoreFilter

/// Reads `.gitignore` and `.tm_properties` from the project root and provides
/// a simple check for whether a path should be hidden in the file browser.
final class GitignoreFilter: @unchecked Sendable {
	private var patterns: [String] = []

	/// Always-ignored directory names (version control, build artifacts).
	private static let defaultIgnored: Set<String> = [
		".git", ".svn", ".hg", ".DS_Store", "node_modules", ".build",
	]

	init(rootURL: URL) {
		loadPatterns(from: rootURL.appendingPathComponent(".gitignore"))
		loadPatterns(from: rootURL.appendingPathComponent(".tm_properties"))
	}

	private func loadPatterns(from url: URL) {
		guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
		for line in content.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
			// For .tm_properties, look for excludeInFileChooser lines
			if url.lastPathComponent == ".tm_properties" {
				if trimmed.contains("excludeInFileChooser") {
					// Parse: excludeInFileChooser = "{pattern}"
					if let range = trimmed.range(of: "=") {
						let value = String(trimmed[range.upperBound...])
							.trimmingCharacters(in: .whitespaces)
							.trimmingCharacters(in: CharacterSet(charactersIn: "\"'{};"))
						if !value.isEmpty {
							patterns.append(value)
						}
					}
				}
				continue
			}
			// Negation patterns (!) are ignored for simplicity.
			if trimmed.hasPrefix("!") { continue }
			// Strip trailing slash (directory indicator) — we match name anyway.
			let pattern = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
			patterns.append(pattern)
		}
	}

	/// Returns `true` if the file/folder at `url` should be hidden.
	func shouldHide(_ url: URL) -> Bool {
		let name = url.lastPathComponent
		if Self.defaultIgnored.contains(name) { return true }
		for pattern in patterns {
			if matchGlob(pattern: pattern, name: name) { return true }
		}
		return false
	}

	/// Simple glob matching: supports `*` (any chars) and `?` (single char).
	private func matchGlob(pattern: String, name: String) -> Bool {
		// Convert glob to regex
		var regex = "^"
		for ch in pattern {
			switch ch {
			case "*": regex += ".*"
			case "?": regex += "."
			case ".": regex += "\\."
			default: regex += String(ch)
			}
		}
		regex += "$"
		return name.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
	}
}

// MARK: - FileNode

/// A file system node for the outline view, with lazy child loading.
final class FileNode: @unchecked Sendable {
	let url: URL
	let isDirectory: Bool
	private(set) var children: [FileNode]?
	private let filter: GitignoreFilter?

	init(url: URL, filter: GitignoreFilter? = nil) {
		var isDir: ObjCBool = false
		FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
		self.url = url
		isDirectory = isDir.boolValue
		self.filter = filter
	}

	/// Lazily load and filter children on first access.
	func loadChildrenIfNeeded() {
		guard isDirectory, children == nil else { return }
		let fm = FileManager.default
		let urls = (try? fm.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
			options: [.skipsHiddenFiles],
		)) ?? []

		children = urls
			.filter { !(filter?.shouldHide($0) ?? false) }
			.sorted { lhs, rhs in
				let lhsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
				let rhsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
				if lhsDir != rhsDir { return lhsDir }
				return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
			}
			.map { FileNode(url: $0, filter: filter) }
	}

	/// Clear cached children so the next access reloads from disk.
	func invalidateChildren() {
		children = nil
	}
}

// MARK: - FileBrowserDataSource

@MainActor
private class FileBrowserDataSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
	let rootNode: FileNode

	/// Called when a file node is selected (single-click).
	var selectionHandler: ((FileNode) -> Void)?

	init(rootURL: URL, filter: GitignoreFilter?) {
		rootNode = FileNode(url: rootURL, filter: filter)
		rootNode.loadChildrenIfNeeded()
	}

	// MARK: - NSOutlineViewDataSource

	func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		let node = item as? FileNode ?? rootNode
		node.loadChildrenIfNeeded()
		return node.children?.count ?? 0
	}

	func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		let node = item as? FileNode ?? rootNode
		return node.children![index]
	}

	func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? FileNode)?.isDirectory ?? false
	}

	// MARK: - NSOutlineViewDelegate

	func outlineView(_: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? FileNode else { return nil }

		let cellView = NSTableCellView()
		let textField = NSTextField(labelWithString: node.url.lastPathComponent)
		textField.font = .systemFont(ofSize: 13)
		textField.lineBreakMode = .byTruncatingTail
		textField.translatesAutoresizingMaskIntoConstraints = false

		let imageView = NSImageView()
		imageView.image = NSWorkspace.shared.icon(forFile: node.url.path)
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.translatesAutoresizingMaskIntoConstraints = false

		cellView.addSubview(imageView)
		cellView.addSubview(textField)
		cellView.textField = textField
		cellView.imageView = imageView

		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
			imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
			imageView.widthAnchor.constraint(equalToConstant: 16),
			imageView.heightAnchor.constraint(equalToConstant: 16),

			textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
			textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
			textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
		])

		return cellView
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard let outlineView = notification.object as? NSOutlineView else { return }
		let row = outlineView.selectedRow
		guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
		selectionHandler?(node)
	}
}
