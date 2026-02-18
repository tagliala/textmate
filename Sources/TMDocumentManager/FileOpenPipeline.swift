import Foundation

// MARK: - Open Pipeline Errors

/// Errors that can occur during the file open pipeline.
public enum FileOpenError: Error, Sendable, CustomStringConvertible {
	/// The file could not be read (permission denied, not found, etc.).
	case readFailed(String, String)
	/// Authorization was required but not granted.
	case authorizationDenied(String)
	/// A bundle filter command failed.
	case filterFailed(filterName: String, exitCode: Int, output: String)
	/// Encoding conversion failed for the detected charset.
	case encodingFailed(String)
	/// The open was cancelled (e.g., user dismissed charset picker).
	case cancelled

	public var description: String {
		switch self {
		case let .readFailed(path, reason):
			"Failed to read '\(path)': \(reason)"
		case let .authorizationDenied(path):
			"Authorization denied for '\(path)'"
		case let .filterFailed(name, code, output):
			"Filter '\(name)' failed (exit \(code)): \(output)"
		case let .encodingFailed(charset):
			"Failed to decode content with charset '\(charset)'"
		case .cancelled:
			"Open cancelled"
		}
	}
}

// MARK: - Open Pipeline Delegate

/// Protocol for external services needed by the open pipeline.
///
/// Replaces the C++ `open_callback_t` and `open_context_t` callbacks
/// with a single async delegate protocol. Implementations provide
/// authorization, charset selection, and filter execution.
public protocol FileOpenDelegate: Sendable {
	/// Called when the file requires elevated privileges to read.
	/// Return `true` if authorization was obtained.
	func obtainReadAuthorization(for path: String) async -> Bool

	/// Called when the encoding could not be auto-detected.
	/// Return the charset to use, or `nil` to cancel.
	func selectCharset(
		for path: String,
		suggestedCharset: String,
	) async -> String?

	/// Called to find and run binary import filters for the content.
	/// Filters transform binary data (e.g., decompressing gzip files).
	///
	/// - Parameters:
	///   - path: The file path.
	///   - data: The raw file data.
	///   - pathAttributes: Scope-like attributes for the path.
	/// - Returns: Transformed data, or the original if no filters apply.
	func runBinaryImportFilters(
		path: String,
		data: Data,
		pathAttributes: String,
	) async throws -> Data

	/// Called to find and run text import filters for the content.
	/// Filters transform UTF-8 text (e.g., prettifying XML).
	///
	/// - Parameters:
	///   - path: The file path.
	///   - content: The decoded UTF-8 text.
	///   - pathAttributes: Scope-like attributes for the path.
	/// - Returns: Transformed text, or the original if no filters apply.
	func runTextImportFilters(
		path: String,
		content: String,
		pathAttributes: String,
	) async throws -> String
}

// MARK: - Default Delegate

/// Default delegate that performs no authorization, no filters,
/// and auto-selects UTF-8 when encoding is ambiguous.
public struct DefaultFileOpenDelegate: FileOpenDelegate {
	public init() {}

	public func obtainReadAuthorization(for _: String) async -> Bool {
		false
	}

	public func selectCharset(
		for _: String,
		suggestedCharset: String,
	) async -> String? {
		suggestedCharset
	}

	public func runBinaryImportFilters(
		path _: String,
		data: Data,
		pathAttributes _: String,
	) async throws -> Data {
		data
	}

	public func runTextImportFilters(
		path _: String,
		content: String,
		pathAttributes _: String,
	) async throws -> String {
		content
	}
}

// MARK: - Open Result

/// The result of successfully opening a file.
public struct FileOpenResult: Sendable {
	/// The decoded UTF-8 text content.
	public let content: String

	/// The encoding detected during reading.
	public let encoding: DocumentEncoding

	/// The detected line ending style.
	public let lineEnding: LineEnding

	/// The raw byte count of the file.
	public let rawByteCount: Int

	/// The path attributes scope string.
	public let pathAttributes: String

	public init(
		content: String,
		encoding: DocumentEncoding,
		lineEnding: LineEnding,
		rawByteCount: Int,
		pathAttributes: String,
	) {
		self.content = content
		self.encoding = encoding
		self.lineEnding = lineEnding
		self.rawByteCount = rawByteCount
		self.pathAttributes = pathAttributes
	}
}

// MARK: - File Open Pipeline

/// Asynchronous file open pipeline.
///
/// Replaces the C++ 14-state state machine in `open.cc` with a
/// linear `async`/`await` implementation. The pipeline performs:
///
/// 1. **Access check** — verify read permission, obtain authorization if needed.
/// 2. **Load content** — read raw bytes from disk.
/// 3. **Binary import filters** — run bundle-defined binary transformations.
/// 4. **Encoding detection** — BOM → xattr → ASCII → UTF-8 → settings → ask user.
/// 5. **Decode** — transcode from detected charset to UTF-8.
/// 6. **Line ending detection** — detect dominant line ending.
/// 7. **Line ending harmonization** — normalize to LF internally.
/// 8. **Text import filters** — run bundle-defined text transformations.
/// 9. **Result** — deliver content with metadata.
public struct FileOpenPipeline: Sendable {
	/// The delegate providing authorization, charset selection, and filter execution.
	public let delegate: FileOpenDelegate

