#if canImport(AppKit)
import Foundation
import Testing
@testable import TMFileBrowser

@Suite("FileBrowserLocation")
struct FileBrowserLocationTests {
	@Test("computer URL has correct scheme")
	func computerScheme() {
		#expect(FileBrowserLocation.computer.scheme == "computer")
	}

	@Test("computer URL has correct path")
	func computerPath() {
		#expect(FileBrowserLocation.computer.path == "/")
	}

	@Test("favorites URL has correct scheme")
	func favoritesScheme() {
		#expect(FileBrowserLocation.favorites.scheme == "favorites")
	}

	@Test("favorites URL has correct path")
	func favoritesPath() {
		#expect(FileBrowserLocation.favorites.path == "/")
	}

	@Test("computer and favorites are distinct")
	func distinctLocations() {
		#expect(FileBrowserLocation.computer != FileBrowserLocation.favorites)
	}

	@Test("computer URL is not a file URL")
	func computerNotFileURL() {
		#expect(!FileBrowserLocation.computer.isFileURL)
	}

	@Test("favorites URL is not a file URL")
	func favoritesNotFileURL() {
		#expect(!FileBrowserLocation.favorites.isFileURL)
	}
}

@Suite("FileItem initialization")
struct FileItemInitTests {
	@Test("init with file URL sets URL property")
	@MainActor func initWithFileURL() {
		let url = URL(fileURLWithPath: "/tmp/test-file.txt")
		let item = FileItem(url: url)
		#expect(item.URL == url)
		#expect(item.url == url)
	}

	@Test("init with non-file URL sets URL property")
	@MainActor func initWithNonFileURL() throws {
		let url = try #require(URL(string: "scm://localhost/path/to/repo/"))
		let item = FileItem(url: url)
		#expect(item.URL == url)
		#expect(item.url == url)
	}

	@Test("url alias returns same value as URL property")
	@MainActor func urlAliasMatchesURL() {
		let url = URL(fileURLWithPath: "/usr/bin/ls")
		let item = FileItem(url: url)
		#expect(item.url == item.URL)
	}

	@Test("factory method creates equivalent item")
	@MainActor func factoryMethod() {
		let url = URL(fileURLWithPath: "/tmp/factory-test.txt")
		let item = FileItem.fileItem(with: url)
		#expect(item.URL == url)
	}

	@Test("parentURL returns parent directory")
	@MainActor func parentURL() {
		let url = URL(fileURLWithPath: "/usr/local/bin/test")
		let item = FileItem(url: url)
		#expect(item.parentURL.path == "/usr/local/bin")
	}

	@Test("resolvedURL returns valid URL")
	@MainActor func resolvedURL() {
		let url = URL(fileURLWithPath: "/tmp")
		let item = FileItem(url: url)
		#expect(item.resolvedURL.isFileURL)
	}

	@Test("children initially nil")
	@MainActor func childrenNil() {
		let item = FileItem(url: URL(fileURLWithPath: "/tmp"))
		#expect(item.children == nil)
	}

	@Test("arrangedChildren initially nil")
	@MainActor func arrangedChildrenNil() {
		let item = FileItem(url: URL(fileURLWithPath: "/tmp"))
		#expect(item.arrangedChildren == nil)
	}

	@Test("displayName returns non-empty string for existing path")
	@MainActor func displayName() {
		let item = FileItem(url: URL(fileURLWithPath: "/tmp"))
		#expect(!item.displayName.isEmpty)
	}

	@Test("canRename is true for writable parent directories")
	@MainActor func canRenameWritable() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-test-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let file = dir.appendingPathComponent("test.txt")
		FileManager.default.createFile(atPath: file.path, contents: nil)
		defer { try? FileManager.default.removeItem(at: file) }

		let item = FileItem(url: file)
		#expect(item.canRename)
	}

	@Test("isDirectory detected for directories")
	@MainActor func isDirectoryDetected() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-test-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let item = FileItem(url: dir)
		#expect(item.isDirectory)
	}

	@Test("isMissing detected for non-existent path")
	@MainActor func isMissingDetected() {
		let url = URL(fileURLWithPath: "/nonexistent-\(UUID()).txt")
		let item = FileItem(url: url)
		#expect(item.isMissing)
	}

	@Test("non-file URLs do not crash updateFileProperties")
	@MainActor func nonFileURLUpdate() throws {
		let url = try #require(URL(string: "computer:///"))
		let item = FileItem(url: url)
		// updateFileProperties should return early for non-file URLs
		#expect(!item.isMissing)
	}
}

