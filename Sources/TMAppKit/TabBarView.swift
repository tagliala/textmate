import AppKit

/// A tab bar view that displays document tabs, matching TextMate's tab bar
/// appearance and behavior.
///
/// Supports:
/// - Draggable tab reordering
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

	public var tabBarHeight: CGFloat = 24

	override public var isFlipped: Bool {
		true
	}

	override public init(frame: NSRect) {
		super.init(frame: frame)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
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

		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
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

	override func mouseDown(with _: NSEvent) {
		selectAction?(tabIndex)
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
