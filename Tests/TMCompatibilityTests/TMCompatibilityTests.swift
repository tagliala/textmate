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

// MARK: - CommandOutputHandler Tests

@Suite("CommandOutputHandler")
struct CommandOutputHandlerTests {
	@Test("exit code 0 uses declared output mode")
	func exitCodeZero() {
		let result = CommandResult(
			exitCode: 0,
			stdout: Data("hello".utf8),
			stderr: Data(),
			command: BundleCommand(
				name: "Test", uuid: "1",
				command: "echo hello",
				output: .replaceInput,
			),
		)

		let action = CommandOutputHandler.action(for: result)
		#expect(action == .replaceSelection("hello"))
	}

	@Test("exit code 200 means discard")
	func exitCode200() {
		let result = CommandResult(
			exitCode: 200,
			stdout: Data("ignored".utf8),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(CommandOutputHandler.action(for: result) == .discard)
	}

	@Test("exit code 201 means replace selection")
	func exitCode201() {
		let result = CommandResult(
			exitCode: 201,
			stdout: Data("new text".utf8),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(CommandOutputHandler.action(for: result) == .replaceSelection("new text"))
	}

	@Test("exit code 202 means replace document")
	func exitCode202() {
		let result = CommandResult(
			exitCode: 202,
			stdout: Data("full doc".utf8),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(CommandOutputHandler.action(for: result) == .replaceDocument("full doc"))
	}

	@Test("exit code 203 means insert snippet")
	func exitCode203() {
		let result = CommandResult(
			exitCode: 203,
			stdout: Data("$1 snippet".utf8),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(CommandOutputHandler.action(for: result) == .insertSnippet("$1 snippet"))
	}

	@Test("exit code 204 means show HTML")
	func exitCode204() {
		let result = CommandResult(
			exitCode: 204,
			stdout: Data("<h1>Hi</h1>".utf8),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(CommandOutputHandler.action(for: result) == .showHTML("<h1>Hi</h1>"))
	}

	@Test("exit code 205 means tool tip")
	func exitCode205() {
		let result = CommandResult(
			exitCode: 205,
			stdout: Data("tip".utf8),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(CommandOutputHandler.action(for: result) == .showToolTip("tip"))
	}

	@Test("exit code 206 means insert at caret")
	func exitCode206() {
		let result = CommandResult(
			exitCode: 206,
			stdout: Data("inserted".utf8),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(CommandOutputHandler.action(for: result) == .insertAtCaret("inserted"))
	}

	@Test("non-zero non-special exit code shows error as tooltip")
	func nonZeroExitCode() {
		let result = CommandResult(
			exitCode: 1,
			stdout: Data("output".utf8),
			stderr: Data("error msg".utf8),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		// stderr takes priority
		#expect(CommandOutputHandler.action(for: result) == .showToolTip("error msg"))
	}

	@Test("non-zero with empty stderr uses stdout for tooltip")
	func nonZeroEmptyStderr() {
		let result = CommandResult(
			exitCode: 1,
			stdout: Data("output".utf8),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(CommandOutputHandler.action(for: result) == .showToolTip("output"))
	}

	@Test("output format snippet overrides output mode")
	func snippetFormatOverride() {
		let result = CommandResult(
			exitCode: 0,
			stdout: Data("$0 text".utf8),
			stderr: Data(),
			command: BundleCommand(
				name: "T", uuid: "1", command: "x",
				output: .replaceInput,
				outputFormat: .snippet,
			),
		)

		#expect(CommandOutputHandler.action(for: result) == .insertSnippet("$0 text"))
	}

	@Test("output format html overrides output mode")
	func htmlFormatOverride() {
		let result = CommandResult(
			exitCode: 0,
			stdout: Data("<p>text</p>".utf8),
			stderr: Data(),
			command: BundleCommand(
				name: "T", uuid: "1", command: "x",
				output: .replaceInput,
				outputFormat: .html,
			),
		)

		#expect(CommandOutputHandler.action(for: result) == .showHTML("<p>text</p>"))
	}

	@Test("output format completionList overrides output mode")
	func completionListFormatOverride() {
		let result = CommandResult(
			exitCode: 0,
			stdout: Data("completions".utf8),
			stderr: Data(),
			command: BundleCommand(
				name: "T", uuid: "1", command: "x",
				output: .replaceInput,
				outputFormat: .completionList,
			),
		)

		#expect(CommandOutputHandler.action(for: result) == .showCompletions("completions"))
	}

	@Test("caret placement mapping")
	func caretPlacement() {
		#expect(CommandOutputHandler.caretPlacement(for: .afterOutput) == .afterOutput)
		#expect(CommandOutputHandler.caretPlacement(for: .selectOutput) == .selectOutput)
		#expect(CommandOutputHandler.caretPlacement(for: .interpolateByChar) == .interpolateByChar)
		#expect(CommandOutputHandler.caretPlacement(for: .interpolateByLine) == .interpolateByLine)
		#expect(CommandOutputHandler.caretPlacement(for: .heuristic) == .heuristic)
	}

	@Test("CommandResult convenience properties")
	func resultProperties() {
		let result = CommandResult(
			exitCode: 0,
			stdout: Data("hello".utf8),
			stderr: Data("warn".utf8),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)

		#expect(result.isSuccess)
		#expect(result.stdoutString == "hello")
		#expect(result.stderrString == "warn")

		let fail = CommandResult(
			exitCode: 1,
			stdout: Data(),
			stderr: Data(),
			command: BundleCommand(name: "T", uuid: "1", command: "x"),
		)
		#expect(!fail.isSuccess)
	}

	@Test("CommandResult exitCodeAction maps special codes")
	func exitCodeAction() {
		let make = { (code: Int32) in
			CommandResult(
				exitCode: code, stdout: Data(), stderr: Data(),
				command: BundleCommand(name: "T", uuid: "1", command: "x"),
			)
		}
		#expect(make(200).exitCodeAction == .discard)
		#expect(make(201).exitCodeAction == .replaceSelection)
		#expect(make(202).exitCodeAction == .replaceDocument)
		#expect(make(204).exitCodeAction == .newWindow)
		#expect(make(205).exitCodeAction == .toolTip)
		#expect(make(206).exitCodeAction == .atCaret)
		#expect(make(0).exitCodeAction == nil)
		#expect(make(1).exitCodeAction == nil)
	}
}

// MARK: - SettingsMigrator Tests

@Suite("SettingsMigrator")
struct SettingsMigratorTests {
	@Test("parseTMProperties parses root section")
	func parseRoot() {
		let content = """
		tabSize = 3
		softTabs = true
		"""

		let sections = SettingsMigrator.parseTMProperties(content)

		#expect(sections.count == 1)
		#expect(sections[0].selector == "")
		#expect(sections[0].assignments.count == 2)
		#expect(sections[0].assignments[0].key == "tabSize")
		#expect(sections[0].assignments[0].value == "3")
		#expect(sections[0].assignments[1].key == "softTabs")
		#expect(sections[0].assignments[1].value == "true")
	}

	@Test("parseTMProperties handles file glob sections")
	func parseGlobSection() {
		let content = """
		softTabs = true

		[*.py]
		tabSize = 4
		softTabs = true
		"""

		let sections = SettingsMigrator.parseTMProperties(content)

		#expect(sections.count == 2)
		#expect(sections[0].selector == "")
		#expect(sections[1].selector == "*.py")
		#expect(sections[1].isScopeSelector == false)
		#expect(sections[1].assignments.count == 2)
	}

	@Test("parseTMProperties handles scope selector sections")
	func parseScopeSection() {
		let content = """
		[source.python]
		tabSize = 4
		"""

		let sections = SettingsMigrator.parseTMProperties(content)

		#expect(sections.count == 1)
		#expect(sections[0].selector == "source.python")
		#expect(sections[0].isScopeSelector == true)
	}

	@Test("parseTMProperties skips comments and blank lines")
	func parseSkipsComments() {
		let content = """
		# This is a comment
		tabSize = 3

		# Another comment

		softTabs = false
		"""

		let sections = SettingsMigrator.parseTMProperties(content)

		#expect(sections.count == 1)
		#expect(sections[0].assignments.count == 2)
	}

	@Test("parseTMProperties handles text and attr scope prefixes")
	func parseScopePrefixes() {
		let content1 = """
		[text.html]
		softWrap = true
		"""
		let content2 = """
		[attr.untitled]
		fileType = source.ruby
		"""

		let s1 = SettingsMigrator.parseTMProperties(content1)
		let s2 = SettingsMigrator.parseTMProperties(content2)

		#expect(s1[0].isScopeSelector == true)
		#expect(s2[0].isScopeSelector == true)
	}

	@Test("parseTMProperties handles multiple glob sections")
	func multipleGlobs() {
		let content = """
		[*.h]
		fileType = source.objc

		[*.cc]
		fileType = source.c++
		"""

		let sections = SettingsMigrator.parseTMProperties(content)

		#expect(sections.count == 2)
		#expect(sections[0].selector == "*.h")
		#expect(sections[1].selector == "*.cc")
	}

	@Test("knownPreferenceKeys contains essential keys")
	func knownKeys() {
		#expect(SettingsMigrator.knownPreferenceKeys.contains("fontName"))
		#expect(SettingsMigrator.knownPreferenceKeys.contains("fontSize"))
		#expect(SettingsMigrator.knownPreferenceKeys.contains("theme"))
		#expect(SettingsMigrator.knownPreferenceKeys.contains("tabSize"))
		#expect(SettingsMigrator.knownPreferenceKeys.contains("softTabs"))
		#expect(SettingsMigrator.knownPreferenceKeys.contains("rmatePort"))
	}

	@Test("detectLegacyInstallation returns an installation struct")
	func detectInstallation() {
		let installation = SettingsMigrator.detectLegacyInstallation()
		// Just verify the struct is created without crashing
		_ = installation.hasAnyData
	}

	@Test("TMPropertiesSection equality")
	func sectionEquality() {
		let s1 = SettingsMigrator.TMPropertiesSection(
			selector: "*.py",
			isScopeSelector: false,
			assignments: [("tabSize", "4")],
		)
		let s2 = SettingsMigrator.TMPropertiesSection(
			selector: "*.py",
			isScopeSelector: false,
			assignments: [("tabSize", "4")],
		)
		let s3 = SettingsMigrator.TMPropertiesSection(
			selector: "*.rb",
			isScopeSelector: false,
			assignments: [("tabSize", "2")],
		)

		#expect(s1 == s2)
		#expect(s1 != s3)
	}
}

// MARK: - RMateServer Tests

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

// MARK: - BundleInfo Tests

@Suite("BundleInfo")
struct BundleInfoTests {
	@Test("BundleInfo equality")
	func bundleInfoEquality() {
		let a = BundleInfo(name: "Ruby", uuid: "abc", path: "/a")
		let b = BundleInfo(name: "Ruby", uuid: "abc", path: "/a")
		let c = BundleInfo(name: "Python", uuid: "def", path: "/b")

		#expect(a == b)
		#expect(a != c)
	}

	@Test("BundleInfo with optional fields")
	func bundleInfoOptionals() {
		let info = BundleInfo(
			name: "HTML",
			uuid: "xyz",
			path: "/bundles/HTML.tmbundle",
			contactName: "Author",
			contactEmailRot13: "nhgube@rknzcyr.pbz",
			description: "HTML support",
		)

		#expect(info.contactName == "Author")
		#expect(info.description == "HTML support")
	}
}
