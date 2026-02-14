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
| **Key bindings** | AppKit key binding mechanism (NSTextInputClient) | ✅ Full |
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
| Grammar parsing divergence | **High** | Test suite comparing output for 50+ languages |
| Snippet behavior differences | **Medium** | Port existing test cases + edge-case tests |
| Command environment differences | **Medium** | Automated comparison of TM_* variables |
| Performance regression (large files) | **Medium** | Benchmark suite for 1MB–100MB files |
| Scope selector matching differences | **High** | Port scope selector tests + fuzzing |
| Theme rendering differences | **Low** | Visual comparison via screenshot diffing |
| `tm_dialog2` incompatibility | **Medium** | Document breaking changes; migration guide |
