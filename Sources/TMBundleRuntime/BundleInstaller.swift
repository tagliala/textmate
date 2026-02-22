import Foundation

// MARK: - Remote Bundle Info

/// Metadata for a bundle available on the remote server.
struct RemoteBundleInfo: Sendable, Identifiable, Equatable {
	let uuid: String
	let name: String
	let category: String
	let summary: String
	let downloadURL: URL
	let downloadSize: Int
	let lastUpdated: Date
	let minimumAppVersion: String
	let isMandatory: Bool
	let isRecommended: Bool
	let grammarScopes: [String]
	let dependencies: [String] // UUIDs

	var id: String {
		uuid
	}

	init(
		uuid: String,
		name: String,
		category: String = "",
		summary: String = "",
		downloadURL: URL,
		downloadSize: Int = 0,
		lastUpdated: Date = Date(),
		minimumAppVersion: String = "",
		isMandatory: Bool = false,
		isRecommended: Bool = false,
		grammarScopes: [String] = [],
		dependencies: [String] = [],
	) {
		self.uuid = uuid
		self.name = name
		self.category = category
		self.summary = summary
		self.downloadURL = downloadURL
		self.downloadSize = downloadSize
		self.lastUpdated = lastUpdated
		self.minimumAppVersion = minimumAppVersion
		self.isMandatory = isMandatory
		self.isRecommended = isRecommended
		self.grammarScopes = grammarScopes
		self.dependencies = dependencies
	}
}

// MARK: - Install Status

/// Installation state of a bundle.
public enum BundleInstallStatus: Sendable, Equatable {
	case notInstalled
	case installed(path: String, lastUpdated: Date)
	case updateAvailable(installedPath: String, remoteDate: Date)
	case installing(progress: Double)
	case failed(error: String)
}

// MARK: - Bundle Installer

/// Manages the download, installation, and removal of TextMate bundles.
///
/// Mirrors the C++ `BundlesManager` singleton pattern:
/// - Maintains a merged view of remote + local bundle catalogs
/// - Resolves dependencies transitively before download
/// - Supports install, update, and uninstall operations
@MainActor
public final class BundleInstaller {
	/// The directory where managed bundles are installed.
	public let installDirectory: String

	/// The local index file path.
	private let localIndexPath: String

	/// The remote index URL.
	public var remoteIndexURL: URL?

	/// All known bundles (remote + local merged).
	public private(set) var catalog: [CatalogEntry] = []

	/// Installation status per bundle UUID.
	public private(set) var installStatus: [String: BundleInstallStatus] = [:]

	/// URLSession for downloads.
	private let session: URLSession

	/// The bundle loader for reading installed bundles.
	private let loader = BundleLoader()

	public init(
		installDirectory: String? = nil,
		localIndexPath: String? = nil,
		remoteIndexURL: URL? = nil,
		session: URLSession = .shared,
	) {
		self.installDirectory = installDirectory ?? BundleLocations.managedBundlesPath
		self.localIndexPath = localIndexPath ?? {
			let appSupport = NSSearchPathForDirectoriesInDomains(
				.applicationSupportDirectory,
				.userDomainMask,
				true,
			).first ?? "~/Library/Application Support"
			return (appSupport as NSString)
				.appendingPathComponent("TextMate/Managed/BundleIndex.plist")
		}()
		self.remoteIndexURL = remoteIndexURL
		self.session = session
	}

	// MARK: - Catalog

	/// A merged entry combining remote metadata and local install state.
	public struct CatalogEntry: Sendable, Identifiable, Equatable {
		public let uuid: String
		public let name: String
		public let category: String
		public let summary: String
		public let isInstalled: Bool
		public let hasUpdate: Bool
		public let isMandatory: Bool
		public let isRecommended: Bool
		public let installedPath: String?
		public let downloadURL: URL?

		public var id: String {
			uuid
		}

		public init(
			uuid: String,
			name: String,
			category: String = "",
			summary: String = "",
			isInstalled: Bool = false,
			hasUpdate: Bool = false,
			isMandatory: Bool = false,
			isRecommended: Bool = false,
			installedPath: String? = nil,
			downloadURL: URL? = nil,
		) {
			self.uuid = uuid
			self.name = name
			self.category = category
			self.summary = summary
			self.isInstalled = isInstalled
			self.hasUpdate = hasUpdate
			self.isMandatory = isMandatory
			self.isRecommended = isRecommended
			self.installedPath = installedPath
			self.downloadURL = downloadURL
		}
	}

