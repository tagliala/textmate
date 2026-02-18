import Foundation

// MARK: - Encoding Cascade Configuration

/// Configuration for encoding detection during file reading.
///
/// Controls which steps of the encoding cascade are used
/// and provides hooks for external settings lookup.
public struct EncodingCascadeOptions: Sendable {
	/// Charset hint from an external source (e.g., user override).
	public var charsetHint: String?

	/// Provider that resolves settings-based charset for a file path.
	/// Receives the file path and path attributes scope string;
	/// returns a charset name or `nil`.
	public var settingsCharsetProvider: (@Sendable (String, String) -> String?)?

	/// Whether to check the `com.apple.TextEncoding` xattr.
	public var checkXattr: Bool = true

	/// Whether to attempt ASCII detection.
	public var checkASCII: Bool = true

	/// Whether to use probability-based heuristic detection
	/// (via `EncodingDetector`).
	public var useHeuristic: Bool = true

	public init(
		charsetHint: String? = nil,
		settingsCharsetProvider: (@Sendable (String, String) -> String?)? = nil,
		checkXattr: Bool = true,
		checkASCII: Bool = true,
		useHeuristic: Bool = true,
	) {
		self.charsetHint = charsetHint
		self.settingsCharsetProvider = settingsCharsetProvider
		self.checkXattr = checkXattr
		self.checkASCII = checkASCII
		self.useHeuristic = useHeuristic
	}
}

// MARK: - Read Result

/// Result of reading a file with encoding detection.
public struct FileReadResult: Sendable, Equatable {
	/// The decoded UTF-8 text content.
	public let content: String

	/// The encoding detected/used during reading.
	public let encoding: DocumentEncoding

	/// The raw byte count read from disk.
	public let rawByteCount: Int

	public init(content: String, encoding: DocumentEncoding, rawByteCount: Int) {
		self.content = content
		self.encoding = encoding
		self.rawByteCount = rawByteCount
	}
}

// MARK: - Streaming File Reader

/// Reads files with automatic encoding detection via a multi-step cascade.
///
/// Ports `Frameworks/file/src/reader.cc`.
///
/// The encoding detection cascade:
/// 1. **BOM** — Check for Unicode byte order marks.
/// 2. **Extended attribute** — Read `com.apple.TextEncoding` xattr.
/// 3. **Charset hint** — User-supplied or settings-based charset.
/// 4. **ASCII** — If all bytes are 7-bit, treat as ASCII.
/// 5. **UTF-8** — Try to decode as UTF-8.
/// 6. **Heuristic** — Use `EncodingDetector` probability analysis.
/// 7. **Fallback** — Default to UTF-8 with lossy decoding.
///
/// Unlike the C++ version which reads in 8KB chunks and feeds them through
/// `text::transcode_t`, this Swift version reads the full file and uses
/// Foundation's charset conversion. For very large files, a chunked
/// streaming mode is available.
public struct StreamingFileReader: Sendable {
	/// Maximum bytes to read in a single chunk (8KB, matching C++ reader).
	public static let chunkSize = 8192

	/// Read a file and detect its encoding.
	///
	/// - Parameters:
	///   - path: The file path to read.
	///   - options: Encoding cascade configuration.
	///   - limit: Maximum bytes to read (0 = unlimited).
	/// - Returns: The decoded content with encoding metadata.
	/// - Throws: If the file cannot be read.
	public static func read(
		path: String,
		options: EncodingCascadeOptions = .init(),
		limit: Int = 0,
	) throws -> FileReadResult {
		let url = URL(fileURLWithPath: path)
		var data = try Data(contentsOf: url)
		let rawByteCount = data.count

		if limit > 0, data.count > limit {
			data = data.prefix(limit)
		}

		let encoding = detectEncoding(data: data, path: path, options: options)
		let content = decode(data: data, encoding: encoding)

		return FileReadResult(
			content: content,
			encoding: encoding,
			rawByteCount: rawByteCount,
		)
	}

