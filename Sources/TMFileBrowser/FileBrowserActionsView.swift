#if canImport(AppKit)
import AppKit

/// Actions bar view for the file browser bottom area.
///
/// Port of `OFBActionsView` from `OFB/OFBActionsView.mm`.
/// Contains buttons for creating files, actions popup, reload,
/// search, favorites, and SCM status views.
@MainActor
public class FileBrowserActionsView: NSVisualEffectView {
	/// Button to create a new file.
	public let createButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(named: NSImage.addTemplateName)
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.toolTip = "Create new file"
		btn.image?.accessibilityDescription = "Create new file"
		return btn
	}()

	/// Actions popup button (gear menu) for file operations.
	public let actionsPopUpButton: NSPopUpButton = {
		let btn = NSPopUpButton(frame: .zero, pullsDown: true)
		btn.isBordered = false
		btn.translatesAutoresizingMaskIntoConstraints = false
		// Use action/gear template image
		let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Actions")
			?? NSImage(named: NSImage.actionTemplateName)!
		(btn.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
		btn.addItem(withTitle: "")
		btn.lastItem?.image = gearImage
		return btn
	}()

	/// Reload button to refresh the file browser contents.
	public let reloadButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(named: NSImage.refreshTemplateName)
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.toolTip = "Reload file browser"
		btn.image?.accessibilityDescription = "Reload file browser"
		return btn
	}()

	/// Search button to initiate a search in the current folder.
	public let searchButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
			?? NSImage(named: "SearchTemplate")
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.toolTip = "Search current folder"
		return btn
	}()

	/// Favorites button to toggle favorites view.
	public let favoritesButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(systemSymbolName: "star", accessibilityDescription: "Favorites")
			?? NSImage(named: "FavoritesTemplate")
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.toolTip = "Show favorites"
		return btn
	}()

	/// SCM button to toggle source control status view.
	public let scmButton: NSButton = {
		let btn = NSButton()
		btn.setButtonType(.momentaryChange)
		btn.isBordered = false
		btn.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "SCM")
			?? NSImage(named: "SCMTemplate")
		btn.imagePosition = .imageOnly
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.toolTip = "Show source control management status"
		return btn
	}()

	/// The vertical divider between create and actions buttons.
	private let verticalDivider: NSBox = {
		let box = NSBox()
		box.boxType = .separator
		box.translatesAutoresizingMaskIntoConstraints = false
		return box
	}()

	/// The top divider line.
	private let topDivider: NSBox = {
		let box = NSBox()
		box.boxType = .separator
		box.translatesAutoresizingMaskIntoConstraints = false
		return box
	}()

	override public init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		material = .titlebar
		blendingMode = .withinWindow
		state = .followsWindowActiveState

		addSubview(topDivider)
		addSubview(createButton)
		addSubview(verticalDivider)
		addSubview(actionsPopUpButton)
		addSubview(reloadButton)
		addSubview(searchButton)
		addSubview(favoritesButton)
		addSubview(scmButton)

		NSLayoutConstraint.activate([
			// Top divider
			topDivider.topAnchor.constraint(equalTo: topAnchor),
			topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
			topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
			topDivider.heightAnchor.constraint(equalToConstant: 1),

			// Create button
			createButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			createButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),

			// Vertical divider
			verticalDivider.leadingAnchor.constraint(equalTo: createButton.trailingAnchor, constant: 8),
			verticalDivider.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
			verticalDivider.heightAnchor.constraint(equalToConstant: 15),
			verticalDivider.widthAnchor.constraint(equalToConstant: 1),

			// Actions popup
			actionsPopUpButton.leadingAnchor.constraint(equalTo: verticalDivider.trailingAnchor, constant: 8),
			actionsPopUpButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
			actionsPopUpButton.widthAnchor.constraint(equalToConstant: 31),

			// Right-side buttons (right-aligned)
			scmButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
			scmButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),

			favoritesButton.trailingAnchor.constraint(equalTo: scmButton.leadingAnchor, constant: -4),
			favoritesButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),

			searchButton.trailingAnchor.constraint(equalTo: favoritesButton.leadingAnchor, constant: -4),
			searchButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),

			reloadButton.trailingAnchor.constraint(equalTo: searchButton.leadingAnchor, constant: -4),
			reloadButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),

			// Overall height
			heightAnchor.constraint(equalToConstant: 25),
		])
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}
}
#endif
