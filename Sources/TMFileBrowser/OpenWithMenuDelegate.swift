#if canImport(AppKit)
import AppKit

/// Populates an "Open With" submenu with applications that can open the
/// given document URLs. Port of `OakOpenWithMenu` from
/// `Frameworks/OakAppKit/src/OakOpenWithMenu.mm`.
@MainActor
public final class OpenWithMenuDelegate: NSObject, NSMenuDelegate {
	/// The document URLs to open.
	public let documentURLs: [URL]

	public init(documentURLs: [URL]) {
		self.documentURLs = documentURLs
		super.init()
	}

	// MARK: - Application Discovery

	private struct AppInfo: Comparable {
		let url: URL
		let name: String
		let version: String
		let isDefault: Bool

		var displayName: String {
			var label = name
			if isDefault { label += " (default)" }
			return label
		}

		static func < (lhs: AppInfo, rhs: AppInfo) -> Bool {
			if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
			return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
		}

		static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
			lhs.url == rhs.url
		}
	}

	private func discoverApplications() -> [AppInfo] {
		guard !documentURLs.isEmpty else { return [] }

		var commonAppURLs: Set<URL>?
		var defaultAppURLs: Set<URL> = []

		for docURL in documentURLs {
			let appURLs = Set(NSWorkspace.shared.urlsForApplications(toOpen: docURL))

			if let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: docURL) {
				defaultAppURLs.insert(defaultApp.standardized)
			}

			let standardized = Set(appURLs.map(\.standardized))
			if let existing = commonAppURLs {
				commonAppURLs = existing.intersection(standardized)
			} else {
				commonAppURLs = standardized
			}
		}

		guard let appURLs = commonAppURLs else { return [] }

		var apps: [AppInfo] = []
		for appURL in appURLs {
			guard let bundle = Bundle(url: appURL) else { continue }
			let name = FileManager.default.displayName(atPath: appURL.path)
			let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
				?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
				?? "???"
			let isDefault = defaultAppURLs.count == 1 && defaultAppURLs.contains(appURL.standardized)
			apps.append(AppInfo(url: appURL, name: name, version: version, isDefault: isDefault))
		}

		return apps.sorted()
	}

	// MARK: - NSMenuDelegate

	public func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		let apps = discoverApplications()
		if apps.isEmpty {
			let item = NSMenuItem(title: "No Suitable Applications Found", action: nil, keyEquivalent: "")
			item.isEnabled = false
			menu.addItem(item)
			return
		}

		var didInsertDefault = false
		for app in apps {
			if didInsertDefault, !app.isDefault {
				menu.addItem(.separator())
				didInsertDefault = false
			}
			if app.isDefault { didInsertDefault = true }

			let item = NSMenuItem(title: app.displayName, action: #selector(openWith(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = app.url
			item.toolTip = app.url.path.abbreviatingWithTildeInPath

			if let icon = NSWorkspace.shared.icon(forFile: app.url.path) as NSImage? {
				let sized = icon.copy() as! NSImage
				sized.size = NSSize(width: 16, height: 16)
				item.image = sized
			}

			menu.addItem(item)
		}
	}

	@objc private func openWith(_ sender: NSMenuItem) {
		guard let appURL = sender.representedObject as? URL else { return }
		let config = NSWorkspace.OpenConfiguration()
		NSWorkspace.shared.open(documentURLs, withApplicationAt: appURL, configuration: config)
	}
}

private extension String {
	var abbreviatingWithTildeInPath: String {
		(self as NSString).abbreviatingWithTildeInPath
	}
}
#endif
