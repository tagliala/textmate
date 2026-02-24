import Foundation
import Testing
@testable import TMCompatibility

// MARK: - EnvironmentBuilder Tests

@Suite("EnvironmentBuilder")
struct EnvironmentBuilderTests {
	@Test("builds editor variables from EditorContext")
	func editorVariables() {
		let editor = EnvironmentBuilder.EditorContext(
			tabSize: 4,
			softTabs: true,
			selectionString: "1:0-1:5",
			scope: "source.swift",
			scopeLeft: "source.swift meta.function",
			lineIndex: 3,
			lineNumber: 1,
			columnNumber: 4,
			currentLine: "let x = 42",
			currentWord: "x",
			selectedText: "let x",
		)

		let env = EnvironmentBuilder.build(editor: editor)

		#expect(env["TM_TAB_SIZE"] == "4")
		#expect(env["TM_SOFT_TABS"] == "YES")
		#expect(env["TM_SELECTION"] == "1:0-1:5")
		#expect(env["TM_SCOPE"] == "source.swift")
		#expect(env["TM_SCOPE_LEFT"] == "source.swift meta.function")
		#expect(env["TM_LINE_INDEX"] == "3")
		#expect(env["TM_LINE_NUMBER"] == "1")
		#expect(env["TM_COLUMN_NUMBER"] == "4")
		#expect(env["TM_CURRENT_LINE"] == "let x = 42")
		#expect(env["TM_CURRENT_WORD"] == "x")
		#expect(env["TM_SELECTED_TEXT"] == "let x")
	}

	@Test("builds document variables and derives filename/directory")
	func documentVariables() {
		let doc = EnvironmentBuilder.DocumentContext(
			filePath: "/Users/test/project/main.swift",
			displayName: "main.swift",
			directory: "/Users/test/project",
		)

		let env = EnvironmentBuilder.build(document: doc)

		#expect(env["TM_FILEPATH"] == "/Users/test/project/main.swift")
		#expect(env["TM_FILENAME"] == "main.swift")
		#expect(env["TM_DIRECTORY"] == "/Users/test/project")
		#expect(env["TM_DISPLAYNAME"] == "main.swift")
	}

	@Test("derives filename and directory from filepath when not provided")
	func derivedPaths() {
		let doc = EnvironmentBuilder.DocumentContext(
			filePath: "/usr/local/bin/script.sh",
			displayName: nil,
			directory: nil,
		)

		let env = EnvironmentBuilder.build(document: doc)

		#expect(env["TM_FILEPATH"] == "/usr/local/bin/script.sh")
		#expect(env["TM_FILENAME"] == "script.sh")
		#expect(env["TM_DIRECTORY"] == "/usr/local/bin")
	}

	@Test("builds project variables")
	func projectVariables() {
		let project = EnvironmentBuilder.ProjectContext(
			projectDirectory: "/Users/test/project",
			projectUUID: "ABC-123",
			scmName: "git",
			scmBranch: "main",
		)

		let env = EnvironmentBuilder.build(project: project)

		#expect(env["TM_PROJECT_DIRECTORY"] == "/Users/test/project")
		#expect(env["TM_PROJECT_UUID"] == "ABC-123")
		#expect(env["TM_SCM_NAME"] == "git")
		#expect(env["TM_SCM_BRANCH"] == "main")
	}

	@Test("builds app variables")
	func appVariables() {
		let app = EnvironmentBuilder.AppContext(
			appPath: "/Applications/TextMate.app",
			pid: 12345,
			supportPath: "/Library/Application Support/TextMate/Support",
		)

		let env = EnvironmentBuilder.build(app: app)

		#expect(env["TM_APP_PATH"] == "/Applications/TextMate.app")
		#expect(env["TM_PID"] == "12345")
		#expect(env["TM_SUPPORT_PATH"] == "/Library/Application Support/TextMate/Support")
	}

	@Test("merges extra variables")
	func extraVariables() {
		let env = EnvironmentBuilder.build(extra: ["CUSTOM_VAR": "hello"])

		#expect(env["CUSTOM_VAR"] == "hello")
	}

	@Test("buildFull includes process environment")
	func buildFull() {
		let env = EnvironmentBuilder.buildFull()

		// Should include at least PATH from the process environment
		#expect(env["PATH"] != nil)
	}

	@Test("allVariableNames contains expected keys")
	func variableNames() {
		#expect(EnvironmentBuilder.allVariableNames.contains("TM_TAB_SIZE"))
		#expect(EnvironmentBuilder.allVariableNames.contains("TM_FILEPATH"))
		#expect(EnvironmentBuilder.allVariableNames.contains("TM_PROJECT_DIRECTORY"))
		#expect(EnvironmentBuilder.allVariableNames.contains("TM_APP_PATH"))
		#expect(EnvironmentBuilder.allVariableNames.count >= 20)
	}

	@Test("nil context values produce no environment keys")
	func nilValues() {
		let doc = EnvironmentBuilder.DocumentContext(
			filePath: nil,
			displayName: nil,
			directory: nil,
		)

		let env = EnvironmentBuilder.build(document: doc)

		#expect(env["TM_FILEPATH"] == nil)
		#expect(env["TM_FILENAME"] == nil)
		#expect(env["TM_DIRECTORY"] == nil)
		#expect(env["TM_DISPLAYNAME"] == nil)
	}
}

