import Foundation
import Testing
@testable import TMServices

@Suite("ExtendedAttributes")
struct ExtendedAttributesTests {
	// MARK: - Read / Write / Remove

	@Test("Write and read string xattr")
	func writeAndReadString() {
		let tmp = NSTemporaryDirectory() + "xattr_test_\(UUID().uuidString)"
		FileManager.default.createFile(atPath: tmp, contents: Data())
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let name = "com.test.xattr"
		let value = "hello world"

		let written = ExtendedAttributes.writeString(name: name, value: value, at: tmp)
		#expect(written)

		let read = ExtendedAttributes.readString(name: name, at: tmp)
		#expect(read == value)
	}

	@Test("Write and read raw data xattr")
	func writeAndReadData() {
		let tmp = NSTemporaryDirectory() + "xattr_data_\(UUID().uuidString)"
		FileManager.default.createFile(atPath: tmp, contents: Data())
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let name = "com.test.binary"
		let data = Data([0x00, 0x01, 0x02, 0xFF])

		let written = ExtendedAttributes.write(name: name, data: data, at: tmp)
		#expect(written)

		let read = ExtendedAttributes.read(name: name, at: tmp)
		#expect(read == data)
	}

	@Test("Read nonexistent xattr returns nil")
	func readNonexistent() {
		let tmp = NSTemporaryDirectory() + "xattr_none_\(UUID().uuidString)"
		FileManager.default.createFile(atPath: tmp, contents: Data())
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		#expect(ExtendedAttributes.read(name: "com.test.nope", at: tmp) == nil)
		#expect(ExtendedAttributes.readString(name: "com.test.nope", at: tmp) == nil)
	}

	@Test("Remove xattr")
	func removeXattr() {
		let tmp = NSTemporaryDirectory() + "xattr_rm_\(UUID().uuidString)"
		FileManager.default.createFile(atPath: tmp, contents: Data())
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		ExtendedAttributes.writeString(name: "com.test.rm", value: "val", at: tmp)
		#expect(ExtendedAttributes.readString(name: "com.test.rm", at: tmp) == "val")

		let removed = ExtendedAttributes.remove(name: "com.test.rm", at: tmp)
		#expect(removed)
		#expect(ExtendedAttributes.readString(name: "com.test.rm", at: tmp) == nil)
	}

	@Test("List xattr names")
	func listXattrs() {
		let tmp = NSTemporaryDirectory() + "xattr_list_\(UUID().uuidString)"
		FileManager.default.createFile(atPath: tmp, contents: Data())
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		ExtendedAttributes.writeString(name: "com.test.a", value: "1", at: tmp)
		ExtendedAttributes.writeString(name: "com.test.b", value: "2", at: tmp)

		let names = ExtendedAttributes.list(at: tmp)
		#expect(names.contains("com.test.a"))
		#expect(names.contains("com.test.b"))
	}

	@Test("File descriptor read and write")
	func fileDescriptorVariants() {
		let tmp = NSTemporaryDirectory() + "xattr_fd_\(UUID().uuidString)"
		FileManager.default.createFile(atPath: tmp, contents: Data())
		defer { try? FileManager.default.removeItem(atPath: tmp) }

		let fd = open(tmp, O_RDWR)
		guard fd >= 0 else {
			Issue.record("Failed to open file")
			return
		}
		defer { close(fd) }

		let name = "com.test.fd"
		let data = Data("fd test".utf8)
		let written = ExtendedAttributes.write(name: name, data: data, fd: fd)
		#expect(written)

		let read = ExtendedAttributes.read(name: name, fd: fd)
		#expect(read == data)
	}

	@Test("Read from nonexistent path returns nil")
	func readFromNonexistentPath() {
		#expect(ExtendedAttributes.read(name: "com.test.x", at: "/tmp/nonexistent_\(UUID())") == nil)
	}
}
