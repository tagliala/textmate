#if canImport(AppKit)
import AppKit

/// A custom table cell view for file browser items.
///
/// Port of `FileItemTableCellView` from `FileItemTableCellView.h/.mm`.
/// Provides optional open/close indicator buttons alongside the standard
/// icon and text field. The open button shows a horizontal line (indicating
/// an open document), and the close button shows a filled circle (indicating
/// an unsaved document).
@MainActor
public class FileItemTableCellView: NSTableCellView {
	/// Button indicating the file is currently open.
	public let openButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Open")
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.isHidden = true
		btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
		return btn
	}()

	/// Button for closing the file (unsaved indicator).
	public let closeButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Close")
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.isHidden = true
		btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
		return btn
	}()

	/// The icon image view.
	public let iconView: NSImageView = {
		let iv = NSImageView()
		iv.imageScaling = .scaleProportionallyUpOrDown
		iv.translatesAutoresizingMaskIntoConstraints = false
		return iv
	}()

	/// The filename text field.
	public let nameField: NSTextField = {
		let tf = NSTextField(labelWithString: "")
		tf.lineBreakMode = .byTruncatingTail
		tf.font = .systemFont(ofSize: 13)
		tf.translatesAutoresizingMaskIntoConstraints = false
		return tf
	}()

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setupSubviews()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	private func setupSubviews() {
		addSubview(openButton)
		addSubview(iconView)
		addSubview(nameField)
		addSubview(closeButton)

		imageView = iconView
		textField = nameField

		NSLayoutConstraint.activate([
			// Open button (left edge)
			openButton.leadingAnchor.constraint(equalTo: leadingAnchor),
			openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			openButton.widthAnchor.constraint(equalToConstant: 10),

			// Icon
			iconView.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 2),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 16),
			iconView.heightAnchor.constraint(equalToConstant: 16),

			// Name
			nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
			nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
			nameField.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -2),

			// Close button (right edge)
			closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
			closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			closeButton.widthAnchor.constraint(equalToConstant: 10),
		])
	}

	/// Configures the cell for a file item.
	public func configure(with item: FileItem, icon: NSImage? = nil) {
		nameField.stringValue = item.displayName
		iconView.image = icon ?? NSWorkspace.shared.icon(forFile: item.URL.path)
		iconView.image?.size = NSSize(width: 16, height: 16)
		toolTip = item.toolTip ?? item.URL.path
	}
}
#endif
