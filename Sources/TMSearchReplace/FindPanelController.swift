#if canImport(AppKit)
import AppKit

// MARK: - Find Panel Controller

/// The main find panel window controller — equivalent to the Objective-C `Find` class.
///
/// Manages the NSPanel containing find/replace text fields, search options,
/// scope selection, action buttons, a results outline view, and a status bar.
/// Acts as a `FindServer` so that find clients (text views) can query the
/// current search parameters and report results back.
@MainActor
public final class FindPanelController: NSWindowController, FindServer, Sendable {
	// MARK: - Shared Instance

	/// Shared singleton — equivalent to `[Find sharedInstance]`.
	public static let shared = FindPanelController()

	// MARK: - FindServer Properties

	public var findOperation: FindOperation = .find
	public var findString: String {
		get { state.findString }
		set {
			state.findString = newValue
			findTextField.stringValue = newValue
			updateCountLabel()
		}
	}

	public var replaceString: String {
		get { state.replaceString }
		set {
			state.replaceString = newValue
			replaceTextField.stringValue = newValue
		}
	}

	public var findOptions: FindOptions {
		state.options
	}

	// MARK: - State & Delegates

	/// Shared find state.
	public let state = FindState()

	/// The pasteboard manager for find/replace history.
	public let pasteboard = FindPasteboard.shared

	/// Navigation delegate for opening documents from search results.
	public weak var navigationDelegate: FindNavigationDelegate?

	/// The current search target scope.
	public var searchTarget: SearchScope {
		get { state.searchScope }
		set {
			state.searchScope = newValue
			updateWherePopup()
		}
	}

	/// Project folder for project-scope searches.
	public var projectFolder: String?

	/// File browser item paths for file-browser-scope searches.
	public var fileBrowserItems: [String] = []

	/// Identifier of the current document (for document-scope searches).
	public var documentIdentifier: UUID?

	/// Cross-document match references for Cmd-G cycling.
	public private(set) var matchReferences: [DocumentMatchReference] = []

	/// Recent folder paths for the "Where" popup.
	private var recentFolders: [String] = []

	/// The active folder search engine.
	private var documentSearch: ProjectSearchEngine?

	/// The results view controller.
	private let resultsVC = FindResultsViewController()

	/// The status bar view controller.
	private let statusBarVC = FindStatusBarController()

	// MARK: - UI Components

	private let findTextField = FindTextFieldController()
	private let replaceTextField = FindTextFieldController()

	private let ignoreCaseCheckbox = NSButton(checkboxWithTitle: "Ignore Case", target: nil, action: nil)
	private let wrapAroundCheckbox = NSButton(checkboxWithTitle: "Wrap Around", target: nil, action: nil)
	private let regularExpressionCheckbox = NSButton(checkboxWithTitle: "Regular Expression", target: nil, action: nil)
	private let ignoreWhitespaceCheckbox = NSButton(checkboxWithTitle: "Ignore Whitespace", target: nil, action: nil)
	private let fullWordsCheckbox = NSButton(checkboxWithTitle: "Full Words", target: nil, action: nil)

	private let wherePopup = NSPopUpButton()
	private let globField = NSTextField()
	private let countLabel = NSTextField(labelWithString: "")

	// Action buttons
	private let findAllButton = NSButton(title: "Find All", target: nil, action: nil)
	private let replaceAllButton = NSButton(title: "Replace All", target: nil, action: nil)
	private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
	private let replaceAndFindButton = NSButton(title: "Replace & Find", target: nil, action: nil)
	private let previousButton = NSButton(title: "Previous", target: nil, action: nil)
	private let nextButton = NSButton(title: "Next", target: nil, action: nil)

	/// Folder search options
	private let searchHiddenFoldersCheckbox = NSButton(
		checkboxWithTitle: "Search Hidden Folders",
		target: nil,
		action: nil,
	)
	private let searchFolderLinksCheckbox = NSButton(checkboxWithTitle: "Search Folder Links", target: nil, action: nil)
	private let searchFileLinksCheckbox = NSButton(checkboxWithTitle: "Search File Links", target: nil, action: nil)
	private let searchBinaryFilesCheckbox = NSButton(checkboxWithTitle: "Search Binary Files", target: nil, action: nil)

	/// Tracks whether the results area is visible.
	private var resultsVisible: Bool = false

	/// Bottom constraint for toggling results visibility.
	private var resultsHeightConstraint: NSLayoutConstraint?

	// MARK: - Initialization

