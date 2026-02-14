import AppKit

/// A tab bar view that displays document tabs, matching TextMate's tab bar
/// appearance and behavior.
///
/// Supports:
/// - Drag-to-reorder tabs
/// - Close buttons on each tab
/// - Overflow menu when tabs exceed visible width
/// - ⌘1–⌘8 to switch to a tab by index, ⌘9 for the last tab
@MainActor
public class TabBarView: NSView {
	public struct Tab: Equatable, Sendable {
		public let identifier: String
		public let title: String
		public let isModified: Bool

		public init(
			identifier: String,
			title: String,
			isModified: Bool = false,
		) {
			self.identifier = identifier
			self.title = title
			self.isModified = isModified
		}
	}

	public weak var delegate: TabBarViewDelegate?

	public private(set) var tabs: [Tab] = []
	public private(set) var selectedIndex: Int = 0

	private var tabButtons: [TabButton] = []
	private let scrollView = NSScrollView()
	private let stackView = NSStackView()
	private let overflowButton = NSButton()

	/// The drag pasteboard type used for tab reordering.
	static let tabDragType = NSPasteboard.PasteboardType("com.macromates.textmate.tab")

	public var tabBarHeight: CGFloat = 24

	override public var isFlipped: Bool {
		true
	}

	override public init(frame: NSRect) {
		super.init(frame: frame)
		setupViews()
		registerForDraggedTypes([Self.tabDragType])
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	override public func layout() {
		super.layout()
		updateOverflowButton()
	}

	// MARK: - Public API

	public func setTabs(_ newTabs: [Tab], selectedIndex: Int) {
		tabs = newTabs
		self.selectedIndex = max(0, min(selectedIndex, newTabs.count - 1))
		rebuildTabButtons()
	}

	public func selectTab(at index: Int) {
		guard index >= 0, index < tabs.count else { return }
		selectedIndex = index
		updateSelection()
		delegate?.tabBarView(self, didSelectTabAt: index)
	}

	// MARK: - Drag & Drop (Destination)

	override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
		guard sender.draggingPasteboard.availableType(from: [Self.tabDragType]) != nil else {
			return []
		}
		return .move
	}

	override public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
		guard sender.draggingPasteboard.availableType(from: [Self.tabDragType]) != nil else {
			return []
		}
		return .move
	}

	override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		guard let data = sender.draggingPasteboard.data(forType: Self.tabDragType),
		      let fromIndex = try? JSONDecoder().decode(Int.self, from: data)
		else {
			return false
		}

		let dropPoint = convert(sender.draggingLocation, from: nil)
		var toIndex = tabs.count - 1

		for (i, button) in tabButtons.enumerated() {
			let mid = button.frame.midX
			if dropPoint.x < mid {
				toIndex = i
				break
			}
		}

		guard fromIndex != toIndex, fromIndex >= 0, fromIndex < tabs.count else {
			return false
		}

		// Reorder the model
		let tab = tabs.remove(at: fromIndex)
		let insertAt = toIndex > fromIndex ? toIndex - 1 : toIndex
		let clampedInsert = max(0, min(insertAt, tabs.count))
		tabs.insert(tab, at: clampedInsert)

		// Update selected index to follow the dragged tab
		if fromIndex == selectedIndex {
			selectedIndex = clampedInsert
		} else if fromIndex < selectedIndex, clampedInsert >= selectedIndex {
			selectedIndex -= 1
		} else if fromIndex > selectedIndex, clampedInsert <= selectedIndex {
			selectedIndex += 1
		}

		rebuildTabButtons()
		delegate?.tabBarView(self, didReorderTabFrom: fromIndex, to: clampedInsert)
		return true
	}

	// MARK: - Private

	private func setupViews() {
		wantsLayer = true

		stackView.orientation = .horizontal
		stackView.spacing = 0
		stackView.distribution = .fill

		scrollView.documentView = stackView
		scrollView.hasHorizontalScroller = false
		scrollView.hasVerticalScroller = false
		scrollView.drawsBackground = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scrollView)

		// Overflow button — shown when tabs exceed visible width
		overflowButton.bezelStyle = .inline
		overflowButton.isBordered = false
		overflowButton.title = "»"
		overflowButton.font = .systemFont(ofSize: 13, weight: .medium)
		overflowButton.target = self
		overflowButton.action = #selector(showOverflowMenu(_:))
		overflowButton.translatesAutoresizingMaskIntoConstraints = false
		overflowButton.isHidden = true
		overflowButton.toolTip = String(localized: "Show hidden tabs", comment: "Tab bar overflow button tooltip")
		addSubview(overflowButton)

		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: overflowButton.leadingAnchor),
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

			overflowButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
			overflowButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			overflowButton.widthAnchor.constraint(equalToConstant: 24),
			overflowButton.heightAnchor.constraint(equalToConstant: 20),
		])
	}

	/// Show/hide the overflow button based on whether tabs exceed visible width.
	private func updateOverflowButton() {
		let contentWidth = stackView.fittingSize.width
		let visibleWidth = scrollView.bounds.width
		overflowButton.isHidden = contentWidth <= visibleWidth
	}

	@objc private func showOverflowMenu(_: Any?) {
		let menu = NSMenu()
		let visibleWidth = scrollView.bounds.width
		var accumulatedWidth: CGFloat = 0

		for (index, tab) in tabs.enumerated() {
			let buttonWidth = tabButtons.indices.contains(index) ? tabButtons[index].bounds.width : 100
			accumulatedWidth += buttonWidth

			// Only show tabs that are partially or fully hidden
			if accumulatedWidth > visibleWidth {
				let item = NSMenuItem(title: tab.title, action: #selector(overflowTabSelected(_:)), keyEquivalent: "")
				item.target = self
				item.tag = index
				if index == selectedIndex {
					item.state = .on
				}
				menu.addItem(item)
			}
		}

		if !menu.items.isEmpty {
			menu.popUp(
				positioning: nil,
				at: NSPoint(x: 0, y: overflowButton.bounds.height),
				in: overflowButton,
			)
		}
	}

	@objc private func overflowTabSelected(_ sender: NSMenuItem) {
		selectTab(at: sender.tag)
	}

	private func rebuildTabButtons() {
		tabButtons.forEach { $0.removeFromSuperview() }
		tabButtons.removeAll()

		for (index, tab) in tabs.enumerated() {
			let button = TabButton(title: tab.title, isModified: tab.isModified)
			button.tabIndex = index
			button.selectAction = { [weak self] idx in
				self?.selectTab(at: idx)
			}
			button.closeAction = { [weak self] in
				self?.delegate?.tabBarView(self!, didCloseTabAt: index)
			}
			stackView.addArrangedSubview(button)
			tabButtons.append(button)
		}

		updateSelection()
	}

	private func updateSelection() {
		for (index, button) in tabButtons.enumerated() {
			button.isSelected = index == selectedIndex
		}
	}
}

