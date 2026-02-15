import Foundation

// MARK: - Backup Record

/// Metadata for a backed-up document.
public struct BackupRecord: Codable, Sendable, Equatable {
	/// The document UUID.
	public var documentID: UUID

	/// Original file path, or nil for untitled.
	public var originalPath: String?

	/// The backup file path within the backup directory.
	public var backupFilename: String

	/// Display name (for window title restoration).
	public var displayName: String

	/// Grammar scope at time of backup.
	public var fileType: String?

	/// Encoding used to save the backup.
	public var encoding: DocumentEncoding

	/// Selection state.
	public var selection: String?

	/// When the backup was created.
	public var createdAt: Date

	public init(
		documentID: UUID,
		originalPath: String? = nil,
		backupFilename: String,
		displayName: String,
		fileType: String? = nil,
		encoding: DocumentEncoding = .utf8,
		selection: String? = nil,
		createdAt: Date = Date(),
	) {
		self.documentID = documentID
		self.originalPath = originalPath
		self.backupFilename = backupFilename
		self.displayName = displayName
		self.fileType = fileType
		self.encoding = encoding
		self.selection = selection
		self.createdAt = createdAt
	}
}

// MARK: - Backup Manifest

/// The manifest listing all backed-up documents.
public struct BackupManifest: Codable, Sendable, Equatable {
	/// Manifest version.
	public var version: Int = 1

	/// All backup records.
	public var records: [BackupRecord]

	/// When the manifest was last updated.
	public var updatedAt: Date

	public init(
		records: [BackupRecord] = [],
		updatedAt: Date = Date(),
	) {
		version = 1
		self.records = records
		self.updatedAt = updatedAt
	}
}

// MARK: - Document Backup Manager

/// Manages automatic backup of unsaved documents for crash recovery.
///
/// Equivalent to the C++ backup mechanism in OakDocument. When a document
/// has unsaved changes, its content is periodically flushed to a backup
/// directory. On app launch, existing backups are detected and offered
/// for recovery.
@MainActor
public final class DocumentBackupManager {
	/// Default backup directory.
	public static let defaultBackupDirectory: URL = {
		let appSupport = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
		).first!
		return appSupport
			.appendingPathComponent("TextMate")
			.appendingPathComponent("Backups")
	}()

	/// The backup directory URL.
	public let backupDirectory: URL

	/// The manifest file URL.
	public var manifestURL: URL {
		backupDirectory.appendingPathComponent("manifest.json")
	}

	/// The current manifest.
	private var manifest: BackupManifest = .init()

	/// Backup interval in seconds (default: 30).
	public var backupInterval: TimeInterval = 30

	/// Whether auto-backup is running.
	public private(set) var isRunning: Bool = false

	/// Timer for periodic backups.
	private var timer: Timer?

	public init(directory: URL? = nil) {
		backupDirectory = directory ?? Self.defaultBackupDirectory
		loadManifest()
	}

	// MARK: - Auto-Backup Lifecycle

	/// Starts periodic auto-backup.
	public func start() {
		guard !isRunning else { return }
		isRunning = true

		timer = Timer.scheduledTimer(withTimeInterval: backupInterval, repeats: true) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.backupAllModifiedDocuments()
			}
		}
	}

	/// Stops periodic auto-backup.
	public func stop() {
		timer?.invalidate()
		timer = nil
		isRunning = false
	}

	// MARK: - Backup Operations

	/// Backs up a single document.
	public func backup(_ document: TMDocument) throws {
		guard document.isModified, let content = document.content else { return }

		// Ensure directory exists
		try FileManager.default.createDirectory(
			at: backupDirectory,
			withIntermediateDirectories: true,
		)

		let backupFilename = "\(document.id.uuidString).txt"
		let backupURL = backupDirectory.appendingPathComponent(backupFilename)

		// Write content
		try content.write(to: backupURL, atomically: true, encoding: .utf8)

		// Update manifest
		manifest.records.removeAll { $0.documentID == document.id }
		manifest.records.append(BackupRecord(
			documentID: document.id,
			originalPath: document.path,
			backupFilename: backupFilename,
			displayName: document.displayName,
			fileType: document.fileType,
			encoding: document.encoding,
			selection: document.selection,
		))
		manifest.updatedAt = Date()

		try saveManifest()
		document.backupPath = backupURL.path
		document.needsBackup = false
	}

	/// Backs up all modified documents that need backup.
	public func backupAllModifiedDocuments() {
		let controller = TMDocumentController.shared
		for doc in controller.documents where doc.needsBackup {
			try? backup(doc)
		}
	}

	/// Removes the backup for a specific document (e.g., after successful save).
	public func removeBackup(for document: TMDocument) {
		manifest.records.removeAll { $0.documentID == document.id }

		let backupFilename = "\(document.id.uuidString).txt"
		let backupURL = backupDirectory.appendingPathComponent(backupFilename)
		try? FileManager.default.removeItem(at: backupURL)
		try? saveManifest()

		document.backupPath = nil
	}

	// MARK: - Recovery

	/// Returns backup records for documents that can be recovered.
	public var recoverableDocuments: [BackupRecord] {
		manifest.records.filter { record in
			let url = backupDirectory.appendingPathComponent(record.backupFilename)
			return FileManager.default.fileExists(atPath: url.path)
		}
	}

	/// Whether there are documents to recover.
	public var hasRecoverableDocuments: Bool {
		!recoverableDocuments.isEmpty
	}

	/// Recovers a backed-up document, restoring its content.
	public func recover(_ record: BackupRecord) throws -> TMDocument {
		let backupURL = backupDirectory.appendingPathComponent(record.backupFilename)
		let content = try String(contentsOf: backupURL, encoding: .utf8)

		let doc: TMDocument = if let path = record.originalPath {
			TMDocumentController.shared.documentForPath(path, fileType: record.fileType)
		} else {
			TMDocumentController.shared.createUntitledDocument(fileType: record.fileType)
		}

		doc.setContent(content, preserveRevision: false)
		doc.encoding = record.encoding
		doc.selection = record.selection

		return doc
	}

	/// Recovers all backed-up documents.
	public func recoverAll() throws -> [TMDocument] {
		try recoverableDocuments.map { try recover($0) }
	}

	/// Discards all backups (e.g., user chose not to recover).
	public func discardAll() throws {
		manifest.records.removeAll()
		try saveManifest()

		// Remove backup files but keep the directory
		let contents = try? FileManager.default.contentsOfDirectory(
			at: backupDirectory,
			includingPropertiesForKeys: nil,
		)
		for url in contents ?? [] {
			if url.lastPathComponent != "manifest.json" {
				try? FileManager.default.removeItem(at: url)
			}
		}
	}

	// MARK: - Manifest Persistence

	private func loadManifest() {
		guard FileManager.default.fileExists(atPath: manifestURL.path),
		      let data = try? Data(contentsOf: manifestURL)
		else { return }

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		manifest = (try? decoder.decode(BackupManifest.self, from: data)) ?? BackupManifest()
	}

	private func saveManifest() throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(manifest)
		try data.write(to: manifestURL, options: .atomic)
	}

	// MARK: - Cleanup

	/// Removes all backups and resets state. Useful for testing.
	public func removeAll() throws {
		manifest = BackupManifest()
		if FileManager.default.fileExists(atPath: backupDirectory.path) {
			try FileManager.default.removeItem(at: backupDirectory)
		}
	}
}
