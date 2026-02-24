#if canImport(AppKit)
import AppKit

/// Terminal preferences pane — `mate` CLI install, rmate server configuration.
///
/// Port of `Frameworks/Preferences/src/TerminalPreferences.mm`.
@MainActor
public final class TerminalPreferencesPane: PreferencesPane {
	override public var toolbarItemImage: NSImage? {
		NSImage(systemSymbolName: "terminal", accessibilityDescription: "Terminal")
	}

	override public var toolbarItemLabel: String {
		"Terminal"
	}

	override public var paneIdentifier: String {
		"Terminal"
	}

	override public var defaultsProperties: [String: String] {
		[
			"path": PreferencesKeys.mateInstallPath,
			"disableRMate": PreferencesKeys.disableRMateServer,
			"interface": PreferencesKeys.rmateServerListen,
			"port": PreferencesKeys.rmateServerPort,
		]
	}

	// MARK: - State

	/// Current `mate` CLI install path.
	public var mateInstallPath: String {
		get { UserDefaults.standard.string(forKey: PreferencesKeys.mateInstallPath) ?? "/usr/local/bin/mate" }
		set { UserDefaults.standard.set(newValue, forKey: PreferencesKeys.mateInstallPath) }
	}

	/// Whether the `mate` CLI is currently installed.
	public var isMateInstalled: Bool {
		FileManager.default.fileExists(atPath: mateInstallPath)
	}

	/// Installed `mate` version, if any.
	public var installedMateVersion: String? {
		UserDefaults.standard.string(forKey: PreferencesKeys.mateInstallVersion)
	}

	/// Whether rmate server is enabled.
	public var isRMateEnabled: Bool {
		get { !UserDefaults.standard.bool(forKey: PreferencesKeys.disableRMateServer) }
		set { UserDefaults.standard.set(!newValue, forKey: PreferencesKeys.disableRMateServer) }
	}

	/// rmate listen mode.
	public var rmateListen: PreferencesKeys.RMateListenMode {
		get {
			let raw = UserDefaults.standard.string(forKey: PreferencesKeys.rmateServerListen) ?? "localhost"
			return PreferencesKeys.RMateListenMode(rawValue: raw) ?? .localhost
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.rmateServerListen)
		}
	}

	/// rmate port number.
	public var rmatePort: String {
		get { UserDefaults.standard.string(forKey: PreferencesKeys.rmateServerPort) ?? "52698" }
		set { UserDefaults.standard.set(newValue, forKey: PreferencesKeys.rmateServerPort) }
	}

	/// Callback for install/uninstall mate action.
	public var onMateInstall: ((String, Bool) -> Void)?

	// MARK: - UI

	private var installStatusLabel: NSTextField?
	private var installButton: NSButton?
	private var pathPopUp: NSPopUpButton?

	override public func loadView() {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 340))

		let grid = buildGrid()
		grid.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(grid)

		NSLayoutConstraint.activate([
			grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
			grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
		])

		view = container
		updateInstallStatus()
	}

	private func buildGrid() -> NSGridView {
		// Mate install section
		let mateTitle = makeLabel("Terminal usage:")

		let pathPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
		pathPopUp.addItem(withTitle: "/usr/local/bin/mate")
		pathPopUp.addItem(withTitle: "~/bin/mate")
		pathPopUp.menu?.addItem(.separator())
		pathPopUp.addItem(withTitle: "Other…")
		pathPopUp.target = self
		pathPopUp.action = #selector(pathChanged(_:))
		self.pathPopUp = pathPopUp

		// Select the current path
		let current = mateInstallPath
		if let idx = pathPopUp.itemArray.firstIndex(where: { $0.title == current }) {
			pathPopUp.selectItem(at: idx)
		}

		let installBtn = NSButton(title: "Install", target: self, action: #selector(installMate(_:)))
		installButton = installBtn

		let installRow = NSStackView(views: [pathPopUp, installBtn])
		installRow.orientation = .horizontal
		installRow.spacing = 8

		let statusLabel = NSTextField(labelWithString: "")
		statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		statusLabel.textColor = .secondaryLabelColor
		installStatusLabel = statusLabel

		// rmate section
		let rmateTitle = makeLabel("rmate:")

		let rmateCheckbox = NSButton(
			checkboxWithTitle: "Enable rmate server",
			target: self, action: #selector(toggleRMate(_:)),
		)
		rmateCheckbox.state = isRMateEnabled ? .on : .off

		let listenLabel = makeLabel("Listen on:")
		let listenPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
		listenPopUp.addItem(withTitle: "localhost")
		listenPopUp.addItem(withTitle: "all interfaces")
		listenPopUp.selectItem(at: rmateListen == .remote ? 1 : 0)
		listenPopUp.target = self
		listenPopUp.action = #selector(listenChanged(_:))

		let portLabel = makeLabel("Port:")
		let portField = NSTextField()
		portField.stringValue = rmatePort
		portField.placeholderString = "52698"
		portField.target = self
		portField.action = #selector(portChanged(_:))

		let rmateHelpText =
			NSTextField(labelWithString: "Use rmate to open files from a remote server via SSH tunneling.")
		rmateHelpText.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		rmateHelpText.textColor = .secondaryLabelColor

		let rows: [[NSView]] = [
			[mateTitle, installRow],
			[makeLabel(""), statusLabel],
			[separator(), separator()],
			[rmateTitle, rmateCheckbox],
			[listenLabel, listenPopUp],
			[portLabel, portField],
			[makeLabel(""), rmateHelpText],
		]

		let grid = NSGridView(views: rows)
		grid.rowAlignment = .firstBaseline
		grid.rowSpacing = 8
		grid.column(at: 0).width = 200
		grid.column(at: 0).xPlacement = .trailing

		return grid
	}

	// MARK: - Actions

	@objc private func pathChanged(_ sender: NSPopUpButton) {
		if sender.selectedItem?.title == "Other…" {
			let panel = NSSavePanel()
			panel.nameFieldStringValue = "mate"
			panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
			panel.beginSheetModal(for: view.window!) { response in
				if response == .OK, let url = panel.url {
					self.mateInstallPath = url.path
					sender.insertItem(withTitle: url.path, at: 0)
					sender.selectItem(at: 0)
				}
			}
		} else if let title = sender.selectedItem?.title {
			let expanded = (title as NSString).expandingTildeInPath
			mateInstallPath = expanded
		}
		updateInstallStatus()
	}

	@objc private func installMate(_: Any?) {
		let install = !isMateInstalled
		onMateInstall?(mateInstallPath, install)
		updateInstallStatus()
	}

	@objc private func toggleRMate(_ sender: NSButton) {
		isRMateEnabled = sender.state == .on
	}

	@objc private func listenChanged(_ sender: NSPopUpButton) {
		rmateListen = sender.indexOfSelectedItem == 1 ? .remote : .localhost
	}

	@objc private func portChanged(_ sender: NSTextField) {
		rmatePort = sender.stringValue
	}

	// MARK: - Install Status

	/// Update the install status label and button title.
	public func updateInstallStatus() {
		if isMateInstalled {
			installStatusLabel?.stringValue = "mate is installed at \(mateInstallPath)"
			installButton?.title = "Uninstall"
		} else {
			installStatusLabel?.stringValue = "mate is not installed"
			installButton?.title = "Install"
		}
	}

	private func makeLabel(_ text: String) -> NSTextField {
		let l = NSTextField(labelWithString: text)
		l.alignment = .right
		return l
	}

	private func separator() -> NSBox {
		let sep = NSBox()
		sep.boxType = .separator
		return sep
	}
}
#endif
