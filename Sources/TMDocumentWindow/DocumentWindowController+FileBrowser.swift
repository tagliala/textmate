import AppKit
import TMFileBrowser

// MARK: - FileBrowserDelegate Conformance

/// Handles file browser events: opening and closing files from the sidebar.
extension DocumentWindowController: FileBrowserDelegate {
	public func fileBrowser(_: FileBrowserViewController, openURLs urls: [URL]) {
		for url in urls {
			openFile(at: url)
		}
	}

	public func fileBrowser(_: FileBrowserViewController, closeURL url: URL) {
		guard let idx = documents.firstIndex(where: { $0.path == url.path }) else { return }
		closeTabsAtIndexes(
			IndexSet(integer: idx),
			askToSaveChanges: true,
			createDocumentIfEmpty: true,
			activate: true,
		)
	}

	public func fileBrowserSelectionDidChange(_: FileBrowserViewController) {
		Self.scheduleSessionBackup()
	}
}
