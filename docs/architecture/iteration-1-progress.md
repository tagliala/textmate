# Iteration 1: Visual Shell — Session Progress

> Last updated: 2026-02-14

## Completed

### Packages & Source Files

| Package | File | Status |
|---------|------|--------|
| **TMCore** | `TextPosition.swift`, `TextRange.swift`, `SelectionState.swift` | ✅ Pre-existing |
| **TMTheme** | `ThemeColor.swift`, `ThemeStyleRule.swift` | ✅ Pre-existing |
| **TMTheme** | `Theme.swift` — global/gutter settings, `isDark`, `effectiveAppearance` | ✅ Pre-existing |
| **TMTheme** | `ThemeLoader.swift` — `.tmTheme` plist parser | ✅ Pre-existing |
| **TMAppKit** | `TabBarView.swift` — tab buttons, selection, close, drag-to-reorder | ✅ Updated |
| **TMAppKit** | `StatusBarView.swift` — line/col, grammar, encoding labels | ✅ Pre-existing |
| **TMAppKit** | `GutterView.swift` — line numbers, theme-aware colors | ✅ Pre-existing |
| **TMAppKit** | `FileBrowserView.swift` — `NSOutlineView` file tree, icons | ✅ Pre-existing |
| **TMDocumentWindow** | `DocumentWindowController.swift` — layout, save/open, theme | ✅ Updated |
| **TMDocumentWindow** | `DocumentModel.swift` — file I/O, encoding detection, BOM | ✅ New |
| **TMApp** | `KeyBindingsLoader.swift` — plist loader + event parsing | ✅ Updated |
| **TMApp** | `MainMenuBuilder.swift` — all 10 menus with shortcuts | ✅ Updated |
| **TMApp** | `AppDelegate.swift` — lifecycle, theme load, key bindings, window state | ✅ Updated |
| **TMApp** | `main.swift` — entry point | ✅ Pre-existing |
| **TMApp** | `Resources/Mac Classic.tmTheme` — bundled default theme | ✅ New |
| **TMApp** | `Resources/KeyBindings.dict` — bundled key bindings | ✅ New |
| **CI** | `.github/workflows/swift.yml` — lint → build → test pipeline | ✅ New |

### Tests

| Suite | Tests | Status |
|-------|-------|--------|
| TMCoreTests (TextPosition, TextRange, SelectionState) | 18 | ✅ Pass |
| TMThemeTests (ThemeColor, ThemeLoader) | 15 | ✅ Pass |
| TMDocumentWindowTests (DocumentModel) | 9 | ✅ Pass |
| **Total** | **42** | **✅ All pass** |

### Build & Lint

- `swift build` — clean build ✅
- `swift test` — 42/42 pass ✅
- `swiftformat Sources/ Tests/` — 0 files need formatting ✅

---

## Remaining Work for Iteration 1

These items are needed to fully complete Phase 1 (Visual Shell) per
[07-execution-plan.md](07-execution-plan.md):

### High Priority — ✅ All done

1. ~~**Load a real `.tmTheme` on launch**~~ ✅
   - Bundled "Mac Classic.tmTheme" in app resources
   - `AppDelegate` calls `ThemeLoader.load()` and `applyTheme()` on every window

2. ~~**File open/save with encoding detection**~~ ✅
   - `DocumentModel` with BOM detection (UTF-8, UTF-16 BE/LE, UTF-32)
   - Fallback encoding chain: UTF-8 → ISO Latin 1 → Windows 1252 → Mac Roman → EUC-JP → Shift JIS
   - `DocumentWindowController.openFile(at:)` and `saveDocument()` / `saveDocumentAs()`
   - Menu items wired to `AppDelegate.saveDocument(_:)` / `saveDocumentAs(_:)`

3. ~~**Window state restoration**~~ ✅
   - `UserDefaults`-based persistence of open document URLs
   - Restored on next launch; falls back to new untitled document

4. ~~**Tab bar drag reordering**~~ ✅
   - `TabButton` implements `NSDraggingSource` with `mouseDragged` threshold
   - `TabBarView` implements `draggingEntered`/`draggingUpdated`/`performDragOperation`
   - Model reordering + selection tracking + delegate notification

5. ~~**Wire `KeyBindingsLoader` into the responder chain**~~ ✅
   - `parseEvent(_:)` converts `NSEvent` to TextMate key notation
   - `NSEvent.addLocalMonitorForEvents` dispatches matched bindings to first responder

6. ~~**CI pipeline**~~ ✅
   - `.github/workflows/swift.yml` targeting `swift` branch
   - Steps: `swiftformat --lint` → `swift build` → `swift test`
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
