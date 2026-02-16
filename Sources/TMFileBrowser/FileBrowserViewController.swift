#if canImport(AppKit)
import AppKit
import Foundation
import QuickLookUI

// MARK: - Delegate Protocol

/// Delegate protocol for file browser events.
///
/// Port of `FileBrowserDelegate` from `FileBrowserViewController.h`.
@MainActor
public protocol FileBrowserDelegate: AnyObject {
	func fileBrowser(_ fileBrowser: FileBrowserViewController, openURLs urls: [URL])
	func fileBrowser(_ fileBrowser: FileBrowserViewController, closeURL url: URL)
}

// MARK: - File Browser View Controller

/// Main file browser sidebar controller with navigation, file operations,
/// outline view data source, drag-and-drop, QuickLook, and session state.
///
/// Port of `FileBrowserViewController` from `FileBrowserViewController.mm`.
@MainActor
public class FileBrowserViewController: NSViewController,
	NSOutlineViewDataSource,
	NSOutlineViewDelegate,
	NSMenuDelegate,
	NSTextFieldDelegate
{
	// MARK: - Properties

	public weak var delegate: FileBrowserDelegate?

	/// The root file item for the current location.
	public private(set) var fileItem: FileItem?

	/// Navigation history.
	private var history: [HistoryEntry] = []
	private var historyIndex: Int = -1

	/// Tracks expanded/selected URLs across reloads.
	private var pendingExpandedURLs: Set<URL> = []
	private var pendingSelectedURLs: Set<URL> = []

	/// The composite view.
	private var fileBrowserView: FileBrowserCompositeView!

	/// Disk operation handler.
	private let diskOperations = DiskOperationHandler()

	/// QuickLook preview items.
	private var previewItems: [FileItem] = []

	/// User preferences.
	public var canExpandSymbolicLinks: Bool = false {
		didSet { reloadExpandability() }
	}

	public var canExpandPackages: Bool = false {
		didSet { reloadExpandability() }
	}

	public var sortDirectoriesBeforeFiles: Bool = false {
		didSet { rearrangeAll() }
	}

	public var showExcludedItems: Bool = false {
		didSet { rearrangeAll() }
	}

	/// Expand/collapse counters for child expansion tracking.
	private var expandingChildrenCounter = 0
	private var collapsingChildrenCounter = 0
	private var nestedCollapsingChildrenCounter = 0

	/// File item directory observers.
	private nonisolated(unsafe) var directoryObserverTokens: [URL: FileItem.DirectoryObserver] = [:]

	/// Loading state.
	private var loadingURLs: Set<URL> = []
	private var loadingCompletionHandlers: [() -> Void] = []

	// MARK: - Computed Properties

	/// The current location URL.
	public var url: URL? {
		fileItem?.url
	}

	/// The current location path.
	public var path: String? {
		url?.path
	}

	/// Whether back navigation is available.
	public var canGoBack: Bool {
		historyIndex > 0
	}

	/// Whether forward navigation is available.
	public var canGoForward: Bool {
		historyIndex + 1 < history.count
	}

	/// The outline view.
	public var outlineView: FileBrowserOutlineView {
		fileBrowserView.outlineView
	}

	/// URLs of selected file items.
	public var selectedFileURLs: [URL] {
		selectedItems.compactMap { $0.url.isFileURL ? $0.url : nil }
	}

	/// Currently selected items.
	public var selectedItems: [FileItem] {
		let outlineView = outlineView
		let clickedRow = outlineView.clickedRow

		let indexSet: IndexSet = if clickedRow >= 0, clickedRow < outlineView.numberOfRows,
		                            !outlineView.selectedRowIndexes.contains(clickedRow)
		{
			IndexSet(integer: clickedRow)
		} else {
			outlineView.selectedRowIndexes
		}

		return indexSet.compactMap { outlineView.item(atRow: $0) as? FileItem }
	}

	/// Items that can be previewed (have a previewItemURL).
	public var previewableItems: [FileItem] {
		selectedItems.filter { $0.previewItemURL != nil }
	}

	/// The directory URL where new items should be created.
	public var directoryURLForNewItems: URL? {
		var candidates: [URL] = []
		for item in selectedItems {
			let resolved = item.resolvedURL
			if resolved.isFileURL, outlineView.isItemExpanded(item) {
				candidates.append(resolved)
			} else if let parentItem = outlineView.parent(forItem: item) as? FileItem,
			          parentItem.resolvedURL.isFileURL
			{
				candidates.append(parentItem.resolvedURL)
			}
		}
		return candidates.last ?? fileItem?.url
	}

	// MARK: - History Entry

	private struct HistoryEntry {
		var url: URL
		var scrollOffset: CGFloat?
	}

	// MARK: - Initialization

	public init() {
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		let tokens = directoryObserverTokens
		MainActor.assumeIsolated {
			for token in tokens.values {
				FileItem.removeObserver(token)
			}
		}
	}

	// MARK: - View Lifecycle

	override public func loadView() {
		fileBrowserView = FileBrowserCompositeView()

		// Configure outline view
		let ov = fileBrowserView.outlineView
		ov.dataSource = self
		ov.delegate = self
		ov.target = self
		ov.action = #selector(didSingleClickOutlineView(_:))
		ov.doubleAction = #selector(didDoubleClickOutlineView(_:))
		ov.menu = NSMenu()
		ov.menu?.delegate = self

		// Configure header buttons
		let header = fileBrowserView.headerView
		header.goBackButton.target = self
		header.goBackButton.action = #selector(goBack(_:))
		header.goBackButton.isEnabled = false
		header.goForwardButton.target = self
		header.goForwardButton.action = #selector(goForward(_:))
		header.goForwardButton.isEnabled = false

		// Configure actions buttons
		let actions = fileBrowserView.actionsView
		actions.createButton.action = #selector(newFileAction(_:))
		actions.reloadButton.target = self
		actions.reloadButton.action = #selector(reload(_:))
		actions.favoritesButton.target = self
		actions.favoritesButton.action = #selector(goToFavorites(_:))
		actions.scmButton.target = self
		actions.scmButton.action = #selector(goToSCMDataSource(_:))

		// Configure disk operations callbacks
		diskOperations.window = view.window
		diskOperations.onItemsInserted = { [weak self] urls in
			self?.insertURLsInOutline(urls) ?? []
		}
		diskOperations.onItemsRemoved = { [weak self] urls in
			self?.removeURLsFromOutline(urls)
		}
		diskOperations.onItemsMoved = { [weak self] srcURLs, destURLs in
			self?.moveURLsInOutline(from: srcURLs, to: destURLs) ?? []
		}

		view = fileBrowserView
	}

	// MARK: - Navigation

	/// Navigate to the given URL.
	@objc public func goToURL(_ url: URL) {
		guard self.url != url else { return }
		addHistoryURL(url)
	}

	/// Navigate back in history.
	@IBAction public func goBack(_: Any?) {
		guard canGoBack else { return }
		historyIndex -= 1
		applyHistoryIndex()
	}

	/// Navigate forward in history.
	@IBAction public func goForward(_: Any?) {
		guard canGoForward else { return }
		historyIndex += 1
		applyHistoryIndex()
	}

	/// Navigate to the parent folder.
	@IBAction public func goToParentFolder(_: Any?) {
		guard let parentURL = fileItem?.parentURL else { return }
		let cameFromURL = url
		goToURL(parentURL)
		if let cameFromURL {
			expandURLs(nil, selectURLs: [cameFromURL])
		}
	}

	/// Navigate to Computer.
	@IBAction public func goToComputer(_: Any?) {
		goToURL(FileBrowserLocation.computer)
	}

	/// Navigate to Home directory.
	@IBAction public func goToHome(_: Any?) {
		goToURL(URL(fileURLWithPath: NSHomeDirectory()))
	}

	/// Navigate to Desktop.
	@IBAction public func goToDesktop(_: Any?) {
		if let desktopURL = try? FileManager.default.url(
			for: .desktopDirectory, in: .userDomainMask,
			appropriateFor: nil, create: true,
		) {
			goToURL(desktopURL)
		}
	}

	/// Navigate to Favorites.
	@IBAction public func goToFavorites(_ sender: Any?) {
		if url != FileBrowserLocation.favorites {
			goToURL(FileBrowserLocation.favorites)
		} else if canGoBack {
			goBack(sender)
		}
	}

	/// Navigate to the SCM data source.
	@IBAction public func goToSCMDataSource(_: Any?) {
		guard let currentURL = url else { return }

		if currentURL.scheme == "file" {
			// Build SCM URL from file path
			if let encoded = currentURL.path.addingPercentEncoding(
				withAllowedCharacters: .urlPathAllowed,
			) {
				let scmURL = URL(string: "scm://localhost\(encoded)/")!
				goToURL(scmURL)
			}
		} else if currentURL.scheme == "scm" {
			if canGoBack {
				goBack(self)
			} else if let parentURL = fileItem?.parentURL {
				goToURL(parentURL)
			}
		} else {
			NSSound.beep()
		}
	}

	/// Show an Open Panel to navigate to any folder.
	@IBAction public func orderFrontGoToFolder(_: Any?) {
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		panel.directoryURL = url

		panel.beginSheetModal(for: view.window!) { [weak self] response in
			if response == .OK, let url = panel.urls.last {
				self?.goToURL(url)
			}
		}
	}

	/// Toggle visibility of hidden/excluded files.
	@IBAction public func toggleShowInvisibles(_: Any?) {
		showExcludedItems = !showExcludedItems
	}

	/// Reload the file browser contents.
	@IBAction public func reload(_: Any?) {
		guard let root = fileItem else { return }
		var stack: [FileItem] = [root]
		while !stack.isEmpty {
			let item = stack.removeFirst()
			guard item.arrangedChildren != nil else { continue }
			// Trigger FSEvents reload for the directory
			stack.append(contentsOf: item.arrangedChildren ?? [])
		}
	}

	/// Deselect all items.
	@IBAction public func deselectAll(_ sender: Any?) {
		outlineView.deselectAll(sender)
	}

	// MARK: - History Management

	private func addHistoryURL(_ url: URL) {
		// Trim forward history
		if historyIndex + 1 < history.count {
			history.removeSubrange((historyIndex + 1)...)
		}

		// Update scroll offset of current entry
		if !history.isEmpty {
			let scrollOffset = outlineView.visibleRect.minY
			history[history.count - 1].scrollOffset = scrollOffset
		}

		history.append(HistoryEntry(url: url))
		historyIndex = history.count - 1
		applyHistoryIndex()
	}

	private func applyHistoryIndex() {
		guard historyIndex >= 0, historyIndex < history.count else { return }
		let entry = history[historyIndex]
		setURL(entry.url)
		updateNavigationButtons()
	}

	private func updateNavigationButtons() {
		fileBrowserView?.headerView.goBackButton.isEnabled = canGoBack
		fileBrowserView?.headerView.goForwardButton.isEnabled = canGoForward
	}

	// MARK: - URL / FileItem Management

	/// Set the root URL and reload the tree.
	public func setURL(_ url: URL) {
		let item = FileItem(url: url)
		setFileItem(item)
	}

	private func setFileItem(_ item: FileItem) {
		// Remove existing observers
		for token in directoryObserverTokens.values {
			FileItem.removeObserver(token)
		}
		directoryObserverTokens.removeAll()

		// Save expanded/selected state
		if fileItem != nil {
			pendingExpandedURLs = computeExpandedURLs()
			pendingSelectedURLs = computeSelectedURLs()
		}

		fileItem = item

		outlineView.reloadData()
		outlineView.deselectAll(self)
		outlineView.scrollRowToVisible(0)

		// Start loading children
		loadChildren(for: item, expandChildren: false)
	}

	/// Select a URL in the outline, expanding parents as needed.
	public func selectURL(_ url: URL, withParentURL parentURL: URL?) {
		// Try to find the item in the current tree
		for i in 0 ..< outlineView.numberOfRows {
			if let item = outlineView.item(atRow: i) as? FileItem,
			   item.url == url
			{
				outlineView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
				centerSelectionInVisibleArea()
				return
			}
		}

		// Need to navigate and expand to find the URL
		if let parentURL {
			goToURL(parentURL)
			expandURLs(nil, selectURLs: [url])
		} else {
			goToURL(url.deletingLastPathComponent())
			expandURLs(nil, selectURLs: [url])
		}
	}

	@objc private func newFileAction(_ sender: Any?) {
		newFile(sender)
	}

	@objc private func newFolderAction(_ sender: Any?) {
		newFolder(sender)
	}

	// MARK: - File Operations

	/// Create a new file in the appropriate directory.
	@discardableResult
	public func newFile(_: Any?) -> URL? {
		guard let dirURL = directoryURLForNewItems else { return nil }

		let newFileURL = dirURL
			.appendingPathComponent("untitled", isDirectory: false)
			.appendingPathExtension("txt")

		let urls = diskOperations.performOperation(
			.newFile, sourceURLs: [],
			destinationURLs: [newFileURL],
			unique: true, select: true,
		)

		if let newURL = urls?.first {
			editNewItemAtURL(newURL)
			return newURL
		}
		return nil
	}

	/// Create a new folder in the appropriate directory.
	@discardableResult
	public func newFolder(_: Any?) -> URL? {
		guard let dirURL = directoryURLForNewItems else { return nil }

		let newFolderURL = dirURL.appendingPathComponent("untitled folder", isDirectory: true)

		let urls = diskOperations.performOperation(
			.newFolder, sourceURLs: [],
			destinationURLs: [newFolderURL],
			unique: true, select: true,
		)

		if let newURL = urls?.first {
			editNewItemAtURL(newURL)
			return newURL
		}
		return nil
	}

	private func editNewItemAtURL(_ url: URL) {
		if outlineView.numberOfSelectedRows == 1 {
			let row = outlineView.selectedRow
			if let item = outlineView.item(atRow: row) as? FileItem,
			   item.url == url
			{
				outlineView.scrollRowToVisible(row)
				outlineView.editColumn(0, row: row, with: nil, select: true)
			}
		}
	}

	/// Perform a file operation via the disk operation handler.
	@discardableResult
	public func performOperation(
		_ operation: DiskOperation,
		urls: [URL: URL],
		unique: Bool,
		select: Bool,
	) -> [URL]? {
		diskOperations.performOperation(
			operation, urls: urls, unique: unique, select: select,
		)
	}

	@discardableResult
	public func performOperation(
		_ operation: DiskOperation,
		sourceURLs: [URL],
		destinationURLs: [URL],
		unique: Bool,
		select: Bool,
	) -> [URL]? {
		diskOperations.performOperation(
			operation,
			sourceURLs: sourceURLs,
			destinationURLs: destinationURLs,
			unique: unique,
			select: select,
		)
	}

	// MARK: - Cut / Copy / Paste

	@IBAction public func cut(_: Any?) {
		let pboard = NSPasteboard.general
		guard writeItems(previewableItems, to: pboard) else { return }
		pboard.setString("cut", forType: NSPasteboard.PasteboardType("OakFileBrowserOperation"))
	}

	@IBAction public func copy(_: Any?) {
		writeItems(previewableItems, to: NSPasteboard.general)
	}

	@IBAction public func copyAsPathname(_: Any?) {
		let pathnames = previewableItems.compactMap(\.url.path)
		let pboard = NSPasteboard.general
		pboard.clearContents()
		pboard.writeObjects(pathnames as [NSString])
	}

	@IBAction public func paste(_: Any?) {
		let pboard = NSPasteboard.general
		let hasOp = pboard.availableType(from: [
			NSPasteboard.PasteboardType("OakFileBrowserOperation"),
		]) != nil
		let isCut = hasOp && pboard.string(
			forType: NSPasteboard.PasteboardType("OakFileBrowserOperation"),
		) == "cut"
		insertItemsFromPasteboard(operation: isCut ? .move : .copy)
	}

	@IBAction public func pasteNext(_: Any?) {
		insertItemsFromPasteboard(operation: .move)
	}

	@IBAction public func createLinkToPasteboardItems(_: Any?) {
		insertItemsFromPasteboard(operation: .link)
	}

	@discardableResult
	private func writeItems(_ items: [FileItem], to pboard: NSPasteboard) -> Bool {
		guard !items.isEmpty else { return false }
		pboard.clearContents()
		let urls = items.map(\.url) as [NSURL]
		pboard.writeObjects(urls)
		if pboard.availableType(from: [.string]) == nil {
			let names = items.compactMap(\.localizedName).joined(separator: "\n")
			pboard.setString(names, forType: .string)
		}
		return true
	}

	private func insertItemsFromPasteboard(operation: DiskOperation) {
		guard let dirURL = directoryURLForNewItems else { return }
		let pboard = NSPasteboard.general
		guard let srcURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return }

		var urlMap: [URL: URL] = [:]
		let fm = FileManager.default
		for srcURL in srcURLs {
			var isDir: ObjCBool = false
			guard fm.fileExists(atPath: srcURL.path, isDirectory: &isDir) else { continue }
			let destURL = dirURL.appendingPathComponent(
				srcURL.lastPathComponent, isDirectory: isDir.boolValue,
			)
			if srcURL != destURL || !operation.contains(.move) {
				urlMap[srcURL] = destURL
			}
		}
		performOperation(operation, urls: urlMap, unique: true, select: true)
	}

	// MARK: - Delete

	@IBAction public func delete(_: Any?) {
		let ov = outlineView
		let selectedIndexes = ov.selectedRowIndexes
		let clickedRow = ov.clickedRow

		// Right-clicked a single item not in the selection
		if clickedRow >= 0, !selectedIndexes.contains(clickedRow) {
			if let item = ov.item(atRow: clickedRow) as? FileItem,
			   let fileURL = item.url as URL?
			{
				performOperation(.trash, sourceURLs: [fileURL], destinationURLs: [], unique: false, select: false)
			}
			return
		}

		// Trash all selected items
		var urlsToTrash: [URL] = []
		var selectItem: FileItem?
		var previousItem: FileItem?
		var stack: [FileItem] = fileItem?.arrangedChildren ?? []

		while !stack.isEmpty {
			let item = stack.removeFirst()
			let row = ov.row(forItem: item)
			if row >= 0, selectedIndexes.contains(row) {
				selectItem = previousItem
				urlsToTrash.append(item.url)
			} else {
				previousItem = item
				if ov.isItemExpanded(item) {
					stack = (item.arrangedChildren ?? []) + stack
				}
			}
		}

		performOperation(.trash, sourceURLs: urlsToTrash, destinationURLs: [], unique: false, select: false)

		// Select nearest remaining item
		let fallback = selectItem ?? fileItem?.arrangedChildren?.first
		if let fallback {
			let selectRow = ov.row(forItem: fallback)
			if selectRow >= 0 {
				ov.selectRowIndexes(IndexSet(integer: selectRow), byExtendingSelection: false)
				ov.scrollRowToVisible(selectRow)
			}
		}
	}

	// MARK: - Duplicate

	@IBAction public func duplicateSelectedEntries(_: Any?) {
		let items = previewableItems
		guard !items.isEmpty else { return }

		var urlMap: [URL: URL] = [:]
		let regex = try! NSRegularExpression(pattern: #"^(.*?)(?: copy(?: \d+)?)?(\.\w+)?$"#)

		for item in items {
			let base = item.url.lastPathComponent
			let range = NSRange(base.startIndex ..< base.endIndex, in: base)
			let name = regex.stringByReplacingMatches(
				in: base, range: range, withTemplate: "$1 copy$2",
			)
			urlMap[item.url] = item.url
				.deletingLastPathComponent()
				.appendingPathComponent(name, isDirectory: item.isDirectory)
		}

		performOperation(.duplicate, urls: urlMap, unique: true, select: true)

		if urlMap.count == 1, outlineView.numberOfSelectedRows == 1 {
			outlineView.editColumn(0, row: outlineView.selectedRow, with: nil, select: true)
		}
	}

	// MARK: - Rename

	@IBAction public func editSelectedEntries(_: Any?) {
		let items = previewableItems
		guard items.count == 1, items[0].canRename else { return }
		let row = outlineView.row(forItem: items[0])
		guard row >= 0 else { return }
		NSApp.activate(ignoringOtherApps: true)
		outlineView.window?.makeKey()
		outlineView.editColumn(0, row: row, with: nil, select: true)
	}

	// MARK: - Favorites

	@IBAction public func addSelectedEntriesToFavorites(_: Any?) {
		let favURL = FileBrowserLocation.favorites
		let fm = FileManager.default
		do {
			try fm.createDirectory(at: favURL, withIntermediateDirectories: true)
			for item in previewableItems {
				let linkURL = favURL.appendingPathComponent(item.localizedName ?? item.displayName)
				try fm.createSymbolicLink(at: linkURL, withDestinationURL: item.resolvedURL)
			}
		} catch {
			view.window?.presentError(error as NSError)
		}
	}

	@IBAction public func removeSelectedEntriesFromFavorites(_: Any?) {
		for item in previewableItems {
			do {
				try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
			} catch {
				view.window?.presentError(error as NSError)
			}
		}
	}

	// MARK: - Show in Finder

	@IBAction public func showSelectedEntriesInFinder(_: Any?) {
		let urls = previewableItems.map(\.resolvedURL)
		NSWorkspace.shared.activateFileViewerSelecting(urls)
	}

	@IBAction public func showEnclosingFolder(_: Any?) {
		guard let item = selectedItems.first,
		      let enclosingFolder = item.url.deletingLastPathComponent() as URL?
		else { return }
		goToURL(enclosingFolder)
		expandURLs(nil, selectURLs: [item.url])
	}

	@IBAction public func showOriginal(_: Any?) {
		guard let item = selectedItems.first else { return }
		let resolvedURL = item.resolvedURL
		var parentURL: AnyObject?
		try? (resolvedURL as NSURL).getResourceValue(
			&parentURL, forKey: .parentDirectoryURLKey,
		)
		if let parent = parentURL as? URL {
			goToURL(parent)
			expandURLs(nil, selectURLs: [resolvedURL])
		}
	}

	@IBAction public func showPackageContents(_: Any?) {
		guard let item = previewableItems.first else { return }
		goToURL(item.resolvedURL)
	}

	// MARK: - Outline View Click Handlers

	@objc private func didSingleClickOutlineView(_: Any?) {
		let flags = NSEvent.modifierFlags
		guard !flags.contains(.control), !flags.contains(.shift), !flags.contains(.command) else { return }

		if UserDefaults.standard.bool(forKey: "fileBrowserSingleClickToOpen") {
			let row = outlineView.clickedRow
			guard row >= 0, let item = outlineView.item(atRow: row) as? FileItem else { return }
			guard !item.isDirectory, !item.isLinkToDirectory, !item.isPackage,
			      !item.isLinkToPackage, !item.isApplication
			else { return }
			openItems([item], animate: false)
		}
	}

	@objc private func didDoubleClickOutlineView(_: Any?) {
		openItems(selectedItems, animate: true)
	}

	/// Open items — directories navigate, files open in TextMate or external apps.
	public func openItems(_ items: [FileItem], animate _: Bool) {
		var itemsToShowInFileBrowser: [FileItem] = []
		var itemsToOpenExternal: [FileItem] = []
		var itemsToOpenInTextMate: [FileItem] = []
		var itemsToShowInFinder: [FileItem] = []

		let eventType = NSApp.currentEvent?.type
		let eventFlags = (NSApp.currentEvent?.modifierFlags ?? [])
			.intersection([.control, .option, .shift, .command])
		let isMouseEvent = eventType == .leftMouseUp || eventType == .otherMouseUp
		let commandKeyDown = isMouseEvent && eventFlags == .command
		let optionKeyDown = isMouseEvent && eventFlags == .option

		for item in items {
			if commandKeyDown {
				itemsToShowInFinder.append(item)
			} else if (item.isDirectory && !item.isPackage) ||
				(item.isLinkToDirectory && !item.isLinkToPackage) ||
				(optionKeyDown && (item.isPackage || item.isLinkToDirectory))
			{
				itemsToShowInFileBrowser.append(item)
			} else if item.isPackage || item.isLinkToPackage || item.isApplication {
				itemsToOpenExternal.append(item)
			} else {
				itemsToOpenInTextMate.append(item)
			}
		}

		if let first = itemsToShowInFileBrowser.first {
			goToURL(first.resolvedURL)
			return
		}

		if !itemsToShowInFinder.isEmpty {
			NSWorkspace.shared.activateFileViewerSelecting(itemsToShowInFinder.map(\.url))
		}

		for item in itemsToOpenExternal {
			NSWorkspace.shared.open(item.resolvedURL)
		}

		if !itemsToOpenInTextMate.isEmpty {
			delegate?.fileBrowser(self, openURLs: itemsToOpenInTextMate.map(\.url))
		}
	}

	// MARK: - Finder Tags

	/// Handle Finder tag selection changes.
	@objc public func didChangeFinderTag(_ sender: FinderTagsChooser) {
		guard let chosenTag = sender.chosenTag else { return }
		for item in previewableItems {
			var tags = item.finderTags
			if sender.removeChosenTag {
				tags.removeAll { $0.name == chosenTag.name }
			} else if !tags.contains(where: { $0.name == chosenTag.name }) {
				tags.append(chosenTag)
			}
			let tagNames = tags.map(\.name)
			try? (item.url as NSURL).setResourceValue(tagNames, forKey: .tagNamesKey)
			item.finderTags = FinderTag.favoriteTags
				.filter { tagNames.contains($0.name) }
		}
	}

	// MARK: - Item Comparator

	/// Comparator for sorting file items.
	public func itemComparator() -> (FileItem, FileItem) -> ComparisonResult {
		let foldersFirst = sortDirectoriesBeforeFiles
		return { lhs, rhs in
			if foldersFirst {
				let lhsDir = lhs.isDirectory || lhs.isLinkToDirectory
				let rhsDir = rhs.isDirectory || rhs.isLinkToDirectory
				if lhsDir, !rhsDir { return .orderedAscending }
				if rhsDir, !lhsDir { return .orderedDescending }
			}
			return (lhs.localizedName ?? lhs.displayName).localizedCompare(rhs.localizedName ?? rhs.displayName)
		}
	}

	/// Arrange children with filtering and sorting.
	public func arrangeChildren(_ children: [FileItem], inParent _: FileItem?) -> [FileItem] {
		var filtered = children
		if !showExcludedItems {
			filtered = children.filter { item in
				// Show hidden files that start with "." only if they pass glob filters
				if item.isHidden, !item.url.lastPathComponent.hasPrefix(".") {
					return false
				}
				if item.isMissing {
					return false
				}
				return true
			}
		}
		let comparator = itemComparator()
		return filtered.sorted { comparator($0, $1) == .orderedAscending }
	}

	/// Re-sort and re-filter children in a parent item, updating the outline view.
	public func rearrangeChildren(inParent item: FileItem) {
		guard let existing = item.arrangedChildren, let children = item.children else { return }

		let newArranged = arrangeChildren(children, inParent: item)
		let ov = outlineView
		let parent: FileItem? = item !== fileItem ? item : nil

		// Simple case: reload entirely for large data sets
		if existing.count * children.count >= 250_000 {
			item.arrangedChildren = newArranged
			ov.reloadItem(parent, reloadChildren: true)
			if item === fileItem { ov.needsDisplay = true }
			updateDisambiguationSuffix(inParent: item)
			return
		}

		// Remove items no longer in the arranged set
		let newSet = Set(newArranged.map(\.url))
		var indexesToRemove = IndexSet()
		for (i, child) in existing.enumerated() {
			if !newSet.contains(child.url) {
				indexesToRemove.insert(i)
			}
		}
		if !indexesToRemove.isEmpty {
			for i in indexesToRemove.reversed() {
				item.arrangedChildren?.remove(at: i)
			}
			ov.removeItems(
				at: indexesToRemove, inParent: parent,
				withAnimation: [.effectFade, .slideUp],
			)
		}

		// Insert new items
		let existingSet = Set((item.arrangedChildren ?? []).map(\.url))
		var insertionIndexes = IndexSet()
		for (i, child) in newArranged.enumerated() {
			if !existingSet.contains(child.url) {
				insertionIndexes.insert(i)
			}
		}
		if !insertionIndexes.isEmpty {
			// Replace arranged children with new order
			item.arrangedChildren = newArranged
			ov.insertItems(
				at: insertionIndexes, inParent: parent,
				withAnimation: [.effectFade, .slideUp],
			)
		} else {
			item.arrangedChildren = newArranged
		}

		updateDisambiguationSuffix(inParent: item)
	}

	/// Update disambiguation suffixes for children with duplicate display names.
	public func updateDisambiguationSuffix(inParent item: FileItem) {
		guard let children = item.arrangedChildren?.filter(\.url.isFileURL) else { return }

		for child in children {
			child.disambiguationSuffix = nil
		}

		var remaining = children
		var depth = 1

		while !remaining.isEmpty {
			let counts = NSCountedSet(array: remaining.map(\.displayName))
			var conflicted: [FileItem] = []

			for child in remaining {
				guard counts.count(for: child.displayName) > 1 else { continue }
				if let suffix = disambiguationSuffix(for: child.url, numberOfParents: depth) {
					child.disambiguationSuffix = " — \(suffix)"
					conflicted.append(child)
				}
			}

			remaining = conflicted
			depth += 1
		}
	}

	private func disambiguationSuffix(for url: URL, numberOfParents: Int) -> String? {
		var currentURL = url
		var parentNames: [String] = []

		for _ in 0 ..< numberOfParents {
			var isVolume: AnyObject?
			try? (currentURL as NSURL).getResourceValue(&isVolume, forKey: .isVolumeKey)
			if (isVolume as? Bool) == true { return nil }

			var parentURL: AnyObject?
			try? (currentURL as NSURL).getResourceValue(&parentURL, forKey: .parentDirectoryURLKey)
			guard let parent = parentURL as? URL, parent != currentURL else { return nil }

			var parentName: AnyObject?
			try? (parent as NSURL).getResourceValue(&parentName, forKey: .localizedNameKey)
			guard let name = parentName as? String else { return nil }

			parentNames.append(name)
			currentURL = parent
		}

		return parentNames.reversed().joined(separator: "/")
	}

	// MARK: - Outline View Updates

	private func insertURLsInOutline(_ urls: [URL]) -> [FileItem] {
		guard let root = fileItem else { return [] }
		var items: [FileItem] = []
		for url in urls {
			let item = FileItem(url: url)
			// Add to parent's children and rearrange
			if let parent = findParentItem(for: url, in: root) {
				var children = parent.children ?? []
				children.append(item)
				parent.children = children
				rearrangeChildren(inParent: parent)
			}
			items.append(item)
		}
		return items
	}

	private func removeURLsFromOutline(_ urls: [URL]) {
		guard let root = fileItem else { return }
		for url in urls {
			if let parent = findParentItem(for: url, in: root) {
				parent.children = parent.children?.filter { $0.url != url }
				rearrangeChildren(inParent: parent)
			}
		}
	}

	private func moveURLsInOutline(from srcURLs: [URL], to destURLs: [URL]) -> [FileItem] {
		removeURLsFromOutline(srcURLs)
		return insertURLsInOutline(destURLs)
	}

	private func findParentItem(for url: URL, in root: FileItem) -> FileItem? {
		let parentURL = url.deletingLastPathComponent()
		if root.url == parentURL { return root }
		var stack: [FileItem] = root.arrangedChildren ?? []
		while !stack.isEmpty {
			let item = stack.removeFirst()
			if item.url == parentURL { return item }
			if let children = item.arrangedChildren {
				stack.append(contentsOf: children)
			}
		}
		return nil
	}

	private func findItem(for url: URL) -> FileItem? {
		guard let root = fileItem else { return nil }
		var stack: [FileItem] = [root]
		while !stack.isEmpty {
			let item = stack.removeFirst()
			if item.url == url { return item }
			if let children = item.arrangedChildren {
				stack.append(contentsOf: children)
			}
		}
		return nil
	}

	// MARK: - Loading / Expanding

	private func loadChildren(for item: FileItem, expandChildren: Bool) {
		guard item.arrangedChildren == nil, item.children == nil else { return }

		let url = item.url
		loadingURLs.insert(url)

		let token = FileItem.addObserver(
			toDirectoryAt: item.resolvedURL,
		) { [weak self] urls in
			self?.didReceiveURLs(urls, forItemWithURL: url, expandChildren: expandChildren)
		}
		directoryObserverTokens[url] = token
	}

	private func didReceiveURLs(
		_ urls: [URL], forItemWithURL url: URL, expandChildren: Bool,
	) {
		guard let item = findItem(for: url) else { return }

		// Item collapsed while loading — discard
		if item !== fileItem, !outlineView.isItemExpanded(item) {
			item.children = nil
			item.arrangedChildren = nil
			outlineView.reloadItem(item, reloadChildren: true)
			if let token = directoryObserverTokens.removeValue(forKey: url) {
				FileItem.removeObserver(token)
			}
			loadingURLs.remove(url)
			checkLoadCompletionHandlers()
			return
		}

		// Merge with existing children or create new ones
		var children: [FileItem] = []
		var newURLs = Set(urls)

		if let existing = item.children {
			for child in existing {
				if newURLs.contains(child.url) {
					newURLs.remove(child.url)
					child.updateFileProperties()
					children.append(child)
				}
			}
		}

		for url in newURLs {
			children.append(FileItem(url: url))
		}

		item.children = children
		rearrangeChildren(inParent: item)

		// Expand/select children
		for child in item.arrangedChildren ?? [] {
			if (expandChildren && !child.isSymbolicLink) ||
				pendingExpandedURLs.contains(child.url) ||
				child.url.scheme == "scm"
			{
				if outlineView.isExpandable(child) {
					outlineView.expandItem(child, expandChildren: expandChildren && !child.isSymbolicLink)
				}
			}

			if pendingSelectedURLs.contains(child.url) {
				let row = outlineView.row(forItem: child)
				if row >= 0 {
					outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: true)
					pendingSelectedURLs.remove(child.url)
				}
			}
		}

		loadingURLs.remove(url)
		checkLoadCompletionHandlers()
	}

	private func checkLoadCompletionHandlers() {
		guard loadingURLs.isEmpty else { return }
		let handlers = loadingCompletionHandlers
		loadingCompletionHandlers = []
		for handler in handlers {
			handler()
		}
	}

	/// Expand saved URLs and select saved URLs after a tree reload.
	public func expandURLs(_ expandURLs: [URL]?, selectURLs: [URL]?) {
		loadingCompletionHandlers.append { [weak self] in
			self?.centerSelectionInVisibleArea()
		}

		if let expandURLs {
			pendingExpandedURLs = Set(expandURLs)
		}
		if let selectURLs {
			pendingSelectedURLs = Set(selectURLs)
		}

		// Expand items that are in the pending set
		var stack: [FileItem] = fileItem?.arrangedChildren ?? []
		while !stack.isEmpty {
			let item = stack.removeFirst()
			if pendingExpandedURLs.contains(item.url) {
				outlineView.expandItem(item)
				if let children = item.arrangedChildren {
					stack.append(contentsOf: children)
				}
			}
		}

		// Select items
		var indexesToSelect = IndexSet()
		for i in 0 ..< outlineView.numberOfRows {
			if let item = outlineView.item(atRow: i) as? FileItem,
			   pendingSelectedURLs.contains(item.url)
			{
				indexesToSelect.insert(i)
			}
		}
		outlineView.selectRowIndexes(indexesToSelect, byExtendingSelection: false)

		checkLoadCompletionHandlers()
	}

	private func centerSelectionInVisibleArea() {
		guard outlineView.numberOfSelectedRows > 0 else { return }
		let row = outlineView.selectedRowIndexes.first!
		let rowRect = outlineView.rect(ofRow: row)
		let visibleRect = outlineView.visibleRect
		if rowRect.minY < visibleRect.minY || rowRect.maxY > visibleRect.maxY {
			outlineView.scroll(
				NSPoint(
					x: rowRect.minX,
					y: round(rowRect.midY - visibleRect.height / 2),
				),
			)
		}
	}

	private func computeExpandedURLs() -> Set<URL> {
		var result = pendingExpandedURLs
		for i in 0 ..< outlineView.numberOfRows {
			if let item = outlineView.item(atRow: i) as? FileItem {
				if outlineView.isItemExpanded(item), item.url.scheme != "scm" {
					result.insert(item.url)
				} else {
					result.remove(item.url)
				}
			}
		}
		return result
	}

	private func computeSelectedURLs() -> Set<URL> {
		var result = pendingSelectedURLs
		let selectedIndexes = outlineView.selectedRowIndexes
		for i in 0 ..< outlineView.numberOfRows {
			if let item = outlineView.item(atRow: i) as? FileItem {
				if selectedIndexes.contains(i) {
					result.insert(item.url)
				} else {
					result.remove(item.url)
				}
			}
		}
		return result
	}

	private func rearrangeAll() {
		guard let root = fileItem else { return }
		var stack: [FileItem] = [root]
		while !stack.isEmpty {
			let item = stack.removeFirst()
			rearrangeChildren(inParent: item)
			if item === root || outlineView.isItemExpanded(item) {
				stack.append(contentsOf: item.arrangedChildren ?? [])
			}
		}
	}

	private func reloadExpandability() {
		guard let root = fileItem else { return }
		var stack: [FileItem] = root.arrangedChildren ?? []
		while !stack.isEmpty {
			let item = stack.removeFirst()
			if item.isSymbolicLink || item.isPackage {
				outlineView.reloadItem(item, reloadChildren: true)
			}
			if outlineView.isExpandable(item), item.arrangedChildren != nil {
				stack.append(contentsOf: item.arrangedChildren ?? [])
			}
		}
	}

	// MARK: - Session State

	/// Get serialized session state for persistence.
	public var sessionState: [String: Any] {
		var state: [String: Any] = [:]
		state["showHidden"] = showExcludedItems

		var historyEntries: [[String: Any]] = []
		let from = max(0, history.count - 5)
		for i in from ..< history.count {
			var entry: [String: Any] = ["url": history[i].url.absoluteString]
			if i == historyIndex {
				entry["scrollOffset"] = outlineView.visibleRect.minY
			} else if let offset = history[i].scrollOffset {
				entry["scrollOffset"] = offset
			}
			historyEntries.append(entry)
		}
		state["history"] = historyEntries
		state["historyIndex"] = historyIndex - from

		state["expanded"] = computeExpandedURLs().map(\.absoluteString)
		state["selection"] = computeSelectedURLs().map(\.absoluteString)

		return state
	}

	/// Restore from serialized session state.
	public func setupView(withState state: [String: Any]) {
		if let showHidden = state["showHidden"] as? Bool {
			showExcludedItems = showHidden
		}

		guard let historyEntries = state["history"] as? [[String: Any]], !historyEntries.isEmpty else { return }

		var newHistory: [HistoryEntry] = []
		for entry in historyEntries {
			guard let urlString = entry["url"] as? String,
			      let url = URL(string: urlString)
			else { continue }
			let scrollOffset = entry["scrollOffset"] as? CGFloat
			newHistory.append(HistoryEntry(url: url, scrollOffset: scrollOffset))
		}

		guard !newHistory.isEmpty else { return }

		history = newHistory
		let idx = state["historyIndex"] as? Int ?? 0
		historyIndex = min(max(0, idx), newHistory.count - 1)
		applyHistoryIndex()

		var expandedURLs: [URL] = []
		if let expandedStrings = state["expanded"] as? [String] {
			expandedURLs = expandedStrings.compactMap(URL.init(string:))
		}

		var selectedURLs: [URL] = []
		if let selectedStrings = state["selection"] as? [String] {
			selectedURLs = selectedStrings.compactMap(URL.init(string:))
		}

		expandURLs(expandedURLs, selectURLs: selectedURLs)
	}

	/// Environment variables for commands.
	public var variables: [String: String] {
		var env: [String: String] = [:]
		let fileURLs = selectedFileURLs
		if !fileURLs.isEmpty {
			env["TM_SELECTED_FILE"] = fileURLs.last?.path
			env["TM_SELECTED_FILES"] = fileURLs.map {
				$0.path.replacingOccurrences(of: " ", with: "\\ ")
			}.joined(separator: " ")
		}
		return env
	}

	// MARK: - NSOutlineViewDataSource

	public func outlineView(
		_: NSOutlineView,
		numberOfChildrenOfItem item: Any?,
	) -> Int {
		let fileItem = (item as? FileItem) ?? fileItem
		return fileItem?.arrangedChildren?.count ?? 0
	}

	public func outlineView(
		_: NSOutlineView,
		child index: Int,
		ofItem item: Any?,
	) -> Any {
		let fileItem = (item as? FileItem) ?? fileItem
		return fileItem!.arrangedChildren![index]
	}

	public func outlineView(
		_: NSOutlineView,
		isItemExpandable item: Any,
	) -> Bool {
		guard let fileItem = item as? FileItem else { return false }
		return (fileItem.isDirectory && (canExpandPackages || !fileItem.isPackage)) ||
			(canExpandSymbolicLinks && fileItem.isLinkToDirectory && (canExpandPackages || !fileItem.isLinkToPackage))
	}

	public func outlineView(
		_: NSOutlineView,
		objectValueFor _: NSTableColumn?,
		byItem item: Any?,
	) -> Any? {
		item
	}

	public func outlineView(
		_: NSOutlineView,
		pasteboardWriterForItem item: Any,
	) -> NSPasteboardWriting? {
		(item as? FileItem)?.url as NSURL?
	}

	// MARK: - NSOutlineViewDelegate

	public func outlineView(
		_: NSOutlineView,
		isGroupItem item: Any,
	) -> Bool {
		guard let fileItem = item as? FileItem else { return false }
		return fileItem.url.scheme == "scm"
	}

	public func outlineView(
		_: NSOutlineView,
		shouldSelectItem item: Any,
	) -> Bool {
		guard let fileItem = item as? FileItem else { return false }
		return fileItem.url.isFileURL
	}

	public func outlineView(
		_ outlineView: NSOutlineView,
		viewFor tableColumn: NSTableColumn?,
		item: Any,
	) -> NSView? {
		guard let fileItem = item as? FileItem else { return nil }

		let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("FileItem")
		var cellView = outlineView.makeView(
			withIdentifier: identifier, owner: self,
		) as? FileItemTableCellView

		if cellView == nil {
			cellView = FileItemTableCellView()
			cellView?.identifier = identifier
			cellView?.openButton.target = self
			cellView?.openButton.action = #selector(takeItemToOpenFrom(_:))
			cellView?.closeButton.target = self
			cellView?.closeButton.action = #selector(takeItemToCloseFrom(_:))
			cellView?.nameField.delegate = self
		}

		let icon = FileItemImage.iconImage(
			for: fileItem.url,
			isModified: false,
			isMissing: fileItem.isMissing,
			isDirectory: fileItem.isDirectory,
			isSymbolicLink: fileItem.isSymbolicLink,
			scmStatus: .none,
			size: NSSize(width: 16, height: 16),
		)

		cellView?.configure(with: fileItem, icon: icon)
		return cellView
	}

	@objc private func takeItemToOpenFrom(_ sender: Any?) {
		guard let button = sender as? NSView else { return }
		let row = outlineView.row(for: button)
		guard row >= 0, let item = outlineView.item(atRow: row) as? FileItem else { return }
		openItems([item], animate: true)
	}

	@objc private func takeItemToCloseFrom(_ sender: Any?) {
		guard let button = sender as? NSView else { return }
		let row = outlineView.row(for: button)
		guard row >= 0, let item = outlineView.item(atRow: row) as? FileItem else { return }
		delegate?.fileBrowser(self, closeURL: item.url)
	}

	public func outlineViewItemDidExpand(_ notification: Notification) {
		guard let item = notification.userInfo?["NSObject"] as? FileItem else { return }
		loadChildren(for: item, expandChildren: expandingChildrenCounter > 0)
	}

	public func outlineViewItemWillCollapse(_ notification: Notification) {
		guard let item = notification.userInfo?["NSObject"] as? FileItem else { return }
		if nestedCollapsingChildrenCounter == 0 || collapsingChildrenCounter > 0 {
			pendingExpandedURLs.remove(item.url)
		}
		nestedCollapsingChildrenCounter += 1
	}

	public func outlineViewItemDidCollapse(_: Notification) {
		nestedCollapsingChildrenCounter -= 1
	}

	public func outlineViewSelectionDidChange(_: Notification) {
		// Update state for session persistence
	}

	// MARK: - NSTextFieldDelegate (Rename)

	public func control(
		_ control: NSControl,
		textShouldEndEditing fieldEditor: NSText,
	) -> Bool {
		let row = outlineView.row(for: control)
		guard row >= 0, let item = outlineView.item(atRow: row) as? FileItem else { return false }

		let newURL = item.url
			.deletingLastPathComponent()
			.appendingPathComponent(fieldEditor.string, isDirectory: item.isDirectory)

		if item.url != newURL {
			DispatchQueue.main.async { [weak self] in
				self?.performOperation(.rename, urls: [item.url: newURL], unique: false, select: true)
			}
		}
		return true
	}

	// MARK: - NSMenuDelegate (Context Menu)

	public func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		buildContextMenu(menu)
	}

	private func buildContextMenu(_ menu: NSMenu) {
		menu.addItem(NSMenuItem(
			title: "Open",
			action: #selector(openSelectedItems(_:)),
			keyEquivalent: "",
		))
		menu.addItem(.separator())

		menu.addItem(NSMenuItem(
			title: "Show Original",
			action: #selector(showOriginal(_:)),
			keyEquivalent: "",
		))
		menu.addItem(NSMenuItem(
			title: "Show Enclosing Folder",
			action: #selector(showEnclosingFolder(_:)),
			keyEquivalent: "",
		))
		menu.addItem(NSMenuItem(
			title: "Show in Finder",
			action: #selector(showSelectedEntriesInFinder(_:)),
			keyEquivalent: "",
		))
		menu.addItem(.separator())

		let newFileItem = NSMenuItem(
			title: "New File",
			action: #selector(newFileAction(_:)),
			keyEquivalent: "n",
		)
		newFileItem.keyEquivalentModifierMask = [.command, .control]
		menu.addItem(newFileItem)

		let newFolderItem = NSMenuItem(
			title: "New Folder",
			action: #selector(newFolderAction(_:)),
			keyEquivalent: "n",
		)
		newFolderItem.keyEquivalentModifierMask = [.command, .shift]
		menu.addItem(newFolderItem)
		menu.addItem(.separator())

		menu.addItem(NSMenuItem(
			title: "Rename",
			action: #selector(editSelectedEntries(_:)),
			keyEquivalent: "",
		))
		menu.addItem(NSMenuItem(
			title: "Duplicate",
			action: #selector(duplicateSelectedEntries(_:)),
			keyEquivalent: "d",
		))
		menu.addItem(NSMenuItem(
			title: "Quick Look",
			action: #selector(toggleQuickLookPreview(_:)),
			keyEquivalent: " ",
		))
		menu.addItem(.separator())

		menu.addItem(NSMenuItem(
			title: "Add to Favorites",
			action: #selector(addSelectedEntriesToFavorites(_:)),
			keyEquivalent: "",
		))
		menu.addItem(NSMenuItem(
			title: "Remove From Favorites",
			action: #selector(removeSelectedEntriesFromFavorites(_:)),
			keyEquivalent: "",
		))
		menu.addItem(.separator())

		menu.addItem(NSMenuItem(
			title: "Move to Trash",
			action: #selector(delete(_:)),
			keyEquivalent: "",
		))
		menu.addItem(.separator())

		menu.addItem(NSMenuItem(
			title: "Copy",
			action: #selector(copy(_:)),
			keyEquivalent: "c",
		))
		menu.addItem(NSMenuItem(
			title: "Copy as Pathname",
			action: #selector(copyAsPathname(_:)),
			keyEquivalent: "",
		))
		menu.addItem(NSMenuItem(
			title: "Paste",
			action: #selector(paste(_:)),
			keyEquivalent: "v",
		))
		menu.addItem(NSMenuItem(
			title: "Move Items Here",
			action: #selector(pasteNext(_:)),
			keyEquivalent: "",
		))
		menu.addItem(.separator())

		menu.addItem(NSMenuItem(
			title: "Undo",
			action: #selector(undo(_:)),
			keyEquivalent: "z",
		))
		menu.addItem(NSMenuItem(
			title: "Redo",
			action: #selector(redo(_:)),
			keyEquivalent: "Z",
		))

		// Set target for all items
		for menuItem in menu.items where menuItem.action != nil {
			if menuItem.target == nil, responds(to: menuItem.action) {
				menuItem.target = self
			}
		}
	}

	@objc private func openSelectedItems(_: Any?) {
		openItems(selectedItems, animate: true)
	}

	// MARK: - Undo / Redo

	@IBAction public func undo(_: Any?) {
		diskOperations.undoManager.undo()
	}

	@IBAction public func redo(_: Any?) {
		diskOperations.undoManager.redo()
	}

	// MARK: - QuickLook

	@IBAction public func toggleQuickLookPreview(_: Any?) {
		if QLPreviewPanel.sharedPreviewPanelExists(),
		   QLPreviewPanel.shared().isVisible
		{
			QLPreviewPanel.shared().orderOut(nil)
		} else {
			QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
		}
	}

	override public func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
		true
	}

	override public func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		previewItems = previewableItems
		panel.delegate = self
		panel.dataSource = self
	}

	override public func endPreviewPanelControl(_: QLPreviewPanel!) {
		previewItems = []
	}

	private func imageRect(of item: FileItem?) -> NSRect {
		guard let item else { return .zero }
		let row = outlineView.row(forItem: item)
		guard row >= 0 else { return .zero }
		guard let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileItemTableCellView
		else { return .zero }
		let button = cellView.openButton
		let imageRect = NSIntersectionRect(
			button.convert(button.bounds, to: nil),
			outlineView.convert(outlineView.visibleRect, to: nil),
		)
		guard !imageRect.isEmpty, let window = cellView.window else { return .zero }
		return window.convertToScreen(imageRect)
	}

	// MARK: - Drag & Drop

	public func outlineView(
		_ outlineView: NSOutlineView,
		validateDrop info: NSDraggingInfo,
		proposedItem item: Any?,
		proposedChildIndex _: Int,
	) -> NSDragOperation {
		let dropItem = (item as? FileItem) ?? fileItem
		guard let dropURL = dropItem?.resolvedURL,
		      dropURL.isFileURL,
		      self.outlineView.isExpandable(dropItem)
		else { return [] }

		let pboard = info.draggingPasteboard
		guard let draggedURLs = pboard.readObjects(forClasses: [NSURL.self]) as? [URL],
		      !draggedURLs.isEmpty
		else { return [] }

		let linkOperation = NSApp.currentEvent?.modifierFlags.contains(.control) ?? false
		let toggleOperation = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false

		for draggedURL in draggedURLs {
			let sameDevice = true // Simplified — full implementation checks device IDs
			let operation: NSDragOperation = linkOperation ? .link : ((sameDevice != toggleOperation) ? .move : .copy)

			if operation == .move, draggedURL.deletingLastPathComponent() == dropURL {
				continue
			}

			outlineView.setDropItem(item as? FileItem, dropChildIndex: -1)
			return operation
		}

		return []
	}

	public func outlineView(
		_: NSOutlineView,
		acceptDrop info: NSDraggingInfo,
		item: Any?,
		childIndex _: Int,
	) -> Bool {
		let newParent = (item as? FileItem) ?? fileItem
		guard let parentURL = newParent?.resolvedURL, parentURL.isFileURL else { return false }

		let mask = info.draggingSourceOperationMask
		let op: NSDragOperation
		if mask.contains(.move) { op = .move }
		else if mask.contains(.copy) { op = .copy }
		else if mask.contains(.link) { op = .link }
		else { return false }

		guard let srcURLs = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
		else { return false }

		var urlMap: [URL: URL] = [:]
		for url in srcURLs {
			urlMap[url] = parentURL.appendingPathComponent(
				url.lastPathComponent,
				isDirectory: op != .link && url.hasDirectoryPath,
			)
		}

		let diskOp: DiskOperation
		switch op {
		case .link: diskOp = .link
		case .copy: diskOp = .copy
		case .move: diskOp = .move
		default: return false
		}

		performOperation(diskOp, urls: urlMap, unique: false, select: false)
		return true
	}

	// MARK: - FileBrowserOutlineViewDelegate

	public func outlineView(
		_: NSOutlineView,
		didTrashURLs urls: [URL],
	) {
		performOperation(.trash, sourceURLs: urls, destinationURLs: [], unique: false, select: false)
	}

	// MARK: - Swipe Navigation

	override public func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
		axis == .horizontal
	}
}

// MARK: - QLPreviewPanelDataSource / QLPreviewPanelDelegate

extension FileBrowserViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
	public nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
		MainActor.assumeIsolated { previewItems.count }
	}

	public nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
		MainActor.assumeIsolated { previewItems[index] }
	}

	public nonisolated func previewPanel(
		_: QLPreviewPanel!,
		sourceFrameOnScreenFor item: (any QLPreviewItem)!,
	) -> NSRect {
		let fileItem = item as? FileItem
		return MainActor.assumeIsolated { imageRect(of: fileItem) }
	}
}
#endif
