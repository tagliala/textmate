# TextMate Swift Rewrite — Session Progress

> Last updated: 2025-07-25

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
- **Iteration 11** — (next)

## Workflow Rules

- **Always run `swiftformat Sources/ Tests/`** before committing
- **Always run `swift build && swift test`** before pushing
- Target the `swift` branch, not `main`
- Use `macos-latest` runner in CI, not hardcoded versions