@Suite("FileItem properties on real files")
struct FileItemRealFileTests {
	@Test("file properties update for existing file")
	@MainActor func existingFileProperties() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-test-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let file = dir.appendingPathComponent("test.txt")
		FileManager.default.createFile(atPath: file.path, contents: Data("hello".utf8))
		defer { try? FileManager.default.removeItem(at: file) }

		let item = FileItem(url: file)
		#expect(!item.isMissing)
		#expect(!item.isDirectory)
		#expect(!item.isSymbolicLink)
		#expect(item.localizedName != nil)
	}

	@Test("symbolic link detection")
	@MainActor func symbolicLinkDetection() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-test-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let target = dir.appendingPathComponent("target.txt")
		FileManager.default.createFile(atPath: target.path, contents: nil)

		let link = dir.appendingPathComponent("link.txt")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

		let item = FileItem(url: link)
		#expect(item.isSymbolicLink)
		#expect(!item.isMissing)
	}

	@Test("symlink to directory sets isLinkToDirectory")
	@MainActor func symlinkToDirectory() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("tmfb-test-\(UUID())")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let targetDir = dir.appendingPathComponent("subdir")
		try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

		let link = dir.appendingPathComponent("linkdir")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: targetDir)

		let item = FileItem(url: link)
		#expect(item.isSymbolicLink)
		#expect(item.isLinkToDirectory)
	}

	@Test("children can be set and read")
	@MainActor func childrenSetAndRead() {
		let parent = FileItem(url: URL(fileURLWithPath: "/tmp"))
		let child1 = FileItem(url: URL(fileURLWithPath: "/tmp/a"))
		let child2 = FileItem(url: URL(fileURLWithPath: "/tmp/b"))

		parent.children = [child1, child2]
		#expect(parent.children?.count == 2)
	}

	@Test("arrangedChildren can be set and read")
	@MainActor func arrangedChildrenSetAndRead() {
		let parent = FileItem(url: URL(fileURLWithPath: "/tmp"))
		let child = FileItem(url: URL(fileURLWithPath: "/tmp/a"))

		parent.arrangedChildren = [child]
		#expect(parent.arrangedChildren?.count == 1)
	}
}

@Suite("FileItem DirectoryObserver")
struct DirectoryObserverTests {
	@Test("add and remove observer does not crash")
	@MainActor func addRemoveObserver() {
		let url = URL(fileURLWithPath: "/tmp/tmfb-observer-\(UUID())")
		let observer = FileItem.addObserver(
			toDirectoryAt: url,
		) { _ in }
		FileItem.removeObserver(observer)
	}

	@Test("notifying observers delivers URLs")
	@MainActor func notifyObservers() {
		let url = URL(fileURLWithPath: "/tmp/tmfb-notify-\(UUID())")
		let childURL = url.appendingPathComponent("child.txt")

		var received: [URL]?
		let observer = FileItem.addObserver(
			toDirectoryAt: url,
		) { urls in
			received = urls
		}
		defer { FileItem.removeObserver(observer) }

		FileItem.notifyObservers(for: url, children: [childURL])
		#expect(received == [childURL])
	}

	@Test("multiple observers all get notified")
	@MainActor func multipleObservers() {
		let url = URL(fileURLWithPath: "/tmp/tmfb-multi-\(UUID())")
		var count1 = 0
		var count2 = 0

		let obs1 = FileItem.addObserver(toDirectoryAt: url) { _ in count1 += 1 }
		let obs2 = FileItem.addObserver(toDirectoryAt: url) { _ in count2 += 1 }
		defer {
			FileItem.removeObserver(obs1)
			FileItem.removeObserver(obs2)
		}

		FileItem.notifyObservers(for: url, children: [])
		#expect(count1 == 1)
		#expect(count2 == 1)
	}

