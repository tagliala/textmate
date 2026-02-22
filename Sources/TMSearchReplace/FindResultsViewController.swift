#if canImport(AppKit)
import AppKit

// MARK: - Find Results View Controller

/// View controller managing the search results outline view — equivalent to `FFResultsViewController`.
///
/// Displays an `NSOutlineView` with file-group headers (expandable) and match
/// rows beneath each file. Supports checkbox exclusion, replacement previews,
/// navigation among results, and keyboard shortcuts for quick file access.
@MainActor
public final class FindResultsViewController: NSViewController, Sendable {
	// MARK: - Properties

	/// The results tree (root node with file children containing match children).
	public var results: SearchResultNode? {
		didSet {
			guard isViewLoaded else { return }
			outlineView.reloadData()
		}
	}

	/// The replacement string used for previews.
	public var replaceString: String = "" {
		didSet {
			guard isViewLoaded else { return }
			outlineView.reloadData()
		}
	}

	/// Whether replacement previews are shown in match cells.
	public var showReplacementPreviews: Bool = false {
		didSet {
			guard isViewLoaded else { return }
			outlineView.reloadData()
		}
	}

	/// Whether the checkbox column is hidden (e.g. for count-only results).
	public var hideCheckBoxes: Bool = false {
		didSet { updateCheckBoxVisibility() }
	}

	/// Called when the user selects a result (single click).
	public var onSelectResult: ((SearchResultNode) -> Void)?

	/// Called when the user double-clicks a result.
	public var onDoubleClickResult: ((SearchResultNode) -> Void)?

	// MARK: - Subviews

	private let scrollView = NSScrollView()
	private let outlineView = NSOutlineView()

