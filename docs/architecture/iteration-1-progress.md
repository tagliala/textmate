# TextMate Swift Rewrite — Session Progress

> Last updated: 2026-02-15

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

## Architecture Reminder

All code follows the iteration strategy from
[01-system-architecture.md](01-system-architecture.md#iteration-strategy):

- **Iteration 1** — Visual Shell ✅
- **Iteration 2** — Foundation Layer ✅
- **Iteration 3** — Core Editor Engine ✅
- **Iteration 4** — Syntax & Language System ✅
- **Iteration 5** — Custom Rendering Engine ✅
- **Iteration 6** — Compatibility Layer (next)

## Workflow Rules

- **Always run `swiftformat Sources/ Tests/`** before committing
- **Always run `swift build && swift test`** before pushing
- Target the `swift` branch, not `main`
- Use `macos-latest` runner in CI, not hardcoded versions
