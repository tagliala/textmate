import Foundation

// MARK: - Save Pipeline Errors

/// Errors that can occur during the file save pipeline.
public enum FileSaveError: Error, Sendable, CustomStringConvertible {
	/// No file path was set and the delegate did not provide one.
	case noPath
	/// The file is on a read-only filesystem.
	case readOnlyFilesystem(String)
	/// The parent directory could not be created.
	case parentCreationFailed(String, String)
	/// Authorization was required but not granted.
	case authorizationDenied(String)
	/// Encoding the content to the target charset failed.
	case encodingFailed(String)
	/// A bundle filter command failed.
	case filterFailed(filterName: String, exitCode: Int, output: String)
	/// The actual write to disk failed.
	case writeFailed(String, String)
	/// The save was cancelled (e.g., user dismissed dialog).
	case cancelled

	public var description: String {
		switch self {
		case .noPath:
			"No path specified for save"
		case let .readOnlyFilesystem(path):
			"Read-only filesystem: '\(path)'"
		case let .parentCreationFailed(path, reason):
			"Cannot create parent directory for '\(path)': \(reason)"
		case let .authorizationDenied(path):
			"Authorization denied for '\(path)'"
		case let .encodingFailed(charset):
			"Failed to encode content as '\(charset)'"
		case let .filterFailed(name, code, output):
			"Filter '\(name)' failed (exit \(code)): \(output)"
		case let .writeFailed(path, reason):
			"Failed to write '\(path)': \(reason)"
		case .cancelled:
			"Save cancelled"
		}
	}
}

// MARK: - Save Pipeline Delegate

/// Protocol for external services needed by the save pipeline.
///
/// Replaces the C++ `save_callback_t` and `save_context_t` callbacks
/// with a single async delegate protocol.
public protocol FileSaveDelegate: Sendable {
	/// Called when the document has no path. Return a path, or `nil` to cancel.
	func selectPath(
		suggestedPath: String?,
		content: String,
	) async -> String?

	/// Called when the file or parent directory is not writable.
	/// Return `true` to attempt making it writable (chmod +w).
	func selectMakeWritable(path: String) async -> Bool

	/// Called when the parent directory does not exist.
	/// Return `true` to create the parent directory.
	func selectCreateParent(path: String) async -> Bool

	/// Called when elevated privileges are needed to write.
	/// Return `true` if authorization was obtained.
	func obtainWriteAuthorization(for path: String) async -> Bool

	/// Called when the target charset cannot encode the content.
	/// Return an alternative charset, or `nil` to cancel.
	func selectCharset(
		for path: String,
		currentCharset: String,
	) async -> String?

	/// Called to find and run text export filters for the content.
	///
	/// - Parameters:
	///   - path: The file path.
	///   - content: The UTF-8 text to transform.
	///   - pathAttributes: Scope-like attributes for the path.
	/// - Returns: Transformed text, or the original if no filters apply.
	func runTextExportFilters(
		path: String,
		content: String,
		pathAttributes: String,
	) async throws -> String

	/// Called to find and run binary export filters for the data.
	///
	/// - Parameters:
	///   - path: The file path.
	///   - data: The encoded data to transform.
	///   - pathAttributes: Scope-like attributes for the path.
	/// - Returns: Transformed data, or the original if no filters apply.
	func runBinaryExportFilters(
		path: String,
		data: Data,
		pathAttributes: String,
	) async throws -> Data
}

// MARK: - Default Delegate

/// Default delegate that performs no authorization, no filters,
/// and refuses to create directories or change permissions.
public struct DefaultFileSaveDelegate: FileSaveDelegate {
	public init() {}

	public func selectPath(
		suggestedPath: String?,
		content _: String,
	) async -> String? {
		suggestedPath
	}

	public func selectMakeWritable(path _: String) async -> Bool {
		false
	}

	public func selectCreateParent(path _: String) async -> Bool {
		true
	}

	public func obtainWriteAuthorization(for _: String) async -> Bool {
		false
	}

	public func selectCharset(
		for _: String,
		currentCharset: String,
	) async -> String? {
		currentCharset
	}

	public func runTextExportFilters(
		path _: String,
		content: String,
		pathAttributes _: String,
	) async throws -> String {
		content
	}

	public func runBinaryExportFilters(
		path _: String,
		data: Data,
		pathAttributes _: String,
	) async throws -> Data {
		data
	}
}

// MARK: - Save Result

/// The result of a successful save operation.
public struct FileSaveResult: Sendable {
	/// The final path the file was saved to.
	public let path: String

	/// The encoding used for saving.
	public let encoding: DocumentEncoding

	/// The number of bytes written.
	public let bytesWritten: Int

	/// Extended attributes that were set.
	public let attributes: [String: String]

	public init(
		path: String,
		encoding: DocumentEncoding,
		bytesWritten: Int,
		attributes: [String: String] = [:],
	) {
		self.path = path
		self.encoding = encoding
		self.bytesWritten = bytesWritten
		self.attributes = attributes
	}
}

