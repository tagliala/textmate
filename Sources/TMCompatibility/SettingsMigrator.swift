import Foundation

/// Migrates TextMate 2 preferences, bundles, and settings to the
/// new Swift application.
///
/// The original settings are stored in:
///   - `~/Library/Application Support/TextMate/` (bundles, themes)
///   - `~/Library/Preferences/com.macromates.TextMate.plist` (app prefs)
///   - `~/.tm_properties` and per-directory `.tm_properties`
///
/// The C++ parser is in `Frameworks/settings/src/settings.cc`.
public struct SettingsMigrator: Sendable {
	/// The TextMate 2 Application Support directory.
	public static let legacyAppSupportDir: URL = {
		let appSupport = FileManager.default.urls(
			for: .applicationSupportDirectory, in: .userDomainMask,
		).first!
		return appSupport.appendingPathComponent("TextMate")
	}()

	/// The TextMate 2 preferences domain.
	public static let legacyPrefsDomain = "com.macromates.TextMate"

	/// The new Application Support directory for the rewrite.
	public static let newAppSupportDir: URL = {
		let appSupport = FileManager.default.urls(
			for: .applicationSupportDirectory, in: .userDomainMask,
		).first!
		return appSupport.appendingPathComponent("TextMate")
	}()

	// MARK: - Migration Status

	/// Known preference keys from TextMate 2.
	public static let knownPreferenceKeys: Set<String> = [
		"environmentVariables",
		"fileBrowserPlacement",
		"fileBrowserSingleClickToOpen",
		"fileBrowserStyle",
		"fontName",
		"fontSize",
		"includeInFileChooser",
		"excludeInFileChooser",
		"includeInFolderSearch",
		"excludeInFolderSearch",
		"disableAntiAlias",
		"disableBundleUpdates",
		"disableRmate",
		"rmatePort",
		"scrollPastEnd",
		"showInvisibles",
		"showWrapColumn",
		"softTabs",
		"softWrap",
		"tabSize",
		"theme",
		"wrapColumn",
		"disableAutoIndent",
		"disableTypingPairs",
	]

	/// A migration report entry.
	public struct MigrationEntry: Sendable, Equatable {
		public enum Kind: Sendable, Equatable {
			case preference(key: String, value: String)
			case bundle(name: String, uuid: String)
			case theme(name: String)
			case tmProperties(path: String)
			case environmentVariable(name: String, value: String)
		}

		public let kind: Kind
		public let migrated: Bool
		public let notes: String?

		public init(kind: Kind, migrated: Bool, notes: String? = nil) {
			self.kind = kind
			self.migrated = migrated
			self.notes = notes
		}
	}

	// MARK: - Detection

	/// Detect whether a TextMate 2 installation exists.
	public static func detectLegacyInstallation() -> LegacyInstallation {
		let fm = FileManager.default

		let hasBundles = fm.fileExists(atPath: legacyAppSupportDir
			.appendingPathComponent("Managed").path)
		let hasPristineBundles = fm.fileExists(atPath: legacyAppSupportDir
			.appendingPathComponent("Pristine Copy").path)
		let hasThemes = fm.fileExists(atPath: legacyAppSupportDir
			.appendingPathComponent("Themes").path)
		let hasKeyBindings = fm.fileExists(atPath: legacyAppSupportDir
			.appendingPathComponent("KeyBindings.dict").path)

		let homeTmProperties = NSHomeDirectory() + "/.tm_properties"
		let hasTmProperties = fm.fileExists(atPath: homeTmProperties)

		// Check preferences
		let hasPreferences = UserDefaults.standard
			.persistentDomain(forName: legacyPrefsDomain) != nil

		return LegacyInstallation(
			appSupportDir: legacyAppSupportDir,
			hasBundles: hasBundles || hasPristineBundles,
			hasThemes: hasThemes,
			hasKeyBindings: hasKeyBindings,
			hasTmProperties: hasTmProperties,
			hasPreferences: hasPreferences,
		)
	}

	// MARK: - Preferences Migration

	/// Read TextMate 2 preferences as a dictionary.
	public static func readLegacyPreferences() -> [String: Any] {
		UserDefaults.standard.persistentDomain(forName: legacyPrefsDomain) ?? [:]
	}

