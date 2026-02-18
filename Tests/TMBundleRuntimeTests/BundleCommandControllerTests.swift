import Foundation
import Testing
@testable import TMBundleRuntime

// MARK: - BundleCommandController Tests

@Suite("BundleCommandController")
@MainActor
struct BundleCommandControllerTests {
	// MARK: - Helpers

	private func makeCommand(
		name: String = "Test Command",
		command: String = "#!/bin/bash\necho hello",
		input: CommandInput = .selection,
		output: CommandOutput = .replaceInput,
		outputFormat: CommandOutputFormat = .text,
		preExec: PreExecAction = .nop,
	) -> BundleCommand {
		BundleCommand(
			name: name,
			uuid: "12345678-1234-1234-1234-123456789ABC",
			command: command,
			preExec: preExec,
			input: input,
			output: output,
			outputFormat: outputFormat,
		)
	}

	/// A test delegate that records calls.
	final class MockDelegate: BundleCommandControllerDelegate {
		var presentedErrors: [NSError] = []
		var toolTips: [String] = []
		var newDocuments: [(content: String, fileType: String?)] = []
		var injectedVars: [String: String] = [:]
		var saveAllCalled = false
		var shouldAllowSave = true

		func updateEnvironment(_ environment: inout [String: String]) {
			for (k, v) in injectedVars {
				environment[k] = v
			}
		}

		func saveAllEditedDocuments(
			includeAll _: Bool,
			completion: @escaping (Bool) -> Void,
		) {
			saveAllCalled = true
			completion(shouldAllowSave)
		}

		func presentError(_ error: NSError) {
			presentedErrors.append(error)
		}

		func showToolTip(_ text: String) {
			toolTips.append(text)
		}

		func showNewDocument(content: String, fileType: String?) {
			newDocuments.append((content, fileType))
		}
	}

	// MARK: - Initialization

	@Test("Controller stores command and applies fixShebang")
	func initFixesShebang() {
		let cmd = BundleCommand(
			name: "No Shebang",
			uuid: "AAAA",
			command: "echo test",
		)
		let controller = BundleCommandController(command: cmd)
		#expect(controller.command.command.hasPrefix("#!/bin/bash"))
	}

	@Test("Controller preserves existing shebang")
	func initPreservesShebang() {
		let cmd = makeCommand(command: "#!/usr/bin/env ruby\nputs 'hi'")
		let controller = BundleCommandController(command: cmd)
		#expect(controller.command.command.hasPrefix("#!/usr/bin/env ruby"))
	}

	// MARK: - Identifier

	@Test("Identifier returns UUID when valid")
	func validIdentifier() {
		let cmd = makeCommand()
		let controller = BundleCommandController(command: cmd)
		#expect(controller.identifier != nil)
	}

	@Test("Identifier returns nil for invalid UUID")
	func invalidIdentifier() {
		let cmd = BundleCommand(
			name: "Bad UUID",
			uuid: "not-a-uuid",
			command: "#!/bin/bash\necho hi",
		)
		let controller = BundleCommandController(command: cmd)
		#expect(controller.identifier == nil)
	}

	// MARK: - Delegate Protocol Defaults

	@Test("Default delegate implementations do not crash")
	func defaultDelegateImpls() {
		let delegate = MockDelegate()
		var env: [String: String] = [:]
		delegate.updateEnvironment(&env)
		delegate.showToolTip("test")
		delegate.showNewDocument(content: "x", fileType: nil)
	}

	// MARK: - Error Presentation

	@Test("BundleCommandError has expected raw values")
	func errorRawValues() {
		#expect(BundleCommandError.requirementsMissing.rawValue == 1)
		#expect(BundleCommandError.abnormalTermination.rawValue == 2)
	}

	@Test("Error domain is set correctly")
	func errorDomain() {
		#expect(BundleCommandErrorDomain == "com.macromates.TextMate.BundleCommand")
	}

	// MARK: - Notification

