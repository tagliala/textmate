import AppKit

/// Delegate protocol for live search bar actions.
@MainActor
public protocol LiveSearchBarViewDelegate: AnyObject {
	/// Called when the search string changes.
	func liveSearchBar(_ bar: LiveSearchBarView, searchStringDidChange text: String)

	/// Called when the user presses Return (accept match).
	func liveSearchBarDidAccept(_ bar: LiveSearchBarView)

	/// Called when the user presses Escape (cancel search).
	func liveSearchBarDidCancel(_ bar: LiveSearchBarView)

	/// Called when ⌘G or next match is requested.
	func liveSearchBarDidRequestNext(_ bar: LiveSearchBarView)

	/// Called when ⇧⌘G or previous match is requested.
	func liveSearchBarDidRequestPrevious(_ bar: LiveSearchBarView)
}

/// A compact search bar displayed inline at the bottom of the editor area.
///
/// This is the Swift counterpart of the C++ `LiveSearchView` in
/// `Frameworks/OakTextView/src/LiveSearchView.mm`. It provides a text field
/// and two checkboxes (Ignore Case, Wrap Around) for incremental search.
///
/// The bar occupies a thin horizontal strip and is designed to be shown/hidden
/// dynamically as an auxiliary view at the top of the editor scroll view.
@MainActor
public class LiveSearchBarView: NSView {
	// MARK: - Public Properties

	/// The delegate receiving search events.
	public weak var delegate: LiveSearchBarViewDelegate?

	/// The current search string.
	public var searchString: String {
		get { textField.stringValue }
		set { textField.stringValue = newValue }
	}

	/// Whether case is ignored (bound to user defaults).
	public var ignoreCase: Bool {
		get { ignoreCaseCheckbox.state == .on }
		set { ignoreCaseCheckbox.state = newValue ? .on : .off }
	}

	/// Whether to wrap around (bound to user defaults).
	public var wrapAround: Bool {
		get { wrapAroundCheckbox.state == .on }
		set { wrapAroundCheckbox.state = newValue ? .on : .off }
	}

	/// Whether the search has no results (tints the text field red).
	public var hasNoResults: Bool = false {
		didSet { updateTextFieldAppearance() }
	}

	/// The preferred height for the search bar.
	public static let barHeight: CGFloat = 28

	// MARK: - Subviews

	private let textField = NSTextField()
	private let ignoreCaseCheckbox = NSButton(
		checkboxWithTitle: "Ignore Case",
		target: nil,
		action: nil,
	)
	private let wrapAroundCheckbox = NSButton(
		checkboxWithTitle: "Wrap Around",
		target: nil,
		action: nil,
	)
	private let divider: NSView = {
		let v = NSBox()
		v.boxType = .separator
		return v
	}()

	// MARK: - Init

	override public init(frame: NSRect) {
		super.init(frame: frame)
		setupViews()
		setupDefaults()
		setupConstraints()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - First Responder

	/// Activates the search bar by focusing the text field.
	public func activate() {
		window?.makeFirstResponder(textField)
	}

	/// Deactivates the search bar.
	public func deactivate() {
		textField.stringValue = ""
		hasNoResults = false
	}

	// MARK: - Setup

	private func setupViews() {
		wantsLayer = true

		textField.focusRingType = .none
		textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		textField.placeholderString = "Search"
		textField.delegate = self
		textField.target = self
		textField.action = #selector(textFieldAction(_:))

		ignoreCaseCheckbox.controlSize = .small
		ignoreCaseCheckbox.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		ignoreCaseCheckbox.target = self
		ignoreCaseCheckbox.action = #selector(checkboxChanged(_:))

		wrapAroundCheckbox.controlSize = .small
		wrapAroundCheckbox.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		wrapAroundCheckbox.target = self
		wrapAroundCheckbox.action = #selector(checkboxChanged(_:))

		addSubview(divider)
		addSubview(textField)
		addSubview(ignoreCaseCheckbox)
		addSubview(wrapAroundCheckbox)
	}

	private func setupDefaults() {
		let defaults = UserDefaults.standard
		defaults.register(defaults: [
			"incrementalSearchIgnoreCase": true,
			"incrementalSearchWrapAround": false,
		])
		ignoreCaseCheckbox.state = defaults.bool(forKey: "incrementalSearchIgnoreCase") ? .on : .off
		wrapAroundCheckbox.state = defaults.bool(forKey: "incrementalSearchWrapAround") ? .on : .off
	}

	private func setupConstraints() {
		for view in [divider, textField, ignoreCaseCheckbox, wrapAroundCheckbox] {
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		NSLayoutConstraint.activate([
			// Divider line at the top
			divider.topAnchor.constraint(equalTo: topAnchor),
			divider.leadingAnchor.constraint(equalTo: leadingAnchor),
			divider.trailingAnchor.constraint(equalTo: trailingAnchor),
			divider.heightAnchor.constraint(equalToConstant: 1),

			// Text field
			textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			textField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),

			// Checkboxes in a row, right-aligned
			ignoreCaseCheckbox.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
			ignoreCaseCheckbox.centerYAnchor.constraint(equalTo: centerYAnchor),

			wrapAroundCheckbox.leadingAnchor.constraint(equalTo: ignoreCaseCheckbox.trailingAnchor, constant: 8),
			wrapAroundCheckbox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			wrapAroundCheckbox.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	private func updateTextFieldAppearance() {
		if hasNoResults {
			textField.textColor = .systemRed
		} else {
			textField.textColor = .controlTextColor
		}
	}

	// MARK: - Actions

	@objc private func textFieldAction(_: Any) {
		// Return key pressed in the text field → accept.
		delegate?.liveSearchBarDidAccept(self)
	}

	@objc private func checkboxChanged(_ sender: NSButton) {
		let key = if sender === ignoreCaseCheckbox {
			"incrementalSearchIgnoreCase"
		} else {
			"incrementalSearchWrapAround"
		}
		UserDefaults.standard.set(sender.state == .on, forKey: key)

		// Re-trigger the search with the new option.
		delegate?.liveSearchBar(self, searchStringDidChange: searchString)
	}

	// MARK: - Key Handling

	override public func cancelOperation(_: Any?) {
		delegate?.liveSearchBarDidCancel(self)
	}

	override public func keyDown(with event: NSEvent) {
		if event.modifierFlags.contains(.command) {
			switch event.charactersIgnoringModifiers {
			case "g":
				if event.modifierFlags.contains(.shift) {
					delegate?.liveSearchBarDidRequestPrevious(self)
				} else {
					delegate?.liveSearchBarDidRequestNext(self)
				}
				return
			default:
				break
			}
		}
		super.keyDown(with: event)
	}
}

// MARK: - NSTextFieldDelegate

extension LiveSearchBarView: NSTextFieldDelegate {
	public func controlTextDidChange(_ notification: Notification) {
		guard notification.object as AnyObject? === textField else { return }
		delegate?.liveSearchBar(self, searchStringDidChange: textField.stringValue)
	}

	/// Handle Escape (cancel), ⌘G (next), ⇧⌘G (previous) while the text
	/// field is first responder.
	public func control(
		_: NSControl,
		textView _: NSTextView,
		doCommandBy commandSelector: Selector,
	) -> Bool {
		switch commandSelector {
		case #selector(NSResponder.cancelOperation(_:)):
			delegate?.liveSearchBarDidCancel(self)
			return true
		default:
			return false
		}
	}
}
