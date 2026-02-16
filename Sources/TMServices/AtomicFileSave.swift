import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Atomic File Save

/// Volume-aware atomic file save, porting the C++ `path::intermediate_t`.
///
/// **Strategies:**
/// - `.always` — Use `NSFileManager.replaceItemAtURL` for maximum safety
/// - `.externalVolumes` — Atomic only on external volumes
/// - `.remoteVolumes` — Atomic only on network-mounted volumes
/// - `.never` — Write directly (fastest, least safe)
///
/// Usage:
/// ```swift
/// let saver = AtomicFileSave(destination: "/path/to/file.txt", atomicMode: .always)
/// let fd = try saver.open()
/// write(fd, data, data.count)
/// try saver.close()   // Commits the atomic swap
/// ```
public final class AtomicFileSave: @unchecked Sendable {
	// MARK: - Types

	/// When to use atomic-save behavior.
	public enum AtomicMode: Sendable {
		/// Always save atomically (safest).
		case always
		/// Only save atomically on external (non-internal) volumes.
		case externalVolumes
		/// Only save atomically on remote (network) volumes.
		case remoteVolumes
		/// Never save atomically (fastest).
		case never
	}

	/// Errors thrown by `AtomicFileSave`.
	public enum SaveError: Error, Sendable, CustomStringConvertible {
		case failedToObtainReplacementDirectory(String)
		case failedToOpenFile(String, Int32)
		case failedToCloseFile(Int32)
		case failedToCommit(String)

		public var description: String {
			switch self {
			case let .failedToObtainReplacementDirectory(msg): "Failed to obtain replacement directory: \(msg)"
			case let .failedToOpenFile(path, err): "open(\"\(path)\"): \(String(cString: strerror(err)))"
			case let .failedToCloseFile(err): "close(): \(String(cString: strerror(err)))"
			case let .failedToCommit(msg): "Failed to commit: \(msg)"
			}
		}
	}

	// MARK: - Strategy Protocol

	private protocol SaveStrategy {
		/// Returns the path to write to.
		func setup() throws -> String
		/// Commits the written data to the final destination.
		func commit() throws
		/// Cleanup on failure.
		func cleanup()
	}

	// MARK: - FileManager Strategy

	/// Uses `NSFileManager.replaceItemAtURL` for maximum safety.
	/// This is the equivalent of C++ `filemanager_strategy_t`.
	private final class FileManagerStrategy: SaveStrategy {
		private let destURL: URL
		private var tempDirectoryURL: URL?
		private var tempURL: URL?

		init(destURL: URL) {
			self.destURL = destURL
		}

		deinit {
			cleanup()
		}

		func setup() throws -> String {
			let fm = FileManager.default
			let tempDir = try fm.url(
				for: .itemReplacementDirectory,
				in: .userDomainMask,
				appropriateFor: destURL,
				create: true,
			)
			tempDirectoryURL = tempDir
			let temp = tempDir.appendingPathComponent(destURL.lastPathComponent)
			tempURL = temp
			return temp.path
		}

		func commit() throws {
			guard let tempURL else {
				throw SaveError.failedToCommit("No temporary URL")
			}

			// Copy metadata from existing file if it exists and is local
			if FileManager.default.fileExists(atPath: destURL.path) {
				var buf = stat()
				if stat(destURL.path, &buf) == 0 {
					let isLocal = PathUtilities.isLocal(destURL.path)
					if isLocal {
						copyfile(destURL.path, tempURL.path, nil, copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL))
					}
					chmod(tempURL.path, buf.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO))
				}
			}

