import Foundation

// MARK: - Document State

/// Tracks the lifecycle state of a document.
public enum DocumentState: Sendable, Equatable {
	/// Not yet loaded from disk.
	case unloaded
	/// Currently loading asynchronously.
	case loading
	/// Content is in memory and available.
	case loaded
	/// Save is in progress.
	case saving
	/// An error occurred during load or save.
	case error(String)
}

// MARK: - Line Ending

/// Line ending style used in the document.
public enum LineEnding: String, Sendable, Codable, CaseIterable {
	case lf = "\n"
	case cr = "\r"
	case crlf = "\r\n"

	/// Display name for the status bar.
	public var displayName: String {
		switch self {
		case .lf: "LF"
		case .cr: "CR"
		case .crlf: "CR/LF"
		}
	}

	/// Detects the dominant line ending in a string.
	public static func detect(in text: String) -> LineEnding {
		var lfCount = 0
		var crCount = 0
		var crlfCount = 0

		var prevWasCR = false
		for scalar in text.unicodeScalars {
			if scalar == "\n" {
				if prevWasCR {
					crlfCount += 1
					crCount -= 1 // Undo the CR counted on previous scalar
				} else {
					lfCount += 1
				}
				prevWasCR = false
			} else if scalar == "\r" {
				crCount += 1
				prevWasCR = true
			} else {
				prevWasCR = false
			}
		}

		if crlfCount >= lfCount, crlfCount >= crCount { return crlfCount > 0 ? .crlf : .lf }
		if crCount > lfCount { return .cr }
		return .lf
	}
}

// MARK: - Document Encoding

/// Pairs a string encoding with line ending style.
public struct DocumentEncoding: Sendable, Equatable, Codable {
	public var charset: String
	public var lineEnding: LineEnding
	public var hasBOM: Bool

	public init(
		charset: String = "UTF-8",
		lineEnding: LineEnding = .lf,
		hasBOM: Bool = false,
	) {
		self.charset = charset
		self.lineEnding = lineEnding
		self.hasBOM = hasBOM
	}

	/// Converts the charset name to Swift's String.Encoding.
	public var stringEncoding: String.Encoding {
		let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
		guard cf != kCFStringEncodingInvalidId else { return .utf8 }
		let ns = CFStringConvertEncodingToNSStringEncoding(cf)
		return String.Encoding(rawValue: ns)
	}

	/// Creates from a Swift String.Encoding.
	public static func from(encoding: String.Encoding, lineEnding: LineEnding = .lf) -> DocumentEncoding {
		let cf = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
		let name = (CFStringConvertEncodingToIANACharSetName(cf) as String?)?.uppercased() ?? "UTF-8"
		return DocumentEncoding(charset: name, lineEnding: lineEnding)
	}

	/// Common presets.
	public static let utf8 = DocumentEncoding(charset: "UTF-8")
	public static let utf8BOM = DocumentEncoding(charset: "UTF-8", hasBOM: true)
	public static let utf16BE = DocumentEncoding(charset: "UTF-16BE", hasBOM: true)
	public static let utf16LE = DocumentEncoding(charset: "UTF-16LE", hasBOM: true)
	public static let latin1 = DocumentEncoding(charset: "ISO-8859-1")
	public static let macRoman = DocumentEncoding(charset: "macintosh")
	public static let shiftJIS = DocumentEncoding(charset: "Shift_JIS")
}

// MARK: - TM Document

/// The core document model — equivalent to the C++ `OakDocument`.
///
/// Tracks identity (UUID + path), lifecycle state, encoding, file type,
/// modification status, and editor metadata. Thread-safe via `@MainActor`.
///
/// Documents are deduplicated by the `TMDocumentController` — opening the
/// same path twice returns the same `TMDocument` instance. Untitled documents
/// have a `nil` path.
@MainActor
public final class TMDocument: Identifiable, Equatable, Hashable {
	// MARK: - Identity

	/// Unique identifier, stable across sessions (persisted in backups).
	public let id: UUID

	/// The on-disk file path, or `nil` for untitled documents.
	public private(set) var path: String?

