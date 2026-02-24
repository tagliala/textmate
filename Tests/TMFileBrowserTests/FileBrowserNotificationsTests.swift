import Testing
@testable import TMFileBrowser

@Suite("FileBrowserNotifications")
struct FileBrowserNotificationsTests {
	@Test("willDelete notification name is correct")
	func willDeleteName() {
		#expect(
			FileBrowserNotifications.willDelete.rawValue ==
				"FileBrowserWillDeleteNotification",
		)
	}

	@Test("didDuplicate notification name is correct")
	func didDuplicateName() {
		#expect(
			FileBrowserNotifications.didDuplicate.rawValue ==
				"FileBrowserDidDuplicateNotification",
		)
	}

	@Test("pathKey value is correct")
	func pathKeyValue() {
		#expect(FileBrowserNotifications.pathKey == "FileBrowserPathKey")
	}

	@Test("urlDictionaryKey value is correct")
	func urlDictionaryKeyValue() {
		#expect(FileBrowserNotifications.urlDictionaryKey == "FileBrowserURLDictionaryKey")
	}

	@Test("notification names are distinct")
	func distinctNames() {
		#expect(
			FileBrowserNotifications.willDelete !=
				FileBrowserNotifications.didDuplicate,
		)
	}
}
