import Foundation
import Testing
import TMCompatibility
@testable import TMBundleRuntime

// MARK: - Security Policy Tests

@Suite("SecurityPolicy")
struct SecurityPolicyTests {
	@Test("Default trust level is applied")
	func defaultTrustLevel() {
		let policy = SecurityPolicy(defaultTrustLevel: .documentWrite)
		#expect(policy.trustLevel(forBundle: "some-uuid") == .documentWrite)
	}

	@Test("Per-bundle override takes precedence")
	func overrideTrustLevel() {
		let policy = SecurityPolicy(defaultTrustLevel: .readOnly)
		policy.setTrustLevel(.full, forBundle: "bundle-1")
		#expect(policy.trustLevel(forBundle: "bundle-1") == .full)
		#expect(policy.trustLevel(forBundle: "bundle-2") == .readOnly)
	}

	@Test("Built-in bundles are always fully trusted")
	func builtInBundles() {
		let policy = SecurityPolicy(
			defaultTrustLevel: .blocked,
			builtInBundleUUIDs: ["builtin-1"],
		)
		#expect(policy.trustLevel(forBundle: "builtin-1") == .full)
		#expect(policy.trustLevel(forBundle: "other") == .blocked)
	}

	@Test("Register additional built-in bundles")
	func registerBuiltIn() {
		let policy = SecurityPolicy(defaultTrustLevel: .readOnly)
		policy.registerBuiltInBundles(["new-builtin"])
		#expect(policy.trustLevel(forBundle: "new-builtin") == .full)
	}

	@Test("Authorization checks")
	func isAuthorized() {
		let policy = SecurityPolicy(defaultTrustLevel: .documentWrite)
		#expect(policy.isAuthorized(bundleUUID: "b1", requiredLevel: .readOnly))
		#expect(policy.isAuthorized(bundleUUID: "b1", requiredLevel: .documentWrite))
		#expect(!policy.isAuthorized(bundleUUID: "b1", requiredLevel: .full))
	}

	@Test("Permission request is nil when authorized")
	func permissionRequestAuthorized() {
		let policy = SecurityPolicy(defaultTrustLevel: .full)
		let request = policy.permissionRequest(
			commandName: "Test",
			bundleName: "Bundle",
			bundleUUID: "uuid",
			requiredLevel: .full,
		)
		#expect(request == nil)
	}

	@Test("Permission request is created when not authorized")
	func permissionRequestRequired() {
		let policy = SecurityPolicy(defaultTrustLevel: .readOnly)
		let request = policy.permissionRequest(
			commandName: "Test",
			bundleName: "Bundle",
			bundleUUID: "uuid",
			requiredLevel: .full,
		)
		#expect(request != nil)
		#expect(request?.commandName == "Test")
		#expect(request?.bundleName == "Bundle")
		#expect(request?.requiredLevel == .full)
		#expect(request?.currentLevel == .readOnly)
	}

	@Test("Apply allowAlways response")
	func applyAllowAlways() {
		let policy = SecurityPolicy(defaultTrustLevel: .readOnly)
		let request = PermissionRequest(
			commandName: "Test",
			bundleName: "Bundle",
			bundleUUID: "uuid",
			requiredLevel: .full,
			currentLevel: .readOnly,
		)
		policy.applyResponse(.allowAlways, to: request)
		#expect(policy.trustLevel(forBundle: "uuid") == .full)
	}

	@Test("Apply denyAlways response")
	func applyDenyAlways() {
		let policy = SecurityPolicy(defaultTrustLevel: .documentWrite)
		let request = PermissionRequest(
			commandName: "Test",
			bundleName: "Bundle",
			bundleUUID: "uuid",
			requiredLevel: .full,
			currentLevel: .documentWrite,
		)
		policy.applyResponse(.denyAlways, to: request)
		#expect(policy.trustLevel(forBundle: "uuid") == .blocked)
	}

	@Test("Reset trust level reverts to default")
	func resetTrustLevel() {
		let policy = SecurityPolicy(defaultTrustLevel: .readOnly)
		policy.setTrustLevel(.full, forBundle: "uuid")
		#expect(policy.trustLevel(forBundle: "uuid") == .full)
		policy.resetTrustLevel(forBundle: "uuid")
		#expect(policy.trustLevel(forBundle: "uuid") == .readOnly)
	}