	/// Font used for match excerpts.
	private var resultsFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)

	/// Tracks last selected result to deduplicate notifications.
	private weak var lastSelectedResult: SearchResultNode?

	// MARK: - Lifecycle

	override public func loadView() {
		loadResultsFont()
		configureOutlineView()
		configureScrollView()

		let container = NSView()
		let topDiv = makeSeparator()
		let bottomDiv = makeSeparator()

		for v in [topDiv, scrollView, bottomDiv] {
			v.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(v)
		}

		NSLayoutConstraint.activate([
			topDiv.topAnchor.constraint(equalTo: container.topAnchor),
			topDiv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			topDiv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			topDiv.heightAnchor.constraint(equalToConstant: 1),

			scrollView.topAnchor.constraint(equalTo: topDiv.bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

			bottomDiv.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
			bottomDiv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			bottomDiv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			bottomDiv.heightAnchor.constraint(equalToConstant: 1),
			bottomDiv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])

		view = container
	}

	// MARK: - Public API

	/// All selected leaf match nodes. If nothing is selected, returns all leaf nodes.
	public var selectedResults: [SearchResultNode] {
		let rows = outlineView.numberOfSelectedRows == 0
			? IndexSet(integersIn: 0 ..< outlineView.numberOfRows)
			: outlineView.selectedRowIndexes

		return rows.compactMap { row -> SearchResultNode? in
			guard let node = outlineView.item(atRow: row) as? SearchResultNode else { return nil }
			return node.children.isEmpty ? node : nil
		}
	}

	/// Incrementally insert new file groups at the given indexes.
	public func insertItems(at indexes: IndexSet) {
		guard let results else { return }
		outlineView.beginUpdates()
		outlineView.insertItems(at: indexes, inParent: nil, withAnimation: [])
		for idx in indexes {
			guard idx < results.children.count else { continue }
			outlineView.expandItem(results.children[idx])
		}
		outlineView.endUpdates()
	}

	/// Show and select a specific result node.
	public func showResultNode(_ node: SearchResultNode?) {
		guard let node else { return }

		if let parent = node.parent, !outlineView.isItemExpanded(parent) {
			outlineView.expandItem(parent)
		}
		if let parent = node.parent {
			let parentRow = outlineView.row(forItem: parent)
			if parentRow >= 0 { outlineView.scrollRowToVisible(parentRow) }
		}

		let row = outlineView.row(forItem: node)
		guard row >= 0 else { return }
		outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		outlineView.scrollRowToVisible(row)
		outlineView.window?.makeFirstResponder(outlineView)
	}

	// MARK: - Navigation

	/// Select the next match result, optionally wrapping around.
	public func selectNextResult(wrapAround: Bool) {
		guard let results else { return }
		let row = outlineView.selectedRow
		let current = row >= 0 ? outlineView.item(atRow: row) as? SearchResultNode : nil

		var next = nextSibling(of: current)
		if next == nil, wrapAround {
			next = firstLeaf(of: results)
		}
		showResultNode(next)
	}

	/// Select the previous match result, optionally wrapping around.
	public func selectPreviousResult(wrapAround: Bool) {
		guard let results else { return }
		let row = outlineView.selectedRow
		let current = row >= 0 ? outlineView.item(atRow: row) as? SearchResultNode : nil

		var prev = previousSibling(of: current)
		if prev == nil, wrapAround {
			prev = lastLeaf(of: results)
		}
		showResultNode(prev)
	}

	/// Select the first match in the next file group.
	public func selectNextDocument() {
		guard let results else { return }
		let row = outlineView.selectedRow
		let current = row >= 0 ? outlineView.item(atRow: row) as? SearchResultNode : nil
		let parent = current?.parent

		if let parent, let parentIdx = results.children.firstIndex(where: { $0 === parent }) {
			let nextIdx = parentIdx + 1
			if nextIdx < results.children.count {
				showResultNode(results.children[nextIdx].children.first)
			} else {
				showResultNode(results.children.first?.children.first)
			}
		} else {
			showResultNode(results.children.first?.children.first)
		}
	}

	/// Select the first match in the previous file group.
	public func selectPreviousDocument() {
		guard let results else { return }
		let row = outlineView.selectedRow
		let current = row >= 0 ? outlineView.item(atRow: row) as? SearchResultNode : nil
		let parent = current?.parent

		if let parent, let parentIdx = results.children.firstIndex(where: { $0 === parent }) {
			let prevIdx = parentIdx - 1
			if prevIdx >= 0 {
				showResultNode(results.children[prevIdx].children.first)
			} else {
				showResultNode(results.children.last?.children.first)
			}
		} else {
			showResultNode(results.children.last?.children.first)
		}
	}

	/// Toggle between collapsed and expanded state for all groups.
	public func toggleCollapsedState() {
		if isCollapsed {
			outlineView.expandItem(nil, expandChildren: true)
		} else {
			outlineView.collapseItem(nil, collapseChildren: true)
		}
	}

	/// Whether more than half the groups are collapsed.
	public var isCollapsed: Bool {
		guard let results, !results.children.isEmpty else { return false }
		let expanded = results.children.count(where: { outlineView.isItemExpanded($0) })
		return 2 * expanded <= results.children.count
	}

	// MARK: - Private Setup

	private func loadResultsFont() {
		let defaults = UserDefaults.standard
		let fontSize = defaults.float(forKey: "searchResultsFontSize")
		let size = fontSize > 0 ? CGFloat(fontSize) : 11.0

		if let fontName = defaults.string(forKey: "searchResultsFontName"),
		   let font = NSFont(name: fontName, size: size)
		{
			resultsFont = font
		} else {
			resultsFont = .monospacedSystemFont(ofSize: size, weight: .regular)
		}
	}

	private func configureOutlineView() {
		outlineView.focusRingType = .none
		outlineView.allowsMultipleSelection = true
		outlineView.autoresizesOutlineColumn = false
		outlineView.usesAlternatingRowBackgroundColors = true
		outlineView.headerView = nil
		outlineView.rowHeight = max(lineHeight(), 14)
		outlineView.columnAutoresizingStyle = .noColumnAutoresizing
		outlineView.style = .plain
		outlineView.floatsGroupRows = false

		let checkboxCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("checkbox"))
		checkboxCol.width = 50
		outlineView.addTableColumn(checkboxCol)
		outlineView.outlineTableColumn = checkboxCol

		let matchCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("match"))
		matchCol.isEditable = false
		outlineView.addTableColumn(matchCol)

		outlineView.dataSource = self
		outlineView.delegate = self
		outlineView.target = self
		outlineView.action = #selector(didSingleClick(_:))
		outlineView.doubleAction = #selector(didDoubleClick(_:))
	}

	private func configureScrollView() {
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		scrollView.documentView = outlineView
	}

	private func lineHeight() -> CGFloat {
		let label = NSTextField(labelWithString: "m")
		label.font = resultsFont
		label.sizeToFit()
		return max(
			label.frame.height,
			ceil(resultsFont.ascender) + ceil(abs(resultsFont.descender)) + ceil(resultsFont.leading),
		)
	}

	private func makeSeparator() -> NSView {
		let box = NSBox()
		box.boxType = .separator
		return box
	}

	private func updateCheckBoxVisibility() {
		guard isViewLoaded else { return }
		let checkboxCol = outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("checkbox"))
		checkboxCol?.isHidden = hideCheckBoxes
		let outlineID = hideCheckBoxes ? "match" : "checkbox"
		outlineView.outlineTableColumn = outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(outlineID))
	}

	// MARK: - Navigation Helpers

	private func nextSibling(of node: SearchResultNode?) -> SearchResultNode? {
		guard let node, let parent = node.parent else { return nil }
		guard let idx = parent.children.firstIndex(where: { $0 === node }) else { return nil }
		let nextIdx = idx + 1
		if nextIdx < parent.children.count {
			return leafOrFirstChild(parent.children[nextIdx])
		}
		// Move to next parent's first child
		if let grandparent = parent.parent,
		   let parentIdx = grandparent.children.firstIndex(where: { $0 === parent }),
		   parentIdx + 1 < grandparent.children.count
		{
			return grandparent.children[parentIdx + 1].children.first
		}
		return nil
	}

	private func previousSibling(of node: SearchResultNode?) -> SearchResultNode? {
		guard let node, let parent = node.parent else { return nil }
		guard let idx = parent.children.firstIndex(where: { $0 === node }) else { return nil }
		if idx > 0 {
			return leafOrLastChild(parent.children[idx - 1])
		}
		// Move to previous parent's last child
		if let grandparent = parent.parent,
		   let parentIdx = grandparent.children.firstIndex(where: { $0 === parent }),
		   parentIdx > 0
		{
			return grandparent.children[parentIdx - 1].children.last
		}
		return nil
	}

	private func firstLeaf(of root: SearchResultNode) -> SearchResultNode? {
		root.children.first?.children.first
	}

	private func lastLeaf(of root: SearchResultNode) -> SearchResultNode? {
		root.children.last?.children.last
	}

	private func leafOrFirstChild(_ node: SearchResultNode) -> SearchResultNode {
		node.children.isEmpty ? node : (node.children.first ?? node)
	}

	private func leafOrLastChild(_ node: SearchResultNode) -> SearchResultNode {
		node.children.isEmpty ? node : (node.children.last ?? node)
	}

	// MARK: - Actions

	@objc private func didSingleClick(_: Any) {
		let row = outlineView.clickedRow
		guard row >= 0, outlineView.numberOfSelectedRows == 1 else { return }
		guard let node = outlineView.item(atRow: row) as? SearchResultNode else { return }
		notifySelection(node)
	}

	@objc private func didDoubleClick(_: Any) {
		let row = outlineView.clickedRow
		guard row >= 0 else { return }
		guard let node = outlineView.item(atRow: row) as? SearchResultNode else { return }
		notifySelection(node)
		onDoubleClickResult?(node)
	}

	private func notifySelection(_ node: SearchResultNode) {
		guard lastSelectedResult !== node else { return }
		lastSelectedResult = node
		onSelectResult?(node)
		Task { @MainActor in
			lastSelectedResult = nil
		}
	}
}

