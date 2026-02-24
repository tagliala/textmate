# Building TextMate (Swift Rewrite)

## Requirements

- **macOS 26.2** or later
- **Xcode 26.2** or later (ships with Swift 6.2)
- Alternatively: Swift 6.2+ toolchain from [swift.org](https://swift.org/install/)

## Quick Start

Build, test, and lint with a single command:

```sh
swift build && swift test && swift format lint --strict --recursive Sources/ Tests/
```

## Build

```sh
# Debug build (default)
swift build

# Release build
swift build -c release
```

## Test

```sh
# Run all tests
swift test

# Run a specific test suite
swift test --filter TMCoreTests

# Run a single test
swift test --filter TMCoreTests.TextPositionTests
```

## Lint

The project uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) for
code style enforcement. Configuration lives in `.swiftformat` at the repository
root.

```sh
# Check formatting (CI mode — fails on violations)
swift format lint --strict --recursive Sources/ Tests/

# Auto-fix formatting
swift format --recursive Sources/ Tests/
```

To install SwiftFormat locally:

```sh
brew install swiftformat
```

Then you can also run:

```sh
# Check with swiftformat
swiftformat --lint Sources/ Tests/

# Auto-fix with swiftformat
swiftformat Sources/ Tests/
```

## Project Structure

```
Package.swift              # Swift Package Manager manifest
Sources/
  TMCore/                  # Core types: TextPosition, TextRange, SelectionState
Tests/
  TMCoreTests/             # Tests using Swift Testing framework (@Test, #expect)
.swiftformat               # SwiftFormat configuration
.github/workflows/
  ci.yml                   # CI: build + test + lint on every push/PR
  release.yml              # Release: build executables and upload artifacts
```

## CI / CD

GitHub Actions workflows are provided:

- **CI** (`ci.yml`): Runs on every push and pull request. Builds the project,
  runs all tests, and checks formatting.
- **Release** (`release.yml`): Triggered on version tags (`v*`). Builds a
  release binary and uploads it as a GitHub release artifact.

## Architecture

See `docs/architecture/` for the full architectural roadmap documentation.
