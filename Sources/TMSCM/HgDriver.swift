import Foundation

// MARK: - Mercurial Driver

/// Mercurial VCS driver — equivalent to the C++ `scm::hg` driver.
///
/// Uses `hg status --all -0` to query file statuses.
public struct HgDriver: SCMDriver, Sendable {
	public let name = "hg"
	public let detectionMarker = ".hg"
	public let mayTouchFilesystem = true

	public init() {}

	// MARK: - Status

	public func status(rootPath: String) async throws -> SCMStatusMap {
		guard let hg = findExecutable("hg") else {
			return SCMStatusMap()
		}

		let output = try await runCommand(
			hg,
			arguments: ["status", "--all", "-0"],
			workingDirectory: rootPath,
		)

		var entries: [String: SCMStatus] = [:]

		// Output format: "X path\0" where X is status char
		for entry in output.split(separator: "\0", omittingEmptySubsequences: true) {
			guard entry.count >= 3 else { continue }

			let statusChar = entry[entry.startIndex]
			let filePath = String(entry[entry.index(entry.startIndex, offsetBy: 2)...])
			let fullPath = (rootPath as NSString).appendingPathComponent(filePath)

			let status = parseHgStatus(statusChar)
			entries[fullPath] = status
		}

		return SCMStatusMap(entries)
	}

	// MARK: - Variables

	public func variables(rootPath: String) async throws -> SCMVariables {
		guard let hg = findExecutable("hg") else {
			return SCMVariables(scmName: name, rootPath: rootPath)
		}

		let branch: String?
		do {
			let output = try await runCommand(
				hg,
				arguments: ["branch"],
				workingDirectory: rootPath,
			)
			let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
			branch = trimmed.isEmpty ? nil : trimmed
		} catch {
			branch = nil
		}

		return SCMVariables(scmName: name, rootPath: rootPath, branch: branch)
	}

	// MARK: - Private

	private func parseHgStatus(_ char: Character) -> SCMStatus {
		switch char {
		case "M": .modified
		case "A": .added
		case "R": .deleted
		case "C": .none
		case "!": .deleted
		case "?": .unversioned
		case "I": .ignored
		default: .unknown
		}
	}
}