	@Test("All overrides returns stored values")
	func allOverrides() {
		let policy = SecurityPolicy(defaultTrustLevel: .readOnly)
		policy.setTrustLevel(.full, forBundle: "a")
		policy.setTrustLevel(.blocked, forBundle: "b")
		let overrides = policy.allOverrides
		#expect(overrides.count == 2)
		#expect(overrides["a"] == .full)
		#expect(overrides["b"] == .blocked)
	}

	@Test("TrustLevel is comparable")
	func trustLevelComparable() {
		#expect(TrustLevel.blocked < TrustLevel.readOnly)
		#expect(TrustLevel.readOnly < TrustLevel.documentWrite)
		#expect(TrustLevel.documentWrite < TrustLevel.projectWrite)
		#expect(TrustLevel.projectWrite < TrustLevel.full)
	}
}

// MARK: - Bundle Index Tests

@Suite("BundleIndex")
struct BundleIndexTests {
	private func makeItem(
		uuid: String = UUID().uuidString,
		name: String = "Test",
		kind: BundleItemKind = .command,
		bundleUUID: String = "bundle-1",
		tabTrigger: String? = nil,
		keyEquivalent: String? = nil,
		isDisabled: Bool = false,
	) -> BundleItem {
		BundleItem(
			uuid: uuid,
			name: name,
			kind: kind,
			bundleUUID: bundleUUID,
			tabTrigger: tabTrigger,
			keyEquivalent: keyEquivalent,
			isDisabled: isDisabled,
		)
	}

	@Test("Set and query index")
	func setAndQuery() {
		let index = BundleIndex()
		let item = makeItem(uuid: "id-1", name: "Hello")
		let bundle = BundleDescriptor(uuid: "bundle-1", name: "TestBundle")

		index.setIndex(items: [item], bundles: [bundle])

		#expect(index.itemCount == 1)
		#expect(index.allBundles.count == 1)
	}

	@Test("Lookup by UUID")
	func lookupByUUID() {
		let index = BundleIndex()
		let item = makeItem(uuid: "id-1", name: "Hello")
		index.setIndex(items: [item], bundles: [])

		#expect(index.lookup(uuid: "id-1")?.name == "Hello")
		#expect(index.lookup(uuid: "nonexistent") == nil)
	}

	@Test("Query by tab trigger")
	func queryByTabTrigger() {
		let index = BundleIndex()
		let item1 = makeItem(uuid: "1", name: "Snippet1", kind: .snippet, tabTrigger: "for")
		let item2 = makeItem(uuid: "2", name: "Snippet2", kind: .snippet, tabTrigger: "while")
		index.setIndex(items: [item1, item2], bundles: [])

		let results = index.query(BundleQuery(
			field: .tabTrigger,
			value: "for",
			kinds: .snippet,
		))
		#expect(results.count == 1)
		#expect(results[0].name == "Snippet1")
	}

	@Test("Query by key equivalent")
	func queryByKeyEquivalent() {
		let index = BundleIndex()
		let item = makeItem(
			uuid: "1",
			name: "Run",
			kind: .command,
			keyEquivalent: "@r",
		)
		index.setIndex(items: [item], bundles: [])

		let results = index.query(BundleQuery(
			field: .keyEquivalent,
			value: "@r",
			kinds: .command,
		))
		#expect(results.count == 1)
		#expect(results[0].name == "Run")
	}

	@Test("Query excludes disabled items by default")
	func queryExcludesDisabled() {
		let index = BundleIndex()
		let item = makeItem(uuid: "1", name: "Hidden", isDisabled: true)
		index.setIndex(items: [item], bundles: [])

		let results = index.query(BundleQuery(kinds: .command))
		#expect(results.isEmpty)

		let withDisabled = index.query(BundleQuery(
			kinds: .command,
			includeDisabled: true,
		))
		#expect(withDisabled.count == 1)
	}

	@Test("Query by kind filter")
	func queryByKind() {
		let index = BundleIndex()
		let cmd = makeItem(uuid: "1", name: "Cmd", kind: .command)
		let snip = makeItem(uuid: "2", name: "Snip", kind: .snippet)
		let grammar = makeItem(uuid: "3", name: "Grammar", kind: .grammar)
		index.setIndex(items: [cmd, snip, grammar], bundles: [])

		let commands = index.query(BundleQuery(kinds: .command))
		#expect(commands.count == 1)

		let executable = index.query(BundleQuery(kinds: .executable))
		#expect(executable.count == 2) // command + snippet
	}

