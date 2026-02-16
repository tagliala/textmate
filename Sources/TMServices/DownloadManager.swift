import Foundation
import os.log

// MARK: - Download Manager

/// URLSession-based download manager with signature verification and ETag caching.
///
/// Port of `Frameworks/SoftwareUpdate/src/OakDownloadManager.mm`.
///
/// Provides two main capabilities:
/// - Single file download with signature verification and ETag caching
/// - Archive download with streaming extraction via `ArchiveExtractor`
public final class DownloadManager: @unchecked Sendable {
	// MARK: - Errors

	/// Errors that can occur during download.
	public enum DownloadError: Error, Sendable, CustomStringConvertible {
		/// The server returned a non-200/304 status code.
		case serverError(statusCode: Int, url: String)
		/// Signature headers are missing from the response.
		case missingSignature
		/// The signee is unknown (no matching public key).
		case unknownSignee(String)
		/// Signature verification failed.
		case signatureVerificationFailed
		/// Failed to write the downloaded file.
		case writeFailed(String)
		/// Archive extraction failed.
		case extractionFailed(String)
		/// The download was cancelled.
		case cancelled

		public var description: String {
			switch self {
			case let .serverError(code, url): "Server returned \(code) for \(url)"
			case .missingSignature: "Missing signature"
			case let .unknownSignee(signee): "Unable to obtain public key for \(signee)"
			case .signatureVerificationFailed: "Unable to verify signature"
			case let .writeFailed(msg): "Failed to write file: \(msg)"
			case let .extractionFailed(msg): "Extraction failed: \(msg)"
			case .cancelled: "Download cancelled"
			}
		}
	}

	// MARK: - Singleton

	/// Shared download manager instance.
	public static let shared = DownloadManager()

	// MARK: - Properties

	/// Custom user agent string. If `nil`, a default is constructed.
	public var customUserAgent: String?

	/// Logger for download events.
	private let logger = Logger(subsystem: "com.macromates.TextMate", category: "DownloadManager")

	/// ETag extended attribute name.
	private static let etagXattrName = "org.w3.http.etag"

	// MARK: - User Agent

	/// Build the user agent string.
	///
	/// Format: `AppName/Version/HostUUID macOSVersion/HWMachine/HWModel/CPUCount`
	public var userAgentString: String {
		if let custom = customUserAgent {
			return custom
		}

		let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TextMate"
		let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"

		var uuidBytes = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		var wait = timespec()
		gethostuuid(&uuidBytes, &wait)
		let uuid = UUID(uuid: uuidBytes)

		let osVersion = ProcessInfo.processInfo.operatingSystemVersion

		return "\(appName)/\(appVersion)/\(uuid.uuidString) \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)/\(Self.hardwareInfo(HW_MACHINE))/\(Self.hardwareInfo(HW_MODEL))/\(Self.hardwareInfo(HW_NCPU, isInteger: true))"
	}

	/// Query sysctl for hardware information.
	private static func hardwareInfo(_ field: Int32, isInteger: Bool = false) -> String {
		var size = 0
		var mib = [CTL_HW, field]
		guard sysctl(&mib, 2, nil, &size, nil, 0) == 0, size > 0 else { return "???" }
		var buffer = [CChar](repeating: 0, count: size)
		guard sysctl(&mib, 2, &buffer, &size, nil, 0) == 0 else { return "???" }
		if isInteger, size == MemoryLayout<Int32>.size {
			let value = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
			return String(value)
		}
		return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
	}

	// MARK: - File Download

