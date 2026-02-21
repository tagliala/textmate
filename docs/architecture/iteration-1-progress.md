# TextMate Swift Rewrite — Session Progress

> Last updated: 2025-08-01

---

## Iteration 1: Visual Shell — ✅ COMPLETE

### Packages & Source Files

| Package | File | Status |
|---------|------|--------|
| **TMCore** | `TextPosition.swift`, `TextRange.swift`, `SelectionState.swift` | ✅ |
| **TMTheme** | `ThemeColor.swift`, `ThemeStyleRule.swift` | ✅ |
| **TMTheme** | `Theme.swift` — global/gutter settings, `isDark`, `effectiveAppearance` | ✅ |
| **TMTheme** | `ThemeLoader.swift` — `.tmTheme` plist parser | ✅ |
| **TMAppKit** | `TabBarView.swift` — tab buttons, selection, close, drag-to-reorder, overflow menu | ✅ |
| **TMAppKit** | `StatusBarView.swift` — line/col, grammar, encoding labels, clickable popups | ✅ |
| **TMAppKit** | `GutterView.swift` — line numbers, fold markers, bookmarks, click-to-toggle | ✅ |
| **TMAppKit** | `FileBrowserView.swift` — `NSOutlineView` file tree, `.gitignore` filter, context menu | ✅ |
| **TMDocumentWindow** | `DocumentWindowController.swift` — layout, save/open, theme | ✅ |
| **TMDocumentWindow** | `DocumentModel.swift` — file I/O, encoding detection, BOM | ✅ |
| **TMApp** | `KeyBindingsLoader.swift` — plist loader + event parsing | ✅ |
| **TMApp** | `MainMenuBuilder.swift` — all 10 menus with shortcuts | ✅ |
| **TMApp** | `AppDelegate.swift` — lifecycle, theme load, key bindings, window state | ✅ |
| **TMApp** | `main.swift` — entry point with `setActivationPolicy(.regular)` | ✅ |
| **TMApp** | `AboutPanelController.swift` — About panel with version, credits, license | ✅ |
| **TMApp** | `PreferencesWindowController.swift` — Preferences stub with 6 tabs | ✅ |
| **TMApp** | `Info.plist` — bundle metadata, file type associations | ✅ |
| **TMApp** | `Resources/Mac Classic.tmTheme` — bundled default theme | ✅ |
| **TMApp** | `Resources/KeyBindings.dict` — bundled key bindings | ✅ |
| **CI** | `.github/workflows/swift.yml` — lint → build → test pipeline | ✅ |

### Tests (42/42 pass)

| Suite | Tests | Status |
|-------|-------|--------|
| TMCoreTests (TextPosition, TextRange, SelectionState) | 18 | ✅ |
| TMThemeTests (ThemeColor, ThemeLoader) | 15 | ✅ |
| TMDocumentWindowTests (DocumentModel) | 9 | ✅ |

### All Iteration 1 Items — ✅

1. ~~Load a real `.tmTheme` on launch~~ ✅
2. ~~File open/save with encoding detection~~ ✅
3. ~~Window state restoration~~ ✅
4. ~~Tab bar drag reordering~~ ✅
5. ~~Wire `KeyBindingsLoader` into responder chain~~ ✅
6. ~~CI pipeline~~ ✅
7. ~~File browser improvements (.gitignore, context menu, lazy loading)~~ ✅
8. ~~Tab overflow menu (» button)~~ ✅
9. ~~Status bar interactivity (clickable grammar/tab/encoding)~~ ✅
10. ~~Gutter improvements (fold markers, bookmarks, click-to-toggle)~~ ✅
11. ~~Info.plist & app icon~~ ✅
12. ~~About panel~~ ✅
13. ~~Preferences window stub~~ ✅

---

## Iteration 2: Foundation Layer — ✅ COMPLETE

Per [07-execution-plan.md](07-execution-plan.md), Phase 2 targets:

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMCore** | `TextBuffer.swift` — piece table with line index | ✅ |
| **TMCore** | `TextUndoManager.swift` — undo/redo with coalescing | ✅ |
| **TMBundle** | `BundlePlistParser.swift` — plist parser for `.tmLanguage`, `.tmSnippet`, `.tmCommand`, `.tmPreferences` | ✅ |
| **TMBundle** | `GrammarDefinition.swift` — `.tmLanguage` data model | ✅ |
| **TMBundle** | `SnippetDefinition.swift` — `.tmSnippet` data model | ✅ |
| **TMBundle** | `CommandDefinition.swift` — `.tmCommand` data model | ✅ |
| **TMBundle** | `PreferenceDefinition.swift` — `.tmPreferences` data model | ✅ |
| **TMSettings** | `TMPropertiesParser.swift` — `.tm_properties` INI parser | ✅ |
| **TMSettings** | `SettingsResolver.swift` — cascading settings resolution | ✅ |

### Tests (144/144 pass — 17 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| TMCoreTests (TextBuffer) | 30+ | ✅ |
| TMCoreTests (TextUndoManager) | 15+ | ✅ |
| TMCoreTests (TextBufferBenchmarks) | 8 | ✅ |
| TMBundleTests | 20+ | ✅ |
| TMSettingsTests | 20+ | ✅ |

---

## Iteration 3: Core Editor Engine — ✅ COMPLETE

Per [07-execution-plan.md](07-execution-plan.md), Phase 3 targets:

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMEditor** | `EditorAction.swift` — 130+ action enum with Cocoa selector mapping, classification | ✅ |
| **TMEditor** | `Editor.swift` — editor engine: action dispatch, movement (30 units), selection extension (35 units), deletion with implicit extension, multi-cursor, auto-indent, transpose, marks | ✅ |
| **TMEditor** | `Clipboard.swift` — ClipboardEntry, SimpleClipboard (history stack), ClipboardSet (general/find/replace/yank) | ✅ |
| **TMEditor** | `TextTransform.swift` — uppercase, lowercase, capitalize, toggleCase, unwrap, shiftLeft/Right, reformat/justify | ✅ |
| **TMEditor** | `SnippetController.swift` — tab stop navigation, session stack, edit adjustment | ✅ |
| **TMEditor** | `MacroRecorder.swift` — start/stop/toggle recording, replay with handler | ✅ |

### Tests (227/227 pass — 25 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| EditorAction | 11 | ✅ |
| Clipboard | 5 | ✅ |
| TextTransform | 10 | ✅ |
| SnippetController | 4 | ✅ |
| MacroRecorder | 7 | ✅ |
| Editor | 35 | ✅ |
| Editor Undo/Redo | 3 | ✅ |
| Editor Multi-Cursor | 1 | ✅ |

### Key Features Implemented

- **130+ editor actions** matching C++ `action_t` enum, with Cocoa selector mapping
- **30 movement units** (char, word, sub-word, soft/hard line, paragraph, document, page, column, typing pair, freehanded)
- **35 selection extension units** (directional + whole-unit: word, line, paragraph, all)
- **Multi-cursor editing** — insert, delete, transform at all cursors simultaneously
- **Clipboard system** — 4 clipboards (general, find, replace, yank) with history navigation, columnar paste, multi-fragment paste
- **Text transforms** — case, unwrap, shift indent, reformat with word wrap + justify
- **Transpose** — characters and words
- **Auto-indent** — copies leading whitespace on newline
- **Snippet navigation** — tab stop forward/backward, session stack
- **Macro recording** — record action sequences, replay with handler
- **Marks** — set, delete-to, select-to, swap-with
- **Move selection** — swap lines up/down, shift left/right

---

## Iteration 4: Syntax & Language System — ✅ COMPLETE

Per [07-execution-plan.md](07-execution-plan.md), Phase 4 targets:

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMGrammar** | `Scope.swift` — linked-list scope representation, pushScope/popScope, hasPrefix | ✅ |
| **TMGrammar** | `ScopeSelector.swift` — recursive-descent parser, path/group/filter/expression matching, scoring | ✅ |
| **TMGrammar** | `OnigmoRegex.swift` — NSRegularExpression wrapper with Oniguruma pattern translation (see [ADR-005](adr-005-native-regex.md)) | ✅ |
| **TMGrammar** | `GrammarRule.swift` — grammar rule tree, GrammarCompiler, include resolution | ✅ |
| **TMGrammar** | `GrammarParser.swift` — line-by-line parser, scope tracking, injection support | ✅ |
| **TMGrammar** | `IncrementalParser.swift` — incremental/async parsing with convergence detection | ✅ |
| **TMGrammar** | `GrammarRegistry.swift` — grammar loading, caching, external include resolution | ✅ |
| **TMGrammar** | `ParserState.swift` — parser state for cross-line continuity | ✅ |

### Architecture Decision: Native Regex (ADR-005)

Dropped vendored Onigmo C library in favor of Swift-native `NSRegularExpression`
with a translation layer for Oniguruma-specific patterns (`\h`, `\H`, `\v`, `\R`, `\X`).
See [adr-005-native-regex.md](adr-005-native-regex.md) for full rationale.

### Tests (105 tests, 12 suites — 6 pending for Onigmo-only features)

| Suite | Tests | Status |
|-------|-------|--------|
| Scope | 10 | ✅ |
| ScopeContext | 2 | ✅ |
| ScopeSelector | 16 | ✅ |
| OnigmoPattern | 14 (+6 pending) | ✅ |
| PatternTranslation | 8 | ✅ |
| PatternUtilities | 8 | ✅ |
| GrammarRule | 2 | ✅ |
| GrammarCompiler | 7 | ✅ |
| ParserState | 4 | ✅ |
| GrammarParser | 6 | ✅ |
| GrammarRegistry | 6 | ✅ |
| IncrementalParser | 6 | ✅ |

Pending tests (`.disabled`) for Onigmo-only features per ADR-005:
`\G` anchor, absent operator `(?~...)`, conditional backrefs,
Oniguruma Unicode property names, subexpression calls `\g<name>`, `\K` keep operator.

---

## Iteration 5: Custom Rendering Engine — ✅ COMPLETE

Per [07-execution-plan.md](07-execution-plan.md), Phase 5 targets:

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMEditorUI** | `FontMetrics.swift` — CoreText font measurement (ascent, descent, leading, xHeight, capHeight, columnWidth, baseline, lineHeight) | ✅ |
| **TMEditorUI** | `LayoutLine.swift` — StyleRun struct + LayoutLine class wrapping CTLine with hit-testing, foreground/background drawing | ✅ |
| **TMEditorUI** | `EditorLayoutManager.swift` — viewport-based layout engine, coordinate conversion, invalidation, attributed string creation with tab stops and style runs | ✅ |
| **TMEditorUI** | `EditorView.swift` — custom NSView replacing NSTextView: CoreText rendering, caret blinking, selection highlighting, mouse handling, NSTextInputClient (IME), NSAccessibility, EditorViewDelegate protocol, EditorViewAction enum (32 actions) | ✅ |

### Integration

| Target | Change | Status |
|--------|--------|--------|
| **Package.swift** | Added TMEditorUI library + TMEditorUITests target | ✅ |
| **TMDocumentWindow** | `DocumentWindowController` now uses `EditorView` instead of `NSTextView` | ✅ |

### Key Features Implemented

- **CoreText rendering** — direct `CTLine` creation and drawing, replacing NSTextView
- **Viewport-based layout** — only lays out visible lines + overscan, caches results
- **Style runs** — per-character foreground/background, bold, italic, underline, strikethrough
- **Caret blinking** — 0.5s timer, resets on input, multi-cursor support
- **Selection highlighting** — single-line and multi-line selection rendering
- **Line highlighting** — optional current-line highlight
- **Invisible characters** — spaces (·), tabs (‣), newlines (¬) with toggle
- **Wrap column indicator** — vertical line at configured column
- **Mouse interaction** — click-to-position, drag-to-select, Option-click multi-cursor, double/triple-click
- **NSTextInputClient** — full IME support (insertText, setMarkedText, unmarkText, markedRange, selectedRange, attributedSubstring, firstRect, characterIndex)
- **NSAccessibility** — textArea role, value, selectedText, lineForIndex, rangeForLine, frameForRange, visibleCharacterRange
- **NSStandardKeyBindingResponding** — 32 key binding actions (12 movement, 10 selection extension, 6 deletion, 3 insertion, 1 selectAll)
- **Coordinate conversion** — lineIndex↔Y, characterIndex↔point, caretRect
- **Invalidation** — per-line, range, style-only, full invalidation

### Tests (78 tests, 4 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| FontMetrics | 11 | ✅ |
| LayoutLine | 7 | ✅ |
| EditorLayoutManager | 27 | ✅ |
| EditorView | 33 | ✅ |

---

## Iteration 6: Compatibility Layer — ✅ COMPLETE

Per [07-execution-plan.md](07-execution-plan.md), Phase 6 targets:

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMCompatibility** | `EnvironmentBuilder.swift` — TM_* env var construction (25 variables, 4 context structs) | ✅ |
| **TMCompatibility** | `CommandTypes.swift` — command pipeline types (8 enums + BundleCommand struct) | ✅ |
| **TMCompatibility** | `CommandRunner.swift` — Foundation Process-based command execution with pipe I/O | ✅ |
| **TMCompatibility** | `CommandOutputHandler.swift` — output routing for 8 modes + exit code overrides | ✅ |
| **TMCompatibility** | `HTMLOutputView.swift` — WKWebView-based HTML output with TextMate JS bridge | ✅ |
| **TMCompatibility** | `DialogShim.swift` — tm_dialog2 compatibility shim with command registry | ✅ |
| **TMCompatibility** | `SettingsMigrator.swift` — legacy TM2 detection, .tm_properties parser, bundle discovery | ✅ |
| **TMCompatibility** | `RMateServer.swift` — NWListener TCP server implementing rmate protocol | ✅ |

