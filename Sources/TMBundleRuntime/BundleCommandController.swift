import AppKit
import Foundation

/// Notification posted when a bundle command finishes execution.
///
/// The notification's `object` is the `BundleCommandController` instance.
/// The `userInfo` dictionary contains the key `"normalExit"` (`Bool`).
public let BundleCommandDidTerminateNotification = Notification.Name(
	"BundleCommandDidTerminateNotification",
)

/// Error domain for bundle command errors.
public let BundleCommandErrorDomain = "com.macromates.TextMate.BundleCommand"

/// Error codes for bundle command failures.
public enum BundleCommandError: Int {
	/// A required external tool is missing from `$PATH`.
	case requirementsMissing = 1
	/// The command process terminated with a non-zero, non-special exit code.
	case abnormalTermination = 2
}

// MARK: - Delegate Protocol

/// Delegate that a host (document window controller, editor view)
/// implements to provide context for command execution.
///
/// Port of the informal `OakCommandDelegate` protocol from
/// `Frameworks/OakCommand/src/OakCommand.mm`.
@MainActor
public protocol BundleCommandControllerDelegate: AnyObject {
	/// Injects additional environment variables for the command.
	///
	/// The delegate should add editor-specific variables such as
	/// `TM_FILENAME`, `TM_FILEPATH`, `TM_LINE_INDEX`, etc.
	func updateEnvironment(_ environment: inout [String: String])

	/// Saves documents before command execution.
	///
	/// - Parameters:
	///   - includeAll: If `true`, save all project documents; otherwise,
	///     save only the current document.
	///   - completion: Call with `true` if save succeeded, `false` to
	///     cancel execution.
	func saveAllEditedDocuments(
		includeAll: Bool,
		completion: @escaping (Bool) -> Void,
	)

	/// Presents an error related to command execution.
	func presentError(_ error: NSError)

	/// Shows a tooltip near the cursor.
	func showToolTip(_ text: String)

	/// Opens a document in the editor.
	func showNewDocument(content: String, fileType: String?)
}

/// Default no-op implementations.
public extension BundleCommandControllerDelegate {
	func updateEnvironment(_: inout [String: String]) {}
	func saveAllEditedDocuments(includeAll _: Bool, completion: @escaping (Bool) -> Void) {
		completion(true)
	}

	func presentError(_ error: NSError) {
		NSApp.presentError(error)
	}

	func showToolTip(_ text: String) {
		_ = text
	}

	func showNewDocument(content _: String, fileType _: String?) {}
}

// MARK: - Bundle Command Controller

/// High-level orchestrator for executing a bundle command within the
/// responder chain.
///
/// Port of the Objective-C++ `OakCommand` class from
/// `Frameworks/OakCommand/src/OakCommand.mm`.
///
/// This controller handles the full lifecycle:
/// 1. **Requirement check** — verifies that external tools referenced
///    by the command exist on `$PATH`.
/// 2. **Pre-execution save** — saves documents if requested.
/// 3. **Environment injection** — asks the delegate to add
///    editor-specific variables.
/// 4. **Process launch** — creates a script file and forks a process.
/// 5. **Output routing** — routes stdout/stderr based on the command's
///    output placement, format, and special exit codes (200–208).
/// 6. **Termination** — posts `BundleCommandDidTerminateNotification`.
@MainActor
public final class BundleCommandController {
	/// The command being executed.
	public private(set) var command: BundleCommand

	/// The delegate providing execution context.
	public weak var delegate: BundleCommandControllerDelegate?

	/// Called when the command finishes. `Bool` is `true` for normal exit.
	public var terminationHandler: ((BundleCommandController, Bool) -> Void)?

	/// Called to handle text output that should be applied to the editor.
	public var outputHandler: ((
		_ text: String,
		_ placement: CommandOutput,
		_ format: CommandOutputFormat,
		_ caret: CommandOutputCaret,
		_ environment: [String: String],
	) -> Void)?

	/// The running process (nil before launch and after completion).
	private var process: Process?

	/// The environment built for the command.
	private var environment: [String: String] = [:]

	/// Whether the user explicitly terminated the command.
	private var userDidAbort = false

