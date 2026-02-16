#if canImport(AppKit)
import AppKit
import Foundation

/// File operation types supported by the file browser.
///
/// Port of `FBOperation` from `FileBrowserViewController.h`.
public struct DiskOperation: OptionSet, Sendable {
	public let rawValue: UInt

	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	public static let link = DiskOperation(rawValue: 0x0001)
	public static let copy = DiskOperation(rawValue: 0x0002)
	public static let duplicate = DiskOperation(rawValue: 0x0004)
	public static let move = DiskOperation(rawValue: 0x0008)
	public static let rename = DiskOperation(rawValue: 0x0010)
	public static let trash = DiskOperation(rawValue: 0x0020)
	public static let newFile = DiskOperation(rawValue: 0x0040)
	public static let newFolder = DiskOperation(rawValue: 0x0080)
}

/// Handles file operations for the file browser with undo support.
///
/// Port of `FileBrowserDiskOperations` category from `FileBrowserDiskOperations.mm`.
/// Performs link, copy, move, rename, duplicate, trash, new file, and new folder
/// operations with conflict resolution dialogs and NSUndoManager integration.
@MainActor
public final class DiskOperationHandler {
	/// The undo manager for file operations.
	public let undoManager: UndoManager

	/// Callback to update the outline view after operations.
	public var onItemsInserted: (([URL]) -> [FileItem])?

	/// Callback to remove items from the outline view.
	public var onItemsRemoved: (([URL]) -> Void)?

	/// Callback to move items in the outline view.
	public var onItemsMoved: (([URL], [URL]) -> [FileItem])?

	/// The window for presenting error/confirmation dialogs.
	public weak var window: NSWindow?

	public init(undoManager: UndoManager = UndoManager()) {
		self.undoManager = undoManager
	}

	// MARK: - Public API

	/// Performs a file operation with source→destination URL mapping.
	///
	/// - Parameters:
	///   - operation: The type of operation.
	///   - urls: Dictionary mapping source URLs to destination URLs.
	///   - makeUnique: Whether to generate unique names for conflicts.
	///   - selectDestinations: Whether to select destination items after.
	/// - Returns: The resulting destination URLs, or nil if no operations succeeded.
	@discardableResult
	public func performOperation(
		_ operation: DiskOperation,
		urls: [URL: URL],
		unique makeUnique: Bool,
		select selectDestinations: Bool,
	) -> [URL]? {
		let srcURLs = Array(urls.keys)
		let destURLs = Array(urls.values)
		return performOperation(
			operation,
			sourceURLs: srcURLs,
			destinationURLs: destURLs,
			unique: makeUnique,
			select: selectDestinations,
		)
	}

	/// Performs a file operation with parallel source and destination URL arrays.
	///
	/// - Parameters:
	///   - operation: The type of operation.
	///   - sourceURLs: Source file URLs.
	///   - destinationURLs: Destination file URLs.
	///   - makeUnique: Whether to generate unique destination names.
	///   - selectDestinations: Whether to select destination items.
	/// - Returns: The resulting destination URLs, or nil if no operations succeeded.
	@discardableResult
	public func performOperation(
		_ operation: DiskOperation,
		sourceURLs: [URL],
		destinationURLs: [URL],
		unique makeUnique: Bool,
		select selectDestinations: Bool,
	) -> [URL]? {
		var destURLs = makeUnique ? uniqueDestinationURLs(destinationURLs) : destinationURLs

		let itemDescription: String
		if sourceURLs.count == 1 {
			let name = FileManager.default.displayName(atPath: sourceURLs[0].path)
			itemDescription = "\"\(name)\""
		} else {
			itemDescription = "\(sourceURLs.count) Items"
		}

		var newSrcURLs: [URL] = []
		var newDestURLs: [URL] = []
		var forceFlag = false

		let total = max(sourceURLs.count, destURLs.count)
		var i = 0
		while i < total {
			let srcURL = i < sourceURLs.count ? sourceURLs[i].standardizedFileURL : nil
			var destURL = i < destURLs.count ? destURLs[i].standardizedFileURL : nil

			var error: NSError?
			var success = performSingleOperation(
				operation,
				sourceURL: srcURL,
				destinationURL: &destURL,
				force: forceFlag,
				error: &error,
			)

			if !success {
				if operation.contains(.link) || operation.contains(.copy) || operation.contains(.move),
				   let err = error,
				   (err as NSError).domain == NSCocoaErrorDomain,
				   (err as NSError).code == NSFileWriteFileExistsError
				{
					let result = showReplaceConfirmation(
						for: destURL,
						remaining: total - i - 1,
					)
					switch result {
					case let .replace(applyAll):
						if applyAll { forceFlag = true }
						success = performSingleOperation(
							operation, sourceURL: srcURL, destinationURL: &destURL,
							force: true, error: &error,
						)
					case .stop:
						i = total
						error = nil
					case .skip:
						i += 1
						continue
					}
				} else if operation == .trash,
				          let err = error,
				          (err as NSError).domain == NSCocoaErrorDomain,
				          (err as NSError).code == NSFileWriteUnsupportedSchemeError
				{
					let result = showForceDeleteConfirmation(
						for: srcURL,
						remaining: total - i - 1,
					)
					switch result {
					case let .replace(applyAll):
						if applyAll { forceFlag = true }
						success = performSingleOperation(
							operation, sourceURL: srcURL, destinationURL: &destURL,
							force: true, error: &error,
						)
					case .stop:
						i = total
						error = nil
					case .skip:
						i += 1
						continue
					}
				}
			}

			if success {
				if let destURL {
					if let srcURL { newSrcURLs.append(srcURL) }
					newDestURLs.append(destURL)
				}
			} else if let error {
				presentError(error)
			}

			i += 1
		}

		guard !newDestURLs.isEmpty else { return nil }

		// Update outline view
		if operation.contains(.move) || operation.contains(.rename) || operation.contains(.trash) {
			_ = onItemsMoved?(newSrcURLs, newDestURLs)
		} else if operation.contains(.link) || operation.contains(.copy) ||
			operation.contains(.duplicate) || operation.contains(.newFile) ||
			operation.contains(.newFolder)
		{
			_ = onItemsInserted?(newDestURLs)
		}

		// Play sound
		if operation.contains(.link) || operation.contains(.move) ||
			operation.contains(.copy) || operation.contains(.duplicate)
		{
			NSSound(named: "Pop")?.play()
		} else if operation.contains(.trash) {
			NSSound(named: "Sosumi")?.play()
		}

		// Register undo
		registerUndo(
			operation: operation,
			sourceURLs: !newSrcURLs.isEmpty ? newSrcURLs : nil,
			destinationURLs: newDestURLs,
			selectDestinations: selectDestinations,
			itemDescription: itemDescription,
		)

		return newDestURLs
	}

