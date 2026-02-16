#if canImport(AppKit)
import AppKit

/// Item representing a file in the commit window.
///
/// Port of `CommitWindow/src/CWItem`.
public struct CommitItem: Sendable, Equatable, Identifiable {
	public let id: String // path as unique identifier
	/// File path (standardized).
	public let path: String
	/// Whether the file should be included in the commit.
	public var commit: Bool
	/// Single-character SCM status code (M, A, D, R, C, ?, X, I, G).
	public let scmStatus: String

	public init(path: String, scmStatus: String, commit: Bool = true) {
		id = path
		self.path = path
		self.scmStatus = scmStatus
		// Auto-deselect untracked and external items by default
		self.commit = commit && scmStatus != "?" && scmStatus != "X"
	}

	/// Comparison by path.
	public static func < (lhs: CommitItem, rhs: CommitItem) -> Bool {
		lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
	}
}

/// An action command that can be applied to files in the commit window.
///
/// Parsed from `--action-cmd` arguments. Format: `"M,A,D:Revert,/usr/bin/svn,revert"`.
public struct CommitActionCommand: Sendable {
	/// Display name.
	public let name: String
	/// Command to execute.
	public let command: [String]
	/// Set of status codes this command applies to.
	public let targetStatuses: Set<String>

	public init(name: String, command: [String], targetStatuses: Set<String>) {
		self.name = name
		self.command = command
		self.targetStatuses = targetStatuses
	}

	/// Parse from a colon-separated string: "M,A,D:Revert,/usr/bin/svn,revert".
	public static func parse(_ string: String) -> CommitActionCommand? {
		let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
		guard parts.count == 2 else { return nil }
		let statuses = Set(parts[0].split(separator: ",").map(String.init))
		let commandParts = parts[1].split(separator: ",").map(String.init)
		guard let name = commandParts.first, commandParts.count >= 2 else { return nil }
		return CommitActionCommand(
			name: name,
			command: Array(commandParts.dropFirst()),
			targetStatuses: statuses,
		)
	}
}

/// Delegate protocol for commit window actions.
@MainActor
public protocol CommitWindowDelegate: AnyObject {
	/// Called when the user commits with a message and selected files.
	func commitWindow(_ controller: CommitWindowController, didCommitMessage: String, items: [CommitItem])
	/// Called when the user cancels the commit.
	func commitWindowDidCancel(_ controller: CommitWindowController)
	/// Called to run a diff for a specific file.
	func commitWindow(_ controller: CommitWindowController, runDiffForItem: CommitItem)
	/// Called to run an action command on files.
	func commitWindow(_ controller: CommitWindowController, runAction: CommitActionCommand, onItems: [CommitItem])
}

/// VCS commit sheet controller — shown as a sheet on the project window.
///
/// Port of `Frameworks/CommitWindow/src/CommitWindow.mm`.
/// Displays a commit message editor, file checklist with SCM status, and action commands.
@MainActor
public final class CommitWindowController: NSWindowController {
	// MARK: - Properties

	/// Delegate for commit actions.
	public weak var delegate: CommitWindowDelegate?

	/// Files to commit.
	public var items: [CommitItem] = [] {
		didSet {
			fileTableView?.reloadData()
			updateCommitButton()
		}
	}

	/// Action commands available.
	public var actionCommands: [CommitActionCommand] = []

	/// Previous commit messages (most recent first, max 5).
	public private(set) var previousMessages: [String] = []

	/// The commit button title prefix (default: "Commit").
	public var commitButtonPrefix: String = "Commit"

	/// The SCM name for commit message grammar (e.g., "git", "svn", "hg").
	public var scmName: String = "git"

	/// Whether to show a "Continue" button.
	public var showContinueButton: Bool = false

	// MARK: - UI

	private var messageTextView: NSTextView!
	private var fileTableView: NSTableView?
	private var commitButton: NSButton!
	private var cancelButton: NSButton!
	private var previousMessagesPopUp: NSPopUpButton!
	private var fileListVisible: Bool {
		get { UserDefaults.standard.bool(forKey: "showFileListInCommitWindow") }
		set { UserDefaults.standard.set(newValue, forKey: "showFileListInCommitWindow") }
	}

