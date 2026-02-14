# 07 — Phased Execution Plan

## Phase 1: Foundation Layer (8 weeks)

**Goals:**
- Establish Swift Package Manager project structure
- Implement core data types: `TextPosition`, `TextRange`, `SelectionState`
- Implement `TextBuffer` (piece table) with full test coverage
- Implement `UndoManager` with coalescing
- Implement plist parser for `.tmLanguage`, `.tmTheme`, `.tmSnippet`,
  `.tmCommand`, `.tmPreferences`
- Set up CI with SwiftFormat linting and Swift Testing

**Risks:**
- Piece table edge cases with Unicode combining characters
- Plist format variations across bundle ecosystem

**Deliverables:**
- `TMCore` package with `TextBuffer`, `SelectionState`, `UndoManager`
- `TMBundle` package with plist parsing (read-only)
- `TMSettings` package with `.tm_properties` parser
- Benchmark suite for `TextBuffer` operations

**Validation:**
- Unit tests > 95% coverage for `TMCore`
- Plist parser loads 100% of grammars from TextMate grammar corpus
- `TextBuffer` benchmarks meet or exceed current `ng::detail::storage_t`
- `.tm_properties` parser produces identical output to current parser

---

## Phase 2: Core Editor Engine (10 weeks)

**Goals:**
- Implement `Editor` with all action types from `ng::editor_t`
- Implement snippet engine (tab stops, placeholders, mirrors, transformations)
- Implement macro recording and playback
- Implement multi-cursor operations
- Implement clipboard management (system, find, replace, yank)
- Implement auto-indent engine and text transformations

**Risks:**
- Snippet nesting and mirror update logic complexity
- Multi-cursor overlapping selection handling

**Deliverables:**
- `TMEditor` package with full editor action support
- Snippet engine passing all ported test cases
- Macro engine supporting record and playback

**Validation:**
- Port all existing editor test cases from C++ suite
- Multi-cursor-specific test cases
- Snippet behavior verified against TextMate specification

---

## Phase 3: Syntax & Language System (8 weeks)

**Goals:**
- Implement TextMate grammar parser (`TMGrammar`)
- Implement scope tree construction and selector matching
- Implement theme loading and style resolution
- Integrate Onigmo regex engine via C interop
- Implement incremental and background parsing

**Risks:**
- Grammar edge cases (recursive includes, injection grammars)
- Onigmo C interop memory management
- Incremental parsing correctness across grammar boundaries

**Deliverables:**
- `TMGrammar` package with grammar parsing and scope assignment
- `TMTheme` package with theme loading and style resolution
- `TMRegExp` package wrapping Onigmo
- Grammar test suite validating against corpus

**Validation:**
- Parse output for 50+ languages matches current TextMate exactly
- Scope selector matching identical to current implementation
- Theme style resolution identical for a test corpus

---

## Phase 4: UI Layer (12 weeks)

**Goals:**
- Custom text rendering engine (CoreText + CALayer)
- `NSTextInputClient` for input handling
- `NSAccessibility` for accessibility
- Gutter view, status bar, document tab bar
- File browser sidebar, find panel
- Preferences window, document window management
- `mate` CLI tool

**Risks:**
- Input method (IME) integration complexity
- Accessibility compliance
- Custom rendering must match native scrolling behavior

**Deliverables:**
- `TMEditorUI`, `TMAppKit`, `TMFileBrowser`, `TMDocumentWindow`, `TMPreferences`
- `TMApp` application target
- `mate` CLI tool

**Validation:**
- Visual comparison against current TextMate
- Input method testing with CJK, emoji, dictation
- VoiceOver accessibility testing
- Scrolling performance: 60fps for 100K-line files

---

## Phase 5: Compatibility Layer (6 weeks)

**Goals:**
- Settings migration from current TextMate
- Command output handling (all output modes)
- HTML output view (WKWebView)
- Dialog compatibility shim
- Environment variable parity
- `rmate` server, QuickLook extension

**Risks:**
- HTML output dependencies on specific WebKit behavior
- Dialog compatibility for nib-based dialogs
- Environment variable edge cases

**Deliverables:**
- Migration assistant, HTML output view, dialog renderer
- `rmate` server, QuickLook extension
- TM_* variable parity test suite

**Validation:**
- Top 50 most-used bundle commands execute correctly
- Settings migration preserves all user preferences
- `rmate` server and QuickLook work correctly

---

## Phase 6: Bundle Execution System (6 weeks)

**Goals:**
- XPC-based command runner (`TMCommandRunner.xpc`)
- Security model (trust levels, permission dialogs)
- Bundle manager (install, update, remove)
- Bundle editor, bundle menu construction, drag commands

**Risks:**
- XPC overhead for high-frequency commands
- Security model vs. workflow compatibility balance

**Deliverables:**
- `TMBundleRuntime` with XPC command runner
- `TMBundleUI` with bundle manager and editor
- Security model with trust levels

**Validation:**
- All shipped bundles execute correctly
- Command latency within 50ms of current TextMate
- Permission dialogs appear correctly

---

## Phase 7: MCP Integration Layer (8 weeks)

**Goals:**
- MCP protocol handling using official MCP Swift SDK
- Server management (start, stop, restart, configure)
- `MCPCapabilityBridge` with all integration points
- Permission model, preferences UI
- Inline completion UI, diagnostics display

**Risks:**
- MCP protocol evolution; version negotiation needed
- Streaming completions and undo model integration
- Security: preventing unauthorized document access

**Deliverables:**
- `TMMCP` package with SDK integration
- MCP preferences pane
- Inline completion UI (ghost text)
- Diagnostics gutter markers

**Validation:**
- Protocol compliance with reference MCP servers
- Streaming completion inserts correctly and is undoable
- Permission model prevents unauthorized access

---

## Phase 8: Performance Hardening (6 weeks)

**Goals:**
- Profile and optimize startup (< 200ms empty, < 500ms project)
- Scrolling performance (60fps for 100K-line files)
- Memory optimization (< 2x file size for documents under 10MB)
- Bundle loading (< 100ms for full index)
- Syntax parsing (< 500ms for 10K-line files)
- Bundle index serialization

**Risks:**
- Structural bottlenecks requiring architectural changes
- Swift ARC overhead in tight loops

**Deliverables:**
- Benchmark results vs. current TextMate
- Optimized bundle index, rendering pipeline
- Memory profiling report
- Performance regression tests in CI

**Validation:**
- All benchmark targets met
- No regressions vs. current TextMate
- CI performance tests pass on every merge

---

## Phase 9: Beta Migration (8 weeks)

**Goals:**
- Public beta with migration assistant
- Collect feedback on compatibility and performance
- Fix regressions, document breaking changes
- Finalize Swift extension API design
- Prepare 1.0 release

**Risks:**
- Undiscovered niche bundle compatibility issues
- Performance on minimum supported hardware
- User resistance to UI changes

**Deliverables:**
- Beta build via TestFlight / website
- Migration guide, known issues list, release notes
- 1.0 release candidate

**Validation:**
- Beta tester feedback collected and triaged
- All critical compatibility issues resolved
- Performance targets met on minimum hardware
- No data loss scenarios identified
