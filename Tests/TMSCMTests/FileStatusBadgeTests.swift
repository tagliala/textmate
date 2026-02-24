import Foundation
import Testing
@testable import TMSCM

// MARK: - FileStatusBadge Tests

@Suite("FileStatusBadge")
struct FileStatusBadgeTests {
	@Test("Modified badge is visible")
	func modifiedVisible() {
		let badge = FileStatusBadge(status: .modified)
		#expect(badge.isVisible)
		#expect(badge.text == "M")
		#expect(!badge.colorName.isEmpty)
		#expect(!badge.symbolName.isEmpty)
	}

	@Test("Added badge")
	func addedBadge() {
		let badge = FileStatusBadge(status: .added)
		#expect(badge.isVisible)
		#expect(badge.text == "A")
		#expect(badge.symbolName == "plus.circle.fill")
	}

	@Test("Deleted badge")
	func deletedBadge() {
		let badge = FileStatusBadge(status: .deleted)
		#expect(badge.isVisible)
		#expect(badge.text == "D")
		#expect(badge.symbolName == "minus.circle.fill")
	}

	@Test("Conflicted badge")
	func conflictedBadge() {
		let badge = FileStatusBadge(status: .conflicted)
		#expect(badge.isVisible)
		#expect(badge.text == "C")
		#expect(badge.symbolName == "exclamationmark.triangle.fill")
	}

	@Test("Clean file is not visible")
	func cleanNotVisible() {
		let badge = FileStatusBadge(status: .none)
		#expect(!badge.isVisible)
		#expect(badge.colorName.isEmpty)
	}

	@Test("Unknown file is not visible")
	func unknownNotVisible() {
		let badge = FileStatusBadge(status: .unknown)
		#expect(!badge.isVisible)
	}

	@Test("Unversioned badge")
	func unversionedBadge() {
		let badge = FileStatusBadge(status: .unversioned)
		#expect(badge.isVisible)
		#expect(badge.text == "?")
	}

	@Test("Mixed badge")
	func mixedBadge() {
		let badge = FileStatusBadge(status: .mixed)
		#expect(badge.isVisible)
		#expect(badge.symbolName == "ellipsis.circle.fill")
	}

	@Test("Equality")
	func equality() {
		let a = FileStatusBadge(status: .modified)
		let b = FileStatusBadge(status: .modified)
		let c = FileStatusBadge(status: .added)
		#expect(a == b)
		#expect(a != c)
	}

	#if canImport(AppKit)
	@Test("NSColor is non-nil for visible badges")
	func colorForVisible() {
		let badge = FileStatusBadge(status: .modified)
		#expect(badge.color != nil)
	}

	@Test("NSColor is nil for clean files")
	func colorForClean() {
		let badge = FileStatusBadge(status: .none)
		#expect(badge.color == nil)
	}
	#endif
}

// MARK: - FileStatusBadgeProvider Tests

@Suite("FileStatusBadgeProvider")
@MainActor
struct FileStatusBadgeProviderTests {
	@Test("Badge for unknown file returns unknown status")
	func unknownFile() {
		let mockDriver = MockDriver(name: "mock", detectionMarker: ".nonexistent_marker_x")
		let registry = SCMDriverRegistry(drivers: [mockDriver])
		let manager = SCMManager(registry: registry)
		let provider = FileStatusBadgeProvider(manager: manager)

		let badge = provider.badge(for: "/tmp/random_file.txt")
		#expect(badge.status == .unknown)
		#expect(!badge.isVisible)
	}

	@Test("Badges for multiple files")
	func multipleBadges() {
		let mockDriver = MockDriver(name: "mock", detectionMarker: ".nonexistent_marker_y")
		let registry = SCMDriverRegistry(drivers: [mockDriver])
		let manager = SCMManager(registry: registry)
		let provider = FileStatusBadgeProvider(manager: manager)

		let badges = provider.badges(for: ["/a.txt", "/b.txt"])
		#expect(badges.count == 2)
	}

	@Test("Invalidate cache")
	func invalidateCache() {
		let mockDriver = MockDriver(name: "mock", detectionMarker: ".nonexistent_marker_z")
		let registry = SCMDriverRegistry(drivers: [mockDriver])
		let manager = SCMManager(registry: registry)
		let provider = FileStatusBadgeProvider(manager: manager)

		provider.invalidate(path: "/test.txt")
		provider.invalidateAll()
		// Should not crash, cache was empty/cleared
	}
}
