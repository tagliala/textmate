import Foundation

// MARK: - Archive Extractor

/// Extracts `.tbz` (bzip2-compressed tar) archives using `/usr/bin/tar`.
///
/// Port of `Frameworks/network/src/tbz.h/.cc` and `download_tbz.h/.cc`.
///
/// Uses a subprocess to run `tar -jxmkC <destination>` with data streamed
/// through a pipe, matching the C++ implementation's approach.
public final class ArchiveExtractor: @unchecked Sendable {
	// MARK: - Errors

	/// Errors related to archive extraction.
	public enum ExtractionError: Error, Sendable {
		/// The tar process failed with the given exit status.
		case processExitedWithStatus(Int32)
		/// The tar process was terminated by a signal.
		case processTerminatedBySignal(Int32)
		/// Failed to launch the extraction process.
		case launchFailed(String)
		/// The extraction destination does not exist.
		case destinationNotFound(String)
		/// Writing to the extraction pipe failed.
		case writeFailed(String)
	}

	// MARK: - Configuration

	/// Options controlling archive extraction.
	public struct Options: Sendable {
		/// Number of leading path components to strip (--strip-components).
		public var stripComponents: Int

		/// Whether to disable copyfile behavior on macOS (--disable-copyfile).
		public var disableCopyfile: Bool

		/// Patterns to exclude from extraction (--exclude).
		public var excludePatterns: [String]

		/// Creates default extraction options.
		///
		/// By default:
		/// - Strip 1 leading component (matches TextMate bundle layout)
		/// - Disable copyfile (prevents AppleDouble files)
		/// - Exclude `._*` resource fork files
		public init(
			stripComponents: Int = 1,
			disableCopyfile: Bool = true,
			excludePatterns: [String] = ["._*"],
		) {
			self.stripComponents = stripComponents
			self.disableCopyfile = disableCopyfile
			self.excludePatterns = excludePatterns
		}
	}

	// MARK: - Properties

	/// The destination directory for extraction.
	public let destination: String

	/// Extraction options.
	public let options: Options

	/// The underlying `Process` handle (set during extraction).
	private var process: Process?

	/// The pipe for streaming data into tar.
	private var inputPipe: Pipe?

	// MARK: - Initialization

	/// Create an extractor targeting the given directory.
	///
	/// - Parameters:
	///   - destination: The directory to extract into (must exist).
	///   - options: Extraction options.
	public init(destination: String, options: Options = Options()) {
		self.destination = destination
		self.options = options
	}

	// MARK: - Extraction

	/// Build the argument list for `/usr/bin/tar`.
	private func tarArguments() -> [String] {
		var args = ["-jxmkC", destination]

		if options.stripComponents > 0 {
			args.append("--strip-components")
			args.append(String(options.stripComponents))
		}

		if options.disableCopyfile {
			args.append("--disable-copyfile")
		}

		for pattern in options.excludePatterns {
			args.append("--exclude")
			args.append(pattern)
		}

		return args
	}

	/// Extract archive data from a `Data` blob.
	///
	/// - Parameter data: The bzip2-compressed tar archive data.
	/// - Throws: `ExtractionError` on failure.
	public func extract(data: Data) throws {
		let pipe = Pipe()
		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
		proc.arguments = tarArguments()
		proc.standardInput = pipe

		process = proc
		inputPipe = pipe

		do {
			try proc.run()
		} catch {
			throw ExtractionError.launchFailed(error.localizedDescription)
		}

		pipe.fileHandleForWriting.write(data)
		pipe.fileHandleForWriting.closeFile()

		proc.waitUntilExit()

		let status = proc.terminationStatus
		if proc.terminationReason == .uncaughtSignal {
			throw ExtractionError.processTerminatedBySignal(status)
		}
		if status != 0 {
			throw ExtractionError.processExitedWithStatus(status)
		}
	}

	/// Begin a streaming extraction — returns a file handle for writing data.
	///
	/// Call `write(_:)` to feed data, then `finishStreaming()` to wait
	/// for completion.
	///
	/// - Throws: `ExtractionError.launchFailed` if tar cannot start.
	public func beginStreaming() throws {
		let pipe = Pipe()
		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
		proc.arguments = tarArguments()
		proc.standardInput = pipe

		// Suppress stderr
		proc.standardError = FileHandle.nullDevice

		process = proc
		inputPipe = pipe

		do {
			try proc.run()
		} catch {
			throw ExtractionError.launchFailed(error.localizedDescription)
		}
	}

	/// Write a chunk of archive data to the streaming extraction.
	///
	/// - Parameter data: The next chunk of bzip2 data.
	public func write(_ data: Data) {
		inputPipe?.fileHandleForWriting.write(data)
	}

	/// Finish the streaming extraction and wait for the process.
	///
	/// - Throws: `ExtractionError` if the process did not exit cleanly.
	public func finishStreaming() throws {
		inputPipe?.fileHandleForWriting.closeFile()
		inputPipe = nil

		guard let proc = process else { return }
		proc.waitUntilExit()
		process = nil

		let status = proc.terminationStatus
		if proc.terminationReason == .uncaughtSignal {
			throw ExtractionError.processTerminatedBySignal(status)
		}
		if status != 0 {
			throw ExtractionError.processExitedWithStatus(status)
		}
	}

	/// Extract archive data asynchronously.
	///
	/// - Parameter data: The bzip2-compressed tar archive data.
	/// - Throws: `ExtractionError` on failure.
	public func extractAsync(data: Data) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			DispatchQueue.global(qos: .utility).async {
				do {
					try self.extract(data: data)
					continuation.resume()
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}
}