	/// Loads the catalog by merging remote index with local state.
	public func loadCatalog() async {
		// Load local installed bundles.
		let fm = FileManager.default
		var localBundles: [String: (path: String, lastUpdated: Date)] = [:]

		if fm.fileExists(atPath: installDirectory) {
			let contents = (try? fm.contentsOfDirectory(atPath: installDirectory)) ?? []
			for entry in contents where entry.hasSuffix(".tmbundle") {
				let path = (installDirectory as NSString).appendingPathComponent(entry)
				let infoPlist = (path as NSString).appendingPathComponent("info.plist")
				if let data = fm.contents(atPath: infoPlist),
				   let dict = try? PropertyListSerialization.propertyList(
				   	from: data,
				   	options: [],
				   	format: nil,
				   ) as? [String: Any],
				   let uuid = dict["uuid"] as? String
				{
					let attrs = try? fm.attributesOfItem(atPath: infoPlist)
					let modified = attrs?[.modificationDate] as? Date ?? Date.distantPast
					localBundles[uuid] = (path: path, lastUpdated: modified)
					installStatus[uuid] = .installed(path: path, lastUpdated: modified)
				}
			}
		}

		// Load remote index if available.
		var remoteBundles: [RemoteBundleInfo] = []
		if let url = remoteIndexURL {
			remoteBundles = await fetchRemoteIndex(url: url)
		}

		// Merge.
		var entries: [CatalogEntry] = []
		var seen = Set<String>()

		for remote in remoteBundles {
			seen.insert(remote.uuid)
			let local = localBundles[remote.uuid]
			let hasUpdate = local != nil && remote.lastUpdated > local!.lastUpdated
			entries.append(CatalogEntry(
				uuid: remote.uuid,
				name: remote.name,
				category: remote.category,
				summary: remote.summary,
				isInstalled: local != nil,
				hasUpdate: hasUpdate,
				isMandatory: remote.isMandatory,
				isRecommended: remote.isRecommended,
				installedPath: local?.path,
				downloadURL: remote.downloadURL,
			))
		}

		// Add locally-installed bundles not in remote index.
		for (uuid, local) in localBundles where !seen.contains(uuid) {
			if let (descriptor, _) = loader.loadBundle(at: local.path) {
				entries.append(CatalogEntry(
					uuid: uuid,
					name: descriptor.name,
					category: descriptor.category,
					summary: descriptor.summary,
					isInstalled: true,
					hasUpdate: false,
					installedPath: local.path,
				))
			}
		}

		catalog = entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	// MARK: - Install

	/// Installs one or more bundles by UUID, resolving dependencies.
	public func install(bundleUUIDs: [String]) async -> [String: Result<String, Error>] {
		var results: [String: Result<String, Error>] = [:]

		// Resolve dependencies.
		let allUUIDs = resolveDependencies(for: bundleUUIDs)

		for uuid in allUUIDs {
			guard let entry = catalog.first(where: { $0.uuid == uuid }),
			      let url = entry.downloadURL
			else {
				results[uuid] = .failure(InstallerError.notFoundInCatalog)
				continue
			}

			installStatus[uuid] = .installing(progress: 0)

			do {
				let path = try await downloadAndInstall(
					url: url,
					bundleName: entry.name,
					uuid: uuid,
				)
				installStatus[uuid] = .installed(
					path: path,
					lastUpdated: Date(),
				)
				results[uuid] = .success(path)
			} catch {
				installStatus[uuid] = .failed(error: error.localizedDescription)
				results[uuid] = .failure(error)
			}
		}

		// Reload catalog to reflect new state.
		await loadCatalog()
		return results
	}

	/// Uninstalls a bundle by UUID.
	public func uninstall(bundleUUID: String) throws {
		guard let entry = catalog.first(where: { $0.uuid == bundleUUID }),
		      let path = entry.installedPath
		else {
			throw InstallerError.notInstalled
		}

		try FileManager.default.removeItem(atPath: path)
		installStatus[bundleUUID] = .notInstalled
	}

	/// Updates all bundles that have available updates.
	public func updateAll() async -> [String: Result<String, Error>] {
		let updatable = catalog.filter(\.hasUpdate).map(\.uuid)
		return await install(bundleUUIDs: updatable)
	}

	// MARK: - Dependency Resolution

	/// Resolves transitive dependencies for a set of bundle UUIDs.
	func resolveDependencies(for bundleUUIDs: [String]) -> [String] {
		// For now, no remote dependency info is loaded — just return the input.
		// In production, this would traverse the dependency graph.
		var resolved = [String]()
		var seen = Set<String>()

		for uuid in bundleUUIDs {
			if seen.insert(uuid).inserted {
				resolved.append(uuid)
			}
		}

		return resolved
	}

	// MARK: - Download

	/// Downloads and installs a single bundle.
	private func downloadAndInstall(
		url: URL,
		bundleName: String,
		uuid: String,
	) async throws -> String {
		let (data, response) = try await session.data(from: url)

		guard let httpResponse = response as? HTTPURLResponse,
		      httpResponse.statusCode == 200
		else {
			throw InstallerError.downloadFailed
		}

		// Write to install directory.
		let fm = FileManager.default
		try fm.createDirectory(
			atPath: installDirectory,
			withIntermediateDirectories: true,
		)

		let bundleDirName = "\(bundleName).tmbundle"
		let targetPath = (installDirectory as NSString).appendingPathComponent(bundleDirName)

		// Remove existing if updating.
		if fm.fileExists(atPath: targetPath) {
			try fm.removeItem(atPath: targetPath)
		}

		// Attempt to extract as tar.gz archive, or write raw plist.
		if isArchive(data: data) {
			try extractArchive(data: data, to: targetPath)
		} else {
			// Assume it's a plist directory structure already serialized.
			try fm.createDirectory(atPath: targetPath, withIntermediateDirectories: true)
			let infoPlist = (targetPath as NSString).appendingPathComponent("info.plist")
			try data.write(to: URL(fileURLWithPath: infoPlist))
		}

		installStatus[uuid] = .installing(progress: 1.0)
		return targetPath
	}

	/// Checks if data looks like a compressed archive.
	private func isArchive(data: Data) -> Bool {
		guard data.count >= 2 else { return false }
		// gzip magic bytes
		return data[0] == 0x1F && data[1] == 0x8B
	}

	/// Extracts a tar.gz archive to the target path.
	private func extractArchive(data: Data, to targetPath: String) throws {
		let fm = FileManager.default
		let tempDir = NSTemporaryDirectory() + UUID().uuidString
		try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
		defer { try? fm.removeItem(atPath: tempDir) }

		let archivePath = (tempDir as NSString).appendingPathComponent("bundle.tar.gz")
		try data.write(to: URL(fileURLWithPath: archivePath))

		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
		process.arguments = ["-xzf", archivePath, "-C", tempDir]
		try process.run()
		process.waitUntilExit()

		guard process.terminationStatus == 0 else {
			throw InstallerError.extractionFailed
		}

		// Find the extracted .tmbundle directory.
		let contents = try fm.contentsOfDirectory(atPath: tempDir)
		if let bundleDir = contents.first(where: { $0.hasSuffix(".tmbundle") }) {
			let extractedPath = (tempDir as NSString).appendingPathComponent(bundleDir)
			try fm.moveItem(atPath: extractedPath, toPath: targetPath)
		} else {
			// If no .tmbundle dir found, use the temp dir contents directly.
			try fm.moveItem(atPath: tempDir, toPath: targetPath)
		}
	}

	// MARK: - Remote Index

	/// Fetches and parses the remote bundle index.
	private func fetchRemoteIndex(url: URL) async -> [RemoteBundleInfo] {
		guard let (data, _) = try? await session.data(from: url) else {
			return []
		}

		guard let dict = try? PropertyListSerialization.propertyList(
			from: data,
			options: [],
			format: nil,
		) as? [String: Any],
			let bundlesArray = dict["bundles"] as? [[String: Any]]
		else {
			return []
		}

		return bundlesArray.compactMap { entry -> RemoteBundleInfo? in
			guard let uuid = entry["uuid"] as? String,
			      let name = entry["name"] as? String,
			      let urlString = entry["url"] as? String,
			      let downloadURL = URL(string: urlString)
			else {
				return nil
			}

			return RemoteBundleInfo(
				uuid: uuid,
				name: name,
				category: entry["category"] as? String ?? "",
				summary: entry["description"] as? String ?? "",
				downloadURL: downloadURL,
				downloadSize: entry["size"] as? Int ?? 0,
				lastUpdated: (entry["updated"] as? Date) ?? Date.distantPast,
				minimumAppVersion: entry["minimumAppVersion"] as? String ?? "",
				isMandatory: entry["isMandatory"] as? Bool ?? false,
				isRecommended: entry["isRecommended"] as? Bool ?? false,
				grammarScopes: entry["grammarScopes"] as? [String] ?? [],
				dependencies: entry["dependencies"] as? [String] ?? [],
			)
		}
	}

	// MARK: - Local Index

	/// Saves the local bundle index to disk.
	public func saveLocalIndex() throws {
		let entries: [[String: Any]] = catalog.filter(\.isInstalled).map { entry in
			var dict: [String: Any] = [
				"uuid": entry.uuid,
				"name": entry.name,
			]
			if let path = entry.installedPath {
				dict["path"] = path
			}
			return dict
		}

		let plist: [String: Any] = ["bundles": entries]
		let data = try PropertyListSerialization.data(
			fromPropertyList: plist,
			format: .xml,
			options: 0,
		)

		let dir = (localIndexPath as NSString).deletingLastPathComponent
		try FileManager.default.createDirectory(
			atPath: dir,
			withIntermediateDirectories: true,
		)
		try data.write(to: URL(fileURLWithPath: localIndexPath))
	}
}

// MARK: - Errors

public enum InstallerError: Error, LocalizedError, Sendable {
	case notFoundInCatalog
	case downloadFailed
	case extractionFailed
	case notInstalled
	case signatureVerificationFailed

	public var errorDescription: String? {
		switch self {
		case .notFoundInCatalog: "Bundle not found in catalog"
		case .downloadFailed: "Failed to download bundle"
		case .extractionFailed: "Failed to extract bundle archive"
		case .notInstalled: "Bundle is not installed"
		case .signatureVerificationFailed: "Bundle signature verification failed"
		}
	}
}