	// MARK: - UserDefaults Keys

	private static let commitMessagesKey = "commitMessages"
	private static let maxPreviousMessages = 5

	// MARK: - Initialization

	public init(initialMessage: String = "") {
		let window = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false,
		)
		window.title = "Commit Changes"
		window.isReleasedWhenClosed = false
		window.minSize = NSSize(width: 400, height: 300)

		super.init(window: window)

		loadPreviousMessages()
		setupUI()

		if !initialMessage.isEmpty {
			messageTextView.string = initialMessage
		}
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Show

	/// Show the commit sheet on a parent window.
	public func showAsSheet(on parentWindow: NSWindow) {
		guard let window else { return }
		parentWindow.beginSheet(window)
	}

	/// Dismiss the commit sheet.
	public func dismiss() {
		guard let window, let sheetParent = window.sheetParent else {
			window?.close()
			return
		}
		sheetParent.endSheet(window)
	}

	// MARK: - UI Setup

	private func setupUI() {
		guard let contentView = window?.contentView else { return }

		// Message text view
		let scrollView = NSScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.hasVerticalScroller = true
		scrollView.borderType = .bezelBorder

		messageTextView = NSTextView()
		messageTextView.isRichText = false
		messageTextView.font = NSFont.userFixedPitchFont(ofSize: 12)
		messageTextView.isAutomaticQuoteSubstitutionEnabled = false
		messageTextView.isAutomaticDashSubstitutionEnabled = false
		messageTextView.isAutomaticTextReplacementEnabled = false
		messageTextView.textContainerInset = NSSize(width: 4, height: 4)
		scrollView.documentView = messageTextView
		contentView.addSubview(scrollView)

		// Previous messages popup
		previousMessagesPopUp = NSPopUpButton(frame: .zero, pullsDown: true)
		previousMessagesPopUp.translatesAutoresizingMaskIntoConstraints = false
		(previousMessagesPopUp.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
		previousMessagesPopUp.addItem(withTitle: "Previous Messages")
		rebuildPreviousMessagesMenu()
		contentView.addSubview(previousMessagesPopUp)

		// File table (initially hidden based on saved state)
		let fileScroll = NSScrollView()
		fileScroll.translatesAutoresizingMaskIntoConstraints = false
		fileScroll.hasVerticalScroller = true
		fileScroll.borderType = .bezelBorder

		let table = NSTableView()
		table.style = .fullWidth
		table.usesAlternatingRowBackgroundColors = true
		table.allowsMultipleSelection = true

		let commitCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("commit"))
		commitCol.title = ""
		commitCol.width = 24
		commitCol.minWidth = 24
		commitCol.maxWidth = 24
		table.addTableColumn(commitCol)

		let statusCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
		statusCol.title = ""
		statusCol.width = 24
		statusCol.minWidth = 24
		statusCol.maxWidth = 24
		table.addTableColumn(statusCol)

		let pathCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
		pathCol.title = "File"
		pathCol.width = 340
		table.addTableColumn(pathCol)

		let diffCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
		diffCol.title = ""
		diffCol.width = 40
		diffCol.minWidth = 40
		diffCol.maxWidth = 40
		table.addTableColumn(diffCol)

		table.dataSource = self
		table.delegate = self
		table.doubleAction = #selector(doubleClickedRow(_:))
		table.target = self
		fileScroll.documentView = table
		fileTableView = table
		contentView.addSubview(fileScroll)

		// Buttons
		commitButton = NSButton(title: "Commit", target: self, action: #selector(commit(_:)))
		commitButton.translatesAutoresizingMaskIntoConstraints = false
		commitButton.keyEquivalent = "\r"
		contentView.addSubview(commitButton)

		cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
		cancelButton.translatesAutoresizingMaskIntoConstraints = false
		cancelButton.keyEquivalent = "\u{1b}"
		contentView.addSubview(cancelButton)

		// Toggle file list button
		let toggleButton = NSButton(title: "▼ Files", target: self, action: #selector(toggleFileList(_:)))
		toggleButton.translatesAutoresizingMaskIntoConstraints = false
		toggleButton.bezelStyle = .recessed
		contentView.addSubview(toggleButton)

		NSLayoutConstraint.activate([
			previousMessagesPopUp.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
			previousMessagesPopUp.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

			scrollView.topAnchor.constraint(equalTo: previousMessagesPopUp.bottomAnchor, constant: 8),
			scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
			scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
			scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

			toggleButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
			toggleButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),

			fileScroll.topAnchor.constraint(equalTo: toggleButton.bottomAnchor, constant: 4),
			fileScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
			fileScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
			fileScroll.heightAnchor.constraint(equalToConstant: fileListVisible ? 190 : 0),

			commitButton.topAnchor.constraint(equalTo: fileScroll.bottomAnchor, constant: 12),
			commitButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
			commitButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

			cancelButton.trailingAnchor.constraint(equalTo: commitButton.leadingAnchor, constant: -8),
			cancelButton.centerYAnchor.constraint(equalTo: commitButton.centerYAnchor),
		])

		updateCommitButton()
	}

	// MARK: - Actions

	@objc private func commit(_: Any?) {
		let message = messageTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !message.isEmpty else { return }

		savePreviousMessage(message)
		delegate?.commitWindow(self, didCommitMessage: message, items: items.filter(\.commit))
		dismiss()
	}

	@objc private func cancel(_: Any?) {
		delegate?.commitWindowDidCancel(self)
		dismiss()
	}

	@objc private func toggleFileList(_: Any?) {
		fileListVisible.toggle()
		// Animate height change
		if let constraint = fileTableView?.enclosingScrollView?.constraints.first(where: {
			$0.firstAttribute == .height && $0.relation == .equal
		}) {
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.25
				constraint.animator().constant = fileListVisible ? 190 : 0
			}
		}
	}

