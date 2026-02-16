#if canImport(AppKit)
import AppKit

/// Bundles preferences pane — install/uninstall bundles, category filter, search.
///
/// Port of `Frameworks/Preferences/src/BundlesPreferences.mm`.
/// Does not subclass `PreferencesPane` — uses its own data model.
@MainActor
public final class BundlesPreferencesPane: NSViewController, PreferencesPaneProtocol {
	public var toolbarItemImage: NSImage? {
		NSWorkspace.shared.icon(forFileType: "tmbundle")
	}

	public var toolbarItemLabel: String {
		"Bundles"
	}

	public var paneIdentifier: String {
		"Bundles"
	}

	// MARK: - Data Model

	/// Bundle descriptor for display in the preferences table.
	public struct BundleInfo: Identifiable, Sendable {
		public let id: String
		public let name: String
		public let category: String
		public let summary: String
		public let htmlURL: URL?
		public let lastUpdated: Date?
		public var isInstalled: Bool

		public init(
			id: String, name: String, category: String = "",
			summary: String = "", htmlURL: URL? = nil,
			lastUpdated: Date? = nil, isInstalled: Bool = false,
		) {
			self.id = id
			self.name = name
			self.category = category
			self.summary = summary
			self.htmlURL = htmlURL
			self.lastUpdated = lastUpdated
			self.isInstalled = isInstalled
		}
	}

	/// All available bundles.
	public var allBundles: [BundleInfo] = [] {
		didSet { refilter() }
	}

	/// Filtered bundles for display.
	public private(set) var filteredBundles: [BundleInfo] = []

	/// Available categories derived from bundles.
	public var categories: [String] {
		Array(Set(allBundles.map(\.category))).sorted()
	}

	/// Selected category filter. Nil = show all.
	public var selectedCategory: String? {
		didSet { refilter() }
	}

	/// Search text filter.
	public var searchText: String = "" {
		didSet { refilter() }
	}

	/// Whether automatic bundle updates are enabled.
	public var autoUpdateEnabled: Bool {
		get { !UserDefaults.standard.bool(forKey: PreferencesKeys.disableBundleUpdates) }
		set { UserDefaults.standard.set(!newValue, forKey: PreferencesKeys.disableBundleUpdates) }
	}

	/// Activity text shown during bundle operations.
	public var activityText: String = ""

	/// Whether a bundle operation is in progress.
	public var isBusy: Bool = false

	/// Callback for install/uninstall actions.
	public var onInstallAction: ((String, Bool) -> Void)?

	/// Callback for bundle link click.
	public var onBundleLinkClick: ((URL) -> Void)?

	// MARK: - UI

	private var tableView: NSTableView!
	private var searchField: NSSearchField!
	private var spinner: NSProgressIndicator!
	private var statusLabel: NSTextField!

