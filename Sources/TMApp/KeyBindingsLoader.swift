import AppKit
import TMDocumentWindow
import TMTheme

/// KeyBindings.dict loader — parses the TextMate key-binding plist format
/// and registers actions to selectors.
///
/// Key notation uses the same format as current TextMate:
/// - `^` = Control
/// - `~` = Option
/// - `$` = Shift
/// - `@` = Command
/// - `#` = Numeric Pad
enum KeyBindingsLoader {
	struct KeyBinding: Sendable {
		let keyString: String
		let action: String
	}

	/// Load key bindings from a `.dict` plist file.
	static func load(from url: URL) -> [KeyBinding] {
		guard let data = try? Data(contentsOf: url),
		      let plist = try? PropertyListSerialization.propertyList(
		      	from: data,
		      	options: [],
		      	format: nil,
		      ) as? [String: String]
		else {
			return []
		}

		return plist.map { KeyBinding(keyString: $0.key, action: $0.value) }
	}
}
