#if canImport(AppKit)
import AppKit
import TMBundleRuntime

// MARK: - Bundle Manager Controller

/// Window controller for the bundle manager — lists all available
/// and installed bundles with install/update/uninstall actions.
///
/// Mirrors the C++ `BundlesManager` UI: a table of bundles with
/// checkboxes for installed state, category/name grouping, and
/// background update handling.
@MainActor
public final class BundleManagerController: NSWindowController {
	/// The installer managing bundle lifecycle.
	public let installer: BundleInstaller

	/// The table view displaying bundles.
	private let tableView = NSTableView()

	/// Search field for filtering.
	private let searchField = NSSearchField()

	/// Current filter text.
	private var filterText: String = ""

	/// Filtered catalog entries for display.
	private var filteredEntries: [BundleInstaller.CatalogEntry] = []

	/// Activity indicator for background operations.
	private let progressIndicator = NSProgressIndicator()

	public init(installer: BundleInstaller) {
		self.installer = installer

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: false,
		)
		window.title = "Bundle Manager"
		window.center()

		super.init(window: window)
		setupUI()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not implemented")
	}

	// MARK: - UI Setup

	private func setupUI() {
		guard let contentView = window?.contentView else { return }

		// Search field.
		searchField.placeholderString = "Filter Bundles"
		searchField.target = self
		searchField.action = #selector(searchFieldChanged(_:))
		searchField.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(searchField)

		// Table view.
		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(scrollView)

		// Columns.
		let installedColumn = NSTableColumn(identifier: .init("installed"))
		installedColumn.title = "✓"
		installedColumn.width = 30
		installedColumn.minWidth = 30
		installedColumn.maxWidth = 30
		tableView.addTableColumn(installedColumn)

		let nameColumn = NSTableColumn(identifier: .init("name"))
		nameColumn.title = "Name"
		nameColumn.width = 200
		tableView.addTableColumn(nameColumn)

		let categoryColumn = NSTableColumn(identifier: .init("category"))
		categoryColumn.title = "Category"
		categoryColumn.width = 120
		tableView.addTableColumn(categoryColumn)

		let statusColumn = NSTableColumn(identifier: .init("status"))
		statusColumn.title = "Status"
		statusColumn.width = 120
		tableView.addTableColumn(statusColumn)

		tableView.dataSource = self
		tableView.delegate = self
		tableView.usesAlternatingRowBackgroundColors = true

		// Progress indicator.
		progressIndicator.style = .spinning
		progressIndicator.isDisplayedWhenStopped = false
		progressIndicator.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(progressIndicator)

		// Layout.
		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
			searchField.leadingAnchor.constraint(
				equalTo: contentView.leadingAnchor,
				constant: 12,
			),
			searchField.trailingAnchor.constraint(
				equalTo: progressIndicator.leadingAnchor,
				constant: -8,
			),

			progressIndicator.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
			progressIndicator.trailingAnchor.constraint(
				equalTo: contentView.trailingAnchor,
				constant: -12,
			),
			progressIndicator.widthAnchor.constraint(equalToConstant: 16),
			progressIndicator.heightAnchor.constraint(equalToConstant: 16),

			scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
			scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
		])
	}

	// MARK: - Data Loading

	/// Loads the catalog and refreshes the table.
	public func loadCatalog() async {
		progressIndicator.startAnimation(nil)
		await installer.loadCatalog()
		applyFilter()
		progressIndicator.stopAnimation(nil)
	}

	/// Applies the current search filter and reloads the table.
	private func applyFilter() {
		if filterText.isEmpty {
			filteredEntries = installer.catalog
		} else {
			let lower = filterText.lowercased()
			filteredEntries = installer.catalog.filter { entry in
				entry.name.lowercased().contains(lower)
					|| entry.category.lowercased().contains(lower)
			}
		}
		tableView.reloadData()
	}

	// MARK: - Actions

	@objc
	private func searchFieldChanged(_ sender: NSSearchField) {
		filterText = sender.stringValue
		applyFilter()
	}

	/// Installs the bundle at the given row index.
	public func installBundle(at row: Int) async {
		guard row < filteredEntries.count else { return }
		let entry = filteredEntries[row]
		progressIndicator.startAnimation(nil)
		_ = await installer.install(bundleUUIDs: [entry.uuid])
		applyFilter()
		progressIndicator.stopAnimation(nil)
	}

	/// Uninstalls the bundle at the given row index.
	public func uninstallBundle(at row: Int) {
		guard row < filteredEntries.count else { return }
		let entry = filteredEntries[row]
		try? installer.uninstall(bundleUUID: entry.uuid)
		applyFilter()
	}

	/// Returns the status display string for a bundle.
	func statusString(for entry: BundleInstaller.CatalogEntry) -> String {
		if let status = installer.installStatus[entry.uuid] {
			switch status {
			case .notInstalled: return "Not Installed"
			case .installed: return "Installed"
			case .updateAvailable: return "Update Available"
			case let .installing(progress): return "Installing \(Int(progress * 100))%"
			case let .failed(error): return "Error: \(error)"
			}
		}
		return entry.isInstalled ? "Installed" : "Not Installed"
	}
}

// MARK: - NSTableViewDataSource

extension BundleManagerController: NSTableViewDataSource {
	public func numberOfRows(in _: NSTableView) -> Int {
		filteredEntries.count
	}
}

// MARK: - NSTableViewDelegate

extension BundleManagerController: NSTableViewDelegate {
	public func tableView(
		_: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int,
	) -> NSView? {
		guard row < filteredEntries.count else { return nil }
		let entry = filteredEntries[row]

		let cell = NSTextField(labelWithString: "")
		cell.isEditable = false
		cell.isBordered = false
		cell.drawsBackground = false

		switch tableColumn?.identifier.rawValue {
		case "installed":
			cell.stringValue = entry.isInstalled ? "✓" : ""
		case "name":
			cell.stringValue = entry.name
		case "category":
			cell.stringValue = entry.category
		case "status":
			cell.stringValue = statusString(for: entry)
		default:
			break
		}

		return cell
	}
}
#endif
