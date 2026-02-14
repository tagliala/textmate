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
	],
	targets: [
		// MARK: - Core Layer

		.target(
			name: "TMCore",
			path: "Sources/TMCore"
		),

		// MARK: - Test Targets

		.testTarget(
			name: "TMCoreTests",
			dependencies: ["TMCore"],
			path: "Tests/TMCoreTests"
		),
	]
)
