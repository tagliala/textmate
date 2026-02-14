import Foundation

/// Resolves settings by cascading `.tm_properties` files from the home
/// directory down to the project/file directory.
///
/// Settings resolution follows TextMate's cascading model:
/// 1. Global defaults
/// 2. `~/.tm_properties`
/// 3. Each `.tm_properties` from the home directory down to the file's directory
/// 4. Section matching: unscoped → glob match → scope selector match
///
/// Modeled after TextMate's C++ `settings_for_path` function.
public enum SettingsResolver {
	/// Resolved settings for a file path.
	public typealias Settings = [String: String]

	/// Resolves settings for the given file path by cascading `.tm_properties`
	/// files from `~` down to the file's parent directory.
	///
	/// - Parameters:
	///   - filePath: Absolute path to the file.
	///   - scope: The grammar scope (e.g. `"source.swift"`). Used for
	///     scope-selector sections.
	///   - baseVariables: Initial variables to include (e.g. environment).
	/// - Returns: Resolved settings dictionary.
	public static func settingsForPath(
		_ filePath: String?,
		scope: String? = nil,
		baseVariables: Settings = [:],
	) -> Settings {
		var variables = baseVariables
		let directory = filePath.map { ($0 as NSString).deletingLastPathComponent }
			?? NSHomeDirectory()

		// Collect .tm_properties files from ~ down to the directory.
		let propertiesPaths = collectPropertiesPaths(for: directory)

		for propPath in propertiesPaths {
			guard let content = try? String(contentsOfFile: propPath, encoding: .utf8) else {
				continue
			}
			let file = TMPropertiesParser.parse(content: content, path: propPath)
			let propDir = (propPath as NSString).deletingLastPathComponent

			for section in file.sections {
				if section.names.isEmpty {
					// Unscoped section — always applies
					for assignment in section.assignments {
						variables[assignment.key] = expandVariable(assignment.value, in: variables)
					}
				} else {
					// Check if any section name matches the file or scope
					let matches = section.names.contains { name in
						matchesSection(name, filePath: filePath, directory: propDir, scope: scope)
					}
					if matches {
						for assignment in section.assignments {
							variables[assignment.key] = expandVariable(assignment.value, in: variables)
						}
					}
				}
			}
		}

		return variables
	}

	/// Returns the value of a specific setting for the given path.
	public static func get(
		_ key: String,
		forPath filePath: String?,
		scope: String? = nil,
		baseVariables: Settings = [:],
	) -> String? {
		settingsForPath(filePath, scope: scope, baseVariables: baseVariables)[key]
	}

	// MARK: - Private

	/// Collects `.tm_properties` file paths from `~` down to `directory`.
	private static func collectPropertiesPaths(for directory: String) -> [String] {
		var paths: [String] = []
		let home = NSHomeDirectory()

		// Walk from directory up to home, collecting paths
		var current = directory
		var ancestors: [String] = []
		while true {
			ancestors.append((current as NSString).appendingPathComponent(".tm_properties"))
			if current == home || current == "/" {
				break
			}
			let parent = (current as NSString).deletingLastPathComponent
			if parent == current { break }
			current = parent
		}

		// Reverse so we go from home → directory (outermost first)
		ancestors.reverse()
		for path in ancestors {
			paths.append(path)
		}

		return paths
	}

	/// Checks if a section name matches the given file path or scope.
	private static func matchesSection(
		_ sectionName: String,
		filePath: String?,
		directory: String,
		scope: String?,
	) -> Bool {
		let name = sectionName.trimmingWhitespace()
		if name.isEmpty { return false }

		// If it looks like a scope selector (starts with "source.", "text.", "attr.")
		if isScopeSelector(name) {
			if let scope {
				return scopeMatches(selector: name, scope: scope)
			}
			return false
		}

		// Otherwise treat as a glob pattern
		if let filePath {
			return globMatches(pattern: name, path: filePath, directory: directory)
		}
		return false
	}

	/// Checks if a string looks like a scope selector.
	private static func isScopeSelector(_ str: String) -> Bool {
		let rootScopes = ["text", "source", "attr"]
		for root in rootScopes {
			if str.hasPrefix(root) {
				let rest = str.dropFirst(root.count)
				if rest.isEmpty || rest.first == "." || rest.first == "," || rest.first == " " {
					return true
				}
			}
		}
		return str.isEmpty
	}

	/// Simple scope matching: checks if the scope starts with or equals the selector.
	private static func scopeMatches(selector: String, scope: String) -> Bool {
		if scope == selector { return true }
		if scope.hasPrefix(selector + ".") { return true }
		// Handle space-separated scope stack
		let components = scope.split(separator: " ")
		return components.contains { part in
			let s = String(part)
			return s == selector || s.hasPrefix(selector + ".")
		}
	}