	/// Extract environment variables from TextMate 2 preferences.
	///
	/// TextMate stores these as an array of dictionaries with keys:
	/// `name`, `value`, and optionally `enabled`.
	public static func readLegacyEnvironmentVariables() -> [(name: String, value: String, enabled: Bool)] {
		let prefs = readLegacyPreferences()
		guard let vars = prefs["environmentVariables"] as? [[String: Any]] else {
			return []
		}

		return vars.compactMap { dict in
			guard let name = dict["name"] as? String,
			      let value = dict["value"] as? String
			else { return nil }
			let enabled = dict["enabled"] as? Bool ?? true
			return (name: name, value: value, enabled: enabled)
		}
	}

	// MARK: - .tm_properties

	/// A parsed section from a `.tm_properties` file.
	public struct TMPropertiesSection: Sendable, Equatable {
		/// The file glob or scope selector for this section
		/// (empty for the root section).
		public var selector: String

		/// Whether the selector is a scope selector (vs a file glob).
		public var isScopeSelector: Bool

		/// Key-value assignments in this section.
		public var assignments: [(key: String, value: String)]

		public init(
			selector: String = "",
			isScopeSelector: Bool = false,
			assignments: [(key: String, value: String)] = [],
		) {
			self.selector = selector
			self.isScopeSelector = isScopeSelector
			self.assignments = assignments
		}

		public static func == (lhs: TMPropertiesSection, rhs: TMPropertiesSection) -> Bool {
			lhs.selector == rhs.selector
				&& lhs.isScopeSelector == rhs.isScopeSelector
				&& lhs.assignments.count == rhs.assignments.count
				&& zip(lhs.assignments, rhs.assignments).allSatisfy { $0.0.key == $0.1.key && $0.0.value == $0.1.value }
		}
	}

	/// Parse a `.tm_properties` file into sections.
	///
	/// The format is:
	/// ```
	/// # comment
	/// key = value
	///
	/// [glob_or_scope]
	/// key = value
	/// ```
	public static func parseTMProperties(_ content: String) -> [TMPropertiesSection] {
		var sections: [TMPropertiesSection] = []
		var currentSection = TMPropertiesSection()

		for line in content.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			// Skip empty lines and comments
			if trimmed.isEmpty || trimmed.hasPrefix("#") {
				continue
			}

			// Section header: [glob] or [scope.selector]
			if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
				// Save previous section if it has content
				if !currentSection.assignments.isEmpty {
					sections.append(currentSection)
				}
				let selector = String(trimmed.dropFirst().dropLast())
					.trimmingCharacters(in: .whitespaces)
				currentSection = TMPropertiesSection(
					selector: selector,
					isScopeSelector: isScopeSelector(selector),
				)
				continue
			}