	@objc private func doubleClickedRow(_: Any?) {
		guard let table = fileTableView else { return }
		let row = table.clickedRow
		guard row >= 0, row < items.count else { return }
		delegate?.commitWindow(self, runDiffForItem: items[row])
	}

	@objc private func toggleCommit(_ sender: NSButton) {
		let row = sender.tag
		guard row >= 0, row < items.count else { return }
		items[row].commit = sender.state == .on
		updateCommitButton()
	}

	// MARK: - Commit Button

	private func updateCommitButton() {
		let count = items.filter(\.commit).count
		let noun = count == 1 ? "Item" : "Items"
		let continueText = showContinueButton ? " & Continue" : ""
		commitButton?.title = "\(commitButtonPrefix) \(count) \(noun)\(continueText)"
		commitButton?.isEnabled = count > 0
	}

	// MARK: - Previous Messages

	private func loadPreviousMessages() {
		previousMessages = UserDefaults.standard.stringArray(forKey: Self.commitMessagesKey) ?? []
	}

	private func savePreviousMessage(_ message: String) {
		previousMessages.removeAll { $0 == message }
		previousMessages.insert(message, at: 0)
		if previousMessages.count > Self.maxPreviousMessages {
			previousMessages = Array(previousMessages.prefix(Self.maxPreviousMessages))
		}
		UserDefaults.standard.set(previousMessages, forKey: Self.commitMessagesKey)
		rebuildPreviousMessagesMenu()
	}