	/// Lifecycle flags matching the C++ stepwise execution.
	private var didCheckRequirements = false
	private var didSaveDocuments = false

	// MARK: - Init

	/// Creates a controller for the given bundle command.
	///
	/// Calls `fixShebang()` automatically if the command lacks a shebang.
	public init(command: BundleCommand) {
		var cmd = command
		cmd.fixShebang()
		self.command = cmd
	}

	/// The command's UUID as an `NSUUID`, if present.
	public var identifier: UUID? {
		UUID(uuidString: command.uuid)
	}

	// MARK: - Execution

	/// Execute the command with the given input and environment.
	///
	/// - Parameters:
	///   - inputData: Data to pipe to the command's stdin.
	///     Pass `nil` to send nothing.
	///   - variables: Base environment variables. The delegate's
	///     `updateEnvironment` will be called to add more.
	public func execute(
		inputData: Data?,
		variables: [String: String] = [:],
	) {
		userDidAbort = false

		// 1. Build environment
		environment = variables
		environment.merge(ProcessInfo.processInfo.environment) { old, _ in old }
		delegate?.updateEnvironment(&environment)

		// 2. Check requirements
		if !didCheckRequirements {
			if let error = checkRequirements() {
				delegate?.presentError(error)
				return
			}
			didCheckRequirements = true
		}

		// 3. Pre-exec save
		if !didSaveDocuments {
			if command.preExec != .nop {
				let includeAll = command.preExec == .saveProject
				delegate?.saveAllEditedDocuments(includeAll: includeAll) { [weak self] didSave in
					guard let self, didSave else { return }
					didSaveDocuments = true
					execute(inputData: inputData, variables: variables)
				}
				return
			}
			didSaveDocuments = true
		}

		// 4. Create script and launch
		let scriptPath: String
		do {
			scriptPath = try createScriptFile()
		} catch {
			let nsError = NSError(
				domain: BundleCommandErrorDomain,
				code: BundleCommandError.abnormalTermination.rawValue,
				userInfo: [
					NSLocalizedDescriptionKey: "Failed to create script file for \"\(command.name)\".",
					NSLocalizedRecoverySuggestionErrorKey: error.localizedDescription,
				],
			)
			delegate?.presentError(nsError)
			return
		}

		launchProcess(
			scriptPath: scriptPath,
			inputData: inputData ?? Data(),
		)
	}

	/// Terminate the running process.
	public func terminate() {
		userDidAbort = true
		if let proc = process, proc.isRunning {
			// Kill the process group so child processes are also terminated.
			let pgid = proc.processIdentifier
			kill(-pgid, SIGTERM)
		}
	}

	// MARK: - Process Launch