// MARK: - NSOutlineViewDataSource

extension FindResultsViewController: NSOutlineViewDataSource {
	public func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		let node = (item as? SearchResultNode) ?? results
		return node?.children.count ?? 0
	}

	public func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
		guard let node = item as? SearchResultNode else { return false }
		return !node.children.isEmpty
	}

	public func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		let node = (item as? SearchResultNode) ?? results
		return node!.children[index]
	}
}

// MARK: - NSOutlineViewDelegate

extension FindResultsViewController: NSOutlineViewDelegate {
	public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		// Don't select group (file) rows directly
		outlineView.level(forItem: item) > 0
	}

	public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
		outlineView.level(forItem: item) == 0
	}

	public func outlineView(_: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? SearchResultNode else { return nil }
		let columnID = tableColumn?.identifier.rawValue ?? "group"

		if columnID == "checkbox" {
			return makeCheckboxCell(for: node)
		} else if columnID == "match" {
			return makeMatchCell(for: node)
		} else {
			return makeHeaderCell(for: node)
		}
	}

	public func outlineViewSelectionDidChange(_: Notification) {
		guard outlineView.numberOfSelectedRows == 1 else { return }
		let row = outlineView.selectedRowIndexes.first ?? -1
		guard row >= 0, let node = outlineView.item(atRow: row) as? SearchResultNode else { return }
		notifySelection(node)
	}

	// MARK: - Cell Factories

	private func makeCheckboxCell(for node: SearchResultNode) -> NSView {
		let cellView = NSTableCellView()
		let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleExcluded(_:)))
		checkbox.controlSize = .small
		checkbox.state = node.isExcluded ? .off : .on
		checkbox.isEnabled = !node.isReadOnly
		checkbox.translatesAutoresizingMaskIntoConstraints = false
		cellView.addSubview(checkbox)
		NSLayoutConstraint.activate([
			checkbox.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
			checkbox.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
		])
		return cellView
	}

	private func makeMatchCell(for node: SearchResultNode) -> NSView {
		let cellView = NSTableCellView()
		let textField = NSTextField(labelWithString: "")
		textField.font = resultsFont
		textField.lineBreakMode = .byTruncatingTail
		textField.setContentHuggingPriority(.required, for: .horizontal)
		textField.setContentCompressionResistancePriority(.required, for: .horizontal)
		textField.translatesAutoresizingMaskIntoConstraints = false
		cellView.addSubview(textField)
		cellView.textField = textField

		NSLayoutConstraint.activate([
			textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
			textField.topAnchor.constraint(equalTo: cellView.topAnchor),
			textField.bottomAnchor.constraint(equalTo: cellView.bottomAnchor),
		])

		if case let .match(docMatch) = node.type {
			textField.attributedStringValue = Self.attributedExcerpt(for: docMatch, font: resultsFont)
		}

		return cellView
	}

	private func makeHeaderCell(for node: SearchResultNode) -> NSView {
		let cellView = NSTableCellView()

		let imageView = NSImageView()
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.image = NSWorkspace.shared.icon(for: .plainText)
		imageView.imageScaling = .scaleProportionallyDown

		let textField = NSTextField(labelWithString: "")
		textField.font = .systemFont(ofSize: NSFont.systemFontSize)
		textField.lineBreakMode = .byTruncatingMiddle
		textField.setContentHuggingPriority(.required, for: .horizontal)
		textField.translatesAutoresizingMaskIntoConstraints = false

		let countBadge = NSButton()
		countBadge.bezelStyle = .inline
		countBadge.font = .labelFont(ofSize: NSFont.labelFontSize)
		countBadge.title = "\(node.matchCount)"
		countBadge.translatesAutoresizingMaskIntoConstraints = false
		countBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

		for v in [imageView, textField, countBadge] {
			cellView.addSubview(v)
		}

		if case let .file(_, displayName) = node.type {
			textField.stringValue = displayName
		}

		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 9),
			imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
			imageView.widthAnchor.constraint(equalToConstant: 16),
			imageView.heightAnchor.constraint(equalToConstant: 16),

			textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 3),
			textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),

			countBadge.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 4),
			countBadge.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
		])

		cellView.textField = textField
		cellView.imageView = imageView

		return cellView
	}

	@objc private func toggleExcluded(_ sender: NSButton) {
		let row = outlineView.row(for: sender)
		guard row >= 0, let node = outlineView.item(atRow: row) as? SearchResultNode else { return }
		node.isExcluded = sender.state == .off
	}

	// MARK: - Attributed Excerpt

	/// Build an attributed string for a match excerpt with the matched portion highlighted.
	static func attributedExcerpt(for match: DocumentMatch, font: NSFont) -> NSAttributedString {
		let result = NSMutableAttributedString()

		let regularAttrs: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: NSColor.textColor,
		]

		let matchAttrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.boldSystemFont(ofSize: font.pointSize),
			.foregroundColor: NSColor.textColor,
			.backgroundColor: NSColor.findHighlightColor,
			.underlineStyle: NSUnderlineStyle.single.rawValue,
			.underlineColor: NSColor.systemOrange,
		]

		// Line number prefix
		let linePrefix = "\(match.lineNumber + 1):\t"
		result.append(NSAttributedString(string: linePrefix, attributes: regularAttrs))

		// Excerpt with highlighted match
		let excerpt = match.excerpt
		let matchByteStart = match.byteRange.lowerBound - match.excerptOffset
		let matchByteEnd = match.byteRange.upperBound - match.excerptOffset

		let excerptUTF8 = Array(excerpt.utf8)
		let safeStart = max(0, min(matchByteStart, excerptUTF8.count))
		let safeEnd = max(safeStart, min(matchByteEnd, excerptUTF8.count))

		if let before = String(bytes: excerptUTF8[0 ..< safeStart], encoding: .utf8) {
			result.append(NSAttributedString(string: before, attributes: regularAttrs))
		}

		if let matched = String(bytes: excerptUTF8[safeStart ..< safeEnd], encoding: .utf8) {
			result.append(NSAttributedString(string: matched, attributes: matchAttrs))
		}

		if let after = String(bytes: excerptUTF8[safeEnd...], encoding: .utf8) {
			result.append(NSAttributedString(string: after, attributes: regularAttrs))
		}

		return result
	}
}
#endif
