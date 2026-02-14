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
			name: "TMTheme",
			targets: ["TMTheme"]
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

		// MARK: - Iteration 1: Visual Shell

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
			path: "Sources/TMApp"
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
	]
)
