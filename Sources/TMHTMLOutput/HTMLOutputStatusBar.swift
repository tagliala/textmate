#if canImport(AppKit)
import AppKit

/// Delegate protocol for status bar navigation actions.
@MainActor
public protocol HTMLOutputStatusBarDelegate: AnyObject {
	/// Navigate back in history.
	func statusBarGoBack(_ statusBar: HTMLOutputStatusBar)
	/// Navigate forward in history.
	func statusBarGoForward(_ statusBar: HTMLOutputStatusBar)
}

/// Status bar for the HTML output browser view.
///
/// Ports `Frameworks/HTMLOutput/src/browser/HOStatusBar.mm`.
/// Provides back/forward navigation buttons, a status text label,
/// and a progress indicator (determinate bar or indeterminate spinner).
@MainActor
public final class HTMLOutputStatusBar: NSVisualEffectView {
	// MARK: - Delegate

	public weak var delegate: HTMLOutputStatusBarDelegate?

	// MARK: - UI Elements

	private let topDivider: NSView = {
		let box = NSBox()
		box.boxType = .separator
		box.translatesAutoresizingMaskIntoConstraints = false
		return box
	}()

	private let divider: NSView = {
		let box = NSBox()
		box.boxType = .separator
		box.translatesAutoresizingMaskIntoConstraints = false
		return box
	}()

	/// The back navigation button.
	public let goBackButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
			?? NSImage(named: NSImage.goBackTemplateName)
		btn.imagePosition = .imageOnly
		btn.toolTip = "Show the previous page"
		btn.isEnabled = false
		btn.translatesAutoresizingMaskIntoConstraints = false
		return btn
	}()

	/// The forward navigation button.
	public let goForwardButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
			?? NSImage(named: NSImage.goForwardTemplateName)
		btn.imagePosition = .imageOnly
		btn.toolTip = "Show the next page"
		btn.isEnabled = false
		btn.translatesAutoresizingMaskIntoConstraints = false
		return btn
	}()

	/// The status text field showing page load status or link URLs on hover.
	public let statusTextField: NSTextField = {
		let field = NSTextField(labelWithString: "")
		field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		field.lineBreakMode = .byTruncatingMiddle
		field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		field.translatesAutoresizingMaskIntoConstraints = false
		return field
	}()

	/// Determinate progress indicator.
	private let progressIndicator: NSProgressIndicator = {
		let indicator = NSProgressIndicator()
		indicator.controlSize = .small
		indicator.maxValue = 1.0
		indicator.isIndeterminate = false
		indicator.isDisplayedWhenStopped = false
		if #unavailable(macOS 14.0) {
			indicator.isBezeled = false
		}
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	/// Indeterminate spinner.
	private let spinner: NSProgressIndicator = {
		let indicator = NSProgressIndicator()
		indicator.controlSize = .small
		indicator.style = .spinning
		indicator.isDisplayedWhenStopped = false
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	// MARK: - State

	/// Whether to show the indeterminate spinner vs the determinate progress bar.
	private var indeterminateProgress: Bool = true {
		didSet {
			guard indeterminateProgress != oldValue else { return }
			if indeterminateProgress {
				progressIndicator.removeFromSuperview()
				addSubview(spinner)
				if busy { spinner.startAnimation(nil) }
			} else {
				addSubview(progressIndicator)
				if busy { spinner.stopAnimation(nil) }
				spinner.removeFromSuperview()
			}
			rebuildConstraints()
		}
	}

	/// The status text to display.
	public var statusText: String {
		get { statusTextField.stringValue }
		set { statusTextField.stringValue = newValue }
	}

	/// The progress value (0 to 1). Setting to 0 switches to indeterminate mode.
	public var progress: CGFloat {
		get { progressIndicator.doubleValue }
		set {
			progressIndicator.doubleValue = newValue
			indeterminateProgress = newValue == 0
		}
	}

	/// Whether a command or page load is in progress.
	public var busy: Bool = false {
		didSet {
			if indeterminateProgress {
				if busy {
					spinner.startAnimation(nil)
				} else {
					spinner.stopAnimation(nil)
				}
			}
		}
	}

	/// Whether the back button is enabled.
	public var canGoBack: Bool {
		get { goBackButton.isEnabled }
		set { goBackButton.isEnabled = newValue }
	}

	/// Whether the forward button is enabled.
	public var canGoForward: Bool {
		get { goForwardButton.isEnabled }
		set { goForwardButton.isEnabled = newValue }
	}

	// MARK: - Layout Constraints

	private var layoutConstraintsCache: [NSLayoutConstraint] = []

	// MARK: - Initialization

	override public init(frame: NSRect) {
		super.init(frame: frame)
		commonInit()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	private func commonInit() {
		wantsLayer = true
		material = .titlebar
		blendingMode = .withinWindow
		state = .followsWindowActiveState

		goBackButton.target = self
		goBackButton.action = #selector(goBackAction(_:))

		goForwardButton.target = self
		goForwardButton.action = #selector(goForwardAction(_:))

		addSubview(topDivider)
		addSubview(divider)
		addSubview(goBackButton)
		addSubview(goForwardButton)
		addSubview(statusTextField)
		addSubview(spinner)

		rebuildConstraints()
	}

	// MARK: - Constraints

	private func rebuildConstraints() {
		NSLayoutConstraint.deactivate(layoutConstraintsCache)
		layoutConstraintsCache.removeAll()

		let activeSpinner: NSView = indeterminateProgress ? spinner : progressIndicator

		var constraints = [
			// Top divider spans full width
			topDivider.topAnchor.constraint(equalTo: topAnchor),
			topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
			topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
			topDivider.heightAnchor.constraint(equalToConstant: 1),

			// Back/forward/divider row
			goBackButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
			goBackButton.widthAnchor.constraint(equalToConstant: 22),
			goBackButton.centerYAnchor.constraint(equalTo: divider.centerYAnchor),

			goForwardButton.leadingAnchor.constraint(equalTo: goBackButton.trailingAnchor, constant: 2),
			goForwardButton.widthAnchor.constraint(equalTo: goBackButton.widthAnchor),
			goForwardButton.centerYAnchor.constraint(equalTo: divider.centerYAnchor),

			divider.leadingAnchor.constraint(equalTo: goForwardButton.trailingAnchor, constant: 2),
			divider.widthAnchor.constraint(equalToConstant: 1),
			divider.heightAnchor.constraint(equalToConstant: 15),
			divider.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 4),
			divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),

			// Status text and spinner
			statusTextField.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 8),
			statusTextField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
			statusTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

			activeSpinner.leadingAnchor.constraint(equalTo: statusTextField.trailingAnchor, constant: 8),
			activeSpinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
		]

		if indeterminateProgress {
			constraints.append(
				activeSpinner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
			)
		} else {
			constraints.append(contentsOf: [
				activeSpinner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
				activeSpinner.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
				activeSpinner.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
			])
		}

		layoutConstraintsCache = constraints
		NSLayoutConstraint.activate(constraints)
	}

	// MARK: - Actions

	@objc private func goBackAction(_: Any?) {
		delegate?.statusBarGoBack(self)
	}

	@objc private func goForwardAction(_: Any?) {
		delegate?.statusBarGoForward(self)
	}
}
#endif
