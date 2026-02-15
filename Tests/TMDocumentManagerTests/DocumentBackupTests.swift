import Foundation
import Testing
@testable import TMDocumentManager

@Suite("DocumentBackupManager - Auto-Save and Recovery")
@MainActor
struct DocumentBackupTests {
	private func freshBackupManager() -> DocumentBackupManager {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("tm_backup_test_\(UUID().uuidString)")
		return DocumentBackupManager(directory: dir)
	}

	private func cleanup(_ manager: DocumentBackupManager) {
		try? manager.removeAll()
	}

	// MARK: - Backup

	@Test("Backup modified document")
	func backupModified() throws {
		let manager = freshBackupManager()
		defer { cleanup(manager) }
		TMDocumentController.shared.removeAll()

		let doc = TMDocument(path: "/tmp/backup_test.txt")
		doc.setContent("Hello, backup!")
		doc.markModified()

		try manager.backup(doc)

		#expect(!doc.needsBackup)
		#expect(doc.backupPath != nil)
		#expect(manager.hasRecoverableDocuments)
	}

	@Test("Backup unmodified document is no-op")
	func backupUnmodified() throws {
		let manager = freshBackupManager()
		defer { cleanup(manager) }

		let doc = TMDocument(path: "/tmp/backup_unmod.txt")
		doc.setContent("content", preserveRevision: true)

		try manager.backup(doc)
		#expect(!manager.hasRecoverableDocuments)
	}

	@Test("Backup document without content is no-op")
	func backupNoContent() throws {
		let manager = freshBackupManager()
		defer { cleanup(manager) }

		let doc = TMDocument(path: "/tmp/backup_empty.txt")
		doc.markModified()

		try manager.backup(doc)
		#expect(!manager.hasRecoverableDocuments)
	}

	// MARK: - Recovery

	@Test("Recover backed-up document")
	func recoverDocument() throws {
		let manager = freshBackupManager()
		defer { cleanup(manager) }
		TMDocumentController.shared.removeAll()

		let doc = TMDocument(path: "/tmp/recover_test.txt")
		doc.setContent("Recoverable content")
		doc.encoding = .utf8
		doc.selection = "1:0"
		TMDocumentController.shared.register(doc)

		try manager.backup(doc)

		let records = manager.recoverableDocuments
		#expect(records.count == 1)

		let recovered = try manager.recover(records[0])
		#expect(recovered.content == "Recoverable content")
		#expect(recovered.selection == "1:0")
	}

	@Test("Recover all documents")
	func recoverAll() throws {
		let manager = freshBackupManager()
		defer { cleanup(manager) }
		TMDocumentController.shared.removeAll()

		let doc1 = TMDocument(path: "/tmp/recover_all_1.txt")
		doc1.setContent("Content 1")
		TMDocumentController.shared.register(doc1)

		let doc2 = TMDocument(path: "/tmp/recover_all_2.txt")
		doc2.setContent("Content 2")
		TMDocumentController.shared.register(doc2)

		try manager.backup(doc1)
		try manager.backup(doc2)

		let recovered = try manager.recoverAll()
		#expect(recovered.count == 2)
	}

	// MARK: - Remove Backup

	@Test("Remove backup clears document's backup")
	func removeBackup() throws {
		let manager = freshBackupManager()
		defer { cleanup(manager) }
		TMDocumentController.shared.removeAll()

		let doc = TMDocument(path: "/tmp/rm_backup.txt")
		doc.setContent("Content")
		TMDocumentController.shared.register(doc)

		try manager.backup(doc)
		#expect(doc.backupPath != nil)

		manager.removeBackup(for: doc)
		#expect(doc.backupPath == nil)
		#expect(!manager.hasRecoverableDocuments)
	}

	// MARK: - Discard All

	@Test("Discard all removes all backups")
	func discardAll() throws {
		let manager = freshBackupManager()
		defer { cleanup(manager) }
		TMDocumentController.shared.removeAll()

		let doc = TMDocument(path: "/tmp/discard.txt")
		doc.setContent("Content")
		TMDocumentController.shared.register(doc)

		try manager.backup(doc)
		try manager.discardAll()

		#expect(!manager.hasRecoverableDocuments)
	}

	// MARK: - Lifecycle

	@Test("Start and stop auto-backup")
	func startStop() {
		let manager = freshBackupManager()
		defer { cleanup(manager) }

		#expect(!manager.isRunning)
		manager.start()
		#expect(manager.isRunning)
		manager.stop()
		#expect(!manager.isRunning)
	}

	@Test("Double start is safe")
	func doubleStart() {
		let manager = freshBackupManager()
		defer { cleanup(manager) }

		manager.start()
		manager.start() // Should not crash
		#expect(manager.isRunning)
		manager.stop()
	}

	// MARK: - Backup Interval

	@Test("Default backup interval")
	func defaultInterval() {
		let manager = freshBackupManager()
		defer { cleanup(manager) }
		#expect(manager.backupInterval == 30)
	}

	@Test("Custom backup interval")
	func customInterval() {
		let manager = freshBackupManager()
		defer { cleanup(manager) }
		manager.backupInterval = 60
		#expect(manager.backupInterval == 60)
	}
}

// MARK: - BackupRecord Tests

@Suite("BackupRecord")
struct BackupRecordTests {
	@Test("BackupRecord initialization")
	func initialization() {
		let id = UUID()
		let record = BackupRecord(
			documentID: id,
			originalPath: "/tmp/orig.txt",
			backupFilename: "\(id.uuidString).txt",
			displayName: "orig.txt",
			fileType: "text.plain",
		)
		#expect(record.documentID == id)
		#expect(record.originalPath == "/tmp/orig.txt")
		#expect(record.displayName == "orig.txt")
		#expect(record.fileType == "text.plain")
	}

	@Test("BackupRecord codable round-trip")
	func codable() throws {
		// Use a date with no sub-second precision so ISO 8601 round-trips exactly
		let date = Date(timeIntervalSinceReferenceDate: Double(Int(Date().timeIntervalSinceReferenceDate)))
		let record = BackupRecord(
			documentID: UUID(),
			originalPath: "/tmp/codable.txt",
			backupFilename: "test.txt",
			displayName: "codable.txt",
			fileType: "source.swift",
			encoding: .utf8,
			selection: "1:0-2:5",
			createdAt: date,
		)

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(record)

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let decoded = try decoder.decode(BackupRecord.self, from: data)

		#expect(decoded == record)
	}
}

// MARK: - BackupManifest Tests

@Suite("BackupManifest")
struct BackupManifestTests {
	@Test("Empty manifest")
	func emptyManifest() {
		let manifest = BackupManifest()
		#expect(manifest.version == 1)
		#expect(manifest.records.isEmpty)
	}

	@Test("Manifest codable round-trip")
	func codable() throws {
		let manifest = BackupManifest(
			records: [
				BackupRecord(
					documentID: UUID(),
					backupFilename: "test.txt",
					displayName: "test.txt",
				),
			],
		)

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(manifest)

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let decoded = try decoder.decode(BackupManifest.self, from: data)

		#expect(decoded.version == 1)
		#expect(decoded.records.count == 1)
	}
}
