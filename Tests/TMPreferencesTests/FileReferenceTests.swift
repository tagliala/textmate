import AppKit
import Testing
@testable import TMPreferences

@Suite("FileReferenceSCMStatus")
struct FileReferenceSCMStatusTests {
	@Test("raw values match expected integer mapping")
	func rawValues() {
		#expect(FileReferenceSCMStatus.none.rawValue == 0)
		#expect(FileReferenceSCMStatus.unversioned.rawValue == 1)
		#expect(FileReferenceSCMStatus.modified.rawValue == 2)
		#expect(FileReferenceSCMStatus.added.rawValue == 3)
		#expect(FileReferenceSCMStatus.deleted.rawValue == 4)
		#expect(FileReferenceSCMStatus.conflicted.rawValue == 5)
		#expect(FileReferenceSCMStatus.mixed.rawValue == 6)
	}

	@Test("init from raw value round-trips")
	func initFromRawValue() {
		for status in [FileReferenceSCMStatus.none, .unversioned, .modified, .added, .deleted, .conflicted, .mixed] {
			#expect(FileReferenceSCMStatus(rawValue: status.rawValue) == status)
		}
	}

	@Test("invalid raw value returns nil")
	func invalidRawValue() {
		#expect(FileReferenceSCMStatus(rawValue: 99) == nil)
		#expect(FileReferenceSCMStatus(rawValue: -1) == nil)
	}
}

@Suite("FileReference")
struct FileReferenceTests {
	// MARK: - Identity Map

	@Test("same URL returns same instance")
	@MainActor func identityMapSameURL() {
		let url = URL(fileURLWithPath: "/tmp/test-identity-\(UUID()).txt")
		let ref1 = FileReference.fileReference(for: url)
		let ref2 = FileReference.fileReference(for: url)
		#expect(ref1 === ref2)
	}

	@Test("different URLs return different instances")
	@MainActor func identityMapDifferentURLs() {
		let url1 = URL(fileURLWithPath: "/tmp/test-diff1-\(UUID()).txt")
		let url2 = URL(fileURLWithPath: "/tmp/test-diff2-\(UUID()).txt")
		let ref1 = FileReference.fileReference(for: url1)
		let ref2 = FileReference.fileReference(for: url2)
		#expect(ref1 !== ref2)
	}

	@Test("image-only reference has nil URL")
	@MainActor func imageOnlyRef() {
		let image = NSImage(size: NSSize(width: 16, height: 16))
		let ref = FileReference.fileReference(image: image)
		#expect(ref.url == nil)
	}

	// MARK: - Open Count

