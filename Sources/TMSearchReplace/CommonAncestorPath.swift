import Foundation

// MARK: - Common Ancestor Path

/// Compute the longest common directory ancestor from an array of paths — equivalent to `CommonAncestor`.
///
/// If the common prefix is a file rather than a directory, the parent directory is returned.
/// Returns `nil` for empty input.
public enum CommonAncestorPath {
	/// Compute the common ancestor directory of the given paths.
	///
	/// - Parameter paths: An array of absolute paths.
	/// - Returns: The longest shared directory prefix, or `nil` when `paths` is empty.
	public static func compute(_ paths: [String]) -> String? {
		guard let first = paths.first else { return nil }
		if paths.count == 1 {
			return directoryOrParent(first)
		}

		let maxLength = paths.map(\.count).min() ?? 0
		let firstChars = Array(first.unicodeScalars)

		var lastSeparatorIndex = 0

		for i in 0 ..< maxLength {
			let ch = firstChars[i]
			var allMatch = true
			for j in 1 ..< paths.count {
				let otherChars = Array(paths[j].unicodeScalars)
				if otherChars[i] != ch {
					allMatch = false
					break
				}
			}

			if !allMatch {
				if lastSeparatorIndex > 0 {
					let endIdx = first.unicodeScalars.index(first.unicodeScalars.startIndex, offsetBy: lastSeparatorIndex)
					return String(first[first.startIndex ..< endIdx])
				}
				return "/"
			}

			if ch == "/" {
				lastSeparatorIndex = i
			}
		}

		// All characters in the shortest path match — back up to the last separator.
		if lastSeparatorIndex > 0 {
			let endIdx = first.unicodeScalars.index(first.unicodeScalars.startIndex, offsetBy: lastSeparatorIndex)
			let prefix = String(first[first.startIndex ..< endIdx])
			return directoryOrParent(prefix)
		}
		return "/"
	}

	// MARK: - Private

	private static func directoryOrParent(_ path: String) -> String {
		let fm = FileManager.default
		var isDir: ObjCBool = false
		if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
			return (path as NSString).deletingLastPathComponent
		}
		return path
	}
}
