import AppKit

// MARK: - Choice Menu Key Action

/// Result of handling a key event in the choice menu.
public enum ChoiceMenuKeyAction: Sendable {
	/// Key was not handled by the menu.
	case unused
	/// Return/Enter was pressed — accept current choice.
	case accept
	/// Tab was pressed — accept and advance.
	case tab
	/// Escape was pressed — cancel completion.
	case cancel
	/// Arrow/Page key moved the selection.
	case movement
}

// MARK: - Choice Menu Panel

/// A floating panel that displays a list of completion choices.
///
/// Port of `OakChoiceMenu` from `Frameworks/OakTextView/src/OakChoiceMenu.mm`.
/// Shown as a borderless child window anchored to a text position in the editor.
/// The panel uses `NSVisualEffectView` for the system menu material appearance.
public final class ChoiceMenuPanel: NSWindowController {
	// MARK: - Properties

	/// The list of completion strings to display.
	public var choices: [String] = [] {
		didSet {
			guard choices != oldValue else { return }
			let oldSelection = selectedChoice
			choiceIndex = nil
			tableView.reloadData()
			if let old = oldSelection {
				choiceIndex = choices.firstIndex(of: old)
			}
			sizeToFit()
		}
	}

	/// The currently selected index, or `nil` for no selection.
	public var choiceIndex: Int? {
		didSet {
			if choiceIndex != oldValue {
				if let idx = choiceIndex {
					tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
					tableView.scrollRowToVisible(idx)
				} else {
					tableView.deselectAll(nil)
				}
			}
		}
	}

	/// The currently selected choice string.
	public var selectedChoice: String? {
		guard let idx = choiceIndex, idx >= 0, idx < choices.count else { return nil }
		return choices[idx]
	}

	/// The font used for displaying choices.
	public var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) {
		didSet { sizeToFit() }
	}

	/// Called when the user accepts a choice (Return or Tab).
	public var onAccept: ((String) -> Void)?

	/// Called when the user cancels (Escape).
	public var onCancel: (() -> Void)?

	private let tableView: NSTableView
	private var anchorPoint: NSPoint = .zero
	private weak var anchorView: NSView?

	/// Maximum number of visible rows before scrolling.
	private let maxVisibleRows = 10

	// MARK: - Initialization

	public init(font: NSFont? = nil) {
		let panel = NSPanel(
			contentRect: .zero,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true,
		)

		tableView = NSTableView(frame: .zero)

		super.init(window: panel)

		if let f = font {
			self.font = f
		}

		configurePanel(panel)
		configureTableView()
		configureContentView(for: panel)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Configuration

	private func configurePanel(_ panel: NSPanel) {
		panel.hasShadow = true
		panel.level = .statusBar
		panel.ignoresMouseEvents = true
		panel.isReleasedWhenClosed = false
		panel.backgroundColor = .clear
	}

	private func configureTableView() {
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("choice"))
		tableView.addTableColumn(column)
		tableView.style = .plain
		tableView.headerView = nil
		tableView.focusRingType = .none
		tableView.allowsMultipleSelection = false
		tableView.dataSource = self
		tableView.delegate = self
		tableView.backgroundColor = .clear
		tableView.reloadData()
	}

	private func configureContentView(for panel: NSPanel) {
		let scrollView = NSScrollView(frame: .zero)
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		scrollView.documentView = tableView
		scrollView.drawsBackground = false
		scrollView.autoresizingMask = [.width, .height]

		let effectView = NSVisualEffectView(frame: .zero)
		effectView.autoresizingMask = [.width, .height]
		effectView.material = .menu
		effectView.blendingMode = .behindWindow

		effectView.addSubview(scrollView)
		scrollView.frame = effectView.bounds

		panel.contentView = effectView
	}

	// MARK: - Sizing

	private func sizeToFit() {
		let padding: CGFloat = 4
		let scrollBarWidth: CGFloat = 15

		// Measure width from content.
		var width: CGFloat = 60
		let attrs: [NSAttributedString.Key: Any] = [.font: font]
		for choice in choices.prefix(256) {
			let size = (choice as NSString).size(withAttributes: attrs)
			width = max(width, padding + size.width + padding)
		}

		// Set row height.
		let sampleSize = ("Xg" as NSString).size(withAttributes: attrs)
		tableView.rowHeight = ceil(sampleSize.height)

		if choices.count > maxVisibleRows {
			width += scrollBarWidth
		}

		let visibleRows = min(choices.count, maxVisibleRows)
		let rowSpacing = tableView.intercellSpacing.height
		let height = CGFloat(visibleRows) * (tableView.rowHeight + rowSpacing)

		// Position: keep top-left at the anchor point.
		guard let win = window else { return }
		let newFrame = NSRect(
			x: win.frame.minX,
			y: win.frame.maxY - height,
			width: min(ceil(width), 400),
			height: height,
		)
		win.setFrame(newFrame, display: true)
	}

	// MARK: - Show / Hide

	/// Show the choice menu anchored at a screen point, attached to a view.
	public func show(at screenPoint: NSPoint, in view: NSView) {
		guard let win = window else { return }
		anchorView = view
		anchorPoint = view.convert(
			view.window?.convertPoint(fromScreen: screenPoint) ?? screenPoint,
			from: nil,
		)

		win.setFrameTopLeftPoint(screenPoint)

		if let idx = choiceIndex {
			tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
		}

		sizeToFit()

		// Observe scroll changes to reposition.
		if let scrollView = view.enclosingScrollView {
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(viewBoundsDidChange(_:)),
				name: NSView.boundsDidChangeNotification,
				object: scrollView.contentView,
			)
		}

		view.window?.addChildWindow(win, ordered: .above)
		win.orderFront(nil)
	}

	/// Dismiss the choice menu.
	public func dismiss() {
		guard let win = window, win.isVisible else { return }
		NotificationCenter.default.removeObserver(
			self,
			name: NSView.boundsDidChangeNotification,
			object: nil,
		)
		win.parent?.removeChildWindow(win)
		win.orderOut(nil)
	}

	override public var isWindowLoaded: Bool {
		true
	}

	/// Whether the menu is currently visible.
	public var isMenuVisible: Bool {
		window?.isVisible ?? false
	}

	@objc private func viewBoundsDidChange(_: Notification) {
		guard let view = anchorView, let viewWindow = view.window else { return }
		let screenPoint = viewWindow.convertPoint(
			toScreen: view.convert(anchorPoint, to: nil),
		)
		window?.setFrameTopLeftPoint(screenPoint)
	}

	// MARK: - Key Event Handling

	/// Process a key event. Returns the action taken.
	public func handleKeyEvent(_ event: NSEvent) -> ChoiceMenuKeyAction {
		guard window != nil else { return .unused }

		// Use the key interpretation system.
		let handler = KeyActionHandler()
		handler.interpretKeyEvents([event])

		switch handler.action {
		case .none:
			return .unused
		case .accept:
			return .accept
		case .tab:
			return .tab
		case .cancel:
			return .cancel
		case let .moveBy(offset):
			moveSelection(by: offset)
			return .movement
		}
	}

	private func moveSelection(by offset: Int) {
		guard !choices.isEmpty else { return }
		let current = choiceIndex ?? (offset > 0 ? -1 : choices.count)
		let newIndex = max(0, min(current + offset, choices.count - 1))
		choiceIndex = newIndex
	}
}