	private func rebuildPreviousMessagesMenu() {
		guard let menu = previousMessagesPopUp?.menu else { return }
		// Keep the first item (title)
		while menu.items.count > 1 {
			menu.removeItem(at: 1)
		}
		for (index, msg) in previousMessages.enumerated() {
			let truncated = msg.count > 30 ? String(msg.prefix(30)) + "…" : msg
			let item = NSMenuItem(title: truncated, action: #selector(selectPreviousMessage(_:)), keyEquivalent: "")
			item.target = self
			item.tag = index
			menu.addItem(item)
		}
		if !previousMessages.isEmpty {
			menu.addItem(.separator())
			let clearItem = NSMenuItem(
				title: "Clear Menu",
				action: #selector(clearPreviousMessages(_:)),
				keyEquivalent: "",
			)
			clearItem.target = self
			menu.addItem(clearItem)
		}
	}

	@objc private func selectPreviousMessage(_ sender: NSMenuItem) {
		let index = sender.tag
		guard index >= 0, index < previousMessages.count else { return }
		messageTextView.string = previousMessages[index]
	}

	@objc private func clearPreviousMessages(_: Any?) {
		previousMessages.removeAll()
		UserDefaults.standard.removeObject(forKey: Self.commitMessagesKey)
		rebuildPreviousMessagesMenu()
	}

	// MARK: - Status Colors

	/// Get foreground/background colors for a SCM status character.
	public static func statusColors(for status: String) -> (foreground: NSColor, background: NSColor) {
		switch status {
		case "M", "G":
			(
				NSColor(red: 0.92, green: 0.39, blue: 0.0, alpha: 1.0),
				NSColor(red: 0.97, green: 0.88, blue: 0.68, alpha: 1.0),
			)
		case "X":
			(.white, .black)
		case "A":
			(
				NSColor(red: 0.0, green: 0.67, blue: 0.0, alpha: 1.0),
				NSColor(red: 0.73, green: 1.0, blue: 0.70, alpha: 1.0),
			)
		case "D", "R":
			(
				.red,
				NSColor(red: 0.96, green: 0.74, blue: 0.74, alpha: 1.0),
			)
		case "C", "?":
			(
				NSColor(red: 0.0, green: 0.50, blue: 0.50, alpha: 1.0),
				NSColor(red: 0.64, green: 0.81, blue: 0.82, alpha: 1.0),
			)
		case "I":
			(
				NSColor(red: 0.50, green: 0.0, blue: 0.50, alpha: 1.0),
				NSColor(red: 0.93, green: 0.68, blue: 0.96, alpha: 1.0),
			)
		default:
			(.labelColor, .clear)
		}
	}

	/// Create a colored attributed string for a status character.
	public static func attributedStatus(_ status: String) -> NSAttributedString {
		let (fg, bg) = statusColors(for: status)
		return NSAttributedString(string: " \(status) ", attributes: [
			.foregroundColor: fg,
			.backgroundColor: bg,
			.font: NSFont.systemFont(ofSize: 11, weight: .medium),
		])
	}
}

// MARK: - NSTableViewDataSource

extension CommitWindowController: NSTableViewDataSource {
	public func numberOfRows(in _: NSTableView) -> Int {
		items.count
	}
}

// MARK: - NSTableViewDelegate

extension CommitWindowController: NSTableViewDelegate {
	public func tableView(_: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard row < items.count else { return nil }
		let item = items[row]
		let colID = tableColumn?.identifier.rawValue ?? ""

		switch colID {
		case "commit":
			let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleCommit(_:)))
			checkbox.state = item.commit ? .on : .off
			checkbox.tag = row
			return checkbox

		case "status":
			let label = NSTextField(labelWithString: "")
			label.attributedStringValue = Self.attributedStatus(item.scmStatus)
			label.alignment = .center
			return label

		case "path":
			// Show just the filename, with directory as tooltip
			let name = (item.path as NSString).lastPathComponent
			let label = NSTextField(labelWithString: name)
			label.toolTip = item.path
			return label

		case "diff":
			let btn = NSButton(title: "Diff", target: self, action: #selector(diffClicked(_:)))
			btn.bezelStyle = .recessed
			btn.tag = row
			btn.font = NSFont.systemFont(ofSize: 10)
			return btn

		default:
			return nil
		}
	}

	@objc private func diffClicked(_ sender: NSButton) {
		let row = sender.tag
		guard row >= 0, row < items.count else { return }
		delegate?.commitWindow(self, runDiffForItem: items[row])
	}
}
#endif
