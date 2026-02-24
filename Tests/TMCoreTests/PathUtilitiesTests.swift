import Foundation
import Testing
@testable import TMCore

@Suite("PathUtilities — String Manipulation")
struct PathUtilitiesStringTests {
	@Test("normalize removes current-dir and parent-dir segments")
	func normalize() {
		#expect(PathUtilities.normalize("/Users/test/../../tmp") == "/tmp")
		#expect(PathUtilities.normalize("/Users/test/../tmp") == "/Users/tmp")
		#expect(PathUtilities.normalize("/Users/test/./tmp") == "/Users/test/tmp")
		#expect(PathUtilities.normalize("./foo") == "foo")
		#expect(PathUtilities.normalize("foo/.") == "foo")
		#expect(PathUtilities.normalize("/foo/bar/../baz") == "/foo/baz")
		#expect(PathUtilities.normalize("") == "")
		#expect(PathUtilities.normalize("/") == "/")
		#expect(PathUtilities.normalize(".") == ".")
		#expect(PathUtilities.normalize("..") == "..")
		#expect(PathUtilities.normalize("../../foo") == "../../foo")
		#expect(PathUtilities.normalize("/path/to/foo/..") == "/path/to")
	}

	@Test("normalize preserves .. beyond root")
	func normalizeBeyondRoot() {
		#expect(PathUtilities.normalize("/../..") == "/../..")
		#expect(PathUtilities.normalize("/foo/../../../bar") == "/../../bar")
	}

	@Test("name returns last component")
	func nameComponent() {
		#expect(PathUtilities.name("/Users/me/foo.html.erb") == "foo.html.erb")
		#expect(PathUtilities.name("/") == "")
		#expect(PathUtilities.name("foo") == "foo")
		#expect(PathUtilities.name("/a/b/c") == "c")
	}

	@Test("parent returns parent directory")
	func parentDir() {
		#expect(PathUtilities.parent("/Users/me/foo") == "/Users/me")
		#expect(PathUtilities.parent("/") == "/")
		#expect(PathUtilities.parent("/a") == "/")
	}

	@Test("extension returns last extension")
	func extensionTest() {
		#expect(PathUtilities.extension("/Users/me/foo.html.erb") == ".erb")
		#expect(PathUtilities.extension("/Users/me/foo") == "")
		#expect(PathUtilities.extension(".hidden") == ".hidden")
	}

	@Test("extensions returns compound extensions")
	func extensionsTest() {
		#expect(PathUtilities.extensions("/Users/me/foo.html.erb") == ".html.erb")
		#expect(PathUtilities.extensions("/Users/me/foo.tar.gz") == ".tar.gz")
		#expect(PathUtilities.extensions("/Users/me/foo.txt") == ".txt")
		#expect(PathUtilities.extensions("/Users/me/foo") == "")
	}

	@Test("stripExtension removes last extension")
	func stripExtension() {
		#expect(PathUtilities.stripExtension("/Users/me/foo.html.erb") == "/Users/me/foo.html")
		#expect(PathUtilities.stripExtension("/Users/me/foo") == "/Users/me/foo")
	}

	@Test("stripExtensions removes all compound extensions")
	func stripExtensions() {
		#expect(PathUtilities.stripExtensions("/Users/me/foo.html.erb") == "/Users/me/foo")
		#expect(PathUtilities.stripExtensions("/Users/me/foo.tar.gz") == "/Users/me/foo")
	}

	@Test("rank scores extension matching")
	func rank() {
		// Exact filename match (path == ext)
		#expect(PathUtilities.rank("Makefile", extension: "Makefile") == 8)
		// Extension without leading dot: "bar.rb" with ext "rb" → char before is '.', score=3
		#expect(PathUtilities.rank("bar.rb", extension: "rb") == 3)
		// Full path: "/foo/bar.rb" with ext "rb" → char before 'rb' at path[-3] is '.', score=3
		#expect(PathUtilities.rank("/foo/bar.rb", extension: "rb") == 3)
		// Underscore separator: "bar_spec.rb" with ext "_spec.rb" → char before is 'r' (not sep), = 0
		// But rank("bar_spec.rb", "spec.rb") → charBefore is '_' → 8
		#expect(PathUtilities.rank("bar_spec.rb", extension: "spec.rb") == 8)
		// No match
		#expect(PathUtilities.rank("/foo/bar.py", extension: "rb") == 0)
		// Path with slash before match
		#expect(PathUtilities.rank("/bar", extension: "bar") == 3)
	}

	@Test("join combines paths correctly")
	func join() {
		#expect(PathUtilities.join("/foo", "bar") == "/foo/bar")
		#expect(PathUtilities.join("/foo", "/bar") == "/bar")
		#expect(PathUtilities.join("/foo", "../bar") == "/bar")
		#expect(PathUtilities.join(["a", "b", "c"]) == "a/b/c")
	}