	@Test("Query by bundle UUID")
	func queryByBundle() {
		let index = BundleIndex()
		let item1 = makeItem(uuid: "1", name: "A", bundleUUID: "b1")
		let item2 = makeItem(uuid: "2", name: "B", bundleUUID: "b2")
		index.setIndex(items: [item1, item2], bundles: [])

		let results = index.query(BundleQuery(bundleUUID: "b1"))
		#expect(results.count == 1)
		#expect(results[0].name == "A")
	}

	@Test("Items in bundle")
	func itemsInBundle() {
		let index = BundleIndex()
		let item1 = makeItem(uuid: "1", name: "A", bundleUUID: "b1")
		let item2 = makeItem(uuid: "2", name: "B", bundleUUID: "b1")
		let item3 = makeItem(uuid: "3", name: "C", bundleUUID: "b2")
		index.setIndex(items: [item1, item2, item3], bundles: [])

		#expect(index.items(inBundle: "b1").count == 2)
		#expect(index.items(inBundle: "b2").count == 1)
	}

	@Test("Add items incrementally")
	func addItems() {
		let index = BundleIndex()
		let item1 = makeItem(uuid: "1", name: "A")
		index.setIndex(items: [item1], bundles: [])
		#expect(index.itemCount == 1)

		let item2 = makeItem(uuid: "2", name: "B")
		index.addItems([item2])
		#expect(index.itemCount == 2)
	}

	@Test("Remove item")
	func removeItem() {
		let index = BundleIndex()
		let item = makeItem(uuid: "1", name: "A", tabTrigger: "test")
		index.setIndex(items: [item], bundles: [])
		#expect(index.itemCount == 1)

		index.removeItem(uuid: "1")
		#expect(index.itemCount == 0)
		#expect(index.lookup(uuid: "1") == nil)
	}

	@Test("Change callback fires on setIndex")
	func changeCallback() {
		let index = BundleIndex()
		let fired = LockedBox(false)
		index.addChangeCallback { fired.withLock { $0 = true } }

		index.setIndex(items: [], bundles: [])
		#expect(fired.value)
	}

	@Test("Remove change callback")
	func removeChangeCallback() {
		let index = BundleIndex()
		let count = LockedBox(0)
		let id = index.addChangeCallback { count.withLock { $0 += 1 } }

		index.setIndex(items: [], bundles: [])
		#expect(count.value == 1)

		index.removeChangeCallback(id: id)
		index.setIndex(items: [], bundles: [])
		#expect(count.value == 1) // Not called again.
	}

	@Test("Bundle descriptor lookup")
	func bundleDescriptorLookup() {
		let index = BundleIndex()
		let bundle = BundleDescriptor(
			uuid: "b1",
			name: "TestBundle",
			category: "Programming",
		)
		index.setIndex(items: [], bundles: [bundle])

		#expect(index.bundle(uuid: "b1")?.name == "TestBundle")
		#expect(index.bundle(uuid: "b1")?.category == "Programming")
		#expect(index.bundle(uuid: "nonexistent") == nil)
	}
}

// MARK: - Bundle Command Parser Tests

@Suite("BundleCommandParser")
struct BundleCommandParserTests {
	let parser = BundleCommandParser()

	@Test("Parse minimal command plist")
	func parseMinimal() {
		let plist: [String: Any] = [
			"command": "echo hello",
			"name": "Hello",
			"uuid": "cmd-1",
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd != nil)
		#expect(cmd?.name == "Hello")
		#expect(cmd?.uuid == "cmd-1")
		#expect(cmd?.command == "echo hello")
	}

	@Test("Parse returns nil without command key")
	func parseWithoutCommand() {
		let plist: [String: Any] = ["name": "NoCommand"]
		#expect(parser.parse(plist: plist) == nil)
	}

	@Test("Parse pre-exec action")
	func parsePreExec() {
		let plist: [String: Any] = [
			"command": "test",
			"beforeRunningCommand": "saveActiveFile",
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.preExec == .saveDocument)
	}

	@Test("Parse input source")
	func parseInput() {
		let plist: [String: Any] = [
			"command": "test",
			"input": "document",
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.input == .entireDocument)
	}

