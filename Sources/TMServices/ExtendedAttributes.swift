import Foundation

// MARK: - Extended Attributes

/// Swift wrappers for POSIX extended attribute (xattr) operations.
///
/// Port of `io/path.h` `get_attr()` / `set_attr()` and inline xattr code
/// from `TMDocumentManager/TMDocument.swift`.
public enum ExtendedAttributes {
	// MARK: - Read

	/// Read an extended attribute as raw bytes.
	///
	/// - Parameters:
	///   - name: The xattr name (e.g. `"com.macromates.selectionRange"`).
	///   - path: Filesystem path.
	/// - Returns: The raw data, or `nil` if the attribute does not exist.
	public static func read(name: String, at path: String) -> Data? {
		let len = getxattr(path, name, nil, 0, 0, 0)
		guard len > 0 else { return nil }
		var buffer = [UInt8](repeating: 0, count: len)
		let actual = getxattr(path, name, &buffer, len, 0, 0)
		guard actual >= 0 else { return nil }
		return Data(buffer[..<actual])
	}

	/// Read an extended attribute as a UTF-8 string.
	public static func readString(name: String, at path: String) -> String? {
		guard let data = read(name: name, at: path) else { return nil }
		return String(data: data, encoding: .utf8)
	}

	// MARK: - Write

	/// Write raw bytes as an extended attribute.
	///
	/// - Parameters:
	///   - name: The xattr name.
	///   - data: The bytes to store.
	///   - path: Filesystem path.
	/// - Returns: `true` on success.
	@discardableResult
	public static func write(name: String, data: Data, at path: String) -> Bool {
		data.withUnsafeBytes { buffer in
			guard let base = buffer.baseAddress else { return false }
			return setxattr(path, name, base, buffer.count, 0, 0) == 0
		}
	}

	/// Write a UTF-8 string as an extended attribute.
	@discardableResult
	public static func writeString(name: String, value: String, at path: String) -> Bool {
		guard let data = value.data(using: .utf8) else { return false }
		return write(name: name, data: data, at: path)
	}

	// MARK: - Remove

	/// Remove an extended attribute.
	@discardableResult
	public static func remove(name: String, at path: String) -> Bool {
		removexattr(path, name, 0) == 0
	}

	// MARK: - List

	/// List all extended attribute names on a path.
	public static func list(at path: String) -> [String] {
		let bufferSize = listxattr(path, nil, 0, 0)
		guard bufferSize > 0 else { return [] }
		var buffer = [CChar](repeating: 0, count: bufferSize)
		let actual = listxattr(path, &buffer, bufferSize, 0)
		guard actual > 0 else { return [] }

		var names: [String] = []
		var start = 0
		for i in 0 ..< actual {
			if buffer[i] == 0 {
				let name = String(cString: Array(buffer[start ... i]))
				names.append(name)
				start = i + 1
			}
		}
		return names
	}

	// MARK: - File Descriptor Variants

	/// Read an extended attribute from an open file descriptor.
	public static func read(name: String, fd: Int32) -> Data? {
		let len = fgetxattr(fd, name, nil, 0, 0, 0)
		guard len > 0 else { return nil }
		var buffer = [UInt8](repeating: 0, count: len)
		let actual = fgetxattr(fd, name, &buffer, len, 0, 0)
		guard actual >= 0 else { return nil }
		return Data(buffer[..<actual])
	}

	/// Write raw bytes as an extended attribute on an open file descriptor.
	@discardableResult
	public static func write(name: String, data: Data, fd: Int32) -> Bool {
		data.withUnsafeBytes { buffer in
			guard let base = buffer.baseAddress else { return false }
			return fsetxattr(fd, name, base, buffer.count, 0, 0) == 0
		}
	}
}
