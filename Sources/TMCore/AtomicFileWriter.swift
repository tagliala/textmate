import Foundation

/// Port of C++ `path::intermediate_t` (io/src/intermediate.h, intermediate.mm).
/// Provides atomic file writing strategies for safe saves.
final class AtomicFileWriter: @unchecked Sendable {
	/// Strategy for atomic saves.
	enum AtomicMode: Sendable {
		/// Always use atomic saves via NSFileManager replacement directory.
		case always
		/// Use atomic saves only for external (non-internal) volumes.
		case externalVolumes
		/// Use atomic saves only for remote (non-local) volumes.
		case remoteVolumes
		/// Never use atomic saves (write directly in place).
		case never
	}

	private let destination: String
	private let mode: AtomicMode
	private let permissions: mode_t

	/// Create an atomic file writer for the given destination path.
	///
	/// - Parameters:
	///   - destination: The final path where the file should appear.
	///   - mode: When to use atomic save strategies.
	///   - permissions: POSIX file permissions for the new file (default: `0o644`).
	init(
		destination: String,
		mode: AtomicMode = .always,
		permissions: mode_t = S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH,
	) {
		self.destination = PathUtilities.resolveHead(destination)
		self.mode = mode
		self.permissions = permissions
	}

	/// Write data atomically to the destination.
	///
	/// Chooses the appropriate strategy based on the `mode` setting:
	/// - `.always` / when file exists on certain volumes: uses `NSFileManager.replaceItemAtURL`
	/// - `.never`: writes directly
	///
	/// - Parameter data: The data to write.
	/// - Throws: If the write operation fails.
	func write(_ data: Data) throws {
		let strategy = chooseStrategy()

		switch strategy {
		case .fileManager:
			try writeViaFileManager(data)
		case .direct:
			try writeDirect(data)
		case .atomic:
			try writeAtomic(data)
		}
	}

	/// Write string content atomically.
	func write(_ string: String, encoding: String.Encoding = .utf8) throws {
		guard let data = string.data(using: encoding) else {
			throw AtomicWriteError.encodingFailed
		}
		try write(data)
	}

	// MARK: - Errors

	enum AtomicWriteError: Error, Sendable {
		case encodingFailed
		case createDirectoryFailed(String)
		case openFailed(String)
		case writeFailed(String)
		case replaceFailed(String)
	}

	// MARK: - Private

	private enum Strategy {
		case fileManager
		case direct
		case atomic
	}

	private func chooseStrategy() -> Strategy {
		guard PathUtilities.exists(destination) else {
			return .direct
		}

		let url = URL(fileURLWithPath: destination)
		let isInternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]))?.volumeIsInternal ?? true
		let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? true

		switch mode {
		case .always:
			return .fileManager
		case .externalVolumes:
			return isInternal ? .direct : .fileManager
		case .remoteVolumes:
			return isLocal ? .direct : .fileManager
		case .never:
			return .direct
		}
	}

	private func writeViaFileManager(_ data: Data) throws {
		let destURL = URL(fileURLWithPath: destination)

		// Preserve existing permissions
		var filePermissions = permissions
		var buf = Darwin.stat()
		if stat(destination, &buf) == 0 {
			filePermissions = buf.st_mode
		}

		// Create temporary directory for replacement
		let fm = FileManager.default
		guard let tempDir = try? fm.url(
			for: .itemReplacementDirectory,
			in: .userDomainMask,
			appropriateFor: destURL,
			create: true,
		) else {
			throw AtomicWriteError.createDirectoryFailed("Failed to create replacement directory for \(destination)")
		}

		let tempURL = tempDir.appendingPathComponent(destURL.lastPathComponent)

		do {
			try data.write(to: tempURL)

			// Copy metadata from original if it exists and is on local volume
			if PathUtilities.exists(destination), PathUtilities.isLocal(destination) {
				copyfile(destination, tempURL.path, nil, copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL))
			}
			chmod(tempURL.path, filePermissions & (S_IRWXU | S_IRWXG | S_IRWXO))

			// Atomic replace
			_ = try fm.replaceItemAt(destURL, withItemAt: tempURL)
		} catch {
			try? fm.removeItem(at: tempDir)
			throw AtomicWriteError.replaceFailed(error.localizedDescription)
		}

		try? fm.removeItem(at: tempDir)
	}

	private func writeAtomic(_ data: Data) throws {
		// Create temp file on same device, then swap
		let tempPath: String = if PathUtilities.device(destination) != PathUtilities.device(PathUtilities.temp()) {
			destination + "~"
		} else {
			PathUtilities.temp(file: "atomic_save")
		}

		let fd = Darwin.open(tempPath, O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC, permissions)
		guard fd != -1 else {
			throw AtomicWriteError.openFailed("open(\(tempPath)): \(String(cString: strerror(errno)))")
		}

		let written = data.withUnsafeBytes { ptr -> Int in
			guard let base = ptr.baseAddress else { return 0 }
			return Darwin.write(fd, base, data.count)
		}
		Darwin.close(fd)

		guard written == data.count else {
			unlink(tempPath)
			throw AtomicWriteError.writeFailed("Short write to \(tempPath)")
		}

		// Try exchangedata, then rename, then copyfile
		if tempPath != destination {
			guard swapAndUnlink(src: tempPath, dst: destination) else {
				throw AtomicWriteError.replaceFailed("Failed to swap \(tempPath) → \(destination)")
			}
		}
	}

	private func writeDirect(_ data: Data) throws {
		PathUtilities.makeDir(PathUtilities.parent(destination))

		let fd = Darwin.open(destination, O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC, permissions)
		guard fd != -1 else {
			throw AtomicWriteError.openFailed("open(\(destination)): \(String(cString: strerror(errno)))")
		}

		let written = data.withUnsafeBytes { ptr -> Int in
			guard let base = ptr.baseAddress else { return 0 }
			return Darwin.write(fd, base, data.count)
		}
		Darwin.close(fd)

		guard written == data.count else {
			throw AtomicWriteError.writeFailed("Short write to \(destination)")
		}
	}

	private func swapAndUnlink(src: String, dst: String) -> Bool {
		// Ensure parent directory exists
		if access(dst, F_OK) != 0 {
			PathUtilities.makeDir(PathUtilities.parent(dst))
		}

		// Try exchangedata (preserves inode/metadata)
		if exchangedata(src, dst, 0) == 0 {
			return unlink(src) == 0
		}

		// exchangedata not supported: try rename
		if errno == ENOTSUP || errno == ENOENT {
			// Copy metadata from dst to src if possible
			if errno == ENOTSUP, access(dst, F_OK) == 0, PathUtilities.isLocal(src) {
				copyfile(dst, src, nil, copyfile_flags_t(COPYFILE_METADATA))
			}
			if Darwin.rename(src, dst) == 0 {
				return true
			}
		}

		// Cross-device: copyfile + unlink
		if errno == EXDEV {
			if copyfile(src, dst, nil, copyfile_flags_t(COPYFILE_DATA | COPYFILE_MOVE)) == 0 {
				return unlink(src) == 0
			}
		}

		return false
	}
}