	@Test("Parse output destination")
	func parseOutput() {
		let plist: [String: Any] = [
			"command": "test",
			"output": "showAsTooltip",
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.output == .toolTip)
	}

	@Test("Parse output format")
	func parseOutputFormat() {
		let plist: [String: Any] = [
			"command": "test",
			"outputFormat": "snippet",
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.outputFormat == .snippet)
	}

	@Test("Parse output caret")
	func parseOutputCaret() {
		let plist: [String: Any] = [
			"command": "test",
			"outputCaret": "heuristic",
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.outputCaret == .heuristic)
	}

	@Test("Parse output reuse")
	func parseOutputReuse() {
		let plist: [String: Any] = [
			"command": "test",
			"outputReuse": "abortAndReuseBusy",
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.outputReuse == .abortAndReuseBusy)
	}

	@Test("Parse auto-refresh from integer")
	func parseAutoRefreshInt() {
		let plist: [String: Any] = [
			"command": "test",
			"autoRefresh": 3, // onDocumentChange | onDocumentSave
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.autoRefresh.contains(.onDocumentChange) == true)
		#expect(cmd?.autoRefresh.contains(.onDocumentSave) == true)
		#expect(cmd?.autoRefresh.contains(.onDocumentClose) == false)
	}

	@Test("Parse auto-refresh from dictionary")
	func parseAutoRefreshDict() {
		let plist: [String: Any] = [
			"command": "test",
			"autoRefresh": [
				"onDocumentChange": true,
				"onDocumentClose": true,
			] as [String: Bool],
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.autoRefresh.contains(.onDocumentChange) == true)
		#expect(cmd?.autoRefresh.contains(.onDocumentClose) == true)
		#expect(cmd?.autoRefresh.contains(.onDocumentSave) == false)
	}

	@Test("Parse boolean flags")
	func parseBooleanFlags() {
		let plist: [String: Any] = [
			"command": "test",
			"autoScrollOutput": true,
			"disableOutputAutoIndent": true,
			"disableJavaScriptAPI": true,
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.autoScrollOutput == true)
		#expect(cmd?.disableOutputAutoIndent == true)
		#expect(cmd?.disableJavaScriptAPI == true)
	}

	@Test("Parse defaults for missing fields")
	func parseDefaults() throws {
		let plist: [String: Any] = ["command": "test"]
		let cmd = try #require(parser.parse(plist: plist))
		#expect(cmd.preExec == .nop)
		#expect(cmd.input == .selection)
		#expect(cmd.inputFallback == .entireDocument)
		#expect(cmd.inputFormat == .text)
		#expect(cmd.output == .replaceInput)
		#expect(cmd.outputFormat == .text)
		#expect(cmd.outputCaret == .afterOutput)
		#expect(cmd.outputReuse == .reuseAvailable)
		#expect(cmd.autoRefresh == .never)
		#expect(cmd.autoScrollOutput == false)
		#expect(cmd.disableOutputAutoIndent == false)
		#expect(cmd.disableJavaScriptAPI == false)
	}

	@Test("Parse from BundleItem")
	func parseFromBundleItem() {
		let item = BundleItem(
			uuid: "item-1",
			name: "Test Item",
			kind: .command,
			bundleUUID: "b1",
			plist: ["command": "echo test"],
		)
		let cmd = parser.parse(item: item)
		#expect(cmd?.name == "Test Item")
		#expect(cmd?.uuid == "item-1")
		#expect(cmd?.command == "echo test")
	}

	@Test("Name and UUID override from parameters")
	func nameUUIDOverride() {
		let plist: [String: Any] = [
			"command": "test",
			"name": "PlistName",
			"uuid": "plist-uuid",
		]
		let cmd = parser.parse(plist: plist, name: "Override", uuid: "override-uuid")
		#expect(cmd?.name == "Override")
		#expect(cmd?.uuid == "override-uuid")
	}

	@Test("Input fallback from legacy key")
	func inputFallbackLegacy() {
		let plist: [String: Any] = [
			"command": "test",
			"fallbackInput": "word",
		]
		let cmd = parser.parse(plist: plist)
		#expect(cmd?.inputFallback == .word)
	}
}

// MARK: - Bundle Command Tests