	/// Download a file with signature verification and ETag caching.
	///
	/// Port of `-[OakDownloadManager downloadFileAtURL:replacingFileAtURL:publicKeys:completionHandler:]`.
	///
	/// - Parameters:
	///   - url: The URL to download from.
	///   - localURL: The local file URL to replace.
	///   - publicKeys: Map of signee identity → PEM public key.
	///   - completion: Called with `(wasUpdated, error)`.
	public func downloadFile(
		at url: URL,
		replacing localURL: URL,
		publicKeys: [String: String],
		completion: @escaping @Sendable (Bool, Error?) -> Void,
	) {
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
		request.setValue(userAgentString, forHTTPHeaderField: "User-Agent")

		// Check for cached ETag
		if let etagData = ExtendedAttributes.read(
			name: Self.etagXattrName,
			at: localURL.path,
		), let etag = String(data: etagData, encoding: .utf8) {
			request.setValue(etag, forHTTPHeaderField: "If-None-Match")
			logger.info("GET \(url.absoluteString) using entity tag \(etag)")
		}

		let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
			var wasUpdated = false
			var resultError = error

			let httpResponse = response as? HTTPURLResponse
			let statusCode = httpResponse?.statusCode ?? 0

			if let error {
				resultError = error
			} else if statusCode != 200 {
				if statusCode != 304 {
					resultError = DownloadError.serverError(statusCode: statusCode, url: url.absoluteString)
				}
				// 304 Not Modified → not an error, wasUpdated stays false
			} else if let data {
				// Verify signature
				let signee = httpResponse?.value(forHTTPHeaderField: SignatureVerifier.httpSigneeHeader)
				let signature = httpResponse?.value(forHTTPHeaderField: SignatureVerifier.httpSignatureHeader)

				if let signee, let signature {
					if let publicKey = publicKeys[signee] {
						do {
							try SignatureVerifier.verify(
								data: data,
								base64Signature: signature,
								publicKeyPEM: publicKey,
							)

							// Write data atomically
							try data.write(to: localURL, options: .atomic)
							wasUpdated = true

							// Cache ETag
							if let newETag = httpResponse?.value(forHTTPHeaderField: "ETag") {
								if !ExtendedAttributes.writeString(
									name: Self.etagXattrName,
									value: newETag,
									at: localURL.path,
								) {
									logger.error("setxattr(\(localURL.path)): failed")
								}
							} else {
								logger.error("No ETag: \(url.absoluteString)")
							}
						} catch {
							resultError = DownloadError.signatureVerificationFailed
						}
					} else {
						resultError = DownloadError.unknownSignee(signee)
					}
				} else {
					resultError = DownloadError.missingSignature
				}
			}

			completion(wasUpdated, resultError)
		}
		task.resume()
	}

	// MARK: - Archive Download

	/// Download and extract a `.tbz` archive with signature verification.
	///
	/// Port of `-[OakDownloadManager downloadArchiveAtURL:forReplacingURL:publicKeys:completionHandler:]`.
	///
	/// - Parameters:
	///   - url: The archive URL to download.
	///   - localURL: The local URL the archive contents will replace (used to determine temp directory location).
	///   - publicKeys: Map of signee identity → PEM public key.
	///   - completion: Called with `(extractedDirectoryURL, error)`.
	/// - Returns: An `NSProgress` object for tracking download progress.
	@discardableResult
	public func downloadArchive(
		at url: URL,
		forReplacing localURL: URL?,
		publicKeys: [String: String],
		completion: @escaping @Sendable (URL?, Error?) -> Void,
	) -> Progress {
		let downloadTask = ArchiveDownloadTask(
			url: url,
			localURL: localURL,
			publicKeys: publicKeys,
			userAgent: userAgentString,
			completion: completion,
		)
		downloadTask.start()
		return downloadTask.progress
	}
}

// MARK: - Archive Download Task

/// Internal task that coordinates archive download + streaming extraction.
///
/// Port of `OakDownloadArchiveTask`.
private final class ArchiveDownloadTask: NSObject, @unchecked Sendable, URLSessionDataDelegate {
	let serverURL: URL
	let localURL: URL?
	let publicKeys: [String: String]
	let userAgent: String
	let completion: @Sendable (URL?, Error?) -> Void

	let progress: Progress
	private var accumulatedData = Data()
	private var signee: String?
	private var signature: String?

	private var temporaryDirectoryURL: URL?
	private var extractor: ArchiveExtractor?
	private var extractorPipe: Pipe?
	private var extractorProcess: Process?
	private var extractorError: Error?

	private var sampleStartDate: Date?
	private var sampleCountOfBytesReceived: Int64 = 0

	private let logger = Logger(subsystem: "com.macromates.TextMate", category: "ArchiveDownload")

	init(
		url: URL,
		localURL: URL?,
		publicKeys: [String: String],
		userAgent: String,
		completion: @escaping @Sendable (URL?, Error?) -> Void,
	) {
		serverURL = url
		self.localURL = localURL
		self.publicKeys = publicKeys
		self.userAgent = userAgent
		self.completion = completion
		progress = Progress.discreteProgress(totalUnitCount: -1)
		super.init()

		progress.kind = .file
		progress.fileOperationKind = .downloading
		progress.localizedDescription = "Downloading \(url.lastPathComponent)…"
	}

	deinit {
		// Clean up temporary directory if still present
		if let tempURL = temporaryDirectoryURL {
			try? FileManager.default.removeItem(at: tempURL)
		}
	}

	func start() {
		var request = URLRequest(url: serverURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)
		request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

		let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
		session.dataTask(with: request).resume()
		session.finishTasksAndInvalidate()
	}

	// MARK: - Extractor Setup

