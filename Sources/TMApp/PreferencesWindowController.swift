import AppKit

/// A stub preferences window with tabs matching TextMate's preferences layout.
///
/// This is a placeholder for Iteration 1 — individual preference panes will be
/// implemented in later iterations.
@MainActor
final class PreferencesWindowController: NSWindowController {
	static let shared = PreferencesWindowController()

	private let tabView = NSTabView()

	private init() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false,
		)
		window.title = String(localized: "Preferences", comment: "Preferences window title")
		window.isReleasedWhenClosed = false
		window.center()

		super.init(window: window)
		setupTabs()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	func showPreferences() {
		window?.makeKeyAndOrderFront(nil)
	}

	private func setupTabs() {
		guard let contentView = window?.contentView else { return }

		tabView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(tabView)

		NSLayoutConstraint.activate([
			tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
			tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
			tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
		])

		let tabNames = [
			String(localized: "Files", comment: "Preferences tab"),
			String(localized: "Projects", comment: "Preferences tab"),
			String(localized: "Bundles", comment: "Preferences tab"),
			String(localized: "Variables", comment: "Preferences tab"),
			String(localized: "Software Update", comment: "Preferences tab"),
			String(localized: "Terminal", comment: "Preferences tab"),
		]

		for name in tabNames {
			let item = NSTabViewItem(identifier: name)
			item.label = name

			// Placeholder content for each tab
			let placeholder = NSTextField(
				labelWithString: String(
					localized: "\(name) preferences will be available in a future iteration.",
					comment: "Preferences placeholder text",
				),
			)
			placeholder.textColor = .secondaryLabelColor
			placeholder.alignment = .center
			placeholder.translatesAutoresizingMaskIntoConstraints = false

			let view = NSView()
			view.addSubview(placeholder)
			NSLayoutConstraint.activate([
				placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
				placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
				placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
				placeholder.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
			])

			item.view = view
			tabView.addTabViewItem(item)
		}
	}
}
