import Foundation

/// Port of C++ `file_status_t` and `file::status` (file/src/status.h, status.cc),
/// `file::path_attributes` (file/src/path_info.mm),
/// and `encoding::charset_from_bom` (file/src/encoding.h, encoding.cc).
/// Provides file writability testing, path-to-scope attribute generation, and BOM detection.
public enum FileStatus: Sendable {
	// MARK: - File Writability

	/// Result of testing file writability.
	public enum WritabilityStatus: Sendable, Equatable, CustomStringConvertible {
		/// File is writable by current user.
		case writable
		/// File is writable only by root.
		case writableByRoot
		/// File is not writable.
		case notWritable
		/// File is not writable but current user is owner.
		case notWritableButOwner
		/// File's parent directory does not exist.
		case noParent
		/// Filesystem is read-only.
		case readOnly
		/// Status could not be determined.
		case unhandled

		public var description: String {
			switch self {
			case .writable: "writable"
			case .writableByRoot: "writableByRoot"
			case .notWritable: "notWritable"
			case .notWritableButOwner: "notWritableButOwner"
			case .noParent: "noParent"
			case .readOnly: "readOnly"
			case .unhandled: "unhandled"
			}
		}
	}

	/// Test whether a file path is writable and by whom.
	public static func status(_ path: String) -> WritabilityStatus {
		if access(path, W_OK) == 0 {
			return .writable
		}

		switch errno {
		case EROFS:
			return .readOnly

		case ENOENT:
			let parentPath = PathUtilities.parent(path)
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

	// MARK: - Path Attributes

	/// Generate scope-like attributes from a file path.
	/// E.g. `/Users/me/foo.html.erb` → `attr.rev-path.erb.html.foo.me.Users attr.os-version.X.Y.Z`
	/// `nil` path → `attr.untitled attr.os-version.X.Y.Z`
	public static func pathAttributes(_ path: String?) -> String {
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
		components.append("attr.os-version.\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")

		return components.joined(separator: " ")
	}

	// MARK: - BOM Detection

	/// Known character set identifiers.
	public enum Charset: String, Sendable {
		case ascii = "ASCII"
		case utf8 = "UTF-8"
		case utf16BE = "UTF-16BE"
		case utf16LE = "UTF-16LE"
		case utf32BE = "UTF-32BE"
		case utf32LE = "UTF-32LE"
		case unknown = "UNKNOWN"
	}

	/// BOM detection result.
	public struct BOMResult: Sendable, Equatable {
		/// Detected charset, or `nil` if no BOM found.
		public let charset: Charset?
		/// Number of BOM bytes consumed.
		public let bomLength: Int
	}

	/// UTF-32 and UTF-16 BOM byte sequences (order matters — check 4-byte before 2-byte)
	private static let bomTests: [(bom: [UInt8], charset: Charset)] = [
		([0x00, 0x00, 0xFE, 0xFF], .utf32BE),
		([0xFE, 0xFF], .utf16BE),
		([0xFF, 0xFE, 0x00, 0x00], .utf32LE),
		([0xFF, 0xFE], .utf16LE),
		([0xEF, 0xBB, 0xBF], .utf8),
	]

	/// Detect a Unicode BOM at the start of a byte sequence.
	public static func charsetFromBOM(_ bytes: some Collection<UInt8>) -> BOMResult {
		let array = Array(bytes.prefix(4))
		for test in bomTests {
			if array.count >= test.bom.count, Array(array.prefix(test.bom.count)) == test.bom {
				return BOMResult(charset: test.charset, bomLength: test.bom.count)
			}
		}
		return BOMResult(charset: nil, bomLength: 0)
	}

	/// Map a charset name string to `String.Encoding`, if supported.
	public static func stringEncoding(for charset: String) -> String.Encoding? {
		switch charset.uppercased() {
		case "UTF-8": .utf8
		case "ASCII": .ascii
		case "UTF-16BE": .utf16BigEndian
		case "UTF-16LE": .utf16LittleEndian
		case "UTF-32BE": .utf32BigEndian
		case "UTF-32LE": .utf32LittleEndian
		case "ISO-8859-1", "LATIN1", "LATIN-1": .isoLatin1
		case "ISO-8859-2", "LATIN2": .isoLatin2
		case "SHIFT_JIS", "SHIFT-JIS", "SJIS": .shiftJIS
		case "EUC-JP": .japaneseEUC
		case "WINDOWS-1252", "CP1252": .windowsCP1252
		case "WINDOWS-1250", "CP1250": .windowsCP1250
		case "WINDOWS-1251", "CP1251": .windowsCP1251
		case "MACINTOSH", "MAC-ROMAN", "MACROMAN": .macOSRoman
		default: nil
		}
	}
}