	private func setupExtractor() -> Pipe? {
		if let pipe = extractorPipe { return pipe }

		do {
			let appropriateForURL = localURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
			temporaryDirectoryURL = try FileManager.default.url(
				for: .itemReplacementDirectory,
				in: .userDomainMask,
				appropriateFor: appropriateForURL,
				create: true,
			)
		} catch {
			logger.error("Failed to obtain NSItemReplacementDirectory: \(error.localizedDescription)")
			extractorError = error
			return nil
		}

		guard let tempDir = temporaryDirectoryURL else { return nil }

		let inputPipe = Pipe()
		let errorPipe = Pipe()

		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
		proc.arguments = [
			"-jxmkC", tempDir.path,
			"--strip-components", "1",
			"--disable-copyfile",
			"--exclude", "._*",
		]
		proc.standardInput = inputPipe
		proc.standardOutput = FileHandle.nullDevice
		proc.standardError = errorPipe

		do {
			try proc.run()
		} catch {
			logger.error("Failed to launch tar: \(error.localizedDescription)")
			extractorError = error
			return nil
		}

		extractorProcess = proc
		extractorPipe = inputPipe
		return inputPipe
	}

	// MARK: - URLSession Delegate

	func urlSession(
		_: URLSession,
		task _: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping (URLRequest?) -> Void,
	) {
		signee = signee ?? response.value(forHTTPHeaderField: SignatureVerifier.httpSigneeHeader)
		signature = signature ?? response.value(forHTTPHeaderField: SignatureVerifier.httpSignatureHeader)
		completionHandler(request)
	}

	func urlSession(
		_: URLSession,
		dataTask _: URLSessionDataTask,
		didReceive response: URLResponse,
		completionHandler: @escaping (URLSession.ResponseDisposition) -> Void,
	) {
		let httpResp = response as? HTTPURLResponse
		signee = signee ?? httpResp?.value(forHTTPHeaderField: SignatureVerifier.httpSigneeHeader)
		signature = signature ?? httpResp?.value(forHTTPHeaderField: SignatureVerifier.httpSignatureHeader)
		completionHandler(.allow)
	}

	func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		guard let pipe = setupExtractor(), !progress.isCancelled else {
			dataTask.cancel()
			return
		}

		pipe.fileHandleForWriting.write(data)
		accumulatedData.append(data)

		// Update progress
		let expected = dataTask.countOfBytesExpectedToReceive
		if expected != NSURLSessionTransferSizeUnknown {
			if sampleStartDate == nil {
				sampleStartDate = Date()
			} else {
				let bytesLeft = expected - dataTask.countOfBytesReceived
				if bytesLeft > 0, let startDate = sampleStartDate {
					let secondsSampled = -startDate.timeIntervalSinceNow
					if secondsSampled > 0.9 {
						let bytesReceivedSinceLastSample = dataTask.countOfBytesReceived - sampleCountOfBytesReceived
						if bytesReceivedSinceLastSample > 0 {
							let eta = ceil(Double(bytesLeft) * secondsSampled / Double(bytesReceivedSinceLastSample))
							progress.setUserInfoObject(NSNumber(value: eta), forKey: .estimatedTimeRemainingKey)
						}
						sampleStartDate = Date()
						sampleCountOfBytesReceived = dataTask.countOfBytesReceived
					}
				} else {
					progress.setUserInfoObject(nil, forKey: .estimatedTimeRemainingKey)
				}
			}
		}

		progress.totalUnitCount = expected
		progress.completedUnitCount = dataTask.countOfBytesReceived
	}

	func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError downloadError: Error?) {
		extractorPipe?.fileHandleForWriting.closeFile()
		progress.totalUnitCount = task.countOfBytesReceived

		// Check for errors
		if let error = extractorError ?? (extractorProcess != nil ? downloadError : nil) {
			logger.error("Failed to download \(self.serverURL.absoluteString): \(error.localizedDescription)")
			completion(nil, error)
			return
		}

		if extractorProcess == nil {
			completion(nil, DownloadManager.DownloadError.extractionFailed("Unable to launch tar."))
			return
		}

		// Verify signature
		do {
			guard let signee, let signature else {
				throw DownloadManager.DownloadError.missingSignature
			}
			guard let publicKey = publicKeys[signee] else {
				throw DownloadManager.DownloadError.unknownSignee(signee)
			}
			try SignatureVerifier.verify(
				data: accumulatedData,
				base64Signature: signature,
				publicKeyPEM: publicKey,
			)
		} catch {
			logger.error("Unable to verify signature")
			completion(nil, DownloadManager.DownloadError.signatureVerificationFailed)
			return
		}

		// Wait for extractor to finish
		guard let proc = extractorProcess else { return }

		DispatchQueue.global(qos: .utility).async { [self] in
			proc.waitUntilExit()

			DispatchQueue.main.async { [self] in
				if proc.terminationStatus == 0 {
					let url = temporaryDirectoryURL
					temporaryDirectoryURL = nil // Transfer ownership
					completion(url, nil)
				} else {
					let msg = "Abnormal exit from tar: \(proc.terminationStatus)"
					logger.error("\(msg)")
					completion(nil, DownloadManager.DownloadError.extractionFailed(msg))
				}
			}
		}
	}
}