	/// Simple glob matching for `.tm_properties` section names.
	///
	/// Supports `*` (any characters except `/`), `**` (any path), and `?`.
	private static func globMatches(pattern: String, path: String, directory: String) -> Bool {
		let fullPattern: String
		if pattern.contains("/") || pattern.contains("**") {
			// Path-relative pattern
			fullPattern = pattern
		} else {
			// Filename-only pattern — match against the filename
			let filename = (path as NSString).lastPathComponent
			return fnmatch(pattern, filename)
		}

		// Make pattern relative to the properties file's directory
		let relativePath: String = if path.hasPrefix(directory + "/") {
			String(path.dropFirst(directory.count + 1))
		} else {
			(path as NSString).lastPathComponent
		}

		return fnmatch(fullPattern, relativePath)
	}

	/// Simple fnmatch-style glob matching.
	private static func fnmatch(_ pattern: String, _ string: String) -> Bool {
		let pChars = Array(pattern)
		let sChars = Array(string)
		return fnmatchHelper(pChars, 0, sChars, 0)
	}

	private static func fnmatchHelper(
		_ pattern: [Character], _ pi: Int,
		_ string: [Character], _ si: Int,
	) -> Bool {
		var pi = pi
		var si = si

		while pi < pattern.count {
			let p = pattern[pi]

			if p == "*" {
				// Check for **
				if pi + 1 < pattern.count, pattern[pi + 1] == "*" {
					// ** matches anything including /
					pi += 2
					// Skip optional /
					if pi < pattern.count, pattern[pi] == "/" {
						pi += 1
					}
					// Try matching the rest from every position
					for i in si ... string.count {
						if fnmatchHelper(pattern, pi, string, i) {
							return true
						}
					}
					return false
				}

				// * matches anything except /
				pi += 1
				for i in si ... string.count {
					if i > si, si < string.count, string[i - 1] == "/" {
						break
					}
					if fnmatchHelper(pattern, pi, string, i) {
						return true
					}
				}
				return false
			}

			if p == "?" {
				if si >= string.count || string[si] == "/" { return false }
				pi += 1
				si += 1
				continue
			}

			if si >= string.count || p != string[si] {
				return false
			}

			pi += 1
			si += 1
		}

		return si == string.count
	}

	/// Expands `${VAR}` and `$VAR` references in a value string.
	private static func expandVariable(_ value: String, in variables: Settings) -> String {
		var result = ""
		let chars = Array(value)
		var i = 0

		while i < chars.count {
			if chars[i] == "$", i + 1 < chars.count {
				if chars[i + 1] == "{" {
					// ${VAR} or ${VAR:+text} or ${VAR:-text}
					if let (expanded, consumed) = expandBracedVariable(chars, from: i, variables: variables) {
						result += expanded
						i += consumed
						continue
					}
				} else if chars[i + 1].isLetter || chars[i + 1] == "_" {
					// $VAR
					var name = ""
					var j = i + 1
					while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" {
						name.append(chars[j])
						j += 1
					}
					if let val = variables[name] {
						result += val
					}
					i = j
					continue
				}
			}

			result.append(chars[i])
			i += 1
		}

		return result
	}

	/// Expands a `${...}` variable reference.
	private static func expandBracedVariable(
		_ chars: [Character], from start: Int, variables: Settings,
	) -> (String, Int)? {
		guard start + 2 < chars.count, chars[start] == "$", chars[start + 1] == "{" else {
			return nil
		}

		var i = start + 2
		var name = ""

		// Read variable name
		while i < chars.count, chars[i] != "}", chars[i] != ":" {
			name.append(chars[i])
			i += 1
		}

		guard i < chars.count else { return nil }

		if chars[i] == "}" {
			// Simple ${VAR}
			let val = variables[name] ?? ""
			return (val, i - start + 1)
		}

		// ${VAR:+text} or ${VAR:-text}
		if chars[i] == ":", i + 1 < chars.count {
			let modifier = chars[i + 1]
			i += 2

			var text = ""
			var depth = 1
			while i < chars.count {
				if chars[i] == "{" { depth += 1 }
				if chars[i] == "}" {
					depth -= 1
					if depth == 0 { break }
				}
				text.append(chars[i])
				i += 1
			}

			guard i < chars.count else { return nil }

			let hasValue = variables[name] != nil && !variables[name]!.isEmpty

			switch modifier {
			case "+":
				// ${VAR:+text} — use text if VAR is set
				return (hasValue ? expandVariable(text, in: variables) : "", i - start + 1)
			case "-":
				// ${VAR:-text} — use text if VAR is not set
				return (hasValue ? variables[name]! : expandVariable(text, in: variables), i - start + 1)
			default:
				return nil
			}
		}

		return nil
	}
}
