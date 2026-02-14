import AppKit

/// A sidebar file browser view displaying a directory tree.
///
/// For Iteration 1, this provides a basic outline view with file/folder icons
/// and disclosure triangles. Full file browser features (SCM badges, filtering,
/// favorites navigation) will come in later iterations.
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
				dataSource = FileBrowserDataSource(rootURL: url)
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
}

/// Delegate for file browser events.
@MainActor
public protocol FileBrowserViewDelegate: AnyObject {
	func fileBrowserView(_ view: FileBrowserView, didSelectFileAt url: URL)
	func fileBrowserView(_ view: FileBrowserView, didDoubleClickFileAt url: URL)
}

// MARK: - FileBrowserDataSource

/// A file system node for the outline view.
final class FileNode: @unchecked Sendable {
	let url: URL
	let isDirectory: Bool
	private(set) var children: [FileNode]?

	init(url: URL) {
		var isDir: ObjCBool = false
		FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
		self.url = url
		isDirectory = isDir.boolValue
	}

	func loadChildrenIfNeeded() {
		guard isDirectory, children == nil else { return }
		let fm = FileManager.default
		let urls = (try? fm.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
			options: [.skipsHiddenFiles],
		)) ?? []

		children = urls
			.sorted { lhs, rhs in
				let lhsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
				let rhsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
				if lhsDir != rhsDir { return lhsDir }
				return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
			}
			.map(FileNode.init)
	}
}

@MainActor
private class FileBrowserDataSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
	let rootNode: FileNode

	init(rootURL: URL) {
		rootNode = FileNode(url: rootURL)
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
}