@Suite("BundleCommand")
struct BundleCommandTests {
	@Test("Fix shebang prepends bash header")
	func fixShebang() {
		var cmd = BundleCommand(name: "Test", uuid: "1", command: "echo hello")
		cmd.fixShebang()
		#expect(cmd.command.hasPrefix("#!/bin/bash\n"))
		#expect(cmd.command.contains("echo hello"))
	}

	@Test("Fix shebang with support path")
	func fixShebangWithSupport() {
		var cmd = BundleCommand(name: "Test", uuid: "1", command: "echo hello")
		cmd.fixShebang(supportPath: "/path/to/support")
		#expect(cmd.command.contains("bash_init.sh"))
		#expect(cmd.command.contains("/path/to/support"))
	}

	@Test("Fix shebang does nothing when shebang exists")
	func fixShebangNoop() {
		var cmd = BundleCommand(
			name: "Test",
			uuid: "1",
			command: "#!/usr/bin/env ruby\nputs 'hi'",
		)
		cmd.fixShebang()
		#expect(cmd.command == "#!/usr/bin/env ruby\nputs 'hi'")
	}
}

// MARK: - Bundle Loader Tests

@Suite("BundleLoader")
struct BundleLoaderTests {
	let loader = BundleLoader()

	@Test("Load from non-existent path returns empty")
	func loadNonexistent() {
		let result = loader.loadFromPaths(["/nonexistent/path"])
		#expect(result.items.isEmpty)
		#expect(result.bundles.isEmpty)
	}

	@Test("Load bundle requires info.plist with uuid and name")
	func loadBundleRequires() {
		let result = loader.loadBundle(at: "/nonexistent/test.tmbundle")
		#expect(result == nil)
	}

	@Test("Parse menu structure with separators")
	func parseMenuSeparators() {
		let mainMenu: [String: Any] = [
			"items": ["uuid-1", "----", "uuid-2"],
		]
		let items = loader.parseMenuStructure(mainMenu, allItems: nil)
		#expect(items.count == 3)
		if case let .item(uuid) = items[0] {
			#expect(uuid == "uuid-1")
		} else {
			Issue.record("Expected .item")
		}
		if case .separator = items[1] {
			// OK
		} else {
			Issue.record("Expected .separator")
		}
	}

	@Test("Parse menu structure with submenus")
	func parseMenuSubmenus() {
		let mainMenu: [String: Any] = [
			"items": ["submenu-1"] as [String],
			"submenus": [
				"submenu-1": [
					"name": "Sub",
					"items": ["child-1", "child-2"],
				] as [String: Any],
			] as [String: Any],
		]
		let items = loader.parseMenuStructure(mainMenu, allItems: nil)
		#expect(items.count == 1)
		if case let .submenu(title, children) = items[0] {
			#expect(title == "Sub")
			#expect(children.count == 2)
		} else {
			Issue.record("Expected .submenu")
		}
	}

	@Test("Parse empty menu structure")
	func parseEmptyMenu() {
		let items = loader.parseMenuStructure(nil, allItems: nil)
		#expect(items.isEmpty)
	}

	@Test("Plist extensions recognized")
	func plistExtensions() {
		#expect(BundleLoader.plistExtensions.contains("tmCommand"))
		#expect(BundleLoader.plistExtensions.contains("tmSnippet"))
		#expect(BundleLoader.plistExtensions.contains("tmLanguage"))
		#expect(BundleLoader.plistExtensions.contains("tmTheme"))
	}
}

// MARK: - Auto-Refresh Scheduler Tests

@Suite("AutoRefreshScheduler")
@MainActor
struct AutoRefreshSchedulerTests {
	@Test("Register and unregister commands")
	func registerUnregister() {
		let index = BundleIndex()
		let policy = SecurityPolicy()
		let dispatcher = CommandDispatcher(bundleIndex: index, securityPolicy: policy)
		let scheduler = AutoRefreshScheduler(dispatcher: dispatcher)

		let cmd = BundleCommand(
			name: "Test",
			uuid: "cmd-1",
			command: "echo",
			autoRefresh: .onDocumentSave,
		)
		scheduler.register(command: cmd)
		#expect(scheduler.registeredCount == 1)

		scheduler.unregister(commandUUID: "cmd-1")
		#expect(scheduler.registeredCount == 0)
	}

