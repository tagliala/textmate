import Foundation

/// Port of C++ `io::process_t`, `io::spawn`, `io::exec`, `io::create_pipe`,
/// and `oak::basic_environment` (io/src/exec.h/cc, pipe.h/cc, environment.h/cc).
/// Provides process spawning, execution, pipe creation, and environment management.
public enum ProcessExecution: Sendable {
	/// Result of spawning a process. File descriptors for stdin/stdout/stderr.
	public struct SpawnedProcess: Sendable {
		public let pid: pid_t
		public let stdin: Int32
		public let stdout: Int32
		public let stderr: Int32

		public var isValid: Bool {
			pid != -1
		}
	}

	/// Create a pipe pair (read, write) with close-on-exec flag set.
	public static func createPipe() -> (read: Int32, write: Int32)? {
		var fds: [Int32] = [0, 0]
		guard pipe(&fds) == 0 else { return nil }
		_ = fcntl(fds[0], F_SETFD, FD_CLOEXEC)
		_ = fcntl(fds[1], F_SETFD, FD_CLOEXEC)
		return (fds[0], fds[1])
	}

	/// Spawn a child process with the given arguments and environment.
	/// Returns pipes connected to the child's stdin/stdout/stderr.
	public static func spawn(
		_ args: [String],
		environment: [String: String]? = nil,
	) -> SpawnedProcess? {
		guard let stdinPipe = createPipe(),
		      let stdoutPipe = createPipe(),
		      let stderrPipe = createPipe()
		else { return nil }

		// Parent reads from stdout/stderr, writes to stdin
		// Child reads from stdin, writes to stdout/stderr
		let childIn = stdinPipe.read
		let parentIn = stdinPipe.write
		let parentOut = stdoutPipe.read
		let childOut = stdoutPipe.write
		let parentErr = stderrPipe.read
		let childErr = stderrPipe.write

		var fileActions: posix_spawn_file_actions_t? = nil
		guard posix_spawn_file_actions_init(&fileActions) == 0 else {
			closeAll([childIn, parentIn, parentOut, childOut, parentErr, childErr])
			return nil
		}
		defer { posix_spawn_file_actions_destroy(&fileActions) }

		guard posix_spawn_file_actions_adddup2(&fileActions, childIn, STDIN_FILENO) == 0,
		      posix_spawn_file_actions_adddup2(&fileActions, childOut, STDOUT_FILENO) == 0,
		      posix_spawn_file_actions_adddup2(&fileActions, childErr, STDERR_FILENO) == 0
		else {
			closeAll([childIn, parentIn, parentOut, childOut, parentErr, childErr])
			return nil
		}

		var attrs: posix_spawnattr_t? = nil
		guard posix_spawnattr_init(&attrs) == 0 else {
			closeAll([childIn, parentIn, parentOut, childOut, parentErr, childErr])
			return nil
		}
		defer { posix_spawnattr_destroy(&attrs) }

		let flags = Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT)
		guard posix_spawnattr_setflags(&attrs, flags) == 0 else {
			closeAll([childIn, parentIn, parentOut, childOut, parentErr, childErr])
			return nil
		}

		// Build argv
		let cArgs = args.map { strdup($0) }
		defer { cArgs.forEach { free($0) } }
		var argv = cArgs.map { UnsafeMutablePointer<CChar>($0) }
		argv.append(nil)

		// Build envp
		let env = environment ?? basicEnvironment()
		let cEnv = env.map { strdup("\($0.key)=\($0.value)") }
		defer { cEnv.forEach { free($0) } }
		var envp = cEnv.map { UnsafeMutablePointer<CChar>($0) }
		envp.append(nil)

		var pid: pid_t = 0
		let rc = posix_spawn(&pid, argv[0], &fileActions, &attrs, &argv, &envp)

		close(childIn)
		close(childOut)
		close(childErr)

		guard rc == 0 else {
			closeAll([parentIn, parentOut, parentErr])
			return nil
		}

