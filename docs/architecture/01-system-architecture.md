# 01 — System Architecture

## Iteration Strategy

The migration follows a **UI-first, engine-later** approach. Rather than building
the full editor engine bottom-up (core → editor → grammar → UI), we begin with a
working application shell that visually matches the current TextMate, then
progressively replace the internals.

### Iteration 1: Visual Shell (Target: launchable app that looks like TextMate)

The first deliverable is a Swift/AppKit application that reproduces TextMate's
visual appearance and basic interaction model:

- **Document window** with the correct layout and proportions
- **Tab bar** matching current behavior (draggable, closeable, overflow)
- **File browser sidebar** with directory tree, icons, disclosure triangles
- **Editor area** using `NSTextView` as a temporary text backend
- **Gutter** with line numbers and fold markers (visual only initially)
- **Status bar** showing line/column, grammar name, tab settings, encoding
- **Theme loading** from `.tmTheme` plist files to match appearance
- **Main menu structure** with all menus and keyboard shortcuts preserved
- **Keyboard shortcuts** loaded from `KeyBindings.dict` — identical to current
  TextMate (see [03 — Compatibility](03-compatibility.md#keyboard-shortcuts))
- **File open/save** with encoding detection
- **Window restoration** (reopen last session)

This iteration deliberately uses `NSTextView` for the editor area. Multi-cursor,
columnar selection, and custom rendering are **not** in scope — they come later
when the custom engine replaces `NSTextView`. The goal is a pixel-comparable
application shell with correct keyboard shortcuts, theming, and window layout.

### Iteration 2: Core Engine

Replace `NSTextView` with the custom `TextBuffer` + CoreText rendering engine.
Add `SelectionState`, undo, and basic editing actions.

### Iteration 3: Language & Bundles

Add grammar parsing (`TMGrammar`), scope-driven syntax highlighting, snippet
engine, bundle loading, and command execution.

### Iteration 4: Full Feature Parity

Find & Replace, project search, SCM integration, preferences UI, bundle manager,
dialog compatibility, `mate` CLI.

### Iteration 5: MCP & Extensions

MCP integration, Swift extension API, performance hardening, beta migration.

> **Note:** The detailed phased plan with timelines is in
> [07 — Execution Plan](07-execution-plan.md). The iteration strategy above
> defines the priority order — visual fidelity and keyboard shortcuts first,
> engine internals second.

---

## High-Level Layer Diagram

The full application is structured as four layers with strict dependency rules
(upper layers depend on lower layers, never the reverse):

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
│  BundleRuntime · CommandRunner · SettingsService         │
│  SCMService · SearchService · MCPService (Iteration 5)  │
├─────────────────────────────────────────────────────────┤
│                    Core Layer                            │
│  TextBuffer · Editor · Selection · Undo                  │
│  Grammar · Scope · Theme · Encoding · Snippet            │
│  BundleIndex · PlistParser · RegExp · FileReference      │
└─────────────────────────────────────────────────────────┘
```

## Modularization Strategy

The current 35+ Objective-C++ frameworks are consolidated into Swift packages
grouped by domain. Packages are listed with their **iteration target** to
indicate build order:

| Swift Package | Current Frameworks Replaced | Role | Iteration |
|---|---|---|---|
| `TMTheme` | theme | Theme loading, style resolution | 1 |
| `TMAppKit` | OakAppKit, OakFilterList, OakTabBarView | Shared UI components (tab bar, filter list) | 1 |
| `TMFileBrowser` | FileBrowser, TMFileReference | Sidebar file browser | 1 |
| `TMDocumentWindow` | DocumentWindow | Window management, tabs | 1 |
| `TMApp` | Applications/TextMate | App lifecycle, menus, top-level controllers | 1 |
| `TMCore` | buffer, text, selection, undo | Text storage, positions, ranges, undo | 2 |
| `TMEditorUI` | OakTextView, layout | Text rendering, gutter, status bar | 2 |
| `TMEditor` | editor | Editor operations, actions, dispatch | 2 |
| `TMDocument` | document | Document model, file I/O, encoding | 2 |
| `TMRegExp` | regexp + vendored Onigmo | Regular expression engine (Onigmo via C interop) | 3 |
| `TMGrammar` | parse, scope | TextMate grammar parsing, scope trees | 3 |
| `TMBundle` | bundles, command | Bundle index, loading, command model | 3 |
| `TMSettings` | settings | `.tm_properties` parsing, scope-aware settings | 3 |
| `TMBundleRuntime` | OakCommand | Secure command execution, sandboxing | 3 |
| `TMSearch` | Find | Project-wide and in-document search | 4 |
| `TMSCM` | scm | Git integration | 4 |
| `TMPreferences` | Preferences | Preference panes | 4 |
| `TMBundleUI` | BundleEditor, BundleMenu, BundlesManager | Bundle management UI | 4 |
| `TMMCP` | *(new)* | MCP client/server, protocol handling | 5 |

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
