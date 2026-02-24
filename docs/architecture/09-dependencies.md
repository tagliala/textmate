# 09 — Dependencies

## Policy

**Native-first.** Every third-party dependency must be justified. The default
answer is "use the Apple framework or Swift standard library equivalent."

A dependency is only acceptable when **all** of these are true:

1. No native Apple framework or Swift stdlib API provides the functionality
2. Building it from scratch would take > 2 weeks and/or risk correctness
3. The dependency is actively maintained (commit in last 6 months)
4. The dependency has a compatible open-source license
5. The dependency does not pull in transitive dependencies that violate this
   policy

## Approved Dependencies

### 1. Onigmo (Regex Engine)

| Field | Value |
|---|---|
| **What** | Onigmo regular expression library (C) |
| **Source** | Vendored in `vendor/Onigmo/` (existing submodule) |
| **License** | BSD |
| **Why needed** | TextMate grammars use Onigmo-specific regex features (`\p{}` Unicode properties, named captures, backtracking semantics) that Swift's `Regex` (SE-0354) does not fully support. Grammar compatibility requires the exact same regex engine. |
| **Alternative considered** | Swift `Regex` — lacks full Onigmo feature set; would break existing grammars |
| **Integration** | C interop via Swift's C bridging; no Objective-C++ needed |
| **Maintenance** | Already vendored; no external update dependency |
| **Risk** | Low — battle-tested, stable API, already in use |

### 2. MCP Swift SDK

| Field | Value |
|---|---|
| **What** | Official Model Context Protocol SDK for Swift |
| **Source** | `https://github.com/modelcontextprotocol/swift-sdk` (v0.10.0+) |
| **License** | MIT |
| **Why needed** | Implements the full MCP specification (2025-11-25): JSON-RPC protocol, capability negotiation, transport layer (stdio, HTTP/SSE), request batching, task augmentation. Building this from scratch would take 4–6 weeks and risk protocol incompatibility. |
| **Alternative considered** | Hand-rolled JSON-RPC over stdio — feasible but would lag behind spec updates and miss edge cases |
| **Transitive deps** | `swift-system` (Apple), `swift-log` (Apple), `eventsource` (SSE client, macOS only) |
| **Maintenance** | Official SDK maintained by MCP specification authors; active development |
| **Risk** | Medium — pre-1.0 SDK; API may change. Mitigated by wrapping in our `TMMCP` module. |

### 3. SwiftFormat (Development Only)

| Field | Value |
|---|---|
| **What** | Code formatting tool for Swift |
| **Source** | `https://github.com/nicklockwood/SwiftFormat` (v0.59.1) |
| **License** | MIT |
| **Why needed** | Enforces consistent code style across the codebase. The Swift ecosystem does not have a built-in formatter with equivalent configurability. |
| **Alternative considered** | `swift-format` (Apple) — less configurable; does not support tab-based indentation which matches TextMate's existing style |
| **Integration** | CLI tool only; not a build dependency. Installed via Homebrew. |
| **Maintenance** | Actively maintained; supports Swift 6.0–6.4 |
| **Risk** | None — development tool only; does not ship with the application |

## Rejected Dependencies

| Dependency | Reason for Rejection |
|---|---|
| **Boost** | C++ library; replaced by Swift standard library |
| **Cap'n Proto** | Serialization library; replaced by `Codable` + plist/JSON |
| **sparsehash** | C++ hash map; replaced by Swift `Dictionary` |
| **ragel** | State machine compiler; replaced by Swift-native parsers |
| **Sparkle** | Update framework; replaced by native update mechanism |
| **SwiftNIO** | Networking; Foundation's `URLSession` and `NWConnection` suffice |
| **swift-argument-parser** | CLI parsing; `ArgumentParser` is an option but `mate` CLI is simple enough for manual parsing |
| **Any JavaScript runtime** | Explicitly forbidden by project requirements |
| **Any WebView-based rendering** | Explicitly forbidden (except for HTML command output via `WKWebView`, which is a native Apple framework) |

## Transitive Dependency Review

The MCP Swift SDK brings these transitive dependencies:

| Package | Owner | License | Justification |
|---|---|---|---|
| `swift-system` | Apple | Apache 2.0 | System call wrappers; Apple-maintained |
| `swift-log` | Apple | Apache 2.0 | Logging API; Apple-maintained |
| `eventsource` | Third-party | MIT | SSE client for HTTP transport; macOS only |

`eventsource` is the only non-Apple transitive dependency. It is small, focused,
and only used when HTTP transport is enabled. If it becomes unmaintained, the SSE
client can be reimplemented using `URLSession` data tasks (~200 lines).

## Future Dependency Considerations

Before adding any new dependency, open a discussion issue with:

1. What the dependency provides
2. Why no native alternative exists
3. The dependency's maintenance status (last commit, release cadence)
4. License compatibility
5. Transitive dependency tree
6. Risk assessment and mitigation plan
