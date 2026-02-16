import Foundation

// MARK: - Path Utilities

/// Swift port of `Frameworks/io/src/path.h` — comprehensive path
/// manipulation, querying, and filesystem operations.
///
/// Most operations take or return plain `String` paths.  Where practical,
/// Foundation `URL` or `FileManager` APIs are used under the hood.
public enum PathUtilities {
	// MARK: - Manipulation

	/// Remove `./`, `../`, and redundant `/` from *path*.
	///
	/// Equivalent to C++ `path::normalize`.
	public static func normalize(_ path: String) -> String {
		guard !path.isEmpty else { return path }
		let url = URL(fileURLWithPath: path).standardized
		return url.path
	}

	/// Normalize and follow all symlinks / aliases.
	///
	/// Equivalent to C++ `path::resolve`.
	public static func resolve(_ path: String) -> String {
		let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
		// Also try resolving Finder aliases
		if let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutMounting]) {
			return resolved.path
		}
		return url.path
	}

	/// Normalize and resolve only the parent directory (not the final component).
	///
	/// Equivalent to C++ `path::resolve_head`.
	public static func resolveHead(_ path: String) -> String {
		let url = URL(fileURLWithPath: path)
		let parent = url.deletingLastPathComponent()
		let resolvedParent = resolve(parent.path)
		return (resolvedParent as NSString).appendingPathComponent(url.lastPathComponent)
	}

	/// Last path component.  `/Users/me/foo.html.erb` → `foo.html.erb`
	public static func name(_ path: String) -> String {
		(path as NSString).lastPathComponent
	}

	/// Parent directory.  `/Users/me/foo.html.erb` → `/Users/me`
	public static func parent(_ path: String) -> String {
		(path as NSString).deletingLastPathComponent
	}

	/// Strip the last extension.  `/Users/me/foo.html.erb` → `/Users/me/foo.html`
	public static func stripExtension(_ path: String) -> String {
		(path as NSString).deletingPathExtension
	}

	/// Strip all extensions.  `/Users/me/foo.html.erb` → `/Users/me/foo`
	public static func stripExtensions(_ path: String) -> String {
		var p = path
		while !(p as NSString).pathExtension.isEmpty {
			p = (p as NSString).deletingPathExtension
		}
		return p
	}

	/// Last extension including dot.  `/Users/me/foo.html.erb` → `.erb`
	public static func `extension`(_ path: String) -> String {
		let ext = (path as NSString).pathExtension
		return ext.isEmpty ? "" : ".\(ext)"
	}

	/// All extensions including dots.  `/Users/me/foo.html.erb` → `.html.erb`
	public static func extensions(_ path: String) -> String {
		let n = name(path)
		guard let dot = n.firstIndex(of: ".") else { return "" }
		return String(n[dot...])
	}

	/// Shell-escape a path for safe use in shell commands.
	///
	/// Wraps in single quotes and escapes internal single quotes.
	public static func escape(_ path: String) -> String {
		if path.isEmpty { return "''" }
		// If the path contains no special characters, return as-is
		let safeChars = CharacterSet.alphanumerics
			.union(CharacterSet(charactersIn: "/_.-+:@"))
		if path.unicodeScalars.allSatisfy({ safeChars.contains($0) }) {
			return path
		}
		let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
		return "'\(escaped)'"
	}

	/// Split a string of shell-escaped paths into individual paths.
	///
	/// Handles single and double quotes, backslash escapes.
	public static func unescape(_ src: String) -> [String] {
		var results: [String] = []
		var current = ""
		var iterator = src.makeIterator()
		var inSingleQuote = false
		var inDoubleQuote = false

		while let ch = iterator.next() {
			if inSingleQuote {
				if ch == "'" {
					inSingleQuote = false
				} else {
					current.append(ch)
				}
			} else if inDoubleQuote {
				if ch == "\"" {
					inDoubleQuote = false
				} else if ch == "\\" {
					if let next = iterator.next() {
						current.append(next)
					}
				} else {
					current.append(ch)
				}
			} else if ch == "'" {
				inSingleQuote = true
			} else if ch == "\"" {
				inDoubleQuote = true
			} else if ch == "\\" {
				if let next = iterator.next() {
					current.append(next)
				}
			} else if ch == " " || ch == "\t" {
				if !current.isEmpty {
					results.append(current)
					current = ""
				}
			} else {
				current.append(ch)
			}
		}
		if !current.isEmpty {
			results.append(current)
		}
		return results
	}

	/// Score how well an extension matches a path (lower is better, 0 = no match).
	///
	/// For example, `rank("foo.html.erb", ".erb")` returns 1 (exact last extension),
	/// while `rank("foo.html.erb", ".html.erb")` returns a lower (better) rank.
	public static func rank(_ path: String, extension ext: String) -> Int {
		guard !ext.isEmpty else { return 0 }
		let allExt = extensions(path)
		if allExt.isEmpty { return 0 }
		if allExt == ext { return 1 }
		if allExt.hasSuffix(ext) { return 2 }
		let lastExt = self.extension(path)
		if lastExt == ext { return 3 }
		return 0
	}

	/// Join base and relative path, normalizing the result.
	public static func join(_ base: String, _ relative: String) -> String {
		if isAbsolute(relative) { return normalize(relative) }
		return normalize((base as NSString).appendingPathComponent(relative))
	}

	/// Join multiple path components.
	public static func join(_ components: [String]) -> String {
		guard let first = components.first else { return "" }
		return components.dropFirst().reduce(first) { join($0, $1) }
	}

	/// Whether the path is absolute (starts with `/`).
	public static func isAbsolute(_ path: String) -> Bool {
		path.hasPrefix("/")
	}

	/// Whether *child* is a child path of *parent* (after normalization).
	public static func isChild(_ child: String, of parent: String) -> Bool {
		let nc = normalize(child)
		let np = normalize(parent)
		return nc.hasPrefix(np + "/") || nc == np
	}

	/// Replace the home directory prefix with `~`.
	///
	/// `/Users/me/foo` → `~/foo`
	public static func withTilde(_ path: String) -> String {
		let home = home()
		if path == home { return "~" }
		if path.hasPrefix(home + "/") {
			return "~" + path.dropFirst(home.count)
		}
		return path
	}

	/// Compute *path* relative to *base*.
	///
	/// `/Users/me/foo.html` relative to `/Users/me/Desktop` → `../foo.html`
	public static func relativeTo(_ path: String, base: String) -> String {
		let pComponents = normalize(path).split(separator: "/", omittingEmptySubsequences: true)
		let bComponents = normalize(base).split(separator: "/", omittingEmptySubsequences: true)

		var common = 0
		while common < pComponents.count, common < bComponents.count,
		      pComponents[common] == bComponents[common]
		{
			common += 1
		}

		let ups = Array(repeating: "..", count: bComponents.count - common)
		let remainder = pComponents[common...].map(String.init)
		let result = (ups + remainder).joined(separator: "/")
		return result.isEmpty ? "." : result
	}

	// MARK: - Display

	/// A display name for a path, optionally showing *numberOfParents* ancestor components.
	public static func displayName(_ path: String, numberOfParents: Int = 0) -> String {
		let url = URL(fileURLWithPath: path)
		if numberOfParents == 0 {
			return FileManager.default.displayName(atPath: path)
		}

		var components: [String] = [url.lastPathComponent]
		var current = url.deletingLastPathComponent()
		for _ in 0 ..< numberOfParents {
			let c = current.lastPathComponent
			if c == "/" { break }
			components.insert(c, at: 0)
			current = current.deletingLastPathComponent()
		}
		return components.joined(separator: "/")
	}

	/// Disambiguate a list of paths by returning the minimum number of
	/// trailing path components needed to uniquely identify each path.
	///
	/// For example, given `["/a/b/c.txt", "/x/y/c.txt", "/z.txt"]`,
	/// returns `[2, 2, 1]` — meaning the first two need 2 components
	/// (`b/c.txt` and `y/c.txt`) while the third needs only 1 (`z.txt`).
	public static func disambiguate(_ paths: [String]) -> [Int] {
		let count = paths.count
		guard count > 0 else { return [] }

		let componentArrays = paths.map { path -> [String] in
			path.split(separator: "/", omittingEmptySubsequences: true)
				.map(String.init)
				.reversed()
				.map(\.self)
		}

		var result = [Int](repeating: 1, count: count)

		for i in 0 ..< count {
			for j in (i + 1) ..< count {
				var depth = 0
				let a = componentArrays[i]
				let b = componentArrays[j]
				while depth < a.count, depth < b.count, a[depth] == b[depth] {
					depth += 1
				}
				let needed = depth + 1
				result[i] = max(result[i], needed)
				result[j] = max(result[j], needed)
			}
		}

		// Clamp to actual number of components
		for i in 0 ..< count {
			result[i] = min(result[i], componentArrays[i].count)
		}

		return result
	}

	/// Find a unique filename by appending ` 2`, ` 3`, etc. if needed.
	///
	/// `/foo/bar.txt` → `/foo/bar 2.txt` if `bar.txt` exists.
	public static func unique(_ requestedPath: String, suffix: String = "") -> String {
		let ext = `extension`(requestedPath)
		let base = ext.isEmpty ? requestedPath : stripExtension(requestedPath)

		var candidate = base + suffix + ext
		var counter = 2
		while FileManager.default.fileExists(atPath: candidate) {
			candidate = "\(base)\(suffix) \(counter)\(ext)"
			counter += 1
		}
		return candidate
	}

	// MARK: - Queries

	/// Get the device ID for a path.
	public static func device(_ path: String) -> dev_t {
		var buf = stat()
		guard stat(path, &buf) == 0 else { return 0 }
		return buf.st_dev
	}

	/// Whether the path exists on disk.
	public static func exists(_ path: String) -> Bool {
		FileManager.default.fileExists(atPath: path)
	}

	/// Whether the path is readable by the current user.
	public static func isReadable(_ path: String) -> Bool {
		FileManager.default.isReadableFile(atPath: path)
	}

	/// Whether the path is writable by the current user.
	public static func isWritable(_ path: String) -> Bool {
		FileManager.default.isWritableFile(atPath: path)
	}

	/// Whether the path is a directory.
	public static func isDirectory(_ path: String) -> Bool {
		var isDir: ObjCBool = false
		return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
	}

	/// Whether the path is executable.
	public static func isExecutable(_ path: String) -> Bool {
		FileManager.default.isExecutableFile(atPath: path)
	}

	/// Whether the path is on a local volume (not network-mounted).
	public static func isLocal(_ path: String) -> Bool {
		let url = URL(fileURLWithPath: path)
		guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey]) else {
			return true
		}
		return values.volumeIsLocal ?? true
	}

	/// Get the path for an open file descriptor.
	public static func forFileDescriptor(_ fd: Int32) -> String? {
		var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
		guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
		let nullIndex = buffer.firstIndex(of: 0) ?? buffer.count
		return String(decoding: buffer.prefix(nullIndex).map { UInt8(bitPattern: $0) }, as: UTF8.self)
	}

	// MARK: - Actions

	/// Read entire file contents as a string.
	public static func content(_ path: String) -> String? {
		try? String(contentsOfFile: path, encoding: .utf8)
	}

	/// Write string content to a file.
	@discardableResult
	public static func setContent(_ path: String, _ value: String) -> Bool {
		do {
			try value.write(toFile: path, atomically: true, encoding: .utf8)
			return true
		} catch {
			return false
		}
	}

	/// Create a symbolic link.
	@discardableResult
	public static func link(from: String, to: String) -> Bool {
		do {
			try FileManager.default.createSymbolicLink(atPath: from, withDestinationPath: to)
			return true
		} catch {
			return false
		}
	}

	/// Rename/move a file.
	@discardableResult
	public static func rename(from: String, to: String, overwrite: Bool = false) -> Bool {
		do {
			if overwrite, FileManager.default.fileExists(atPath: to) {
				try FileManager.default.removeItem(atPath: to)
			}
			try FileManager.default.moveItem(atPath: from, toPath: to)
			return true
		} catch {
			return false
		}
	}

	/// Move a file to the Trash and return the path in the trash.
	@discardableResult
	public static func moveToTrash(_ path: String) -> String? {
		let url = URL(fileURLWithPath: path)
		var resultURL: NSURL?
		do {
			try FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
			return (resultURL as URL?)?.path
		} catch {
			return nil
		}
	}

	/// Duplicate a file.  Returns the path of the copy.
	@discardableResult
	public static func duplicate(_ src: String, to dst: String? = nil, overwrite: Bool = false) -> String? {
		let destination = dst ?? unique(src, suffix: " copy")
		do {
			if overwrite, FileManager.default.fileExists(atPath: destination) {
				try FileManager.default.removeItem(atPath: destination)
			}
			try FileManager.default.copyItem(atPath: src, toPath: destination)
			return destination
		} catch {
			return nil
		}
	}

	/// Create a directory (including intermediate directories).
	@discardableResult
	public static func makeDir(_ path: String) -> Bool {
		do {
			try FileManager.default.createDirectory(
				atPath: path,
				withIntermediateDirectories: true,
				attributes: nil,
			)
			return true
		} catch {
			return false
		}
	}

	/// Rename a file, falling back to copy+delete if cross-device.
	@discardableResult
	public static func renameOrCopy(from src: String, to dst: String, createParent: Bool = true) -> Bool {
		if createParent {
			_ = makeDir(parent(dst))
		}
		if rename(from: src, to: dst) { return true }
		// Fallback: copy + remove
		guard duplicate(src, to: dst) != nil else { return false }
		try? FileManager.default.removeItem(atPath: src)
		return true
	}

	// MARK: - Global Info

	/// The current working directory.
	public static func cwd() -> String {
		FileManager.default.currentDirectoryPath
	}

	/// The user's home directory.
	public static func home() -> String {
		NSHomeDirectory()
	}

	/// A temporary file (optionally with given content).
	public static func temp(file: String? = nil, content: String? = nil) -> String {
		let dir = NSTemporaryDirectory()
		let path: String
		if let file {
			path = (dir as NSString).appendingPathComponent(file)
		} else {
			let template = (dir as NSString).appendingPathComponent("tm_XXXXXXXX")
			var buf = Array(template.utf8CString)
			guard mkstemp(&buf) != -1 else { return "" }
			let nullIndex = buf.firstIndex(of: 0) ?? buf.count
			path = String(decoding: buf.prefix(nullIndex).map { UInt8(bitPattern: $0) }, as: UTF8.self)
		}
		if let content {
			try? content.write(toFile: path, atomically: true, encoding: .utf8)
		}
		return path
	}

	/// The user's Caches directory.
	public static func cache(file: String? = nil) -> String {
		let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.path
		if let file {
			return (dir as NSString).appendingPathComponent(file)
		}
		return dir
	}

	/// The user's Desktop directory.
	public static func desktop() -> String {
		FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.path
	}

	/// List mounted volumes.
	public static func volumes() -> [String] {
		let keys: [URLResourceKey] = [.volumeNameKey]
		guard let urls = FileManager.default.mountedVolumeURLs(
			includingResourceValuesForKeys: keys,
			options: [.skipHiddenVolumes],
		) else { return [] }
		return urls.map(\.path)
	}
}