### Tests (53 tests, 6 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| EnvironmentBuilder | 10 | ✅ |
| CommandTypes | 8 | ✅ |
| CommandOutputHandler | 12 | ✅ |
| SettingsMigrator | 10 | ✅ |
| RMateServer | 8 | ✅ |
| BundleInfo | 5 | ✅ |

---

## Iteration 7: Bundle Execution System — ✅ COMPLETE

Per [07-execution-plan.md](07-execution-plan.md), Phase 7 targets:

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMBundleRuntime** | `SecurityPolicy.swift` — TrustLevel (5 levels), PermissionRequest/Response, SecurityPolicy class, LockedBox thread-safe container | ✅ |
| **TMBundleRuntime** | `BundleIndex.swift` — BundleItemKind OptionSet (12 kinds), BundleMenuItem enum, BundleItem class, BundleDescriptor, BundleQuery, BundleIndex (thread-safe) | ✅ |
| **TMBundleRuntime** | `BundleLoader.swift` — .tmbundle directory discovery, plist parsing, menu structure parsing | ✅ |
| **TMBundleRuntime** | `BundleCommandParser.swift` — plist-to-BundleCommand parser with v1→v2 format conversion | ✅ |
| **TMBundleRuntime** | `CommandDispatcher.swift` — full command execution pipeline (security → pre-exec → env → input → process → output routing), script caching | ✅ |
| **TMBundleRuntime** | `AutoRefreshScheduler.swift` — document event triggers, debounced re-execution | ✅ |
| **TMBundleRuntime** | `DragCommandHandler.swift` — drag-and-drop command matching, TM_DROPPED_FILE env vars | ✅ |
| **TMBundleRuntime** | `BundleInstaller.swift` — remote catalog fetch, download/extract/install, dependency resolution, uninstall | ✅ |
| **TMBundleUI** | `BundleMenuBuilder.swift` — NSMenuDelegate dynamic menu, key equivalent parsing (^~$@), disambiguation popup | ✅ |
| **TMBundleUI** | `BundleManagerController.swift` — NSWindowController for install/update/uninstall UI | ✅ |
| **TMBundleUI** | `BundleEditorController.swift` — sidebar tree + content editor + properties panel, change tracking, item CRUD | ✅ |
| **TMBundleUI** | `PermissionDialogController.swift` — modal permission dialog + security preferences panel | ✅ |

### Tests (97 tests, 17 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| SecurityPolicy | 10 | ✅ |
| BundleIndex | 12 | ✅ |
| BundleCommandParser | 14 | ✅ |
| BundleCommand | 3 | ✅ |
| BundleLoader | 5 | ✅ |
| AutoRefreshScheduler | 4 | ✅ |
| CommandDispatcher | 3 | ✅ |
| DragCommandHandler | 3 | ✅ |
| BundleItemKind | 2 | ✅ |
| BundleDescriptor | 2 | ✅ |
| CommandResult | 2 | ✅ |
| BundleInstaller | 5 | ✅ |
| BundleEditorEntry | 5 | ✅ |
| BundleEditorTreeBuilder | 5 | ✅ |
| BundleEditorChangeTracker | 6 | ✅ |
| BundleItemProperties | 5 | ✅ |
| KeyEquivalentParsing | 5 | ✅ |

---

## Iteration 8: Document Management — ✅ COMPLETE

Per [07-execution-plan.md](07-execution-plan.md), Phase 8 targets:

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMDocumentManager** | `TMDocument.swift` — core document model: UUID identity, state machine (unloaded/loading/loaded/saving/error), ref-counted open/close, async load/save, BOM-aware encoding detection, line ending normalization, 3-way merge, xattr persistence, change observation | ✅ |
| **TMDocumentManager** | `TMDocumentController.swift` — singleton registry: UUID + path indexes, path deduplication via canonicalization, LRU tracking, untitled document factory, document added/removed callbacks | ✅ |
| **TMDocumentManager** | `FileWatcher.swift` — DispatchSource-based kqueue file monitoring: per-file watches with WatchToken, FileWatchEvent OptionSet, auto-rewatch on delete/rename, DirectoryWatcher companion | ✅ |
| **TMDocumentManager** | `DocumentSession.swift` — session save/restore: SessionDocumentInfo, SessionWindowInfo, WindowFrame, DocumentSession (all Codable), SessionManager JSON persistence to ~/Library/Application Support/TextMate/ | ✅ |
| **TMDocumentManager** | `MarkTracker.swift` — global bookmark system: MarkType enum (4 types), DocumentMark struct, path-keyed storage, toggle bookmark, line adjustment for edits, path rename transfer, export/import serialization | ✅ |
| **TMDocumentManager** | `FileTypeDetector.swift` — file type detection: shebang parsing (with /usr/bin/env and flag skipping), first-line regex patterns, 40+ extension mappings, 15+ filename mappings, version-stripping for interpreters | ✅ |
| **TMDocumentManager** | `RecentDocuments.swift` — LRU recent files: RecentDocumentEntry, UserDefaults persistence, max entries, prune stale entries, change callback | ✅ |
| **TMDocumentManager** | `DocumentBackup.swift` — auto-save crash recovery: BackupRecord, BackupManifest (Codable), periodic timer-based backup, recovery and discard operations | ✅ |

### Key Features Implemented

- **Document model** — full equivalent of C++ `OakDocument` with UUID identity, state machine, revision-based modification tracking
- **Encoding detection** — BOM-aware (UTF-8/16/32), IANA charset conversion, line ending detection via Unicode scalar iteration (handles CR+LF grapheme cluster correctly)
- **3-way merge** — mine-wins strategy for external file changes during editing
- **Extended attributes** — persists selection range, visible index, bookmarks, folded ranges via `setxattr`/`getxattr`
- **File watching** — kqueue-based `DispatchSource.makeFileSystemObjectSource` with automatic rewatch after rename/delete
- **Session persistence** — JSON-based window state serialization with ISO 8601 dates
- **Mark system** — line-adjustment for insert/delete, path rename transfer, document load/save lifecycle
- **File type detection** — priority chain: shebang > first-line patterns > filename > extension > fallback

### Tests (194 tests, 23 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| TMDocument | 16 | ✅ |
| LineEnding Detection | 5 | ✅ |
| DocumentEncoding | 5 | ✅ |
| DataDecoding | 7 | ✅ |
| ThreeWayMerge | 6 | ✅ |
| DocumentIOError | 3 | ✅ |
| DocumentState | 5 | ✅ |
| TMDocumentController | 16 | ✅ |
| FileWatcher | 7 | ✅ |
| DirectoryWatcher | 3 | ✅ |
| FileWatchEvent | 2 | ✅ |
| SessionDocumentInfo | 3 | ✅ |
| SessionWindowInfo | 3 | ✅ |
| DocumentSession | 2 | ✅ |
| SessionManager | 3 | ✅ |
| MarkTracker | 15 | ✅ |
| DocumentMark | 3 | ✅ |
| FileTypeDetector | 30 | ✅ |
| RecentDocumentsManager | 10 | ✅ |
| RecentDocumentEntry | 2 | ✅ |
| DocumentBackupManager | 10 | ✅ |
| BackupRecord | 7 | ✅ |
| BackupManifest | 2 | ✅ |

---

## Phase 9: Search & Replace — ✅ COMPLETE

### Packages & Source Files

| Package | File | Status |
|---------|------|--------|
| **TMSearchReplace** | `FindOptions.swift` — `FindOptions` OptionSet, `FindOperation`, `SearchScope`, `FindMatch`, `DocumentMatch`, `LineColumnRange` | ✅ |
| **TMSearchReplace** | `TextFinder.swift` — `TextFinder` protocol, `PlainTextFinder` (case, words, backwards, whitespace), `RegexFinder` (NSRegularExpression, captures), factory | ✅ |
| **TMSearchReplace** | `ReplacementTemplate.swift` — Format string expansion (`$N`, `${name}`, `${N:/transform}`, `(?N:then:else)`, escapes), `replaceAll` convenience | ✅ |
| **TMSearchReplace** | `BufferSearcher.swift` — Buffer-level find ops (findNext with wrap, findAll, replaceAll with template expansion, countMatches) | ✅ |
| **TMSearchReplace** | `ProjectSearchEngine.swift` — `SearchResultNode` tree, `ProjectSearchConfig`, `SearchProgress`, async `ProjectSearchEngine` with glob filtering | ✅ |
| **TMSearchReplace** | `FindProtocol.swift` — `FindServer`/`FindClient` protocols, `FindNavigationDelegate`, `DocumentMatchReference`, `FindState` observable | ✅ |
| **TMSearchReplace** | `IncrementalSearch.swift` — `IncrementalSearchState` live search bar (anchor, highlight all, findNext/Previous) | ✅ |
| **TMSearchReplace** | `FindHistory.swift` — `FindPasteboard` singleton (system find pasteboard sync, history, UserDefaults persistence) | ✅ |

### Key Features

- **TextFinder protocol** — abstraction for plain text and regex engines, with factory dispatch
- **PlainTextFinder** — String-based search with Unicode normalization, full word boundary detection, backwards search, whitespace-insensitive mode
- **RegexFinder** — NSRegularExpression wrapper with numbered capture group extraction, anchorsMatchLines, case insensitive
- **ReplacementTemplate** — Full format string expansion: `$0`–`$9`, `${name}`, `${N:/upcase|downcase|capitalize}`, `(?N:then:else)` conditionals, escape sequences; recursive expansion inside conditionals
- **BufferSearcher** — String-level find with wrap-around, offset-based forward/backward, replaceAll with template expansion
- **ProjectSearchEngine** — Async file system traversal with include/exclude glob filtering, per-file matching, excerpt building with context, cancel support, progress reporting
- **SearchResultNode** — Tree model (root→file→match) with exclude/readonly propagation, match counting, deduplication
- **FindState** — Observable shared state with find/replace history (max 30, dedup), options, search scope persistence
- **FindPasteboard** — Singleton bridging system NSPasteboard.find, history management, UserDefaults save/restore
- **IncrementalSearchState** — Live search bar with anchor position, automatic re-search on keystroke (didSet), highlight all matches, case toggle

### Tests (140 tests, 22 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| FindOptions | 7 | ✅ |
| FindOperation | 2 | ✅ |
| SearchScope | 2 | ✅ |
| FindMatch | 5 | ✅ |
| DocumentMatch | 2 | ✅ |
| LineColumnRange | 5 | ✅ |
| PlainTextFinder | 12 | ✅ |
| RegexFinder | 7 | ✅ |
| TextFinder Factory | 3 | ✅ |
| RegexValidation | 2 | ✅ |
| ReplacementTemplate | 20 | ✅ |
| BufferSearchResult | 2 | ✅ |
| BufferSearcher | 15 | ✅ |
| SearchResultNode | 9 | ✅ |
| ProjectSearchConfig | 3 | ✅ |
| SearchProgress | 2 | ✅ |
| ProjectSearchEngine | 4 | ✅ |
| FindState | 7 | ✅ |
| DocumentMatchReference | 2 | ✅ |
| FindPasteboard | 4 | ✅ |
| FindHistory | 6 | ✅ |
| IncrementalSearchState | 12 | ✅ |

---

## Phase 10: SCM Integration — ✅ COMPLETE

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMSCM** | `SCMStatus.swift` — `SCMStatus` enum (9 cases: unknown/none/unversioned/modified/added/deleted/conflicted/ignored/mixed), `SCMStatusMap` (path→status dictionary, directory status computation, merge), `SCMVariables` (VCS info, TM_SCM_* environment export) | ✅ |
| **TMSCM** | `SCMDriver.swift` — `SCMDriver` protocol (detection marker, root walk, async status/variables), `SCMDriverRegistry` (ordered driver list, auto-detect), `runCommand` async Process helper, `findExecutable` PATH search | ✅ |
| **TMSCM** | `GitDriver.swift` — Git driver: `git status --porcelain=v1 -uall --no-renames` parsing, index/worktree status mapping, branch via `--show-current`, HEAD commit via `rev-parse --short` | ✅ |
| **TMSCM** | `HgDriver.swift` — Mercurial driver: `hg status --all -0` null-separated parsing, `mayTouchFilesystem = true` | ✅ |
| **TMSCM** | `SvnDriver.swift` — Subversion driver: `svn status` 7-column format parsing, `tracksDirectories = true`, branch detection from URL (`/branches/`, `/trunk`) | ✅ |
| **TMSCM** | `SCMRepository.swift` — `@MainActor` observable repository: async refresh, repository-level and file-level observer callbacks, `modifiedFiles`/`uncommittedFiles` computed properties, `SCMError` enum | ✅ |
| **TMSCM** | `SCMManager.swift` — `@MainActor` singleton manager: repository caching by root path, auto-detect VCS, auto-refresh via `Task` with configurable interval, `refreshAll` via TaskGroup, convenience status/variables/branch APIs | ✅ |
| **TMSCM** | `FileStatusBadge.swift` — Visual badge computation: colorName, symbolName (SF Symbols), text, AppKit NSColor, `FileStatusBadgeProvider` with `@MainActor` cache | ✅ |

### Key Features

