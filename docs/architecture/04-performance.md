# 04 — Performance Strategy

## Swift Concurrency Model

The application uses structured concurrency throughout:

| Operation | Concurrency Model |
|---|---|
| File loading | `Task { }` with `.userInitiated` priority |
| Syntax parsing (background) | `Task { }` with `.utility` priority |
| MCP communication | `AsyncSequence` for streaming; `Task` for request/response |
| Command execution | `Task { }` wrapping subprocess I/O |
| Project search | `TaskGroup` for parallel file scanning |
| File watching | `AsyncStream` wrapping `DispatchSource.makeFileSystemObjectSource` |
| UI updates | `@MainActor` for all view state mutations |

### Actor Model

```swift
@MainActor class EditorViewController          // UI and editor state
actor MCPServiceActor                           // MCP connection management
actor BundleIndexActor                          // Bundle loading and querying
actor SearchActor                               // Project-wide search
```

Actors prevent data races. `TextBuffer` is a value type with copy-on-write
semantics, enabling safe passage between actors without locking.

### Swift 6.2 Features Used

- **`Task.immediate`** (SE-0472): For tasks that should run immediately on the
  calling executor when isolation is compatible, avoiding scheduling overhead
- **Isolated deinit** (SE-0471): For actors that need to safely close resources
  during deinitialization
- **Named tasks** (SE-0469): For debugging and identifying tasks in Instruments
- **`nonisolated(nonsending)`** (SE-0461): For async functions that should
  execute on the calling actor, reducing executor hopping
- **Isolated conformances** (SE-0470): For protocol conformances scoped to a
  specific global actor (e.g., `@MainActor`)

## Threading Architecture

```
Main Thread (Main Actor)
├── UI rendering (AppKit, CoreText)
├── User input handling
├── Selection state
└── Editor action dispatch

Background Threads (Cooperative Thread Pool)
├── Syntax parsing
├── File I/O
├── Project search
├── Symbol indexing
├── MCP communication
└── Bundle command execution
```

**Critical rule:** The main thread never performs blocking I/O.

## Caching Strategy

| Cache | Key | Value | Invalidation |
|---|---|---|---|
| Scope-to-style | Scope hash | `StyleAttributes` | Theme change |
| Grammar parse state | Line index | Parser state stack | Text edit (from edit point) |
| CTLine cache | Line index + content hash | `CTLine` | Text edit, font change, resize |
| Bundle index | — | `[BundleItem]` | File system change in bundle paths |
| File type detection | File path + first 1KB | Grammar identifier | Never (immutable input) |
| MCP capability cache | Server identifier | `CapabilitySet` | User permission change |

## Profiling and Benchmarking Plan

A `TMBenchmarks` test suite contains performance tests:

1. **Text insertion/deletion:** Piece table operations for 1K–1M line documents
2. **Syntax parsing:** Time to parse 1K-line files in 10 common languages
3. **Layout computation:** Time from edit to CTLine creation for visible viewport
4. **Scroll performance:** Frame rate during continuous scrolling in 100K-line file
5. **Startup time:** Process launch to first editor ready
   - Target: < 200ms (empty document), < 500ms (restoring a project)
6. **Memory usage:** RSS for documents of various sizes
7. **Bundle loading:** Time to index all installed bundles
8. **Search performance:** Regex search across a 10,000-file project

Benchmarks run in CI on every merge to main. Regressions > 10% trigger a warning.

## Startup Time Optimization

1. **Lazy bundle loading:** Metadata loaded eagerly from serialized cache; full
   content loaded on demand
2. **Serialized bundle index:** Binary-encoded index written to disk; invalidated
   when bundle directory timestamps change
3. **Deferred UI construction:** Preference panes, find panel, bundle editor
   constructed on first access
4. **Session restore:** Window positions and open documents restored from
   serialized session file; only visible documents load immediately
5. **Grammar precompilation:** Top 20 grammars pre-parsed and cached

## Indexing Strategy

**Symbol indexing** proceeds in two phases:

1. **Visible documents:** Symbols indexed synchronously during parsing
2. **Project-wide:** Background `TaskGroup` walks project tree, populating index

The symbol index supports:
- Fuzzy matching for "Go to Symbol"
- Incremental update on file change (via file system events)
- Persistence to disk for fast restoration

## MCP Performance Considerations

- **Streaming responses:** MCP completions arrive as `AsyncSequence<String>`,
  inserted incrementally
- **Request debouncing:** 100ms default before notifying MCP servers of state
  changes
- **Connection pooling:** Persistent MCP connections reused across requests
- **Timeout enforcement:** Configurable timeout (default: 30s); cancelled with
  user notification
- **Background processing:** All MCP protocol handling off main thread