// MARK: - CommandTypes Tests

@Suite("CommandTypes")
struct CommandTypesTests {
	@Test("CommandInput parses plist strings")
	func inputFromPlist() {
		#expect(CommandInput(plistString: "selection") == .selection)
		#expect(CommandInput(plistString: "document") == .entireDocument)
		#expect(CommandInput(plistString: "scope") == .scope)
		#expect(CommandInput(plistString: "line") == .line)
		#expect(CommandInput(plistString: "word") == .word)
		#expect(CommandInput(plistString: "character") == .character)
		#expect(CommandInput(plistString: "none") == .nothing)
		#expect(CommandInput(plistString: "garbage") == .selection) // default
	}

	@Test("CommandOutput parses plist strings")
	func outputFromPlist() {
		#expect(CommandOutput(plistString: "replaceInput") == .replaceInput)
		#expect(CommandOutput(plistString: "replaceDocument") == .replaceDocument)
		#expect(CommandOutput(plistString: "atCaret") == .atCaret)
		#expect(CommandOutput(plistString: "afterInput") == .afterInput)
		#expect(CommandOutput(plistString: "newWindow") == .newWindow)
		#expect(CommandOutput(plistString: "toolTip") == .toolTip)
		#expect(CommandOutput(plistString: "discard") == .discard)
		#expect(CommandOutput(plistString: "replaceSelection") == .replaceSelection)
		#expect(CommandOutput(plistString: "garbage") == .replaceInput) // default
	}

	@Test("BundleCommand default values")
	func commandDefaults() {
		let cmd = BundleCommand(
			name: "Test",
			uuid: "123",
			command: "echo hello",
		)

		#expect(cmd.name == "Test")
		#expect(cmd.uuid == "123")
		#expect(cmd.command == "echo hello")
		#expect(cmd.preExec == .nop)
		#expect(cmd.input == .selection)
		#expect(cmd.output == .replaceInput)
		#expect(cmd.outputFormat == .text)
	}

	@Test("fixShebang adds bash shebang when missing")
	func fixShebangAdds() {
		var cmd = BundleCommand(
			name: "Test",
			uuid: "123",
			command: "echo hello",
		)

		cmd.fixShebang()

		#expect(cmd.command.hasPrefix("#!/bin/bash"))
		#expect(cmd.command.contains("echo hello"))
	}

	@Test("fixShebang preserves existing shebang")
	func fixShebangPreserves() {
		var cmd = BundleCommand(
			name: "Test",
			uuid: "123",
			command: "#!/usr/bin/env python3\nprint('hi')",
		)

		cmd.fixShebang()

		#expect(cmd.command.hasPrefix("#!/usr/bin/env python3"))
		#expect(!cmd.command.contains("#!/bin/bash"))
	}

	@Test("AutoRefresh option set")
	func autoRefresh() {
		var refresh: AutoRefresh = [.onDocumentChange, .onDocumentSave]
		#expect(refresh.contains(.onDocumentChange))
		#expect(refresh.contains(.onDocumentSave))
		#expect(!refresh.contains(.onDocumentClose))

		refresh.insert(.onDocumentClose)
		#expect(refresh.contains(.onDocumentClose))
	}

	@Test("PreExecAction variants")
	func preExecAction() {
		#expect(PreExecAction.nop != .saveDocument)
		#expect(PreExecAction.saveProject != .nop)
	}

	@Test("CommandOutputFormat variants")
	func outputFormats() {
		let formats: [CommandOutputFormat] = [.text, .snippet, .html, .completionList, .snippetNoAutoIndent]
		#expect(formats.count == 5)
	}

	@Test("CommandOutputCaret variants")
	func caretVariants() {
		let carets: [CommandOutputCaret] = [
			.afterOutput,
			.selectOutput,
			.interpolateByChar,
			.interpolateByLine,
			.heuristic,
		]
		#expect(carets.count == 5)
	}

	@Test("CommandOutputReuse variants")
	func reuseVariants() {
		let reuse: [CommandOutputReuse] = [.reuseAvailable, .reuseNone, .reuseBusy, .abortAndReuseBusy]
		#expect(reuse.count == 4)
	}
}

// MARK: - RMateServer Tests

// MARK: - PopupDialogHandler Tests

@Suite("PopupDialogHandler")
@MainActor
struct PopupDialogHandlerTests {
	@Test("returns error when no suggestions provided")
	func noSuggestions() {
		let handler = PopupDialogHandler()
		let result = handler.handle(command: "popup", arguments: [], input: nil)
		#expect(result.exitCode == 1)
		#expect(result.errorMessage?.contains("No suggestions") == true)
	}