- **SCMDriver protocol** — abstract interface for VCS drivers with root detection (walks parent directories for marker file/directory), async status and variables
- **Git/Hg/Svn drivers** — full porcelain output parsing, branch/revision detection, proper status code mapping
- **SCMStatusMap** — path→status dictionary with directory status aggregation (computes `mixed` when children have different statuses), merge operation for combining maps
- **SCMVariables** — VCS-agnostic variable struct exposing `TM_SCM_NAME`, `TM_SCM_BRANCH` for bundle command environment
- **SCMRepository** — observable repository model with async refresh, dual-level observer pattern (repository-wide and per-file callbacks), Identifiable
- **SCMManager** — singleton manager with LRU-style repository cache, auto-detect VCS from file path, configurable auto-refresh interval (default 3s), TaskGroup-based parallel refresh
- **FileStatusBadge** — visual status representation with SF Symbol names, semantic color names, AppKit NSColor mapping for file browser integration

### Tests (68 tests, 14 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| SCMStatus | 5 | ✅ |
| SCMStatusMap | 10 | ✅ |
| SCMVariables | 5 | ✅ |
| MockDriver | 4 | ✅ |
| SCMDriverRegistry | 4 | ✅ |
| GitDriver | 1 | ✅ |
| HgDriver | 1 | ✅ |
| SvnDriver | 1 | ✅ |
| ShellHelpers | 3 | ✅ |
| SCMRepository | 8 | ✅ |
| SCMError | 1 | ✅ |
| SCMManager | 9 | ✅ |
| FileStatusBadge | 11 | ✅ |
| FileStatusBadgeProvider | 3 | ✅ |

---

## Phase 11: Filter List / Navigation — ✅ COMPLETE

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMFilterList** | `FuzzyRanker.swift` — `CoverRange` struct, `RankResult` struct, `FuzzyRanker` enum with `normalizeFilter`, `rank(filter:candidate:)`, 4-phase matrix algorithm (match matrix → backward bound → run propagation → greedy walk), CamelCase bonus, contiguous run preference, inline ASCII helpers | ✅ |
| **TMFilterList** | `AbbreviationStore.swift` — Named singletons (NSLock-protected), MRU learn/retrieve, exact+prefix lookup, max 50 entries, UserDefaults persistence, `rankBoost()`, `LockedValue<T>` thread-safe wrapper | ✅ |
| **TMFilterList** | `MatchHighlighter.swift` — `Style` struct, `attributedString(for:coverRanges:)` with background color + underline, `splitCoverRanges(_:at:)` for path/name boundary splitting (`#if canImport(AppKit)`) | ✅ |
| **TMFilterList** | `ChooserItem.swift` — `ChooserItem` protocol, `FileChooserItem` (filename-first then full-path fallback, abbreviation boost, glob matching), `BundleChooserItem` (5 search fields, eclipsed support), `SymbolChooserItem` (section grouping, offset-based order), sorting extensions | ✅ |
| **TMFilterList** | `ChooserPanelController.swift` — `@MainActor` NSPanel (utility, floating), NSSearchField + NSTableView + NSVisualEffectView footer, `showWindow(relativeTo:)`, subclass override points (`#if canImport(AppKit)`) | ✅ |
| **TMFilterList** | `FileChooser.swift` — `FileChooserSource` enum (all/open/uncommitted), `ParsedFilter` struct (regex: filter/glob/selection/symbol), `FileChooserState` with async `enumerateFiles`, abbreviation learning | ✅ |
| **TMFilterList** | `BundleItemChooser.swift` — `BundleSearchSource` OptionSet (7 flags + 3 composites), `BundleItemChooserState` with source/field filtering, `BundleItemDescriptor` population DTO | ✅ |
| **TMFilterList** | `SymbolChooser.swift` — `SymbolChooserState` with section detection (em-space prefix `\u{2003}`), separator exclusion, fuzzy filtering, `SymbolDescriptor` | ✅ |
| **TMFilterList** | `ChooserTableCellView.swift` — `FileChooserCellView` (icon + 2-line name/path, close button), `BundleItemCellView` (name + key equivalent/tab trigger, strikethrough for eclipsed) (`#if canImport(AppKit)`) | ✅ |

### Key Features

- **Fuzzy ranking** — port of C++ `oak::rank()`: 4-phase dynamic programming on match matrix, CamelCase/word-boundary awareness, contiguous run preference, prefix bonus, length ratio bonus
- **Abbreviation learning** — MRU-ordered learned bindings with max 50 entries, exact+prefix lookup, rank boost formula `2.0 + index/count`, UserDefaults persistence
- **File chooser** — 3 sources (all files, open documents, uncommitted), filter parsing regex (glob/selection/symbol notation), filename-first then full-path fallback ranking, async file enumeration with glob exclude
- **Bundle item chooser** — 7 search source flags with 3 tab composites (actions/settings/other), 5 search fields (title/keyEquivalent/tabTrigger/semanticClass/scopeSelector), preserve-order mode for settings
- **Symbol chooser** — section grouping via em-space prefix, separator exclusion, document-order default
- **Match highlighting** — NSAttributedString with background color and underline on matched ranges, cover range splitting at path/name boundary
- **NSPanel UI** — floating utility panel with search field, table view, status footer, `showWindow(relativeTo:)` positioning

### Tests (106 tests, 16 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| FuzzyRanker | 23 | ✅ |
| AbbreviationStore | 12 | ✅ |
| FileChooserSource | 2 | ✅ |
| ParsedFilter | 7 | ✅ |
| FileChooserState | 8 | ✅ |
| FileChooserItem | 5 | ✅ |
| BundleSearchSource | 3 | ✅ |
| BundleChooserItem | 8 | ✅ |
| BundleItemChooserState | 7 | ✅ |
| BundleItemDescriptor | 1 | ✅ |
| SymbolDescriptor | 2 | ✅ |
| SymbolChooserItem | 4 | ✅ |
| SymbolChooserState | 7 | ✅ |
| MatchHighlighter.splitCoverRanges | 7 | ✅ |
| MatchHighlighter.Style | 2 | ✅ |
| MatchHighlighter.attributedString | 3 | ✅ |

---

## Phase 12: Preferences & Auxiliary UI — ✅ COMPLETE

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMPreferences** | `PreferencesKeys.swift` — 30+ static key constants organized by category, `RMateListenMode` enum, `UpdateChannel` enum, `defaultEnvironmentVariables` (9 entries) | ✅ |
| **TMPreferences** | `PreferencesPane.swift` — `@MainActor PreferencesPaneProtocol`, `PreferencesPane` base class with KVC proxy via `value(forUndefinedKey:)`/`setValue(_:forUndefinedKey:)` routing to `defaultsProperties`/`tmProperties`, `PreferencesSettingsBridge` singleton | ✅ |
| **TMPreferences** | `FilesPreferencesPane.swift` — session restore, encoding popup (12 encodings), line ending popup, file type checkboxes | ✅ |
| **TMPreferences** | `ProjectsPreferencesPane.swift` — 11 defaults properties (foldersOnTop, showFileExtensions, fileBrowserPlacement, etc.), 3 tm properties (exclude/include/binary patterns) | ✅ |
| **TMPreferences** | `BundlesPreferencesPane.swift` — standalone pane with `BundleInfo` struct, category extraction, search filtering, sorted display | ✅ |
| **TMPreferences** | `VariablesPreferencesPane.swift` — standalone pane with `EnvironmentVariable` struct, NSTableView with add/remove, dictionary round-trip for UserDefaults | ✅ |
| **TMPreferences** | `SoftwareUpdatePreferencesPane.swift` — update channel popup, "Check Now" button, `lastCheckDescription()` via RelativeDateTimeFormatter | ✅ |
| **TMPreferences** | `TerminalPreferencesPane.swift` — mate CLI install path/status, rmate server config (listen mode, port) | ✅ |
| **TMPreferences** | `PreferencesWindowController.swift` — `@MainActor` singleton, NSPanel with `NSWindowToolbarStylePreference`, 6 panes, selectNext/Previous with wrapping | ✅ |
| **TMPreferences** | `CommitWindowController.swift` — `CommitItem` (auto-deselect ?/X), `CommitActionCommand` (parse factory), status colors (hardcoded RGB), previous messages (max 5, UserDefaults) | ✅ |
| **TMPreferences** | `HTMLOutputWindowController.swift` — WKWebView wrapper, `isRunningCommand` → `isDocumentEdited`, frame autosave, `retainedSelf` lifecycle | ✅ |
| **TMPreferences** | `FileReference.swift` — `FileReferenceSCMStatus` enum, identity-mapped cache via `NSMapTable.strongToWeakObjects()`, open/modified ref-counting, SCM badge overlay, symlink badge | ✅ |

### Integration

| Target | Change | Status |
|--------|--------|--------|
| **Package.swift** | Added TMPreferences library + TMPreferencesTests target, WebKit linker setting, TMApp dependency | ✅ |
| **TMApp** | `PreferencesWindowController.swift` replaced with thin `AppPreferencesWindowController` wrapper importing TMPreferences | ✅ |
| **TMApp** | `AppDelegate.swift` updated to use `AppPreferencesWindowController` | ✅ |

### Key Features

- **PreferencesPane base class** — KVC proxy pattern routing Cocoa bindings to UserDefaults (`defaultsProperties`) or `PreferencesSettingsBridge` (`tmProperties`)
- **PreferencesSettingsBridge** — `@unchecked Sendable` singleton with `@Sendable` configure/get/set closures for thread-safe settings access
- **CommitItem** — auto-deselects unversioned ("?") and conflicted ("X") items, `Comparable` by case-insensitive path
- **CommitActionCommand** — parse factory for "M,A,D:Revert,/usr/bin/svn,revert" format strings
- **FileReference** — identity-mapped via `NSMapTable.strongToWeakObjects()`, open/modified ref-counting with preconditions, SCM badge overlay image composition
- **HTMLOutputWindowController** — WKWebView with `isRunningCommand` binding to `isDocumentEdited`, `cancelOperation` override for stop button

### Tests (123 tests, 12 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| PreferencesKeys | 10 | ✅ |
| PreferencesSettingsBridge | 5 | ✅ |
| EnvironmentVariable | 14 | ✅ |
| CommitItem | 11 | ✅ |
| CommitActionCommand | 9 | ✅ |
| CommitStatusColors | 9 | ✅ |
| FileReference | 21 | ✅ |
| BundlesPreferencesPane | 10 | ✅ |
| PreferencesPaneProperty | 12 | ✅ |
| HTMLOutputWindowController | 6 | ✅ |
| PreferencesWindowController | 10 | ✅ |
| PreferencesKeys (env vars) | 6 | ✅ |*

---

## Phase 13: Application Infrastructure — ✅ COMPLETE

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMServices** | `ExtendedAttributes.swift` — POSIX xattr wrappers: `read/readString/write/writeString/remove/list` by path, `read/write` by file descriptor | ✅ |
| **TMServices** | `PathUtilities.swift` — 40+ path manipulation functions: `normalize/name/parent/extension/extensions/join/isAbsolute/isChild/withTilde/relativeTo/escape/unescape/displayName/disambiguate/unique/rank/exists/isDirectory/isReadable/home/temp/cwd/makeDir/content/setContent` | ✅ |
| **TMServices** | `AtomicFileSave.swift` — volume-aware atomic file save with 3 strategies: `FileManagerStrategy` (NSFileManager `replaceItem`), `RenameStrategy` (temp+rename on same volume), `DirectStrategy` (overwrite in-place); `SaveError` enum | ✅ |
| **TMServices** | `EventStringFormatter.swift` — event string parsing/formatting for `$^~@#` key representation: `parse/create/normalize/glyphsForFlags/glyphsForEventString/attributedString`; function key glyph table; modifier flag display order (⌃⌥⇧⌘) | ✅ |
| **TMServices** | `VersionComparison.swift` — semantic version string comparison with prerelease (`-`) and build metadata (`+`) handling: `compare(_:_:) -> ComparisonResult`, `less(_:_:) -> Bool` | ✅ |
| **TMServices** | `SignatureVerifier.swift` — DSA/RSA signature verification via Security.framework: `SecVerifyTransformCreate`, `SecItemImport` for PEM key import, `KeyChain` struct for identity→key mapping, base64 signature decoding | ✅ |
| **TMServices** | `ArchiveExtractor.swift` — `.tbz` extraction via `/usr/bin/tar -jxmkC`: bulk `extract(data:)`, streaming `beginStreaming/write/finishStreaming`, async `extractAsync(data:)`, configurable `Options` (stripComponents, disableCopyfile, excludePatterns) | ✅ |
| **TMServices** | `DownloadManager.swift` — URLSession-based download manager: `downloadFile` with ETag xattr caching + signature verification, `downloadArchive` with streaming extraction pipeline, user agent string with sysctl hardware info, internal `ArchiveDownloadTask` (`URLSessionDataDelegate`) | ✅ |
| **TMServices** | `SoftwareUpdateEngine.swift` — `@MainActor` auto-update engine: `NSBackgroundActivityScheduler` (1-hour interval), channel management (release/beta/nightly), async `checkForUpdate`, `installAndRelaunch` with shell script, `suspendChecks`, read-only filesystem detection, `downloadUpdate` returning `(Progress, Task)` | ✅ |

### Integration

| Target | Change | Status |
|--------|--------|--------|
| **Package.swift** | Added TMServices library + TMServicesTests target, Security.framework linker setting | ✅ |

### Key Features