			// Key = value assignment
			if let eqIdx = trimmed.firstIndex(of: "=") {
				let key = trimmed[trimmed.startIndex ..< eqIdx]
					.trimmingCharacters(in: .whitespaces)
				let value = trimmed[trimmed.index(after: eqIdx)...]
					.trimmingCharacters(in: .whitespaces)
				if !key.isEmpty {
					currentSection.assignments.append((key: key, value: value))
				}
			}
		}

		// Save last section
		if !currentSection.assignments.isEmpty {
			sections.append(currentSection)
		}

		return sections
	}

	/// Determine if a string looks like a scope selector (vs a file glob).
	///
	/// Mirrors the C++ `is_scope_selector()` from settings.cc.
	private static func isScopeSelector(_ str: String) -> Bool {
		let rootScopes = ["text", "source", "attr"]
		for scope in rootScopes {
			if str.hasPrefix(scope) {
				let rest = str.dropFirst(scope.count)
				if rest.isEmpty { return true }
				if let first = rest.first, "., ".contains(first) { return true }
			}
		}
		return str.isEmpty
	}

	// MARK: - Bundle Discovery

	/// Discover user-installed bundles.
	public static func discoverLegacyBundles() -> [BundleInfo] {
		let fm = FileManager.default
		var bundles: [BundleInfo] = []

		let searchDirs = [
			legacyAppSupportDir.appendingPathComponent("Managed"),
			legacyAppSupportDir.appendingPathComponent("Pristine Copy/Bundles"),
			legacyAppSupportDir.appendingPathComponent("Bundles"),
		]

		for dir in searchDirs {
			guard let items = try? fm.contentsOfDirectory(
				at: dir,
				includingPropertiesForKeys: nil,
			) else { continue }

			for item in items where item.pathExtension == "tmbundle" {
				if let info = readBundleInfo(at: item) {
					bundles.append(info)
				}
			}
		}

		return bundles
	}

	/// Read bundle information from a `.tmbundle` directory.
	private static func readBundleInfo(at url: URL) -> BundleInfo? {
		let infoPath = url.appendingPathComponent("info.plist")
		guard let data = try? Data(contentsOf: infoPath),
		      let plist = try? PropertyListSerialization.propertyList(
		      	from: data, options: [], format: nil,
		      ) as? [String: Any]
		else { return nil }

		let name = plist["name"] as? String ?? url.deletingPathExtension().lastPathComponent
		let uuid = plist["uuid"] as? String ?? ""

		return BundleInfo(
			name: name,
			uuid: uuid,
			path: url.path,
			contactName: plist["contactName"] as? String,
			contactEmailRot13: plist["contactEmailRot13"] as? String,
			description: plist["description"] as? String,
		)
	}

	// MARK: - Full Migration

	/// Perform a full migration scan and return a report.
	public static func scan() -> MigrationReport {
		let installation = detectLegacyInstallation()
		var entries: [MigrationEntry] = []

		// Preferences
		let prefs = readLegacyPreferences()
		for (key, value) in prefs {
			let known = knownPreferenceKeys.contains(key)
			entries.append(MigrationEntry(
				kind: .preference(key: key, value: "\(value)"),
				migrated: false,
				notes: known ? nil : "Unknown preference key",
			))
		}

		// Environment variables
		for envVar in readLegacyEnvironmentVariables() where envVar.enabled {
			entries.append(MigrationEntry(
				kind: .environmentVariable(name: envVar.name, value: envVar.value),
				migrated: false,
			))
		}

		// Bundles
		for bundle in discoverLegacyBundles() {
			entries.append(MigrationEntry(
				kind: .bundle(name: bundle.name, uuid: bundle.uuid),
				migrated: false,
			))
		}

		// .tm_properties
		let homeTmProperties = NSHomeDirectory() + "/.tm_properties"
		if FileManager.default.fileExists(atPath: homeTmProperties) {
			entries.append(MigrationEntry(
				kind: .tmProperties(path: homeTmProperties),
				migrated: false,
			))
		}

		return MigrationReport(
			installation: installation,
			entries: entries,
		)
	}
}

// MARK: - Supporting Types

/// Information about a legacy TextMate 2 installation.
public struct LegacyInstallation: Sendable {
	public let appSupportDir: URL
	public let hasBundles: Bool
	public let hasThemes: Bool
	public let hasKeyBindings: Bool
	public let hasTmProperties: Bool
	public let hasPreferences: Bool

	/// Whether any legacy data was found.
	public var hasAnyData: Bool {
		hasBundles || hasThemes || hasKeyBindings
			|| hasTmProperties || hasPreferences
	}
}

/// Basic info about a discovered bundle.
public struct BundleInfo: Sendable, Equatable {
	public let name: String
	public let uuid: String
	public let path: String
	public let contactName: String?
	public let contactEmailRot13: String?
	public let description: String?

	public init(
		name: String,
		uuid: String,
		path: String,
		contactName: String? = nil,
		contactEmailRot13: String? = nil,
		description: String? = nil,
	) {
		self.name = name
		self.uuid = uuid
		self.path = path
		self.contactName = contactName
		self.contactEmailRot13 = contactEmailRot13
		self.description = description
	}
}

/// Report from a migration scan.
public struct MigrationReport: Sendable {
	public let installation: LegacyInstallation
	public let entries: [SettingsMigrator.MigrationEntry]

	/// Number of items that were successfully migrated.
	public var migratedCount: Int {
		entries.filter(\.migrated).count
	}

	/// Number of items found.
	public var totalCount: Int {
		entries.count
	}
}