	/// Read a file in streaming chunks, calling the handler for each
	/// decoded UTF-8 chunk.
	///
	/// - Parameters:
	///   - path: The file path to read.
	///   - options: Encoding cascade configuration.
	///   - handler: Called with each decoded UTF-8 chunk.
	/// - Returns: The detected encoding.
	/// - Throws: If the file cannot be opened or read.
	public static func readChunked(
		path: String,
		options: EncodingCascadeOptions = .init(),
		handler: (String) -> Void,
	) throws -> DocumentEncoding {
		let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC)
		guard fd != -1 else {
			throw FileReadError.openFailed(path, String(cString: strerror(errno)))
		}
		defer { Darwin.close(fd) }

		// Read initial chunk for encoding detection
		var firstChunk = Data(count: Self.chunkSize)
		let firstCount = firstChunk.withUnsafeMutableBytes { ptr -> Int in
			guard let base = ptr.baseAddress else { return 0 }
			return Darwin.read(fd, base, Self.chunkSize)
		}

		guard firstCount > 0 else {
			// Empty file
			return DocumentEncoding.utf8
		}
		firstChunk = firstChunk.prefix(firstCount)

		let encoding = detectEncoding(data: firstChunk, path: path, options: options)

		// Skip BOM bytes if present
		var bomLength = 0
		if encoding.hasBOM {
			let bom = detectBOM(firstChunk)
			bomLength = bom.length
		}

		// Decode and emit first chunk
		let firstContent = decode(data: firstChunk.dropFirst(bomLength), encoding: encoding)
		if !firstContent.isEmpty {
			handler(firstContent)
		}

		// Read remaining chunks
		var buffer = Data(count: Self.chunkSize)
		while true {
			let count = buffer.withUnsafeMutableBytes { ptr -> Int in
				guard let base = ptr.baseAddress else { return 0 }
				return Darwin.read(fd, base, Self.chunkSize)
			}
			guard count > 0 else { break }

			let chunk = buffer.prefix(count)
			let text = decode(data: chunk, encoding: encoding)
			if !text.isEmpty {
				handler(text)
			}
		}