	@Test("parses suggestions from plist input")
	func parseSuggestionsFromPlist() throws {
		let handler = PopupDialogHandler()
		let plist: [String: Any] = [
			"suggestions": [
				["display": "hello", "match": "hello", "insert": "hello()"],
				["display": "world", "match": "world"],
			],
			"returnChoice": true,
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: plist, format: .xml, options: 0,
		)
		// The popup will show a menu at mouse location — in headless tests
		// the menu returns nil (user cancelled), so we expect nil output.
		let result = handler.handle(command: "popup", arguments: [], input: data)
		// Cancelled popup returns exitCode 0, nil output.
		#expect(result.exitCode == 0)
	}

	@Test("parses suggestions from --suggestions argument")
	func parseSuggestionsFromArgs() {
		let handler = PopupDialogHandler()
		let plistString = "( { display = law; match = law; }, { display = laws; match = laws; } )"
		let result = handler.handle(
			command: "popup",
			arguments: ["--suggestions", plistString],
			input: nil,
		)
		#expect(result.exitCode == 0)
	}

	@Test("filters suggestions by alreadyTyped")
	func filterByAlreadyTyped() throws {
		let handler = PopupDialogHandler()
		let plist: [String: Any] = [
			"suggestions": [
				["display": "hello", "match": "hello"],
				["display": "world", "match": "world"],
			],
			"alreadyTyped": "xyz",
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: plist, format: .xml, options: 0,
		)
		// No suggestions match "xyz", so result should be empty (not an error).
		let result = handler.handle(command: "popup", arguments: [], input: data)
		#expect(result.exitCode == 0)
		#expect(result.output == nil)
	}

	@Test("case insensitive filtering excludes non-matching")
	func caseInsensitiveFilter() throws {
		let handler = PopupDialogHandler()
		let plist: [String: Any] = [
			"suggestions": [
				["display": "Hello", "match": "Hello"],
				["display": "World", "match": "World"],
			],
			"alreadyTyped": "nomatch",
			"caseInsensitive": true,
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: plist, format: .xml, options: 0,
		)
		let result = handler.handle(command: "popup", arguments: [], input: data)
		#expect(result.exitCode == 0)
		#expect(result.output == nil)
	}

	@Test("empty input data returns error")
	func emptyInputData() {
		let handler = PopupDialogHandler()
		let result = handler.handle(command: "popup", arguments: [], input: Data())
		#expect(result.exitCode == 1)
	}
}

@Suite("RMateServer")
struct RMateServerTests {
	@Test("welcome message has correct format")
	func welcomeMessage() async {
		let msg = await RMateServer.welcomeMessage()
		#expect(msg.hasPrefix("220 "))
		#expect(msg.contains("RMATE TextMate"))
		#expect(msg.hasSuffix(")\n"))
	}

	@Test("RMateOpenRequest parses record arguments")
	func openRequestParsing() {
		var record = RMateRecord(command: "open")
		record.arguments["path"] = "/tmp/test.txt"
		record.arguments["display-name"] = "test.txt"
		record.arguments["selection"] = "1:0"
		record.arguments["file-type"] = "source.python"
		record.arguments["wait"] = "yes"
		record.arguments["data-on-save"] = "yes"
		record.arguments["re-activate"] = "yes"
		record.arguments["add-to-recents"] = "yes"
		record.arguments["token"] = "abc123"

		let request = RMateOpenRequest(record: record)

		#expect(request.path == "/tmp/test.txt")
		#expect(request.displayName == "test.txt")
		#expect(request.selection == "1:0")
		#expect(request.fileType == "source.python")
		#expect(request.wait == true)
		#expect(request.dataOnSave == true)
		#expect(request.reActivate == true)
		#expect(request.addToRecents == true)
		#expect(request.token == "abc123")
	}

	@Test("RMateOpenRequest defaults for missing arguments")
	func openRequestDefaults() {
		let record = RMateRecord(command: "open")
		let request = RMateOpenRequest(record: record)

		#expect(request.path == nil)
		#expect(request.uuid == nil)
		#expect(request.displayName == nil)
		#expect(request.wait == false)
		#expect(request.dataOnSave == false)
		#expect(request.dataOnClose == false)
		#expect(request.reActivate == false)
		#expect(request.addToRecents == false)
		#expect(request.fileData == nil)
	}

	@Test("RMateRecord accepts data")
	func recordAcceptsData() {
		var record = RMateRecord(command: "open")
		let data: [UInt8] = [72, 101, 108, 108, 111]
		record.acceptData(data)

		#expect(record.fileData == Data(data))
	}

	@Test("RMateRecord appends data incrementally")
	func recordAppendsData() {
		var record = RMateRecord(command: "open")
		record.acceptData([1, 2, 3])
		record.acceptData([4, 5])

		#expect(record.fileData?.count == 5)
		#expect(record.fileData == Data([1, 2, 3, 4, 5]))
	}

	@Test("server initializes with defaults")
	func serverDefaults() async {
		let server = await RMateServer()
		let port = await server.port
		let listening = await server.isListening

		#expect(port == 52698)
		#expect(listening == false)
	}

	@Test("server initializes with custom port")
	func serverCustomPort() async {
		let server = await RMateServer(port: 12345, listenForRemoteClients: true)
		let port = await server.port
		let remote = await server.listenForRemoteClients

		#expect(port == 12345)
		#expect(remote == true)
	}
}