			_ = try FileManager.default.replaceItemAt(destURL, withItemAt: tempURL)
			tempDirectoryURL = nil // Prevent cleanup from removing
		}

		func cleanup() {
			if let tempDir = tempDirectoryURL {
				try? FileManager.default.removeItem(at: tempDir)
				tempDirectoryURL = nil
			}
		}
	}

	// MARK: - Rename Strategy

	/// Write to a temporary file alongside the destination, then rename.
	/// Falls back to `rename` → `copyfile`.
	private final class RenameStrategy: SaveStrategy {
		private let resolvedDest: String
		private let intermediatePath: String

		init(dest: String) {
			resolvedDest = PathUtilities.resolveHead(dest)
			intermediatePath = Self.createPath(resolvedDest)
		}

		private static func createPath(_ path: String) -> String {
			if !PathUtilities.exists(path) {
				_ = PathUtilities.makeDir(PathUtilities.parent(path))
				return path
			}

			let tempDevice = PathUtilities.device(NSTemporaryDirectory())
			let pathDevice = PathUtilities.device(path)
			let parentWritable = access(PathUtilities.parent(path), W_OK) == 0

			if pathDevice != tempDevice, parentWritable {
				return path + "~"
			}
			return PathUtilities.temp()
		}

		func setup() throws -> String {
			intermediatePath
		}

		func commit() throws {
			if intermediatePath == resolvedDest { return }
			if !swapAndUnlink(src: intermediatePath, dst: resolvedDest) {
				throw SaveError.failedToCommit("Failed to swap \(intermediatePath) → \(resolvedDest)")
			}
		}

		func cleanup() {
			if intermediatePath != resolvedDest {
				try? FileManager.default.removeItem(atPath: intermediatePath)
			}
		}

		private func swapAndUnlink(src: String, dst: String) -> Bool {
			// Ensure parent directory exists
			if !FileManager.default.fileExists(atPath: dst) {
				_ = PathUtilities.makeDir(PathUtilities.parent(dst))
			}

			// Try exchangedata (preserves inode for hardlinks)
			if exchangedata(src, dst, 0) == 0 {
				unlink(src)
				return true
			}

			if errno == ENOTSUP || errno == ENOENT {
				// Copy metadata from dst if it exists and is local
				if errno == ENOTSUP, FileManager.default.fileExists(atPath: dst) {
					if PathUtilities.isLocal(src) {
						copyfile(dst, src, nil, copyfile_flags_t(COPYFILE_METADATA))
						utimes(src, nil)
					} else {
						var sbuf = stat()
						if stat(dst, &sbuf) == 0 {
							chmod(src, sbuf.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO))
						}
					}
				}

				// Try rename
				if Darwin.rename(src, dst) == 0 {
					return true
				}
			}

			if errno == EXDEV {
				// Cross-device: copy + remove
				if copyfile(src, dst, nil, copyfile_flags_t(COPYFILE_DATA | COPYFILE_MOVE)) == 0 {
					unlink(src)
					return true
				}
			}

			return false
		}
	}

	// MARK: - Non-Atomic Strategy

	/// Write directly to the destination without any safety measures.
	private final class DirectStrategy: SaveStrategy {
		private let path: String
		init(path: String) {
			self.path = path
		}

		func setup() throws -> String {
			path
		}

		func commit() throws { /* nothing to do */ }
		func cleanup() { /* nothing to do */ }
	}

	// MARK: - Properties

	private let strategy: SaveStrategy
	private let mode: mode_t
	private var fileDescriptor: Int32 = -1

	// MARK: - Init

	/// Create an atomic file saver.
	///
	/// - Parameters:
	///   - destination: The final destination path.
	///   - atomicMode: When to use atomic save behavior.
	///   - mode: File permission mode (default: 0o644).
	public init(
		destination: String,
		atomicMode: AtomicMode = .always,
		mode: mode_t = S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH,
	) {
		let dest = PathUtilities.resolveHead(destination)
		var actualMode = mode

		if PathUtilities.exists(dest) {
			// Preserve existing file mode
			var buf = stat()
			if stat(dest, &buf) == 0 {
				actualMode = buf.st_mode
			}

			let url = URL(fileURLWithPath: dest)
			let isInternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]))?.volumeIsInternal ?? false
			let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? true

			let shouldBeAtomic: Bool = switch atomicMode {
			case .always:
				true
			case .externalVolumes:
				!isInternal
			case .remoteVolumes:
				!isLocal
			case .never:
				false
			}

			if shouldBeAtomic {
				strategy = FileManagerStrategy(destURL: url)
			} else {
				strategy = DirectStrategy(path: dest)
			}
		} else {
			// New file: no atomic needed
			strategy = DirectStrategy(path: dest)
		}

		self.mode = actualMode
	}

	deinit {
		if fileDescriptor != -1 {
			Darwin.close(fileDescriptor)
		}
	}

	// MARK: - Open / Close

	/// Open the file for writing and return the file descriptor.
	///
	/// - Parameter flags: Open flags (default: `O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC`).
	/// - Returns: The file descriptor.
	public func open(flags: Int32 = O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC) throws -> Int32 {
		let path = try strategy.setup()
		fileDescriptor = Darwin.open(path, flags, mode)
		if fileDescriptor == -1 {
			throw SaveError.failedToOpenFile(path, errno)
		}
		return fileDescriptor
	}

	/// Close the file and commit the atomic save.
	public func close() throws {
		guard fileDescriptor != -1 else { return }
		let result = Darwin.close(fileDescriptor)
		fileDescriptor = -1

		if result == -1 {
			strategy.cleanup()
			throw SaveError.failedToCloseFile(errno)
		}

		try strategy.commit()
	}

	/// Write data to the file.
	///
	/// - Parameter data: The data to write.
	/// - Returns: The number of bytes written.
	@discardableResult
	public func write(_ data: Data) throws -> Int {
		try data.withUnsafeBytes { buffer in
			guard let base = buffer.baseAddress else { return 0 }
			let written = Darwin.write(fileDescriptor, base, buffer.count)
			if written == -1 {
				throw SaveError.failedToOpenFile("write", errno)
			}
			return written
		}
	}
}
