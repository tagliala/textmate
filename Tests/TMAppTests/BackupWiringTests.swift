#if canImport(AppKit)
import Foundation
import Testing
import TMDocumentManager

@Suite("DocumentBackupManager — App Wiring")
@MainActor
struct BackupWiringTests {
	@Test("shared singleton is consistent")
	func sharedSingleton() {
		let a = DocumentBackupManager.shared
		let b = DocumentBackupManager.shared
		#expect(a === b)
	}

	@Test("start and stop toggle isRunning")
	func startStop() {
		let mgr = DocumentBackupManager(directory: URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("BackupWiringTest-\(UUID().uuidString)"))
		#expect(!mgr.isRunning)
		mgr.start()
		#expect(mgr.isRunning)
		mgr.stop()
		#expect(!mgr.isRunning)
	}

	@Test("backup creates file for modified document")
	func backupCreatesFile() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("BackupWiringTest-\(UUID().uuidString)")
		let mgr = DocumentBackupManager(directory: dir)
		defer { try? mgr.removeAll() }

		let doc = TMDocumentController.shared.createUntitledDocument()
		doc.setContent("hello backup", preserveRevision: false)

		try mgr.backup(doc)

		let backupURL = dir.appendingPathComponent("\(doc.id.uuidString).txt")
		#expect(FileManager.default.fileExists(atPath: backupURL.path))
		#expect(doc.backupPath == backupURL.path)
	}

	@Test("removeBackup clears backup file and path")
	func removeBackup() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("BackupWiringTest-\(UUID().uuidString)")
		let mgr = DocumentBackupManager(directory: dir)
		defer { try? mgr.removeAll() }

		let doc = TMDocumentController.shared.createUntitledDocument()
		doc.setContent("to be removed", preserveRevision: false)
		try mgr.backup(doc)

		mgr.removeBackup(for: doc)

		let backupURL = dir.appendingPathComponent("\(doc.id.uuidString).txt")
		#expect(!FileManager.default.fileExists(atPath: backupURL.path))
		#expect(doc.backupPath == nil)
	}

	@Test("recovery round-trip restores content")
	func recoveryRoundTrip() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("BackupWiringTest-\(UUID().uuidString)")
		let mgr = DocumentBackupManager(directory: dir)
		defer { try? mgr.removeAll() }

		let doc = TMDocumentController.shared.createUntitledDocument()
		doc.setContent("recover me", preserveRevision: false)
		try mgr.backup(doc)

		#expect(mgr.hasRecoverableDocuments)
		let records = mgr.recoverableDocuments
		#expect(records.count == 1)

		let recovered = try mgr.recover(records[0])
		#expect(recovered.content == "recover me")
	}
}
#endif
