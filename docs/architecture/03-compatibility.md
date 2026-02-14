# 03 — Compatibility Strategy

## Feature Mapping: Current → New

| Current Feature | New Architecture | Compatibility |
|---|---|---|
| **Bundles (.tmbundle)** | `TMBundle` loads `.tmbundle` directories | ✅ Full |
| **Language grammars (.tmLanguage)** | `TMGrammar` parses plist grammars | ✅ Full |
| **Themes (.tmTheme)** | `TMTheme` loads plist themes | ✅ Full |
| **Snippets (.tmSnippet)** | `TMEditor` snippet engine | ✅ Full |
| **Commands (.tmCommand)** | `TMBundleRuntime` executes commands | ✅ Full |
| **Macros (.tmMacro)** | `TMEditor` macro recording/playback | ✅ Full |
| **Preferences (.tmPreferences)** | `TMSettings` loads plist preferences | ✅ Full |
| **Settings (.tm_properties)** | `TMSettings` parses with identical semantics | ✅ Full |
| **Environment variables (TM_*)** | `TMBundleRuntime` provides identical vars | ✅ Full |
| **Key bindings & shortcuts** | AppKit key binding mechanism (NSTextInputClient) — **must be identical** | ✅ Full |
| **Scope selectors** | `TMGrammar` scope selector matching | ✅ Full |
| **Find & Replace (regex)** | Onigmo regex engine (identical) | ✅ Full |
| **Project/folder search** | Reimplemented with same UI patterns | ✅ Full |
| **File browser** | Reimplemented using AppKit/SwiftUI | ✅ Full |
| **SCM integration (git badges)** | Reimplemented using native git | ✅ Full |
| **HTML output (commands)** | WKWebView for command HTML output | ✅ Full |
| **`rmate` server** | Reimplemented using Foundation networking | ✅ Full |
| **`mate` CLI** | Reimplemented in Swift | ✅ Full |
| **QuickLook generator** | Reimplemented as QuickLook extension | ✅ Full |
| **Dialog plugin (dialog 1.x/2.x)** | Native Swift UI replacement | ⚠️ Partial |
| **Authorization/privileged helper** | SMAppService (modern API) | ⚠️ Partial |
| **License system** | Removed — open-source application | ❌ Dropped |
| **Sparkle-based updates** | Native update mechanism or App Store | ❌ Redesigned |
| **Custom crash reporter** | MetricKit / native crash reporting | ❌ Redesigned |
| **Cap'n Proto serialization** | Replaced with Codable + plist/JSON | ❌ Redesigned |
| **Boost dependency** | Swift standard library equivalents | ❌ Removed |
| **sparsehash dependency** | Swift Dictionary | ❌ Removed |
| **ragel state machines** | Swift-native parsers | ❌ Removed |
| **Custom build system (rave/ninja)** | Swift Package Manager + Xcode | ❌ Removed |

## Summary

| Level | Count | Description |
|---|---|---|
| ✅ Full | 20 | Identical behavior, automatic migration |
| ⚠️ Partial | 2 | Behavior preserved with minor changes |
| ❌ Dropped/Redesigned | 7 | Legacy infra replaced with modern equivalents |

## Partial Compatibility Details

### Dialog Plugin (1.x / 2.x)

The current dialog plugin uses `tm_dialog`/`tm_dialog2` for showing UI from
bundle commands. The new architecture replaces this with:

- A JSON-based dialog specification format
- A native Swift dialog renderer
- A compatibility shim for standard `tm_dialog2` controls

Legacy nibs referenced by existing bundles will not render identically. Bundles
using standard controls (text fields, checkboxes, popups) will work. Bundles with
custom nibs will need updating.

### Privileged Helper

The current `PrivilegedTool` uses the deprecated `SMJobBless` API. The new
architecture uses `SMAppService` (modern replacement available since macOS 13).

## Keyboard Shortcuts

**Keyboard shortcuts MUST be preserved identically.** This is a non-negotiable
requirement. TextMate users have deep muscle memory for its shortcuts, and any
deviation is a migration blocker.

### Sources of Key Bindings

Keyboard shortcuts come from multiple sources, loaded in this priority order
(highest priority first):

1. **User key bindings** — `~/Library/Application Support/TextMate/KeyBindings.dict`
2. **Application key bindings** — `TextMate.app/Contents/Resources/KeyBindings.dict`
3. **User system key bindings** — `~/Library/KeyBindings/DefaultKeyBinding.dict`
4. **System key bindings** — `/Library/KeyBindings/DefaultKeyBinding.dict`
5. **AppKit standard key bindings** — `AppKit.framework/Resources/StandardKeyBinding.dict`
6. **Bundle key equivalents** — Per-bundle item `keyEquivalent` fields

### Implementation Requirements

- The application **must** load and honor `KeyBindings.dict` files using the
  same plist format and key notation as the current TextMate (modifiers:
  `^` Control, `~` Option, `$` Shift, `@` Command, `#` Numeric Pad).