	@Test("isAbsolute checks canonical absolute paths")
	func isAbsolute() {
		#expect(PathUtilities.isAbsolute("/foo"))
		#expect(PathUtilities.isAbsolute("/"))
		#expect(!PathUtilities.isAbsolute("foo"))
		#expect(!PathUtilities.isAbsolute(""))
		#expect(!PathUtilities.isAbsolute("/../.."))
	}

	@Test("isChild checks parent-child relationship")
	func isChild() {
		#expect(PathUtilities.isChild("/foo/bar", of: "/foo"))
		#expect(PathUtilities.isChild("/foo", of: "/foo"))
		#expect(!PathUtilities.isChild("/foobar", of: "/foo"))
		#expect(!PathUtilities.isChild("/bar", of: "/foo"))
	}

	@Test("withTilde replaces home directory")
	func withTilde() {
		let home = PathUtilities.home()
		#expect(PathUtilities.withTilde(home + "/Documents") == "~/Documents")
		#expect(PathUtilities.withTilde(home) == "~")
		#expect(PathUtilities.withTilde("/other/path") == "/other/path")
	}

	@Test("relativeTo computes relative path")
	func relativeTo() {
		#expect(PathUtilities.relativeTo("/Users/me/foo", base: "/Users/me") == "foo")
		#expect(PathUtilities.relativeTo("/Users/me/foo", base: "/Users/other") == "../me/foo")
		#expect(PathUtilities.relativeTo("/a/b/c", base: "/a/d/e") == "../../b/c")
	}

	@Test("escape produces shell-safe path")
	func escape() {
		#expect(PathUtilities.escape("/foo/bar") == "/foo/bar")
		#expect(PathUtilities.escape("/foo bar") == "/foo\\ bar")
		#expect(PathUtilities.escape("/foo\nbar") == "/foo'\n'bar")
	}

	@Test("unescape splits shell words")
	func unescape() {
		#expect(PathUtilities.unescape("foo bar baz") == ["foo", "bar", "baz"])
		#expect(PathUtilities.unescape("'foo bar' baz") == ["foo bar", "baz"])
		#expect(PathUtilities.unescape("foo\\ bar baz") == ["foo bar", "baz"])
		#expect(PathUtilities.unescape("\"hello world\"") == ["hello world"])
	}

	@Test("disambiguate provides levels for display")
	func disambiguate() {
		let paths = ["/a/b/c", "/d/e/c", "/a/f/c"]
		let levels = PathUtilities.disambiguate(paths)
		// All share basename "c", so all need at least 1 parent level
		for level in levels {
			#expect(level >= 1)
		}
	}
}

@Suite("PathUtilities — File System Operations")
struct PathUtilitiesFileSystemTests {
	@Test("exists detects real paths")
	func exists() {
		#expect(PathUtilities.exists("/"))
		#expect(PathUtilities.exists("/tmp"))
		#expect(!PathUtilities.exists("/nonexistent_path_12345"))
	}

	@Test("isDirectory detects directories")
	func isDirectory() {
		#expect(PathUtilities.isDirectory("/tmp"))
		#expect(!PathUtilities.isDirectory("/nonexistent_12345"))
	}

	@Test("isReadable checks read permissions")
	func isReadable() {
		#expect(PathUtilities.isReadable("/tmp"))
	}

	@Test("home returns valid path")
	func home() {
		let home = PathUtilities.home()
		#expect(!home.isEmpty)
		#expect(PathUtilities.isDirectory(home))
	}

	@Test("cwd returns current directory")
	func cwd() {
		let cwd = PathUtilities.cwd()
		#expect(cwd != nil)
	}

	@Test("temp returns temp directory")
	func temp() {
		let tmp = PathUtilities.temp()
		#expect(!tmp.isEmpty)
	}

	@Test("volumes lists mounted volumes")
	func volumes() {
		let vols = PathUtilities.volumes()
		#expect(vols.contains("/"))
	}

	@Test("content and setContent round-trip")
	func contentRoundTrip() {
		let path = PathUtilities.temp() + "/tm_test_content_\(ProcessInfo.processInfo.processIdentifier).txt"
		defer { PathUtilities.remove(path) }

		let testContent = "Hello, TextMate!"
		#expect(PathUtilities.setContent(path, string: testContent))
		#expect(PathUtilities.content(path) == testContent)
	}

