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
			targets: ["TMCore"]
		),
		.library(
			name: "TMBundle",
			targets: ["TMBundle"]
		),
		.library(
			name: "TMSettings",
			targets: ["TMSettings"]
		),
		.library(
			name: "TMTheme",
			targets: ["TMTheme"]
		),
		.library(
			name: "TMEditor",
			targets: ["TMEditor"]
		),
		.library(
			name: "TMAppKit",
			targets: ["TMAppKit"]
		),
		.library(
			name: "TMDocumentWindow",
			targets: ["TMDocumentWindow"]
		),
		.executable(
			name: "TextMateApp",
			targets: ["TMApp"]
		),
	],
	targets: [
		// MARK: - Core Layer

		.target(
			name: "TMCore",
			path: "Sources/TMCore"
		),

		.target(
			name: "TMBundle",
			path: "Sources/TMBundle"
		),

		.target(
			name: "TMSettings",
			path: "Sources/TMSettings"
		),

		// MARK: - Iteration 1: Visual Shell

		.target(
			name: "TMEditor",
			dependencies: [
				"TMCore",
			],
			path: "Sources/TMEditor"
		),

		.target(
			name: "TMTheme",
			path: "Sources/TMTheme"
		),

		.target(
			name: "TMAppKit",
			path: "Sources/TMAppKit"
		),

		.target(
			name: "TMDocumentWindow",
			dependencies: [
				"TMTheme",
				"TMAppKit",
			],
			path: "Sources/TMDocumentWindow"
		),

		.executableTarget(
			name: "TMApp",
			dependencies: [
				"TMTheme",
				"TMAppKit",
				"TMDocumentWindow",
			],
			path: "Sources/TMApp",
			exclude: ["Info.plist"],
			resources: [
				.copy("Resources/Mac Classic.tmTheme"),
				.copy("Resources/KeyBindings.dict"),
			]
		),

		// MARK: - Test Targets

		.testTarget(
			name: "TMCoreTests",
			dependencies: ["TMCore"],
			path: "Tests/TMCoreTests"
		),

		.testTarget(
			name: "TMThemeTests",
			dependencies: ["TMTheme"],
			path: "Tests/TMThemeTests"
		),

		.testTarget(
			name: "TMDocumentWindowTests",
			dependencies: ["TMDocumentWindow"],
			path: "Tests/TMDocumentWindowTests"
		),

		.testTarget(
			name: "TMBundleTests",
			dependencies: ["TMBundle"],
			path: "Tests/TMBundleTests"
		),

		.testTarget(
			name: "TMSettingsTests",
			dependencies: ["TMSettings"],
			path: "Tests/TMSettingsTests"
		),

		.testTarget(
			name: "TMEditorTests",
			dependencies: ["TMEditor"],
			path: "Tests/TMEditorTests"
		),
	]
)