- **ExtendedAttributes** — Non-throwing API returning optionals/bools; supports both path-based and file-descriptor-based operations
- **PathUtilities** — Comprehensive port of `Frameworks/io/src/path.h`; `disambiguate` returns minimum trailing component counts; `escape` uses shell quoting; `unescape` returns `[String]` to handle multiple paths
- **AtomicFileSave** — Port of `intermediate_t`; volume-aware strategy selection ensures atomic writes even across volume boundaries
- **EventStringFormatter** — Full port of `ns/event.h/.mm`; supports legacy TextMate 1 format; function key glyph table (F1–F35); auto-shift detection for shifted characters
- **SignatureVerifier** — `KeyChain` struct maps signee identities to PEM public keys; `httpSigneeHeader`/`httpSignatureHeader` constants for download verification
- **DownloadManager** — Singleton with `URLSessionDataDelegate`; captures signee/signature from HTTP response headers and redirect chains; ETag-based conditional requests via xattr cache
- **SoftwareUpdateEngine** — Observable `@MainActor` class; `@preconcurrency import Foundation` + `nonisolated(unsafe)` for Sendable bridging; `MainActor.assumeIsolated` in deinit

### Tests (105 tests, 9 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| ExtendedAttributes | 7 | ✅ |
| PathUtilities | 22 | ✅ |
| AtomicFileSave | 6 | ✅ |
| EventStringFormatter | 11 | ✅ |
| VersionComparison | 12 | ✅ |
| SignatureVerifier | 7 | ✅ |
| ArchiveExtractor | 6 | ✅ |
| DownloadManager | 4 | ✅ |
| SoftwareUpdateEngine | 8 | ✅ |

*Note: Tests require macOS — guarded with `#if canImport(AppKit)` where needed. ArchiveExtractor real archive test uses `/usr/bin/tar` for creating test `.tbz` files.*

---

## Phase 14: File Browser Sidebar — ✅ COMPLETE

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMFileBrowser** | `FileBrowserNotifications.swift` — `willDelete`/`didDuplicate` notification names, `pathKey`/`urlDictionaryKey` userInfo keys | ✅ |
| **TMFileBrowser** | `FileItem.swift` — `@MainActor` model for files/directories: URL, file property flags, Finder tags, localized name, directory observer pattern, `QLPreviewItem` conformance, `FileBrowserLocation` enum, `FinderTag` struct | ✅ |
| **TMFileBrowser** | `FileItemImage.swift` — Composite icon generation with SCM status badges: `iconImage(for:...)`, badge color/symbol rendering, dimmed modified icons | ✅ |
| **TMFileBrowser** | `FileBrowserOutlineView.swift` — Custom `NSOutlineView` subclass: ⌘-Delete trash shortcut, right-click menu support, `FileBrowserOutlineViewDelegate` protocol | ✅ |
| **TMFileBrowser** | `FileItemTableCellView.swift` — Table cell view with open/close buttons, icon, editable name field, `configure(with:icon:)` | ✅ |
| **TMFileBrowser** | `FileBrowserHeaderView.swift` — `NSVisualEffectView` header with folder popup, back/forward navigation buttons | ✅ |
| **TMFileBrowser** | `FileBrowserActionsView.swift` — `NSVisualEffectView` actions bar with create, reload, search, favorites, SCM buttons | ✅ |
| **TMFileBrowser** | `FinderTagsChooser.swift` — Color swatch grid for Finder tag selection/removal | ✅ |
| **TMFileBrowser** | `FileBrowserCompositeView.swift` — Composes header, scroll view with outline, and actions bar | ✅ |
| **TMFileBrowser** | `DiskOperations.swift` — `DiskOperation` OptionSet, `DiskOperationHandler` with undo/redo, conflict resolution dialogs (Replace/Stop/Skip), unique name generation | ✅ |
| **TMFileBrowser** | `FileBrowserViewController.swift` — Full file browser controller (~1750 lines): navigation history, file operations, cut/copy/paste, delete/duplicate/rename, favorites, session state persistence, context menu, QuickLook, drag & drop, Finder tag editing, item comparator/arrangement | ✅ |

### Integration

| Target | Change | Status |
|--------|--------|--------|
| **Package.swift** | Added TMFileBrowser library + TMFileBrowserTests target, QuickLookUI framework linker setting | ✅ |

### Key Features

- **FileItem** — `@MainActor` model with `@unchecked Sendable`; uppercase `URL` property (Obj-C convention) with lowercase `url` alias; `DirectoryObserver` pattern for FSEvent-backed directory watching; `QLPreviewItem` conformance via `nonisolated` + `MainActor.assumeIsolated`
- **FileBrowserViewController** — Full port of 2300-line C++ `FileBrowserViewController.mm`; navigation stack with back/forward/parent/computer/home/desktop/favorites/SCM; session state serialization; `NSOutlineViewDataSource`/`NSOutlineViewDelegate`; LCS-based outline view animation for rearranges; disambiguation suffix calculation for duplicate names; drag-and-drop with link/copy/move detection
- **DiskOperationHandler** — `UndoManager`-based undo/redo for all file operations; conflict resolution with Replace/Stop/Skip alerts; unique name generation via regex; sound effects for operations
- **QuickLook** — `QLPreviewPanelDataSource`/`QLPreviewPanelDelegate` via nonisolated extension; `acceptsPreviewPanelControl`/`beginPreviewPanelControl`/`endPreviewPanelControl` overrides
- **Concurrency** — `nonisolated(unsafe)` for directory observer tokens; `MainActor.assumeIsolated` in deinit for cleanup; `nonisolated` QL methods with `MainActor.assumeIsolated` bodies

### Tests (27 tests, 20 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| FileBrowserNotifications | 5 | ✅ |
| FileBrowserLocation | 7 | ✅ |
| FileItem initialization | 10 | ✅ |
| FileItem properties (real files) | 4 | ✅ |
| FileItem DirectoryObserver | 4 | ✅ |
| FinderTag | 4 | ✅ |
| FileItemImage.SCMStatus | 2 | ✅ |
| FileItemImage icon generation | 6 | ✅ |
| DiskOperation OptionSet | 4 | ✅ |
| DiskOperationHandler.incrementedName | 6 | ✅ |
| DiskOperationHandler unique URLs | 1 + 1 skipped | ✅ |
| FileBrowserViewController init | 4 | ✅ |
| FileBrowserViewController navigation | 6 | ✅ |
| FileBrowserViewController comparator | 2 | ✅ |
| FileBrowserViewController session state | 4 | ✅ |
| FileBrowserCompositeView | 1 | ✅ |
| FileBrowserHeaderView | 1 | ✅ |
| FileBrowserActionsView | 1 | ✅ |
| FileBrowserOutlineView | 1 | ✅ |
| FileItemTableCellView | 2 | ✅ |

*Note: All AppKit-dependent code guarded with `#if canImport(AppKit)`. View controller tests exercise init, navigation, session state roundtrip, and item comparator without requiring a visible window.*

---

## Iteration 15: HTML Output Chrome & System Services — ✅ COMPLETE

### What Was Ported

Ported remaining meaningful C++ code from legacy frameworks:

| Legacy Framework | Lines (C++) | Ported To | Description |
|------------------|-------------|-----------|-------------|
| HTMLOutput/src/ (HOStatusBar, HOBrowserView, HOWebViewDelegateHelper, OakHTMLOutputView, HOJSBridge) | ~1,400 | TMHTMLOutput | Browser chrome, JS bridge, command lifecycle |
| authorization/src/ | ~356 | TMServices | Privileged helper IPC, AuthorizationRef |
| ns/src/spellcheck/ | ~102 | TMServices | NSSpellChecker wrapper with UTF-8 ranges |
| encoding/src/ | ~258 | TMDocumentManager | Bayesian charset classifier |

### New Package: TMHTMLOutput

Depends on TMCompatibility, links WebKit.

