#if canImport(AppKit)
import AppKit
import Testing
@testable import TMApp

@Suite("KeyBindingsLoader")
struct KeyBindingsLoaderTests {
	// MARK: - Load from Plist

	@Test("loads key bindings from a valid plist file")
	func loadValidPlist() throws {
		let plist: [String: String] = [
			"@n": "newDocument:",
			"@o": "openDocument:",
			"^x": "cut:",
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: plist,
			format: .xml,
			options: 0,
		)
		let tempURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_keybindings_\(UUID().uuidString).dict")
		try data.write(to: tempURL)
		defer { try? FileManager.default.removeItem(at: tempURL) }

		let bindings = KeyBindingsLoader.load(from: tempURL)
		#expect(bindings.count == 3)

		let keys = Set(bindings.map(\.keyString))
		#expect(keys.contains("@n"))
		#expect(keys.contains("@o"))
		#expect(keys.contains("^x"))

		let actions = Set(bindings.map(\.action))
		#expect(actions.contains("newDocument:"))
		#expect(actions.contains("openDocument:"))
		#expect(actions.contains("cut:"))
	}

	@Test("returns empty array for missing file")
	func loadMissingFile() {
		let url = URL(fileURLWithPath: "/nonexistent/path/bindings.dict")
		let bindings = KeyBindingsLoader.load(from: url)
		#expect(bindings.isEmpty)
	}

	@Test("returns empty array for invalid plist data")
	func loadInvalidData() throws {
		let tempURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_invalid_\(UUID().uuidString).dict")
		try Data("not a plist".utf8).write(to: tempURL)
		defer { try? FileManager.default.removeItem(at: tempURL) }

		let bindings = KeyBindingsLoader.load(from: tempURL)
		#expect(bindings.isEmpty)
	}

	@Test("returns empty array for wrong plist type (array instead of dict)")
	func loadWrongType() throws {
		let plist: [String] = ["@n", "@o"]
		let data = try PropertyListSerialization.data(
			fromPropertyList: plist,
			format: .xml,
			options: 0,
		)
		let tempURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_wrongtype_\(UUID().uuidString).dict")
		try data.write(to: tempURL)
		defer { try? FileManager.default.removeItem(at: tempURL) }

		let bindings = KeyBindingsLoader.load(from: tempURL)
		#expect(bindings.isEmpty)
	}

	// MARK: - Parse Event

	@Test("parseEvent produces correct modifier prefixes")
	func parseEventModifiers() {
		// ⌘N → "@n"
		let cmdN = mockEvent(chars: "n", modifiers: .command)
		#expect(KeyBindingsLoader.parseEvent(cmdN) == "@n")

		// ⌃X → "^x"
		let ctrlX = mockEvent(chars: "x", modifiers: .control)
		#expect(KeyBindingsLoader.parseEvent(ctrlX) == "^x")

		// ⌥⌘O → "~@o"
		let optCmdO = mockEvent(chars: "o", modifiers: [.option, .command])
		#expect(KeyBindingsLoader.parseEvent(optCmdO) == "~@o")

		// ⇧⌘Z → "$@z"
		let shiftCmdZ = mockEvent(chars: "z", modifiers: [.shift, .command])
		#expect(KeyBindingsLoader.parseEvent(shiftCmdZ) == "$@z")

		// ⌃⌥⇧⌘A → "^~$@a"
		let allMods = mockEvent(
			chars: "a",
			modifiers: [.control, .option, .shift, .command],
		)
		#expect(KeyBindingsLoader.parseEvent(allMods) == "^~$@a")
	}

	@Test("parseEvent with no modifiers returns just the key")
	func parseEventNoModifiers() {
		let plain = mockEvent(chars: "a", modifiers: [])
		#expect(KeyBindingsLoader.parseEvent(plain) == "a")
	}

	@Test("key binding round-trip: load and match")
	func roundTrip() throws {
		let plist: [String: String] = [
			"@s": "saveDocument:",
			"^~$@a": "selectAll:",
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: plist,
			format: .xml,
			options: 0,
		)
		let tempURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("test_roundtrip_\(UUID().uuidString).dict")
		try data.write(to: tempURL)
		defer { try? FileManager.default.removeItem(at: tempURL) }

		let bindings = KeyBindingsLoader.load(from: tempURL)

		// Simulate ⌘S event
		let cmdS = mockEvent(chars: "s", modifiers: .command)
		let parsed = KeyBindingsLoader.parseEvent(cmdS)
		let matched = bindings.first { $0.keyString == parsed }
		#expect(matched?.action == "saveDocument:")
	}

	// MARK: - Helpers

	/// Creates a mock NSEvent with the given key character and modifiers.
	private func mockEvent(chars: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
		NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: modifiers,
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: chars,
			charactersIgnoringModifiers: chars,
			isARepeat: false,
			keyCode: 0,
		)!
	}
}

#endif