	// MARK: - Single Operation

	private func performSingleOperation(
		_ operation: DiskOperation,
		sourceURL: URL?,
		destinationURL: inout URL?,
		force: Bool,
		error: inout NSError?,
	) -> Bool {
		let fm = FileManager.default

		// Handle force replacement
		if force, operation.contains(.link) || operation.contains(.copy) || operation.contains(.move),
		   let destURL = destinationURL, fm.fileExists(atPath: destURL.path)
		{
			do {
				try fm.removeItem(at: destURL)
			} catch let err as NSError {
				error = err
				return false
			}
		}

		do {
			if operation.contains(.link) {
				guard let srcURL = sourceURL, var destURL = destinationURL else { return false }
				// Create symbolic link — use relative path if on same device
				try fm.createSymbolicLink(at: destURL, withDestinationURL: srcURL)
				destinationURL = destURL
				return true
			} else if operation.contains(.move) || operation.contains(.rename) {
				guard let srcURL = sourceURL, let destURL = destinationURL else { return false }
				try fm.moveItem(at: srcURL, to: destURL)
				return true
			} else if operation.contains(.newFile) {
				guard let destURL = destinationURL else { return false }
				return fm.createFile(atPath: destURL.path, contents: nil)
			} else if operation.contains(.newFolder) {
				guard let destURL = destinationURL else { return false }
				try fm.createDirectory(at: destURL, withIntermediateDirectories: false)
				return true
			} else if operation.contains(.copy) || operation.contains(.duplicate) {
				guard let srcURL = sourceURL, let destURL = destinationURL else { return false }

				// Prevent copying a directory into itself
				if destURL.path.hasPrefix(srcURL.path + "/") {
					error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP))
					return false
				}

				try fm.copyItem(at: srcURL, to: destURL)

				if operation.contains(.duplicate) {
					NotificationCenter.default.post(
						name: FileBrowserNotifications.didDuplicate,
						object: nil,
						userInfo: [
							FileBrowserNotifications.urlDictionaryKey: [srcURL: destURL],
						],
					)
				}
				return true
			} else if operation.contains(.trash) {
				guard let srcURL = sourceURL else { return false }

				NotificationCenter.default.post(
					name: FileBrowserNotifications.willDelete,
					object: nil,
					userInfo: [FileBrowserNotifications.pathKey: srcURL.path],
				)

				var resultingURL: NSURL?
				try fm.trashItem(at: srcURL, resultingItemURL: &resultingURL)
				destinationURL = resultingURL as URL?
				return true
			}
		} catch let err as NSError {
			// Force delete when trash is not supported
			if operation.contains(.trash), force,
			   (err as NSError).domain == NSCocoaErrorDomain,
			   (err as NSError).code == NSFileWriteUnsupportedSchemeError
			{
				do {
					try fm.removeItem(at: sourceURL!)
					return true
				} catch let innerErr as NSError {
					error = innerErr
					return false
				}
			}
			error = err
		}

		return false
	}

	// MARK: - Unique Names

	/// Generates unique destination URLs by appending numbers to avoid conflicts.
	public func uniqueDestinationURLs(_ urls: [URL]) -> [URL] {
		var result: [URL] = []
		var existingURLs = Set<URL>()

		for url in urls {
			var destURL = url
			let base = destURL.lastPathComponent

			var counter = 1
			while existingURLs.contains(destURL) || FileManager.default.fileExists(atPath: destURL.path) {
				counter += 1
				let name = Self.incrementedName(base, counter: counter)
				destURL = destURL.deletingLastPathComponent().appendingPathComponent(
					name,
					isDirectory: url.hasDirectoryPath,
				)
			}

			existingURLs.insert(destURL)
			result.append(destURL)
		}

		return result
	}

	/// Generates an incremented filename: "file.txt" → "file 2.txt"
	static func incrementedName(_ name: String, counter: Int) -> String {
		let pattern = try! NSRegularExpression(pattern: #"^(.*?)(?: \d+)?(\.\w+)?$"#)
		let range = NSRange(name.startIndex ..< name.endIndex, in: name)
		return pattern.stringByReplacingMatches(
			in: name,
			range: range,
			withTemplate: "$1 \(counter)$2",
		)
	}

	// MARK: - Undo

	private func registerUndo(
		operation: DiskOperation,
		sourceURLs: [URL]?,
		destinationURLs: [URL],
		selectDestinations: Bool,
		itemDescription: String,
	) {
		undoManager.registerUndo(withTarget: self) { [weak self] target in
			target.undoOperation(
				operation,
				sourceURLs: sourceURLs,
				destinationURLs: destinationURLs,
				select: selectDestinations,
			)
		}

		let actionName = if operation.contains(.link) {
			"Create Link to \(itemDescription)"
		} else if operation.contains(.copy) {
			"Copy of \(itemDescription)"
		} else if operation.contains(.duplicate) {
			"Duplicate \(itemDescription)"
		} else if operation.contains(.move) {
			"Move of \(itemDescription)"
		} else if operation.contains(.rename) {
			"Rename \(itemDescription)"
		} else if operation.contains(.trash) {
			"Move of \(itemDescription) to Trash"
		} else if operation.contains(.newFile) {
			"New File"
		} else if operation.contains(.newFolder) {
			"New Folder"
		} else {
			"File Operation"
		}
		undoManager.setActionName(actionName)
	}

	private func undoOperation(
		_ operation: DiskOperation,
		sourceURLs: [URL]?,
		destinationURLs: [URL],
		select selectDestinations: Bool,
	) {
		let fm = FileManager.default

		for (i, destURL) in destinationURLs.enumerated() {
			do {
				if operation.contains(.link) || operation.contains(.copy) ||
					operation.contains(.duplicate) || operation.contains(.newFile) ||
					operation.contains(.newFolder)
				{
					NotificationCenter.default.post(
						name: FileBrowserNotifications.willDelete,
						object: nil,
						userInfo: [FileBrowserNotifications.pathKey: destURL.path],
					)
					try fm.removeItem(at: destURL)
					onItemsRemoved?([destURL])
				} else if operation.contains(.move) || operation.contains(.rename) ||
					operation.contains(.trash)
				{
					if let srcURLs = sourceURLs, i < srcURLs.count {
						try fm.moveItem(at: destURL, to: srcURLs[i])
						_ = onItemsMoved?([destURL], [srcURLs[i]])
					}
				}
			} catch {
				presentError(error as NSError)
			}
		}

		// Register redo
		undoManager.registerUndo(withTarget: self) { [weak self] target in
			target.performOperation(
				operation,
				sourceURLs: sourceURLs ?? [],
				destinationURLs: destinationURLs,
				unique: false,
				select: selectDestinations,
			)
		}
	}

	// MARK: - Dialogs

	private enum ConflictResult {
		case replace(applyAll: Bool)
		case stop
		case skip
	}

	private func showReplaceConfirmation(for url: URL?, remaining: Int) -> ConflictResult {
		let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? "item"
		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = "Do you want to replace \"\(name)\"?"
		alert.informativeText = "An item named \"\(name)\" already exists in the location."
		if remaining > 0 {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = "Replace All"
		}
		alert.addButton(withTitle: "Replace")
		alert.addButton(withTitle: "Stop")
		alert.addButton(withTitle: "Skip")

		let response = alert.runModal()
		switch response {
		case .alertFirstButtonReturn:
			return .replace(applyAll: alert.suppressionButton?.state == .on)
		case .alertSecondButtonReturn:
			return .stop
		default:
			return .skip
		}
	}

	private func showForceDeleteConfirmation(for url: URL?, remaining: Int) -> ConflictResult {
		let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? "item"
		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = "Are you sure you want to delete \"\(name)\"?"
		alert.informativeText = "This item will be deleted immediately. You can't undo this action."
		if remaining > 0 {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = "Delete All"
		}
		alert.addButton(withTitle: "Delete")
		alert.addButton(withTitle: "Stop")
		alert.addButton(withTitle: "Skip")

		let response = alert.runModal()
		switch response {
		case .alertFirstButtonReturn:
			return .replace(applyAll: alert.suppressionButton?.state == .on)
		case .alertSecondButtonReturn:
			return .stop
		default:
			return .skip
		}
	}

	private func presentError(_ error: NSError) {
		if let window {
			NSApp.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
		} else {
			NSApp.presentError(error)
		}
	}
}
#endif
