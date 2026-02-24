import Foundation
import Testing
@testable import TMSearchReplace

// MARK: - SearchResultNode Tests

@Suite("SearchResultNode")
@MainActor
struct SearchResultNodeTests {
	@Test("Root node starts empty")
	func rootEmpty() {
		let root = SearchResultNode(type: .root)
		#expect(root.children.isEmpty)
		#expect(root.matchCount == 0)
		#expect(root.excludedCount == 0)
		#expect(root.allMatches.isEmpty)
	}

	@Test("File group creation")
	func fileGroup() {
		let root = SearchResultNode(type: .root)
		let group = root.fileGroup(forPath: "/tmp/test.swift", displayName: "test.swift")

		#expect(root.children.count == 1)
		if case let .file(path, name) = group.type {
			#expect(path == "/tmp/test.swift")
			#expect(name == "test.swift")
		} else {
			Issue.record("Expected file type")
		}
	}

	@Test("File group deduplication")
	func fileGroupDedup() {
		let root = SearchResultNode(type: .root)
		let group1 = root.fileGroup(forPath: "/tmp/test.swift", displayName: "test.swift")
		let group2 = root.fileGroup(forPath: "/tmp/test.swift", displayName: "test.swift")

		#expect(root.children.count == 1)
		#expect(group1.id == group2.id)
	}

	@Test("Adding matches to file group")
	func addMatches() {
		let root = SearchResultNode(type: .root)
		let group = root.fileGroup(forPath: "/tmp/test.swift", displayName: "test.swift")

		let match = DocumentMatch(
			documentID: UUID(), displayName: "test.swift",
			byteRange: 0 ..< 10, lineNumber: 0,
		)
		group.addMatch(match)

		#expect(group.children.count == 1)
		#expect(root.matchCount == 1)
	}

	@Test("Match count propagation")
	func matchCountPropagation() {
		let root = SearchResultNode(type: .root)

		let group1 = root.fileGroup(forPath: "/a.swift", displayName: "a.swift")
		group1.addMatch(DocumentMatch(documentID: UUID(), displayName: "a.swift", byteRange: 0 ..< 5))
		group1.addMatch(DocumentMatch(documentID: UUID(), displayName: "a.swift", byteRange: 10 ..< 15))

		let group2 = root.fileGroup(forPath: "/b.swift", displayName: "b.swift")
		group2.addMatch(DocumentMatch(documentID: UUID(), displayName: "b.swift", byteRange: 0 ..< 3))

		#expect(root.matchCount == 3)
		#expect(group1.matchCount == 2)
		#expect(group2.matchCount == 1)
	}

	@Test("Excluded count")
	func excludedCount() {
		let root = SearchResultNode(type: .root)
		let group = root.fileGroup(forPath: "/a.swift", displayName: "a.swift")
		group.addMatch(DocumentMatch(documentID: UUID(), displayName: "a.swift", byteRange: 0 ..< 5))
		group.addMatch(DocumentMatch(documentID: UUID(), displayName: "a.swift", byteRange: 10 ..< 15))

		group.children[0].isExcluded = true

		#expect(root.excludedCount == 1)
		#expect(root.activeMatchCount == 1)
	}

	@Test("All matches flattened")
	func allMatchesFlattened() {
		let root = SearchResultNode(type: .root)
		let group = root.fileGroup(forPath: "/a.swift", displayName: "a.swift")
		group.addMatch(DocumentMatch(documentID: UUID(), displayName: "a.swift", byteRange: 0 ..< 5))
		group.addMatch(DocumentMatch(documentID: UUID(), displayName: "a.swift", byteRange: 10 ..< 15))

		let all = root.allMatches
		#expect(all.count == 2)
	}

	@Test("File paths list")
	func filePaths() {
		let root = SearchResultNode(type: .root)
		_ = root.fileGroup(forPath: "/a.swift", displayName: "a.swift")
		_ = root.fileGroup(forPath: "/b.swift", displayName: "b.swift")

		let paths = root.filePaths
		#expect(paths.count == 2)
		#expect(paths.contains("/a.swift"))
		#expect(paths.contains("/b.swift"))
	}

	@Test("Parent reference is set")
	func parentReference() {
		let root = SearchResultNode(type: .root)
		let group = root.fileGroup(forPath: "/a.swift", displayName: "a.swift")
		group.addMatch(DocumentMatch(documentID: UUID(), displayName: "a.swift", byteRange: 0 ..< 5))

		#expect(group.parent?.id == root.id)
		#expect(group.children[0].parent?.id == group.id)
	}
}

// MARK: - ProjectSearchConfig Tests