	@Test("Will not register commands without triggers")
	func noTriggersNotRegistered() {
		let index = BundleIndex()
		let policy = SecurityPolicy()
		let dispatcher = CommandDispatcher(bundleIndex: index, securityPolicy: policy)
		let scheduler = AutoRefreshScheduler(dispatcher: dispatcher)

		let cmd = BundleCommand(
			name: "Test",
			uuid: "cmd-1",
			command: "echo",
			autoRefresh: .never,
		)
		scheduler.register(command: cmd)
		#expect(scheduler.registeredCount == 0)
	}

	@Test("Unregister all clears everything")
	func unregisterAll() {
		let index = BundleIndex()
		let policy = SecurityPolicy()
		let dispatcher = CommandDispatcher(bundleIndex: index, securityPolicy: policy)
		let scheduler = AutoRefreshScheduler(dispatcher: dispatcher)

		scheduler.register(command: BundleCommand(
			name: "A",
			uuid: "1",
			command: "echo",
			autoRefresh: .onDocumentChange,
		))
		scheduler.register(command: BundleCommand(
			name: "B",
			uuid: "2",
			command: "echo",
			autoRefresh: .onDocumentSave,
		))
		#expect(scheduler.registeredCount == 2)

		scheduler.unregisterAll()
		#expect(scheduler.registeredCount == 0)
	}

	@Test("Registered command UUIDs")
	func registeredUUIDs() {
		let index = BundleIndex()
		let policy = SecurityPolicy()
		let dispatcher = CommandDispatcher(bundleIndex: index, securityPolicy: policy)
		let scheduler = AutoRefreshScheduler(dispatcher: dispatcher)

		scheduler.register(command: BundleCommand(
			name: "A",
			uuid: "cmd-a",
			command: "echo",
			autoRefresh: .onDocumentChange,
		))
		#expect(scheduler.registeredCommandUUIDs.contains("cmd-a"))
	}
}

// MARK: - Command Dispatcher Tests

@Suite("CommandDispatcher")
@MainActor
struct CommandDispatcherTests {
	@Test("Initial state is idle")
	func initialState() {
		let index = BundleIndex()
		let policy = SecurityPolicy()
		let dispatcher = CommandDispatcher(bundleIndex: index, securityPolicy: policy)
		#expect(dispatcher.state == .idle)
	}

	@Test("Execute by UUID with missing item does nothing")
	func executeMissingItem() async {
		let index = BundleIndex()
		let policy = SecurityPolicy()
		let dispatcher = CommandDispatcher(bundleIndex: index, securityPolicy: policy)
		await dispatcher.execute(itemUUID: "nonexistent")
		#expect(dispatcher.state == .idle)
	}

	@Test("Execute without delegate stays idle")
	func executeNoDelegate() async {
		let index = BundleIndex()
		let policy = SecurityPolicy()
		let dispatcher = CommandDispatcher(bundleIndex: index, securityPolicy: policy)
		let cmd = BundleCommand(name: "Test", uuid: "1", command: "echo hi")
		await dispatcher.execute(command: cmd)
		#expect(dispatcher.state == .idle)
	}
}

// MARK: - Drag Command Handler Tests

@Suite("DragCommandHandler")
@MainActor
struct DragCommandHandlerTests {
	@Test("Find commands with no drag commands in index")
	func findNoDragCommands() {
		let index = BundleIndex()
		let handler = DragCommandHandler(bundleIndex: index)
		let results = handler.findCommands(
			forFileExtensions: ["png"],
			scope: "text.plain",
		)
		#expect(results.isEmpty)
	}

	@Test("Build drag environment variables")
	func dragEnvironment() {
		let index = BundleIndex()
		let handler = DragCommandHandler(bundleIndex: index)
		let env = handler.dragEnvironment(droppedFiles: [
			"/path/to/image.png",
			"/path/to/other.jpg",
		])
		#expect(env["TM_DROPPED_FILE"] == "/path/to/image.png")
		#expect(env["TM_DROPPED_FILEPATH"] == "/path/to/image.png")
		#expect(env["TM_DROPPED_FILEPATHS"]?.contains("\n") == true)
	}

