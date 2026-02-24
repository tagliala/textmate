import Foundation

// MARK: - Session Document Info

/// Serializable snapshot of a document's state within a session.
public struct SessionDocumentInfo: Codable, Sendable, Equatable {
	/// The document UUID.
	public var id: UUID

	/// The file path, or nil for untitled documents.
	public var path: String?

	/// The display name (for untitled documents).
	public var displayName: String?

	/// Grammar scope (file type).
	public var fileType: String?

	/// Selection ranges.
	public var selection: String?

	/// Visible scroll index.
	public var visibleIndex: Int

	/// Whether the document was modified but unsaved.
	public var isModified: Bool

	/// Unsaved content for modified untitled documents.
	public var content: String?

	/// Tab size.
	public var tabSize: Int

	/// Whether soft tabs are enabled.
	public var softTabs: Bool

	/// Folded ranges.
	public var foldedRanges: [String]

	/// Bookmarks.
	public var bookmarks: [Int]

	public init(
		id: UUID = UUID(),
		path: String? = nil,
		displayName: String? = nil,
		fileType: String? = nil,
		selection: String? = nil,
		visibleIndex: Int = 0,
		isModified: Bool = false,
		content: String? = nil,
		tabSize: Int = 4,
		softTabs: Bool = false,
		foldedRanges: [String] = [],
		bookmarks: [Int] = [],
	) {
		self.id = id
		self.path = path
		self.displayName = displayName
		self.fileType = fileType
		self.selection = selection
		self.visibleIndex = visibleIndex
		self.isModified = isModified
		self.content = content
		self.tabSize = tabSize
		self.softTabs = softTabs
		self.foldedRanges = foldedRanges
		self.bookmarks = bookmarks
	}
}

// MARK: - Session Window Info

/// Serializable snapshot of a window's state.
public struct SessionWindowInfo: Codable, Sendable, Equatable {
	/// Window frame as (x, y, width, height).
	public var frame: WindowFrame

	/// Documents open in this window (tab order).
	public var documents: [SessionDocumentInfo]

	/// Index of the selected (active) document.
	public var selectedDocumentIndex: Int

	/// File browser root path, if the file browser is open.
	public var fileBrowserPath: String?

	/// Whether the file browser is visible.
	public var fileBrowserVisible: Bool

	/// File browser width when visible.
	public var fileBrowserWidth: Double

	/// Whether the project is in "mini" mode (no file browser, no tabs).
	public var isMiniaturized: Bool

	public init(
		frame: WindowFrame = WindowFrame(),
		documents: [SessionDocumentInfo] = [],
		selectedDocumentIndex: Int = 0,
		fileBrowserPath: String? = nil,
		fileBrowserVisible: Bool = false,
		fileBrowserWidth: Double = 200,
		isMiniaturized: Bool = false,
	) {
		self.frame = frame
		self.documents = documents
		self.selectedDocumentIndex = selectedDocumentIndex
		self.fileBrowserPath = fileBrowserPath
		self.fileBrowserVisible = fileBrowserVisible
		self.fileBrowserWidth = fileBrowserWidth
		self.isMiniaturized = isMiniaturized
	}
}

// MARK: - Window Frame

/// A serializable window frame.
public struct WindowFrame: Codable, Sendable, Equatable {
	public var x: Double
	public var y: Double
	public var width: Double
	public var height: Double

	public init(x: Double = 0, y: Double = 0, width: Double = 800, height: Double = 600) {
		self.x = x
		self.y = y
		self.width = width
		self.height = height
	}
}

// MARK: - Session

/// The full application session — a collection of window states.
public struct DocumentSession: Codable, Sendable, Equatable {
	/// Version of the session format.
	public var version: Int = 1

	/// Window states in the session.
	public var windows: [SessionWindowInfo]

	/// Global marks/bookmarks (path → line numbers).
	public var globalMarks: [String: [Int]]

	/// Recently opened file paths.
	public var recentFiles: [String]

	/// When this session was saved.
	public var savedAt: Date

	public init(
		windows: [SessionWindowInfo] = [],
		globalMarks: [String: [Int]] = [:],
		recentFiles: [String] = [],
		savedAt: Date = Date(),
	) {
		version = 1
		self.windows = windows
		self.globalMarks = globalMarks
		self.recentFiles = recentFiles
		self.savedAt = savedAt
	}
}

// MARK: - Document Session Snapshot

public extension SessionDocumentInfo {
	/// Creates a `SessionDocumentInfo` from a live `TMDocument`.
	@MainActor
	static func from(document: TMDocument) -> SessionDocumentInfo {
		SessionDocumentInfo(
			id: document.id,
			path: document.path,
			displayName: document.customName ?? document.displayName,
			fileType: document.fileType,
			selection: document.selection,
			visibleIndex: document.visibleIndex,
			isModified: document.isModified,
			content: document.path == nil && document.isModified ? document.content : nil,
			tabSize: document.tabSize,
			softTabs: document.softTabs,
			foldedRanges: document.foldedRanges,
			bookmarks: document.bookmarks,
		)
	}

	/// Restores a `TMDocument` from session info.
	@MainActor
	func restore() -> TMDocument {
		let doc: TMDocument = if let path {
			TMDocumentController.shared.documentForPath(path, fileType: fileType)
		} else {
			TMDocumentController.shared.createUntitledDocument(fileType: fileType)
		}

		doc.selection = selection
		doc.visibleIndex = visibleIndex
		doc.tabSize = tabSize
		doc.softTabs = softTabs
		doc.foldedRanges = foldedRanges
		doc.bookmarks = bookmarks

		if let content, path == nil {
			doc.setContent(content, preserveRevision: false)
		}

		return doc
	}
}

// MARK: - Session Manager

/// Manages session persistence — save and restore of application state.
@MainActor
public final class SessionManager {
	/// Default session directory.
	public static let defaultSessionDirectory: URL = {
		let appSupport = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
		).first!
		return appSupport
			.appendingPathComponent("TextMate")
			.appendingPathComponent("Session")
	}()

	/// The session file URL.
	public let sessionURL: URL

	public init(directory: URL? = nil) {
		let dir = directory ?? Self.defaultSessionDirectory
		sessionURL = dir.appendingPathComponent("session.json")
	}

	// MARK: - Save

	/// Saves the given session to disk.
	public func save(_ session: DocumentSession) throws {
		let dir = sessionURL.deletingLastPathComponent()
		try FileManager.default.createDirectory(
			at: dir,
			withIntermediateDirectories: true,
		)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(session)
		try data.write(to: sessionURL, options: .atomic)
	}

	/// Builds a `DocumentSession` from the currently provided document list.
	public func captureSession(
		windows: [SessionWindowInfo],
		recentFiles: [String] = [],
		globalMarks: [String: [Int]] = [:],
	) -> DocumentSession {
		DocumentSession(
			windows: windows,
			globalMarks: globalMarks,
			recentFiles: recentFiles,
			savedAt: Date(),
		)
	}

	// MARK: - Restore

	/// Loads the last saved session from disk.
	public func restore() throws -> DocumentSession {
		let data = try Data(contentsOf: sessionURL)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(DocumentSession.self, from: data)
	}

	/// Whether a saved session exists on disk.
	public var hasSavedSession: Bool {
		FileManager.default.fileExists(atPath: sessionURL.path)
	}

	// MARK: - Delete

	/// Deletes the saved session file.
	public func deleteSavedSession() throws {
		if FileManager.default.fileExists(atPath: sessionURL.path) {
			try FileManager.default.removeItem(at: sessionURL)
		}
	}
}
