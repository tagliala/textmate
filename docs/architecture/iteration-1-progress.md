# Iteration 1: Visual Shell — Session Progress

> Last updated: 2026-02-14

## Completed

### Packages & Source Files

| Package | File | Status |
|---------|------|--------|
| **TMCore** | `TextPosition.swift`, `TextRange.swift`, `SelectionState.swift` | ✅ Pre-existing |
| **TMTheme** | `ThemeColor.swift`, `ThemeStyleRule.swift` | ✅ Pre-existing |
| **TMTheme** | `Theme.swift` — global/gutter settings, `isDark`, `effectiveAppearance` | ✅ New |
| **TMTheme** | `ThemeLoader.swift` — `.tmTheme` plist parser | ✅ New |
| **TMAppKit** | `TabBarView.swift` — tab buttons, selection, close, theme | ✅ New |
| **TMAppKit** | `StatusBarView.swift` — line/col, grammar, encoding labels | ✅ New |
| **TMAppKit** | `GutterView.swift` — line numbers, theme-aware colors | ✅ New |
| **TMAppKit** | `FileBrowserView.swift` — `NSOutlineView` file tree, icons | ✅ New |
| **TMDocumentWindow** | `DocumentWindowController.swift` — complete layout | ✅ New |
| **TMApp** | `KeyBindingsLoader.swift` — `KeyBindings.dict` plist loader | ✅ New |
| **TMApp** | `MainMenuBuilder.swift` — all 10 menus with shortcuts | ✅ New |
| **TMApp** | `AppDelegate.swift` — lifecycle, open/save, window mgmt | ✅ New |
| **TMApp** | `main.swift` — entry point | ✅ New |

### Tests

| Suite | Tests | Status |
|-------|-------|--------|
| TMCoreTests (TextPosition, TextRange, SelectionState) | 18 | ✅ Pass |
| TMThemeTests (ThemeColor, ThemeLoader) | 15 | ✅ Pass |
| **Total** | **33** | **✅ All pass** |

### Build & Lint

- `swift build` — clean build ✅
- `swift test` — 33/33 pass ✅
- `swiftformat Sources/ Tests/` — 0 files need formatting ✅

---

## Remaining Work for Iteration 1

These items are needed to fully complete Phase 1 (Visual Shell) per
[07-execution-plan.md](07-execution-plan.md):

### High Priority

1. **Load a real `.tmTheme` on launch**
   - Bundle a default theme (e.g. Mac Classic or Monokai) in the app resources
   - `AppDelegate` should call `ThemeLoader.load()` and `applyTheme()` on the
     initial window

2. **File open/save with encoding detection**
   - `AppDelegate.openDocument` currently loads via `String(contentsOf:)` — add
     `encoding/` framework integration or ICU detection
   - Wire `NSDocument.save`/`saveAs` to write files from `NSTextView.string`

3. **Window state restoration**
   - Persist open windows/tabs/project roots via `NSWindowRestoration`
   - Reopen last session on launch

4. **Tab bar drag reordering**
   - `TabBarView` currently supports select/close but not drag-to-reorder
   - Implement `NSDraggingSource`/`NSDraggingDestination` on `TabButton`

5. **Wire `KeyBindingsLoader` into the responder chain**
   - Load `KeyBindings.dict` at launch and install an `NSEvent.addLocalMonitor`
     or override `performKeyEquivalent:` to dispatch bindings

6. **CI pipeline**
   - GitHub Actions workflow targeting `swift` branch
   - Steps: `swiftformat --lint Sources/ Tests/` → `swift build` → `swift test`
   - Runner: `macos-latest`

### Medium Priority

7. **File browser improvements**
   - Lazy loading for large directory trees
   - `.gitignore` / `.tm_properties` filtering
   - Single-click to open, double-click to keep open (transient tabs)
   - Context menu (New File, New Folder, Reveal in Finder, Delete)

8. **Tab overflow menu**
   - When tabs exceed visible width, show a `»` overflow button with a popup
     listing hidden tabs

9. **Status bar interactivity**
   - Click grammar label → grammar chooser
   - Click tab size → tab size picker
   - Click encoding → encoding picker

10. **Gutter improvements**
    - Fold markers (disclosure triangles) in the gutter
    - Bookmarks (⌘F2) gutter indicators
    - Breakpoint-style click-to-toggle on line numbers

### Low Priority

11. **Info.plist & app icon**
    - Add a proper `Info.plist` for the new app target with bundle ID,
      file type associations (`.txt`, `.md`, etc.), and the TextMate icon

12. **About panel**
    - Wire `About TextMate` to show version, credits, and license

13. **Preferences window stub**
    - Empty preferences window with tabs matching TextMate's layout

---

## Architecture Reminder

All code follows the iteration strategy from
[01-system-architecture.md](01-system-architecture.md#iteration-strategy):

- **Iteration 1** — Visual Shell (current)
- **Iteration 2** — Core Editor Engine (buffer, undo, syntax highlighting)
- **Iteration 3** — Bundle & Command System
- **Iteration 4** — Advanced Features (snippets, macros, SCM)
- **Iteration 5** — Polish & Migration (drop-in replacement)

## Workflow Rules

- **Always run `swiftformat Sources/ Tests/`** before committing
- **Always run `swift build && swift test`** before pushing
- Target the `swift` branch, not `main`
- Use `macos-latest` runner in CI, not hardcoded versions