		return SpawnedProcess(pid: pid, stdin: parentIn, stdout: parentOut, stderr: parentErr)
	}

	/// Read all available data from a file descriptor and close it.
	public static func exhaustFD(_ fd: Int32) -> String {
		var result = Data()
		var buf = [UInt8](repeating: 0, count: 4096)
		while true {
			let len = read(fd, &buf, buf.count)
			if len <= 0 { break }
			result.append(contentsOf: buf[0 ..< len])
		}
		close(fd)
		return String(data: result, encoding: .utf8) ?? ""
	}

	/// Execute a command synchronously and return its stdout on success.
	/// Returns `nil` if the process fails or exits with non-zero status.
	public static func exec(
		_ args: [String],
		environment: [String: String]? = nil,
	) -> String? {
		guard let process = spawn(args, environment: environment) else { return nil }
		close(process.stdin)

		// Read stdout and stderr in parallel using nonisolated(unsafe) for
		// variables mutated in concurrent dispatch blocks that are synchronized
		// by DispatchGroup.wait().
		nonisolated(unsafe) var output = ""
		nonisolated(unsafe) var errorOutput = ""
		nonisolated(unsafe) var exitStatus: Int32 = -1

		let group = DispatchGroup()

		group.enter()
		DispatchQueue.global().async {
			output = exhaustFD(process.stdout)
			group.leave()
		}

		group.enter()
		DispatchQueue.global().async {
			errorOutput = exhaustFD(process.stderr)
			group.leave()
		}

		group.enter()
		DispatchQueue.global().async {
			var status: Int32 = 0
			waitpid(process.pid, &status, 0)
			if (status & 0x7F) == 0 { // WIFEXITED
				exitStatus = (status >> 8) & 0xFF // WEXITSTATUS
			}
			group.leave()
		}

		group.wait()
		_ = errorOutput // suppress unused warning
		return exitStatus == 0 ? output : nil
	}

	// MARK: - Environment

	/// Default whitelist for environment variables to inherit.
	private static let defaultWhitelist = "Apple_*:COMMAND_MODE:DIALOG*:SHELL:SHLVL:SSH_AUTH_SOCK:__CF_USER_TEXT_ENCODING"

	/// Build the basic environment for spawned processes.
	/// Inherits whitelisted variables from the current process, plus standard variables.
	public static func basicEnvironment() -> [String: String] {
		let whitelistStr = defaultWhitelist

		// Split whitelist into exact matches and glob patterns
		var exactMatches = Set<String>()
		var globPatterns: [String] = []
		for entry in whitelistStr.split(separator: ":").map(String.init) {
			if entry.contains("*") {
				globPatterns.append(entry)
			} else {
				exactMatches.insert(entry)
			}
		}

		var result: [String: String] = [:]

		// Filter process environment through whitelist
		for (key, value) in ProcessInfo.processInfo.environment {
			let isWhitelisted = exactMatches.contains(key) ||
				globPatterns.contains(where: { fnmatch($0, key, 0) == 0 })
			if isWhitelisted {
				result[key] = value
			}
		}

		// Add standard variables
		let home = PathUtilities.home()
		result["HOME"] = home
		result["TMPDIR"] = NSTemporaryDirectory()
		result["LOGNAME"] = NSUserName()
		result["USER"] = NSUserName()

		if let bundleId = Bundle.main.bundleIdentifier {
			result["TM_APP_IDENTIFIER"] = bundleId
		}
		result["TM_FULLNAME"] = NSFullUserName()
		result["TM_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"

		// Get default system PATH via sysctl
		var mib: [Int32] = [CTL_USER, USER_CS_PATH]
		var len = 0
		sysctl(&mib, 2, nil, &len, nil, 0)
		if len > 0 {
			var pathBuf = [CChar](repeating: 0, count: len)
			sysctl(&mib, 2, &pathBuf, &len, nil, 0)
			let pathBytes = pathBuf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
			let systemPath = String(decoding: pathBytes, as: UTF8.self)
			if result["PATH"] == nil {
				result["PATH"] = systemPath
			}
		}

		return result
	}

	// MARK: - Private Helpers

	private static func closeAll(_ fds: [Int32]) {
		for fd in fds {
			close(fd)
		}
	}
}