	/// A virtual path used for scope resolution when the real path is unavailable.
	/// Example: "untitled.rb" to give an untitled document a Ruby scope.
	public var virtualPath: String?

	/// A user-provided name override (e.g., for scratch buffers).
	public var customName: String?

	/// The inode number observed at last read, used for rename tracking.
	private(set) var inode: UInt64?

	// MARK: - State

	/// Current lifecycle state.
	public private(set) var state: DocumentState = .unloaded

	/// Reference count for open operations — document is considered
	/// open when `openCount > 0`.
	private var openCount: Int = 0

	/// Whether the document is currently open (at least one viewer).
	public var isOpen: Bool {
		openCount > 0
	}

	/// Whether the file exists on disk.
	public var isOnDisk: Bool {
		path != nil && FileManager.default.fileExists(atPath: path!)
	}

	/// The saved revision number — when `revision != savedRevision`, the
	/// document has unsaved changes.
	public private(set) var revision: Int = 0

	/// The revision at last save.
	public private(set) var savedRevision: Int = 0

	/// Whether the document has unsaved modifications.
	public var isModified: Bool {
		revision != savedRevision
	}

	/// Whether the document is empty and untitled (disposable).
	public var isDisposable: Bool {
		path == nil && !isModified && (content?.isEmpty ?? true)
	}

	/// Whether the document is in read-only viewing mode.
	public var isViewingMode: Bool = false

	// MARK: - Content

	/// The document text content. Set during load, updated by the editor.
	public var content: String?

	/// A snapshot of the content at time of last load/save, used for
	/// 3-way merge when external changes are detected.
	private var contentSnapshot: String?

	// MARK: - Encoding

	/// The detected or configured encoding for this document.
	public var encoding: DocumentEncoding = .utf8

	// MARK: - File Type

	/// The grammar scope for this document (e.g., "source.swift").
	/// Lazily detected from path and content.
	public var fileType: String?

	// MARK: - Editor Metadata

	/// Serialized selection ranges (e.g., "1:0-1:10&2:5").
	public var selection: String?

	/// The line index visible at the top of the editor.
	public var visibleIndex: Int = 0

	/// Tab size for this document.
	public var tabSize: Int = 4

	/// Whether soft tabs (spaces) are enabled.
	public var softTabs: Bool = false

	/// Whether this tab is "sticky" (pinned).
	public var isSticky: Bool = false

	/// The spelling language (e.g., "en_US").
	public var spellingLanguage: String?

	/// Whether continuous spell checking is enabled.
	public var continuousSpellChecking: Bool = false

	/// Folded ranges, as serialized strings.
	public var foldedRanges: [String] = []

	/// Bookmarks set in this document, as line numbers.
	public var bookmarks: [Int] = []

	// MARK: - Backup

	/// Whether a backup is needed (set after edits, cleared after backup).
	public var needsBackup: Bool = false

	/// Path to the backup file, if one exists.
	public var backupPath: String?

	/// Whether to keep the backup file after saving (for crash recovery).
	public var keepBackupFile: Bool = false

	// MARK: - SCM

	/// Source control status character (e.g., "M" for modified).
	public var scmStatus: String?

	// MARK: - Timestamps

	/// When the document was last modified on disk.
	public var diskModificationDate: Date?

	/// When the document was last saved by us.
	public var lastSaveDate: Date?

	// MARK: - Observation

	/// Callbacks fired when document state changes.
	private var changeCallbacks: [UUID: () -> Void] = [:]

	// MARK: - Initialization

	public init(
		id: UUID = UUID(),
		path: String? = nil,
		fileType: String? = nil,
	) {
		self.id = id
		self.path = path
		self.fileType = fileType
	}

	// MARK: - Open / Close

	/// Increments the open count. Call when a viewer starts using this document.
	public func open() {
		openCount += 1
	}

	/// Decrements the open count. When it reaches zero, the document
	/// may release its buffer and persist metadata to disk.
	public func close() {
		guard openCount > 0 else { return }
		openCount -= 1
		if openCount == 0 {
			saveMetadataToExtendedAttributes()
			notifyChange()
		}
	}

	// MARK: - Loading

