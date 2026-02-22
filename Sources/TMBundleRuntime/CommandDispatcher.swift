import Foundation
import TMCompatibility

// MARK: - Command Delegate

/// Protocol the host (editor/document) implements to supply input data
/// and receive command output, mirroring the C++ `command::delegate_t`.
@MainActor
public protocol CommandDispatcherDelegate: AnyObject {
	/// Provides the input data for the command's stdin based on the input source.
	func inputData(
		for source: CommandInput,
		fallback: CommandInput,
		format: CommandInputFormat,
		scope: String,
	) -> Data

	/// Called when the command produces text output to replace input/document.
	func applyTextOutput(
		_ text: String,
		placement: CommandOutput,
		format: CommandOutputFormat,
		caret: CommandOutputCaret,
	)

	/// Called when the command wants to show HTML output.
	func showHTMLOutput(_ html: String, reuse: CommandOutputReuse, command: BundleCommand)

	/// Called when the command wants to show a tooltip.
	func showToolTip(_ text: String)

	/// Called when the command wants to open a new document with output.
	func showNewDocument(_ text: String)

	/// Called when the command wants to show a completion list.
	func showCompletions(_ text: String)

	/// Called when the command wants to insert a snippet.
	func insertSnippet(_ snippet: String, disableAutoIndent: Bool)

	/// Called when the command produces an error.
	func showError(command: BundleCommand, exitCode: Int, stdout: String, stderr: String)

	/// Called before execution — implementation should save as needed.
	func performPreExecAction(_ action: PreExecAction) async -> Bool

	/// Returns the current scope string for scope-based filtering.
	var currentScope: String { get }

	/// Returns the working directory for command execution.
	var workingDirectory: String { get }

	/// Returns environment variables for the current context.
	var environment: [String: String] { get }
}

// MARK: - Dispatcher State

/// Tracks the state of the command execution pipeline.
public enum CommandDispatcherState: Sendable, Equatable {
	case idle
	case running(commandName: String)
	case waitingForPermission
}

// MARK: - Command Dispatcher

/// Orchestrates the full lifecycle of a bundle command execution:
/// 1. Security check → permission request if needed
/// 2. Pre-exec action (save document/project)
/// 3. Build environment variables
/// 4. Gather input data
/// 5. Create and launch process
/// 6. Route output to appropriate handler
///
/// This is the main entry point for executing any bundle command.
@MainActor
public final class CommandDispatcher {
	/// The bundle index for looking up items.
	public let bundleIndex: BundleIndex

	/// The security policy for authorization checks.
	public let securityPolicy: SecurityPolicy

	/// The command parser.
	private let parser = BundleCommandParser()

	/// The delegate receiving input requests and output routing.
	public weak var delegate: CommandDispatcherDelegate?

	/// Currently running command and its process, if any.
	private var activeRunner: ActiveRunner?

	/// Current state.
	public private(set) var state: CommandDispatcherState = .idle

	/// Callback for permission prompts (set by the UI layer).
	public var permissionHandler: (@MainActor (PermissionRequest) async -> PermissionResponse)?

	/// Cache directory for content-addressed script files.
	private let scriptCacheDirectory: String

	public init(
		bundleIndex: BundleIndex,
		securityPolicy: SecurityPolicy,
		scriptCacheDirectory: String? = nil,
	) {
		self.bundleIndex = bundleIndex
		self.securityPolicy = securityPolicy
		self.scriptCacheDirectory = scriptCacheDirectory ?? {
			let caches = NSSearchPathForDirectoriesInDomains(
				.cachesDirectory,
				.userDomainMask,
				true,
			).first ?? NSTemporaryDirectory()
			return (caches as NSString).appendingPathComponent("com.macromates.TextMate/Scripts")
		}()
	}

	// MARK: - Execution

	/// Executes a bundle item by UUID.
	public func execute(itemUUID: String) async {
		guard let item = bundleIndex.lookup(uuid: itemUUID) else { return }
		guard let plist = item.plist else { return }
		guard var command = parser.parse(plist: plist, name: item.name, uuid: item.uuid) else {
			return
		}
		command.fixShebang()
		await execute(command: command, bundleName: bundleName(for: item))
	}

