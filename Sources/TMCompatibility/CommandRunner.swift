import Foundation

/// Executes bundle commands as subprocesses, routing stdin/stdout/stderr.
///
/// Counterpart of the C++ `command::runner_t` in
/// `Frameworks/command/src/runner.mm`. Uses Swift `Process` instead of
/// direct `vfork`/`execve`.
@MainActor
public final class CommandRunner {
	/// Delegate for command lifecycle events.
	public weak var delegate: CommandRunnerDelegate?

	/// The command being executed.
	public let command: BundleCommand

	/// The environment variables passed to the subprocess.
	public let environment: [String: String]

	/// Working directory for the subprocess.
	public let workingDirectory: String

	/// The running process (nil before launch, nil after completion).
	private var process: Process?

	/// Stdout accumulator.
	private var stdoutData = Data()

	/// Stderr accumulator.
	private var stderrData = Data()

	/// Whether the command is currently running.
	public var isRunning: Bool {
		process?.isRunning ?? false
	}

	/// The process ID (if running).
	public var processID: Int32? {
		process?.processIdentifier
	}

	/// Creates a runner for the given command.
	///
	/// - Parameters:
	///   - command: The bundle command to execute.
	///   - environment: The `TM_*` environment (typically from `EnvironmentBuilder`).
	///   - workingDirectory: Working directory for the process.
	///   - delegate: Delegate for output and completion events.
	public init(
		command: BundleCommand,
		environment: [String: String],
		workingDirectory: String,
		delegate: CommandRunnerDelegate? = nil,
	) {
		var cmd = command
		cmd.fixShebang()
		self.command = cmd
		self.environment = environment
		self.workingDirectory = workingDirectory
		self.delegate = delegate
	}

	// MARK: - Execution

	/// Write the command script to a temporary file and launch it.
	///
	/// - Parameter inputData: Data to write to the command's stdin.
	///   Pass `nil` when the command's input type is `.nothing`.
	/// - Throws: If the script file cannot be created or the process fails to
	///   launch.
	public func launch(inputData: Data? = nil) throws {
		let scriptPath = try createScriptFile()

		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: scriptPath)
		proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
		proc.environment = environment

		// Stdin
		if let data = inputData {
			let stdinPipe = Pipe()
			proc.standardInput = stdinPipe
			let writeHandle = stdinPipe.fileHandleForWriting
			// Write on background to avoid blocking
			DispatchQueue.global().async {
				writeHandle.write(data)
				writeHandle.closeFile()
			}
		} else {
			proc.standardInput = FileHandle.nullDevice
		}

		// Stdout
		let stdoutPipe = Pipe()
		proc.standardOutput = stdoutPipe
		stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			Task { @MainActor [weak self] in
				self?.stdoutData.append(data)
				self?.delegate?.commandRunner(self!, didReceiveStdout: data)
			}
		}

		// Stderr
		let stderrPipe = Pipe()
		proc.standardError = stderrPipe
		stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			Task { @MainActor [weak self] in
				self?.stderrData.append(data)
				self?.delegate?.commandRunner(self!, didReceiveStderr: data)
			}
		}

		proc.terminationHandler = { [weak self] process in
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.process = nil

				// Clean up temp script
				try? FileManager.default.removeItem(atPath: scriptPath)

				let result = CommandResult(
					exitCode: process.terminationStatus,
					stdout: stdoutData,
					stderr: stderrData,
					command: command,
				)
				delegate?.commandRunner(self, didFinishWith: result)
			}
		}

		try proc.run()
		process = proc
		delegate?.commandRunnerDidLaunch(self)
	}

	/// Terminate the running process.
	public func terminate() {
		process?.terminate()
	}

	/// Send an interrupt signal to the running process.
	public func interrupt() {
		process?.interrupt()
	}

	// MARK: - Script File

	/// Write the command script to a temporary file, make it executable,
	/// and return the path.
	private func createScriptFile() throws -> String {
		let cacheDir = FileManager.default.urls(
			for: .cachesDirectory, in: .userDomainMask,
		).first!.appendingPathComponent("com.macromates.TextMate/Scripts")

		try FileManager.default.createDirectory(
			at: cacheDir, withIntermediateDirectories: true,
		)

		let hash = command.command.utf8.reduce(into: UInt64(5381)) { result, byte in
			result = result &* 33 &+ UInt64(byte)
		}
		let scriptPath = cacheDir.appendingPathComponent(String(hash, radix: 16))

		try command.command.write(
			to: scriptPath, atomically: true, encoding: .utf8,
		)

		// Make executable
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o700], ofItemAtPath: scriptPath.path,
		)

		return scriptPath.path
	}
}

// MARK: - Command Result

/// The result of a completed command execution.
public struct CommandResult: Sendable {
	/// The process exit code.
	public let exitCode: Int32
	/// Captured stdout data.
	public let stdout: Data
	/// Captured stderr data.
	public let stderr: Data
	/// The command that produced this result.
	public let command: BundleCommand

	/// Stdout as a UTF-8 string.
	public var stdoutString: String {
		String(data: stdout, encoding: .utf8) ?? ""
	}

	/// Stderr as a UTF-8 string.
	public var stderrString: String {
		String(data: stderr, encoding: .utf8) ?? ""
	}

	/// Whether the command exited successfully (exit code 0).
	public var isSuccess: Bool {
		exitCode == 0
	}

	/// TextMate uses specific exit codes for special behaviors:
	/// - 200: Discard output
	/// - 201: Replace selection with output
	/// - 202: Replace document with output
	/// - 203: Insert as snippet
	/// - 204: Show HTML
	/// - 205: Show tool tip
	/// - 206: Insert as text
	public var exitCodeAction: CommandOutput? {
		switch exitCode {
		case 200: .discard
		case 201: .replaceSelection
		case 202: .replaceDocument
		case 203: nil // snippet (handled specially)
		case 204: .newWindow // HTML
		case 205: .toolTip
		case 206: .atCaret
		default: nil
		}
	}
}

// MARK: - Delegate

/// Delegate protocol for `CommandRunner` lifecycle events.
@MainActor
public protocol CommandRunnerDelegate: AnyObject {
	/// Called when the command process starts.
	func commandRunnerDidLaunch(_ runner: CommandRunner)

	/// Called when stdout data arrives.
	func commandRunner(_ runner: CommandRunner, didReceiveStdout data: Data)

	/// Called when stderr data arrives.
	func commandRunner(_ runner: CommandRunner, didReceiveStderr data: Data)

	/// Called when the command finishes.
	func commandRunner(_ runner: CommandRunner, didFinishWith result: CommandResult)
}

/// Default no-op implementations.
public extension CommandRunnerDelegate {
	func commandRunnerDidLaunch(_: CommandRunner) {}
	func commandRunner(_: CommandRunner, didReceiveStdout _: Data) {}
	func commandRunner(_: CommandRunner, didReceiveStderr _: Data) {}
	func commandRunner(_: CommandRunner, didFinishWith _: CommandResult) {}
}