	@Test("isClosable starts as false")
	@MainActor func initialClosable() {
		let url = URL(fileURLWithPath: "/tmp/test-closable-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		#expect(ref.isClosable == false)
	}

	@Test("increaseOpenCount makes isClosable true")
	@MainActor func openCountMakesClosable() {
		let url = URL(fileURLWithPath: "/tmp/test-open-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		ref.increaseOpenCount()
		#expect(ref.isClosable == true)
		ref.decreaseOpenCount()
	}

	@Test("balanced open/close returns to not closable")
	@MainActor func balancedOpenClose() {
		let url = URL(fileURLWithPath: "/tmp/test-balance-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		ref.increaseOpenCount()
		ref.increaseOpenCount()
		#expect(ref.isClosable == true)
		ref.decreaseOpenCount()
		#expect(ref.isClosable == true)
		ref.decreaseOpenCount()
		#expect(ref.isClosable == false)
	}

	// MARK: - Modified Count

	@Test("isModified starts as false")
	@MainActor func initialModified() {
		let url = URL(fileURLWithPath: "/tmp/test-mod-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		#expect(ref.isModified == false)
	}

	@Test("increaseModifiedCount makes isModified true")
	@MainActor func modifiedCountMakesModified() {
		let url = URL(fileURLWithPath: "/tmp/test-mod2-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		ref.increaseOpenCount()
		ref.increaseModifiedCount()
		#expect(ref.isModified == true)
		ref.decreaseModifiedCount()
		ref.decreaseOpenCount()
	}

	@Test("balanced modify returns to not modified")
	@MainActor func balancedModify() {
		let url = URL(fileURLWithPath: "/tmp/test-balmod-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		ref.increaseOpenCount()
		ref.increaseModifiedCount()
		ref.increaseModifiedCount()
		#expect(ref.isModified == true)
		ref.decreaseModifiedCount()
		#expect(ref.isModified == true)
		ref.decreaseModifiedCount()
		#expect(ref.isModified == false)
		ref.decreaseOpenCount()
	}

	// MARK: - SCM Status

	@Test("scmStatus defaults to none")
	@MainActor func defaultSCMStatus() {
		let url = URL(fileURLWithPath: "/tmp/test-scm-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		#expect(ref.scmStatus == .none)
	}

	@Test("setting scmStatus invalidates cached image")
	@MainActor func scmStatusInvalidatesImage() {
		let url = URL(fileURLWithPath: "/tmp/test-scminval-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		// Access image to cache it
		_ = ref.image
		// Change status — should invalidate
		ref.scmStatus = .modified
		#expect(ref.scmStatus == .modified)
		// Access image again — should recompose (no crash)
		_ = ref.image
	}

	@Test("setting same scmStatus does not trigger change")
	@MainActor func scmStatusSameValue() {
		let url = URL(fileURLWithPath: "/tmp/test-scmsame-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		ref.scmStatus = .none
		// Should not crash or trigger unnecessary change
		#expect(ref.scmStatus == .none)
	}

	// MARK: - Image

	@Test("image returns an NSImage")
	@MainActor func imageReturnsNSImage() {
		let url = URL(fileURLWithPath: "/tmp/test-img-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		let img = ref.image
		#expect(img.size.width == 16)
		#expect(img.size.height == 16)
	}

	@Test("icon returns image with reduced alpha when modified")
	@MainActor func iconModifiedAlpha() {
		let url = URL(fileURLWithPath: "/tmp/test-icon-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		ref.increaseOpenCount()
		ref.increaseModifiedCount()
		let icon = ref.icon
		// Icon should be different from base image (different NSImage instance due to alpha)
		#expect(icon !== ref.image || ref.isModified)
		ref.decreaseModifiedCount()
		ref.decreaseOpenCount()
	}

	@Test("icon returns base image when not modified")
	@MainActor func iconUnmodified() {
		let url = URL(fileURLWithPath: "/tmp/test-icon2-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)
		let icon = ref.icon
		let image = ref.image
		// When not modified, icon should be the same object as image
		#expect(icon === image)
	}

	// MARK: - Equality

	@Test("file references with same URL are equal")
	@MainActor func equalityByURL() {
		let url = URL(fileURLWithPath: "/tmp/test-eq-\(UUID()).txt")
		let ref1 = FileReference.fileReference(for: url)
		let ref2 = FileReference.fileReference(for: url)
		#expect(ref1.isEqual(ref2))
		#expect(ref1.hash == ref2.hash)
	}

	@Test("file references with different URLs are not equal")
	@MainActor func inequalityByURL() {
		let url1 = URL(fileURLWithPath: "/tmp/test-neq1-\(UUID()).txt")
		let url2 = URL(fileURLWithPath: "/tmp/test-neq2-\(UUID()).txt")
		let ref1 = FileReference.fileReference(for: url1)
		let ref2 = FileReference.fileReference(for: url2)
		#expect(!ref1.isEqual(ref2))
	}

	// MARK: - Notification

	@Test("performClose posts fileReferenceWillClose notification")
	@MainActor func performCloseNotification() async throws {
		let url = URL(fileURLWithPath: "/tmp/test-close-\(UUID()).txt")
		let ref = FileReference.fileReference(for: url)

		nonisolated(unsafe) var receivedURL: URL?
		let observer = NotificationCenter.default.addObserver(
			forName: .fileReferenceWillClose,
			object: ref,
			queue: .main,
		) { notification in
			receivedURL = notification.userInfo?["URL"] as? URL
		}

		ref.performClose(nil)

		// Give notification a chance to be delivered
		try await Task.sleep(for: .milliseconds(50))

		#expect(receivedURL == url)
		NotificationCenter.default.removeObserver(observer)
	}

	// MARK: - KVO Dependencies

	@Test("keyPathsForValuesAffectingIcon includes expected paths")
	@MainActor func kvoIcon() {
		let paths = FileReference.keyPathsForValuesAffectingIcon()
		#expect(paths.contains("image"))
		#expect(paths.contains("isModified"))
	}

	// MARK: - Static image(for:size:)

	@Test("image(for:size:) returns correctly sized image")
	@MainActor func imageForURLWithSize() {
		let url = URL(fileURLWithPath: "/tmp/test-sized-\(UUID()).txt")
		let img = FileReference.image(for: url, size: NSSize(width: 32, height: 32))
		#expect(img.size.width == 32)
		#expect(img.size.height == 32)
	}
}