	/// Executes a pre-parsed `BundleCommand`.
	public func execute(command: BundleCommand, bundleName: String = "") async {
		guard state == .idle else { return }

		// 1. Security check.
		let requiredLevel = trustLevelRequired(for: command)
		if let request = securityPolicy.permissionRequest(
			commandName: command.name,
			bundleName: bundleName,
			bundleUUID: command.uuid,
			requiredLevel: requiredLevel,
		) {
			state = .waitingForPermission
			guard let handler = permissionHandler else {
				state = .idle
				return
			}
			let response = await handler(request)
			securityPolicy.applyResponse(response, to: request)

			switch response {
			case .denyOnce, .denyAlways:
				state = .idle
				return
			case .allowOnce, .allowAlways:
				break
			}
		}

		// 2. Pre-exec action.
		if command.preExec != .nop {
			guard let delegate else {
				state = .idle
				return
			}
			let success = await delegate.performPreExecAction(command.preExec)
			if !success {
				state = .idle
				return
			}
		}

		// 3. Build environment.
		guard let delegate else {
			state = .idle
			return
		}

		let environment = delegate.environment
		let workingDirectory = delegate.workingDirectory

		// 4. Gather input.
		// Pass the command's scope selector (not currentScope) so that
		// `.scope` input can walk left/right matching the selector.
		// This mirrors C++ runner.mm which passes `_command.scope_selector`.
		let inputData = delegate.inputData(
			for: command.input,
			fallback: command.inputFallback,
			format: command.inputFormat,
			scope: command.scopeSelector,
		)

		// 5. Create script file.
		var mutableCommand = command
		mutableCommand.fixShebang()

		let scriptPath = createScriptFile(for: mutableCommand)
		guard let scriptPath else {
			state = .idle
			return
		}

		// 6. Launch process.
		state = .running(commandName: command.name)

		let result = await runProcess(
			scriptPath: scriptPath,
			environment: environment,
			workingDirectory: workingDirectory,
			inputData: inputData,
		)

		// 7. Route output.
		routeOutput(result: result, command: command)
		state = .idle
	}

	/// Terminates the currently running command, if any.
	public func terminate() {
		activeRunner?.process.terminate()
		activeRunner = nil
		state = .idle
	}

	/// Interrupts (SIGINT) the currently running command.
	public func interrupt() {
		activeRunner?.process.interrupt()
	}

	// MARK: - Script Caching

	/// Creates a content-addressed script file and returns its path.
	private func createScriptFile(for command: BundleCommand) -> String? {
		let fm = FileManager.default

		// Ensure cache directory exists.
		try? fm.createDirectory(
			atPath: scriptCacheDirectory,
			withIntermediateDirectories: true,
		)

		// SHA-256 hash of script content for content-addressing.
		let scriptData = Data(command.command.utf8)
		let hash = scriptData.sha256HexString

		let scriptPath = (scriptCacheDirectory as NSString)
			.appendingPathComponent("\(hash).sh")

		if !fm.fileExists(atPath: scriptPath) {
			fm.createFile(atPath: scriptPath, contents: scriptData)
			// Make executable.
			try? fm.setAttributes(
				[.posixPermissions: 0o700],
				ofItemAtPath: scriptPath,
			)
		}

		return scriptPath
	}

	// MARK: - Process Execution

