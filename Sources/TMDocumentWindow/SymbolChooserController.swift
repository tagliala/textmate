#if canImport(AppKit)
import AppKit
import TMFilterList

/// Concrete chooser controller for the "Jump to Symbol…" panel.
///
/// Wraps `SymbolChooserState` and `ChooserPanelController` to provide
/// fuzzy search across document symbols.
@MainActor
public final class SymbolChooserController: ChooserPanelController, NSTableViewDataSource, NSTableViewDelegate {
	/// The underlying symbol chooser state.
	private let state = SymbolChooserState()

	/// Callback invoked when the user selects a symbol.
	/// Parameter: the symbol's selection string (e.g. line number).
	public var onSelectSymbol: ((String) -> Void)?

	public init() {
		super.init(title: "Jump to Symbol")
		delegate = self
		tableView.dataSource = self
		tableView.delegate = self
		tableView.rowHeight = 24
	}

	/// Populate the chooser with symbol descriptors from the document.
	public func populate(documentName: String, symbols: [SymbolDescriptor]) {
		state.documentName = documentName
		state.setSymbols(symbols)
		state.refilter()
		items = state.filteredItems
	}

	// MARK: - ChooserPanelController Overrides

	override public func updateItems(_: Any?) {
		state.updateFilter(filterString)
		items = state.filteredItems
	}

	override public func updateStatusText() {
		statusTextField.stringValue = state.documentName
	}

	// MARK: - NSTableViewDataSource

	public func numberOfRows(in _: NSTableView) -> Int {
		items.count
	}

	// MARK: - NSTableViewDelegate

	public func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
		guard row < items.count, let item = items[row] as? SymbolChooserItem else { return nil }

		let cellID = NSUserInterfaceItemIdentifier("SymbolCell")
		let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView
			?? NSTableCellView(frame: .zero)
		cell.identifier = cellID

		if cell.textField == nil {
			let label = NSTextField(labelWithString: "")
			label.translatesAutoresizingMaskIntoConstraints = false
			cell.addSubview(label)
			cell.textField = label
			NSLayoutConstraint.activate([
				label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
				label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
				label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			])
		}

		if !item.nameCoverRanges.isEmpty {
			cell.textField?.attributedStringValue = MatchHighlighter.attributedString(
				for: item.symbolName,
				coverRanges: item.nameCoverRanges,
				lineBreakMode: .byTruncatingTail,
			)
		} else {
			cell.textField?.stringValue = item.symbolName
		}

		return cell
	}
}

// MARK: - ChooserPanelDelegate

extension SymbolChooserController: ChooserPanelDelegate {
	public func chooserPanel(_: ChooserPanelController, didSelectItems selectedItems: [any ChooserItem]) {
		guard let symbolItem = selectedItems.first as? SymbolChooserItem else { return }
		onSelectSymbol?(symbolItem.selectionString)
	}

	public func chooserPanelDidCancel(_: ChooserPanelController) {}
}

#endif