// MARK: - File Save Pipeline

/// Asynchronous file save pipeline.
///
/// Replaces the C++ 12-state state machine in `save.cc` with a
/// linear `async`/`await` implementation. The pipeline performs:
///
/// 1. **Path resolution** — ensure we have a destination path.
/// 2. **Writability check** — test permissions, offer to make writable.
/// 3. **Authorization** — obtain elevated privileges if needed.
/// 4. **Text export filters** — run bundle-defined text transformations.
/// 5. **Line ending conversion** — convert LF to document's line ending.
/// 6. **Encode** — transcode from UTF-8 to target charset.
/// 7. **Binary export filters** — run bundle-defined binary transformations.
/// 8. **Write** — atomically save content to disk.
public struct FileSavePipeline: Sendable {
	/// The delegate providing path selection, authorization, and filter execution.
	public let delegate: FileSaveDelegate

	/// Extended attributes to write alongside the file.
	public let attributes: [String: String]

	public init(
		delegate: FileSaveDelegate = DefaultFileSaveDelegate(),
		attributes: [String: String] = [:],
	) {
		self.delegate = delegate
		self.attributes = attributes
	}

	/// Save content to a file, performing the full pipeline.
	///
	/// - Parameters:
	///   - path: The destination path, or `nil` to let the delegate choose.
	///   - content: The UTF-8 text to save.
	///   - encoding: The target encoding.
	/// - Returns: The save result with final path and byte count.
	/// - Throws: `FileSaveError` if the pipeline fails at any stage.
	public func save(
		path: String?,
		content: String,
		encoding: DocumentEncoding,
	) async throws -> FileSaveResult {
		// 1. Resolve path
		let resolvedPath = try await resolvePath(path: path, content: content)

		// 2. Build path attributes for filter matching
		let pathAttrs = buildPathAttributes(resolvedPath)

		// 3. Check writability and handle permissions
		try await ensureWritable(path: resolvedPath)

		// 4. Run text export filters
		var processedContent = try await delegate.runTextExportFilters(
			path: resolvedPath,
			content: content,
			pathAttributes: pathAttrs,
		)

		// 5. Convert line endings
		processedContent = convertLineEndings(processedContent, to: encoding.lineEnding)

		// 6. Encode content
		var currentEncoding = encoding
		let encodedData = try await encodeContent(
			processedContent,
			encoding: &currentEncoding,
			path: resolvedPath,
		)

		// 7. Run binary export filters
		let filteredData = try await delegate.runBinaryExportFilters(
			path: resolvedPath,
			data: encodedData,
			pathAttributes: pathAttrs,
		)

		// 8. Write to disk
		try writeToPath(path: resolvedPath, data: filteredData)

		// 9. Set extended attributes
		setAttributes(path: resolvedPath, attributes: attributes, encoding: currentEncoding)

		return FileSaveResult(
			path: resolvedPath,
			encoding: currentEncoding,
			bytesWritten: filteredData.count,
			attributes: attributes,
		)
	}

	// MARK: - Pipeline Stages

	/// Stage 1: Resolve the save path.
	private func resolvePath(path: String?, content: String) async throws -> String {
		if let path { return path }

		guard let selected = await delegate.selectPath(
			suggestedPath: nil,
			content: content,
		) else {
			throw FileSaveError.cancelled
		}
		return selected
	}

	/// Stages 2-3: Ensure the path is writable (permissions, parent dirs, auth).
	private func ensureWritable(path: String) async throws {
		let status = checkWritability(path)

		switch status {
		case .writable:
			return

		case .notWritable, .notWritableButOwner:
			let makeWritable = await delegate.selectMakeWritable(path: path)
			if makeWritable {
				// Try chmod +w
				var buf = Darwin.stat()
				if stat(path, &buf) == 0 {
					chmod(path, buf.st_mode | S_IWUSR)
				}
			} else {
				throw FileSaveError.authorizationDenied(path)
			}

		case .writableByRoot:
			let authorized = await delegate.obtainWriteAuthorization(for: path)
			guard authorized else {
				throw FileSaveError.authorizationDenied(path)
			}

		case .noParent:
			let createParent = await delegate.selectCreateParent(path: path)
			guard createParent else {
				throw FileSaveError.cancelled
			}
			let parentPath = (path as NSString).deletingLastPathComponent
			do {
				try FileManager.default.createDirectory(
					atPath: parentPath,
					withIntermediateDirectories: true,
				)
			} catch {
				throw FileSaveError.parentCreationFailed(path, error.localizedDescription)
			}

		case .readOnly:
			throw FileSaveError.readOnlyFilesystem(path)

		case .unhandled:
			throw FileSaveError.writeFailed(path, "Unable to determine write status")
		}
	}

