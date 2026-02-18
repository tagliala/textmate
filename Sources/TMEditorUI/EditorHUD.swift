import AppKit

/// A transient heads-up display overlay for brief status messages.
///
/// This is the Swift counterpart of the C++ `OTVHUD` in
/// `Frameworks/OakTextView/src/OTVHUD.mm`. It shows a rounded semi-transparent
/// overlay in the top-right corner of an editor view, auto-fading after a delay.
///
/// Usage:
/// ```swift
/// EditorHUD.show(in: editorView, text: "Tab Size: 3")
/// ```
@MainActor
public final class EditorHUD: NSWindowController {
	// MARK: - Constants

	private static let hudWidth: CGFloat = 100
	private static let hudHeight: CGFloat = 30
	private static let hudInset: CGFloat = 10
	private static let fadeDelay: TimeInterval = 1.0

	// MARK: - Properties

	private let textField: NSTextField
	private var requestID: UInt = 0
	private weak var lastView: NSView?

	// MARK: - Shared Instance Management

	/// Weak reference to the last HUD shown, to reuse if the same view.
	private weak static var lastHUD: EditorHUD?

	/// Show a HUD in the given view with the specified text.
	///
	/// Reuses the existing HUD if it's for the same view.
	///
	/// - Parameters:
	///   - view: The view to attach the HUD to.
	///   - text: The text to display.
	/// - Returns: The displayed HUD instance.
	@discardableResult
	public static func show(in view: NSView, text: String) -> EditorHUD {
		var hud = lastHUD
		if hud == nil || hud?.lastView !== view {
			hud = EditorHUD(view: view)
			lastHUD = hud
		}
		hud!.stringValue = text
		hud!.showWindow(nil)
		return hud!
	}

	// MARK: - Init

	/// Creates a HUD positioned in the top-right corner of the given view.
	public init(view: NSView) {
		lastView = view

		let viewRect = view.window.flatMap { win in
			win.convertToScreen(view.convert(view.visibleRect, to: nil))
		} ?? view.visibleRect

		let safeRect = viewRect.isEmpty
			? NSRect(x: 100, y: 100, width: 400, height: 300)
			: viewRect
		let insetRect = safeRect.insetBy(dx: Self.hudInset, dy: Self.hudInset)
		let hudFrame = NSRect(
			x: insetRect.maxX - Self.hudWidth,
			y: insetRect.maxY - Self.hudHeight,
			width: Self.hudWidth,
			height: Self.hudHeight,
		)

		let panel = NSPanel(
			contentRect: hudFrame,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false,
		)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.ignoresMouseEvents = true
		panel.level = .popUpMenu
		panel.hasShadow = false

		// Rounded semi-transparent background
		let backgroundView = HUDBackgroundView(frame: NSRect(origin: .zero, size: hudFrame.size))
		panel.contentView = backgroundView

		// Centered text label
		textField = NSTextField(labelWithString: "")
		textField.font = .systemFont(ofSize: 20)
		textField.alignment = .center
		textField.textColor = .white
		textField.isBezeled = false
		textField.drawsBackground = false
		textField.isEditable = false
		textField.isSelectable = false

		// Shadow on text
		let shadow = NSShadow()
		shadow.shadowColor = .darkGray
		shadow.shadowOffset = NSSize(width: 1, height: -1)
		shadow.shadowBlurRadius = 1.2
		textField.shadow = shadow

		textField.translatesAutoresizingMaskIntoConstraints = false
		backgroundView.addSubview(textField)

		NSLayoutConstraint.activate([
			textField.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
			textField.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
			textField.widthAnchor.constraint(equalToConstant: Self.hudWidth),
		])

		super.init(window: panel)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Text

	/// The text displayed in the HUD.
	public var stringValue: String {
		get { textField.stringValue }
		set {
			let pStyle = NSMutableParagraphStyle()
			pStyle.alignment = .center

			let shadow = NSShadow()
			shadow.shadowColor = .darkGray
			shadow.shadowOffset = NSSize(width: 1, height: -1)
			shadow.shadowBlurRadius = 1.2

			textField.attributedStringValue = NSAttributedString(
				string: newValue,
				attributes: [
					.paragraphStyle: pStyle,
					.foregroundColor: NSColor.white,
					.shadow: shadow,
				],
			)
		}
	}

	// MARK: - Show / Dismiss

	override public func showWindow(_ sender: Any?) {
		requestID &+= 1
		NSObject.cancelPreviousPerformRequests(
			withTarget: self,
			selector: #selector(fadeOut),
			object: nil,
		)

		// Reposition to the current view location.
		if let view = lastView, let win = view.window {
			let screenRect = win.convertToScreen(view.convert(view.visibleRect, to: nil))
			if !screenRect.isEmpty, screenRect.width.isFinite, screenRect.height.isFinite {
				let insetRect = screenRect.insetBy(dx: Self.hudInset, dy: Self.hudInset)
				let hudFrame = NSRect(
					x: insetRect.maxX - Self.hudWidth,
					y: insetRect.maxY - Self.hudHeight,
					width: Self.hudWidth,
					height: Self.hudHeight,
				)
				window?.setFrame(hudFrame, display: false)
			}
		}

		// Snap to full opacity.
		NSAnimationContext.beginGrouping()
		NSAnimationContext.current.duration = 0
		window?.animator().alphaValue = 1
		NSAnimationContext.endGrouping()

		super.showWindow(sender)

		perform(#selector(fadeOut), with: nil, afterDelay: Self.fadeDelay)
	}

	@objc private func fadeOut() {
		let savedID = requestID
		NSAnimationContext.beginGrouping()
		NSAnimationContext.current.completionHandler = { [weak self] in
			guard let self, requestID == savedID else { return }
			close()
		}
		window?.animator().alphaValue = 0
		NSAnimationContext.endGrouping()
	}
}

// MARK: - Background View

/// Rounded semi-transparent background for the HUD.
private class HUDBackgroundView: NSView {
	override func draw(_: NSRect) {
		NSColor(calibratedWhite: 0.5, alpha: 0.5).set()
		NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
	}
}
