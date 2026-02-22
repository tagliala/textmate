#if canImport(AppKit)
import AppKit
import TMCompatibility

// MARK: - Run Command Window Controller

/// A singleton panel that lets the user type an arbitrary shell command,
/// choose an output destination, and execute it against the currently
/// focused document.  Mirrors the original C++ `OakRunCommandWindowController`.
@MainActor
public final class RunCommandWindowController: NSWindowController, NSWindowDelegate {
	// MARK: - Singleton

	public static let shared = RunCommandWindowController()

	// MARK: - Execution Callback

	/// Set by the `DocumentWindowController` that opens the panel.
	/// Called when the user clicks **Execute**.
	public var onExecute: ((_ command: String, _ output: CommandOutput) -> Void)?

	// MARK: - UI Controls

	private let commandLabel = NSTextField(labelWithString: "Command:")
	private let commandComboBox = NSComboBox()
	private let resultLabel = NSTextField(labelWithString: "Result:")
	private let resultPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
	private let executeButton = NSButton(
		title: "Execute",
		target: nil,
		action: #selector(execute(_:)),
	)
	private let cancelButton = NSButton(
		title: "Cancel",
		target: nil,
		action: #selector(cancel(_:)),
	)

	// MARK: - History

	private static let historyKey = "FilterThroughCommandHistory"
	private static let historyMaxSize = 10
	private static let outputTypeKey = "filterOutputType"

	private var commandHistory: [String] {
		get { UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? [] }
		set { UserDefaults.standard.set(newValue, forKey: Self.historyKey) }
	}

	// MARK: - Output Options

	private struct OutputOption {
		let title: String
		let keyEquivalent: String
		let output: CommandOutput
	}

	private let outputOptions: [OutputOption] = [
		OutputOption(title: "Replace Input", keyEquivalent: "1", output: .replaceInput),
		OutputOption(title: "Insert After Input", keyEquivalent: "2", output: .afterInput),
		OutputOption(title: "New Document", keyEquivalent: "3", output: .newWindow),
		OutputOption(title: "Tool Tip", keyEquivalent: "4", output: .toolTip),
	]

	// MARK: - Init

	private init() {
		let panel = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: true,
		)
		panel.title = "Filter Through Command"
		panel.isReleasedWhenClosed = false
		panel.becomesKeyOnlyIfNeeded = false

		super.init(window: panel)
		panel.delegate = self

		setupUI()
		loadHistory()
		loadOutputType()
		updateExecuteButtonState()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - UI Setup

