import Foundation

/// Port of C++ `path` namespace (io/src/path.h, path.cc, entries.h/cc, move_path.h/cc).
/// Provides path string manipulation, resolution, file system queries, extended attributes,
/// directory scanning, and copy/move/remove operations.
public enum PathUtilities: Sendable {
	// MARK: - String Manipulation

	/// Remove `./`, `../`, and `//` from path. Preserves `..` segments
	/// that go beyond root (e.g. `/../..`), matching C++ `path::normalize` behavior.
	public static func normalize(_ path: String) -> String {
		guard !path.isEmpty else { return path }

		let isAbsolute = path.hasPrefix("/")
		let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

		var stack: [String] = []
		for component in components {
			switch component {
			case "", ".":
				if stack.isEmpty, isAbsolute {
					stack.append("")
				}
			case "..":
				if stack.count > (isAbsolute ? 1 : 0), stack.last != ".." {
					stack.removeLast()
				} else {
					stack.append(component)
				}
			default:
				stack.append(component)
			}
		}

		if stack.isEmpty {
			return isAbsolute ? "/" : "."
		}

		let result = stack.joined(separator: "/")
		return result.isEmpty ? "/" : result
	}

	/// Return the last component of the path. `/Users/me/foo.html.erb` → `foo.html.erb`
	public static func name(_ p: String) -> String {
		let path = normalize(p)
		guard let idx = path.lastIndex(of: "/") else { return path }
		return String(path[path.index(after: idx)...])
	}

	/// Return the parent directory. `/Users/me/foo.html.erb` → `/Users/me`
	public static func parent(_ p: String) -> String {
		guard p != "/" else { return p }
		return join(p, "..")
	}

	/// Strip the last extension. `/Users/me/foo.html.erb` → `/Users/me/foo.html`
	public static func stripExtension(_ p: String) -> String {
		let path = normalize(p)
		let ext = `extension`(path)
		guard !ext.isEmpty else { return path }
		return String(path.dropLast(ext.count))
	}

	/// Strip all compound extensions. `/Users/me/foo.html.erb` → `/Users/me/foo`
	public static func stripExtensions(_ p: String) -> String {
		let path = normalize(p)
		let ext = extensions(path)
		guard !ext.isEmpty else { return path }
		return String(path.dropLast(ext.count))
	}

	/// Return the last extension including dot. `/Users/me/foo.html.erb` → `.erb`
	public static func `extension`(_ p: String) -> String {
		let filename = name(normalize(p))
		guard let dotIdx = filename.lastIndex(of: ".") else { return "" }
		return String(filename[dotIdx...])
	}

	/// Return compound extensions. `/Users/me/foo.html.erb` → `.html.erb`
	/// Only merges consecutive extensions when the inner one is purely lowercase ASCII.
	public static func extensions(_ p: String) -> String {
		let filename = name(normalize(p))
		guard let dotIdx = filename.lastIndex(of: ".") else { return "" }

		if dotIdx > filename.startIndex {
			let beforeDot = filename[filename.startIndex ..< dotIdx]
			if let prevDot = beforeDot.lastIndex(of: ".") {
				let between = filename[filename.index(after: prevDot) ..< dotIdx]
				let allLowerAlpha = between.allSatisfy { $0.isLowercase && $0.isASCII }
				if allLowerAlpha {
					return String(filename[prevDot...])
				}
			}
		}
		return String(filename[dotIdx...])
	}

	/// Shell-escape a path. Special characters are backslash-escaped,
	/// newlines are wrapped in single quotes.
	public static func escape(_ path: String) -> String {
		let safeChars = Set<Character>("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.,:/@")
		var result = ""
		for scalar in path.unicodeScalars {
			let ch = Character(scalar)
			if ch == "\n" {
				result += "'\n'"
			} else if safeChars.contains(ch) || scalar.value >= 0x7F, scalar.value <= 0xFF {
				result.append(ch)
			} else {
				result += "\\\(ch)"
			}
		}
		return result
	}

