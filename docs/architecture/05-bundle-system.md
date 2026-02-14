# 05 — Bundle & Plugin System

## Loading Existing Bundles

The `TMBundle` package loads bundles from these paths (priority order, matching
current TextMate):

1. `~/Library/Application Support/TextMate/Bundles` (user bundles)
2. `~/Library/Application Support/TextMate/Pristine Copy/Bundles` (managed)
3. `/Library/Application Support/TextMate/Bundles` (system-wide)
4. `TextMate.app/Contents/Resources/Bundles` (shipped)

Bundle item types:

| Item Type | File Extension | Handler |
|---|---|---|
| Grammar | `.tmLanguage`, `.plist` | `TMGrammar` parser |
| Theme | `.tmTheme`, `.plist` | `TMTheme` loader |
| Snippet | `.tmSnippet`, `.plist` | `TMEditor` snippet engine |
| Command | `.tmCommand`, `.plist` | `TMBundleRuntime` executor |
| Macro | `.tmMacro`, `.plist` | `TMEditor` macro player |
| Preference | `.tmPreferences`, `.plist` | `TMSettings` merger |
| Drag Command | `.tmDragCommand`, `.plist` | `TMBundleRuntime` executor |

## Secure Command Execution

Bundle commands execute in a sandboxed XPC service:

```
TMCommandRunner.xpc
├── Receives: command string, environment, input data, working directory
├── Executes: /bin/sh -c "<command>" (or specified interpreter)
├── Captures: stdout, stderr, exit code
├── Returns: output data, exit code
└── Enforces: timeout, memory limit
```

**Security measures:**

1. **XPC isolation:** Commands run in a separate process with own sandbox
2. **Environment sanitization:** Only approved TM_* variables and configured PATH
3. **Timeout:** Commands exceeding 60s (configurable) are terminated
4. **Output size limit:** Output exceeding 50 MB is truncated
5. **No interactive shell:** Commands cannot read from user's TTY
6. **Audit logging:** Executions logged for debugging

## Environment Variables

All `TM_*` variables are provided, matching current TextMate:

| Variable | Description |
|---|---|
| `TM_BUNDLE_SUPPORT` | Path to bundle's Support directory |
| `TM_CURRENT_LINE` | Content of current line |
| `TM_CURRENT_WORD` | Word under caret |
| `TM_DIRECTORY` | Directory of current document |
| `TM_DOCUMENT_UUID` | UUID of current document |
| `TM_FILEPATH` | Full path of current document |
| `TM_FILENAME` | Filename of current document |
| `TM_LINE_INDEX` | Caret's column position (0-based) |
| `TM_LINE_NUMBER` | Caret's line number (1-based) |
| `TM_PROJECT_DIRECTORY` | Root directory of the project |
| `TM_SCOPE` | Scope at caret position |
| `TM_SELECTED_TEXT` | Currently selected text |
| `TM_SOFT_TABS` | "YES" if soft tabs enabled |
| `TM_SUPPORT_PATH` | Path to global Support bundle |
| `TM_TAB_SIZE` | Current tab size |

User-defined variables from `.tm_properties` and Preferences → Variables are
included.

## Security Model

```
Trust Levels:
├── Shipped bundles        → Trusted (no prompt)
├── Managed bundles        → Trusted (installed via bundle manager)
├── User bundles           → Trusted (user explicitly installed)
├── Downloaded bundles     → Untrusted until approved
│   └── First command triggers permission dialog:
│       "Bundle 'X' wants to run a shell command. Allow?"
│       [Allow Once] [Always Allow] [Deny]
└── MCP servers            → Always require explicit per-server approval
```

## Future Swift Extension API

A forward-looking Swift extension API planned for post-1.0:

```swift
public protocol TMExtension {
    static var identifier: String { get }
    static var displayName: String { get }
    func activate(context: TMExtensionContext) async
    func deactivate() async
}

public protocol TMExtensionContext {
    var activeDocument: TMDocumentProxy? { get }
    var workspace: TMWorkspaceProxy { get }
    func registerCommand(_ command: TMExtensionCommand) async
    func registerCompletionProvider(_ provider: TMCompletionProvider) async
    func registerDiagnosticsProvider(_ provider: TMDiagnosticsProvider) async
}

public protocol TMDocumentProxy {
    var text: String { get async }
    var selections: [TMSelection] { get async }
    var grammar: String? { get async }
    func edit(_ edits: [TMTextEdit]) async throws
    func setSelections(_ selections: [TMSelection]) async
}
```

Swift extensions compile as Swift packages, loaded via XPC for crash isolation.

## Migration Path

No migration is required for existing `.tmbundle` bundles. For bundle authors
wanting Swift extensions:

1. **Phase 1:** Continue using `.tmbundle` with shell commands — fully supported
2. **Phase 2 (post-1.0):** Add `Package.swift` for Swift-native extensions
3. **Phase 3:** Swift extensions coexist with bundle items in the same `.tmbundle`

The traditional bundle format is **not deprecated**. It remains first-class.

## Ecosystem Evaluation

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| **Keep .tmbundle** | Zero migration; massive library | Shell-based; limited API | ✅ Keep |
| **Add Swift extension API** | Type-safe; performant | New tooling needed | ✅ Add (post-1.0) |
| **Lua/Python scripting** | Richer than shell | Adds runtime dependency | ❌ Rejected |
| **WebAssembly** | Sandboxed; portable | Adds Wasm runtime | ❌ Rejected |
| **JavaScript/Node** | Large ecosystem | Explicitly forbidden | ❌ Rejected |