	/// Encoding cascade options.
	public let encodingOptions: EncodingCascadeOptions

	public init(
		delegate: FileOpenDelegate = DefaultFileOpenDelegate(),
		encodingOptions: EncodingCascadeOptions = .init(),
	) {
		self.delegate = delegate
		self.encodingOptions = encodingOptions
	}

	/// Open a file, performing the full pipeline.
	///
	/// - Parameter path: The file path to open.
	/// - Returns: The decoded content with encoding and line ending metadata.
	/// - Throws: `FileOpenError` if the pipeline fails at any stage.
	public func open(path: String) async throws -> FileOpenResult {
		// 1. Check read access
		try await checkReadAccess(path: path)

		// 2. Load raw content
		let rawData = try loadContent(path: path)

		// 3. Build path attributes for filter matching
		let pathAttrs = buildPathAttributes(path)

		// 4. Run binary import filters
		let filteredData = try await delegate.runBinaryImportFilters(
			path: path,
			data: rawData,
			pathAttributes: pathAttrs,
		)

		// 5. Detect encoding
		var encoding = StreamingFileReader.detectEncoding(
			data: filteredData,
			path: path,
			options: encodingOptions,
		)

		// 6. Decode content
		var content = try await decodeContent(
			data: filteredData,
			encoding: &encoding,
			path: path,
		)

		// 7. Detect line endings
		let lineEnding = LineEnding.detect(in: content)
		encoding.lineEnding = lineEnding

		// 8. Harmonize line endings (normalize to LF)
		content = harmonizeLineEndings(content, from: lineEnding)

		// 9. Run text import filters
		content = try await delegate.runTextImportFilters(
			path: path,
			content: content,
			pathAttributes: pathAttrs,
		)

		return FileOpenResult(
			content: content,
			encoding: encoding,
			lineEnding: lineEnding,
			rawByteCount: rawData.count,
			pathAttributes: pathAttrs,
		)
	}

	// MARK: - Pipeline Stages

	/// Stage 1: Check read access, requesting authorization if needed.
	private func checkReadAccess(path: String) async throws {
		guard access(path, R_OK) != 0 else { return }

		switch errno {
		case EACCES:
			let authorized = await delegate.obtainReadAuthorization(for: path)
			guard authorized else {
				throw FileOpenError.authorizationDenied(path)
			}

		case ENOENT:
			throw FileOpenError.readFailed(path, "File not found")

		default:
			throw FileOpenError.readFailed(path, String(cString: strerror(errno)))
		}
	}

	/// Stage 2: Load raw file content.
	private func loadContent(path: String) throws -> Data {
		let url = URL(fileURLWithPath: path)
		do {
			return try Data(contentsOf: url)
		} catch {
			throw FileOpenError.readFailed(path, error.localizedDescription)
		}
	}

	/// Stage 3: Build scope-like path attributes.
	///
	/// Replicates `file::path_attributes()` from `path_info.mm`.
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

	/// Stages 5-6: Decode data using detected encoding, with charset fallback.
	private func decodeContent(
		data: Data,
		encoding: inout DocumentEncoding,
		path: String,
	) async throws -> String {
		// Skip BOM bytes
		let bom = StreamingFileReader.detectBOM(data)
		let contentData = bom.length > 0 ? Data(data.dropFirst(bom.length)) : data

		// Try the detected encoding
		let stringEncoding = encoding.stringEncoding
		if let result = String(data: contentData, encoding: stringEncoding) {
			return result
		}

		// Encoding failed — ask delegate for alternative
		guard let newCharset = await delegate.selectCharset(
			for: path,
			suggestedCharset: encoding.charset,
		) else {
			throw FileOpenError.cancelled
		}

		encoding.charset = newCharset
		let newStringEncoding = encoding.stringEncoding

		if let result = String(data: contentData, encoding: newStringEncoding) {
			return result
		}

		// Final fallback: lossy UTF-8
		encoding.charset = "UTF-8"
		return String(decoding: contentData, as: UTF8.self)
	}

	/// Stage 8: Normalize all line endings to LF.
	func harmonizeLineEndings(_ content: String, from lineEnding: LineEnding) -> String {
		switch lineEnding {
		case .lf:
			content
		case .crlf:
			content.replacingOccurrences(of: "\r\n", with: "\n")
		case .cr:
			content.replacingOccurrences(of: "\r", with: "\n")
		}
	}
}
