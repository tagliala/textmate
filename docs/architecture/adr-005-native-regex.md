# ADR-005: Use Swift-Native Regex Instead of Vendored Onigmo

## Status

**Accepted** — February 2026

## Context

The original C++ TextMate uses [Onigmo](https://github.com/k-takata/Onigmo) (an Oniguruma fork) as its regular expression engine. TextMate grammar files (`.tmLanguage`) were designed around Oniguruma regex syntax.

For the Swift rewrite, we initially created a `COnigmo` SPM target that wrapped the vendored C library via a unity build with unsafe pointer interop. This approach gave ~100% syntax compatibility but introduced significant complexity:

- **14 C source files** (unity build + 10 encoding wrappers + setup) with `unsafeFlags` in the build config
- **Extensive unsafe pointer juggling** (`OpaquePointer`, `UnsafeMutablePointer<regex_t>`, C callback bridging)
- **31 compiler warnings** from the vendored C code
- **Symbol collision issues** between encoding files requiring manual splitting
- **Not concurrency-safe** (global mutable state in C init)

## Decision

**Drop Onigmo. Use `NSRegularExpression` (ICU engine) as the regex backend.**

The `OnigmoPattern` and `OnigmoMatch` types are retained as the API surface for the grammar engine, but their implementation now uses pure Swift + Foundation instead of C interop.

A small translation layer in `OnigmoPattern.translatePattern()` converts the most common Oniguruma-specific constructs to ICU equivalents:

| Oniguruma | ICU Translation | Usage |
|-----------|----------------|-------|
| `\h` | `[\t\p{Zs}]` | Horizontal whitespace |
| `\H` | `[^\t\p{Zs}]` | Non-horizontal whitespace |
| `\v` | `[\n\r\x0B\f\x85\u2028\u2029]` | Vertical whitespace |
| `\R` | `(?:\r\n\|[\n\r...])` | Any line break |
| `\X` | `(?:\P{M}\p{M}*)` | Extended grapheme cluster |

## Consequences

### Positive

- **Pure Swift** — no C code, no unsafe pointers, no `@unchecked Sendable` workarounds for C types
- **Zero build warnings** from the regex layer
- **Simpler SPM graph** — one fewer target, no `cSettings` or `unsafeFlags`
- **Full concurrency safety** — `NSRegularExpression` is thread-safe by design
- **Smaller binary** — no vendored C library (~50 source files eliminated)
- **Better diagnostics** — Swift error messages instead of C compilation errors

### Negative

- **~2-5% of grammar patterns** may use Oniguruma-specific syntax not covered by the translation layer (e.g., `\p{Katakana}` with Oniguruma-specific property names, conditional patterns, absent operators)
- **Potential performance difference** — ICU regex may be slower or faster than Onigmo for specific patterns; not benchmarked yet
- **`\G` (anchor to previous match)** is not natively supported by ICU. The grammar parser handles `\G` semantics at a higher level (via `patternHasAnchor()` and `state.anchor`), so this does not affect correctness.

### Mitigation

If a grammar pattern fails to compile with ICU, `OnigmoPattern.isValid` returns `false` and the pattern is silently skipped (matching the C++ behavior for invalid patterns). This degrades gracefully — the grammar still works, it just won't highlight the specific construct that used an unsupported Oniguruma feature.

If significant compatibility issues surface during testing with real-world grammars, Onigmo can be re-introduced as an **optional fallback** behind a feature flag, rather than the primary engine.

## Alternatives Considered

1. **Keep Onigmo as primary engine** — rejected due to maintenance burden and unsafe code
2. **Swift 5.7+ `Regex` type** — considered, but `NSRegularExpression` has better ICU coverage and `NSTextCheckingResult.range(withName:)` for named captures. May revisit when Swift Regex matures further.
3. **tree-sitter** — different parsing paradigm entirely; TextMate grammars are regex-based, so this would require replacing the grammar format too