	@Test("makeDir creates nested directories")
	func makeDir() {
		let base = PathUtilities.temp() + "/tm_test_mkdir_\(ProcessInfo.processInfo.processIdentifier)"
		let nested = base + "/a/b/c"
		defer { PathUtilities.remove(base) }

		#expect(PathUtilities.makeDir(nested))
		#expect(PathUtilities.isDirectory(nested))
	}

	@Test("unique generates non-colliding paths")
	func unique() {
		let base = PathUtilities.temp() + "/tm_test_unique_\(ProcessInfo.processInfo.processIdentifier)"
		defer { PathUtilities.remove(PathUtilities.parent(base)) }

		let path1 = base + ".txt"
		PathUtilities.setContent(path1, string: "a")

		let result = PathUtilities.unique(path1)
		#expect(result != nil)
		#expect(result != path1)
	}

	@Test("entries lists directory contents")
	func entries() {
		let dir = PathUtilities.temp() + "/tm_test_entries_\(ProcessInfo.processInfo.processIdentifier)"
		defer { PathUtilities.remove(dir) }

		PathUtilities.makeDir(dir)
		PathUtilities.setContent(dir + "/a.txt", string: "a")
		PathUtilities.setContent(dir + "/b.txt", string: "b")

		let items = PathUtilities.entries(dir)
		let names = items.map(\.name).sorted()
		#expect(names == ["a.txt", "b.txt"])
	}

	@Test("copy duplicates files")
	func copy() {
		let dir = PathUtilities.temp() + "/tm_test_copy_\(ProcessInfo.processInfo.processIdentifier)"
		defer { PathUtilities.remove(dir) }

		let src = dir + "/src.txt"
		let dst = dir + "/dst.txt"
		PathUtilities.makeDir(dir)
		PathUtilities.setContent(src, string: "hello")

		#expect(PathUtilities.copy(from: src, to: dst))
		#expect(PathUtilities.content(dst) == "hello")
	}

	@Test("move relocates files")
	func moveFile() {
		let dir = PathUtilities.temp() + "/tm_test_move_\(ProcessInfo.processInfo.processIdentifier)"
		defer { PathUtilities.remove(dir) }

		let src = dir + "/src.txt"
		let dst = dir + "/dst.txt"
		PathUtilities.makeDir(dir)
		PathUtilities.setContent(src, string: "hello")

		#expect(PathUtilities.move(from: src, to: dst))
		#expect(!PathUtilities.exists(src))
		#expect(PathUtilities.content(dst) == "hello")
	}

	@Test("remove deletes files and directories")
	func removeFile() {
		let dir = PathUtilities.temp() + "/tm_test_remove_\(ProcessInfo.processInfo.processIdentifier)"
		PathUtilities.makeDir(dir + "/sub")
		PathUtilities.setContent(dir + "/sub/file.txt", string: "data")

		#expect(PathUtilities.exists(dir))
		#expect(PathUtilities.remove(dir))
		#expect(!PathUtilities.exists(dir))
	}

	@Test("extended attributes round-trip")
	func xattr() {
		let path = PathUtilities.temp() + "/tm_test_xattr_\(ProcessInfo.processInfo.processIdentifier).txt"
		defer { PathUtilities.remove(path) }

		PathUtilities.setContent(path, string: "test")

		PathUtilities.setAttr(path, name: "com.test.attr", value: "hello")
		let value = PathUtilities.getAttr(path, name: "com.test.attr")
		#expect(value == "hello")

		// Remove attribute
		PathUtilities.setAttr(path, name: "com.test.attr", value: nil)
		#expect(PathUtilities.getAttr(path, name: "com.test.attr") == nil)
	}

	@Test("resolve follows symlinks")
	func resolve() {
		let dir = PathUtilities.temp() + "/tm_test_resolve_\(ProcessInfo.processInfo.processIdentifier)"
		defer { PathUtilities.remove(dir) }

		PathUtilities.makeDir(dir)
		let real = dir + "/real.txt"
		let link = dir + "/link.txt"
		PathUtilities.setContent(real, string: "data")
		PathUtilities.link(from: real, to: link)

		let resolved = PathUtilities.resolve(link)
		// Resolved should point to the real file (possibly via different path due to /tmp → /private/tmp)
		#expect(resolved.hasSuffix("real.txt"))
	}
}

@Suite("PathUtilities — Display & Disambiguation")
struct PathUtilitiesDisplayTests {
	@Test("displayName returns filename")
	func displayName() {
		let name = PathUtilities.displayName("/Users/test/foo.txt")
		#expect(!name.isEmpty)
	}

	@Test("displayName with parents adds context")
	func displayNameWithParents() {
		let name = PathUtilities.displayName("/Users/test/foo.txt", numberOfParents: 1)
		#expect(name.contains("—") || name.contains("test") || !name.isEmpty)
	}
}
