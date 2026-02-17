// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "TextMate",
	platforms: [
		.macOS("26.2"),
	],
	products: [
		.library(
			name: "TMCore",
			targets: ["TMCore"],
		),
		.library(
			name: "TMBundle",
			targets: ["TMBundle"],
		),
		.library(
			name: "TMSettings",
			targets: ["TMSettings"],
		),
		.library(
			name: "TMTheme",
			targets: ["TMTheme"],
		),
		.library(
			name: "TMEditor",
			targets: ["TMEditor"],
		),
		.library(
			name: "TMGrammar",
			targets: ["TMGrammar"],
		),
		.library(
			name: "TMAppKit",
			targets: ["TMAppKit"],
		),
		.library(
			name: "TMEditorUI",
			targets: ["TMEditorUI"],
		),
		.library(
			name: "TMDocumentWindow",
			targets: ["TMDocumentWindow"],
		),
		.library(
			name: "TMCompatibility",
			targets: ["TMCompatibility"],
		),
		.library(
			name: "TMBundleRuntime",
			targets: ["TMBundleRuntime"],
		),
		.library(
			name: "TMBundleUI",
			targets: ["TMBundleUI"],
		),
		.library(
			name: "TMDocumentManager",
			targets: ["TMDocumentManager"],
		),
		.library(
			name: "TMSearchReplace",
			targets: ["TMSearchReplace"],
		),
		.library(
			name: "TMSCM",
			targets: ["TMSCM"],
		),
		.library(
			name: "TMFilterList",
			targets: ["TMFilterList"],
		),
		.library(
			name: "TMPreferences",
			targets: ["TMPreferences"],
		),
		.library(
			name: "TMServices",
			targets: ["TMServices"],
		),
		.library(
			name: "TMFileBrowser",
			targets: ["TMFileBrowser"],
		),
		.library(
			name: "TMHTMLOutput",
			targets: ["TMHTMLOutput"],
		),
		.executable(
			name: "TextMateApp",
			targets: ["TMApp"],
		),
	],
	targets: [
		// MARK: - Core Layer

		.target(
			name: "TMCore",
			path: "Sources/TMCore",
		),

		.target(
			name: "TMBundle",
			path: "Sources/TMBundle",
		),

		.target(
			name: "TMSettings",
			path: "Sources/TMSettings",
		),

		// MARK: - Iteration 1: Visual Shell

		.target(
			name: "TMGrammar",
			dependencies: [
				"TMBundle",
			],
			path: "Sources/TMGrammar",
		),

		.target(
			name: "TMEditor",
			dependencies: [
				"TMCore",
			],
			path: "Sources/TMEditor",
		),

		.target(
			name: "TMTheme",
			dependencies: [
				"TMGrammar",
			],
			path: "Sources/TMTheme",
		),

		.target(
			name: "TMAppKit",
			path: "Sources/TMAppKit",
		),

		.target(
			name: "TMEditorUI",
			dependencies: [
				"TMCore",
				"TMEditor",
				"TMTheme",
			],
			path: "Sources/TMEditorUI",
		),

		.target(
			name: "TMDocumentWindow",
			dependencies: [
				"TMTheme",
				"TMAppKit",
				"TMEditorUI",
			],
			path: "Sources/TMDocumentWindow",
		),

		.executableTarget(
			name: "TMApp",
			dependencies: [
				"TMTheme",
				"TMAppKit",
				"TMDocumentWindow",
				"TMPreferences",
			],
			path: "Sources/TMApp",
			exclude: ["Info.plist"],
			resources: [
				.copy("Resources/Mac Classic.tmTheme"),
				.copy("Resources/KeyBindings.dict"),
			],
		),

		// MARK: - Compatibility Layer

		.target(
			name: "TMCompatibility",
			path: "Sources/TMCompatibility",
		),

		// MARK: - Bundle Execution System

		.target(
			name: "TMBundleRuntime",
			path: "Sources/TMBundleRuntime",
		),

		.target(
			name: "TMBundleUI",
			dependencies: [
				"TMBundleRuntime",
			],
			path: "Sources/TMBundleUI",
		),

		// MARK: - Document Management

		.target(
			name: "TMDocumentManager",
			path: "Sources/TMDocumentManager",
		),

		// MARK: - Search & Replace

		.target(
			name: "TMSearchReplace",
			path: "Sources/TMSearchReplace",
		),

		// MARK: - SCM Integration

		.target(
			name: "TMSCM",
			path: "Sources/TMSCM",
		),

		// MARK: - Filter List / Navigation

		.target(
			name: "TMFilterList",
			path: "Sources/TMFilterList",
		),

		// MARK: - Preferences & Auxiliary UI

		.target(
			name: "TMPreferences",
			path: "Sources/TMPreferences",
			linkerSettings: [
				.linkedFramework("WebKit"),
			],
		),

		// MARK: - Application Infrastructure

		.target(
			name: "TMServices",
			path: "Sources/TMServices",
			linkerSettings: [
				.linkedFramework("Security"),
			],
		),

		// MARK: - File Browser Sidebar

		.target(
			name: "TMFileBrowser",
			path: "Sources/TMFileBrowser",
			linkerSettings: [
				.linkedFramework("QuickLookUI"),
			],
		),

		// MARK: - HTML Output Browser

		.target(
			name: "TMHTMLOutput",
			dependencies: [
				"TMCompatibility",
			],
			path: "Sources/TMHTMLOutput",
			linkerSettings: [
				.linkedFramework("WebKit"),
			],
		),

		// MARK: - Test Targets

		.testTarget(
			name: "TMCoreTests",
			dependencies: ["TMCore"],
			path: "Tests/TMCoreTests",
		),

		.testTarget(
			name: "TMThemeTests",
			dependencies: ["TMTheme", "TMGrammar"],
			path: "Tests/TMThemeTests",
		),

		.testTarget(
			name: "TMDocumentWindowTests",
			dependencies: ["TMDocumentWindow"],
			path: "Tests/TMDocumentWindowTests",
		),

		.testTarget(
			name: "TMBundleTests",
			dependencies: ["TMBundle"],
			path: "Tests/TMBundleTests",
		),

		.testTarget(
			name: "TMSettingsTests",
			dependencies: ["TMSettings"],
			path: "Tests/TMSettingsTests",
		),

		.testTarget(
			name: "TMEditorTests",
			dependencies: ["TMEditor"],
			path: "Tests/TMEditorTests",
		),

		.testTarget(
			name: "TMEditorUITests",
			dependencies: ["TMEditorUI"],
			path: "Tests/TMEditorUITests",
		),

		.testTarget(
			name: "TMGrammarTests",
			dependencies: ["TMGrammar", "TMBundle"],
			path: "Tests/TMGrammarTests",
		),

		.testTarget(
			name: "TMCompatibilityTests",
			dependencies: ["TMCompatibility"],
			path: "Tests/TMCompatibilityTests",
		),

		.testTarget(
			name: "TMBundleRuntimeTests",
			dependencies: ["TMBundleRuntime"],
			path: "Tests/TMBundleRuntimeTests",
		),

		.testTarget(
			name: "TMBundleUITests",
			dependencies: ["TMBundleUI", "TMBundleRuntime"],
			path: "Tests/TMBundleUITests",
		),

		.testTarget(
			name: "TMDocumentManagerTests",
			dependencies: ["TMDocumentManager"],
			path: "Tests/TMDocumentManagerTests",
		),

		.testTarget(
			name: "TMSearchReplaceTests",
			dependencies: ["TMSearchReplace"],
			path: "Tests/TMSearchReplaceTests",
		),

		.testTarget(
			name: "TMSCMTests",
			dependencies: ["TMSCM"],
			path: "Tests/TMSCMTests",
		),

		.testTarget(
			name: "TMFilterListTests",
			dependencies: ["TMFilterList"],
			path: "Tests/TMFilterListTests",
		),

		.testTarget(
			name: "TMPreferencesTests",
			dependencies: ["TMPreferences"],
			path: "Tests/TMPreferencesTests",
		),

		.testTarget(
			name: "TMServicesTests",
			dependencies: ["TMServices"],
			path: "Tests/TMServicesTests",
		),

		.testTarget(
			name: "TMFileBrowserTests",
			dependencies: ["TMFileBrowser"],
			path: "Tests/TMFileBrowserTests",
		),

		.testTarget(
			name: "TMHTMLOutputTests",
			dependencies: ["TMHTMLOutput", "TMCompatibility"],
			path: "Tests/TMHTMLOutputTests",
		),
	],
)
