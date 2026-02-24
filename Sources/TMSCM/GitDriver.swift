import Foundation

// MARK: - Git Driver

/// Git VCS driver — equivalent to the C++ `scm::git` driver.
///
/// Uses `git ls-files`, `git diff-files`, and `git diff-index` to compute
/// file statuses. Parses `git branch --show-current` for branch name.
public struct GitDriver: SCMDriver, Sendable {
	public let name = "git"
	public let detectionMarker = ".git"

	public init() {}

	// MARK: - Status

	public func status(rootPath: String) async throws -> SCMStatusMap {
		guard let git = findExecutable("git") else {
			return SCMStatusMap()
		}

		// Use git status --porcelain=v1 for reliable parsing
		let output = try await runCommand(
			git,
			arguments: ["status", "--porcelain=v1", "-uall", "--no-renames"],
			workingDirectory: rootPath,
			environment: ["GIT_DIR": rootPath + "/.git"],
		)

		var entries: [String: SCMStatus] = [:]

		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			guard line.count >= 4 else { continue }

			let indexStatus = line[line.startIndex]
			let workTreeStatus = line[line.index(after: line.startIndex)]
			let filePath = String(line[line.index(line.startIndex, offsetBy: 3)...])
			let fullPath = (rootPath as NSString).appendingPathComponent(filePath)

			let status = parseGitStatus(index: indexStatus, workTree: workTreeStatus)
			entries[fullPath] = status
		}

		return SCMStatusMap(entries)
	}

	// MARK: - Variables

	public func variables(rootPath: String) async throws -> SCMVariables {
		guard let git = findExecutable("git") else {
			return SCMVariables(scmName: name, rootPath: rootPath)
		}

		// Get current branch
		let branch: String?
		do {
			let branchOutput = try await runCommand(
				git,
				arguments: ["branch", "--show-current"],
				workingDirectory: rootPath,
			)
			let trimmed = branchOutput.trimmingCharacters(in: .whitespacesAndNewlines)
			branch = trimmed.isEmpty ? nil : trimmed
		} catch {
			branch = nil
		}

		// Get HEAD commit
		var vars: [String: String] = [:]
		do {
			let headOutput = try await runCommand(
				git,
				arguments: ["rev-parse", "--short", "HEAD"],
				workingDirectory: rootPath,
			)
			let head = headOutput.trimmingCharacters(in: .whitespacesAndNewlines)
			if !head.isEmpty {
				vars["TM_SCM_COMMIT"] = head
			}
		} catch {
			// Not critical
		}

		return SCMVariables(
			scmName: name,
			rootPath: rootPath,
			branch: branch,
			variables: vars,
		)
	}

	// MARK: - Private

	/// Parse git porcelain v1 status codes into SCMStatus.
	private func parseGitStatus(index: Character, workTree: Character) -> SCMStatus {
		// Conflict indicators
		if index == "U" || workTree == "U" || (index == "A" && workTree == "A")
			|| (index == "D" && workTree == "D")
		{
			return .conflicted
		}

		// If either index or worktree shows a change, report it
		if index == "?" && workTree == "?" {
			return .unversioned
		}
		if index == "!" && workTree == "!" {
			return .ignored
		}
		if index == "A" || workTree == "A" {
			return .added
		}
		if index == "D" || workTree == "D" {
			return .deleted
		}
		if index == "M" || workTree == "M" || index == "T" || workTree == "T" {
			return .modified
		}

		return .none
	}
}