	/// Split a shell-quoted string into individual "words", handling single/double
	/// quotes and backslash escaping.
	public static func unescape(_ str: String) -> [String] {
		var result = [""]
		var isEscaped = false
		var singleQuoted = false
		var doubleQuoted = false

		for ch in str {
			if !isEscaped, ch == "'" {
				singleQuoted.toggle()
			} else if !isEscaped, !singleQuoted, ch == "\"" {
				doubleQuoted.toggle()
			} else if !isEscaped, !singleQuoted, ch == "\\" {
				isEscaped = true
			} else if !isEscaped, !singleQuoted, !doubleQuoted, ch == " " {
				if !result[result.count - 1].isEmpty {
					result.append("")
				}
			} else {
				isEscaped = false
				result[result.count - 1].append(ch)
			}
		}
		return result
	}

	/// Return a score for how well `ext` matches the end of `path`.
	/// Smaller non-zero values indicate a better match; 0 means no match.
	public static func rank(_ path: String, extension ext: String) -> Int {
		guard path.count >= ext.count, path.hasSuffix(ext) else { return 0 }
		if path.count == ext.count { return ext.count }

		let charBeforeExt = path[path.index(path.endIndex, offsetBy: -ext.count - 1)]
		if charBeforeExt == "." || charBeforeExt == "_" {
			return ext.count + 1
		} else if charBeforeExt == "/" {
			return ext.count
		}
		return 0
	}

	/// Join two paths. If `path` is absolute, normalize it alone;
	/// otherwise join onto `base`.
	public static func join(_ base: String, _ path: String) -> String {
		if !path.isEmpty, path.first == "/" {
			return normalize(path)
		}
		return normalize(base + "/" + path)
	}

	/// Join an array of path components.
	public static func join(_ components: [String]) -> String {
		normalize(components.joined(separator: "/"))
	}

	/// Check whether `path` is an absolute, valid path (no `..` escaping root).
	public static func isAbsolute(_ path: String) -> Bool {
		guard !path.isEmpty, path.first == "/" else { return false }
		let p = normalize(path)
		return p != "/.." && !p.hasPrefix("/../")
	}

	/// Check whether `child` is a descendant of (or equal to) `parent`.
	public static func isChild(_ nonNormalizedChild: String, of nonNormalizedParent: String) -> Bool {
		let child = normalize(nonNormalizedChild)
		let parentPath = normalize(nonNormalizedParent)
		return child.hasPrefix(parentPath)
			&& (parentPath.count == child.count || child[child.index(child.startIndex, offsetBy: parentPath.count)] == "/")
	}

	/// Replace the home-directory prefix with `~`.
	public static func withTilde(_ p: String) -> String {
		let base = home()
		var path = normalize(p)
		if p.count > 1, p.hasSuffix("/") {
			path += "/"
		}
		if path.hasPrefix(base),
		   path.count == base.count || path[path.index(path.startIndex, offsetBy: base.count)] == "/"
		{
			return "~" + path.dropFirst(base.count)
		}
		return path
	}

	/// Compute the relative path from `base` to `path`.
	public static func relativeTo(_ p: String, base b: String) -> String? {
		guard !b.isEmpty else { return p.isEmpty ? nil : p }
		guard !p.isEmpty else { return nil }

		let path = normalize(p)
		let base = normalize(b)
		guard path.first == "/" else { return path }

		let absComponents = base.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		let relComponents = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

		var i = 0
		while i < absComponents.count, i < relComponents.count, absComponents[i] == relComponents[i] {
			i += 1
		}

		if i == 1 { // only "/" in common
			return base == "/" ? String(path.dropFirst()) : path
		}

		var result: [String] = []
		for _ in i ..< absComponents.count {
			result.append("..")
		}
		result.append(contentsOf: relComponents[i...])
		return join(result)
	}

	/// Display name for a path, optionally including `n` ancestor directory names.
	public static func displayName(_ p: String, numberOfParents n: Int = 0) -> String {
		let path = normalize(p)
		var res = systemDisplayName(path)

		if n > 0 {
			var parentComponents: [String] = []
			var current = path
			for _ in 0 ..< n {
				let p = parent(current)
				guard p != current else { break }
				parentComponents.insert(systemDisplayName(p), at: 0)
				current = p
			}
			if !parentComponents.isEmpty {
				res += " — " + parentComponents.joined(separator: "/")
			}
		}
		return res
	}