@Suite("ProjectSearchConfig")
struct ProjectSearchConfigTests {
	@Test("Default configuration")
	func defaultConfig() {
		let config = ProjectSearchConfig(pattern: "test")
		#expect(config.pattern == "test")
		#expect(config.options == .default)
		#expect(config.searchPaths.isEmpty)
		#expect(config.includeGlobs.isEmpty)
		#expect(!config.excludeGlobs.isEmpty)
		#expect(!config.excludeDirectoryGlobs.isEmpty)
		#expect(config.followFileLinks)
		#expect(!config.followDirectoryLinks)
		#expect(!config.searchHidden)
		#expect(!config.searchBinary)
		#expect(config.maxFileSize == 10_000_000)
	}

	@Test("Custom configuration")
	func customConfig() {
		let config = ProjectSearchConfig(
			pattern: "foo",
			options: .regularExpression,
			searchPaths: ["/usr/local"],
			includeGlobs: ["*.swift"],
			searchHidden: true,
		)
		#expect(config.pattern == "foo")
		#expect(config.options == .regularExpression)
		#expect(config.searchPaths == ["/usr/local"])
		#expect(config.includeGlobs == ["*.swift"])
		#expect(config.searchHidden)
	}

	@Test("Default exclude patterns include common builds")
	func defaultExcludes() {
		let config = ProjectSearchConfig(pattern: "x")
		#expect(config.excludeDirectoryGlobs.contains(".git"))
		#expect(config.excludeDirectoryGlobs.contains("node_modules"))
		#expect(config.excludeDirectoryGlobs.contains(".build"))
	}
}

// MARK: - SearchProgress Tests

@Suite("SearchProgress")
struct SearchProgressTests {
	@Test("Default progress")
	func defaultProgress() {
		let progress = SearchProgress()
		#expect(progress.filesScanned == 0)
		#expect(progress.filesMatched == 0)
		#expect(progress.totalMatches == 0)
		#expect(progress.currentFile == nil)
		#expect(!progress.isComplete)
	}

	@Test("Progress with values")
	func withValues() {
		let progress = SearchProgress(
			filesScanned: 100,
			filesMatched: 5,
			totalMatches: 42,
			currentFile: "/tmp/test.swift",
			isComplete: true,
		)
		#expect(progress.filesScanned == 100)
		#expect(progress.filesMatched == 5)
		#expect(progress.totalMatches == 42)
		#expect(progress.currentFile == "/tmp/test.swift")
		#expect(progress.isComplete)
	}
}

// MARK: - ProjectSearchEngine Tests

@Suite("ProjectSearchEngine")
@MainActor
struct ProjectSearchEngineTests {
	@Test("Engine initializes with config")
	func initialization() {
		let config = ProjectSearchConfig(pattern: "test", searchPaths: ["/tmp"])
		let engine = ProjectSearchEngine(config: config)
		#expect(engine.config.pattern == "test")
		#expect(!engine.isCancelled)
		#expect(engine.results.matchCount == 0)
	}

	@Test("Engine can be cancelled")
	func cancel() {
		let config = ProjectSearchConfig(pattern: "test", searchPaths: ["/tmp"])
		let engine = ProjectSearchEngine(config: config)
		engine.cancel()
		#expect(engine.isCancelled)
	}

	@Test("Search in temp directory with created file")
	func searchTempFile() async throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("TMSearchTest-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		let testFile = tmpDir.appendingPathComponent("test.txt")
		try "hello world hello".write(to: testFile, atomically: true, encoding: .utf8)

		let config = ProjectSearchConfig(
			pattern: "hello",
			options: .none,
			searchPaths: [tmpDir.path],
		)
		let engine = ProjectSearchEngine(config: config)

		await withCheckedContinuation { continuation in
			engine.onComplete = { _ in
				continuation.resume()
			}
			engine.start()
		}

		#expect(engine.progress.isComplete)
		#expect(engine.progress.filesScanned >= 1)
		#expect(engine.progress.filesMatched == 1)
		#expect(engine.progress.totalMatches == 2)
		#expect(engine.results.matchCount == 2)
	}

	@Test("Search respects include globs")
	func includeGlobs() async throws {
		let tmpDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("TMSearchTest-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		try "hello".write(to: tmpDir.appendingPathComponent("test.swift"), atomically: true, encoding: .utf8)
		try "hello".write(to: tmpDir.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		let config = ProjectSearchConfig(
			pattern: "hello",
			options: .none,
			searchPaths: [tmpDir.path],
			includeGlobs: ["*.swift"],
		)
		let engine = ProjectSearchEngine(config: config)

		await withCheckedContinuation { continuation in
			engine.onComplete = { _ in continuation.resume() }
			engine.start()
		}

		#expect(engine.progress.filesMatched == 1)
		#expect(engine.results.filePaths.count == 1)
	}
}