	private init() {
		let panel = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
			styleMask: [.titled, .closable, .resizable, .utilityWindow],
			backing: .buffered,
			defer: true,
		)
		panel.title = "Find"
		panel.isFloatingPanel = true
		panel.becomesKeyOnlyIfNeeded = true
		panel.isReleasedWhenClosed = false
		panel.setFrameAutosaveName("FindPanel")
		panel.minSize = NSSize(width: 400, height: 140)

		super.init(window: panel)

		buildUI()
		syncUIFromState()
		bindActions()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError()
	}

	// MARK: - Public API

	/// Show the find panel (Use & Find or just Find).
	public func showPanel(withSelection selection: String? = nil, scope: SearchScope? = nil) {
		if let selection, !selection.isEmpty {
			findString = selection
		}
		if let scope {
			searchTarget = scope
		}
		pasteboard.syncFromSystem()
		findTextField.stringValue = state.findString
		showWindow(nil)
	}

	/// Toggle a find option from a menu item (tag-based).
	public func toggleFindOption(tag: Int) {
		let option = findOptionForTag(tag)
		if state.options.contains(option) {
			state.options.remove(option)
		} else {
			state.options.insert(option)
		}
		syncCheckboxesFromState()
	}

	/// Perform "Find Next" from outside the panel (e.g. Cmd-G).
	public func findNext(sender _: Any? = nil) {
		state.options.remove(.backwards)
		findOperation = .find
		performFindOnClient()
	}

	/// Perform "Find Previous" from outside the panel (e.g. Shift-Cmd-G).
	public func findPrevious(sender _: Any? = nil) {
		state.options.insert(.backwards)
		findOperation = .find
		performFindOnClient()
	}

	// MARK: - FindServer Callbacks

	public func didFind(count: Int, of searchString: String, atLine: Int, column: Int, wrapped: Bool) {
		let wrappedText = wrapped ? " (wrapped)" : ""
		if count == 0 {
			statusBarVC.statusText = "No matches for \"\(searchString)\""
		} else if count == 1 {
			statusBarVC.statusText = "Found \"\(searchString)\" at line \(atLine + 1), column \(column + 1)\(wrappedText)"
		} else {
			statusBarVC.statusText = "\(count) matches for \"\(searchString)\""
		}
	}

	public func didReplace(count: Int, of searchString: String, with replacement: String) {
		if count == 0 {
			statusBarVC.statusText = "Nothing replaced"
		} else {
			let s = count == 1 ? "" : "s"
			statusBarVC.statusText = "Replaced \(count) occurrence\(s) of \"\(searchString)\" with \"\(replacement)\""
		}
	}

	// MARK: - UI Construction

	private func buildUI() {
		guard let contentView = window?.contentView else { return }

		// Find row
		let findLabel = NSTextField(labelWithString: "Find:")
		findLabel.alignment = .right
		findLabel.setContentHuggingPriority(.required, for: .horizontal)

		let findHistoryBtn = NSButton(title: "⏷", target: self, action: #selector(showFindHistory(_:)))
		findHistoryBtn.bezelStyle = .inline
		findHistoryBtn.setContentHuggingPriority(.required, for: .horizontal)

		// Replace row
		let replaceLabel = NSTextField(labelWithString: "Replace:")
		replaceLabel.alignment = .right
		replaceLabel.setContentHuggingPriority(.required, for: .horizontal)

		let replaceHistoryBtn = NSButton(title: "⏷", target: self, action: #selector(showReplaceHistory(_:)))
		replaceHistoryBtn.bezelStyle = .inline
		replaceHistoryBtn.setContentHuggingPriority(.required, for: .horizontal)

		// Options row
		let optionsStack = NSStackView(views: [
			ignoreCaseCheckbox, wrapAroundCheckbox, regularExpressionCheckbox,
			ignoreWhitespaceCheckbox, fullWordsCheckbox,
		])
		optionsStack.orientation = .horizontal
		optionsStack.distribution = .fill
		optionsStack.spacing = 12

		// Where row
		let whereLabel = NSTextField(labelWithString: "Where:")
		whereLabel.alignment = .right
		whereLabel.setContentHuggingPriority(.required, for: .horizontal)
		buildWherePopup()

		globField.placeholderString = "File pattern (e.g. *.swift)"
		globField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
		globField.setContentHuggingPriority(.defaultLow, for: .horizontal)

		let whereStack = NSStackView(views: [whereLabel, wherePopup, globField])
		whereStack.orientation = .horizontal
		whereStack.spacing = 6

		// Folder search options (hidden unless scope requires them)
		let folderOptsStack = NSStackView(views: [
			searchHiddenFoldersCheckbox, searchFolderLinksCheckbox,
			searchFileLinksCheckbox, searchBinaryFilesCheckbox,
		])
		folderOptsStack.orientation = .horizontal
		folderOptsStack.spacing = 12

		// Action buttons
		for btn in [findAllButton, replaceAllButton, replaceButton, replaceAndFindButton, previousButton, nextButton] {
			btn.bezelStyle = .rounded
			btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
		}
		nextButton.keyEquivalent = "\r"

		let buttonsStack = NSStackView(views: [
			findAllButton, replaceAllButton, replaceButton, replaceAndFindButton,
			previousButton, nextButton,
		])
		buttonsStack.orientation = .horizontal
		buttonsStack.distribution = .fillEqually
		buttonsStack.spacing = 6

		// Count label
		countLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
		countLabel.textColor = .secondaryLabelColor
		countLabel.setContentHuggingPriority(.required, for: .horizontal)

		// Find text field view
		let findRow = NSStackView(views: [findLabel, findTextField.view, findHistoryBtn, countLabel])
		findRow.orientation = .horizontal
		findRow.spacing = 6

		let replaceRow = NSStackView(views: [replaceLabel, replaceTextField.view, replaceHistoryBtn])
		replaceRow.orientation = .horizontal
		replaceRow.spacing = 6

		// Main vertical stack
		let mainStack = NSStackView(views: [
			findRow, replaceRow, optionsStack, whereStack, folderOptsStack,
			buttonsStack,
		])
		mainStack.orientation = .vertical
		mainStack.alignment = .leading
		mainStack.spacing = 8
		mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 0, right: 12)

		// Layout
		mainStack.translatesAutoresizingMaskIntoConstraints = false
		resultsVC.view.translatesAutoresizingMaskIntoConstraints = false
		statusBarVC.view.translatesAutoresizingMaskIntoConstraints = false

		contentView.addSubview(mainStack)
		contentView.addSubview(resultsVC.view)
		contentView.addSubview(statusBarVC.view)

		let resultsHeight = resultsVC.view.heightAnchor.constraint(equalToConstant: 0)
		resultsHeightConstraint = resultsHeight

		NSLayoutConstraint.activate([
			mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
			mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

			findRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -12),
			replaceRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -12),
			buttonsStack.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -12),

			resultsVC.view.topAnchor.constraint(equalTo: mainStack.bottomAnchor, constant: 4),
			resultsVC.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			resultsVC.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			resultsHeight,

			statusBarVC.view.topAnchor.constraint(equalTo: resultsVC.view.bottomAnchor),
			statusBarVC.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			statusBarVC.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			statusBarVC.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			statusBarVC.view.heightAnchor.constraint(equalToConstant: 24),
		])

		// Wire up find/replace text field callbacks
		findTextField.onValueChanged = { [weak self] value in
			self?.state.findString = value
			self?.pasteboard.findString = value
			self?.updateCountLabel()
		}

		replaceTextField.onValueChanged = { [weak self] value in
			self?.state.replaceString = value
			self?.pasteboard.replaceString = value
		}

		// Wire up results selection
		resultsVC.onSelectResult = { [weak self] node in
			self?.didSelectResult(node)
		}
		resultsVC.onDoubleClickResult = { [weak self] node in
			self?.didDoubleClickResult(node)
		}

		// Wire up status bar stop
		statusBarVC.onStop = { [weak self] in
			self?.stopFolderSearch()
		}
	}

	// MARK: - Where Popup

	private func buildWherePopup() {
		wherePopup.removeAllItems()
		wherePopup.addItem(withTitle: "Document")
		wherePopup.addItem(withTitle: "Selection")
		wherePopup.addItem(withTitle: "Open Files")
		wherePopup.addItem(withTitle: "Project Folder")
		wherePopup.addItem(withTitle: "File Browser Items")
		wherePopup.menu?.addItem(.separator())
		wherePopup.addItem(withTitle: "Other Folder…")

		if !recentFolders.isEmpty {
			wherePopup.menu?.addItem(.separator())
			for folder in recentFolders.prefix(5) {
				let displayName = FileManager.default.displayName(atPath: folder)
				let item = NSMenuItem(title: displayName, action: #selector(selectRecentFolder(_:)), keyEquivalent: "")
				item.target = self
				item.representedObject = folder
				wherePopup.menu?.addItem(item)
			}
		}

		wherePopup.target = self
		wherePopup.action = #selector(wherePopupChanged(_:))

		updateWherePopup()
	}

	private func updateWherePopup() {
		let index = min(state.searchScope.rawValue, wherePopup.numberOfItems - 1)
		wherePopup.selectItem(at: max(0, index))

		let isFolderSearch = state.searchScope == .project || state.searchScope == .other
			|| state.searchScope == .fileBrowserItems || state.searchScope == .openFiles
		globField.isHidden = !isFolderSearch
		updateFolderSearchOptionVisibility()
	}

	private func updateFolderSearchOptionVisibility() {
		let show = state.searchScope == .project || state.searchScope == .other
		searchHiddenFoldersCheckbox.superview?.isHidden = !show
	}

	// MARK: - Action Bindings

	private func bindActions() {
		ignoreCaseCheckbox.target = self
		ignoreCaseCheckbox.action = #selector(optionCheckboxToggled(_:))
		ignoreCaseCheckbox.tag = 0

		wrapAroundCheckbox.target = self
		wrapAroundCheckbox.action = #selector(optionCheckboxToggled(_:))
		wrapAroundCheckbox.tag = 1

		regularExpressionCheckbox.target = self
		regularExpressionCheckbox.action = #selector(optionCheckboxToggled(_:))
		regularExpressionCheckbox.tag = 2

		ignoreWhitespaceCheckbox.target = self
		ignoreWhitespaceCheckbox.action = #selector(optionCheckboxToggled(_:))
		ignoreWhitespaceCheckbox.tag = 3

		fullWordsCheckbox.target = self
		fullWordsCheckbox.action = #selector(optionCheckboxToggled(_:))
		fullWordsCheckbox.tag = 4

		findAllButton.target = self
		findAllButton.action = #selector(performFindAll(_:))

		replaceAllButton.target = self
		replaceAllButton.action = #selector(performReplaceAll(_:))

		replaceButton.target = self
		replaceButton.action = #selector(performReplace(_:))

		replaceAndFindButton.target = self
		replaceAndFindButton.action = #selector(performReplaceAndFind(_:))

		previousButton.target = self
		previousButton.action = #selector(performFindPrevious(_:))

		nextButton.target = self
		nextButton.action = #selector(performFindNext(_:))
	}

	// MARK: - Sync State ↔ UI

	private func syncUIFromState() {
		findTextField.stringValue = state.findString
		findTextField.history = pasteboard.findHistory
		replaceTextField.stringValue = state.replaceString
		replaceTextField.history = pasteboard.replaceHistory
		syncCheckboxesFromState()
		updateWherePopup()
	}

	private func syncCheckboxesFromState() {
		ignoreCaseCheckbox.state = state.options.contains(.ignoreCase) ? .on : .off
		wrapAroundCheckbox.state = state.options.contains(.wrapAround) ? .on : .off
		regularExpressionCheckbox.state = state.options.contains(.regularExpression) ? .on : .off
		ignoreWhitespaceCheckbox.state = state.options.contains(.ignoreWhitespace) ? .on : .off
		fullWordsCheckbox.state = state.options.contains(.fullWords) ? .on : .off
	}

	private func syncStateFromCheckboxes() {
		var opts: FindOptions = []
		if ignoreCaseCheckbox.state == .on { opts.insert(.ignoreCase) }
		if wrapAroundCheckbox.state == .on { opts.insert(.wrapAround) }
		if regularExpressionCheckbox.state == .on { opts.insert(.regularExpression) }
		if ignoreWhitespaceCheckbox.state == .on { opts.insert(.ignoreWhitespace) }
		if fullWordsCheckbox.state == .on { opts.insert(.fullWords) }
		state.options = opts
	}

	// MARK: - Option Mapping

	private func findOptionForTag(_ tag: Int) -> FindOptions {
		switch tag {
		case 0: .ignoreCase
		case 1: .wrapAround
		case 2: .regularExpression
		case 3: .ignoreWhitespace
		case 4: .fullWords
		default: []
		}
	}

	// MARK: - Count Label

	private func updateCountLabel() {
		// Count label shows match count in current document (document scope only)
		countLabel.stringValue = ""
	}

	// MARK: - Actions

	@objc private func showFindHistory(_: Any) {
		findTextField.history = pasteboard.findHistory
		findTextField.showHistory()
	}

	@objc private func showReplaceHistory(_: Any) {
		replaceTextField.history = pasteboard.replaceHistory
		replaceTextField.showHistory()
	}

	@objc private func optionCheckboxToggled(_: NSButton) {
		syncStateFromCheckboxes()
	}

	@objc private func wherePopupChanged(_: Any) {
		let idx = wherePopup.indexOfSelectedItem
		if idx == wherePopup.numberOfItems - 1 - (recentFolders.isEmpty ? 0 : recentFolders.count + 1) {
			// "Other Folder…"
			showFolderSelectionPanel()
		} else if idx < SearchScope.allCases.count {
			state.searchScope = SearchScope(rawValue: idx) ?? .document
		}
		updateWherePopup()
	}

	@objc private func selectRecentFolder(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		projectFolder = path
		state.searchScope = .other
		updateWherePopup()
	}

	@objc private func performFindNext(_: Any) {
		findNext()
	}

	@objc private func performFindPrevious(_: Any) {
		findPrevious()
	}

	@objc private func performFindAll(_: Any) {
		commitFindString()
		let scope = state.searchScope
		if scope == .project || scope == .other || scope == .fileBrowserItems || scope == .openFiles {
			startFolderSearch()
		} else {
			findOperation = .find
			state.options.insert(.allMatches)
			performFindOnClient()
			state.options.remove(.allMatches)
		}
	}

	@objc private func performReplace(_: Any) {
		commitFindString()
		findOperation = .replace
		performFindOnClient()
	}

	@objc private func performReplaceAndFind(_: Any) {
		commitFindString()
		findOperation = .replaceAndFind
		performFindOnClient()
	}

	@objc private func performReplaceAll(_: Any) {
		commitFindString()
		let scope = state.searchScope
		if scope == .selection {
			findOperation = .replaceAllInSelection
		} else {
			findOperation = .replaceAll
		}
		performFindOnClient()
	}

	// MARK: - Find Client Interaction

	private func commitFindString() {
		pasteboard.findString = state.findString
		pasteboard.replaceString = state.replaceString
	}

	private func performFindOnClient() {
		guard let responder = window?.firstResponder ?? NSApp.mainWindow?.firstResponder else { return }

		// Walk the responder chain to find a FindClient
		var current: NSResponder? = responder
		while let r = current {
			if let client = r as? FindClient {
				client.performFindOperation(self)
				return
			}
			current = r.nextResponder
		}

		statusBarVC.statusText = "No text view to search"
	}

	// MARK: - Folder Search

	private func showFolderSelectionPanel() {
		let openPanel = NSOpenPanel()
		openPanel.canChooseFiles = false
		openPanel.canChooseDirectories = true
		openPanel.allowsMultipleSelection = false
		openPanel.prompt = "Search"

		if let folder = projectFolder {
			openPanel.directoryURL = URL(fileURLWithPath: folder)
		}

		openPanel.beginSheetModal(for: window!) { [weak self] response in
			guard response == .OK, let url = openPanel.url else { return }
			self?.projectFolder = url.path
			self?.addRecentFolder(url.path)
			self?.state.searchScope = .other
			self?.buildWherePopup()
		}
	}

	private func startFolderSearch() {
		stopFolderSearch()

		let searchPaths: [String]
		switch state.searchScope {
		case .project:
			guard let folder = projectFolder else {
				statusBarVC.statusText = "No project folder set"
				return
			}
			searchPaths = [folder]
		case .other:
			guard let folder = projectFolder else {
				showFolderSelectionPanel()
				return
			}
			searchPaths = [folder]
		case .fileBrowserItems:
			searchPaths = fileBrowserItems
		default:
			return
		}

		guard !state.findString.isEmpty else {
			statusBarVC.statusText = "Enter a search string"
			return
		}

		let globString = globField.stringValue.isEmpty ? nil : globField.stringValue
		let includeGlobs = globString.map { [$0] } ?? []

		let config = ProjectSearchConfig(
			pattern: state.findString,
			options: state.options,
			searchPaths: searchPaths,
			includeGlobs: includeGlobs,
			followFileLinks: searchFileLinksCheckbox.state == .on,
			followDirectoryLinks: searchFolderLinksCheckbox.state == .on,
			searchHidden: searchHiddenFoldersCheckbox.state == .on,
			searchBinary: searchBinaryFilesCheckbox.state == .on,
		)

		let engine = ProjectSearchEngine(config: config)
		documentSearch = engine

		let root = SearchResultNode(type: .root)
		resultsVC.results = root

		showResults(true)
		statusBarVC.isProgressVisible = true
		statusBarVC.statusText = "Searching…"

		engine.onMatchesFound = { [weak self] matches in
			self?.folderSearchDidReceiveMatches(matches)
		}

		engine.onProgressUpdate = { [weak self] progress in
			self?.statusBarVC.statusText = "Scanned \(progress.filesScanned) files…"
		}

		engine.onComplete = { [weak self] progress in
			self?.folderSearchDidFinish(progress)
		}

		engine.start()
	}

	private func stopFolderSearch() {
		documentSearch?.cancel()
		documentSearch = nil
		statusBarVC.isProgressVisible = false
	}

	private func folderSearchDidReceiveMatches(_ matches: [DocumentMatch]) {
		guard let root = resultsVC.results else { return }

		var newGroupIndexes = IndexSet()

		for match in matches {
			let displayName = match.displayName
			let path = match.documentPath ?? displayName
			let groupExisted = root.children.contains { node in
				if case let .file(p, _) = node.type { return p == path }
				return false
			}

			let group = root.fileGroup(forPath: path, displayName: displayName)
			group.addMatch(match)

			if !groupExisted {
				if let newIdx = root.children.firstIndex(where: { $0 === group }) {
					newGroupIndexes.insert(newIdx)
				}
			}
		}

		if !newGroupIndexes.isEmpty {
			resultsVC.insertItems(at: newGroupIndexes)
		} else {
			// Reload to update existing groups
			resultsVC.results = root
		}
	}

	private func folderSearchDidFinish(_ progress: SearchProgress) {
		statusBarVC.isProgressVisible = false

		let s = progress.totalMatches == 1 ? "" : "es"
		let fs = progress.filesMatched == 1 ? "" : "s"
		statusBarVC.statusText = "\(progress.totalMatches) match\(s) in \(progress.filesMatched) file\(fs)"
		statusBarVC.alternateStatusText = "\(progress.filesScanned) files scanned"
	}

	private func showResults(_ show: Bool) {
		resultsVisible = show
		resultsHeightConstraint?.constant = show ? 200 : 0

		if show {
			let frame = window?.frame ?? .zero
			let minHeight: CGFloat = 400
			if frame.height < minHeight {
				var newFrame = frame
				newFrame.size.height = minHeight
				newFrame.origin.y -= (minHeight - frame.height)
				window?.setFrame(newFrame, display: true, animate: true)
			}
		}
	}

	// MARK: - Result Selection

	private func didSelectResult(_ node: SearchResultNode) {
		guard case let .match(docMatch) = node.type else { return }
		navigationDelegate?.selectRange(docMatch.lineRange, inDocumentWithID: docMatch.documentID)
	}

	private func didDoubleClickResult(_ node: SearchResultNode) {
		guard case .match = node.type else { return }
		window?.orderOut(nil)
	}

	// MARK: - Recent Folders

	private func addRecentFolder(_ path: String) {
		recentFolders.removeAll { $0 == path }
		recentFolders.insert(path, at: 0)
		if recentFolders.count > 5 {
			recentFolders = Array(recentFolders.prefix(5))
		}
	}

	// MARK: - Copy Results

	/// Copy matching text from all active (non-excluded) results.
	public func copyMatchingParts() -> String {
		guard let root = resultsVC.results else { return "" }
		return root.allMatches.map(\.excerpt).joined(separator: "\n")
	}

	/// Copy entire lines for all active (non-excluded) results.
	public func copyEntireLines() -> String {
		guard let root = resultsVC.results else { return "" }
		return root.allMatches.map(\.excerpt).joined(separator: "\n")
	}

	// MARK: - Check/Uncheck All

	/// Include all results in replacement.
	public func checkAll() {
		setAllExcluded(false)
	}

	/// Exclude all results from replacement.
	public func uncheckAll() {
		setAllExcluded(true)
	}

	private func setAllExcluded(_ excluded: Bool) {
		guard let root = resultsVC.results else { return }
		for group in root.children {
			for child in group.children {
				child.isExcluded = excluded
			}
		}
		resultsVC.results = root // Trigger reload
	}
}

// MARK: - SearchScope + CaseIterable

extension SearchScope: CaseIterable {
	public static var allCases: [SearchScope] {
		[.document, .selection, .openFiles, .project, .fileBrowserItems, .other]
	}
}
#endif