	/// For each path, compute the minimum number of parent-directory components
	/// needed to distinguish it from other paths in the list.
	public static func disambiguate(_ paths: [String]) -> [Int] {
		guard !paths.isEmpty else { return [] }
		var indices = Array(0 ..< paths.count)

		// Sort by reversed path (lexicographic on reversed characters)
		indices.sort { lhs, rhs in
			var s1 = paths[lhs].reversed().makeIterator()
			var s2 = paths[rhs].reversed().makeIterator()
			while true {
				guard let c1 = s1.next() else { return s2.next() != nil }
				guard let c2 = s2.next() else { return false }
				if c1 < c2 { return true }
				if c1 > c2 { return false }
			}
		}

		var levels = [Int](repeating: 0, count: paths.count)
		var i = 0
		while i < indices.count {
			let current = paths[indices[i]]
			var above = 0
			if i > 0 {
				above = countSharedTrailingSlashes(current, paths[indices[i - 1]])
			}

			var j = i
			while j < indices.count, paths[indices[j]] == current {
				j += 1
			}

			var below = 0
			if j < indices.count {
				below = countSharedTrailingSlashes(current, paths[indices[j]])
			}

			for k in i ..< j {
				levels[indices[k]] = max(above, below)
			}
			i = j
		}
		return levels
	}

	/// Generate a non-colliding filename. Returns `nil` if no unique name found within 500 attempts.
	public static func unique(_ requestedPath: String, suffix: String = "") -> String? {
		guard exists(requestedPath) else { return requestedPath }

		let dir = parent(requestedPath)
		var base = name(stripExtension(requestedPath))
		let ext = `extension`(requestedPath)

		// Strip existing numeric suffix like " 2"
		if let range = base.range(of: #" \d+$"#, options: .regularExpression) {
			base.removeSubrange(range)
		}
		// Strip existing copy suffix
		if !suffix.isEmpty, base.hasSuffix(suffix) {
			base.removeLast(suffix.count)
		}

		for i in 1 ..< 500 {
			let num = i > 1 ? " \(i)" : ""
			let path = join(dir, base + suffix + num + ext)
			if !exists(path) {
				return path
			}
		}
		return nil
	}

	// MARK: - Symlink & Alias Resolution

	/// Normalize path and follow all symlinks and macOS aliases.
	public static func resolve(_ path: String) -> String {
		var seen = Set<String>()
		return resolveLinks(normalize(path), resolveParent: true, seen: &seen)
	}

	/// Normalize path and follow only the leaf symlink/alias (parent may be a link).
	public static func resolveHead(_ path: String) -> String {
		var seen = Set<String>()
		return resolveLinks(normalize(path), resolveParent: false, seen: &seen)
	}

	// MARK: - Stat-based Queries

	/// Check if path exists (follows symlinks).
	public static func exists(_ path: String) -> Bool {
		access(path, F_OK) == 0
	}

	/// Check if path is readable by current user.
	public static func isReadable(_ path: String) -> Bool {
		access(path, R_OK) == 0
	}

	/// Check if path is writable by current user.
	public static func isWritable(_ path: String) -> Bool {
		access(path, W_OK) == 0
	}

	/// Check if path is executable by current user and is not a directory.
	public static func isExecutable(_ path: String) -> Bool {
		access(path, X_OK) == 0 && !isDirectory(path)
	}

	/// Check if path is a directory (resolves head symlinks).
	public static func isDirectory(_ path: String) -> Bool {
		var buf = stat()
		let resolved = resolveHead(path)
		guard lstat(resolved, &buf) == 0 else { return false }
		return (buf.st_mode & S_IFMT) == S_IFDIR
	}

