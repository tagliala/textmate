import AppKit

/// Displays a custom About panel for TextMate, showing app name, version,
/// copyright, and license information.
@MainActor
final class AboutPanelController {
	private var window: NSWindow?

	static let shared = AboutPanelController()

	private init() {}

	func showAboutPanel() {
		if let existing = window {
			existing.makeKeyAndOrderFront(nil)
			return
		}

		let panel = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false,
		)
		panel.title = ""
		panel.isReleasedWhenClosed = false
		panel.center()

		let contentView = NSView(frame: panel.contentView!.bounds)
		contentView.wantsLayer = true

		// App icon
		let iconView = NSImageView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
		iconView.image = NSApp.applicationIconImage
		iconView.imageScaling = .scaleProportionallyUpOrDown
		iconView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(iconView)

		// App name
		let nameLabel = NSTextField(labelWithString: "TextMate")
		nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
		nameLabel.alignment = .center
		nameLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(nameLabel)

		// Version
		let versionLabel = NSTextField(labelWithString: "Version 3.0 (Swift Rewrite)")
		versionLabel.font = .systemFont(ofSize: 12)
		versionLabel.textColor = .secondaryLabelColor
		versionLabel.alignment = .center
		versionLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(versionLabel)

		// Copyright
		let copyrightLabel = NSTextField(
			labelWithString: "Copyright © 2004–2026 MacroMates Ltd.\nAll rights reserved.",
		)
		copyrightLabel.font = .systemFont(ofSize: 11)
		copyrightLabel.textColor = .tertiaryLabelColor
		copyrightLabel.alignment = .center
		copyrightLabel.maximumNumberOfLines = 2
		copyrightLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(copyrightLabel)

		// License link
		let licenseButton = NSButton(
			title: String(localized: "License Agreement", comment: "About panel: license link"),
			target: self,
			action: #selector(showLicense),
		)
		licenseButton.bezelStyle = .inline
		licenseButton.isBordered = false
		licenseButton.contentTintColor = .controlAccentColor
		licenseButton.font = .systemFont(ofSize: 11)
		licenseButton.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(licenseButton)

		NSLayoutConstraint.activate([
			iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
			iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 96),
			iconView.heightAnchor.constraint(equalToConstant: 96),

			nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
			nameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

			versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
			versionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

			copyrightLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 12),
			copyrightLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
			copyrightLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
			copyrightLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

			licenseButton.topAnchor.constraint(equalTo: copyrightLabel.bottomAnchor, constant: 8),
			licenseButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
		])

		panel.contentView = contentView
		window = panel
		panel.makeKeyAndOrderFront(nil)
	}

	@objc private func showLicense() {
		// Try to find the LICENSE file relative to the main bundle
		if let bundlePath = Bundle.main.resourceURL?.deletingLastPathComponent()
			.appendingPathComponent("LICENSE"),
			FileManager.default.fileExists(atPath: bundlePath.path)
		{
			NSWorkspace.shared.open(bundlePath)
		} else {
			// Open GitHub license page as fallback
			if let url = URL(string: "https://github.com/textmate/textmate/blob/main/LICENSE") {
				NSWorkspace.shared.open(url)
			}
		}
	}
}
