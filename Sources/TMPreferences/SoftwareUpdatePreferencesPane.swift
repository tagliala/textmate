#if canImport(AppKit)
import AppKit

/// Software Update preferences pane — update channel, crash reporting.
///
/// Port of `Frameworks/Preferences/src/SoftwareUpdatePreferences.mm`.
@MainActor
public final class SoftwareUpdatePreferencesPane: PreferencesPane {
	override public var toolbarItemImage: NSImage? {
		NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Software Update")
	}

	override public var toolbarItemLabel: String {
		"Software Update"
	}

	override public var paneIdentifier: String {
		"SoftwareUpdate"
	}

	/// Callback to trigger a manual update check.
	public var onCheckNow: (() -> Void)?

	/// Whether an update check is currently in progress.
	public var isChecking: Bool = false {
		didSet { updateCheckNowButton() }
	}

	// MARK: - UI

	private var checkNowButton: NSButton?
	private var lastCheckLabel: NSTextField?
	private var updateTimer: Timer?

	// MARK: - View Loading

	override public func loadView() {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 300))

		let grid = buildGrid()
		grid.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(grid)

		NSLayoutConstraint.activate([
			grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
			grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
		])

		view = container

		// Update the "last check" label periodically
		updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
			Task { @MainActor in
				self?.updateLastCheckLabel()
			}
		}
		updateLastCheckLabel()
	}

	deinit {
		MainActor.assumeIsolated {
			updateTimer?.invalidate()
		}
	}

	private func buildGrid() -> NSGridView {
		// Watch for updates
		let watchCheckbox = NSButton(
			checkboxWithTitle: "Watch for:",
			target: self, action: #selector(toggleWatch(_:)),
		)
		watchCheckbox.state = !UserDefaults.standard.bool(forKey: PreferencesKeys.disableSoftwareUpdate) ? .on : .off

		let channelPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
		channelPopUp.addItem(withTitle: "Normal Releases")
		channelPopUp.addItem(withTitle: "Pre-releases")
		let channel = UserDefaults.standard.string(forKey: PreferencesKeys.softwareUpdateChannel) ?? "release"
		channelPopUp.selectItem(at: channel == "prerelease" ? 1 : 0)
		channelPopUp.target = self
		channelPopUp.action = #selector(channelChanged(_:))

		let watchRow = NSStackView(views: [watchCheckbox, channelPopUp])
		watchRow.orientation = .horizontal
		watchRow.spacing = 8

		// Ask before downloading
		let askCheckbox = NSButton(
			checkboxWithTitle: "Ask before downloading updates",
			target: self, action: #selector(toggleAsk(_:)),
		)
		askCheckbox.state = UserDefaults.standard.bool(forKey: PreferencesKeys.askBeforeUpdating) ? .on : .off

		// Last check
		let lastCheckTitle = NSTextField(labelWithString: "Last check:")
		lastCheckTitle.alignment = .right
		let lastCheck = NSTextField(labelWithString: lastCheckDescription())
		lastCheck.textColor = .secondaryLabelColor
		lastCheckLabel = lastCheck

		// Check Now button
		let checkBtn = NSButton(title: "Check Now", target: self, action: #selector(checkNow(_:)))
		checkNowButton = checkBtn

		// Crash reporting
		let crashCheckbox = NSButton(
			checkboxWithTitle: "Submit crash reports to MacroMates",
			target: self, action: #selector(toggleCrashReporting(_:)),
		)
		crashCheckbox.state = !UserDefaults.standard.bool(forKey: PreferencesKeys.disableCrashReporting) ? .on : .off

		let contactLabel = NSTextField(labelWithString: "Contact:")
		contactLabel.alignment = .right
		let contactField = NSTextField()
		contactField.stringValue = UserDefaults.standard.string(forKey: PreferencesKeys.crashReportsContactInfo)
			?? NSFullUserName()
		contactField.target = self
		contactField.action = #selector(contactChanged(_:))

		let rows: [[NSView]] = [
			[label(""), watchRow],
			[label(""), askCheckbox],
			[separator(), separator()],
			[lastCheckTitle, lastCheck],
			[label(""), checkBtn],
			[separator(), separator()],
			[label(""), crashCheckbox],
			[contactLabel, contactField],
		]

		let grid = NSGridView(views: rows)
		grid.rowAlignment = .firstBaseline
		grid.rowSpacing = 8
		grid.column(at: 0).width = 200
		grid.column(at: 0).xPlacement = .trailing

		return grid
	}

	// MARK: - Actions

	@objc private func toggleWatch(_ sender: NSButton) {
		UserDefaults.standard.set(sender.state != .on, forKey: PreferencesKeys.disableSoftwareUpdate)
	}

	@objc private func channelChanged(_ sender: NSPopUpButton) {
		let channel = sender.indexOfSelectedItem == 1 ? "prerelease" : "release"
		UserDefaults.standard.set(channel, forKey: PreferencesKeys.softwareUpdateChannel)
	}

	@objc private func toggleAsk(_ sender: NSButton) {
		UserDefaults.standard.set(sender.state == .on, forKey: PreferencesKeys.askBeforeUpdating)
	}

	@objc private func checkNow(_: Any?) {
		onCheckNow?()
	}

	@objc private func toggleCrashReporting(_ sender: NSButton) {
		UserDefaults.standard.set(sender.state != .on, forKey: PreferencesKeys.disableCrashReporting)
	}

	@objc private func contactChanged(_ sender: NSTextField) {
		UserDefaults.standard.set(sender.stringValue, forKey: PreferencesKeys.crashReportsContactInfo)
	}

	// MARK: - Last Check Description

	private func updateLastCheckLabel() {
		lastCheckLabel?.stringValue = lastCheckDescription()
	}

	/// Compute a relative date string for the last update check.
	public func lastCheckDescription() -> String {
		guard let date = UserDefaults.standard.object(forKey: PreferencesKeys.lastSoftwareUpdateCheck) as? Date else {
			return "Never"
		}
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter.localizedString(for: date, relativeTo: Date())
	}

	private func updateCheckNowButton() {
		checkNowButton?.isEnabled = !isChecking
		checkNowButton?.title = isChecking ? "Checking…" : "Check Now"
	}

	// MARK: - Helpers

	private func label(_ text: String) -> NSTextField {
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