	/// Loads the document content from disk asynchronously.
	public func load() async throws {
		guard let filePath = path else {
			state = .loaded
			content = content ?? ""
			return
		}

		state = .loading
		notifyChange()

		do {
			let url = URL(fileURLWithPath: filePath)
			let data = try Data(contentsOf: url)

			// Detect encoding
			let (text, detectedEncoding) = Self.decodeData(data)
			content = text
			encoding = detectedEncoding
			contentSnapshot = text

			// Detect line endings
			encoding.lineEnding = LineEnding.detect(in: text)

			// Read file attributes
			let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
			diskModificationDate = attrs?[.modificationDate] as? Date
			if let fileSystemNumber = attrs?[.systemFileNumber] as? UInt64 {
				inode = fileSystemNumber
			}

			revision = 0
			savedRevision = 0
			state = .loaded
			notifyChange()
		} catch {
			state = .error(error.localizedDescription)
			notifyChange()
			throw error
		}
	}

	// MARK: - Saving

	/// Saves the document content to disk.
	public func save() async throws {
		guard let filePath = path else {
			throw DocumentIOError.noPath
		}
		guard let text = content else {
			throw DocumentIOError.noContent
		}

		state = .saving
		notifyChange()

		do {
			let url = URL(fileURLWithPath: filePath)

			// Ensure parent directory exists
			let dir = url.deletingLastPathComponent()
			try FileManager.default.createDirectory(
				at: dir,
				withIntermediateDirectories: true,
			)

			// Encode
			guard let data = encodeText(text) else {
				throw DocumentIOError.encodingFailed(encoding.charset)
			}

			try data.write(to: url, options: .atomic)

			savedRevision = revision
			contentSnapshot = text
			lastSaveDate = Date()
			needsBackup = false
			state = .loaded

			// Update disk attributes
			let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
			diskModificationDate = attrs?[.modificationDate] as? Date

			notifyChange()
		} catch {
			state = .loaded // Revert to loaded state on failure
			notifyChange()
			throw error
		}
	}

	/// Saves the document to a new path.
	public func save(to newPath: String) async throws {
		let oldPath = path
		path = newPath
		do {
			try await save()
		} catch {
			path = oldPath
			throw error
		}
	}

	// MARK: - Content Modification

	/// Records a content change, incrementing the revision.
	public func markModified() {
		revision += 1
		needsBackup = true
		notifyChange()
	}

	/// Replaces the content entirely (e.g., after an external reload).
	public func setContent(_ newContent: String, preserveRevision: Bool = false) {
		content = newContent
		if !preserveRevision {
			revision += 1
			needsBackup = true
		}
		notifyChange()
	}

	/// Marks the document as saved at the current revision.
	public func markSaved() {
		savedRevision = revision
		needsBackup = false
		notifyChange()
	}

	// MARK: - External Changes

	/// Checks if the file on disk has been modified since we last read/wrote it.
	public func hasExternalChanges() -> Bool {
		guard let filePath = path else { return false }
		let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
		guard let diskDate = attrs?[.modificationDate] as? Date else { return false }
		guard let ourDate = diskModificationDate else { return true }
		return diskDate > ourDate
	}

	/// Reloads the document from disk, optionally performing a 3-way merge
	/// if the document has unsaved changes.
	public func reload(mergeChanges: Bool = true) async throws {
		guard let filePath = path else { return }

		let url = URL(fileURLWithPath: filePath)
		let data = try Data(contentsOf: url)
		let (theirText, detectedEncoding) = Self.decodeData(data)

		if mergeChanges, isModified, let snapshot = contentSnapshot, let myText = content {
			// 3-way merge: (original=snapshot, mine=myText, theirs=theirText)
			let merged = Self.threeWayMerge(
				original: snapshot,
				mine: myText,
				theirs: theirText,
			)
			content = merged
			contentSnapshot = theirText
		} else {
			content = theirText
			contentSnapshot = theirText
			encoding = detectedEncoding
			revision = 0
			savedRevision = 0
		}

		let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
		diskModificationDate = attrs?[.modificationDate] as? Date

		notifyChange()
	}

	// MARK: - Display

	/// The display name shown in tabs and window titles.
	public var displayName: String {
		if let customName { return customName }
		if let path { return (path as NSString).lastPathComponent }
		if let virtualPath { return (virtualPath as NSString).lastPathComponent }
		return "Untitled"
	}