	override public func loadView() {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 400))

		// Search field
		searchField = NSSearchField()
		searchField.translatesAutoresizingMaskIntoConstraints = false
		searchField.placeholderString = "Filter"
		searchField.target = self
		searchField.action = #selector(searchChanged(_:))
		container.addSubview(searchField)

		// Table view
		tableView = NSTableView()
		tableView.style = .fullWidth
		tableView.usesAlternatingRowBackgroundColors = true
		tableView.allowsMultipleSelection = false

		let installedCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Installed"))
		installedCol.title = ""
		installedCol.width = 24
		installedCol.minWidth = 24
		installedCol.maxWidth = 24
		tableView.addTableColumn(installedCol)

		let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("BundleName"))
		nameCol.title = "Bundle"
		nameCol.width = 140
		tableView.addTableColumn(nameCol)

		let linkCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("WebLink"))
		linkCol.title = ""
		linkCol.width = 24
		linkCol.minWidth = 24
		linkCol.maxWidth = 24
		tableView.addTableColumn(linkCol)

		let updatedCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Updated"))
		updatedCol.title = "Updated"
		updatedCol.width = 90
		tableView.addTableColumn(updatedCol)

		let descCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Description"))
		descCol.title = "Description"
		descCol.width = 200
		tableView.addTableColumn(descCol)

		tableView.dataSource = self
		tableView.delegate = self

		let scrollView = NSScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		container.addSubview(scrollView)

		// Footer
		spinner = NSProgressIndicator()
		spinner.style = .spinning
		spinner.controlSize = .small
		spinner.translatesAutoresizingMaskIntoConstraints = false
		spinner.isHidden = true
		container.addSubview(spinner)

		statusLabel = NSTextField(labelWithString: "")
		statusLabel.translatesAutoresizingMaskIntoConstraints = false
		statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		statusLabel.textColor = .secondaryLabelColor
		container.addSubview(statusLabel)

		let autoUpdateCheckbox = NSButton(
			checkboxWithTitle: "Check for and install updates automatically",
			target: self, action: #selector(toggleAutoUpdate(_:)),
		)
		autoUpdateCheckbox.translatesAutoresizingMaskIntoConstraints = false
		autoUpdateCheckbox.state = autoUpdateEnabled ? .on : .off
		container.addSubview(autoUpdateCheckbox)

		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
			searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
			searchField.widthAnchor.constraint(equalToConstant: 200),

			scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
			scrollView.bottomAnchor.constraint(equalTo: autoUpdateCheckbox.topAnchor, constant: -8),

			spinner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
			spinner.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

			statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
			statusLabel.centerYAnchor.constraint(equalTo: spinner.centerYAnchor),

			autoUpdateCheckbox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
			autoUpdateCheckbox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
		])

		view = container
	}

	// MARK: - Filtering

	private func refilter() {
		var items = allBundles
		if let cat = selectedCategory, !cat.isEmpty {
			items = items.filter { $0.category == cat }
		}
		if !searchText.isEmpty {
			let lower = searchText.lowercased()
			items = items.filter { $0.name.localizedCaseInsensitiveContains(lower) }
		}
		filteredBundles = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		tableView?.reloadData()
	}

	// MARK: - Actions

	@objc private func searchChanged(_ sender: NSSearchField) {
		searchText = sender.stringValue
	}

	@objc private func toggleAutoUpdate(_ sender: NSButton) {
		autoUpdateEnabled = sender.state == .on
	}

	@objc private func toggleInstall(_ sender: NSButton) {
		let row = tableView.row(for: sender)
		guard row >= 0, row < filteredBundles.count else { return }
		let bundle = filteredBundles[row]
		let install = sender.state == .on
		onInstallAction?(bundle.id, install)
	}

	private let dateFormatter: DateFormatter = {
		let df = DateFormatter()
		df.dateStyle = .medium
		df.timeStyle = .none
		return df
	}()
}

// MARK: - NSTableViewDataSource

extension BundlesPreferencesPane: NSTableViewDataSource {
	public func numberOfRows(in _: NSTableView) -> Int {
		filteredBundles.count
	}
}

// MARK: - NSTableViewDelegate

extension BundlesPreferencesPane: NSTableViewDelegate {
	public func tableView(_: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard row < filteredBundles.count else { return nil }
		let bundle = filteredBundles[row]
		let colID = tableColumn?.identifier.rawValue ?? ""

		switch colID {
		case "Installed":
			let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleInstall(_:)))
			checkbox.state = bundle.isInstalled ? .on : .off
			return checkbox

		case "BundleName":
			return NSTextField(labelWithString: bundle.name)

		case "WebLink":
			if bundle.htmlURL != nil {
				let btn = NSButton(
					image: NSImage(systemSymbolName: "safari", accessibilityDescription: "Web") ?? NSImage(),
					target: self,
					action: #selector(openBundleLink(_:)),
				)
				btn.isBordered = false
				btn.tag = row
				return btn
			}
			return nil

		case "Updated":
			let text = bundle.lastUpdated.map { dateFormatter.string(from: $0) } ?? ""
			return NSTextField(labelWithString: text)

		case "Description":
			return NSTextField(labelWithString: bundle.summary)

		default:
			return nil
		}
	}

	@objc private func openBundleLink(_ sender: NSButton) {
		let row = sender.tag
		guard row >= 0, row < filteredBundles.count, let url = filteredBundles[row].htmlURL else { return }
		onBundleLinkClick?(url)
	}
}
#endif
