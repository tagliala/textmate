# 08 — Testing Strategy

## Philosophy

Every module is tested from day one. Tests are not an afterthought — they are
a prerequisite for merging code. The project uses Apple's
[Swift Testing](https://github.com/swiftlang/swift-testing) framework, which is
built into Swift 6.0+ and ships with Xcode 16+.

## Framework: Swift Testing

Swift Testing is chosen over XCTest because:

- **Expressive API:** `@Test`, `#expect`, `@Suite` are clearer than `XCTAssert*`
- **Built-in parametrized tests:** Test the same logic across many inputs
- **Traits:** `.enabled(if:)`, `.tags()`, `.timeLimit()` for fine control
- **Parallel by default:** Tests run concurrently, catching concurrency bugs
- **No third-party dependency:** Ships with the Swift toolchain

### Example (already in the codebase)

```swift
import Testing
@testable import TMCore

@Suite("TextPosition")
struct TextPositionTests {
    @Test("zero position has all fields at zero")
    func zeroPosition() {
        let pos = TextPosition.zero
        #expect(pos.line == 0)
        #expect(pos.column == 0)
        #expect(pos.offset == 0)
    }

    @Test("positions compare by offset")
    func comparison() {
        let a = TextPosition(line: 0, column: 0, offset: 10)
        let b = TextPosition(line: 1, column: 0, offset: 20)
        #expect(a < b)
    }
}
```

## Test Categories

| Category | What it covers | Location | Run frequency |
|---|---|---|---|
| **Unit tests** | Individual types, functions, algorithms | `Tests/<Module>Tests/` | Every commit |
| **Integration tests** | Module interactions (e.g., grammar + theme) | `Tests/IntegrationTests/` | Every commit |
| **Compatibility tests** | Grammar/snippet/command parity with C++ TextMate | `Tests/CompatibilityTests/` | Every commit |
| **Performance tests** | Benchmarks for critical paths | `Tests/BenchmarkTests/` | Every merge to main |
| **UI tests** | Accessibility, input methods, visual regression | `UITests/` | Nightly / pre-release |

## Coverage Targets

| Module | Target | Rationale |
|---|---|---|
| `TMCore` | ≥ 95% | Foundation of the editor; correctness is critical |
| `TMEditor` | ≥ 90% | Complex action logic; many edge cases |
| `TMGrammar` | ≥ 90% | Grammar parsing must be identical to current TextMate |
| `TMTheme` | ≥ 85% | Style resolution is relatively straightforward |
| `TMBundle` | ≥ 85% | Plist parsing with well-defined formats |
| `TMSettings` | ≥ 90% | Settings hierarchy has subtle precedence rules |
| `TMBundleRuntime` | ≥ 80% | Command execution involves subprocess I/O |
| `TMMCP` | ≥ 80% | Protocol handling with async sequences |
| UI modules | ≥ 60% | UI testing is harder; rely on manual + UI tests |

## Compatibility Test Suite

The highest-risk area is grammar parsing fidelity. A dedicated compatibility test
suite compares the output of the new Swift parser against the existing C++ parser
for a corpus of real-world files:

1. **Grammar corpus:** 50+ language grammars from the TextMate bundle ecosystem
2. **Test files:** Representative source files for each language
3. **Comparison method:** Parse each file with both engines; compare scope
   assignments token-by-token
4. **Automation:** Scope assignments from the C++ engine are serialized as
   expected output files; the Swift engine's output is compared against them

## Running Tests

```sh
# All tests
swift test

# Specific module
swift test --filter TMCoreTests

# Specific test
swift test --filter TMCoreTests.TextPositionTests

# With verbose output
swift test --verbose
```

## Linting

[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (v0.59.1+) enforces
code style. Configuration is in `.swiftformat` at the repository root.

```sh
# Check (CI mode)
swiftformat --lint Sources/ Tests/

# Auto-fix
swiftformat Sources/ Tests/
```

SwiftFormat is chosen because:
- Actively maintained (v0.59.1 as of Feb 2026, supports Swift 6.0–6.4)
- Configurable to match TextMate's existing coding style (tabs, tabWidth 3)
- Fast execution; suitable for pre-commit hooks and CI
- No third-party runtime dependency (standalone binary)

## CI Integration

GitHub Actions (`ci.yml`) runs on every push and PR:

1. **Build** (debug + release)
2. **Test** (all test targets)
3. **Lint** (SwiftFormat check)

See `.github/workflows/ci.yml` for the workflow definition.

## Pre-Commit Hook (Optional)

Developers can install a git pre-commit hook to lint before committing:

```sh
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
swiftformat --lint Sources/ Tests/
EOF
chmod +x .git/hooks/pre-commit
```