	/// Check if path is on a local (non-network) volume.
	public static func isLocal(_ path: String) -> Bool {
		let url = URL(fileURLWithPath: path, isDirectory: isDirectory(path))
		guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey]) else { return false }
		return values.volumeIsLocal ?? false
	}

	/// Get the device ID for the path's filesystem.
	public static func device(_ path: String) -> dev_t {
		var buf = stat()
		guard stat(path, &buf) == 0 else { return ~0 }
		return buf.st_dev
	}

	// MARK: - Content I/O

	/// Read entire file as a string. Returns `nil` on error.
	public static func content(_ path: String) -> String? {
		guard let fd = openForReading(path) else { return nil }
		defer { close(fd) }

		var result = Data()
		var buf = [UInt8](repeating: 0, count: 8192)
		_ = fcntl(fd, F_NOCACHE, 1)
		while true {
			let len = read(fd, &buf, buf.count)
			if len <= 0 { break }
			result.append(contentsOf: buf[0 ..< len])
		}
		return String(data: result, encoding: .utf8)
	}

	/// Write data to a file (via intermediate write for safety). Returns success.
	@discardableResult
	public static func setContent(_ path: String, data: Data) -> Bool {
		guard makeDir(parent(path)) else { return false }
		do {
			try data.write(to: URL(fileURLWithPath: path), options: .atomic)
			return true
		} catch {
			return false
		}
	}

	/// Write string content to a file.
	@discardableResult
	public static func setContent(_ path: String, string: String) -> Bool {
		guard let data = string.data(using: .utf8) else { return false }
		return setContent(path, data: data)
	}

	// MARK: - Extended Attributes

	/// Get a single extended attribute value from a resolved path.
	public static func getAttr(_ p: String, name attrName: String) -> String? {
		let path = resolve(p)
		let size = getxattr(path, attrName, nil, 0, 0, 0)
		guard size > 0 else { return nil }

		var data = [UInt8](repeating: 0, count: size)
		let actual = getxattr(path, attrName, &data, size, 0, 0)
		guard actual > 0 else { return nil }
		return String(bytes: data[0 ..< actual], encoding: .utf8)
	}

	/// Set or remove an extended attribute.
	public static func setAttr(_ p: String, name attrName: String, value: String?) {
		let path = resolve(p)
		if let value {
			let bytes = Array(value.utf8)
			setxattr(path, attrName, bytes, bytes.count, 0, 0)
		} else {
			removexattr(path, attrName, 0)
		}
	}

	/// Get all extended attributes for a file.
	public static func attributes(_ path: String) -> [String: String] {
		var result: [String: String] = [:]
		guard let fd = openForReading(path) else { return result }
		defer { close(fd) }

		let listSize = flistxattr(fd, nil, 0, 0)
		guard listSize > 0 else { return result }

		var list = [CChar](repeating: 0, count: listSize)
		guard flistxattr(fd, &list, listSize, 0) == listSize else { return result }

		var i = 0
		while i < listSize {
			// Extract name from null-terminated C string in list buffer
			let nameLen = Int(strlen(&list[i]))
			let nameBytes = Array(list[i ..< i + nameLen]).map { UInt8(bitPattern: $0) }
			let nameStr = String(decoding: nameBytes, as: UTF8.self)
			let valueSize = fgetxattr(fd, nameStr, nil, 0, 0, 0)
			if valueSize > 0 {
				var valueData = [UInt8](repeating: 0, count: valueSize)
				if fgetxattr(fd, nameStr, &valueData, valueSize, 0, 0) == valueSize {
					if let value = String(bytes: valueData, encoding: .utf8) {
						result[nameStr] = value
					}
				}
			}
			i += Int(strlen(&list[i])) + 1
		}
		return result
	}

	/// Set multiple extended attributes on a file.
	@discardableResult
	public static func setAttributes(_ path: String, attributes: [String: String]) -> Bool {
		guard !attributes.isEmpty else { return true }
		guard let fd = openForReading(path) else { return false }
		defer { close(fd) }

		var success = true
		for (key, value) in attributes {
			let bytes = Array(value.utf8)
			if fsetxattr(fd, key, bytes, bytes.count, 0, 0) != 0 {
				if errno != ENOTSUP {
					success = false
				}
			}
		}
		return success
	}

	// MARK: - File Actions

	/// Create a symbolic link.
	@discardableResult
	public static func link(from: String, to: String) -> Bool {
		symlink(from, to) == 0
	}

	/// Create directory and all intermediate directories.
	@discardableResult
	public static func makeDir(_ path: String) -> Bool {
		guard !exists(path) else { return isDirectory(path) }
		makeDir(parent(path))
		mkdir(path, S_IRWXU | S_IRWXG | S_IRWXO)
		return isDirectory(path)
	}

	/// Move a file to the macOS Trash. Returns the URL of the trashed item.
	public static func moveToTrash(_ path: String) -> URL? {
		let url = URL(fileURLWithPath: path)
		var resultURL: NSURL?
		do {
			try FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
			return resultURL as URL?
		} catch {
			return nil
		}
	}

	/// Rename or copy across filesystems with parent directory creation.
	@discardableResult
	public static func renameOrCopy(from src: String, to dst: String, createParent: Bool = true) -> Bool {
		if createParent, !makeDir(parent(dst)) {
			return false
		}
		if Darwin.rename(src, dst) == 0 {
			return true
		}
		if errno == EXDEV {
			// Cross-device: fall back to copyfile
			return copyfile(src, dst, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_MOVE | COPYFILE_UNLINK)) == 0
		}
		return false
	}

	/// Duplicate a file, generating a unique name if `dst` is nil.
	public static func duplicate(_ src: String, dst: String? = nil, overwrite _: Bool = false) -> String? {
		let target: String
		if let dst {
			target = dst
		} else {
			guard let u = unique(src, suffix: " copy") else { return nil }
			target = u
		}
		guard copy(from: src, to: target) else { return nil }
		return target
	}

	// MARK: - Copy / Move / Remove

	/// Recursively copy a file or directory.
	@discardableResult
	public static func copy(from src: String, to dst: String) -> Bool {
		guard copyfile(src, dst, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC)) == 0 else {
			return false
		}
		// Recurse into directories
		var success = true
		for entry in entries(src) {
			let newSrc = join(src, entry.name)
			let newDst = join(dst, entry.name)
			switch entry.type {
			case .directory:
				if !copy(from: newSrc, to: newDst) { success = false }
			case .regular, .symlink:
				if copyfile(newSrc, newDst, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC)) != 0 {
					success = false
				}
			case .other:
				success = false
			}
		}
		return success
	}

	/// Move a file or directory, handling cross-device moves via copy + remove.
	@discardableResult
	public static func move(from src: String, to dst: String, overwrite: Bool = false) -> Bool {
		guard exists(src) else { return false }

		if exists(dst), !overwrite {
			return false
		}

		guard makeDir(parent(dst)) else { return false }

		if exists(dst) {
			guard remove(dst) else { return false }
		}

		let srcDevice = device(src)
		let dstDevice = device(parent(dst))

		if srcDevice == dstDevice {
			return Darwin.rename(src, dst) == 0
		} else {
			return copy(from: src, to: dst) && remove(src)
		}
	}

	/// Recursively remove a file or directory.
	@discardableResult
	public static func remove(_ path: String) -> Bool {
		var buf = stat()
		guard lstat(path, &buf) == 0 else { return false }

		if (buf.st_mode & S_IFMT) == S_IFDIR {
			return removeDir(path)
		}
		return unlink(path) == 0
	}

	// MARK: - Directory Scanning

	/// Result from scanning a directory.
	public struct DirectoryEntry: Sendable {
		public let name: String
		public let type: EntryType

		public enum EntryType: Sendable {
			case regular, directory, symlink, other
		}
	}

	/// List directory contents, optionally filtering with a glob pattern.
	public static func entries(_ path: String, glob globPattern: String? = nil) -> [DirectoryEntry] {
		guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
			return []
		}

		var results: [DirectoryEntry] = []
		for entryName in contents {
			// skip . and ..
			if entryName == "." || entryName == ".." { continue }

			let fullPath = join(path, entryName)

			// Apply glob filter if specified
			if let pattern = globPattern {
				let url = URL(fileURLWithPath: fullPath)
				if !matchesGlob(url.path, pattern: pattern) {
					continue
				}
			}

			var buf = stat()
			let type: DirectoryEntry.EntryType
			if lstat(fullPath, &buf) == 0 {
				let mode = buf.st_mode & S_IFMT
				if mode == S_IFDIR { type = .directory }
				else if mode == S_IFLNK { type = .symlink }
				else if mode == S_IFREG { type = .regular }
				else { type = .other }
			} else {
				type = .other
			}
			results.append(DirectoryEntry(name: entryName, type: type))
		}
		return results
	}

	// MARK: - System Directories

	/// Current user's home directory.
	public static func home() -> String {
		FileManager.default.homeDirectoryForCurrentUser.path
	}

	/// Current working directory.
	public static func cwd() -> String? {
		FileManager.default.currentDirectoryPath
	}

	/// Temporary directory, optionally creating a unique temp file.
	public static func temp(file: String? = nil, content: String? = nil) -> String {
		let base = NSTemporaryDirectory()
		guard let file else { return base }

		let progname = ProcessInfo.processInfo.processName
		let template = (base as NSString).appendingPathComponent("\(progname)_\(file)")

		if let content {
			let path = template + ".\(ProcessInfo.processInfo.processIdentifier)"
			setContent(path, string: content)
			return path
		}
		return template
	}

	/// User cache directory, optionally with a file component.
	public static func cache(file: String? = nil) -> String {
		let dirs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
		let base = dirs.first?.path ?? NSTemporaryDirectory()
		guard let file else { return base }
		let progname = ProcessInfo.processInfo.processName
		return (base as NSString).appendingPathComponent("\(progname)_\(file)")
	}

	/// User's Desktop directory.
	public static func desktop() -> String {
		home() + "/Desktop"
	}

	/// List mounted volumes (excluding hidden volumes like /dev).
	public static func volumes() -> [String] {
		let urls = FileManager.default.mountedVolumeURLs(
			includingResourceValuesForKeys: [.volumeIsLocalKey],
			options: [.skipHiddenVolumes],
		)
		return (urls ?? []).map(\.path)
	}

	// MARK: - Private Helpers

	private static func systemDisplayName(_ path: String) -> String {
		let url = URL(fileURLWithPath: path)
		if path.hasPrefix("/Volumes/") || path.hasPrefix("/home/") {
			return name(path)
		}
		guard let values = try? url.resourceValues(forKeys: [.localizedNameKey]),
		      let displayName = values.localizedName
		else {
			return name(path)
		}
		return displayName
	}

	private static func countSharedTrailingSlashes(_ s1: String, _ s2: String) -> Int {
		var it1 = s1.reversed().makeIterator()
		var it2 = s2.reversed().makeIterator()
		var slashCount = 0
		while true {
			guard let c1 = it1.next(), let c2 = it2.next() else { break }
			if c1 != c2 { break }
			if c1 == "/" { slashCount += 1 }
		}
		return slashCount
	}

	private static func resolveAlias(_ path: String) -> String {
		let url = URL(fileURLWithPath: path)
		guard let values = try? url.resourceValues(forKeys: [.isAliasFileKey]),
		      let isAlias = values.isAliasFile, isAlias
		else {
			return path
		}
		guard let resolved = try? URL(resolvingAliasFileAt: url, options: []) else {
			return path
		}
		return resolved.path
	}

	private static func resolveLinks(_ p: String, resolveParent: Bool, seen: inout Set<String>) -> String {
		if p == "/" || !isAbsolute(p) { return p }
		guard seen.insert(p).inserted else { return p }

		let parentPath = resolveParent
			? resolveLinks(parent(p), resolveParent: true, seen: &seen)
			: parent(p)
		var path = join(parentPath, name(p))

		var buf = stat()
		guard lstat(path, &buf) == 0 else { return path }

		if (buf.st_mode & S_IFMT) == S_IFLNK {
			var linkBuf = [CChar](repeating: 0, count: Int(PATH_MAX))
			let len = readlink(path, &linkBuf, Int(PATH_MAX))
			if len > 0, len < PATH_MAX {
				let linkBytes = (0 ..< len).map { UInt8(bitPattern: linkBuf[$0]) }
				let target = String(decoding: linkBytes, as: UTF8.self)
				path = resolveLinks(join(parentPath, target), resolveParent: resolveParent, seen: &seen)
			}
		} else if (buf.st_mode & S_IFMT) == S_IFREG {
			path = resolveAlias(path)
		}
		return path
	}

	private static func removeDir(_ path: String) -> Bool {
		var success = true
		for entry in entries(path) {
			let fullPath = join(path, entry.name)
			if entry.type == .directory {
				if !removeDir(fullPath) { success = false }
			} else {
				if unlink(fullPath) != 0 { success = false }
			}
		}
		if success {
			return rmdir(path) == 0
		}
		return false
	}

	private static func openForReading(_ path: String) -> Int32? {
		let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC)
		return fd == -1 ? nil : fd
	}

	/// Simple glob matching for directory entry filtering.
	private static func matchesGlob(_ path: String, pattern: String) -> Bool {
		fnmatch(pattern, path, FNM_PATHNAME) == 0
	}
}
