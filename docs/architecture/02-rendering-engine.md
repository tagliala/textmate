# 02 — Rendering & Text Engine Strategy

## NSTextView vs Custom Engine

| Criterion | NSTextView (TextKit 2) | Custom Engine |
|---|---|---|
| Multi-cursor support | Not natively supported | Full control |
| Incremental layout | Supported in TextKit 2 | Full control |
| Large file performance | Adequate with viewport layout | Superior with custom viewport |
| Syntax highlighting | Via NSTextStorage subclass | Direct scope-to-style pipeline |
| Columnar selection | Not supported | Full control |
| Gutter rendering | Not built-in | Full control |
| Code folding | Not built-in | Full control |
| Maintenance burden | Low (Apple-maintained) | High (fully owned) |
| Soft-wrap behavior | Built-in | Must implement |
| Input method (IME) | Built-in | Must integrate NSTextInputClient |
| Accessibility | Built-in | Must implement via NSAccessibility |

**Decision:** Custom rendering engine built on CoreText and CALayer, implementing
`NSTextInputClient` for input handling and `NSAccessibility` for accessibility.

**Justification:** TextMate's differentiators — multi-cursor editing, columnar
selections, code folding, custom gutter rendering, and scope-driven highlighting
— are not well served by NSTextView. The current TextMate already uses a custom
engine (`ng::layout_t` + CGContext drawing).

**Risk mitigation:** Implement `NSTextInputClient` correctly from day one for all
input methods. Implement `NSAccessibility` protocol for accessibility. Both are
stable Apple protocols.

## Incremental Layout Strategy

Layout is organized as an array of `LayoutLine` values:

```swift
struct LayoutLine {
    let lineIndex: Int              // Hard line index in buffer
    let softWrapOffset: Int         // Offset within hard line (0 if not wrapped)
    let origin: CGPoint             // Position in document coordinates
    let height: CGFloat             // Line height (including spacing)
    let ctLine: CTLine              // CoreText line for rendering
    let scopeRuns: [ScopeRun]       // Scope assignments for this line
    let styleRuns: [StyleRun]       // Resolved styles for this line
}
```

**Viewport-based layout:** Only lines visible in the viewport (plus ~50 lines
overscan) are laid out. Scrolling triggers incremental layout of newly visible
lines.

**Invalidation triggers:**

| Trigger | What is invalidated |
|---|---|
| Text edit | Affected hard lines + subsequent soft-wrap calculations |
| Theme change | All style runs (scope runs unchanged) |
| Grammar change | Scope runs from edit point forward (incremental re-parse) |
| Window resize | Soft-wrap calculations for all lines |
| Font change | All CTLine objects |

## Syntax Highlighting Pipeline

```
TextBuffer → GrammarParser → ScopeMap → ThemeResolver → StyledLines → CoreText → CALayer
```

1. **Grammar parsing** (line-by-line, incremental): `parse(line, state) → (scopes, newState)`
2. **Scope resolution:** Map scope stacks to theme styles
3. **Style caching:** Cache scope-to-style mappings in a `Dictionary`

**Incremental parsing:** After an edit, only lines from the edit point forward
are re-parsed, stopping when the parser state at end of line matches the cached
state (indicating no further changes propagate).

**Background parsing:** For large files, initial parsing runs on a background
thread (`Task` with `.userInitiated` priority). The visible viewport is parsed
first.

**Regex engine:** Onigmo is retained via C interop (see
[09-dependencies.md](09-dependencies.md) for justification). Onigmo supports the
full TextMate grammar regex syntax including `\p{}` Unicode properties and named
captures.

## Large File Handling

Files over a configurable threshold (default: 10 MB):

- **Deferred parsing:** Syntax highlighting disabled by default; user can opt in
- **Memory-mapped I/O:** File is memory-mapped rather than fully loaded
- **Viewport-only layout:** Only visible lines are laid out
- **Read-only suggestion:** Files over 100 MB default to read-only

## Memory Optimization

- **Piece table with shared storage:** Original content stored once; edits in
  append-only buffer
- **Scope interning:** Scope strings interned in a global table
- **Style run compression:** Consecutive identical styles share a single entry
- **Off-screen eviction:** CTLine objects far from viewport are released
- **Theme style cache:** Invalidated only on theme change

## Multi-Cursor & Advanced Editing

Multi-cursor editing is first-class:

- `SelectionState` holds an ordered array of `TextRange` values
- Operations apply to all selections simultaneously
- Overlapping selections merge automatically after each operation
- Columnar selection creates one selection per line in the rectangular region
