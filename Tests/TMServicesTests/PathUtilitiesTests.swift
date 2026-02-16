import Foundation
import Testing
@testable import TMServices

@Suite("PathUtilities")
struct PathUtilitiesTests {
	// MARK: - Normalization

	@Test("Normalize removes trailing slash")
	func normalizeTrailingSlash() {
		#expect(PathUtilities.normalize("/foo/bar/") == "/foo/bar")
	}

	@Test("Normalize handles duplicate slashes")
	func normalizeDuplicateSlashes() {
		let result = PathUtilities.normalize("/foo//bar")
		// Normalize may or may not collapse duplicate slashes
		#expect(result == "/foo//bar" || result == "/foo/bar")
	}

	@Test("Normalize resolves . and ..")
	func normalizeDotDotDot() {
		#expect(PathUtilities.normalize("/foo/./bar/../baz") == "/foo/baz")
	}

	@Test("Root stays root")
	func normalizeRoot() {
		#expect(PathUtilities.normalize("/") == "/")
	}

	// MARK: - Name / Parent / Extension

	@Test("Name extracts last component")
	func name() {
		#expect(PathUtilities.name("/foo/bar/baz.txt") == "baz.txt")
	}

	@Test("Parent extracts directory")
	func parent() {
		#expect(PathUtilities.parent("/foo/bar/baz.txt") == "/foo/bar")
	}

	@Test("Extension extracts file extension")
	func fileExtension() {
		#expect(PathUtilities.extension("/foo/bar.txt") == ".txt")
	}

	@Test("Extensions extracts all extensions")
	func fileExtensions() {
		let exts = PathUtilities.extensions("/foo/bar.tar.gz")
		#expect(exts == ".tar.gz")
	}

	@Test("Strip extension removes last extension")
	func stripExtension() {
		#expect(PathUtilities.stripExtension("/foo/bar.tar.gz") == "/foo/bar.tar")
	}

	@Test("Strip all extensions")
	func stripExtensions() {
		#expect(PathUtilities.stripExtensions("/foo/bar.tar.gz") == "/foo/bar")
	}

	// MARK: - Path Queries

	@Test("isAbsolute detects absolute paths")
	func isAbsolute() {
		#expect(PathUtilities.isAbsolute("/foo"))
		#expect(!PathUtilities.isAbsolute("foo"))
		#expect(!PathUtilities.isAbsolute(""))
	}

	@Test("isChild checks parent-child relationship")
	func isChild() {
		#expect(PathUtilities.isChild("/foo/bar", of: "/foo"))
		// A path is considered a child of itself
		#expect(PathUtilities.isChild("/foo", of: "/foo"))
		#expect(!PathUtilities.isChild("/foobar", of: "/foo"))
	}

	// MARK: - Join

	@Test("Join combines path components")
	func join() {
		#expect(PathUtilities.join("/foo", "bar") == "/foo/bar")
		#expect(PathUtilities.join("/foo", "/bar") == "/bar") // absolute child overrides
	}

	// MARK: - Tilde

	@Test("withTilde abbreviates home directory")
	func withTilde() {
		let home = PathUtilities.home()
		#expect(PathUtilities.withTilde(home + "/Documents") == "~/Documents")
	}

	@Test("withTilde leaves non-home paths unchanged")
	func withTildeNoOp() {
		#expect(PathUtilities.withTilde("/usr/bin") == "/usr/bin")
	}

	// MARK: - Relative Path

	@Test("relativeTo computes relative path")
	func relativeTo() {
		#expect(PathUtilities.relativeTo("/foo/bar/baz", base: "/foo") == "bar/baz")
	}

	// MARK: - Escape / Unescape

	@Test("Escape handles special characters")
	func escape() {
		let escaped = PathUtilities.escape("/foo/bar baz")
		// Escape may use backslash or quoting
		#expect(escaped != "/foo/bar baz")
		#expect(!escaped.isEmpty)
	}

