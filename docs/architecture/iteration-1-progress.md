# TextMate Swift Rewrite — Session Progress

> Last updated: 2026-02-14

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

## Iteration 2: Foundation Layer — IN PROGRESS

Per [07-execution-plan.md](07-execution-plan.md), Phase 2 targets:

### Deliverables

| Package | File | Status |
|---------|------|--------|
| **TMCore** | `TextBuffer.swift` — piece table with line index | 🔲 |
| **TMCore** | `UndoManager.swift` — undo/redo with coalescing | 🔲 |
| **TMBundle** | `BundlePlistParser.swift` — plist parser for `.tmLanguage`, `.tmSnippet`, `.tmCommand`, `.tmPreferences` | 🔲 |
| **TMBundle** | `GrammarDefinition.swift` — `.tmLanguage` data model | 🔲 |
| **TMBundle** | `SnippetDefinition.swift` — `.tmSnippet` data model | 🔲 |
| **TMBundle** | `CommandDefinition.swift` — `.tmCommand` data model | 🔲 |
| **TMBundle** | `PreferenceDefinition.swift` — `.tmPreferences` data model | 🔲 |
| **TMSettings** | `TMPropertiesParser.swift` — `.tm_properties` INI parser | 🔲 |
| **TMSettings** | `SettingsResolver.swift` — cascading settings resolution | 🔲 |

### Tests

| Suite | Tests | Status |
|-------|-------|--------|
| TMCoreTests (TextBuffer) | — | 🔲 |
| TMCoreTests (UndoManager) | — | 🔲 |
| TMBundleTests | — | 🔲 |
| TMSettingsTests | — | 🔲 |

### Validation Targets

- Unit tests > 95% coverage for `TMCore`
- Plist parser loads 100% of grammars from TextMate grammar corpus
- `TextBuffer` benchmarks meet or exceed C++ `ng::detail::storage_t`
- `.tm_properties` parser produces identical output to C++ parser

---

## Architecture Reminder

All code follows the iteration strategy from
[01-system-architecture.md](01-system-architecture.md#iteration-strategy):

- **Iteration 1** — Visual Shell ✅
- **Iteration 2** — Foundation Layer (current)
- **Iteration 3** — Core Editor Engine (buffer → editor, syntax highlighting)
- **Iteration 4** — Bundle & Command System
- **Iteration 5** — Advanced Features (snippets, macros, SCM)

## Workflow Rules

- **Always run `swiftformat Sources/ Tests/`** before committing
- **Always run `swift build && swift test`** before pushing
- Target the `swift` branch, not `main`
- Use `macos-latest` runner in CI, not hardcoded versions