	// MARK: - Path

	/// Updates the document's path (e.g., after rename detection via inode).
	public func setPath(_ newPath: String?) {
		path = newPath
		notifyChange()
	}

	// MARK: - Observation

	/// Registers a callback for document changes. Returns an ID for removal.
	@discardableResult
	public func addChangeCallback(_ callback: @escaping () -> Void) -> UUID {
		let id = UUID()
		changeCallbacks[id] = callback
		return id
	}

	/// Removes a change callback.
	public func removeChangeCallback(id: UUID) {
		changeCallbacks.removeValue(forKey: id)
	}

	private func notifyChange() {
		for callback in changeCallbacks.values {
			callback()
		}
	}

	// MARK: - Equatable / Hashable

	public nonisolated static func == (lhs: TMDocument, rhs: TMDocument) -> Bool {
		lhs.id == rhs.id
	}

	public nonisolated func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}

	// MARK: - Encoding Detection

	/// Decodes raw data, detecting encoding from BOM and content analysis.
	nonisolated static func decodeData(_ data: Data) -> (String, DocumentEncoding) {
		// Check BOMs
		if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
			if let s = String(data: data.dropFirst(3), encoding: .utf8) {
				return (s, .utf8BOM)
			}
		}
		if data.count >= 4, data[0] == 0x00, data[1] == 0x00, data[2] == 0xFE, data[3] == 0xFF {
			if let s = String(data: data, encoding: .utf32BigEndian) {
				return (s, DocumentEncoding(charset: "UTF-32BE", hasBOM: true))
			}
		}
		if data.count >= 4, data[0] == 0xFF, data[1] == 0xFE, data[2] == 0x00, data[3] == 0x00 {
			if let s = String(data: data, encoding: .utf32LittleEndian) {
				return (s, DocumentEncoding(charset: "UTF-32LE", hasBOM: true))
			}
		}
		if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
			if let s = String(data: data, encoding: .utf16BigEndian) {
				return (s, .utf16BE)
			}
		}
		if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
			if let s = String(data: data, encoding: .utf16LittleEndian) {
				return (s, .utf16LE)
			}
		}

		// Try common encodings
		let charsets: [(String.Encoding, String)] = [
			(.utf8, "UTF-8"),
			(.isoLatin1, "ISO-8859-1"),
			(.windowsCP1252, "windows-1252"),
			(.macOSRoman, "macintosh"),
			(.japaneseEUC, "EUC-JP"),
			(.shiftJIS, "Shift_JIS"),
		]
		for (enc, name) in charsets {
			if let s = String(data: data, encoding: enc) {
				return (s, DocumentEncoding(charset: name))
			}
		}

		// Last resort — lossy UTF-8
		return (String(decoding: data, as: UTF8.self), .utf8)
	}

	/// Encodes text to data using the document's encoding settings.
	private func encodeText(_ text: String) -> Data? {
		// Normalize line endings
		let normalized: String
		switch encoding.lineEnding {
		case .lf:
			normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
				.replacingOccurrences(of: "\r", with: "\n")
		case .cr:
			normalized = text.replacingOccurrences(of: "\r\n", with: "\r")
				.replacingOccurrences(of: "\n", with: "\r")
		case .crlf:
			let withLF = text.replacingOccurrences(of: "\r\n", with: "\n")
				.replacingOccurrences(of: "\r", with: "\n")
			normalized = withLF.replacingOccurrences(of: "\n", with: "\r\n")
		}

		guard var data = normalized.data(using: encoding.stringEncoding) else {
			return nil
		}

		// Prepend BOM if needed
		if encoding.hasBOM {
			let bom: [UInt8] = switch encoding.charset {
			case "UTF-8": [0xEF, 0xBB, 0xBF]
			case "UTF-16BE": [0xFE, 0xFF]
			case "UTF-16LE": [0xFF, 0xFE]
			case "UTF-32BE": [0x00, 0x00, 0xFE, 0xFF]
			case "UTF-32LE": [0xFF, 0xFE, 0x00, 0x00]
			default: []
			}
			if !bom.isEmpty {
				data = Data(bom) + data
			}
		}

		return data
	}

	// MARK: - 3-Way Merge

	/// Simple line-based 3-way merge. If conflicts exist, mine wins.
	nonisolated static func threeWayMerge(original: String, mine: String, theirs: String) -> String {
		let originalLines = original.components(separatedBy: "\n")
		let myLines = mine.components(separatedBy: "\n")
		let theirLines = theirs.components(separatedBy: "\n")

		var result: [String] = []
		let maxCount = max(originalLines.count, myLines.count, theirLines.count)

		for i in 0 ..< maxCount {
			let orig = i < originalLines.count ? originalLines[i] : ""
			let my = i < myLines.count ? myLines[i] : ""
			let their = i < theirLines.count ? theirLines[i] : ""

			if my == orig {
				// I didn't change this line — take theirs.
				result.append(their)
			} else {
				// I changed this line — keep mine.
				result.append(my)
			}
		}

		return result.joined(separator: "\n")
	}

	// MARK: - Extended Attributes

	/// Saves editor metadata to file's extended attributes.
	private func saveMetadataToExtendedAttributes() {
		guard let filePath = path else { return }
		let url = URL(fileURLWithPath: filePath)

		var attrs: [String: Data] = [:]
		if let selection {
			attrs["com.macromates.selectionRange"] = Data(selection.utf8)
		}
		if visibleIndex > 0 {
			attrs["com.macromates.visibleIndex"] = Data("\(visibleIndex)".utf8)
		}
		if !bookmarks.isEmpty {
			let str = bookmarks.map(String.init).joined(separator: ",")
			attrs["com.macromates.bookmarks"] = Data(str.utf8)
		}
		if !foldedRanges.isEmpty {
			let str = foldedRanges.joined(separator: ";")
			attrs["com.macromates.folded"] = Data(str.utf8)
		}

		for (key, value) in attrs {
			url.withUnsafeFileSystemRepresentation { path in
				guard let path else { return }
				_ = value.withUnsafeBytes { buffer in
					setxattr(path, key, buffer.baseAddress, buffer.count, 0, 0)
				}
			}
		}
	}

	/// Restores editor metadata from file's extended attributes.
	public func loadMetadataFromExtendedAttributes() {
		guard let filePath = path else { return }
		let url = URL(fileURLWithPath: filePath)

		func readXattr(_ name: String) -> String? {
			url.withUnsafeFileSystemRepresentation { path -> String? in
				guard let path else { return nil }
				let len = getxattr(path, name, nil, 0, 0, 0)
				guard len > 0 else { return nil }
				var buffer = [UInt8](repeating: 0, count: len)
				let actual = getxattr(path, name, &buffer, len, 0, 0)
				guard actual > 0 else { return nil }
				return String(bytes: buffer[0 ..< actual], encoding: .utf8)
			}
		}

		if let sel = readXattr("com.macromates.selectionRange") {
			selection = sel
		}
		if let vis = readXattr("com.macromates.visibleIndex"), let idx = Int(vis) {
			visibleIndex = idx
		}
		if let marks = readXattr("com.macromates.bookmarks") {
			bookmarks = marks.split(separator: ",").compactMap { Int($0) }
		}
		if let folded = readXattr("com.macromates.folded") {
			foldedRanges = folded.components(separatedBy: ";")
		}
	}
}

// MARK: - Document I/O Errors

public enum DocumentIOError: Error, LocalizedError, Sendable {
	case noPath
	case noContent
	case encodingFailed(String)
	case fileNotFound(String)
	case permissionDenied(String)
	case externallyModified(String)
	case mergeFailed

	public var errorDescription: String? {
		switch self {
		case .noPath:
			"The document has not been saved yet."
		case .noContent:
			"The document has no content to save."
		case let .encodingFailed(charset):
			"Could not encode the document using \(charset)."
		case let .fileNotFound(path):
			"File not found: \(path)"
		case let .permissionDenied(path):
			"Permission denied: \(path)"
		case let .externallyModified(path):
			"File has been modified externally: \(path)"
		case .mergeFailed:
			"Failed to merge external changes."
		}
	}
}
