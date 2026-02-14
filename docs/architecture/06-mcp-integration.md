# 06 — MCP Integration

## Overview

MCP (Model Context Protocol) is integrated as a **core service** in the Service
Layer, using the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
(v0.10.0+, Swift 6.0+). This is the only third-party dependency for MCP — it
provides the protocol implementation, transport layer, and JSON-RPC handling.

The integration targets MCP specification **2025-11-25** (latest), which includes
task augmentation, structured content, audio content, and request batching.

See [09-dependencies.md](09-dependencies.md) for the dependency justification.

## Architecture

```
┌──────────────────────────────────────────────┐
│              Application Layer               │
│     MCPPanel · MCPPermissionSheet            │
├──────────────────────────────────────────────┤
│              Service Layer                   │
│  ┌────────────────────────────────────────┐  │
│  │           MCPService                   │  │
│  │  ┌─────────┐  ┌──────────────────┐    │  │
│  │  │ MCP SDK  │  │ MCPTransport     │    │  │
│  │  │ Client   │  │ (Stdio / HTTP)   │    │  │
│  │  └────┬─────┘  └──────────────────┘    │  │
│  │       │                                 │  │
│  │  ┌────▼──────────────────────────────┐ │  │
│  │  │       MCPCapabilityBridge         │ │  │
│  │  │  · DocumentAccess (read/write)    │ │  │
│  │  │  · SelectionAccess (read/write)   │ │  │
│  │  │  · CommandExecution               │ │  │
│  │  │  · BundleQuery                    │ │  │
│  │  │  · DiagnosticsProvider            │ │  │
│  │  │  · WorkspaceNavigation            │ │  │
│  │  └───────────────────────────────────┘ │  │
│  └────────────────────────────────────────┘  │
├──────────────────────────────────────────────┤
│              Core Layer                      │
│  TextBuffer · Editor · Selection · Bundles   │
└──────────────────────────────────────────────┘
```

## MCP SDK Usage

The official MCP Swift SDK provides:

- **`Client`**: Connects to MCP servers, handles protocol negotiation
- **`StdioTransport`**: For local subprocess MCP servers
- **`HTTPClientTransport`**: For remote MCP servers (with Server-Sent Events)
- **Request batching**: `client.withBatch { }` for sending multiple requests
- **Capability negotiation**: Automatic capability checking
- **Structured tool calling**: Type-safe tool invocation

```swift
import MCP

let client = Client(name: "TextMate", version: "3.0.0")
let transport = StdioTransport()
let result = try await client.connect(transport: transport)

// Check capabilities
if result.capabilities.tools != nil {
    let (tools, _) = try await client.listTools()
}
```

## Design Principles

1. **Sandboxed access:** MCP servers run as external processes. Communication
   over stdio or HTTP. No direct memory access to editor state.

2. **Capability-based permissions:** Each MCP connection scoped to explicitly
   granted capabilities. Users approve per-server via a permission sheet.

3. **Read/write separation:** Document read and write access are separate
   capabilities. An MCP server can be read-only.

4. **Concurrency:** MCP operations are `async` functions. Streaming uses
   `AsyncSequence`. All operations dispatched to `MCPServiceActor`.

5. **Integration points:**
   - Document model: read buffer contents, get/set selections, insert text
   - Selection and cursor: observe changes, programmatically set cursors
   - Commands and macros: invoke bundle commands, execute macro sequences
   - Bundle execution: query bundles, trigger commands
   - Diagnostics: publish inline errors, warnings, hints

6. **Optional but integrated:** MCP compiled in but disabled by default. Users
   enable in Preferences and configure servers. No MCP code executes unless
   enabled.

7. **Trust model:**
   - First-run permission prompt per MCP server
   - Persistent permission storage in user defaults
   - Revocation available in Preferences → MCP
   - Sandboxed: servers cannot access files outside project unless granted

## Transport Options

| Transport | Use Case | SDK Support |
|---|---|---|
| `StdioTransport` | Local MCP servers (most common) | Built-in |
| `HTTPClientTransport` | Remote MCP servers with SSE streaming | Built-in |

## Performance

- **Streaming:** Completions arrive as `AsyncSequence`, inserted incrementally
- **Debouncing:** 100ms before notifying servers of state changes
- **Connection reuse:** Persistent connections per session
- **Timeouts:** Configurable per-server (default: 30s)
- **Background processing:** All protocol handling off `@MainActor`