	private func setupUI() {
		guard let contentView = window?.contentView else { return }

		commandLabel.alignment = .right
		commandLabel.translatesAutoresizingMaskIntoConstraints = false

		commandComboBox.isEditable = true
		commandComboBox.completes = false
		commandComboBox.translatesAutoresizingMaskIntoConstraints = false
		commandComboBox.target = self
		commandComboBox.action = #selector(comboBoxAction(_:))

		resultLabel.alignment = .right
		resultLabel.translatesAutoresizingMaskIntoConstraints = false

		resultPopUpButton.translatesAutoresizingMaskIntoConstraints = false
		let menu = resultPopUpButton.menu ?? NSMenu()
		menu.removeAllItems()
		for option in outputOptions {
			let item = NSMenuItem(
				title: option.title,
				action: #selector(takeOutputTypeFrom(_:)),
				keyEquivalent: option.keyEquivalent,
			)
			item.tag = outputOptions.firstIndex(where: { $0.output == option.output }) ?? 0
			item.target = self
			menu.addItem(item)
		}
		resultPopUpButton.menu = menu

		executeButton.translatesAutoresizingMaskIntoConstraints = false
		executeButton.target = self
		executeButton.action = #selector(execute(_:))
		executeButton.keyEquivalent = "\r"

		cancelButton.translatesAutoresizingMaskIntoConstraints = false
		cancelButton.target = self
		cancelButton.action = #selector(cancel(_:))
		cancelButton.keyEquivalent = "\u{1b}" // Escape

		let views: [NSView] = [
			commandLabel, commandComboBox,
			resultLabel, resultPopUpButton,
			executeButton, cancelButton,
		]
		for view in views {
			contentView.addSubview(view)
		}

		NSLayoutConstraint.activate([
			// Command row
			commandLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			commandLabel.firstBaselineAnchor.constraint(equalTo: commandComboBox.firstBaselineAnchor),
			commandLabel.widthAnchor.constraint(equalToConstant: 80),

			commandComboBox.leadingAnchor.constraint(equalTo: commandLabel.trailingAnchor, constant: 8),
			commandComboBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			commandComboBox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
			commandComboBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),

			// Result row
			resultLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			resultLabel.firstBaselineAnchor.constraint(equalTo: resultPopUpButton.firstBaselineAnchor),
			resultLabel.widthAnchor.constraint(equalTo: commandLabel.widthAnchor),

			resultPopUpButton.leadingAnchor.constraint(equalTo: resultLabel.trailingAnchor, constant: 8),
			resultPopUpButton.topAnchor.constraint(equalTo: commandComboBox.bottomAnchor, constant: 12),

			// Buttons
			executeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			executeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

			cancelButton.trailingAnchor.constraint(equalTo: executeButton.leadingAnchor, constant: -8),
			cancelButton.firstBaselineAnchor.constraint(equalTo: executeButton.firstBaselineAnchor),

			resultPopUpButton.bottomAnchor.constraint(lessThanOrEqualTo: executeButton.topAnchor, constant: -12),
		])

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(commandTextChanged(_:)),
			name: NSControl.textDidChangeNotification,
			object: commandComboBox,
		)
	}

	// MARK: - History Management

	private func loadHistory() {
		let history = commandHistory
		commandComboBox.removeAllItems()
		commandComboBox.addItems(withObjectValues: history)
		if let first = history.first {
			commandComboBox.stringValue = first
		}
	}

	private func pushToHistory(_ command: String) {
		var history = commandHistory
		history.removeAll { $0 == command }
		history.insert(command, at: 0)
		if history.count > Self.historyMaxSize {
			history = Array(history.prefix(Self.historyMaxSize))
		}
		commandHistory = history
		loadHistory()
	}

	// MARK: - Output Type Persistence

	private var selectedOutput: CommandOutput {
		let tag = resultPopUpButton.selectedTag()
		guard tag >= 0, tag < outputOptions.count else { return .replaceInput }
		return outputOptions[tag].output
	}

	private func loadOutputType() {
		let raw = UserDefaults.standard.integer(forKey: Self.outputTypeKey)
		if raw >= 0, raw < outputOptions.count {
			resultPopUpButton.selectItem(withTag: raw)
		}
	}

	private func saveOutputType() {
		UserDefaults.standard.set(resultPopUpButton.selectedTag(), forKey: Self.outputTypeKey)
	}

	// MARK: - Actions

	@objc private func execute(_: Any?) {
		let command = commandComboBox.stringValue
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !command.isEmpty else { return }

		pushToHistory(command)
		saveOutputType()

		onExecute?(command, selectedOutput)
		close()
	}

	@objc private func cancel(_: Any?) {
		close()
	}

	@objc private func takeOutputTypeFrom(_ sender: NSMenuItem) {
		resultPopUpButton.selectItem(withTag: sender.tag)
		saveOutputType()
	}

	@objc private func comboBoxAction(_: Any?) {
		updateExecuteButtonState()
	}

	@objc private func commandTextChanged(_: Notification) {
		updateExecuteButtonState()
	}

	private func updateExecuteButtonState() {
		let text = commandComboBox.stringValue
			.trimmingCharacters(in: .whitespacesAndNewlines)
		executeButton.isEnabled = !text.isEmpty
	}

	// MARK: - Public Interface

	/// Shows the panel, optionally near the given window.
	public func showPanel(near parentWindow: NSWindow? = nil) {
		if let parent = parentWindow, let panel = window {
			let frame = parent.frame
			let panelFrame = panel.frame
			let x = frame.midX - panelFrame.width / 2
			let y = frame.maxY - panelFrame.height - 40
			panel.setFrameOrigin(NSPoint(x: x, y: y))
		}
		showWindow(nil)
		window?.makeFirstResponder(commandComboBox)
	}

	/// The current command string (for testing).
	public var commandString: String {
		get { commandComboBox.stringValue }
		set { commandComboBox.stringValue = newValue }
	}

	/// The selected output destination (for testing).
	public var outputDestination: CommandOutput {
		selectedOutput
	}

	// MARK: - NSWindowDelegate

	public func windowWillClose(_: Notification) {
		onExecute = nil
	}
}
#endif