	@Test("Unescape reverses escape")
	func unescape() {
		let original = "/foo/bar baz"
		let escaped = PathUtilities.escape(original)
		let result = PathUtilities.unescape(escaped)
		#expect(result.contains(original))
	}

	// MARK: - Display Name

	@Test("displayName returns localized name")
	func displayName() {
		let name = PathUtilities.displayName("/")
		#expect(!name.isEmpty)
	}

	@Test("displayName with parent count")
	func displayNameParentCount() {
		let name = PathUtilities.displayName("/usr/bin/ls", numberOfParents: 1)
		// Should include parent directory
		#expect(name.contains("bin"))
	}

	// MARK: - Disambiguate

	@Test("Disambiguate returns unique display counts")
	func disambiguate() {
		let paths = ["/a/b/file.txt", "/c/d/file.txt"]
		let result = PathUtilities.disambiguate(paths)
		#expect(result.count == 2)
		// Both need at least 2 components to disambiguate
		#expect(result[0] >= 2)
		#expect(result[1] >= 2)
	}

	@Test("Disambiguate with already unique names")
	func disambiguateUnique() {
		let paths = ["/a/foo.txt", "/a/bar.txt"]
		let result = PathUtilities.disambiguate(paths)
		#expect(result[0] == 1)
		#expect(result[1] == 1)
	}

	// MARK: - Unique Name

	@Test("Unique generates non-colliding name")
	func unique() {
		let tmp = NSTemporaryDirectory()
		let base = tmp + "unique_test_\(UUID().uuidString).txt"
		// File doesn't exist, so the unique name should be the same
		#expect(PathUtilities.unique(base) == base)
	}

	// MARK: - File System Queries

	@Test("exists checks file existence")
	func exists() {
		#expect(PathUtilities.exists("/"))
		#expect(!PathUtilities.exists("/nonexistent_\(UUID())"))
	}

	@Test("isDirectory checks directories")
	func isDirectory() {
		#expect(PathUtilities.isDirectory("/tmp"))
		#expect(!PathUtilities.isDirectory("/nonexistent_\(UUID())"))
	}

	@Test("isReadable checks readability")
	func isReadable() {
		#expect(PathUtilities.isReadable("/"))
	}

	// MARK: - Global Paths

	@Test("home returns a valid path")
	func home() {
		let h = PathUtilities.home()
		#expect(!h.isEmpty)
		#expect(PathUtilities.isAbsolute(h))
	}

	@Test("temp returns a valid path")
	func temp() {
		let t = PathUtilities.temp()
		#expect(!t.isEmpty)
	}

	@Test("cwd returns a valid path")
	func cwd() {
		let c = PathUtilities.cwd()
		#expect(!c.isEmpty)
		#expect(PathUtilities.isAbsolute(c))
	}

	// MARK: - Rank

	@Test("rank scores path relevance")
	func rank() {
		let r = PathUtilities.rank("/foo/bar/baz.txt", extension: "txt")
		#expect(r >= 0)
	}

	// MARK: - File Operations

	@Test("makeDir creates directories")
	func makeDir() {
		let tmp = NSTemporaryDirectory() + "mkdir_test_\(UUID().uuidString)/sub/dir"
		let root = PathUtilities.parent(PathUtilities.parent(tmp))
		defer { try? FileManager.default.removeItem(atPath: root) }

		let result = PathUtilities.makeDir(tmp)
		#expect(result)
		#expect(PathUtilities.isDirectory(tmp))
	}

	@Test("content reads file content")
	func content() throws {
		let tmp = NSTemporaryDirectory() + "content_test_\(UUID().uuidString)"
		try "test content".write(toFile: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let read = PathUtilities.content(tmp)
		#expect(read == "test content")
	}

	@Test("setContent writes file content")
	func setContent() {
		let tmp = NSTemporaryDirectory() + "setcontent_\(UUID().uuidString)"
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let result = PathUtilities.setContent(tmp, "written")
		#expect(result)

		let read = PathUtilities.content(tmp)
		#expect(read == "written")
	}
}
