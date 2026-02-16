#if canImport(AppKit)
import AppKit

/// Preferences window controller with toolbar-selectable panes.
///
/// Port of `Frameworks/Preferences/src/Preferences.mm`.
/// Replaces the Iteration 1 stub with fully functional preference panes.
@MainActor
public final class PreferencesWindowController: NSWindowController, NSToolbarDelegate {
	/// Shared singleton instance.
	public static let shared = PreferencesWindowController()

	/// The preference panes in display order.
	public private(set) var panes: [PreferencesPaneProtocol & NSViewController] = []

	/// Currently selected pane index.
	public private(set) var selectedPaneIndex: Int = 0

	/// Transition container for smooth pane switching.
	private let containerView = NSView()

	private init() {
		let window = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false,
		)
		window.title = "Preferences"
		window.isReleasedWhenClosed = false
		window.toolbarStyle = .preference

		super.init(window: window)

		setupDefaultPanes()
		setupToolbar()
		setupContainerView()
		restoreSelection()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Pane Management

	/// Configure the preference panes. Must be called before showing the window.
	public func setPanes(_ newPanes: [PreferencesPaneProtocol & NSViewController]) {
		panes = newPanes
		setupToolbar()
		if selectedPaneIndex >= panes.count {
			selectedPaneIndex = 0
		}
		selectPane(at: selectedPaneIndex, animated: false)
	}

	private func setupDefaultPanes() {
		panes = [
			FilesPreferencesPane(),
			ProjectsPreferencesPane(),
			BundlesPreferencesPane(),
			VariablesPreferencesPane(),
			SoftwareUpdatePreferencesPane(),
			TerminalPreferencesPane(),
		]
	}

	// MARK: - Show

	/// Show the preferences window.
	public func showPreferences() {
		window?.makeKeyAndOrderFront(nil)
	}

	/// Show a specific pane by identifier.
	public func showPane(identifier: String) {
		if let idx = panes.firstIndex(where: { $0.paneIdentifier == identifier }) {
			selectPane(at: idx, animated: false)
		}
		showPreferences()
	}

	// MARK: - Container View

	private func setupContainerView() {
		guard let contentView = window?.contentView else { return }
		containerView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(containerView)
		NSLayoutConstraint.activate([
			containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
			containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
		])
		selectPane(at: selectedPaneIndex, animated: false)
	}

	// MARK: - Pane Selection

	/// Select a preference pane by index.
	public func selectPane(at index: Int, animated: Bool = true) {
		guard index >= 0, index < panes.count else { return }

		// Remove current pane's view
		for subview in containerView.subviews {
			subview.removeFromSuperview()
		}

		selectedPaneIndex = index
		let pane = panes[index]
		let paneView = pane.view
		paneView.translatesAutoresizingMaskIntoConstraints = false
		containerView.addSubview(paneView)

		NSLayoutConstraint.activate([
			paneView.topAnchor.constraint(equalTo: containerView.topAnchor),
			paneView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
			paneView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
			paneView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
		])

		// Resize window to fit pane
		if let window {
			let paneSize = pane.preferredContentSize.width > 0 ? pane.preferredContentSize : NSSize(
				width: 560,
				height: 400,
			)
			var frame = window.frame
			let titleBarHeight = frame.height - (window.contentView?.frame.height ?? 0)
			let newHeight = paneSize.height + titleBarHeight
			frame.origin.y += frame.height - newHeight
			frame.size.height = newHeight
			frame.size.width = max(paneSize.width, 560)
			window.setFrame(frame, display: true, animate: animated)
		}

		// Update toolbar selection
		window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(pane.paneIdentifier)

		// Update title
		window?.title = pane.toolbarItemLabel

		// Save selection
		UserDefaults.standard.set(pane.paneIdentifier, forKey: PreferencesKeys.preferencesSelectedView)
	}

	/// Select the next pane (wrapping).
	@objc public func selectNextTab(_: Any?) {
		let next = (selectedPaneIndex + 1) % panes.count
		selectPane(at: next)
	}

	/// Select the previous pane (wrapping).
	@objc public func selectPreviousTab(_: Any?) {
		let prev = (selectedPaneIndex - 1 + panes.count) % panes.count
		selectPane(at: prev)
	}

	// MARK: - Toolbar

	private func setupToolbar() {
		let toolbar = NSToolbar(identifier: "PreferencesToolbar")
		toolbar.delegate = self
		toolbar.displayMode = .iconAndLabel
		toolbar.allowsUserCustomization = false
		toolbar.selectedItemIdentifier = panes.isEmpty ? nil : NSToolbarItem.Identifier(panes[0].paneIdentifier)
		window?.toolbar = toolbar
	}

	public func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		panes.map { NSToolbarItem.Identifier($0.paneIdentifier) }
	}

	public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarAllowedItemIdentifiers(NSToolbar())
	}

	public func toolbarSelectableItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarAllowedItemIdentifiers(NSToolbar())
	}

	public func toolbar(
		_: NSToolbar,
		itemForItemIdentifier identifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar _: Bool,
	) -> NSToolbarItem? {
		guard let pane = panes.first(where: { $0.paneIdentifier == identifier.rawValue }) else { return nil }

		let item = NSToolbarItem(itemIdentifier: identifier)
		item.label = pane.toolbarItemLabel
		item.image = pane.toolbarItemImage ?? NSImage(
			systemSymbolName: "gearshape",
			accessibilityDescription: pane.toolbarItemLabel,
		)
		item.target = self
		item.action = #selector(toolbarItemClicked(_:))
		return item
	}

	@objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
		if let idx = panes.firstIndex(where: { $0.paneIdentifier == sender.itemIdentifier.rawValue }) {
			selectPane(at: idx)
		}
	}

	// MARK: - State Restoration

	private func restoreSelection() {
		if let savedID = UserDefaults.standard.string(forKey: PreferencesKeys.preferencesSelectedView),
		   let idx = panes.firstIndex(where: { $0.paneIdentifier == savedID })
		{
			selectedPaneIndex = idx
		}
	}
}
#endif
