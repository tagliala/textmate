import Foundation

/// Notification names for file browser operations.
///
/// These notifications allow other components to observe file browser
/// events such as file deletion and duplication.
public enum FileBrowserNotifications {
	/// Posted before files are deleted (moved to Trash or permanently removed).
	///
	/// The notification's `userInfo` contains the ``pathKey`` with the file path.
	public static let willDelete = Notification.Name("FileBrowserWillDeleteNotification")

	/// Posted after files are duplicated.
	///
	/// The notification's `userInfo` contains the ``urlDictionaryKey`` with
	/// a mapping from source URL to destination URL.
	public static let didDuplicate = Notification.Name("FileBrowserDidDuplicateNotification")

	/// Key for the file path string in ``willDelete`` notification's `userInfo`.
	public static let pathKey = "FileBrowserPathKey"

	/// Key for the `[URL: URL]` dictionary in ``didDuplicate`` notification's `userInfo`.
	public static let urlDictionaryKey = "FileBrowserURLDictionaryKey"
}