- All actions referenced in `KeyBindings.dict` (e.g., `moveSubWordLeft:`,
  `selectCurrentScope:`, `changeCaseOfWord:`, `reformatText:`) must be
  implemented and wired to the same selectors.
- Bundle item key equivalents must work identically — the same bundle item must
  trigger from the same shortcut.
- Menu key equivalents must match the current menu structure exactly.
- Tab-switching shortcuts (`⌘1`–`⌘8`, `⌘9` for last tab) must be preserved.

### Validation

- Automated test comparing all resolved key bindings from the current TextMate
  against the new application.
- The `BundleItemChooser` (or its equivalent) must show the same key bindings
  list as the current version.
- Manual testing of all shortcuts defined in `KeyBindings.dict` (currently ~30
  custom bindings).

## Migration Strategy

### Settings Migration

On first launch, the application:

1. Detects existing settings in `~/Library/Application Support/TextMate`
2. Presents a migration dialog
3. Copies and converts preferences, key bindings, font/theme selections
4. Preserves the original directory (no deletion)
5. Records migration version to prevent re-migration

### Bundle Migration

Existing bundles require **no migration**. The new bundle loader reads
`.tmbundle` directories with identical semantics. User bundles in
`~/Library/Application Support/TextMate/Bundles` are loaded as-is.

## Legacy Behavior Removal

| Removed Behavior | Justification |
|---|---|
| dialog 1.x nib rendering | Deprecated; no modern equivalent in sandboxed apps |
| SMJobBless privileged helper | Deprecated macOS API |
| Sparkle update framework | Third-party dependency; native alternatives exist |
| Custom crash reporter UI | MetricKit provides superior crash collection |
| Cap'n Proto for IPC | Codable provides sufficient serialization |
| Boost/sparsehash | C++ dependencies with Swift stdlib equivalents |
| Rave/Ninja build system | C++ build infra; Swift Package Manager is standard |

## Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Keyboard shortcut divergence | **Critical** | Load identical `KeyBindings.dict`; automated comparison test |
| Grammar parsing divergence | **High** | Test suite comparing output for 50+ languages |
| Snippet behavior differences | **Medium** | Port existing test cases + edge-case tests |
| Command environment differences | **Medium** | Automated comparison of TM_* variables |
| Performance regression (large files) | **Medium** | Benchmark suite for 1MB–100MB files |
| Scope selector matching differences | **High** | Port scope selector tests + fuzzing |
| Theme rendering differences | **Low** | Visual comparison via screenshot diffing |
| `tm_dialog2` incompatibility | **Medium** | Document breaking changes; migration guide |

## Localization & Theme Scope

### Policy

- **All** user-facing strings in the application must use Swift localization best-practices (for example, `String(localized:comment:)`) so the UI is localizable and translators receive context. Hard-coded English UI strings are prohibited.
- The system appearance (light/dark) determines application chrome (menus, tab bar, gutter, sidebar, status bar, controls). Chrome must use AppKit system colors and respect `effectiveAppearance` rather than being driven by bundle themes.
- `.tmTheme` files (legacy TextMate theme plists) apply **only** to editor content (syntax colors, editor background, insertion point, selection). A theme must not change chrome colors or window appearance.

### Implementation Guidance

- Use `String(localized:comment:)` for all menu titles, control labels, accessibility labels, status text, and any string shown to the user. Add meaningful `comment:` text for translators.
- Chrome components (tab bar, gutter, status bar, file browser) should use AppKit system colors such as `NSColor.labelColor`, `NSColor.secondaryLabelColor`, `NSColor.controlBackgroundColor`, and `NSColor.controlAccentColor` so they automatically follow system appearance.
- `DocumentWindowController.applyTheme(_:)` (or equivalent) must be implemented to modify only the editor `NSTextView` visual properties: `backgroundColor`, `textColor`, `insertionPointColor`, and `selectedTextAttributes`. Do not set `window.appearance` or mutate chrome view colors from theme application.
- When parsing legacy `.tmTheme` files, map their color settings to editor style rules and explicitly ignore any "global" or "ui" chrome color keys; emit a non-fatal logged warning if such keys are present so bundle authors can be notified to migrate.

### Validation and Tests

- Add automated checks to detect hard-coded UI strings in menu-building code and major chrome components. A CI job should fail if new literal UI strings are added without localization.
- Add light/dark snapshot tests for chrome components to ensure the UI follows `effectiveAppearance` across macOS appearances.
- Add editor snapshot tests that confirm `.tmTheme` color mappings affect only the editor view and do not alter chrome elements.

### Accessibility Notes

- All interactive controls must include localized accessibility labels and hints where appropriate (for example, the tab close button `accessibilityLabel`/`accessibilityHelp`).

### Migration Notes

- When migrating user-installed themes, copy their color values into the editor-style model only. If a theme attempted to style chrome in the legacy app, prefer keeping the existing system chrome and notify the user that only editor colors were imported.

