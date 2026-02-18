#if canImport(AppKit) && canImport(WebKit)
import AppKit
import TMHTMLOutput

/// A window controller that wraps an `HTMLOutputCommandView` for
/// displaying HTML output from bundle commands.
///
/// Port of `Frameworks/HTMLOutputWindow/src/HTMLOutputWindowController.mm`.
/// Each document window may own one of these; it is reused across
/// commands according to the command's `outputReuse` setting.
@MainActor
public final class HTMLOutputWindowController: NSWindowController {
	/// The HTML output command view filling the window.
	public let commandView: HTMLOutputCommandView

	public init() {
		let win = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 750, height: 600),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false,
		)
		win.title = "HTML Output"
		win.setFrameAutosaveName("HTMLOutputWindow")
		win.isReleasedWhenClosed = false
		win.center()

		commandView = HTMLOutputCommandView(frame: win.contentView!.bounds)
		commandView.translatesAutoresizingMaskIntoConstraints = false
		win.contentView!.addSubview(commandView)

		NSLayoutConstraint.activate([
			commandView.topAnchor.constraint(equalTo: win.contentView!.topAnchor),
			commandView.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor),
			commandView.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor),
			commandView.bottomAnchor.constraint(equalTo: win.contentView!.bottomAnchor),
		])

		super.init(window: win)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
}
#endif