	/// Check writability of a path.
	///
	/// Replicates `file::status()` from `status.cc`.
	func checkWritability(_ path: String) -> WritabilityStatus {
		if access(path, W_OK) == 0 {
			return .writable
		}

		switch errno {
		case EROFS:
			return .readOnly

		case ENOENT:
			let parentPath = (path as NSString).deletingLastPathComponent
			if access(parentPath, W_OK) == 0 {
				return .writable
			}
			switch errno {
			case EROFS: return .readOnly
			case ENOENT: return .noParent
			case EACCES: return .writableByRoot
			default: return .unhandled
			}

		case EACCES:
			var buf = Darwin.stat()
			guard stat(path, &buf) == 0 else {
				return errno == EACCES ? .writableByRoot : .unhandled
			}
			if (buf.st_mode & S_IWUSR) == 0 {
				return buf.st_uid == getuid() ? .notWritableButOwner : .notWritable
			} else if buf.st_uid != getuid() {
				return .writableByRoot
			}
			return .unhandled

		default:
			return .unhandled
		}
	}

	/// Stage 5: Convert line endings from LF to the target style.
	func convertLineEndings(_ content: String, to lineEnding: LineEnding) -> String {
		switch lineEnding {
		case .lf:
			content
		case .cr:
			content.replacingOccurrences(of: "\n", with: "\r")
		case .crlf:
			content.replacingOccurrences(of: "\n", with: "\r\n")
		}
	}

	/// Stage 6: Encode content to the target charset, with fallback.
	private func encodeContent(
		_ content: String,
		encoding: inout DocumentEncoding,
		path: String,
	) async throws -> Data {
		// Try encoding with BOM prefix
		if let data = encodeWithBOM(content, encoding: encoding) {
			return data
		}

		// Encoding failed — ask delegate for alternative
		guard let newCharset = await delegate.selectCharset(
			for: path,
			currentCharset: encoding.charset,
		) else {
			throw FileSaveError.cancelled
		}

		encoding.charset = newCharset
		if let data = encodeWithBOM(content, encoding: encoding) {
			return data
		}

		throw FileSaveError.encodingFailed(encoding.charset)
	}

	/// Encode text and prepend BOM if required.
	private func encodeWithBOM(_ content: String, encoding: DocumentEncoding) -> Data? {
		let stringEncoding = encoding.stringEncoding
		guard var data = content.data(using: stringEncoding) else { return nil }

		if encoding.hasBOM {
			let bom: [UInt8] = switch encoding.charset.uppercased() {
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

	/// Stage 8: Write data to disk.
	private func writeToPath(path: String, data: Data) throws {
		let url = URL(fileURLWithPath: path)

		// Ensure parent directory exists
		let parentURL = url.deletingLastPathComponent()
		try FileManager.default.createDirectory(
			at: parentURL,
			withIntermediateDirectories: true,
		)

		try data.write(to: url, options: .atomic)
	}

	/// Set extended attributes on the saved file.
	private func setAttributes(
		path: String,
		attributes: [String: String],
		encoding: DocumentEncoding,
	) {
		// Store the encoding as an xattr if it's not UTF-8 or has a BOM
		let shouldStoreEncoding = encoding.charset.uppercased() != "UTF-8" || encoding.hasBOM
		if shouldStoreEncoding {
			let value = encoding.charset
			if let data = value.data(using: .utf8) {
				data.withUnsafeBytes { ptr in
					guard let base = ptr.baseAddress else { return }
					setxattr(path, "com.apple.TextEncoding", base, data.count, 0, 0)
				}
			}
		} else {
			// Remove encoding xattr if saving as plain UTF-8
			removexattr(path, "com.apple.TextEncoding", 0)
		}

		// Set custom attributes
		for (key, value) in attributes {
			if let data = value.data(using: .utf8) {
				data.withUnsafeBytes { ptr in
					guard let base = ptr.baseAddress else { return }
					setxattr(path, key, base, data.count, 0, 0)
				}
			}
		}
	}

	/// Build scope-like path attributes (mirrors `FileOpenPipeline.buildPathAttributes`).
	func buildPathAttributes(_ path: String?) -> String {
		var components: [String] = []

		if let path {
			var revPath: [String] = []
			for token in path.split(separator: "/") {
				for subtoken in token.split(separator: ".") {
					guard !subtoken.isEmpty else { continue }
					revPath.append(subtoken.replacingOccurrences(of: " ", with: "_"))
				}
			}
			revPath.append("rev-path")
			revPath.append("attr")
			revPath.reverse()
			components.append(revPath.joined(separator: "."))
		} else {
			components.append("attr.untitled")
		}

		let version = ProcessInfo.processInfo.operatingSystemVersion
		components.append(
			"attr.os-version.\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
		)

		return components.joined(separator: " ")
	}

	// MARK: - Writability Status

	/// File writability status (local to pipeline, matching `FileStatus.WritabilityStatus`).
	enum WritabilityStatus {
		case writable
		case writableByRoot
		case notWritable
		case notWritableButOwner
		case noParent
		case readOnly
		case unhandled
	}
}
