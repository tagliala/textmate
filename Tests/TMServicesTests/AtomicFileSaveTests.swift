import Foundation
import Testing
@testable import TMServices

@Suite("AtomicFileSave")
struct AtomicFileSaveTests {
	@Test("Direct save writes content")
	func directSave() throws {
		let tmp = NSTemporaryDirectory() + "atomic_direct_\(UUID().uuidString).txt"
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let saver = AtomicFileSave(destination: tmp, atomicMode: .never)
		let fd = try saver.open()
		#expect(fd >= 0)

		let data = Data("direct write".utf8)
		try saver.write(data)
		try saver.close()

		let content = try Data(contentsOf: URL(fileURLWithPath: tmp))
		#expect(content == data)
	}

	@Test("Atomic save via FileManager strategy")
	func atomicFileManagerSave() throws {
		let tmp = NSTemporaryDirectory() + "atomic_fm_\(UUID().uuidString).txt"
		// Create initial file
		try Data("original".utf8).write(to: URL(fileURLWithPath: tmp))
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let saver = AtomicFileSave(destination: tmp, atomicMode: .always)
		let fd = try saver.open()
		#expect(fd >= 0)

		let newData = Data("replaced content".utf8)
		try saver.write(newData)
		try saver.close()

		let content = try Data(contentsOf: URL(fileURLWithPath: tmp))
		#expect(content == newData)
	}

	@Test("AtomicMode enum cases exist")
	func atomicModes() {
		let modes: [AtomicFileSave.AtomicMode] = [.always, .externalVolumes, .remoteVolumes, .never]
		#expect(modes.count == 4)
	}

	@Test("SaveError descriptions are non-empty")
	func errorDescriptions() {
		let errors: [AtomicFileSave.SaveError] = [
			.failedToObtainReplacementDirectory("test"),
			.failedToOpenFile("test", 2),
			.failedToCloseFile(5),
			.failedToCommit("test"),
		]
		for error in errors {
			#expect(!error.localizedDescription.isEmpty)
		}
	}

	@Test("Multiple writes accumulate")
	func multipleWrites() throws {
		let tmp = NSTemporaryDirectory() + "atomic_multi_\(UUID().uuidString).txt"
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let saver = AtomicFileSave(destination: tmp, atomicMode: .never)
		_ = try saver.open()

		try saver.write(Data("hello ".utf8))
		try saver.write(Data("world".utf8))
		try saver.close()

		let content = try String(contentsOf: URL(fileURLWithPath: tmp), encoding: .utf8)
		#expect(content == "hello world")
	}

	@Test("Permissions are set on file")
	func permissions() throws {
		let tmp = NSTemporaryDirectory() + "atomic_perm_\(UUID().uuidString).txt"
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let saver = AtomicFileSave(destination: tmp, atomicMode: .never, mode: 0o644)
		_ = try saver.open()
		try saver.write(Data("permtest".utf8))
		try saver.close()

		var stat_buf = stat()
		stat(tmp, &stat_buf)
		let perms = stat_buf.st_mode & 0o777
		#expect(perms == 0o644)
	}
}
