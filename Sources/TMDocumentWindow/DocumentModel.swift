import Foundation

/// A lightweight model tracking per-document metadata for the current
/// iteration. This will be replaced by a full `TMDocument` backed by
/// `TextBuffer` in Iteration 2.
///
/// For now it keeps the file URL, detected encoding, and modification flag
/// so that the window controller can implement save / save-as.
@MainActor
public class DocumentModel {
	/// The on-disk URL, or `nil` for an unsaved ("Untitled") document.
	public var fileURL: URL?

	/// The string encoding detected when the file was opened, or the
	/// encoding chosen by the user for new documents.
	public var encoding: String.Encoding

	/// Whether the document text has been modified since the last save.
	public var isModified: Bool = false

	/// The display title — filename or "Untitled".
	public var displayTitle: String {
		fileURL?.lastPathComponent ?? String(
			localized: "Untitled",
			comment: "Default title for new documents",
		)
	}

	/// Name of the encoding for display in the status bar.
	public var encodingDisplayName: String {
		switch encoding {
		case .utf8: "UTF-8"
		case .utf16: "UTF-16"
		case .utf16BigEndian: "UTF-16 BE"
		case .utf16LittleEndian: "UTF-16 LE"
		case .utf32: "UTF-32"
		case .ascii: "ASCII"
		case .isoLatin1: "ISO Latin 1"
		case .macOSRoman: "Mac Roman"
		case .japaneseEUC: "EUC-JP"
		case .shiftJIS: "Shift JIS"
		case .windowsCP1252: "Windows 1252"
		default: "UTF-8"
		}
	}

	public init(fileURL: URL? = nil, encoding: String.Encoding = .utf8) {
		self.fileURL = fileURL
		self.encoding = encoding
	}

	// MARK: - Reading

	/// Read the file at `url` and return the decoded text, detecting
	/// the encoding automatically. Updates `self.encoding` to match.
	public func readFile(at url: URL) throws -> String {
		let data = try Data(contentsOf: url)
		let (text, detectedEncoding) = Self.decodeWithEncodingDetection(data)
		encoding = detectedEncoding
		fileURL = url
		isModified = false
		return text
	}

	// MARK: - Writing

	/// Write `text` to the document's `fileURL` using the current encoding.
	/// If `fileURL` is `nil`, the caller must present a Save panel first.
	public func writeFile(text: String) throws {
		guard let url = fileURL else {
			throw DocumentError.noFileURL
		}
		guard let data = text.data(using: encoding) else {
			throw DocumentError.encodingFailed(encodingDisplayName)
		}
		try data.write(to: url, options: .atomic)
		isModified = false
	}

	// MARK: - Encoding Detection

	/// Attempt to decode `data` by checking for BOM markers, then trying
	/// common encodings in preference order.
	static func decodeWithEncodingDetection(_ data: Data) -> (String, String.Encoding) {
		// Check BOM
		if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
			if let s = String(data: data, encoding: .utf8) {
				return (s, .utf8)
			}
		}
		if data.count >= 2 {
			if data[0] == 0xFE, data[1] == 0xFF {
				if let s = String(data: data, encoding: .utf16BigEndian) {
					return (s, .utf16BigEndian)
				}
			}
			if data[0] == 0xFF, data[1] == 0xFE {
				if data.count >= 4, data[2] == 0x00, data[3] == 0x00 {
					if let s = String(data: data, encoding: .utf32LittleEndian) {
						return (s, .utf32LittleEndian)
					}
				}
				if let s = String(data: data, encoding: .utf16LittleEndian) {
					return (s, .utf16LittleEndian)
				}
			}
		}

		// Try common encodings in order
		let encodings: [String.Encoding] = [
			.utf8,
			.isoLatin1,
			.windowsCP1252,
			.macOSRoman,
			.japaneseEUC,
			.shiftJIS,
		]
		for enc in encodings {
			if let s = String(data: data, encoding: enc) {
				return (s, enc)
			}
		}

		// Last resort — lossy UTF-8
		let s = String(decoding: data, as: UTF8.self)
		return (s, .utf8)
	}
}

/// Errors from document operations.
public enum DocumentError: Error, LocalizedError {
	case noFileURL
	case encodingFailed(String)

	public var errorDescription: String? {
		switch self {
		case .noFileURL:
			String(
				localized: "The document has not been saved yet.",
				comment: "Error: save without URL",
			)
		case let .encodingFailed(name):
			String(
				localized: "Could not encode the document using \(name).",
				comment: "Error: encoding failure",
			)
		}
	}
}
