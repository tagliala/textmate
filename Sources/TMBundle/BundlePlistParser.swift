import Foundation

/// A parser for TextMate bundle plist files (XML property list format).
///
/// TextMate bundles use XML plists for `.tmLanguage`, `.tmSnippet`,
/// `.tmCommand`, `.tmPreferences`, and `.tmTheme` files. This parser wraps
/// Foundation's `PropertyListSerialization` and provides typed accessors
/// for common TextMate plist keys.
public enum BundlePlistParser {
	/// Parse errors.
	public enum ParseError: Error, Sendable {
		case fileNotFound(String)
		case invalidPlist(String)
		case missingKey(String)
		case unexpectedType(key: String, expected: String, got: String)
	}

	/// Loads and parses a plist file at the given URL.
	///
	/// - Parameter url: File URL of the `.tm*` plist.
	/// - Returns: The top-level dictionary.
	public static func load(url: URL) throws -> [String: Any] {
		guard let data = try? Data(contentsOf: url) else {
			throw ParseError.fileNotFound(url.path)
		}
		return try parse(data: data)
	}

	/// Parses plist data into a dictionary.
	public static func parse(data: Data) throws -> [String: Any] {
		let obj: Any
		do {
			obj = try PropertyListSerialization.propertyList(
				from: data,
				options: [],
				format: nil,
			)
		} catch {
			throw ParseError.invalidPlist(error.localizedDescription)
		}

		guard let dict = obj as? [String: Any] else {
			throw ParseError.unexpectedType(
				key: "(root)",
				expected: "Dictionary",
				got: String(describing: type(of: obj)),
			)
		}
		return dict
	}

	// MARK: - Typed Accessors

	/// Extracts a required string value.
	public static func string(_ dict: [String: Any], key: String) throws -> String {
		guard let val = dict[key] else {
			throw ParseError.missingKey(key)
		}
		guard let str = val as? String else {
			throw ParseError.unexpectedType(key: key, expected: "String", got: String(describing: type(of: val)))
		}
		return str
	}

	/// Extracts an optional string value.
	public static func optionalString(_ dict: [String: Any], key: String) -> String? {
		dict[key] as? String
	}

	/// Extracts a required array of dictionaries.
	public static func arrayOfDicts(_ dict: [String: Any], key: String) throws -> [[String: Any]] {
		guard let val = dict[key] else {
			throw ParseError.missingKey(key)
		}
		guard let arr = val as? [[String: Any]] else {
			throw ParseError.unexpectedType(key: key, expected: "Array<Dict>", got: String(describing: type(of: val)))
		}
		return arr
	}

	/// Extracts an optional array of dictionaries.
	public static func optionalArrayOfDicts(_ dict: [String: Any], key: String) -> [[String: Any]]? {
		dict[key] as? [[String: Any]]
	}

	/// Extracts a required dictionary.
	public static func dictionary(_ dict: [String: Any], key: String) throws -> [String: Any] {
		guard let val = dict[key] else {
			throw ParseError.missingKey(key)
		}
		guard let d = val as? [String: Any] else {
			throw ParseError.unexpectedType(key: key, expected: "Dictionary", got: String(describing: type(of: val)))
		}
		return d
	}

	/// Extracts an optional dictionary.
	public static func optionalDictionary(_ dict: [String: Any], key: String) -> [String: Any]? {
		dict[key] as? [String: Any]
	}

	/// Extracts an optional array of strings.
	public static func optionalStringArray(_ dict: [String: Any], key: String) -> [String]? {
		dict[key] as? [String]
	}

	/// Extracts an optional integer.
	public static func optionalInt(_ dict: [String: Any], key: String) -> Int? {
		if let n = dict[key] as? Int { return n }
		if let n = dict[key] as? NSNumber { return n.intValue }
		return nil
	}

	/// Extracts an optional boolean.
	public static func optionalBool(_ dict: [String: Any], key: String) -> Bool? {
		if let b = dict[key] as? Bool { return b }
		if let n = dict[key] as? NSNumber { return n.boolValue }
		if let s = dict[key] as? String {
			switch s.lowercased() {
			case "yes", "true", "1": return true
			case "no", "false", "0": return false
			default: return nil
			}
		}
		return nil
	}
}