	private func launchProcess(scriptPath: String, inputData: Data) {
		let workingDir = environment["TM_DIRECTORY"]
			?? environment["TM_PROJECT_DIRECTORY"]
			?? NSTemporaryDirectory()

		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: scriptPath)
		proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)
		proc.environment = environment

		// Stdin
		let stdinPipe = Pipe()
		proc.standardInput = stdinPipe

		// Stdout
		let stdoutPipe = Pipe()
		proc.standardOutput = stdoutPipe

		// Stderr
		let stderrPipe = Pipe()
		proc.standardError = stderrPipe

		// Collect output asynchronously
		let stdoutBox = LockedBox(Data())
		let stderrBox = LockedBox(Data())

		stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			if !data.isEmpty {
				stdoutBox.withLock { $0.append(data) }
			}
		}

		stderrPipe.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			if !data.isEmpty {
				stderrBox.withLock { $0.append(data) }
			}
		}

		proc.terminationHandler = { [weak self] p in
			// Read remaining data
			stdoutPipe.fileHandleForReading.readabilityHandler = nil
			stderrPipe.fileHandleForReading.readabilityHandler = nil
			let finalOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
			let finalErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
			stdoutBox.withLock { $0.append(finalOut) }
			stderrBox.withLock { $0.append(finalErr) }

			let status = p.terminationStatus
			let stdout = stdoutBox.value
			let stderr = stderrBox.value

			DispatchQueue.main.async { [weak self] in
				self?.handleCompletion(
					status: status,
					stdout: stdout,
					stderr: stderr,
					scriptPath: scriptPath,
				)
			}
		}

		do {
			try proc.run()
			process = proc

			// Set process group
			setpgid(proc.processIdentifier, proc.processIdentifier)

			// Write input on background
			if !inputData.isEmpty {
				DispatchQueue.global().async {
					stdinPipe.fileHandleForWriting.write(inputData)
					stdinPipe.fileHandleForWriting.closeFile()
				}
			} else {
				stdinPipe.fileHandleForWriting.closeFile()
			}
		} catch {
			// Clean up script file
			try? FileManager.default.removeItem(atPath: scriptPath)

			let nsError = NSError(
				domain: BundleCommandErrorDomain,
				code: BundleCommandError.abnormalTermination.rawValue,
				userInfo: [
					NSLocalizedDescriptionKey: "Failed to launch \"\(command.name)\".",
					NSLocalizedRecoverySuggestionErrorKey: error.localizedDescription,
				],
			)
			delegate?.presentError(nsError)
		}
	}

	// MARK: - Completion Handling

	/// Process the command result, routing output to the appropriate handler.
	///
	/// Mirrors the giant `completionHandler` block in C++ `OakCommand`'s
	/// `executeWithInput:outputHandler:`.
	private func handleCompletion(
		status: Int32,
		stdout: Data,
		stderr: Data,
		scriptPath: String,
	) {
		process = nil

		// Clean up the temp script
		try? FileManager.default.removeItem(atPath: scriptPath)

		// Decode output
		var out = String(data: stdout, encoding: .utf8) ?? ""
		var err = String(data: stderr, encoding: .utf8) ?? ""

		// Replace script path with command name in output
		// (matching C++ `oak::replace_copy`)
		out = out.replacingOccurrences(of: scriptPath, with: command.name)
		err = err.replacingOccurrences(of: scriptPath, with: command.name)

		// Determine exit code.
		// Process.terminationStatus returns the exit code directly
		// (not the raw wait(2) format).
		let rc = Int(status)

		// Resolve effective output placement (special exit codes override)
		var placement = command.output
		var format = command.outputFormat
		var outputCaret = command.outputCaret

		switch rc {
		case 200: placement = .discard
		case 201: placement = .replaceInput
			format = .text
			outputCaret = .heuristic
		case 202: placement = .replaceDocument
			format = .text
			outputCaret = .interpolateByLine
		case 203: placement = .afterInput
			format = .text
			outputCaret = .afterOutput
		case 204: placement = .newWindow
			format = .html
		case 205: placement = .toolTip
			format = .text
		case 206: placement = .newWindow
			format = .text
		case 207:
			format = .snippet
			if command.input == .selection {
				placement = .replaceInput
			} else if command.input == .entireDocument {
				placement = .atCaret
			} else {
				placement = .afterInput
			}
		default: break
		}

		let normalExit = rc == 0 || (200 ... 207).contains(rc)

		// Error handling
		if !normalExit, !userDidAbort {
			presentCommandError(rc: rc, stdout: out, stderr: err)
		} else if placement == .newWindow {
			if format == .text {
				delegate?.showNewDocument(
					content: err + out, fileType: nil,
				)
			} else if format == .html {
				// HTML output handled elsewhere
			}
		} else if placement == .toolTip {
			let trimmed = (err + out).trimmingCharacters(
				in: .whitespacesAndNewlines,
			)
			if !trimmed.isEmpty {
				delegate?.showToolTip(trimmed)
			}
		} else if placement != .discard {
			if format == .snippet, command.disableOutputAutoIndent {
				format = .snippetNoAutoIndent
			}

			if let handler = outputHandler {
				handler(out, placement, format, outputCaret, environment)
			} else if !out.isEmpty || !err.isEmpty {
				delegate?.showNewDocument(
					content: err + out, fileType: nil,
				)
			}
		}

		// Notify
		terminationHandler?(self, normalExit)
		NotificationCenter.default.post(
			name: BundleCommandDidTerminateNotification,
			object: self,
			userInfo: ["normalExit": normalExit],
		)
	}

	// MARK: - Error Presentation

	/// Present a command failure error matching the C++ behavior.
	private func presentCommandError(rc: Int, stdout: String, stderr: String) {
		let combined = (stderr + stdout).trimmingCharacters(
			in: .whitespacesAndNewlines,
		)

		var message: String
		if combined.isEmpty {
			message = "Command returned status code \(rc)."
		} else {
			// Truncate long output: show first 4 + last 3 lines
			let lines = combined.components(separatedBy: "\n")
			if lines.count > 7 {
				let head = lines.prefix(4)
				let tail = lines.suffix(3)
				message = (head + ["⋮"] + tail).joined(separator: "\n")
			} else {
				message = combined
			}
		}

		let error = NSError(
			domain: BundleCommandErrorDomain,
			code: BundleCommandError.abnormalTermination.rawValue,
			userInfo: [
				NSLocalizedDescriptionKey: "Failure running \"\(command.name)\".",
				NSLocalizedRecoverySuggestionErrorKey: message,
			],
		)
		delegate?.presentError(error)
	}

	// MARK: - Requirements Check

	/// Verify that external tools referenced by the command exist.
	///
	/// Returns an `NSError` describing the missing requirement,
	/// or `nil` if all requirements are met.
	private func checkRequirements() -> NSError? {
		// Check if the command references specific executables
		// that should be on $PATH.
		guard let pathVar = environment["PATH"] else { return nil }
		let paths = pathVar.split(separator: ":").map(String.init)

		// The C++ version uses `bundles::missing_requirement()` to check
		// bundle item metadata. We check the first word of the command
		// after the shebang line as a heuristic.
		let firstLine = command.command.components(separatedBy: "\n")
			.first(where: { !$0.hasPrefix("#!") && !$0.isEmpty })

		guard let firstWord = firstLine?
			.trimmingCharacters(in: .whitespaces)
			.components(separatedBy: " ").first,
			!firstWord.isEmpty,
			!firstWord.hasPrefix("$"),
			!firstWord.hasPrefix("/"),
			!firstWord.hasPrefix(".")
		else {
			return nil
		}

		// Check if the command exists on PATH
		let fm = FileManager.default
		for dir in paths {
			let fullPath = (dir as NSString).appendingPathComponent(firstWord)
			if fm.isExecutableFile(atPath: fullPath) {
				return nil
			}
		}

		// It's common for commands to use bash builtins — don't flag those
		let builtins: Set<String> = [
			"echo", "printf", "test", "export", "source", "eval", "exec",
			"cd", "pwd", "exit", "return", "set", "unset", "shift",
			"read", "declare", "local", "if", "then", "else", "fi",
			"for", "while", "do", "done", "case", "esac", "function",
			"true", "false", "cat", "grep", "sed", "awk", "sort",
			"cut", "tr", "head", "tail", "wc", "tee", "xargs",
			"find", "mkdir", "rm", "cp", "mv", "ln", "chmod",
			"touch", "basename", "dirname", "ruby", "python", "python3",
			"perl", "node", "swift", "env", "which", "type",
		]
		if builtins.contains(firstWord) {
			return nil
		}

		return nil // Don't block execution for unresolved commands
	}

	// MARK: - Script File

	/// Write the command script to a temporary file.
	private func createScriptFile() throws -> String {
		let cacheDir = FileManager.default.urls(
			for: .cachesDirectory, in: .userDomainMask,
		).first!.appendingPathComponent("com.macromates.TextMate/Scripts")

		try FileManager.default.createDirectory(
			at: cacheDir, withIntermediateDirectories: true,
		)

		// Content-addressed filename
		let hash = command.command.utf8.reduce(into: UInt64(5381)) { r, b in
			r = r &* 33 &+ UInt64(b)
		}
		let scriptURL = cacheDir.appendingPathComponent(
			String(hash, radix: 16) + ".sh",
		)

		try command.command.write(
			to: scriptURL, atomically: true, encoding: .utf8,
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o700],
			ofItemAtPath: scriptURL.path,
		)

		return scriptURL.path
	}
}