// MARK: - NSTableViewDataSource

extension ChoiceMenuPanel: NSTableViewDataSource {
	public func numberOfRows(in _: NSTableView) -> Int {
		choices.count
	}

	public func tableView(_: NSTableView, objectValueFor _: NSTableColumn?, row: Int) -> Any? {
		choices[row]
	}
}

// MARK: - NSTableViewDelegate

extension ChoiceMenuPanel: NSTableViewDelegate {
	public func tableView(
		_ tableView: NSTableView,
		viewFor _: NSTableColumn?,
		row: Int,
	) -> NSView? {
		let identifier = NSUserInterfaceItemIdentifier("choiceCell")
		let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField
			?? {
				let tf = NSTextField(labelWithString: "")
				tf.identifier = identifier
				tf.lineBreakMode = .byTruncatingTail
				return tf
			}()
		cell.stringValue = choices[row]
		cell.font = font
		return cell
	}
}

// MARK: - Key Action Handler

/// Internal helper that interprets key events and maps standard selectors
/// to completion menu actions.
private final class KeyActionHandler: NSResponder {
	enum Action {
		case none
		case accept
		case tab
		case cancel
		case moveBy(Int)
	}

	var action: Action = .none

	override func doCommand(by selector: Selector) {
		switch selector {
		case #selector(insertNewline(_:)),
		     #selector(insertNewlineIgnoringFieldEditor(_:)):
			action = .accept
		case #selector(insertTab(_:)):
			action = .tab
		case #selector(cancelOperation(_:)):
			action = .cancel
		case #selector(moveUp(_:)),
		     #selector(moveUpAndModifySelection(_:)):
			action = .moveBy(-1)
		case #selector(moveDown(_:)),
		     #selector(moveDownAndModifySelection(_:)):
			action = .moveBy(1)
		case #selector(scrollPageUp(_:)),
		     #selector(pageUp(_:)),
		     #selector(pageUpAndModifySelection(_:)):
			action = .moveBy(-9)
		case #selector(scrollPageDown(_:)),
		     #selector(pageDown(_:)),
		     #selector(pageDownAndModifySelection(_:)):
			action = .moveBy(9)
		case #selector(moveToBeginningOfDocument(_:)),
		     #selector(moveToBeginningOfDocumentAndModifySelection(_:)),
		     #selector(scrollToBeginningOfDocument(_:)):
			action = .moveBy(Int.min / 2)
		case #selector(moveToEndOfDocument(_:)),
		     #selector(moveToEndOfDocumentAndModifySelection(_:)),
		     #selector(scrollToEndOfDocument(_:)):
			action = .moveBy(Int.max / 2)
		default:
			break
		}
	}

	override func insertText(_: Any) {
		// Ignored — text input not consumed by choice menu.
	}
}
