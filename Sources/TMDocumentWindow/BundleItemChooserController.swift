#if canImport(AppKit)
import AppKit
import TMFilterList

/// Concrete chooser controller for the "Select Bundle Item…" (⌃⌘T) panel.
///
/// Wraps `BundleItemChooserState` and `ChooserPanelController` to provide
/// fuzzy search across bundle commands, snippets, grammars, and themes.
@MainActor
public final class BundleItemChooserController: ChooserPanelController, NSTableViewDataSource, NSTableViewDelegate {
	/// The underlying bundle item chooser state.
	private let state = BundleItemChooserState()

	/// Callback invoked when the user selects a bundle item.
	/// Parameter: the item identifier (UUID).
	public var onSelectItem: ((String) -> Void)?

	public init() {
		super.init(title: "Select Bundle Item")
		delegate = self
		tableView.dataSource = self
		tableView.delegate = self
		tableView.rowHeight = 24
	}

	/// Populate the chooser with bundle item descriptors.
	public func populate(with descriptors: [BundleItemDescriptor]) {
		state.populateItems(descriptors)
		state.refilter()
		items = state.filteredItems
	}

	/// Set the active scope context for filtering.
	public func setScopeContext(_ scope: String?) {
		state.scopeContext = scope
	}

	// MARK: - ChooserPanelController Overrides

	override public func updateItems(_: Any?) {
		state.updateFilter(filterString)
		items = state.filteredItems
	}

	override public func updateStatusText() {
		let count = state.filteredItems.count
		let total = state.allItems.count
		statusTextField.stringValue = count == total ? "" : "\(count) of \(total)"
	}

	// MARK: - NSTableViewDataSource

	public func numberOfRows(in _: NSTableView) -> Int {
		items.count
	}

	// MARK: - NSTableViewDelegate

	public func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
		guard row < items.count, let item = items[row] as? BundleChooserItem else { return nil }

		let cellID = NSUserInterfaceItemIdentifier("BundleItemCell")
		let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? BundleItemCellView
			?? BundleItemCellView(frame: .zero)
		cell.identifier = cellID
		cell.configure(with: item)
		return cell
	}
}

// MARK: - ChooserPanelDelegate

extension BundleItemChooserController: ChooserPanelDelegate {
	public func chooserPanel(_: ChooserPanelController, didSelectItems selectedItems: [any ChooserItem]) {
		guard let bundleItem = selectedItems.first as? BundleChooserItem else { return }
		state.learnSelection(identifier: bundleItem.itemIdentifier)
		onSelectItem?(bundleItem.itemIdentifier)
	}

	public func chooserPanelDidCancel(_: ChooserPanelController) {}
}

#endif
