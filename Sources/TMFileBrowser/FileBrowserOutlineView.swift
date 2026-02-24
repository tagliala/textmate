#if canImport(AppKit)
import AppKit

/// Extended delegate protocol for the file browser outline view.
///
/// Port of `FileBrowserOutlineViewDelegate` from `FileBrowserOutlineView.h`.
/// Adds will/did expand/collapse and trash notifications that the standard
/// `NSOutlineViewDelegate` doesn't provide.
@MainActor
public protocol FileBrowserOutlineViewDelegate: NSOutlineViewDelegate {
	/// Called before an item is about to be expanded.
	func outlineView(_ outlineView: NSOutlineView, willExpandItem item: Any, expandChildren: Bool)

	/// Called after an item has been expanded.
	func outlineView(_ outlineView: NSOutlineView, didExpandItem item: Any, expandChildren: Bool)

	/// Called before an item is about to be collapsed.
	func outlineView(_ outlineView: NSOutlineView, willCollapseItem item: Any, collapseChildren: Bool)

	/// Called after an item has been collapsed.
	func outlineView(_ outlineView: NSOutlineView, didCollapseItem item: Any, collapseChildren: Bool)

	/// Called when URLs have been trashed via the outline view.
	func outlineView(_ outlineView: NSOutlineView, didTrashURLs urls: [URL])
}

/// Default implementations so conformers only need to implement what they use.
public extension FileBrowserOutlineViewDelegate {
	func outlineView(_: NSOutlineView, willExpandItem _: Any, expandChildren _: Bool) {}
	func outlineView(_: NSOutlineView, didExpandItem _: Any, expandChildren _: Bool) {}
	func outlineView(_: NSOutlineView, willCollapseItem _: Any, collapseChildren _: Bool) {}
	func outlineView(_: NSOutlineView, didCollapseItem _: Any, collapseChildren _: Bool) {}
	func outlineView(_: NSOutlineView, didTrashURLs _: [URL]) {}
}

/// A custom `NSOutlineView` subclass for the file browser.
///
/// Port of `FileBrowserOutlineView` from `FileBrowserOutlineView.mm`.
/// Intercepts expand/collapse notifications to provide the extended
/// delegate protocol, and handles keyboard shortcuts for file operations.
@MainActor
public class FileBrowserOutlineView: NSOutlineView {
	/// Whether the current expand/collapse includes children.
	private var expandingChildren = false

	// MARK: - Expand/Collapse with Children

	override public func expandItem(_ item: Any?, expandChildren: Bool) {
		expandingChildren = expandChildren
		if let delegate = delegate as? FileBrowserOutlineViewDelegate, let item {
			delegate.outlineView(self, willExpandItem: item, expandChildren: expandChildren)
		}
		super.expandItem(item, expandChildren: expandChildren)
		if let delegate = delegate as? FileBrowserOutlineViewDelegate, let item {
			delegate.outlineView(self, didExpandItem: item, expandChildren: expandChildren)
		}
		expandingChildren = false
	}

	override public func collapseItem(_ item: Any?, collapseChildren: Bool) {
		expandingChildren = collapseChildren
		if let delegate = delegate as? FileBrowserOutlineViewDelegate, let item {
			delegate.outlineView(self, willCollapseItem: item, collapseChildren: collapseChildren)
		}
		super.collapseItem(item, collapseChildren: collapseChildren)
		if let delegate = delegate as? FileBrowserOutlineViewDelegate, let item {
			delegate.outlineView(self, didCollapseItem: item, collapseChildren: collapseChildren)
		}
		expandingChildren = false
	}

	// MARK: - Keyboard Handling

	override public func keyDown(with event: NSEvent) {
		if event.charactersIgnoringModifiers == String(Character(UnicodeScalar(NSDeleteCharacter)!)),
		   event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
		{
			// ⌘-Delete: Move to Trash
			performTrash()
			return
		}
		super.keyDown(with: event)
	}

	/// Performs the trash operation on selected items.
	private func performTrash() {
		let selectedRows = selectedRowIndexes
		var urls: [URL] = []

		for row in selectedRows {
			if let item = item(atRow: row) as? FileItem,
			   item.URL.isFileURL
			{
				urls.append(item.URL)
			}
		}

		guard !urls.isEmpty else { return }

		var trashedURLs: [URL] = []
		for url in urls {
			var resultingURL: NSURL?
			do {
				try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
				trashedURLs.append(url)
			} catch {
				NSApp.presentError(error)
			}
		}

		if !trashedURLs.isEmpty,
		   let delegate = delegate as? FileBrowserOutlineViewDelegate
		{
			delegate.outlineView(self, didTrashURLs: trashedURLs)
		}
	}

	// MARK: - Menu Support

	override public func menu(for event: NSEvent) -> NSMenu? {
		let point = convert(event.locationInWindow, from: nil)
		let row = row(at: point)

		// If right-clicking on an unselected row, select it first
		if row >= 0, !selectedRowIndexes.contains(row) {
			selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		}

		return menu
	}
}
#endif
