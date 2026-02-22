#if canImport(AppKit)
import AppKit

// MARK: - Auto-Sizing Text Field

/// A text field that grows vertically to fit multi-line content up to a maximum height.
private class AutoSizingTextField: NSTextField {
	var customIntrinsicSize: NSSize = .zero

	override var intrinsicContentSize: NSSize {
		customIntrinsicSize == .zero ? super.intrinsicContentSize : customIntrinsicSize
	}

	func updateIntrinsicHeight(for string: String?) {
		guard let cell = cell?.copy() as? NSTextFieldCell else { return }
		cell.stringValue = string ?? ""

		let boundingWidth = bounds.width > 0 ? bounds.width : 200
		let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: boundingWidth, height: .greatestFiniteMagnitude))
		let height = max(22, min(size.height, 225))

		customIntrinsicSize = NSSize(width: NSView.noIntrinsicMetric, height: height)
		invalidateIntrinsicContentSize()
	}
}

// MARK: - Find Text Field Controller

/// A view controller wrapping a text field with auto-sizing, history popover,
/// and optional syntax highlighting — equivalent to `FFTextFieldViewController`.
///
/// The text field grows vertically as the user types multi-line content and
/// provides a down-arrow history popover from the associated pasteboard history.
@MainActor
public final class FindTextFieldController: NSViewController, NSTextFieldDelegate, Sendable {
	/// The current string value of the text field.
	public var stringValue: String = "" {
		didSet {
			guard stringValue != oldValue else { return }
			if isViewLoaded {
				textField.stringValue = stringValue
				textField.updateIntrinsicHeight(for: stringValue)
			}
			onValueChanged?(stringValue)
		}
	}

	/// Whether the text field currently has focus.
	public private(set) var hasFocus: Bool = false

	/// Callback when the string value changes.
	public var onValueChanged: ((String) -> Void)?

	/// History entries for the down-arrow popover (most recent first).
	public var history: [String] = []

	// MARK: - Private

	private let textField = AutoSizingTextField()
	private var popover: NSPopover?

	// MARK: - Lifecycle

	override public func loadView() {
		textField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))
		textField.delegate = self
		textField.cell?.wraps = true
		textField.translatesAutoresizingMaskIntoConstraints = false

		view = textField
	}

	override public func viewDidAppear() {
		super.viewDidAppear()
		textField.stringValue = stringValue
		textField.updateIntrinsicHeight(for: stringValue)
	}

	// MARK: - Public API

	/// Show the history popover below the text field.
	public func showHistory() {
		guard !history.isEmpty else { return }

		if popover?.isShown == true {
			popover?.close()
			popover = nil
			return
		}

		let tableVC = HistoryPopoverViewController(
			entries: history,
			onSelect: { [weak self] entry in
				self?.popover?.close()
				self?.popover = nil
				self?.stringValue = entry
			},
		)

		let pop = NSPopover()
		pop.behavior = .transient
		pop.contentViewController = tableVC
		pop.show(relativeTo: .zero, of: textField, preferredEdge: .maxY)
		popover = pop
	}

	/// Show an informational popover (e.g. regex error message).
	public func showInfoPopover(message: String) {
		if let existing = popover, existing.isShown {
			existing.close()
		}

		let label = NSTextField(labelWithString: message)
		label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
		label.translatesAutoresizingMaskIntoConstraints = false

		let vc = NSViewController()
		vc.view = label

		let pop = NSPopover()
		pop.behavior = .transient
		pop.contentViewController = vc
		pop.show(relativeTo: .zero, of: textField, preferredEdge: .maxY)
		popover = pop
	}

	// MARK: - NSTextFieldDelegate

	public func controlTextDidChange(_: Notification) {
		let newValue = textField.stringValue
		textField.updateIntrinsicHeight(for: newValue)
		if stringValue != newValue {
			stringValue = newValue
		}
	}

	public func controlTextDidEndEditing(_: Notification) {
		let newValue = textField.stringValue
		if stringValue != newValue {
			stringValue = newValue
		}
	}

	public func control(_: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		if selector == #selector(NSResponder.moveDown(_:)) {
			let text = textView.string
			let lastNewline = text.range(of: "\n", options: .backwards)
			let selectedRange = textView.selectedRange()

			let isAtEnd: Bool
			if let nlRange = lastNewline {
				let nlOffset = text.distance(from: text.startIndex, to: nlRange.lowerBound)
				isAtEnd = nlOffset < selectedRange.upperBound
			} else {
				isAtEnd = true
			}

			if isAtEnd {
				showHistory()
				return true
			}
		}
		return false
	}
}

// MARK: - History Popover

/// A simple table view controller for the history popover.
@MainActor
private final class HistoryPopoverViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	private let entries: [String]
	private let onSelect: (String) -> Void
	private let tableView = NSTableView()

	init(entries: [String], onSelect: @escaping (String) -> Void) {
		self.entries = entries
		self.onSelect = onSelect
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError()
	}

	override func loadView() {
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
		column.width = 280
		tableView.addTableColumn(column)
		tableView.headerView = nil
		tableView.dataSource = self
		tableView.delegate = self
		tableView.target = self
		tableView.doubleAction = #selector(didDoubleClick(_:))
		tableView.rowHeight = 20

		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		let height = min(CGFloat(entries.count) * 20 + 4, 200)
		NSLayoutConstraint.activate([
			scrollView.widthAnchor.constraint(equalToConstant: 300),
			scrollView.heightAnchor.constraint(equalToConstant: height),
		])

		view = scrollView
	}

	@objc private func didDoubleClick(_: Any) {
		let row = tableView.clickedRow
		guard row >= 0, row < entries.count else { return }
		onSelect(entries[row])
	}

	func numberOfRows(in _: NSTableView) -> Int {
		entries.count
	}

	func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
		let cell = NSTextField(labelWithString: entries[row])
		cell.lineBreakMode = .byTruncatingTail
		cell.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
		return cell
	}
}
#endif
