#if canImport(AppKit)
import AppKit
import TMBundleRuntime

// MARK: - Permission Dialog

/// Presents a modal dialog when a bundle command requires elevated trust.
///
/// Shows the command name, bundle name, required trust level, and offers
/// Allow Once / Allow Always / Deny Once / Deny Always options.
@MainActor
public final class PermissionDialogController {
	public init() {}

	/// Shows a permission dialog and returns the user's response.
	public func showPermissionDialog(
		for request: PermissionRequest,
	) async -> PermissionResponse {
		await withCheckedContinuation { continuation in
			let alert = NSAlert()
			alert.messageText = "Permission Required"
			alert.informativeText = """
			"\(request.commandName)" from bundle "\(request.bundleName)" \
			requires \(trustLevelDescription(request.requiredLevel)) access.

			Current trust level: \(trustLevelDescription(request.currentLevel))
			"""
			alert.alertStyle = .warning

			alert.addButton(withTitle: "Allow Once")
			alert.addButton(withTitle: "Allow Always")
			alert.addButton(withTitle: "Deny")
			alert.addButton(withTitle: "Deny Always")

			let response = alert.runModal()
			let result: PermissionResponse = switch response {
			case .alertFirstButtonReturn:
				.allowOnce
			case .alertSecondButtonReturn:
				.allowAlways
			case .alertThirdButtonReturn:
				.denyOnce
			default:
				.denyAlways
			}
			continuation.resume(returning: result)
		}
	}

	/// Human-readable trust level description.
	private func trustLevelDescription(_ level: TrustLevel) -> String {
		switch level {
		case .blocked: "Blocked"
		case .readOnly: "Read Only"
		case .documentWrite: "Document Write"
		case .projectWrite: "Project Write"
		case .full: "Full"
		}
	}
}

// MARK: - Security Preferences View

/// A preferences panel component for managing per-bundle trust levels.
@MainActor
public final class SecurityPreferencesController: NSViewController {
	private let securityPolicy: SecurityPolicy
	private let bundleIndex: BundleIndex

	/// Table view showing per-bundle trust overrides.
	private let tableView = NSTableView()

	/// Cached override entries for display.
	private var entries: [(bundleName: String, bundleUUID: String, trustLevel: TrustLevel)] = []

	public init(securityPolicy: SecurityPolicy, bundleIndex: BundleIndex) {
		self.securityPolicy = securityPolicy
		self.bundleIndex = bundleIndex
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not implemented")
	}

	override public func loadView() {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(scrollView)

		let nameColumn = NSTableColumn(identifier: .init("name"))
		nameColumn.title = "Bundle"
		nameColumn.width = 200
		tableView.addTableColumn(nameColumn)

		let trustColumn = NSTableColumn(identifier: .init("trust"))
		trustColumn.title = "Trust Level"
		trustColumn.width = 150
		tableView.addTableColumn(trustColumn)

		tableView.dataSource = self
		tableView.delegate = self

		// Reset button.
		let resetButton = NSButton(
			title: "Reset Selected",
			target: self,
			action: #selector(resetSelected(_:)),
		)
		resetButton.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(resetButton)

		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: container.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			scrollView.bottomAnchor.constraint(
				equalTo: resetButton.topAnchor,
				constant: -8,
			),

			resetButton.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -8,
			),
			resetButton.bottomAnchor.constraint(
				equalTo: container.bottomAnchor,
				constant: -8,
			),
		])

		view = container
	}

	override public func viewDidLoad() {
		super.viewDidLoad()
		reloadData()
	}

	/// Reloads the table with current overrides.
	public func reloadData() {
		entries = securityPolicy.allOverrides.map { uuid, level in
			let name = bundleIndex.bundle(uuid: uuid)?.name ?? uuid
			return (bundleName: name, bundleUUID: uuid, trustLevel: level)
		}.sorted { $0.bundleName < $1.bundleName }

		tableView.reloadData()
	}

	@objc
	private func resetSelected(_: Any?) {
		let row = tableView.selectedRow
		guard row >= 0, row < entries.count else { return }
		let entry = entries[row]
		securityPolicy.resetTrustLevel(forBundle: entry.bundleUUID)
		reloadData()
	}
}

// MARK: - NSTableViewDataSource

extension SecurityPreferencesController: NSTableViewDataSource {
	public func numberOfRows(in _: NSTableView) -> Int {
		entries.count
	}
}

// MARK: - NSTableViewDelegate

extension SecurityPreferencesController: NSTableViewDelegate {
	public func tableView(
		_: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int,
	) -> NSView? {
		guard row < entries.count else { return nil }
		let entry = entries[row]
		let cell = NSTextField(labelWithString: "")
		cell.isEditable = false

		switch tableColumn?.identifier.rawValue {
		case "name":
			cell.stringValue = entry.bundleName
		case "trust":
			switch entry.trustLevel {
			case .blocked: cell.stringValue = "Blocked"
			case .readOnly: cell.stringValue = "Read Only"
			case .documentWrite: cell.stringValue = "Document Write"
			case .projectWrite: cell.stringValue = "Project Write"
			case .full: cell.stringValue = "Full"
			}
		default:
			break
		}

		return cell
	}
}
#endif
