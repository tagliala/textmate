# 01 — System Architecture

## High-Level Layer Diagram

The application is structured as four layers with strict dependency rules (upper
layers depend on lower layers, never the reverse):

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                     │
│  TextMate.app · mate CLI · QuickLook · SyntaxMate       │
├─────────────────────────────────────────────────────────┤
│                    Presentation Layer                    │
│  DocumentWindow · EditorView · FileBrowser · Preferences │
│  FindPanel · BundleEditor · StatusBar · GutterView       │
├─────────────────────────────────────────────────────────┤
│                    Service Layer                         │
│  MCPService · BundleRuntime · CommandRunner              │
│  SettingsService · SCMService · SearchService            │
├─────────────────────────────────────────────────────────┤
│                    Core Layer                            │
│  TextBuffer · Editor · Selection · Undo                  │
│  Grammar · Scope · Theme · Encoding · Snippet            │
│  BundleIndex · PlistParser · RegExp · FileReference      │
└─────────────────────────────────────────────────────────┘
```

## Modularization Strategy

The current 35+ Objective-C++ frameworks are consolidated into Swift packages
grouped by domain:

| Swift Package | Current Frameworks Replaced | Role |
|---|---|---|
| `TMCore` | buffer, text, selection, undo | Text storage, positions, ranges, undo |
| `TMEditor` | editor | Editor operations, actions, dispatch |
| `TMGrammar` | parse, scope | TextMate grammar parsing, scope trees |
| `TMTheme` | theme | Theme loading, style resolution |
| `TMBundle` | bundles, command | Bundle index, loading, command model |
| `TMSettings` | settings | `.tm_properties` parsing, scope-aware settings |
| `TMDocument` | document | Document model, file I/O, encoding |
| `TMRegExp` | regexp + vendored Onigmo | Regular expression engine (Onigmo via C interop) |
| `TMMCP` | *(new)* | MCP client/server, protocol handling |
| `TMBundleRuntime` | OakCommand | Secure command execution, sandboxing |
| `TMSCM` | scm | Git integration |
| `TMSearch` | Find | Project-wide and in-document search |
| `TMEditorUI` | OakTextView, layout | Text rendering, gutter, status bar |
| `TMAppKit` | OakAppKit, OakFilterList, OakTabBarView | Shared UI components |
| `TMFileBrowser` | FileBrowser, TMFileReference | Sidebar file browser |
| `TMDocumentWindow` | DocumentWindow | Window management, tabs |
| `TMPreferences` | Preferences | Preference panes |
| `TMBundleUI` | BundleEditor, BundleMenu, BundlesManager | Bundle management UI |
| `TMApp` | Applications/TextMate | App lifecycle, menus, top-level controllers |

Each package is a Swift Package Manager target with explicit dependency
declarations, enabling independent compilation and testing.

## Core Abstractions

### Document Model

```
TMDocument
├── TextBuffer          — Piece-table-based character storage
├── GrammarState        — Incremental parse state per line
├── ScopeMap            — Indexed map of scope assignments
├── MarkSet             — Bookmarks, breakpoints, diagnostics
├── SpellingState       — Live spell-check annotations
├── SymbolIndex         — Extracted symbol list
├── UndoManager         — Undo/redo with coalescing
├── SelectionState      — Active selections (multi-cursor)
└── Metadata
    ├── encoding, newline style, BOM
    ├── file path, disk revision
    └── grammar assignment
```

### Text Storage: Piece Table

The `TextBuffer` replaces the current `oak::basic_tree_t`-backed
`ng::detail::storage_t` with a **piece table** — an append-only data structure
that is:

- More memory efficient for large files (no chunk copying)
- Naturally undo-friendly (operations are non-destructive)
- Well-suited for Swift value semantics via copy-on-write

**Trade-off:** The piece table sacrifices some random-access read performance
compared to a gap buffer, but gains superior insert/delete performance and
simpler undo semantics. For a text editor where insertions and deletions are the
dominant operations, this is the correct trade-off.

### Selection Model

The selection model (already implemented in `Sources/TMCore/`) supports:

- Multiple carets and selections (`[TextRange]` array)
- Columnar (rectangular) selections
- Each `TextRange` has an anchor and head `TextPosition`
- Overlapping selections are merged automatically via `SelectionState`

Editor operations are expressed as pure functions:

```swift
func perform(
    _ action: EditorAction,
    on buffer: TextBuffer,
    with selections: SelectionState
) -> (TextBuffer, SelectionState)
```

This design simplifies testing: every editor operation is testable without UI.

## Backward Compatibility Layer

A `LegacySupport` module provides:

1. **Plist parsing** for `.tmBundle`, `.tmLanguage`, `.tmTheme`, `.tmSnippet`,
   `.tmPreferences`, `.tmCommand` files
2. **Environment variable mapping** preserving all `TM_*` variables
3. **Command output format handling** for legacy output modes
4. **Settings migration** from `~/Library/Application Support/TextMate`
5. **Grammar compatibility** ensuring existing grammars parse identically
