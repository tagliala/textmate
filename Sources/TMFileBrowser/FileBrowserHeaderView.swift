#if canImport(AppKit)
import AppKit

/// Header view for the file browser with navigation buttons and a folder popup.
///
/// Port of `OFBHeaderView` from `OFB/OFBHeaderView.mm`.
/// Contains a back button, forward button, and a folder popup button
/// that shows the current location with breadcrumb navigation.
@MainActor
public class FileBrowserHeaderView: NSVisualEffectView {
	/// Popup button showing the current folder and its ancestors.
	public let folderPopUpButton: NSPopUpButton = {
		let btn = NSPopUpButton(frame: .zero, pullsDown: true)
		btn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		btn.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
		btn.setContentHuggingPriority(.defaultLow, for: .vertical)
		btn.isBordered = false
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.setAccessibilityLabel("Current folder")
		return btn
	}()

	/// Go back in navigation history.
	public let goBackButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(named: NSImage.goBackTemplateName)
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.toolTip = "Go Back"
		btn.image?.accessibilityDescription = "Go Back"
		return btn
	}()

	/// Go forward in navigation history.
	public let goForwardButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(named: NSImage.goForwardTemplateName)
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.toolTip = "Go Forward"
		btn.image?.accessibilityDescription = "Go Forward"
		return btn
	}()

	/// The bottom divider line.
	private let bottomDivider: NSBox = {
		let box = NSBox()
		box.boxType = .separator
		box.translatesAutoresizingMaskIntoConstraints = false
		return box
	}()

	/// The vertical divider between folder popup and navigation buttons.
	private let verticalDivider: NSBox = {
		let box = NSBox()
		box.boxType = .separator
		box.translatesAutoresizingMaskIntoConstraints = false
		return box
	}()

	override public init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		blendingMode = .withinWindow
		material = .titlebar

		addSubview(folderPopUpButton)
		addSubview(verticalDivider)
		addSubview(goBackButton)
		addSubview(goForwardButton)
		addSubview(bottomDivider)

		NSLayoutConstraint.activate([
			// Folder popup: left side
			folderPopUpButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
			folderPopUpButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
			folderPopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 75),

			// Vertical divider
			verticalDivider.leadingAnchor.constraint(equalTo: folderPopUpButton.trailingAnchor, constant: 3),
			verticalDivider.centerYAnchor.constraint(equalTo: folderPopUpButton.centerYAnchor),
			verticalDivider.heightAnchor.constraint(equalToConstant: 15),
			verticalDivider.widthAnchor.constraint(equalToConstant: 1),

			// Back button
			goBackButton.leadingAnchor.constraint(equalTo: verticalDivider.trailingAnchor, constant: 2),
			goBackButton.centerYAnchor.constraint(equalTo: folderPopUpButton.centerYAnchor),
			goBackButton.widthAnchor.constraint(equalToConstant: 22),

			// Forward button
			goForwardButton.leadingAnchor.constraint(equalTo: goBackButton.trailingAnchor, constant: 2),
			goForwardButton.centerYAnchor.constraint(equalTo: folderPopUpButton.centerYAnchor),
			goForwardButton.widthAnchor.constraint(equalTo: goBackButton.widthAnchor),
			goForwardButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),

			// Bottom divider
			bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
			bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
			bottomDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
			bottomDivider.heightAnchor.constraint(equalToConstant: 1),

			// Overall height
			heightAnchor.constraint(equalToConstant: 24),
		])
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}
}
#endif