	@Test("Build bundle command from drag command")
	func buildBundleCommand() {
		let index = BundleIndex()
		let handler = DragCommandHandler(bundleIndex: index)
		let drag = DragCommand(
			uuid: "drag-1",
			name: "Insert Image",
			command: "echo $TM_DROPPED_FILE",
		)
		let cmd = handler.buildBundleCommand(from: drag, droppedFiles: ["/img.png"])
		#expect(cmd.name == "Insert Image")
		#expect(cmd.input == .nothing)
		#expect(cmd.output == .atCaret)
		#expect(cmd.outputFormat == .snippet)
	}
}

// MARK: - Bundle Item Kind Tests

@Suite("BundleItemKind")
struct BundleItemKindTests {
	@Test("Executable includes command, dragCommand, snippet, macro")
	func executable() {
		#expect(BundleItemKind.executable.contains(.command))
		#expect(BundleItemKind.executable.contains(.dragCommand))
		#expect(BundleItemKind.executable.contains(.snippet))
		#expect(BundleItemKind.executable.contains(.macro))
		#expect(!BundleItemKind.executable.contains(.grammar))
		#expect(!BundleItemKind.executable.contains(.theme))
	}

	@Test("Kind intersection works for filtering")
	func kindIntersection() {
		let filter: BundleItemKind = [.command, .snippet]
		#expect(BundleItemKind.command.intersection(filter) != [])
		#expect(BundleItemKind.snippet.intersection(filter) != [])
		#expect(BundleItemKind.grammar.intersection(filter) == [])
	}
}

// MARK: - Bundle Descriptor Tests

@Suite("BundleDescriptor")
struct BundleDescriptorTests {
	@Test("Descriptor equality")
	func equality() {
		let a = BundleDescriptor(uuid: "1", name: "A")
		let b = BundleDescriptor(uuid: "1", name: "A")
		let c = BundleDescriptor(uuid: "2", name: "A")
		let d = BundleDescriptor(uuid: "1", name: "B")
		#expect(a == b)
		#expect(a != c)
		#expect(a != d) // Same UUID, different name
	}

	@Test("Descriptor ID is UUID")
	func id() {
		let d = BundleDescriptor(uuid: "test-uuid", name: "Test")
		#expect(d.id == "test-uuid")
	}
}

// MARK: - Command Result Tests

@Suite("CommandResult")
struct CommandResultTests {
	@Test("stdout and stderr string decoding")
	func stringDecoding() {
		let result = CommandResult(
			exitCode: 0,
			stdout: Data("hello".utf8),
			stderr: Data("error".utf8),
			commandName: "test",
		)
		#expect(result.stdoutString == "hello")
		#expect(result.stderrString == "error")
	}

	@Test("Empty data produces empty strings")
	func emptyData() {
		let result = CommandResult(
			exitCode: 0,
			stdout: Data(),
			stderr: Data(),
			commandName: "test",
		)
		#expect(result.stdoutString == "")
		#expect(result.stderrString == "")
	}
}

// MARK: - Bundle Installer Tests

@Suite("BundleInstaller")
@MainActor
struct BundleInstallerTests {
	@Test("Initial catalog is empty")
	func initialCatalog() {
		let installer = BundleInstaller(
			installDirectory: NSTemporaryDirectory() + "test-bundles",
		)
		#expect(installer.catalog.isEmpty)
	}

	@Test("Catalog entry equality")
	func catalogEntryEquality() {
		let a = BundleInstaller.CatalogEntry(uuid: "1", name: "A")
		let b = BundleInstaller.CatalogEntry(uuid: "1", name: "A")
		let c = BundleInstaller.CatalogEntry(uuid: "2", name: "A")
		#expect(a == b)
		#expect(a != c)
	}

	@Test("Resolve dependencies returns input UUIDs")
	func resolveDependencies() {
		let installer = BundleInstaller()
		let resolved = installer.resolveDependencies(for: ["a", "b", "c"])
		#expect(resolved == ["a", "b", "c"])
	}

	@Test("Resolve dependencies deduplicates")
	func resolveDependenciesDedup() {
		let installer = BundleInstaller()
		let resolved = installer.resolveDependencies(for: ["a", "b", "a"])
		#expect(resolved == ["a", "b"])
	}

	@Test("Uninstall non-installed bundle throws")
	func uninstallNotInstalled() {
		let installer = BundleInstaller()
		#expect(throws: InstallerError.self) {
			try installer.uninstall(bundleUUID: "nonexistent")
		}
	}
}
