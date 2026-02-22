#if canImport(AppKit)
import AppKit
import TMFilterList

/// Concrete chooser controller for the "Open Quickly…" (⌘T) file panel.
///
/// Wraps `FileChooserState` and `ChooserPanelController` to provide fuzzy
/// file search within the project, open documents, or uncommitted files.
@MainActor
public final class FileChooserController: ChooserPanelController, NSTableViewDataSource, NSTableViewDelegate {
	/// The underlying file chooser state.
	private let state: FileChooserState

	/// Callback invoked when the user selects a file.
	/// Parameters: file path, optional selection string (line number), optional symbol string.
	public var onSelectFile: ((String, String?, String?) -> Void)?

	/// Callback invoked when the user clicks the close button on an open document cell.
	public var onCloseDocument: ((String) -> Void)?

	public init(projectPath: String) {
		state = FileChooserState(projectPath: projectPath)
		super.init(title: "Open Quickly")
		delegate = self
		tableView.dataSource = self
		tableView.delegate = self
	}

	/// Pre-populate open document paths and uncommitted paths before showing.
	public func setOpenDocuments(_ paths: [String]) {
		state.openDocuments = paths
	}

	public func setUncommittedFiles(_ paths: [String]) {
		state.uncommittedFiles = paths
	}

	public func setCurrentDocumentPath(_ path: String?) {
		state.currentDocumentPath = path
	}

	/// Show the panel and begin asynchronous file enumeration.
	public func showAndEnumerate(relativeTo parentFrame: NSRect) {
		showWindow(relativeTo: parentFrame)
		Task { @MainActor in
			await state.enumerateFiles()
			state.refilter()
			items = state.filteredItems
		}
	}

	// MARK: - ChooserPanelController Overrides

	override public func updateItems(_: Any?) {
		state.updateFilter(filterString)
		items = state.filteredItems
	}

	override public func updateStatusText() {
		let parsed = state.parsedFilter
		var parts: [String] = []
		if let sel = parsed.selectionString {
			parts.append("Line: \(sel)")
		}
		if let sym = parsed.symbolString {
			parts.append("Symbol: \(sym)")
		}
		statusTextField.stringValue = parts.joined(separator: "  ")
	}

	// MARK: - NSTableViewDataSource

	public func numberOfRows(in _: NSTableView) -> Int {
		items.count
	}

	// MARK: - NSTableViewDelegate

	public func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
		guard row < items.count, let item = items[row] as? FileChooserItem else { return nil }

		let cellID = NSUserInterfaceItemIdentifier("FileChooserCell")
		let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? FileChooserCellView
			?? FileChooserCellView(frame: .zero)
		cell.identifier = cellID
		cell.configure(with: item)
		cell.showCloseButton = item.isOpenDocument
		cell.onClose = { [weak self] in
			self?.onCloseDocument?(item.path)
		}
		return cell
	}
}

// MARK: - ChooserPanelDelegate

extension FileChooserController: ChooserPanelDelegate {
	public func chooserPanel(_: ChooserPanelController, didSelectItems selectedItems: [any ChooserItem]) {
		guard let fileItem = selectedItems.first as? FileChooserItem else { return }
		state.learnSelection(path: fileItem.path)
		let parsed = state.parsedFilter
		onSelectFile?(fileItem.path, parsed.selectionString, parsed.symbolString)
	}

	public func chooserPanelDidCancel(_: ChooserPanelController) {}
}

#endif
