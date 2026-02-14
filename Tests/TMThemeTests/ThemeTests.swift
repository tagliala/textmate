import Foundation
import Testing
@testable import TMTheme

@Suite("ThemeColor")
struct ThemeColorTests {
	@Test("parse 6-digit hex color")
	func parseHex6() {
		let color = ThemeColor(hex: "#FF8000")
		#expect(color != nil)
		#expect(color?.red == 1.0)
		#expect(color?.green == 128.0 / 255.0)
		#expect(color?.blue == 0.0)
		#expect(color?.alpha == 1.0)
	}

	@Test("parse 8-digit hex color with alpha")
	func parseHex8() {
		let color = ThemeColor(hex: "#FF800080")
		#expect(color != nil)
		#expect(color?.alpha == 128.0 / 255.0)
	}

	@Test("parse 3-digit short hex")
	func parseHex3() {
		let color = ThemeColor(hex: "#F80")
		#expect(color != nil)
		#expect(color?.red == 1.0)
		#expect(color?.green == 0x88 / 255.0)
		#expect(color?.blue == 0.0)
	}

	@Test("parse hex without hash prefix")
	func parseHexNoHash() {
		let color = ThemeColor(hex: "FF8000")
		#expect(color != nil)
		#expect(color?.red == 1.0)
	}

	@Test("parse empty string returns nil")
	func parseEmpty() {
		#expect(ThemeColor(hex: "") == nil)
	}

	@Test("parse invalid hex returns nil")
	func parseInvalid() {
		#expect(ThemeColor(hex: "#ZZZZZZ") == nil)
	}

	@Test("isDark for dark color")
	func isDark() throws {
		let dark = try #require(ThemeColor(hex: "#181818"))
		#expect(dark.isDark)
	}

	@Test("isDark for light color")
	func isLight() throws {
		let light = try #require(ThemeColor(hex: "#F8F8F8"))
		#expect(!light.isDark)
	}
}

@Suite("ThemeLoader")
struct ThemeLoaderTests {
	private func twilightPlist() -> Data {
		// Minimal valid .tmTheme plist matching Twilight structure
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
		"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
			<key>name</key>
			<string>Twilight</string>
			<key>semanticClass</key>
			<string>theme.dark.twilight</string>
			<key>uuid</key>
			<string>766026CB-703D-4610-B070-8DE07D967C5F</string>
			<key>gutterSettings</key>
			<dict>
				<key>background</key>
				<string>#2F2F31</string>
				<key>foreground</key>
				<string>#8F8F8F</string>
				<key>divider</key>
				<string>#414143</string>
				<key>selectionBackground</key>
				<string>#414143</string>
				<key>selectionBorder</key>
				<string>#484848</string>
				<key>selectionForeground</key>
				<string>#BABABA</string>
			</dict>
			<key>settings</key>
			<array>
				<dict>
					<key>settings</key>
					<dict>
						<key>background</key>
						<string>#181818</string>
						<key>caret</key>
						<string>#A7A7A7</string>
						<key>foreground</key>
						<string>#F8F8F8</string>
						<key>invisibles</key>
						<string>#FFFFFF40</string>
						<key>lineHighlight</key>
						<string>#FFFFFF08</string>
						<key>selection</key>
						<string>#DDF0FF33</string>
					</dict>
				</dict>
				<dict>
					<key>name</key>
					<string>Comment</string>
					<key>scope</key>
					<string>comment</string>
					<key>settings</key>
					<dict>
						<key>fontStyle</key>
						<string>italic</string>
						<key>foreground</key>
						<string>#5F5A60</string>
					</dict>
				</dict>
				<dict>
					<key>name</key>
					<string>Constant</string>
					<key>scope</key>
					<string>constant</string>
					<key>settings</key>
					<dict>
						<key>foreground</key>
						<string>#CF6A4C</string>
					</dict>
				</dict>
			</array>
		</dict>
		</plist>
		"""
		return Data(xml.utf8)
	}

	@Test("load theme from plist data")
	func loadFromData() throws {
		let theme = try ThemeLoader.load(from: twilightPlist())
		#expect(theme.name == "Twilight")
		#expect(theme.semanticClass == "theme.dark.twilight")
		#expect(theme.uuid == "766026CB-703D-4610-B070-8DE07D967C5F")
	}

	@Test("global settings parsed correctly")
	func globalSettings() throws {
		let theme = try ThemeLoader.load(from: twilightPlist())
		#expect(theme.isDark)
		#expect(theme.globalSettings.background.isDark)
	}

	@Test("gutter settings parsed correctly")
	func gutterSettings() throws {
		let theme = try ThemeLoader.load(from: twilightPlist())
		let gutter = theme.gutterSettings
		// #8F8F8F → 143/255
		#expect(gutter.foreground.red == 0x8F / 255.0)
		#expect(gutter.foreground.green == 0x8F / 255.0)
	}

	@Test("scope rules parsed correctly")
	func scopeRules() throws {
		let theme = try ThemeLoader.load(from: twilightPlist())
		#expect(theme.rules.count == 2)

		let comment = theme.rules[0]
		#expect(comment.scopeSelector == "comment")
		#expect(comment.name == "Comment")
		#expect(comment.isItalic == true)
		#expect(comment.isBold == nil)

		let constant = theme.rules[1]
		#expect(constant.scopeSelector == "constant")
		#expect(constant.foreground != nil)
	}

	@Test("missing settings array throws")
	func missingSettings() {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
		"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
			<key>name</key>
			<string>Empty</string>
		</dict>
		</plist>
		"""
		#expect(throws: ThemeLoadError.self) {
			try ThemeLoader.load(from: Data(xml.utf8))
		}
	}

	@Test("isDark returns true for dark theme")
	func darkTheme() throws {
		let theme = try ThemeLoader.load(from: twilightPlist())
		#expect(theme.isDark)
	}
}
