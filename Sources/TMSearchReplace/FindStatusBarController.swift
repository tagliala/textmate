#if canImport(AppKit)
import AppKit

// MARK: - Find Status Bar Controller

/// A view controller displaying search progress and status — equivalent to `FFStatusBarViewController`.
///
/// Shows a stop button, spinning progress indicator, and a toggle-able status text
/// label that alternates between primary and alternate descriptions on click.
@MainActor
public final class FindStatusBarController: NSViewController, Sendable {
	/// The primary status text (e.g. "42 matches in 7 files").
	public var statusText: String = "" {
		didSet { updateStatusDisplay() }
	}

	/// An alternate status text shown when the user clicks the label (e.g. search details).
	public var alternateStatusText: String = "" {
		didSet { updateAlternateDisplay() }
	}

	/// Whether the progress spinner and stop button are visible.
	public var isProgressVisible: Bool = false {
		didSet { updateProgressVisibility() }
	}

	/// Called when the user clicks the stop button.
	public var onStop: (() -> Void)?

	// MARK: - Subviews

	private lazy var stopButton: NSButton = {
		let btn = NSButton()
		btn.isBordered = false
		btn.setButtonType(.momentaryChange)
		btn.controlSize = .small
		btn.image = NSImage(named: NSImage.stopProgressFreestandingTemplateName)
		btn.imagePosition = .imageOnly
		btn.toolTip = "Stop Search"
		btn.keyEquivalent = "."
		btn.keyEquivalentModifierMask = .command
		btn.target = self
		btn.action = #selector(didClickStop(_:))
		btn.setContentHuggingPriority(.required, for: .horizontal)
		btn.translatesAutoresizingMaskIntoConstraints = false
		return btn
	}()

	private lazy var progressIndicator: NSProgressIndicator = {
		let pi = NSProgressIndicator()
		pi.controlSize = .small
		pi.isDisplayedWhenStopped = false
		pi.style = .spinning
		pi.translatesAutoresizingMaskIntoConstraints = false
		return pi
	}()

	private lazy var statusLabel: NSButton = {
		let btn = NSButton()
		btn.alignment = .left
		btn.isBordered = false
		btn.setButtonType(.toggle)
		btn.controlSize = .small
		btn.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
		btn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		btn.setContentHuggingPriority(.defaultHigh, for: .vertical)
		btn.translatesAutoresizingMaskIntoConstraints = false
		return btn
	}()

	// MARK: - Lifecycle

	override public func loadView() {
		let stack = NSStackView(views: [stopButton, progressIndicator, statusLabel])
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
		stack.setCustomSpacing(2, after: progressIndicator)
		stack.setHuggingPriority(.defaultHigh - 1, for: .vertical)

		stopButton.isHidden = !isProgressVisible
		progressIndicator.isHidden = !isProgressVisible

		view = stack
	}

	// MARK: - Actions

	@objc private func didClickStop(_: Any) {
		onStop?()
	}

	// MARK: - Private

	private func updateStatusDisplay() {
		guard isViewLoaded else { return }
		let formatted = Self.formatStatusString(statusText)
		statusLabel.attributedTitle = formatted
		statusLabel.attributedAlternateTitle = formatted
	}

	private func updateAlternateDisplay() {
		guard isViewLoaded else { return }
		statusLabel.attributedAlternateTitle = Self.formatStatusString(alternateStatusText)
	}

	private func updateProgressVisibility() {
		guard isViewLoaded else { return }
		if isProgressVisible {
			progressIndicator.startAnimation(nil)
		} else {
			progressIndicator.stopAnimation(nil)
		}
		stopButton.isHidden = !isProgressVisible
		progressIndicator.isHidden = !isProgressVisible
	}

	// MARK: - Status String Formatting

	/// Format a status string for display, replacing newlines with ¬ and tabs with ‣.
	static func formatStatusString(_ string: String) -> NSAttributedString {
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.lineBreakMode = .byTruncatingMiddle

		let regularAttrs: [NSAttributedString.Key: Any] = [
			.foregroundColor: NSColor.labelColor,
			.paragraphStyle: paragraphStyle,
		]

		let dimmedAttrs: [NSAttributedString.Key: Any] = [
			.foregroundColor: NSColor.tertiaryLabelColor,
			.paragraphStyle: paragraphStyle,
		]

		let lineJoiner = NSAttributedString(string: "¬", attributes: dimmedAttrs)
		let tabJoiner = NSAttributedString(string: "‣", attributes: dimmedAttrs)

		let result = NSMutableAttributedString()

		var firstLine = true
		string.enumerateLines { line, _ in
			if !firstLine {
				result.append(lineJoiner)
			}
			firstLine = false

			let parts = line.components(separatedBy: "\t")
			for (i, part) in parts.enumerated() {
				if i > 0 {
					result.append(tabJoiner)
				}
				result.append(NSAttributedString(string: part, attributes: regularAttrs))
			}
		}

		return result
	}
}
#endif
