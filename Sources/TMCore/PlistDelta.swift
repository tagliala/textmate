import Foundation

// MARK: - PlistDelta

/// Compute and apply deltas between plist dictionaries.
///
/// Deltas track which keys changed and which were deleted,
/// including across nested dictionary structures.  Key paths
/// are dot‑separated with `\` escaping for keys that contain dots.
public enum PlistDelta {
	// MARK: Create delta

	/// Compute a delta between two plist dictionaries.
	///
	/// The result is a dictionary with:
	///  - `"isDelta"`: true
	///  - `"changed"`: flat dictionary of dotted key paths → new values
	///  - `"deleted"`: array of dotted key path strings
	///  - `"uuid"`:    preserved from `oldDict` if present
	///
	/// Nested dictionaries are diffed recursively.
	public static func createDelta(
		old oldDict: PlistDictionary,
		new newDict: PlistDictionary,
	) -> PlistDictionary {
		var changed = PlistDictionary()
		var deleted = [PlistValue]()
		deltaHelper(old: oldDict, new: newDict, changed: &changed, deleted: &deleted, path: [])

		var result = PlistDictionary()
		result["isDelta"] = .bool(true)
		if !changed.isEmpty { result["changed"] = .dictionary(changed) }
		if !deleted.isEmpty { result["deleted"] = .array(deleted) }
		if let uuid = oldDict["uuid"] { result["uuid"] = uuid }
		return result
	}

	// MARK: Merge deltas

	/// Merge a chain of plists where some may be deltas.
	///
	/// Plists are applied in reverse order (last has highest priority).
	/// Delta plists (those with `"isDelta" = true`) apply their changes
	/// and deletions on top of the accumulated result. Non‑delta plists
	/// replace the result entirely.
	///
	/// Returns an empty dictionary when no non‑delta base was found.
	public static func mergeDelta(plists: [PlistDictionary]) -> PlistDictionary {
		var result = PlistDictionary()
		var didFindNonDelta = false

		// Iterate in reverse (rightmost = highest priority)
		for plist in plists.reversed() {
			if plist["isDelta"] != nil {
				// Apply deletions
				if case let .array(deleted)? = plist["deleted"] {
					for item in deleted {
						if let keyPath = item.stringValue {
							eraseKeyPath(&result, keyPath: keyPath)
						}
					}
				}
				// Apply changes
				if case let .dictionary(changed)? = plist["changed"] {
					for (keyPath, value) in changed {
						updateKeyPath(&result, keyPath: keyPath, value: value)
					}
				}
			} else {
				result = plist
				didFindNonDelta = true
			}
		}
		return didFindNonDelta ? result : PlistDictionary()
	}
}

// MARK: - Private helpers

private extension PlistDelta {
	// MARK: Key‑path encoding

	static func encodeKey(_ key: String) -> String {
		var res = ""
		for ch in key {
			if ch == "\\" || ch == "." { res.append("\\") }
			res.append(ch)
		}
		return res
	}

	// MARK: Key‑path parsing

	static func parseKeyPath(_ keyPath: String) -> [String] {
		var result = [""]
		var escape = false
		for ch in keyPath {
			if !escape, ch == "." {
				result.append("")
			} else if !escape, ch == "\\" {
				escape = true
			} else {
				result[result.count - 1].append(ch)
				escape = false
			}
		}
		return result
	}

	// MARK: Recursive delta computation

	static func deltaHelper(
		old oldDict: PlistDictionary,
		new newDict: PlistDictionary,
		changed: inout PlistDictionary,
		deleted: inout [PlistValue],
		path: [String],
	) {
		// Find keys present in old but not in new → deleted
		var deletedKeys = Set(oldDict.keys)
		for key in newDict.keys {
			deletedKeys.remove(key)
		}

		for key in deletedKeys {
			var fullPath = path
			fullPath.append(key)
			let encoded = fullPath.map(encodeKey).joined(separator: ".")
			deleted.append(.string(encoded))
		}

		// Compare values in new
		for (key, newValue) in newDict {
			var fullPath = path
			fullPath.append(key)

			if let oldValue = oldDict[key],
			   case let .dictionary(oldSub) = oldValue,
			   case let .dictionary(newSub) = newValue
			{
				// Both are dictionaries → recurse
				deltaHelper(old: oldSub, new: newSub, changed: &changed, deleted: &deleted, path: fullPath)
			} else if oldDict[key] == nil || oldDict[key] != newValue {
				// Changed or added
				let encoded = fullPath.map(encodeKey).joined(separator: ".")
				changed[encoded] = newValue
			}
		}
	}

	// MARK: Key‑path erase

	static func eraseKeyPath(_ plist: inout PlistDictionary, keyPath: String) {
		let keys = parseKeyPath(keyPath)
		eraseKeyPathRecursive(&plist, keys: keys[...])
	}

	static func eraseKeyPathRecursive(
		_ dict: inout PlistDictionary,
		keys: ArraySlice<String>,
	) {
		guard let key = keys.first else { return }

		guard dict[key] != nil else { return }

		if keys.count == 1 {
			dict.removeValue(forKey: key)
		} else if case var .dictionary(sub)? = dict[key] {
			eraseKeyPathRecursive(&sub, keys: keys.dropFirst())
			dict[key] = .dictionary(sub)
		} else if case var .array(arr)? = dict[key] {
			let target = keys[keys.index(after: keys.startIndex)]
			arr.removeAll { $0.stringValue == target }
			dict[key] = .array(arr)
		}
	}

	// MARK: Key‑path update

	static func updateKeyPath(
		_ plist: inout PlistDictionary,
		keyPath: String,
		value: PlistValue,
	) {
		let keys = parseKeyPath(keyPath)
		updateKeyPathRecursive(&plist, keys: keys[...], value: value)
	}

	static func updateKeyPathRecursive(
		_ dict: inout PlistDictionary,
		keys: ArraySlice<String>,
		value: PlistValue,
	) {
		guard let key = keys.first else { return }

		if keys.count == 1 {
			dict[key] = value
		} else if dict[key] != nil {
			if case var .dictionary(sub) = dict[key] {
				updateKeyPathRecursive(&sub, keys: keys.dropFirst(), value: value)
				dict[key] = .dictionary(sub)
			} else if case var .array(arr) = dict[key] {
				let nextKey = keys[keys.index(after: keys.startIndex)]
				arr.append(.string(nextKey))
				dict[key] = .array(arr)
			}
		} else {
			// Build nested structure for remaining keys
			var payload = value
			for k in keys.dropFirst().reversed() {
				payload = .dictionary([k: payload])
			}
			dict[key] = payload
		}
	}
}