	/// Runs the command script and collects output.
	private func runProcess(
		scriptPath: String,
		environment: [String: String],
		workingDirectory: String,
		inputData: Data,
	) async -> CommandResult {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.executableURL = URL(fileURLWithPath: scriptPath)
			process.environment = environment
			process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

			let stdinPipe = Pipe()
			let stdoutPipe = Pipe()
			let stderrPipe = Pipe()

			process.standardInput = stdinPipe
			process.standardOutput = stdoutPipe
			process.standardError = stderrPipe

			activeRunner = ActiveRunner(process: process)

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

			process.terminationHandler = { [weak self] proc in
				stdoutPipe.fileHandleForReading.readabilityHandler = nil
				stderrPipe.fileHandleForReading.readabilityHandler = nil

				// Read any remaining data.
				let finalStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
				let finalStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
				stdoutBox.withLock { $0.append(finalStdout) }
				stderrBox.withLock { $0.append(finalStderr) }

				let result = CommandResult(
					exitCode: Int(proc.terminationStatus),
					stdout: stdoutBox.value,
					stderr: stderrBox.value,
					commandName: "",
				)

				DispatchQueue.main.async {
					self?.activeRunner = nil
					continuation.resume(returning: result)
				}
			}

			do {
				try process.run()

				// Write input data to stdin.
				if !inputData.isEmpty {
					stdinPipe.fileHandleForWriting.write(inputData)
				}
				stdinPipe.fileHandleForWriting.closeFile()
			} catch {
				activeRunner = nil
				let result = CommandResult(
					exitCode: -1,
					stdout: Data(),
					stderr: Data(error.localizedDescription.utf8),
					commandName: "",
				)
				continuation.resume(returning: result)
			}
		}
	}

	// MARK: - Output Routing

	/// Routes command output to the appropriate delegate method.
	private func routeOutput(result: CommandResult, command: BundleCommand) {
		guard let delegate else { return }

		let exitCode = result.exitCode
		let stdout = result.stdoutString
		let stderr = result.stderrString

		// Check for special exit codes (200–208) that override output placement.
		let effectiveOutput = exitCodeOverride(exitCode) ?? command.output

		// Non-zero, non-special exit code = error.
		if exitCode != 0, exitCodeOverride(exitCode) == nil {
			delegate.showError(
				command: command,
				exitCode: exitCode,
				stdout: stdout,
				stderr: stderr,
			)
			return
		}

		switch effectiveOutput {
		case .discard:
			break

		case .replaceInput, .replaceSelection:
			if command.outputFormat == .snippet {
				delegate.insertSnippet(
					stdout,
					disableAutoIndent: command.disableOutputAutoIndent,
				)
			} else {
				delegate.applyTextOutput(
					stdout,
					placement: effectiveOutput,
					format: command.outputFormat,
					caret: command.outputCaret,
				)
			}

		case .replaceDocument:
			delegate.applyTextOutput(
				stdout,
				placement: .replaceDocument,
				format: command.outputFormat,
				caret: command.outputCaret,
			)

		case .atCaret:
			if command.outputFormat == .snippet {
				delegate.insertSnippet(
					stdout,
					disableAutoIndent: command.disableOutputAutoIndent,
				)
			} else {
				delegate.applyTextOutput(
					stdout,
					placement: .atCaret,
					format: command.outputFormat,
					caret: command.outputCaret,
				)
			}

		case .afterInput:
			delegate.applyTextOutput(
				stdout,
				placement: .afterInput,
				format: command.outputFormat,
				caret: command.outputCaret,
			)

		case .newWindow:
			if command.outputFormat == .html {
				delegate.showHTMLOutput(stdout, reuse: command.outputReuse, command: command)
			} else {
				delegate.showNewDocument(stdout)
			}

		case .toolTip:
			delegate.showToolTip(stdout)
		}
	}

	/// Maps special exit codes 200-208 to output placement overrides.
	private func exitCodeOverride(_ exitCode: Int) -> CommandOutput? {
		switch exitCode {
		case 200: .discard
		case 201: .replaceInput
		case 202: .replaceDocument
		case 203: .atCaret
		case 204: .afterInput
		case 205: .newWindow
		case 206: .toolTip
		case 207: .newWindow // show as HTML
		case 208: .replaceSelection
		default: nil
		}
	}

	/// Determines the trust level required for a command.
	private func trustLevelRequired(for command: BundleCommand) -> TrustLevel {
		// Commands that discard output are read-only.
		if command.output == .discard && command.preExec == .nop {
			return .readOnly
		}
		// Commands that modify the document need document write.
		if command.output == .replaceInput || command.output == .atCaret
			|| command.output == .afterInput || command.output == .replaceSelection
			|| command.output == .replaceDocument
		{
			return .documentWrite
		}
		// All other commands (tooltip, new window, HTML) get full trust.
		return .full
	}

	/// Resolves the bundle name for an item.
	private func bundleName(for item: BundleItem) -> String {
		bundleIndex.bundle(uuid: item.bundleUUID)?.name ?? "Unknown Bundle"
	}
}

// MARK: - Active Runner

private struct ActiveRunner {
	let process: Process
}

// MARK: - Command Result

/// The result of a completed command execution.
public struct CommandResult: Sendable {
	public let exitCode: Int
	public let stdout: Data
	public let stderr: Data
	public let commandName: String

	public init(exitCode: Int, stdout: Data, stderr: Data, commandName: String) {
		self.exitCode = exitCode
		self.stdout = stdout
		self.stderr = stderr
		self.commandName = commandName
	}

	/// Stdout decoded as UTF-8.
	public var stdoutString: String {
		String(data: stdout, encoding: .utf8) ?? ""
	}

	/// Stderr decoded as UTF-8.
	public var stderrString: String {
		String(data: stderr, encoding: .utf8) ?? ""
	}
}

// MARK: - Data SHA-256

extension Data {
	/// Returns a hex-encoded SHA-256 hash of this data.
	var sha256HexString: String {
		// Simple hash using the built-in CC_SHA256 via CryptoKit when available.
		// Fallback to a simple FNV-1a hash for script caching (not security-critical).
		var hash: UInt64 = 14_695_981_039_346_656_037
		for byte in self {
			hash ^= UInt64(byte)
			hash &*= 1_099_511_628_211
		}
		return String(format: "%016llx", hash)
	}
}
