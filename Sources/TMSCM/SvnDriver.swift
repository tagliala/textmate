import Foundation

// MARK: - Subversion Driver

/// Subversion VCS driver — equivalent to the C++ `scm::svn` driver.
///
/// Uses `svn status` to query file statuses.
public struct SvnDriver: SCMDriver, Sendable {
	public let name = "svn"
	public let detectionMarker = ".svn"
	public let tracksDirectories = true

	public init() {}

	// MARK: - Status

	public func status(rootPath: String) async throws -> SCMStatusMap {
		guard let svn = findExecutable("svn") else {
			return SCMStatusMap()
		}

		let output = try await runCommand(
			svn,
			arguments: ["status"],
			workingDirectory: rootPath,
		)

		var entries: [String: SCMStatus] = [:]

		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			guard line.count >= 8 else { continue }

			let statusChar = line[line.startIndex]
			// svn status format: 7 columns of status flags + space + path
			let pathStart = line.index(line.startIndex, offsetBy: 8)
			guard pathStart <= line.endIndex else { continue }
			let filePath = String(line[pathStart...]).trimmingCharacters(in: .whitespaces)
			let fullPath: String = if filePath.hasPrefix("/") {
				filePath
			} else {
				(rootPath as NSString).appendingPathComponent(filePath)
			}

			let status = parseSvnStatus(statusChar)
			entries[fullPath] = status
		}

		return SCMStatusMap(entries)
	}

	// MARK: - Variables

	public func variables(rootPath: String) async throws -> SCMVariables {
		guard let svn = findExecutable("svn") else {
			return SCMVariables(scmName: name, rootPath: rootPath)
		}

		var vars: [String: String] = [:]
		do {
			let output = try await runCommand(
				svn,
				arguments: ["info", "--show-item", "url"],
				workingDirectory: rootPath,
			)
			let url = output.trimmingCharacters(in: .whitespacesAndNewlines)
			if !url.isEmpty {
				vars["TM_SCM_URL"] = url
			}
		} catch {
			// Not critical
		}

		// Try to extract branch from URL
		let branch: String?
		if let url = vars["TM_SCM_URL"] {
			if let branchRange = url.range(of: "/branches/") {
				let rest = url[branchRange.upperBound...]
				branch = String(rest.prefix(while: { $0 != "/" }))
			} else if url.contains("/trunk") {
				branch = "trunk"
			} else {
				branch = nil
			}
		} else {
			branch = nil
		}

		return SCMVariables(scmName: name, rootPath: rootPath, branch: branch, variables: vars)
	}

	// MARK: - Private

	private func parseSvnStatus(_ char: Character) -> SCMStatus {
		switch char {
		case "M", "R": .modified
		case "A": .added
		case "D", "!": .deleted
		case "C": .conflicted
		case "?": .unversioned
		case "I": .ignored
		case "X": .none
		default: .unknown
		}
	}
}
