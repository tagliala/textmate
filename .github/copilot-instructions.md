# TextMate Copilot Instructions

This is the TextMate text editor codebase - a sophisticated macOS text editor with extensible architecture.

Note: this workspace contains the Swift rewrite branch for the TextMate application. The application name remains "TextMate"; these instructions and the code in `Sources/` reflect the Swift-based rewrite (UI-first Iteration 1).

## Project Structure

- **Applications/**: Contains the main TextMate app and helper utilities
- **Frameworks/**: Core C++ and Objective-C++ frameworks providing functionality
- **PlugIns/**: Plugin modules for extensibility
- **Shared/**: Common headers and precompiled headers
- **vendor/**: Third-party dependencies

## Key Technologies

- **Languages**: C++20, Objective-C++, Objective-C
- **Build System**: Ninja (via custom rave build system)
- **Platform**: macOS (minimum 14.0)
- **Architecture**: Framework-based modular design

## Coding Conventions

### C++ Style
- Use tabs for indentation (tabSize = 3)
- Prefer `snake_case` for functions and variables
- Use `PascalCase` for classes and types
- Namespace everything under appropriate namespaces (`ng`, `bundles`, etc.)
- Header guards use format: `FILENAME_H_RANDOMID`

### Memory Management
- Use ARC (Automatic Reference Counting) for Objective-C++
- Follow RAII patterns for C++
- Prefer smart pointers when appropriate

### File Extensions
- `.h` files are treated as Objective-C++ by default
- `.cc` for C++ implementation
- `.mm` for Objective-C++ implementation
- `.m` for Objective-C implementation

## Important Patterns

### Framework Structure
Each framework typically has:
- `src/` directory with headers and implementation
- Public headers exposed through include paths
- Private implementation details hidden

### Bundle System
- TextMate uses a bundle system for extensibility
- Bundles contain commands, snippets, themes, etc.
- Bundle items are queried using scope selectors

### Editor Architecture
- Core editing functionality in `ng` namespace
- Modular design with clipboard, snippets, selection, etc.
- Event-driven architecture with callbacks

### Build System
- Uses custom `rave` build configuration files (`.rave`)
- Ninja backend for actual compilation
- Debug and release configurations available
- Per-framework and per-application build targets

## Key Components

### Core Frameworks
- **editor**: Text editing engine and operations
- **document**: Document model and management
- **bundles**: Bundle loading and querying system
- **selection**: Text selection and ranges
- **regexp**: Regular expression support
- **scm**: Source control integration
- **settings**: Configuration and preferences

### UI Components
- **OakTextView**: Main text editing view
- **DocumentWindow**: Document window management
- **OakAppKit**: Custom AppKit extensions
- **MenuBuilder**: Dynamic menu construction

## Development Guidelines

### Adding New Features
1. Consider which framework should contain the functionality
2. Follow existing patterns for similar features
3. Update appropriate `.rave` build files
4. Add tests in `tests/` subdirectories when applicable

### Working with Bundles
- Bundle items have UUIDs, names, and scope selectors
- Use `bundles::query()` to find relevant items
- Commands can transform text, show output, etc.

### Text Processing
- Use `ng::ranges_t` for text selections
- Text transformations follow functional patterns
- Support for snippets with placeholder expansion

### Platform Integration
- Heavy use of Foundation and AppKit frameworks
- Custom Objective-C++ wrappers for C++ functionality
- Native macOS UI patterns and behaviors

## Testing
- Uses CxxTest framework for unit testing
- Test files follow `t_*.{cc,mm}` pattern
- GUI tests use `gui_*.mm` pattern
- Run tests with `ninja <framework>/test`

## Build Commands
- `./configure && ninja TextMate/run` - Build and launch TextMate
- `ninja TextMate` - Build TextMate without launching
- `ninja <framework>/test` - Run tests for specific framework
- `ninja -t clean` - Clean build artifacts

## Swift Rewrite Validation Policy

For changes under `Sources/` and `Tests/` (Swift rewrite), maintain a **warning-free** build:

- Do **not** introduce compilation warnings in production code (`Sources/**`).
- Do **not** introduce compilation warnings in test code (`Tests/**`).
- If formatting or linting introduces warnings/errors, fix them before finalizing changes.

### Post-Format Checklist (Swift)

Run this sequence exactly after Swift edits:

1. `swiftformat Sources/**/*.swift Tests/**/*.swift`
2. `rm -rf .build && swift build --build-tests`
3. Check diagnostics: ensure no `warning:` and no `error:` in build output
4. `swift test`
5. If issues appear, make one focused fix pass, then rerun steps 2-4

Reference command block:

```bash
swiftformat Sources/**/*.swift Tests/**/*.swift
rm -rf .build && swift build --build-tests 2>&1 | tee /tmp/swift_build_buildtests.txt
grep -n "warning:" /tmp/swift_build_buildtests.txt || echo "No warnings"
grep -n "error:" /tmp/swift_build_buildtests.txt || echo "No errors"
swift test
```

When contributing to TextMate, maintain the existing architectural patterns, follow the established coding style, and ensure changes integrate well with the bundle and framework system.
