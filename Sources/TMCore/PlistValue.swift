import Foundation

// MARK: - PlistValue

/// A strongly‑typed representation of a property list value.
///
/// Replaces the C++ `plist::any_t` (`boost::recursive_variant`).
/// Every case maps 1‑to‑1 with a Core Foundation plist type.
public indirect enum PlistValue: Sendable, Equatable {
	case bool(Bool)
	case int(Int)
	case string(String)
	case data(Data)
	case date(Date)
	case array([PlistValue])
	case dictionary(PlistDictionary)

	// MARK: Convenience initialisers

	public init(_ value: Bool) {
		self = .bool(value)
	}

	public init(_ value: Int) {
		self = .int(value)
	}

	public init(_ value: String) {
		self = .string(value)
	}

	public init(_ value: Data) {
		self = .data(value)
	}

	public init(_ value: Date) {
		self = .date(value)
	}

	public init(_ value: [PlistValue]) {
		self = .array(value)
	}

	public init(_ value: PlistDictionary) {
		self = .dictionary(value)
	}

	// MARK: Type accessors

	public var boolValue: Bool? {
		if case let .bool(v) = self { return v }
		return nil
	}

	public var intValue: Int? {
		if case let .int(v) = self { return v }
		return nil
	}

	public var stringValue: String? {
		if case let .string(v) = self { return v }
		return nil
	}

	public var dataValue: Data? {
		if case let .data(v) = self { return v }
		return nil
	}

	public var dateValue: Date? {
		if case let .date(v) = self { return v }
		return nil
	}

	public var arrayValue: [PlistValue]? {
		if case let .array(v) = self { return v }
		return nil
	}

	public var dictionaryValue: PlistDictionary? {
		if case let .dictionary(v) = self { return v }
		return nil
	}

	// MARK: Truthiness (port of plist::is_true)

	/// Returns `true` when the value is truthy.
	///
	/// Matches C++ `plist::is_true`: booleans return their value,
	/// integers ≠ 0 are true, non‑empty strings other than `"0"` are true.
	public var isTruthy: Bool {
		switch self {
		case let .bool(v): v
		case let .int(v): v != 0
		case let .string(v): v != "0" && !v.isEmpty
		default: false
		}
	}

	// MARK: Conversion helpers (port of convert_to)

	/// Attempt to coerce this value into a `Bool`.
	public func asBool() -> Bool? {
		switch self {
		case let .bool(v): v
		case let .int(v): v != 0
		case let .string(v): v != "0"
		default: nil
		}
	}

	/// Attempt to coerce this value into an `Int`.
	public func asInt() -> Int? {
		switch self {
		case let .bool(v): v ? 1 : 0
		case let .int(v): v
		case let .string(v): Int(v)
		default: nil
		}
	}

	/// Attempt to coerce this value into a `String`.
	public func asString() -> String? {
		switch self {
		case let .bool(v): v ? "1" : "0"
		case let .int(v): Swift.String(v)
		case let .string(v): v
		default: nil
		}
	}

	// MARK: Key‑path extraction (port of plist::get_key_path)

	/// Retrieve a value at the given key path (dot‑separated keys).
	///
	/// Key paths may span multiple levels of nested dictionaries.
	/// When a single key segment fails, the parser tries longer segments
	/// to support keys that themselves contain dots.
	public func valueForKeyPath(_ keyPath: String) -> PlistValue? {
		guard case let .dictionary(dict) = self else { return nil }

		let segments = keyPath.split(separator: ".", omittingEmptySubsequences: false)

		// Try progressively longer initial key segments.
		for end in 1 ... segments.count {
			let key = segments[0 ..< end].joined(separator: ".")
			if let child = dict[key] {
				if end == segments.count {
					return child
				}
				let remaining = segments[end...].joined(separator: ".")
				return child.valueForKeyPath(remaining)
			}
		}
		return nil
	}

	// MARK: Foundation bridge — from

	/// Convert a Foundation plist object (`Any`) into a `PlistValue`.
	public static func from(foundation obj: Any) -> PlistValue? {
		switch obj {
		case let b as NSNumber where CFGetTypeID(b as CFTypeRef) == CFBooleanGetTypeID():
			return .bool(b.boolValue)
		case let n as NSNumber:
			return .int(n.intValue)
		case let s as String:
			return .string(s)
		case let d as Data:
			return .data(d)
		case let dt as Date:
			return .date(dt)
		case let arr as [Any]:
			return .array(arr.compactMap { from(foundation: $0) })
		case let dict as [String: Any]:
			var result = PlistDictionary()
			for (k, v) in dict {
				if let pv = from(foundation: v) {
					result[k] = pv
				}
			}
			return .dictionary(result)
		default:
			return nil
		}
	}

	/// Convert this value back to a Foundation plist object.
	public func toFoundation() -> Any {
		switch self {
		case let .bool(v): return v as NSNumber
		case let .int(v): return v as NSNumber
		case let .string(v): return v as NSString
		case let .data(v): return v as NSData
		case let .date(v): return v as NSDate
		case let .array(arr): return arr.map { $0.toFoundation() } as NSArray
		case let .dictionary(dict):
			let result = NSMutableDictionary(capacity: dict.count)
			for (k, v) in dict {
				result[k] = v.toFoundation()
			}
			return result
		}
	}
}

// MARK: - PlistDictionary

public typealias PlistDictionary = [String: PlistValue]

// MARK: - PlistIO

/// Load and save property lists using Foundation serialization.
public enum PlistIO {
	/// The serialization format for saving.
	public enum Format {
		case binary
		case xml
	}

	/// Load a property list from a file path.
	///
	/// Returns `nil` when the file cannot be read or parsed.
	public static func load(contentsOfFile path: String) -> PlistDictionary? {
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
			return nil
		}
		return parse(data: data)?.dictionaryValue
	}

	/// Parse a property list from raw data.
	public static func parse(data: Data) -> PlistValue? {
		guard let obj = try? PropertyListSerialization.propertyList(
			from: data, options: [], format: nil,
		) else {
			return nil
		}
		return PlistValue.from(foundation: obj)
	}

	/// Parse a property list from a UTF‑8 string.
	public static func parse(string: String) -> PlistValue? {
		guard let data = string.data(using: .utf8) else { return nil }
		return parse(data: data)
	}

	/// Save a plist dictionary to a file in the given format.
	@discardableResult
	public static func save(
		_ plist: PlistValue,
		toFile path: String,
		format: Format = .binary,
	) -> Bool {
		let foundation = plist.toFoundation()
		let plFormat: PropertyListSerialization.PropertyListFormat = switch format {
		case .binary: .binary
		case .xml: .xml
		}

		guard let data = try? PropertyListSerialization.data(
			fromPropertyList: foundation,
			format: plFormat,
			options: 0,
		) else {
			return false
		}

		// Atomic write through a temporary file
		let url = URL(fileURLWithPath: path)
		do {
			try data.write(to: url, options: .atomic)
			return true
		} catch {
			return false
		}
	}
}