		return encoding
	}

	// MARK: - Encoding Detection

	/// Run the encoding detection cascade on raw data.
	///
	/// - Parameters:
	///   - data: The raw file bytes (at least the first chunk).
	///   - path: The file path (for xattr and settings lookup).
	///   - options: Cascade configuration.
	/// - Returns: The detected encoding.
	public static func detectEncoding(
		data: Data,
		path: String,
		options: EncodingCascadeOptions = .init(),
	) -> DocumentEncoding {
		// 1. Check BOM
		let bom = detectBOM(data)
		if let charset = bom.charset {
			return DocumentEncoding(
				charset: charset,
				hasBOM: true,
			)
		}

		// 2. Check com.apple.TextEncoding xattr
		if options.checkXattr, let xattrCharset = readTextEncodingXattr(path: path) {
			return DocumentEncoding(charset: xattrCharset)
		}

		// 3. User/settings hint
		if let hint = options.charsetHint {
			return DocumentEncoding(charset: hint)
		}

		// 3b. Settings-based charset
		if let provider = options.settingsCharsetProvider {
			let pathAttrs = Self.buildPathAttributes(path)
			if let charset = provider(path, pathAttrs) {
				return DocumentEncoding(charset: charset)
			}
		}

		// 4. Check if all ASCII
		if options.checkASCII, isASCII(data) {
			return DocumentEncoding(charset: "ASCII")
		}

		// 5. Try UTF-8
		if String(data: data, encoding: .utf8) != nil {
			return DocumentEncoding.utf8
		}

		// 6. Heuristic detection
		if options.useHeuristic {
			if let detected = heuristicDetect(data: data) {
				return DocumentEncoding(charset: detected)
			}
		}

		// 7. Fallback to UTF-8 (will use lossy decoding)
		return DocumentEncoding.utf8
	}

	// MARK: - Private Helpers

	/// BOM detection result.
	struct BOMDetection {
		let charset: String?
		let length: Int
	}

	/// UTF-32 and UTF-16 BOM byte sequences (order matters — check 4-byte before 2-byte).
	private static let bomTable: [(bom: [UInt8], charset: String)] = [
		([0x00, 0x00, 0xFE, 0xFF], "UTF-32BE"),
		([0xFE, 0xFF], "UTF-16BE"),
		([0xFF, 0xFE, 0x00, 0x00], "UTF-32LE"),
		([0xFF, 0xFE], "UTF-16LE"),
		([0xEF, 0xBB, 0xBF], "UTF-8"),
	]

	/// Detect a Unicode BOM at the start of data.
	static func detectBOM(_ data: Data) -> BOMDetection {
		let prefix = Array(data.prefix(4))
		for entry in bomTable {
			if prefix.count >= entry.bom.count,
			   Array(prefix.prefix(entry.bom.count)) == entry.bom
			{
				return BOMDetection(charset: entry.charset, length: entry.bom.count)
			}
		}
		return BOMDetection(charset: nil, length: 0)
	}

	/// Read the `com.apple.TextEncoding` extended attribute.
	///
	/// Format: `CHARSET_NAME;CFSTRINGENCODING_ID`
	/// We only use the charset name (before the semicolon).
	static func readTextEncodingXattr(path: String) -> String? {
		let name = "com.apple.TextEncoding"
		let size = getxattr(path, name, nil, 0, 0, 0)
		guard size > 0 else { return nil }

		var buffer = Data(count: size)
		let read = buffer.withUnsafeMutableBytes { ptr -> Int in
			guard let base = ptr.baseAddress else { return -1 }
			return getxattr(path, name, base, size, 0, 0)
		}
		guard read > 0 else { return nil }

		guard let value = String(data: buffer, encoding: .utf8) else { return nil }

		// Extract charset name (before semicolon)
		let charset = value.split(separator: ";").first.map(String.init)
		return charset?.trimmingCharacters(in: .whitespaces).uppercased()
	}

	/// Check if all bytes in the data are 7-bit ASCII.
	static func isASCII(_ data: Data) -> Bool {
		data.allSatisfy { $0 < 0x80 }
	}

	/// Use EncodingDetector to find the most probable encoding.
	static func heuristicDetect(data: Data) -> String? {
		let detector = EncodingDetector.shared
		let charsets = detector.charsets()
		guard !charsets.isEmpty else { return nil }

		var bestCharset: String?
		var bestProb: Double = 0

		for charset in charsets {
			let prob = detector.probability(of: data, being: charset)
			if prob > bestProb {
				bestProb = prob
				bestCharset = charset
			}
		}

		// Only use heuristic result if probability is reasonably high
		guard bestProb > 0.5 else { return nil }
		return bestCharset
	}

	/// Decode data using the detected encoding, falling back to lossy UTF-8.
	static func decode(data: some DataProtocol, encoding: DocumentEncoding) -> String {
		// Map charset to String.Encoding
		let stringEncoding = encoding.stringEncoding
		let rawData = Data(data)

		if let result = String(data: rawData, encoding: stringEncoding) {
			return result
		}

		// Fallback: try UTF-8
		if stringEncoding != .utf8, let result = String(data: rawData, encoding: .utf8) {
			return result
		}

		// Last resort: lossy UTF-8
		return String(decoding: rawData, as: UTF8.self)
	}

	// MARK: - Errors

	public enum FileReadError: Error, Sendable, CustomStringConvertible {
		case openFailed(String, String)
		case readFailed(String, String)

		public var description: String {
			switch self {
			case let .openFailed(path, reason):
				"Failed to open '\(path)': \(reason)"
			case let .readFailed(path, reason):
				"Failed to read '\(path)': \(reason)"
			}
		}
	}

	// MARK: - Path Attributes

	/// Build scope-like path attributes from a file path.
	///
	/// Matches C++ `file::path_attributes()` from `path_info.mm`.
	/// E.g. `/Users/me/foo.html.erb` → `attr.rev-path.erb.html.foo.me.Users attr.os-version.X.Y.Z`
	static func buildPathAttributes(_ path: String?) -> String {
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
}