| File | Description |
|------|-------------|
| `HTMLOutputStatusBar.swift` | NSVisualEffectView status bar with back/forward buttons, status text, progress indicator (determinate + spinner) |
| `HTMLOutputBrowserView.swift` | Composite WKWebView + StatusBar with KVO progress tracking, swipe navigation, hover link status, error pages, WKNavigationDelegate (txmt://, tm-file://), WKUIDelegate (JS alerts, new windows) |
| `HTMLOutputCommandView.swift` | Full TextMate HTML output widget with JS bridge (TextMate.system/log/open), command lifecycle, auto-scroll, process management, printing |

### Additions to Existing Packages

| Package | File | Description |
|---------|------|-------------|
| TMServices | `AuthorizationService.swift` | NSXPCConnection-based privileged helper (replaces Unix socket IPC), AuthorizationRef wrapper, hex serialization |
| TMServices | `SpellCheckService.swift` | NSSpellChecker wrapper with DocumentTag lifecycle, UTF-16→UTF-8 range conversion, suggestions |
| TMDocumentManager | `EncodingDetector.swift` | Bayesian charset classifier with word/byte frequency analysis, Codable JSON persistence (replaces Cap'n Proto) |

### Modernization Decisions

- **WKWebView** replaces deprecated `WebView` throughout
- **NSXPCConnection + SMAppService** replaces Unix socket IPC for privileged helper
- **MainActor.assumeIsolated** used in WKScriptMessageHandler callbacks for strict concurrency
- **Codable JSON** replaces Cap'n Proto for encoding frequency persistence
- **String.Index(utf16Offset:)** used for NSSpellChecker range conversion to UTF-8

### Frameworks Assessed as Not Needing Port

| Framework | Reason |
|-----------|--------|
| HTMLOutputWindow | Functionality covered by TMPreferences.HTMLOutputWindowController |
| OakDebug | Debug macros — not needed in Swift |
| OakSystem | Trivial wrappers already covered by Foundation/AppKit |
| cf | CoreFoundation wrappers — using native Swift equivalents |
| MenuBuilder | Ported as TMApp.MainMenuBuilder |
| license | Unnecessary — TextMate 2 is free/open-source |
| crash/CrashReporter | Apple Crash Reporter + os.log replaces custom crash handling |

### Tests (1425/1425 pass — 191 suites)

| Suite | Tests | Status |
|-------|-------|--------|
| HTMLOutputStatusBar | 8 | ✅ |
| HTMLOutputBrowserView | 5 | ✅ |
| HTMLOutputBrowserView – Delegate | 1 | ✅ |
| HTMLOutputCommandView | 6 | ✅ |
| HTMLOutputCommandView – Printing | 1 | ✅ |
| AuthorizationService – Constants | 2 | ✅ |
| AuthorizationService – Serialization | 1 | ✅ |
| AuthorizationService – Error Types | 2 | ✅ |
| SpellCheckService | 7 | ✅ |
| EncodingDetector | 7 | ✅ |
| FrequencyRecord | 3 | ✅ |

---

## Phase 16: Snippet & Format String Engine — ✅ COMPLETE

### What Was Ported

Ported the core regexp framework's format string, snippet, glob, indent, and dependency graph modules (~2,200 lines of C++20 → ~2,670 lines of Swift).

| Legacy Framework | C++ Source Files | Ported To | Description |
|------------------|-----------------|-----------|-------------|
| regexp/src/format_string.h/.cc | ~600 | TMCore | Format string AST, parser, expander |
| regexp/src/snippet.h/.cc | ~500 | TMCore | Snippet runtime (fields, mirrors, transforms, nesting) |
| regexp/src/glob.h/.cc | ~400 | TMSettings | Glob pattern compilation, brace expansion, include/exclude lists |
| regexp/src/indent.h/.cc | ~200 | TMEditor | Pattern-based auto-indentation FSM |
| oak/dependency_graph.h | ~100 | TMCore | Generic DAG for mirror update ordering |

### New Source Files (2,670 lines)

| Package | File | Lines | Description |
|---------|------|-------|-------------|
| **TMCore** | `FormatStringNode.swift` | 107 | AST `indirect enum` with 11 cases: text, variable, variableTransform, variableFallback, variableCondition, variableChange, caseChange, placeholder, placeholderTransform, placeholderChoice, code |
| **TMCore** | `FormatStringParser.swift` | 563 | Recursive descent parser for TM format strings and snippet bodies; handles `${var}`, `${var/regex/format/opts}`, `${var:?then:else}`, case changes (`\u\l\U\L\E`), control codes, escape sequences |
| **TMCore** | `FormatStringExpander.swift` | 503 | AST evaluator with variable interpolation, regex transforms, case transforms (upper/lower/capitalize with stop words), named transforms (asciify, urlencode, shellEscape, number, duration), snippet field tracking |
| **TMCore** | `DependencyGraph.swift` | 76 | Generic DAG with `addNode`, `addEdge`, `touch` (transitive dependents via BFS), `topologicalOrder` (Kahn's algorithm) |
| **TMCore** | `SnippetEngine.swift` | 660 | Full snippet runtime: `SnippetField` (tab stop, mirror, transform, choice), `SnippetState` (parse → setup → navigate → update mirrors), `SnippetStack` (push/pop/next/previous, nested snippets, position adjustment) |
| **TMSettings** | `GlobPattern.swift` | 546 | Glob-to-regex compiler with `GlobNode` AST, `BraceParser` (brace expansion), `GlobParser` (wildcards, character classes, path separators, exclude patterns), `GlobList` (semicolon-separated include/exclude matching) |
| **TMEditor** | `IndentFSM.swift` | 215 | `PatternType` OptionSet (increase/decrease/incrementNext/ignore/zeroIndent), `IndentFSM` struct with `scanLine`, `isSeeded`/`isIgnored` queries, static `createIndent`/`leadingWhitespace` helpers |

### Key Design Decisions

- **C++ `boost::variant`** → Swift `indirect enum` for AST nodes (zero-cost abstraction)
- **NSRegularExpression** used directly for regex transforms (no Onigmo dependency)
- **Title-case capitalize** — expanded stop words set (23 words: a, an, the, and, as, at, but, by, for, if, in, nor, of, on, or, so, to, up, via, vs, with, yet) matching standard English title-case conventions
- **BraceParser** — rewritten to properly propagate stop characters through nested `{a,b}` expansion
- **GlobParser exclusion** — `~pattern` fully parsed into `exclude` node's left child for correct negation matching
- **DependencyGraph.touch()** — returns empty set for non-existent nodes (guard clause)
- **SnippetStack** — `currentField` exposed as public var for cross-snippet field access

### Tests (1569/1569 pass — 197 suites, +144 tests in 6 new suites)

| Suite | Tests | Status |
|-------|-------|--------|
| DependencyGraphTests | 8 | ✅ |
| FormatStringParserTests | 30+ | ✅ |
| FormatStringExpanderTests | 30+ | ✅ |
| SnippetEngineTests | 15+ | ✅ |
| GlobPatternTests | 20+ | ✅ |
| IndentFSMTests | 15+ | ✅ |

### Remaining Legacy Gaps (for future phases)

| Framework | Lines (C++) | Notes |
|-----------|-------------|-------|
| DocumentWindow | ~3,573 | Main document window management |
| buffer | ~1,178 | Core text buffer |
| file | ~1,547 | File open/save coordination |
| io | ~1,938 | File I/O engine |
| dialog/dialog-1.x | ~3,953 | Command UI handlers |
| theme | ~956 | Theme completion |
| ns | ~606 | Miscellaneous NS utilities |
| CLI Applications | ~5,454 | mate, tm_query, etc. |

---

## Phase 17 — Plist Engine & Text Utilities

Ported the C++ `plist` framework (~1,482 lines) and `text` utility
framework (~897 lines) — foundational infrastructure used pervasively
throughout the codebase.

### Source Files

| Package | File | Description |
|---------|------|-------------|
| **TMCore** | `PlistValue.swift` | Typed plist value enum (`indirect enum PlistValue`), Foundation bridge, key-path extraction, IO (load/save/parse) |
| **TMCore** | `PlistSerializer.swift` | ASCII (OpenStep) plist format serializer with key ordering, escaping, indentation |
| **TMCore** | `PlistDelta.swift` | Plist diff/merge: `createDelta(old:new:)`, `mergeDelta(plists:)` with dot-separated key paths |
| **TMCore** | `PlistCache.swift` | Filesystem plist cache with entry tracking, modification detection, Codable JSON persistence |
| **TMCore** | `TextUtilities.swift` | HTML entity decoding (253 entities), Base32/64, ROT13, URL encode/decode, format size, east-asian width, soft breaks, opposite case, indent style |

### C++ → Swift Mapping

| C++ | Swift |
|-----|-------|
| `plist::any_t` (boost::recursive_variant) | `PlistValue` (indirect enum, 7 cases) |
| `plist::dictionary_t` | `PlistDictionary` ([String: PlistValue]) |
| `plist::load()` / `plist::save()` | `PlistIO.load(contentsOfFile:)` / `PlistIO.save(_:toFile:)` |
| `boost::to_s(plist)` | `PlistSerializer.serialize(_:options:keySortOrder:)` |
| `plist::create_delta()` / `plist::merge_delta()` | `PlistDelta.createDelta(old:new:)` / `PlistDelta.mergeDelta(plists:)` |
| `plist::cache_t` (Cap'n Proto) | `PlistCache` (Codable JSON) |
| `decode::entities()` | `TextDecode.htmlEntities(_:)` |
| `decode::base32()` / `decode::base64()` | `TextDecode.base32(_:)` / `TextDecode.base64(_:)` |
| `decode::rot13()` | `TextDecode.rot13(_:)` |
| `encode::url_part()` | `TextEncode.urlPart(_:excluding:)` |
| `text::format_size()` | `TextUtilities.formatSize(_:)` |
| `text::is_east_asian_width()` | `TextUtilities.isEastAsianWidth(_:)` |
| `text::soft_breaks()` | `TextUtilities.softBreaks(in:width:tabSize:prefixSize:)` |
| `text::opposite_case()` | `TextUtilities.oppositeCase(_:)` |
| `text::indent_t::create()` | `IndentStyle.create(atColumn:units:)` |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| PlistValueTests | 16 | ✅ |
| PlistSerializerTests | 12 | ✅ |
| PlistDeltaTests | 9 | ✅ |
| TextUtilitiesTests | 25+ | ✅ |
| IndentStyleTests | 5 | ✅ |

### Cumulative Total: 1644 tests in 202 suites

---

## Phase 18 — IO Framework & File Status

Ported the C++ `io` framework (~1,301 lines) and simpler parts of the
`file` framework (~400 lines) — low-level file system primitives used
throughout the codebase for path manipulation, process spawning, file
watching, atomic saves, and file status queries.

### Source Files

| Package | File | Description |
|---------|------|-------------|
| **TMCore** | `PathUtilities.swift` | ~40 path manipulation & FS operations: normalize, name, parent, extension, extensions, join, isAbsolute, isChild, withTilde, relativeTo, escape, unescape, displayName, disambiguate, unique, rank, resolve (symlinks + macOS aliases), exists, isReadable, isWritable, isDirectory, isExecutable, isLocal, device, content, setContent, getAttr, setAttr, attributes, setAttributes, link, makeDir, moveToTrash, renameOrCopy, duplicate, copy, move, remove, entries, home, cwd, temp, cache, desktop, volumes |
| **TMCore** | `ProcessExecution.swift` | Process spawning (posix_spawn with pipe I/O), synchronous exec with parallel stdout/stderr reading, environment variable whitelisting with glob patterns |
| **TMCore** | `FSEventWatcher.swift` | FSEventStream wrapper: EventHandler protocol, WatchedStream (wraps FSEventStreamRef, stat-based change detection, watches nearest existing parent), FSEventWatcher singleton with watch/unwatch |
| **TMCore** | `AtomicFileWriter.swift` | 3 atomic save strategies: FileManager (NSFileManager replaceItemAt), atomic (exchangedata/rename), direct; volume-aware strategy selection |
| **TMCore** | `FileStatus.swift` | File writability testing (7 status cases), path→scope attribute generation, BOM detection (UTF-8/16/32 BE/LE), charset→String.Encoding mapping |

### C++ → Swift Mapping

| C++ | Swift |
|-----|-------|
| `path::normalize()` | `PathUtilities.normalize(_:)` |
| `path::name()` / `parent()` / `extension()` / `extensions()` | `PathUtilities.name/parent/extension/extensions` |
| `path::join()` / `is_absolute()` / `is_child()` | `PathUtilities.join/isAbsolute/isChild` |
| `path::with_tilde()` / `relative_to()` | `PathUtilities.withTilde/relativeTo` |
| `path::escape()` / `unescape()` | `PathUtilities.escape/unescape` |
| `path::display_name()` / `disambiguate()` / `unique()` | `PathUtilities.displayName/disambiguate/unique` |
| `path::rank()` | `PathUtilities.rank(_:extension:)` |
| `path::resolve()` / `resolve_head()` | `PathUtilities.resolve/resolveHead` (+ macOS alias via URL.resolvingAliasFileAt) |
| `path::exists()` / `is_directory()` / `is_readable()` / etc. | `PathUtilities.exists/isDirectory/isReadable/...` |
| `path::content()` / `set_content()` | `PathUtilities.content/setContent` |
| `path::get_attr()` / `set_attr()` | `PathUtilities.getAttr/setAttr` (raw xattr API) |
| `path::copy()` / `move()` / `remove()` | `PathUtilities.copy/move/remove` (recursive via copyfile) |
| `path::entries()` | `PathUtilities.entries` (DirectoryEntry struct) |
| `path::home()` / `temp()` / `volumes()` | `PathUtilities.home/temp/cache/desktop/volumes` |
| `io::spawn()` / `io::exec()` | `ProcessExecution.spawn/exec` (posix_spawn + DispatchGroup) |
| `io::create_pipe()` | `ProcessExecution.createPipe` (pipe + FD_CLOEXEC) |
| `oak::basic_environment()` | `ProcessExecution.basicEnvironment` (whitelist-filtered + standard vars) |
| `fs::watch()` / `fs::unwatch()` | `FSEventWatcher.shared.watch/unwatch` |
| `path::intermediate_t` | `AtomicFileWriter` (3 strategies: fileManager, atomic, direct) |
| `file::status()` | `FileStatus.status(_:)` (WritabilityStatus enum) |
| `file::path_attributes()` | `FileStatus.pathAttributes(_:)` (reversed dotted scope string) |
| `encoding::charset_from_bom()` | `FileStatus.charsetFromBOM(_:)` (BOMResult struct) |

### Key Design Decisions

- **`Optional<String>`** instead of C++ `NULL_STR` sentinel values
- **`URL.resolvingAliasFileAt`** for macOS alias resolution (cleaner than raw CF API)
- **`FileManager.contentsOfDirectory`** for directory scanning instead of POSIX `scandir`
- **`posix_spawn` directly** (not Foundation `Process` class) to match C++ semantics
- **`nonisolated(unsafe)`** for dispatch group parallel variable mutation
- **`@unchecked Sendable`** for FSEventWatcher with NSLock thread safety
- **`FSEventStreamSetDispatchQueue`** instead of deprecated `FSEventStreamScheduleWithRunLoop`
- **`dev_t` return**: `~0` instead of `dev_t(bitPattern: -1)` (avoids unsigned overflow)

### Items Deferred to Future Phases

| C++ Source | Reason |
|-----------|--------|
| `file/reader.cc` | Streaming charset-detecting file reader (depends on encoding detection, settings) |
| `file/type.cc` | File type detection (depends on bundles, settings, regexp) |
| `file/open.cc`, `file/save.cc` | Complex state machines (depend on authorization, command, settings) |
| `file/filter.cc` | Bundle import/export filters (depends on command runner) |
| `io/resource.cc` | Legacy Carbon resource fork API (deprecated, skip) |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| PathUtilities — String Manipulation | 14 | ✅ |
| PathUtilities — File System Operations | 12 | ✅ |
| PathUtilities — Display & Disambiguation | 2 | ✅ |
| ProcessExecution — Pipe & Spawn | 8 | ✅ |
| FileStatus — Writability | 4 | ✅ |
| FileStatus — Path Attributes | 3 | ✅ |
| FileStatus — BOM Detection | 8 | ✅ |
| AtomicFileWriter | 7 | ✅ |
| FSEventWatcher — Basic | 3 | ✅ |

### Cumulative Total: 1712 tests in 211 suites

---

## Phase 45: Editor View Interaction Layer — ✅ COMPLETE

### Key Features

| Feature | Description | File(s) |
|---------|-------------|---------|
| **Auto-Pairing** | Smart typing pairs (brackets/quotes) with skip-over, surround-selection, odd-count quotes | `Editor.swift`, `TMDocumentEditor.swift` |
| **`insertWithPairing`** | Editor method: 5-step pairing logic (skip closer, surround, word-char guard, same-char count, insert pair) | `Editor.swift` |
| **`TypingPair` struct** | Opener/closer pair model with default set `()[]{}""''` | `Editor.swift` |
| **`performKeyEquivalent`** | Key equiv dispatch to bundle items (Cmd-key → snippet/command) | `EditorView.swift`, `TMDocumentEditor.swift` |
| **Context Menu** | Right-click menu with Cut/Copy/Paste/Select All | `EditorView.swift`, `TMDocumentEditor.swift` |
| **`scrollWheel`** | Smooth scroll passthrough to scroll view | `EditorView.swift` |
| **`magnify`** | Pinch-to-zoom font scale (6pt–200pt range) | `EditorView.swift`, `TMDocumentEditor.swift` |
| **Menu Validation** | `NSMenuItemValidation` conformance, Cut/Copy disabled without selection | `EditorView.swift`, `TMDocumentEditor.swift` |
| **Services Menu** | `validRequestorForSendType:returnType:`, `writeSelection:`, `readSelection:` | `EditorView.swift` |
| **Drag Source** | `NSDraggingSource` conformance, `beginDragSession(from:)` for text drags | `EditorView.swift` |
| **Key Equiv String** | NSEvent → TextMate key equiv format (`^~$@` modifiers prefix) | `TMDocumentEditor.swift` |

### EditorViewDelegate Additions

| Method | Purpose |
|--------|---------|
| `editorView(_:performKeyEquivalent:) → Bool` | Bundle key equiv dispatch |
| `editorView(_:fontScaleDidChange:)` | Pinch-to-zoom font size |
| `editorViewNeedsContextMenu(_:for:) → NSMenu?` | Context menu construction |
| `editorView(_:validateMenuItem:) → Bool` | Menu item validation |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| Auto-Pairing (insertWithPairing) | 16 | ✅ |
| TMDocumentEditor — Auto-Pairing | 4 | ✅ |
| EditorView — Interactions | 5 | ✅ |
| TMDocumentEditor — Key Equivalent String | 1 | ✅ |

### Cumulative Total: 2596 tests in 320 suites

---

## Phase 46: Live Spell Checking & Macro Wiring — ✅ COMPLETE

### Summary

End-to-end live spell checking pipeline and macro recording menu wiring.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMEditorUI/EditorLayoutManager.swift` | Added `misspellingProvider` callback for per-line misspelling data |
| `Sources/TMEditorUI/EditorView.swift` | `isContinuousSpellCheckingEnabled`, `spellingLanguage`, spelling dot image factory, misspelling draw pass, `changeSpelling(_:)`, `ignoreSpelling(_:)`, context menu suggestions, 3 new delegate methods |
| `Sources/TMDocumentWindow/TMDocumentEditor.swift` | Spell check cache with per-line lazy evaluation via `SpellCheckService`, `recheckSpelling()`, `invalidateSpellCheckCache()`, `spellingSuggestions(at:)`, spell delegate implementations, macro recording in `insertText`/`performAction`, `toggleMacroRecording()`, `replayMacro()` |
| `Sources/TMDocumentWindow/DocumentWindowController+MenuActions.swift` | `toggleContinuousSpellChecking(_:)`, `toggleMacroRecording(_:)`, `replayMacro(_:)` |
| `Sources/TMDocumentWindow/DocumentWindowController.swift` | `validateMenuItem` for spell/macro items, `StatusBarViewDelegate` conformance, spell propagation in `applySettings` |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| TMDocumentEditor — Spell Checking | 8 | ✅ |
| EditorView — Spell Checking State | 4 | ✅ |
| TMDocumentEditor — Macro Recording | 6 | ✅ |
| DocumentWindowController — Spell & Macro Validation | 4 | ✅ |

### Cumulative Total: 2620 tests in 324 suites

---

## Phase 47: Code Folding End-to-End Wiring — ✅ COMPLETE

### Summary

Wired the FoldManager engine (built in a prior phase) end-to-end: data source adapter, editor API, layout manager fold-aware rendering, gutter view interaction, and menu actions.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMDocumentWindow/TextBufferFoldDataSource.swift` | **New** — `FoldDataSource` adapter bridging `TextBuffer` to `FoldManager`; indent-based default fold info; custom `foldInfoProvider` callback |
| `Sources/TMDocumentWindow/TMDocumentEditor.swift` | Added `foldDataSource`/`foldManager` properties + init wiring; public fold API extension: `toggleFold(atLine:recursive:)`, `toggleAllFolds(atLevel:)`, `foldableLineNumbers()`, `foldedLineNumbers()`, `foldedAsString`, `restoreFolds(from:)` |
| `Sources/TMEditorUI/EditorLayoutManager.swift` | Added `foldManager` property with `didSet`; `_hiddenLines` lazy cache; dual-path `layoutLines(in:)` (fast path when no folds, fold-aware scan path otherwise); fold-aware `totalHeight`, `yPosition(forLine:)`, `lineIndex(atY:)`, `layoutLinesSoftWrap`; `isLineFolded(_:)`, `invalidateFolds()` |
| `Sources/TMEditorUI/FoldManager.swift` | Added `public init() {}` to `LineInfo` (cross-module accessibility) |
| `Sources/TMEditorUI/EditorView.swift` | Made `updateFrameSize()` public |
| `Sources/TMAppKit/GutterView.swift` | Changed `foldedLines` to public var with `didSet { needsDisplay = true }` |
| `Sources/TMDocumentWindow/DocumentWindowController.swift` | `GutterViewDelegate` conformance (`didToggleFoldAtLine`); `updateGutterFoldState()` helper; delegate wiring in `setupEditorContainer()`; call in `wireDocumentEditor()` |
| `Sources/TMDocumentWindow/DocumentWindowController+MenuActions.swift` | Rewrote `toggleCurrentFolding` and `takeLevelToFoldFrom` to use FoldManager |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| FoldWiringTests | 7 | ✅ |
| TextBufferFoldDataSourceTests | 7 | ✅ |
| EditorLayoutManager Folds | 4 | ✅ |

### Cumulative Total: 2642 tests in 327 suites

---

## Phase 48: Find Panel ↔ Editor Bridge — ✅ COMPLETE

### Summary

Wired the Find panel (`FindPanelController`/`FindServer`) end-to-end to the editor via `FindClient` conformance on `DocumentWindowController`. ⌘G, ⇧⌘G, Replace, Replace All, and all find panel operations now reach the editor. Find matches are highlighted in the editor view with a yellow overlay.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMDocumentWindow/TMDocumentEditor+Find.swift` | **New** — Bridge translating FindServer queries into BufferSearcher calls; `findNext`, `findAll`, `countMatches`, `replaceCurrent`, `replaceAll`, `allMatchRanges`; capture-aware replacement via `ReplacementTemplate`; `matchCaptures` storage via `ObjectIdentifier`-keyed static dictionary |
| `Sources/TMDocumentWindow/DocumentWindowController+Find.swift` | **New** — `FindClient` conformance dispatching all 8 `FindOperation` cases; `updateHighlights`/`clearHighlights` wiring byte ranges to EditorView |
| `Sources/TMDocumentWindow/TMDocumentEditor.swift` | `syncAfterEdit()` and `syncSelectionToView()` changed from `private` to `internal` for cross-file extension access |
| `Sources/TMDocumentWindow/DocumentWindowController+MenuActions.swift` | Added `findNext:`, `findPrevious:`, `useSelectionForFind:`, `useSelectionForReplace:` menu actions |
| `Sources/TMEditorUI/EditorView.swift` | Added `highlightRanges` property (array of line/index tuples) with `didSet { needsDisplay = true }`; `highlightColor` property; `drawHighlight(range:forLine:in:)` drawing pass before selection highlights |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| FindBridge | 21 | ✅ |
| FindClientConformance | 1 | ✅ |

### Cumulative Total: 2664 tests in 329 suites

---

## Phase 49: File Browser Breadcrumb Navigation — ✅ COMPLETE

### Summary

Wired the `folderPopUpButton` in the file browser header to dynamically populate a breadcrumb menu showing the current location, its parent chain up to root, a Computer entry, "Other…" for Go to Folder, and "Use as Project Folder" for file:// URLs. The popup button was previously present in the UI but completely non-functional.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMFileBrowser/FileBrowserViewController.swift` | Added `currentLocationMenuItem` property; `updateCurrentLocationItem()` syncs title/icon/representedObject on navigation; `folderPopUpButtonWillPopUp(_:)` notification handler; `populateFolderMenu(_:)` builds parent chain via `FileManager.displayName(atPath:)`, Computer entry, "Other…" (via `orderFrontGoToFolder:`), and "Use as Project Folder" (via responder chain to `takeProjectPathFrom:`); `takeURLFrom(_:)` action navigates to selected parent; `folderIcon(for:)` returns 16×16 icon |
| `Sources/TMDocumentWindow/DocumentWindowController+MenuActions.swift` | Added `takeProjectPathFrom(_:)` — reads `representedObject` as String path, sets `projectPath` |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| FileBrowserBreadcrumb | 5 | ✅ |

### Cumulative Total: 2669 tests in 330 suites

---

## Phase 50: Symbol Extraction Pipeline — ✅ COMPLETE

### Summary

Connected the syntax highlighter to the symbol chooser (⌘⇧T) and status bar symbol popup (⌃6). Previously, the symbol extraction scaffolding existed in TMCore (`SymbolExtractor`, `SymbolTransformation`), TMFilterList (`SymbolChooserState`, `SymbolDescriptor`), and TMDocumentWindow (`SymbolChooserController`) — but the pipeline was disconnected: the chooser was fed an empty `symbols: []` array and the status bar popup handler was unimplemented.

### Bug Fix

`PreferenceDefinition.swift` line 173 was parsing the `symbolTransformation` field from the wrong plist key (`"showInSymbolList"` instead of `"symbolTransformation"`).

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMBundle/PreferenceDefinition.swift` | **Fix** — `symbolTransformation` now parsed from correct key `"symbolTransformation"` |
| `Sources/TMDocumentWindow/SyntaxHighlighter+Symbols.swift` | **New** — Extension adding `extractSymbols(bundleIndex:lines:)`: queries BundleIndex for `.settings` items, walks parser scope maps, matches scopes against bundle preferences via `ScopeSelector.doesMatch()` with rank-based priority, caches lookups, extracts text from symbol runs, applies `SymbolTransformation` |
| `Sources/TMDocumentWindow/DocumentWindowController+Choosers.swift` | **Rewritten** — `showSymbolChooser` now feeds real extracted symbols; added `extractCurrentSymbols()`, `navigateToSelectionString(_:)`, `populateSymbolMenu(_:)`, `symbolMenuItemSelected(_:)` |
| `Sources/TMDocumentWindow/DocumentWindowController.swift` | Added `statusBarViewWillShowSymbolMenu(_:popup:)` to `StatusBarViewDelegate` conformance |

### Algorithm (mirrors C++ `symbols_t::did_parse`)

1. Query `BundleIndex` for all `.settings` preference items
2. For each scope in the parser's scope maps, check if any preference with matching scope selector has `showInSymbolList: true`
3. Use `ScopeSelector.doesMatch(ScopeContext(scope))` for matching, pick highest-rank match
4. Cache scope→transformation lookups in `[Scope: SymbolTransformation?]`
5. Walk lines, extract text from symbol runs (UTF-8 byte offset substrings), apply `SymbolTransformation`
6. Return `[SymbolDescriptor]` sorted by position

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| SyntaxHighlighter — Symbol Extraction | 9 | ✅ |
| PreferenceDefinition (symbol settings) | 2 | ✅ |

### Cumulative Total: 2680 tests in 331 suites

---

## Phase 51: Grammar-Based Fold Markers — ✅ COMPLETE

### Summary

Wired grammar fold markers (`foldingStartMarker` / `foldingStopMarker`) into the existing code folding infrastructure. Previously, `TextBufferFoldDataSource.foldInfoProvider` was never assigned — all folding was indent-based. Now, when a grammar (or bundle preference) defines fold markers, they are compiled to `NSRegularExpression` and used for per-line fold detection.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMGrammar/GrammarRegistry.swift` | **New** — `definition(forScope:)` public accessor exposing the private `definitions` dictionary |
| `Sources/TMDocumentWindow/GrammarFoldProvider.swift` | **New** — Compiles `foldingStartMarker`/`foldingStopMarker` to regex, performs per-line matching. Two-tier lookup: bundle preferences (scope-matched) then grammar definition fallback. Matches C++ `setup_patterns()` + `info_for()` algorithm from `folds.cc` |
| `Sources/TMDocumentWindow/TMDocumentEditor.swift` | **Modified** — Added `grammarFoldProvider` property; `configureGrammar()` now calls `configureFoldMarkers()` to create and wire the provider into `foldDataSource.foldInfoProvider` |
| `Tests/TMDocumentWindowTests/GrammarFoldProviderTests.swift` | **New** — 17 tests covering marker detection, indent suppression, empty lines, reconfiguration, bundle preference override, and end-to-end wiring |

### Algorithm (mirrors C++ `folds.cc`)

1. **Two-tier lookup**: Check bundle preferences via `BundleIndex.query(.settings)` with scope matching for `foldingStartMarker`/`foldingStopMarker`; fall back to `GrammarDefinition.foldingStartMarker/foldingStopMarker`
2. **Per-line matching**: Compile patterns to `NSRegularExpression`, match each line
3. **Indent suppression**: If `isStartMarker || isStopMarker`, force `isIndentStartMarker = false` (consistent with C++)
4. **Fallback**: If no fold markers configured, `foldInfoProvider` stays nil → `TextBufferFoldDataSource` uses indent-based detection

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| GrammarFoldProvider | 17 | ✅ |

### Cumulative Total: 2697 tests in 332 suites

---

## Phase 52: Grammar-Aware Auto-Indent — ✅ COMPLETE

### Summary

Connected the `IndentFSM` engine (Phase 16) to the editor's newline action. Previously, auto-indent only copied the leading whitespace from the current line. Now, when a grammar defines `increaseIndentPattern` / `decreaseIndentPattern` (via bundle preferences), the FSM scans preceding lines and computes the correct indent level.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMDocumentWindow/IndentPatternProvider.swift` | **New** — Queries BundleIndex for `.settings` items with scope-matched indent patterns; populates `IndentFSM` `PatternType` set per line; feeds `IndentFSM.scanLine()` for context lines |
| `Sources/TMEditor/Editor.swift` | Added `indentProvider: ((Int) -> String)?` callback; `performInsertNewline()` uses provider if available, falls back to leading-whitespace copy |
| `Sources/TMDocumentWindow/TMDocumentEditor.swift` | Wires `IndentPatternProvider` to `editor.indentProvider` in `configureGrammar()` |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| IndentPatternProvider | 11 | ✅ |

### Cumulative Total: 2708 tests in 333 suites

---

## Phase 53: Encoding & Line-Ending Status Bar UI — ✅ COMPLETE

### Summary

Added encoding and line-ending popup buttons to the status bar, wired to the document model. Users can now see and change the document's charset encoding and line ending from the status bar.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMAppKit/StatusBarView.swift` | Added `encodingPopUp`/`lineEndingPopUp` (NSPopUpButton); `setEncoding`/`setLineEnding` methods; `rebuildEncodingMenu()` (7 common charsets) and `rebuildLineEndingMenu()` (LF/CR/CR-LF); action handlers; delegate method `statusBarView(_:didSelectLineEnding:)` |
| `Sources/TMDocumentWindow/DocumentWindowController.swift` | `StatusBarViewDelegate` methods `didSelectEncoding`/`didSelectLineEnding` update document model; `wireDocumentEditor()`/`openFile`/`applySettings` push encoding+lineEnding to status bar |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| EncodingDisplayTests | 5 | ✅ |
| LineEndingDisplayTests | 4 | ✅ |

### Cumulative Total: 2717 tests in 335 suites

---

## Phase 54: Theme Live Reload — ✅ COMPLETE

### Summary

Added a Theme submenu to the View menu, populated dynamically from BundleIndex theme items. Theme selection is persisted to UserDefaults and applied live to all open windows — rebuilding the ThemeEngine and invalidating the layout for instant visual refresh.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMApp/MainMenuBuilder.swift` | Added "Theme" submenu placeholder to View menu |
| `Sources/TMApp/AppDelegate.swift` | `populateThemeMenu()` queries BundleIndex `.theme` items; `selectTheme(_:)` action handler; `loadAndApplyTheme(uuid:)` loads .tmTheme, persists UUID; `restorePersistedTheme()` on launch; `applyThemeToAllWindows()` |
| `Sources/TMDocumentWindow/DocumentWindowController.swift` | `applyTheme(_:)` now creates `ThemeEngine(theme:)`, sets `themeEngine`, pushes to `SyntaxHighlighter.setThemeEngine()`, calls `invalidateAllLines()` |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| MainMenuBuilder (themeSubmenu) | 1 | ✅ |
| ThemeLiveReloadTests | 4 | ✅ |

### Cumulative Total: 2722 tests in 336 suites

---

## Phase 55: Critical App Lifecycle Wiring — ✅ COMPLETE

### Summary

Wired essential application lifecycle features: `applicationShouldTerminate` with dirty-document save prompts, `txmt://` URL scheme handler for opening files at line/column, RMateServer auto-start on launch, and `:line` navigation in the file chooser.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMApp/AppDelegate.swift` | `applicationShouldTerminate` iterates all windows, prompts save for dirty docs; `application(_:open:)` handles `txmt://open?url=&line=&column=` URLs; `applicationDidFinishLaunching` starts RMateServer |
| `Sources/TMDocumentWindow/DocumentWindowController+Choosers.swift` | File chooser "Go" handler now parses `:line[:column]` suffix from selection string and navigates after opening |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| TxmtURLHandler | 5 | ✅ |
| FileChooserLineNavigation | 3 | ✅ |

### Cumulative Total: 2725 tests in 338 suites

---

## Phase 56: Grammar Switching Popup — ✅ COMPLETE

### Summary

Wired the grammar popup in the status bar so users can switch the active grammar. Previously the popup existed but had no target/action — selecting a grammar did nothing.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMAppKit/StatusBarView.swift` | Added `grammarPopUp.target = self` + `grammarPopUp.action`; new `grammarSelected(_:)` handler reads scope from `representedObject` |
| `Sources/TMDocumentWindow/DocumentWindowController.swift` | Implemented `statusBarViewWillShowGrammarMenu` (queries BundleIndex .grammar items, builds alphabetical menu with "Plain Text" + separator), `statusBarView(_:didSelectGrammar:)` (applies grammar), updated `wireDocumentEditor()` to show grammar name |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| GrammarSelectionTests | 2 | ✅ |
| GrammarSwitchingTests | 5 | ✅ |

### Cumulative Total: 2732 tests in 340 suites

---

## Phase 57: Escape Key → Completion Popup — ✅ COMPLETE

### Summary

Mapped the Escape key (`cancelOperation:`) to trigger the completion popup (`complete:`), mirroring the C++ OakTextView behavior.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMDocumentWindow/TMDocumentEditor.swift` | In `editorView(_:doCommandBySelector:)`, remap `cancelOperation:` → `complete:` before EditorAction conversion |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| EscapeCompletionTests | 2 | ✅ |

### Cumulative Total: 2734 tests in 340 suites

---

## Phase 58: mate CLI Executable — ✅ COMPLETE

### Summary

Created a standalone `mate` command-line tool that connects to TextMate's RMateServer via TCP to open files, supporting line/column navigation, file type hints, stdin reading, and wait mode.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/mate/main.swift` | **New** — Full CLI: arg parsing, TCP socket connection on localhost:52698, rmate protocol client, stdin/file handling, -l/-t/-n/-w flags, MATEFLAGS/RMATE_PORT env |
| `Package.swift` | Added `mate` executable product and target |

### Cumulative Total: 2737 tests in 340 suites

---

## Phase 59: Find in Project Wiring — ✅ COMPLETE

### Summary

Wired ⇧⌘F (Find in Project) with a dedicated action that auto-switches the search scope to `.project` and passes the project folder. Connected the `FindNavigationDelegate` so clicking search results navigates to the matching file/line/column.

### Key Changes

| File | Changes |
|------|---------|
| `Sources/TMApp/MainMenuBuilder.swift` | Changed "Find in Project…" menu item to use `orderFrontFindInProjectPanel:` action |
| `Sources/TMSearchReplace/FindPanelController.swift` | Added optional `scope` parameter to `showPanel(withSelection:scope:)` |
| `Sources/TMDocumentWindow/DocumentWindowController+MenuActions.swift` | Added `orderFrontFindInProjectPanel:` (sets project folder + scope + delegate); wired `navigationDelegate` in `orderFrontFindPanel:` too; `FindNavigationDelegate` conformance with `selectRange(_:inDocumentWithID:)` + `bringToFront()` |

### Test Coverage

| Test Suite | Tests | Status |
|-----------|-------|--------|
| FindInProjectWiring | 6 | ✅ |

### Cumulative Total: 2743 tests in 341 suites

---

### Phase 60 — Menu Action Responder Wiring & Quick Wins (commit `05101cf0`)

**Summary**: Combined four quick-win gaps into a single phase: (1) 22 `@objc` trampoline methods on EditorView for Text menu, Select submenu, Move Selection, and Paste actions; (2) BundleEditorController wiring for ⌃⌥⌘B; (3) macOS dirty-dot (`window.isDocumentEdited`) reflecting document modification state.

**Key Changes**:
- `Sources/TMEditorUI/EditorView.swift` — 22 trampoline methods (selectWord, selectParagraph, selectHardLine, selectCurrentScope, selectBlock, transpose, pasteNext, pastePrevious, uppercaseWord, lowercaseWord, capitalizeWord, changeCaseOfLetter, changeCaseOfWord, shiftLeft, shiftRight, indent, reformatText, reformatTextAndJustify, unwrapText, moveSelectionUp/Down/Left/Right) routing to `delegate?.editorView(_:doCommandBySelector:)` directly to avoid infinite recursion
- `Sources/TMDocumentWindow/DocumentWindowController+MenuActions.swift` — `showBundleEditor` creates `BundleEditorController(bundleIndex:)` and opens window; added `import TMBundleUI`
- `Sources/TMDocumentWindow/DocumentWindowController.swift` — `updateWindowTitle()` now sets `window?.isDocumentEdited = textDocument.isModified`
- `Package.swift` — Added TMBundleUI dependency to TMDocumentWindow target

| Test Suite | Tests | Status |
|-----------|-------|--------|
| EditorView Trampoline Selectors | 2 (parameterized, 23 selectors each) | ✅ |
| Window dirty dot wiring | 2 | ✅ |

### Cumulative Total: 2747 tests in 343 suites

---

### Phase 61 — Find Pboard Trampolines, Center Selection, Macro & Spell Menus

**Summary**: Added find/replace pasteboard trampolines, center-selection-in-visible-area override, macro recording menu items (Start/Stop ⌥⌘M, Replay ⇧⌥⌘M), and "Check Spelling as You Type" Spelling submenu item.

**Key Changes**:
- `Sources/TMEditorUI/EditorView.swift` — `copySelectionToFindPboard:` and `copySelectionToReplacePboard:` trampolines; `override centerSelectionInVisibleArea(_:)` → `scrollToCaret()`
- `Sources/TMApp/MainMenuBuilder.swift` — Macro recording items in Bundles menu; "Check Spelling as You Type" in Spelling submenu

| Test Suite | Tests | Status |
|-----------|-------|--------|
| EditorView Trampoline Selectors (updated) | +2 selectors | ✅ |
| Center Selection test | 1 | ✅ |

### Cumulative Total: 2748 tests in 343 suites

---

### Phase 62 — Undo/Redo Wiring & selectBlock Fix

**Summary**: Wired Edit → Undo/Redo menu actions to `TextUndoManager` with proper `canUndo`/`canRedo` guards, added `validateMenuItem` cases for greying out, and fixed `selectBlock:` mapping from `.selectParagraph` to `.selectTypingPair`.

**Key Changes**:
- `Sources/TMDocumentWindow/DocumentWindowController+MenuActions.swift` — `undo(_:)` and `redo(_:)` with guards
- `Sources/TMDocumentWindow/DocumentWindowController.swift` — `validateMenuItem` cases for `undo:` and `redo:`
- `Sources/TMEditor/EditorAction.swift` — `selectBlock:` → `.selectTypingPair`

| Test Suite | Tests | Status |
|-----------|-------|--------|
| UndoRedoMenuTests | 4 | ✅ |
| SelectBlockMappingTests | 1 | ✅ |

### Cumulative Total: 2753 tests in 345 suites

---

### Phase 63 — File Drop Handler Wiring

**Summary**: Implemented `editorView(_:didReceiveFileDrop:atLine:index:)` on TMDocumentEditor. Drops insert file paths joined by newlines at the caret. Full DragCommandHandler integration deferred until the command execution pipeline is wired.

**Key Changes**:
- `Sources/TMDocumentWindow/TMDocumentEditor.swift` — File drop delegate method inserting paths at caret
- `Tests/TMDocumentWindowTests/TMDocumentEditorTests.swift` — FileDropTests suite (3 tests)

| Test Suite | Tests | Status |
|-----------|-------|--------|
| FileDropTests | 3 | ✅ |

### Cumulative Total: 2756 tests in 346 suites

---

### Phase 64 — Dead Code Cleanup & Drag Command Wiring (commit `6bdf80a7`)

**Summary**: Removed dead `executeItem`/`parser` from BundleSystemController. Added `commandDispatcher` to DocumentWindowController and `onExecuteBundleCommand` callback to TMDocumentEditor. File drops now dispatch drag commands through the CommandDispatcher pipeline.

**Key Changes**:
- `Sources/TMApp/BundleSystemController.swift` — Removed dead `executeItem(uuid:delegate:)` and `private let parser`
- `Sources/TMDocumentWindow/DocumentWindowController.swift` — Added `commandDispatcher: CommandDispatcher?` property, wired `onExecuteBundleCommand` in `wireDocumentEditor()`
- `Sources/TMDocumentWindow/TMDocumentEditor.swift` — Added `onExecuteBundleCommand` callback; drag commands dispatched via `Task { await onExecuteBundleCommand(bundleCmd) }`
- `Sources/TMApp/AppDelegate.swift` — Passes `commandDispatcher` to DocumentWindowController at 3 creation sites
- `Tests/TMDocumentWindowTests/TMDocumentEditorTests.swift` — 2 new DragCommand tests

| Test Suite | Tests | Status |
|-----------|-------|--------|
| DragCommandTests | 2 | ✅ |

### Cumulative Total: 2758 tests in 346 suites

---

### Phase 65 — Snippet Mirror & Transform Wiring (commit `ad104cec`)

**Summary**: Wired snippet mirror propagation so typing in a tab stop updates all mirror occurrences in real time. SnippetController now delegates to SnippetState for mirror cascade, keeping currentField in sync on navigation.

**Key Changes**:
- `Sources/TMEditor/SnippetController.swift` — `replaceCurrentField(with:)` delegates to SnippetState, returns buffer-adjusted MirrorUpdate list; `hasActiveMirrors`, `refreshTabStops()`, `updateTabStopRange(at:to:)`; sync `SnippetState.currentField` on push/next/previous
- `Sources/TMEditor/Editor.swift` — `propagateSnippetMirrors()` reads tab stop content, cascades to mirrors, applies to buffer; called from `insertText`, `insertWithPairing`, `performDelete`
- `Sources/TMDocumentWindow/TMDocumentEditor.swift` — `insertSnippetWithExpansion` passes `baseOffset` and `SnippetState` (when mirrors exist) to `SnippetController.Session`
- `Tests/TMEditorTests/SnippetMirrorTests.swift` — 9 new tests

| Test Suite | Tests | Status |
|-----------|-------|--------|
| SnippetMirrorTests | 9 | ✅ |

### Cumulative Total: 2767 tests in 347 suites

---

### Phase 66 — Incremental Reparse Optimization (commit `6f776401`)

**Summary**: Added EditRegionTracker to track line-level impact of buffer edits, enabling incremental reparse via `SyntaxHighlighter.replaceLines()` for single edits instead of full `setText()` on every keystroke.

**Key Changes**:
- `Sources/TMDocumentWindow/TMDocumentEditor.swift` — `EditRegionTracker` (BufferCallback) tracks single-edit line regions; `editTracker` property wired in init/deinit; `syncAfterEdit()` uses `editTracker.consume()` for incremental path, falls back to `setText` for multiple edits; `documentDidChange()` resets tracker
- `Tests/TMDocumentWindowTests/IncrementalReparseTests.swift` — 8 unit tests for EditRegionTracker + 5 integration tests for syncAfterEdit incremental/full reparse

| Test Suite | Tests | Status |
|-----------|-------|--------|
| EditRegionTracker | 8 | ✅ |
| IncrementalReparseIntegration | 5 | ✅ |

### Cumulative Total: 2780 tests in 349 suites

---

### Phase 67 — ChoiceMenuPanel Wiring (commit `17a5b104`)

**Summary**: Wired the ChoiceMenuPanel into TMDocumentEditor for both completion suggestions and snippet tab stop choices. Key events are intercepted before `interpretKeyEvents` when the menu is visible, and choice acceptance handles both completion cancellation and snippet tab stop replacement.

**Key Changes**:
- `Sources/TMEditorUI/EditorView.swift` — Added `editorView(_:handleKeyDown:) -> Bool` to EditorViewDelegate; EditorView.keyDown calls delegate first, skips interpretKeyEvents when true returned
- `Sources/TMDocumentWindow/TMDocumentEditor.swift` — `handleKeyDown` routes through `choiceMenu.handleKeyEvent()`; `createChoiceMenu()` wires onAccept/onCancel; `acceptChoiceMenuSelection(_:)` for completions and snippet choices; `showSnippetChoicesIfNeeded()` checks snippet choices and shows/populates menu
- `Tests/TMDocumentWindowTests/ChoiceMenuWiringTests.swift` — 12 new tests

| Test Suite | Tests | Status |
|-----------|-------|--------|
| ChoiceMenuWiringTests | 12 | ✅ |

### Cumulative Total: 2792 tests in 350 suites

---

### Phase 68 — Drag-and-Drop Copy + Move Support (commit `d0750b3b`)

**Summary**: Implemented proper drag-and-drop copy and move semantics in EditorView and TMDocumentEditor. Within-app drags default to move; cross-app drags use copy. The source operation mask, drop operation, and move cleanup (deleting original selection after drop) mirror the C++ implementation.

**Key Changes**:
- `Sources/TMEditorUI/EditorView.swift` — `isDragSource` flag; `sourceOperationMaskFor` returns `[.copy, .move]` within app; `draggingSession(_:endedAt:operation:)` handles move cleanup; drop methods return `.move` for same-view; `performDragOperation` distinguishes text/file drops, passes `isMove`; new delegate methods `didReceiveTextDrop` and `editorViewDidCompleteDragMove`
- `Sources/TMDocumentWindow/TMDocumentEditor.swift` — `preDragSelections` property; `didReceiveTextDrop` saves pre-drag selections for moves; `editorViewDidCompleteDragMove` deletes original selections in reverse order
- `Tests/TMDocumentWindowTests/TMDocumentEditorTests.swift` — 7 new tests

| Test Suite | Tests | Status |
|-----------|-------|--------|
| Drag Copy+Move Tests | 7 | ✅ |

### Cumulative Total: 2799 tests in 350 suites

---

### Phase 69 — Scope-Based Command Input (commit `ba134df0`)

**Summary**: Replaced the `.scope` input stub in `DocumentCommandDelegate.resolveInput()` with a proper scope-aware text selection that walks left/right from the caret while the parser scope matches the command's scope selector. Also fixed `CommandDispatcher` to pass `command.scopeSelector` (not `delegate.currentScope`) matching the C++ `_command.scope_selector` pattern.

**Key Changes**:
- `Sources/TMBundleRuntime/CommandDispatcher.swift` — Pass `command.scopeSelector` as the scope parameter to `inputData()`, matching C++ `runner.mm` which uses `_command.scope_selector`
- `Sources/TMDocumentWindow/DocumentCommandDelegate.swift` — Import TMGrammar; accept scope parameter (was `_`); implement `.scope` case using `ScopeSelector` + `parser.scope(atLine:byteOffset:)` to walk left/right, mirroring C++ `extend_scope_left`/`extend_scope_right`
- `Tests/TMDocumentWindowTests/DocumentCommandDelegateTests.swift` — 7 new tests in new `ScopeBasedInputTests` suite

| Test Suite | Tests | Status |
|-----------|-------|--------|
| ScopeBasedInputTests | 7 | ✅ |

### Cumulative Total: 2806 tests in 351 suites

---

### Phase 70 — Key-Equiv & Tab-Trigger Command Dispatch (commit `c199046c`)

**Summary**: Fixed two critical gaps where matched bundle command items were silently dropped. `performKeyEquivalent` now dispatches commands through `BundleCommandParser` + `onExecuteBundleCommand` callback instead of returning `true` without executing. `expandTabTrigger` now handles both snippet and command items, with commands parsed and dispatched through the callback.

**Key Changes**:
- `Sources/TMDocumentWindow/TMDocumentEditor.swift` — `performKeyEquivalent`: after snippet handling, parse command plists via `BundleCommandParser().parse(item:)`, call `fixShebang()`, dispatch through `onExecuteBundleCommand` in a Task; `expandTabTrigger`: restructured to handle `.snippet` (existing path) and `.command` (new path: select trigger text, parse, dispatch)
- `Tests/TMDocumentWindowTests/TMDocumentEditorTests.swift` — 7 new tests in `CommandDispatchTests` suite

| Test Suite | Tests | Status |
|-----------|-------|--------|
| CommandDispatchTests | 7 | ✅ |

### Cumulative Total: 2813 tests in 352 suites

---

### Phase 71 — AutoRefreshScheduler Wiring (commit `08232748`)

**Summary**: Wired the fully-implemented `AutoRefreshScheduler` into the document lifecycle. Commands are now re-executed automatically when their auto-refresh triggers fire (document change, save, close).

**Key Changes**:
- `Sources/TMDocumentWindow/DocumentWindowController.swift` — `autoRefreshScheduler` property; created alongside `CommandDispatcher` in `wireDocumentEditor()`; commands registered after execution; `documentDidSave()` called after successful saves; `documentDidClose()` + `unregisterAll()` called in `windowWillClose`
- `Sources/TMDocumentWindow/DocumentWindowController+CloseFlow.swift` — `documentDidSave()` called after iterative save
- `Sources/TMDocumentWindow/TMDocumentEditor.swift` — Added `onContentChanged` callback fired at end of `syncAfterEdit()`; window controller forwards to `scheduler.documentDidChange()`
- `Tests/TMDocumentWindowTests/WindowLifecycleTests.swift` — 5 new tests in `AutoRefreshWiringTests` suite

| Test Suite | Tests | Status |
|-----------|-------|--------|
| AutoRefreshWiringTests | 5 | ✅ |

### Cumulative Total: 2818 tests in 353 suites

---

### Phase 72 — MarkTracker Wiring (commit `1c1954bc`)

**Summary**: Wired the `MarkTracker` singleton into the document lifecycle so bookmarks survive document close/reopen. Marks are loaded when a document is activated and saved before saves and on window close.

**Key Changes**:
- `Sources/TMDocumentWindow/DocumentWindowController.swift` — `MarkTracker.shared.loadIntoDocument(doc)` in `wireDocumentEditor()` and after `document.load()` in `openFile(at:)`; `saveFromDocument()` before each save and for all documents in `windowWillClose`
- `Sources/TMDocumentWindow/DocumentWindowController+CloseFlow.swift` — `saveFromDocument()` before iterative save
- `Tests/TMDocumentWindowTests/WindowLifecycleTests.swift` — 2 new tests in `MarkTrackerWiringTests` suite

| Test Suite | Tests | Status |
|-----------|-------|--------|
| MarkTrackerWiringTests | 2 | ✅ |

### Cumulative Total: 2820 tests in 354 suites

---

### Phase 73 — DialogShim Wiring (commit `69a0ecfe`)

**Summary**: Wired the `DialogShim` singleton into `DocumentWindowController`, making it available to bundle commands that need to show menus, tooltips, alerts, and file panels. Created built-in command handlers for the 5 most common tm_dialog2 commands.

**Key Changes**:
- `Sources/TMCompatibility/BuiltInDialogHandlers.swift` — **New** — 5 `DialogCommandHandler` implementations: `AlertDialogHandler` (NSAlert with --title/--body/--button args + plist input), `MenuDialogHandler` (popup menu from plist menuItems), `TooltipDialogHandler` (HTML/text tooltip via DialogShim delegate), `FilePanelDialogHandler` (open/save panel with --save/--directory/--title), `HelpDialogHandler` (lists registered commands); `DialogShim.registerBuiltInHandlers()` extension; `String.escapedForHTML` helper
- `Sources/TMDocumentWindow/DocumentCommandDelegate.swift` — `DialogShimDelegate` conformance on `DocumentWindowController`; `dialogShim(_:showToolTipHTML:at:transparent:)` forwards to `showHUD(text:)`
- `Sources/TMDocumentWindow/DocumentWindowController.swift` — `import TMCompatibility`; `wireDocumentEditor()` sets `DialogShim.shared.delegate = self` and calls `registerBuiltInHandlers()`; `windowWillClose` clears delegate if still owned
- `Tests/TMDocumentWindowTests/WindowLifecycleTests.swift` — 6 new tests in `DialogShimWiringTests` suite (delegate set, handlers registered, delegate cleared on close, unknown command error, help handler, tooltip delegate forwarding)

| Test Suite | Tests | Status |
|-----------|-------|--------|
| DialogShimWiringTests | 6 | ✅ |

### Cumulative Total: 2826 tests in 355 suites

---

### Phase 74 — Run Command Window (commit `4bc87b68`)

**Summary**: Implemented the "Filter Through Command…" panel — a singleton NSPanel that lets users type an arbitrary shell command, choose an output destination, and execute it against the current selection.

**Key Changes**:
- `Sources/TMDocumentWindow/RunCommandWindowController.swift` — **New** — Singleton NSPanel with editable combo box (history from UserDefaults, max 10), output popup (Replace Input / Insert After Input / New Document / Tool Tip), Execute (Return) and Cancel (Escape) buttons
- `Sources/TMDocumentWindow/DocumentWindowController+MenuActions.swift` — `orderFrontRunCommandWindow` creates BundleCommand and dispatches via CommandDispatcher

| Test Suite | Tests | Status |
|-----------|-------|--------|
| RunCommandWindowTests | 6 | ✅ |

### Cumulative Total: 2832 tests in 356 suites

---

### Phase 75 — scmBadgeProvider Cleanup (commit `348519d7`)

**Summary**: Removed orphaned `scmBadgeProvider: FileStatusBadgeProvider?` property from DocumentWindowController — declared but never assigned or read. SCM status works via closure-based `scmStatusProvider`.

### Cumulative Total: 2832 tests in 356 suites

---

### Phase 76 — Async Bundle Loading (commit `1713e14f`)

**Summary**: Moved bundle loading off the main thread. `BundleSystemController.loadBundlesAsync()` uses `Task.detached(priority: .userInitiated)` for background I/O, then updates `BundleIndex` on MainActor. Windows can open before bundles finish loading.

**Key Changes**:
- `Sources/TMApp/BundleSystemController.swift` — Added `loadBundlesAsync()` async method
- `Sources/TMApp/AppDelegate.swift` — Menu delegate installed immediately; bundles loaded asynchronously; theme menu/persisted theme restored after async load

| Test Suite | Tests | Status |
|-----------|-------|--------|
| BundleSystemAsyncTests | 3 | ✅ |

### Cumulative Total: 2835 tests in 357 suites

---

### Phase 77 — Remove Dead DocumentModel (commit `da325a6f`)

**Summary**: Deleted `DocumentModel.swift` and its test file — a legacy ~140-line document model class never referenced from production code. `TMDocument` in TMDocumentManager is the real document model.

### Cumulative Total: 2826 tests in 356 suites

---

### Phase 78 — Dead Code Cleanup (commit `cffd035c`)

**Summary**: Removed 881 lines of confirmed dead code: unused imports in 3 files, and 2 dead files (PlistCache.swift ~460 lines with zero references, FileBrowserView.swift ~420 lines with class never instantiated).

**Key Changes**:
- Removed `import TMDocumentWindow` from KeyBindingsLoader.swift, MainMenuBuilder.swift
- Removed `import TMBundle` from SyntaxHighlighter+Symbols.swift
- Deleted `Sources/TMCore/PlistCache.swift` (zero references anywhere)
- Deleted `Sources/TMAppKit/FileBrowserView.swift` (class never instantiated outside its own file)

### Cumulative Total: 2826 tests in 356 suites

---

## Architecture Reminder

All code follows the iteration strategy from
[01-system-architecture.md](01-system-architecture.md#iteration-strategy):

- **Iteration 1** — Visual Shell ✅
- **Iteration 2** — Foundation Layer ✅
- **Iteration 3** — Core Editor Engine ✅
- **Iteration 4** — Syntax & Language System ✅
- **Iteration 5** — Custom Rendering Engine ✅
- **Iteration 6** — Compatibility Layer ✅
- **Iteration 7** — Bundle Execution System ✅
- **Iteration 8** — Document Management ✅
- **Iteration 9** — Search & Replace ✅
- **Iteration 10** — SCM Integration ✅
- **Iteration 11** — Filter List / Navigation ✅
- **Iteration 12** — Preferences & Auxiliary UI ✅
- **Iteration 13** — Application Infrastructure ✅
- **Iteration 14** — File Browser Sidebar ✅
- **Iteration 15** — HTML Output Chrome & System Services ✅
- **Iteration 16** — Snippet & Format String Engine ✅
- **Iteration 17** — Plist Engine & Text Utilities ✅
- **Iteration 18** — IO Framework & File Status ✅
- **Iteration 19+** — Phases 19–46 (integration, polish, interaction, spell check, macros) ✅
- **Iteration 20** — (next)

## Workflow Rules

- **Always run `swiftformat Sources/ Tests/`** before committing
- **Always run `swift build && swift test`** before pushing
- Target the `swift` branch, not `main`
- Use `macos-26` runner in CI, not hardcoded versions
