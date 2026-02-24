#if canImport(AppKit)
import AppKit

/// The composite view for the file browser sidebar.
///
/// Port of `FileBrowserView` from `FileBrowserView.h/.mm`.
/// Lays out the header view, outline view (in a scroll view), and actions view
/// vertically.
@MainActor
public class FileBrowserCompositeView: NSView {
	/// The header view with navigation buttons and folder popup.
	public let headerView = FileBrowserHeaderView(frame: .zero)

	/// The outline view for displaying the file tree.
	public let outlineView: FileBrowserOutlineView = {
		let ov = FileBrowserOutlineView()
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
		column.title = ""
		column.isEditable = false
		ov.addTableColumn(column)
		ov.outlineTableColumn = column
		ov.headerView = nil
		ov.rowHeight = 20
		ov.indentationPerLevel = 16
		ov.autoresizesOutlineColumn = true
		ov.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		ov.allowsMultipleSelection = true
		ov.usesAlternatingRowBackgroundColors = false
		return ov
	}()

	/// The actions bar at the bottom.
	public let actionsView = FileBrowserActionsView(frame: .zero)

	/// The scroll view wrapping the outline view.
	private let scrollView: NSScrollView = {
		let sv = NSScrollView()
		sv.hasVerticalScroller = true
		sv.hasHorizontalScroller = false
		sv.autohidesScrollers = true
		sv.drawsBackground = true
		sv.translatesAutoresizingMaskIntoConstraints = false
		return sv
	}()

	override public init(frame: NSRect) {
		super.init(frame: frame)
		setupViews()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	private func setupViews() {
		headerView.translatesAutoresizingMaskIntoConstraints = false
		actionsView.translatesAutoresizingMaskIntoConstraints = false

		scrollView.documentView = outlineView

		addSubview(headerView)
		addSubview(scrollView)
		addSubview(actionsView)

		NSLayoutConstraint.activate([
			headerView.topAnchor.constraint(equalTo: topAnchor),
			headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
			headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

			scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: actionsView.topAnchor),

			actionsView.leadingAnchor.constraint(equalTo: leadingAnchor),
			actionsView.trailingAnchor.constraint(equalTo: trailingAnchor),
			actionsView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}
}
#endif
