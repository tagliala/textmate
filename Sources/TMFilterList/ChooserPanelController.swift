#if canImport(AppKit)
import AppKit

/// Delegate protocol for chooser panel events.
@MainActor
public protocol ChooserPanelDelegate: AnyObject {
	/// Called when the user selects items and confirms (Return key or double-click).
	func chooserPanel(_ controller: ChooserPanelController, didSelectItems items: [any ChooserItem])
	/// Called when the chooser panel is dismissed without selection.
	func chooserPanelDidCancel(_ controller: ChooserPanelController)
}

/// Base controller for floating chooser panels (Go to File, Go to Symbol, etc.).
///
/// Port of TextMate's `OakChooser` — provides a floating panel with a search field
/// at top, a table view in the middle, and a status footer at the bottom.
/// Subclasses override `updateItems(_:)` to populate with filtered results.
@MainActor
open class ChooserPanelController: NSWindowController {
	// MARK: - Properties

	/// Delegate for selection/cancel events.
	public weak var delegate: ChooserPanelDelegate?

	/// The current filter string typed by the user.
	public var filterString: String = "" {
		didSet {
			guard filterString != oldValue else { return }
			searchField.stringValue = filterString
			updateItems(self)
			if tableView.numberOfRows > 0 {
				tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
				tableView.scrollRowToVisible(0)
			}
			updateStatusText()
		}
	}

	/// Items currently displayed in the table.
	public var items: [any ChooserItem] = [] {
		didSet {
			tableView.reloadData()
			if tableView.numberOfRows > 0 {
				tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			}
			itemCountField.stringValue = "\(items.count) items"
		}
	}

	/// Currently selected items.
	public var selectedItems: [any ChooserItem] {
		tableView.selectedRowIndexes.compactMap { row in
			row < items.count ? items[row] : nil
		}
	}

	// MARK: - UI Elements

	/// The search field at the top of the panel.
	public let searchField = NSSearchField()

	/// The results table view.
	public let tableView = NSTableView()

	/// The scroll view containing the table.
	public let scrollView = NSScrollView()

	/// Footer view for status text.
	public let footerView = NSVisualEffectView()

	/// Status text label in the footer.
	public let statusTextField = NSTextField(labelWithString: "")

	/// Item count label in the footer.
	public let itemCountField = NSTextField(labelWithString: "")

	// MARK: - Initialization

	/// Create a chooser panel with the given title.
	public init(title: String = "Choose") {
		let panel = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
			styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
			backing: .buffered,
			defer: true,
		)
		panel.title = title
		panel.isFloatingPanel = true
		panel.becomesKeyOnlyIfNeeded = false
		panel.hidesOnDeactivate = false
		panel.isReleasedWhenClosed = false
		panel.minSize = NSSize(width: 300, height: 200)
		panel.animationBehavior = .utilityWindow

		super.init(window: panel)

		setupUI()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - UI Setup

	private func setupUI() {
		guard let contentView = window?.contentView else { return }

		// Search field
		searchField.translatesAutoresizingMaskIntoConstraints = false
		searchField.placeholderString = "Filter"
		searchField.sendsSearchStringImmediately = true
		searchField.target = self
		searchField.action = #selector(searchFieldChanged(_:))
		searchField.focusRingType = .none
		contentView.addSubview(searchField)

		// Scroll view with table
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.hasVerticalScroller = true
		scrollView.borderType = .noBorder

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
		column.resizingMask = .autoresizingMask
		tableView.addTableColumn(column)
		tableView.headerView = nil
		tableView.rowHeight = 36
		tableView.usesAlternatingRowBackgroundColors = true
		tableView.allowsMultipleSelection = false
		tableView.doubleAction = #selector(acceptSelection(_:))
		tableView.target = self

		scrollView.documentView = tableView
		contentView.addSubview(scrollView)

		// Footer
		footerView.translatesAutoresizingMaskIntoConstraints = false
		footerView.blendingMode = .withinWindow
		footerView.material = .titlebar

		statusTextField.translatesAutoresizingMaskIntoConstraints = false
		statusTextField.font = .systemFont(ofSize: 11)
		statusTextField.textColor = .secondaryLabelColor
		footerView.addSubview(statusTextField)

		itemCountField.translatesAutoresizingMaskIntoConstraints = false
		itemCountField.font = .systemFont(ofSize: 11)
		itemCountField.textColor = .secondaryLabelColor
		itemCountField.alignment = .right
		footerView.addSubview(itemCountField)

		contentView.addSubview(footerView)

		// Layout constraints
		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
			searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

			scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
			scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

			footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			footerView.heightAnchor.constraint(equalToConstant: 24),

			statusTextField.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 8),
			statusTextField.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),

			itemCountField.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -8),
			itemCountField.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
		])
	}

	// MARK: - Presentation

	/// Show the panel relative to a parent frame (centered horizontally, near top).
	public func showWindow(relativeTo parentFrame: NSRect) {
		guard let panel = window else { return }

		let panelSize = panel.frame.size
		let x = parentFrame.midX - panelSize.width / 2
		let y = parentFrame.maxY - panelSize.height - 40

		panel.setFrameOrigin(NSPoint(x: x, y: y))
		showWindow(nil)
		window?.makeFirstResponder(searchField)
	}

	// MARK: - Subclass Override Points

	/// Override to update items when the filter string changes.
	/// The base implementation does nothing.
	open func updateItems(_: Any?) {
		// Subclasses override
	}

	/// Override to provide custom status text.
	open func updateStatusText() {
		// Subclasses override
	}

	// MARK: - Actions

	@objc private func searchFieldChanged(_ sender: NSSearchField) {
		let newFilter = sender.stringValue
		if newFilter != filterString {
			filterString = newFilter
		}
	}

	@objc private func acceptSelection(_: Any?) {
		let selected = selectedItems
		guard !selected.isEmpty else { return }
		close()
		delegate?.chooserPanel(self, didSelectItems: selected)
	}

	/// Cancel the chooser (Escape key).
	public func cancelChooser() {
		close()
		delegate?.chooserPanelDidCancel(self)
	}
}

#endif
