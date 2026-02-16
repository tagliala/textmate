#if canImport(AppKit)
import AppKit

/// Variables preferences pane — user-defined environment variables.
///
/// Port of `Frameworks/Preferences/src/VariablesPreferences.mm`.
@MainActor
public final class VariablesPreferencesPane: NSViewController, PreferencesPaneProtocol {
	public var toolbarItemImage: NSImage? {
		NSImage(systemSymbolName: "dollarsign.circle", accessibilityDescription: "Variables")
	}

	public var toolbarItemLabel: String {
		"Variables"
	}

	public var paneIdentifier: String {
		"Variables"
	}

	// MARK: - Data Model

	/// A single environment variable entry.
	public struct EnvironmentVariable: Sendable, Equatable {
		public var enabled: Bool
		public var name: String
		public var value: String

		public init(enabled: Bool = true, name: String = "", value: String = "") {
			self.enabled = enabled
			self.name = name
			self.value = value
		}

		/// Convert to a dictionary for UserDefaults persistence.
		public var dictionaryRepresentation: [String: Any] {
			["enabled": enabled, "name": name, "value": value]
		}

		/// Initialize from a dictionary loaded from UserDefaults.
		public init?(dictionary: [String: Any]) {
			guard let name = dictionary["name"] as? String,
			      let value = dictionary["value"] as? String
			else { return nil }
			enabled = dictionary["enabled"] as? Bool ?? false
			self.name = name
			self.value = value
		}
	}

	/// Current environment variables.
	public var variables: [EnvironmentVariable] = [] {
		didSet { tableView?.reloadData() }
	}

	/// Callback when variables change.
	public var onVariablesChanged: (([EnvironmentVariable]) -> Void)?

	// MARK: - UI

	private var tableView: NSTableView!

	override public func loadView() {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))

		// Table view
		tableView = NSTableView()
		tableView.style = .fullWidth
		tableView.usesAlternatingRowBackgroundColors = true

		let enabledCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
		enabledCol.title = ""
		enabledCol.width = 24
		enabledCol.minWidth = 24
		enabledCol.maxWidth = 24
		tableView.addTableColumn(enabledCol)

		let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
		nameCol.title = "Variable Name"
		nameCol.width = 160
		tableView.addTableColumn(nameCol)

		let valueCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
		valueCol.title = "Value"
		valueCol.width = 300
		tableView.addTableColumn(valueCol)

		tableView.dataSource = self
		tableView.delegate = self

		let scrollView = NSScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		container.addSubview(scrollView)

		// Buttons
		let addButton = NSButton(title: "+", target: self, action: #selector(addVariable(_:)))
		addButton.translatesAutoresizingMaskIntoConstraints = false
		addButton.bezelStyle = .smallSquare
		addButton.setContentHuggingPriority(.required, for: .horizontal)
		container.addSubview(addButton)

		let removeButton = NSButton(title: "−", target: self, action: #selector(removeVariable(_:)))
		removeButton.translatesAutoresizingMaskIntoConstraints = false
		removeButton.bezelStyle = .smallSquare
		removeButton.setContentHuggingPriority(.required, for: .horizontal)
		container.addSubview(removeButton)

		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
			scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),

			addButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			addButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
			addButton.widthAnchor.constraint(equalToConstant: 24),

			removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 2),
			removeButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
			removeButton.widthAnchor.constraint(equalToConstant: 24),
		])

		view = container
		loadVariablesFromDefaults()
	}

	// MARK: - Persistence

	/// Load variables from UserDefaults.
	public func loadVariablesFromDefaults() {
		let dicts = UserDefaults.standard.array(forKey: PreferencesKeys.environmentVariables) as? [[String: Any]]
		if let dicts {
			variables = dicts.compactMap(EnvironmentVariable.init(dictionary:))
		} else {
			// Use default variables
			variables = PreferencesKeys.defaultEnvironmentVariables.map {
				EnvironmentVariable(enabled: $0.enabled, name: $0.name, value: $0.value)
			}
		}
	}

	/// Save variables to UserDefaults.
	public func saveVariablesToDefaults() {
		let dicts = variables.map(\.dictionaryRepresentation)
		UserDefaults.standard.set(dicts, forKey: PreferencesKeys.environmentVariables)
		onVariablesChanged?(variables)
	}

	// MARK: - Actions

	@objc private func addVariable(_: Any?) {
		variables.append(EnvironmentVariable())
		tableView.reloadData()
		tableView.editColumn(1, row: variables.count - 1, with: nil, select: true)
		saveVariablesToDefaults()
	}

	@objc private func removeVariable(_: Any?) {
		let row = tableView.selectedRow
		guard row >= 0, row < variables.count else { return }
		variables.remove(at: row)
		tableView.reloadData()
		saveVariablesToDefaults()
	}
}

// MARK: - NSTableViewDataSource

extension VariablesPreferencesPane: NSTableViewDataSource {
	public func numberOfRows(in _: NSTableView) -> Int {
		variables.count
	}
}

// MARK: - NSTableViewDelegate

extension VariablesPreferencesPane: NSTableViewDelegate {
	public func tableView(_: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard row < variables.count else { return nil }
		let variable = variables[row]
		let colID = tableColumn?.identifier.rawValue ?? ""

		switch colID {
		case "enabled":
			let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
			checkbox.state = variable.enabled ? .on : .off
			checkbox.tag = row
			return checkbox

		case "name":
			let field = NSTextField()
			field.stringValue = variable.name
			field.isEditable = true
			field.isBordered = false
			field.backgroundColor = .clear
			field.delegate = self
			field.tag = row
			field.identifier = NSUserInterfaceItemIdentifier("name")
			return field

		case "value":
			let field = NSTextField()
			field.stringValue = variable.value
			field.isEditable = true
			field.isBordered = false
			field.backgroundColor = .clear
			field.delegate = self
			field.tag = row
			field.identifier = NSUserInterfaceItemIdentifier("value")
			return field

		default:
			return nil
		}
	}

	@objc private func toggleEnabled(_ sender: NSButton) {
		let row = sender.tag
		guard row >= 0, row < variables.count else { return }
		variables[row].enabled = sender.state == .on
		saveVariablesToDefaults()
	}
}

// MARK: - NSTextFieldDelegate

extension VariablesPreferencesPane: NSTextFieldDelegate {
	public func controlTextDidEndEditing(_ notification: Notification) {
		guard let field = notification.object as? NSTextField else { return }
		let row = field.tag
		guard row >= 0, row < variables.count else { return }

		let colID = field.identifier?.rawValue ?? ""
		switch colID {
		case "name":
			variables[row].name = field.stringValue
			// Auto-enable when editing name
			if !field.stringValue.isEmpty {
				variables[row].enabled = true
			}
		case "value":
			variables[row].value = field.stringValue
			// Auto-enable when editing value
			if !field.stringValue.isEmpty {
				variables[row].enabled = true
			}
		default:
			break
		}
		saveVariablesToDefaults()
	}
}
#endif
