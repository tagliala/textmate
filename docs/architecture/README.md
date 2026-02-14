# TextMate Swift Rewrite — Architecture Documentation

This directory contains the strategic roadmap for a complete rewrite of TextMate
as a modern macOS application written entirely in Swift, targeting **macOS 26.2+**
with **Swift 6.2+**.

## Documents

| # | Document | Description |
|---|----------|-------------|
| 01 | [System Architecture](01-system-architecture.md) | Layers, modules, core abstractions, document model |
| 02 | [Rendering & Text Engine](02-rendering-engine.md) | NSTextView evaluation, incremental layout, syntax highlighting |
| 03 | [Compatibility](03-compatibility.md) | Feature mapping, migration strategy, breaking changes |
| 04 | [Performance](04-performance.md) | Concurrency model, caching, profiling, startup optimization |
| 05 | [Bundle & Plugin System](05-bundle-system.md) | Bundle loading, command execution, security, Swift extension API |
| 06 | [MCP Integration](06-mcp-integration.md) | Model Context Protocol architecture and integration |
| 07 | [Execution Plan](07-execution-plan.md) | Phased implementation plan with goals, risks, deliverables |
| 08 | [Testing Strategy](08-testing-strategy.md) | Testing philosophy, frameworks, coverage targets, CI |
| 09 | [Dependencies](09-dependencies.md) | Third-party dependency policy, justified dependencies |

## Key Decisions

- **Language:** Swift 6.2+ (strict concurrency, `Sendable` enforcement)
- **Minimum OS:** macOS 26.2
- **Build system:** Swift Package Manager
- **Testing:** Swift Testing framework (`@Test`, `#expect`)
- **Linting:** SwiftFormat
- **CI/CD:** GitHub Actions
- **Third-party policy:** Native-first; every dependency requires justification

## Relationship to Existing Codebase

The existing C++/Objective-C++ codebase in `Applications/`, `Frameworks/`,
`PlugIns/`, `vendor/`, and `Shared/` remains untouched. The Swift rewrite lives
in `Sources/` and `Tests/` alongside it. The two codebases share the repository
during the transition period.

Submodules (`bin/CxxTest`, `Applications/TextMate/icons`, `PlugIns/dialog`,
`PlugIns/dialog-1.x`, `vendor/Onigmo/vendor`, `vendor/kvdb/vendor`,
`Applications/SyntaxMate/resources/SyntaxMate.tmBundle`) are preserved and
unmodified.