/// Delegate for tab bar events.
@MainActor
public protocol TabBarViewDelegate: AnyObject {
	func tabBarView(_ tabBarView: TabBarView, didSelectTabAt index: Int)
	func tabBarView(_ tabBarView: TabBarView, didCloseTabAt index: Int)
	func tabBarView(_ tabBarView: TabBarView, didReorderTabFrom fromIndex: Int, to toIndex: Int)
}

/// Default no-op implementations.
public extension TabBarViewDelegate {
	func tabBarView(_: TabBarView, didReorderTabFrom _: Int, to _: Int) {}
}

// MARK: - TabButton

@MainActor
private class TabButton: NSView {
	let titleLabel = NSTextField(labelWithString: "")
	let closeButton = NSButton()
	var closeAction: (() -> Void)?
	var selectAction: ((Int) -> Void)?
	var tabIndex = 0
	var isSelected = false {
		didSet { needsDisplay = true }
	}

	override var isFlipped: Bool {
		true
	}

	init(title: String, isModified: Bool) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false

		titleLabel.stringValue = isModified ? "● \(title)" : title
		titleLabel.font = .systemFont(ofSize: 11)
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(titleLabel)

		closeButton.bezelStyle = .inline
		closeButton.isBordered = false
		closeButton.image = NSImage(
			systemSymbolName: "xmark",
			accessibilityDescription: String(localized: "Close tab", comment: "Tab close button accessibility"),
		)
		closeButton.imageScaling = .scaleProportionallyDown
		closeButton.target = self
		closeButton.action = #selector(closeClicked)
		closeButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(closeButton)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 24),
			widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
			widthAnchor.constraint(lessThanOrEqualToConstant: 200),

			closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
			closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			closeButton.widthAnchor.constraint(equalToConstant: 14),
			closeButton.heightAnchor.constraint(equalToConstant: 14),

			titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	@objc private func closeClicked() {
		closeAction?()
	}

	override func mouseDown(with event: NSEvent) {
		selectAction?(tabIndex)
		// Start drag tracking — if the mouse moves more than 3px, begin drag
		dragStartLocation = convert(event.locationInWindow, from: nil)
	}

	private var dragStartLocation: NSPoint = .zero

	override func mouseDragged(with event: NSEvent) {
		let current = convert(event.locationInWindow, from: nil)
		let dx = abs(current.x - dragStartLocation.x)
		let dy = abs(current.y - dragStartLocation.y)
		guard dx > 3 || dy > 3 else { return }

		let pasteboardItem = NSPasteboardItem()
		if let data = try? JSONEncoder().encode(tabIndex) {
			pasteboardItem.setData(data, forType: TabBarView.tabDragType)
		}

		let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
		draggingItem.setDraggingFrame(bounds, contents: snapshot())
		beginDraggingSession(with: [draggingItem], event: event, source: self)
	}

	/// Create a snapshot image of this view for the drag image.
	private func snapshot() -> NSImage {
		let image = NSImage(size: bounds.size)
		image.lockFocus()
		if let ctx = NSGraphicsContext.current?.cgContext {
			layer?.render(in: ctx)
		}
		image.unlockFocus()
		return image
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		if isSelected {
			NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
			bounds.fill()
		}
		titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
	}
}

// MARK: - TabButton + NSDraggingSource

extension TabButton: NSDraggingSource {
	func draggingSession(
		_: NSDraggingSession,
		sourceOperationMaskFor _: NSDraggingContext,
	) -> NSDragOperation {
		.move
	}
}