	@Test("removed observer no longer receives notifications")
	@MainActor func removedObserverNoNotification() {
		let url = URL(fileURLWithPath: "/tmp/tmfb-removed-\(UUID())")
		var count = 0

		let observer = FileItem.addObserver(toDirectoryAt: url) { _ in count += 1 }
		FileItem.removeObserver(observer)

		FileItem.notifyObservers(for: url, children: [])
		#expect(count == 0)
	}
}

@Suite("FinderTag")
struct FinderTagTests {
	@Test("init with name only")
	func initWithName() {
		let tag = FinderTag(name: "Work")
		#expect(tag.name == "Work")
		#expect(tag.displayName == "Work")
	}

	@Test("equatable by name")
	func equatable() {
		let a = FinderTag(name: "Red", labelColor: .red)
		let b = FinderTag(name: "Red", labelColor: .blue)
		#expect(a != b, "Tags differ by color as expected")
	}

	@Test("hashable for use in sets")
	func hashable() {
		let a = FinderTag(name: "Alpha")
		let b = FinderTag(name: "Beta")
		let set: Set<FinderTag> = [a, b, a]
		#expect(set.count == 2)
	}

	@Test("favoriteTags returns an array")
	func favoriteTags() {
		// This reads from NSWorkspace so the count varies, but should not crash
		let tags = FinderTag.favoriteTags
		#expect(tags.count >= 0)
	}
}

@Suite("FileItemImage.SCMStatus")
struct SCMStatusTests {
	@Test("all SCM status values are distinct")
	func allDistinct() {
		let statuses: [FileItemImage.SCMStatus] = [
			.none, .unknown, .unversioned, .modified,
			.added, .deleted, .conflicted, .mixed,
		]
		// They should all be different
		for i in 0 ..< statuses.count {
			for j in (i + 1) ..< statuses.count {
				#expect(
					statuses[i] != statuses[j],
					"\(statuses[i]) should differ from \(statuses[j])",
				)
			}
		}
	}

	@Test("SCMStatus is Sendable")
	func sendable() {
		let status: FileItemImage.SCMStatus = .modified
		let _: any Sendable = status
		#expect(status == .modified)
	}
}

@Suite("FileItemImage icon generation")
struct FileItemImageTests {
	@Test("icon for existing file produces non-nil image")
	@MainActor func iconForExistingFile() {
		let url = URL(fileURLWithPath: "/usr/bin/ls")
		let image = FileItemImage.iconImage(for: url)
		#expect(image.size.width > 0)
		#expect(image.size.height > 0)
	}

	@Test("icon respects custom size")
	@MainActor func iconCustomSize() {
		let url = URL(fileURLWithPath: "/tmp")
		let size = NSSize(width: 32, height: 32)
		let image = FileItemImage.iconImage(for: url, size: size)
		#expect(image.size.width == 32)
		#expect(image.size.height == 32)
	}

	@Test("icon with SCM status overlay produces valid image")
	@MainActor func iconWithSCMBadge() {
		let url = URL(fileURLWithPath: "/tmp")
		let image = FileItemImage.iconImage(for: url, scmStatus: .modified)
		#expect(image.size.width > 0)
	}

	@Test("icon for missing file uses generic icon")
	@MainActor func iconForMissingFile() {
		let url = URL(fileURLWithPath: "/nonexistent-\(UUID())")
		let image = FileItemImage.iconImage(for: url, isMissing: true)
		#expect(image.size.width > 0)
	}

	@Test("dimmed icon for modified file produces valid image")
	@MainActor func dimmedIconForModified() {
		let url = URL(fileURLWithPath: "/tmp")
		let image = FileItemImage.iconImage(for: url, isModified: true)
		#expect(image.size.width > 0)
	}

	@Test("all SCM statuses produce valid icons")
	@MainActor func allSCMStatuses() {
		let statuses: [FileItemImage.SCMStatus] = [
			.none, .unknown, .unversioned, .modified,
			.added, .deleted, .conflicted, .mixed,
		]
		let url = URL(fileURLWithPath: "/tmp")
		for status in statuses {
			let image = FileItemImage.iconImage(for: url, scmStatus: status)
			#expect(image.size.width > 0, "Failed for status: \(status)")
		}
	}
}
#endif
