import Foundation
import Testing
@testable import TMCore

@Suite("AtomicFileWriter")
struct AtomicFileWriterTests {
	@Test("write string with always-atomic mode")
	func writeStringAtomic() throws {
		let path = PathUtilities.temp() + "/tm_test_atomic_\(ProcessInfo.processInfo.processIdentifier).txt"
		defer { PathUtilities.remove(path) }

		let writer = AtomicFileWriter(destination: path, mode: .always)
		try writer.write("Hello, atomic!")
		#expect(PathUtilities.content(path) == "Hello, atomic!")
	}

	@Test("write Data with always-atomic mode")
	func writeDataAtomic() throws {
		let path = PathUtilities.temp() + "/tm_test_atomic_data_\(ProcessInfo.processInfo.processIdentifier).bin"
		defer { PathUtilities.remove(path) }

		let data = Data([0x01, 0x02, 0x03, 0x04])
		let writer = AtomicFileWriter(destination: path, mode: .always)
		try writer.write(data)

		let readBack = try Data(contentsOf: URL(fileURLWithPath: path))
		#expect(readBack == data)
	}

	@Test("write string with never-atomic mode")
	func writeStringDirect() throws {
		let path = PathUtilities.temp() + "/tm_test_direct_\(ProcessInfo.processInfo.processIdentifier).txt"
		defer { PathUtilities.remove(path) }

		let writer = AtomicFileWriter(destination: path, mode: .never)
		try writer.write("Hello, direct!")
		#expect(PathUtilities.content(path) == "Hello, direct!")
	}

	@Test("write overwrites existing content")
	func overwrite() throws {
		let path = PathUtilities.temp() + "/tm_test_overwrite_\(ProcessInfo.processInfo.processIdentifier).txt"
		defer { PathUtilities.remove(path) }

		let writer1 = AtomicFileWriter(destination: path, mode: .always)
		try writer1.write("first")
		let writer2 = AtomicFileWriter(destination: path, mode: .always)
		try writer2.write("second")
		#expect(PathUtilities.content(path) == "second")
	}

	@Test("write preserves file permissions when overwriting")
	func preservePermissions() throws {
		let path = PathUtilities.temp() + "/tm_test_perms_\(ProcessInfo.processInfo.processIdentifier).txt"
		defer { PathUtilities.remove(path) }

		let writer1 = AtomicFileWriter(destination: path, mode: .always)
		try writer1.write("initial")

		// Set specific permissions
		chmod(path, 0o644)
		var st = stat()
		stat(path, &st)
		let originalMode = st.st_mode & 0o777

		let writer2 = AtomicFileWriter(destination: path, mode: .always)
		try writer2.write("updated")

		stat(path, &st)
		let newMode = st.st_mode & 0o777
		#expect(newMode == originalMode)
	}

	@Test("write to invalid path throws error")
	func writeToInvalidPath() {
		#expect(throws: (any Error).self) {
			let writer = AtomicFileWriter(
				destination: "/nonexistent_dir_12345/foo.txt",
				mode: .always,
			)
			try writer.write("fail")
		}
	}

	@Test("write empty data succeeds")
	func writeEmptyData() throws {
		let path = PathUtilities.temp() + "/tm_test_empty_\(ProcessInfo.processInfo.processIdentifier).txt"
		defer { PathUtilities.remove(path) }

		let writer = AtomicFileWriter(destination: path, mode: .always)
		try writer.write(Data())
		#expect(PathUtilities.exists(path))
		let readBack = try Data(contentsOf: URL(fileURLWithPath: path))
		#expect(readBack.isEmpty)
	}
}