	@Test("Termination notification name is correct")
	func notificationName() {
		#expect(
			BundleCommandDidTerminateNotification.rawValue
				== "BundleCommandDidTerminateNotification",
		)
	}

	// MARK: - Terminate

	@Test("Terminate sets abort flag before process exists")
	func terminateBeforeLaunch() {
		let cmd = makeCommand()
		let controller = BundleCommandController(command: cmd)
		// Should not crash when no process is running
		controller.terminate()
	}

	// MARK: - Pre-Exec Save

	@Test("Pre-exec save calls delegate when configured")
	func preExecSave() {
		let cmd = makeCommand(
			command: "#!/bin/bash\nexit 0",
			preExec: .saveDocument,
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		delegate.shouldAllowSave = false // Block execution
		controller.delegate = delegate

		controller.execute(inputData: nil)

		#expect(delegate.saveAllCalled == true)
	}

	// MARK: - Live Execution

	@Test("Execute simple echo command and receive output")
	func executeEchoCommand() async {
		let cmd = makeCommand(
			command: "#!/bin/bash\necho -n hello",
			output: .newWindow,
			outputFormat: .text,
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		controller.delegate = delegate

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			controller.terminationHandler = { _, normalExit in
				#expect(normalExit == true)
				continuation.resume()
			}
			controller.execute(inputData: nil)
		}

		// The output should have been routed to showNewDocument
		#expect(delegate.newDocuments.count == 1)
		#expect(delegate.newDocuments.first?.content.contains("hello") == true)
	}

	@Test("Exit code 205 routes output as tooltip")
	func exitCode205Tooltip() async {
		let cmd = makeCommand(
			command: "#!/bin/bash\necho -n tooltip text\nexit 205",
			output: .discard,
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		controller.delegate = delegate

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			controller.terminationHandler = { _, normalExit in
				#expect(normalExit == true)
				continuation.resume()
			}
			controller.execute(inputData: nil)
		}

		#expect(delegate.toolTips.count == 1)
		#expect(delegate.toolTips.first == "tooltip text")
	}

	@Test("Exit code 200 discards output")
	func exitCode200Discard() async {
		let cmd = makeCommand(
			command: "#!/bin/bash\necho should be discarded\nexit 200",
			output: .newWindow,
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		controller.delegate = delegate

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			controller.terminationHandler = { _, _ in
				continuation.resume()
			}
			controller.execute(inputData: nil)
		}

		#expect(delegate.newDocuments.isEmpty)
		#expect(delegate.toolTips.isEmpty)
	}

	@Test("Non-zero non-special exit code presents error")
	func abnormalExitPresentsError() async throws {
		let cmd = makeCommand(
			command: "#!/bin/bash\necho -n oops >&2\nexit 1",
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		controller.delegate = delegate

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			controller.terminationHandler = { _, normalExit in
				#expect(normalExit == false)
				continuation.resume()
			}
			controller.execute(inputData: nil)
		}

		#expect(delegate.presentedErrors.count == 1)
		let error = try #require(delegate.presentedErrors.first)
		#expect(error.domain == BundleCommandErrorDomain)
	}

	@Test("Input data is piped to stdin")
	func stdinPiping() async {
		let cmd = makeCommand(
			command: "#!/bin/bash\ncat",
			output: .newWindow,
			outputFormat: .text,
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		controller.delegate = delegate

		let inputData = "stdin content".data(using: .utf8)!

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			controller.terminationHandler = { _, _ in
				continuation.resume()
			}
			controller.execute(inputData: inputData)
		}

		#expect(delegate.newDocuments.count == 1)
		#expect(delegate.newDocuments.first?.content == "stdin content")
	}

	@Test("Output handler receives text for non-special placements")
	func outputHandlerCallback() async {
		let cmd = makeCommand(
			command: "#!/bin/bash\necho -n replaced",
			output: .replaceInput,
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		controller.delegate = delegate

		var receivedText: String?
		var receivedPlacement: CommandOutput?
		controller.outputHandler = { text, placement, _, _, _ in
			receivedText = text
			receivedPlacement = placement
		}

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			controller.terminationHandler = { _, _ in
				continuation.resume()
			}
			controller.execute(inputData: nil)
		}

		#expect(receivedText == "replaced")
		#expect(receivedPlacement == .replaceInput)
	}

	// MARK: - Exit Code Mapping

	@Test("Exit code 201 maps to replaceInput")
	func exitCode201() async {
		let cmd = makeCommand(
			command: "#!/bin/bash\necho -n output\nexit 201",
			output: .discard,
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		controller.delegate = delegate

		var receivedPlacement: CommandOutput?
		controller.outputHandler = { _, placement, _, _, _ in
			receivedPlacement = placement
		}

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			controller.terminationHandler = { _, normalExit in
				#expect(normalExit == true)
				continuation.resume()
			}
			controller.execute(inputData: nil)
		}

		#expect(receivedPlacement == .replaceInput)
	}

	@Test("Exit code 206 opens new window with text format")
	func exitCode206NewWindow() async {
		let cmd = makeCommand(
			command: "#!/bin/bash\necho -n new doc\nexit 206",
			output: .discard,
		)
		let controller = BundleCommandController(command: cmd)
		let delegate = MockDelegate()
		controller.delegate = delegate

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			controller.terminationHandler = { _, _ in
				continuation.resume()
			}
			controller.execute(inputData: nil)
		}

		#expect(delegate.newDocuments.count == 1)
		#expect(delegate.newDocuments.first?.content.contains("new doc") == true)
	}
}
