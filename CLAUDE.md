# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OllamaBar is a Swift command-line executable built with Swift Package Manager. It requires Swift 6.2+.

## Commands

```bash
# Build
swift build

# Run
swift run OllamaBar

# Build release
swift build -c release

# Run tests (once test targets are added)
swift test

# Run a single test
swift test --filter TestSuiteName/testMethodName
```

## Architecture

This is a minimal Swift CLI project with a single executable target. The entry point is `Sources/OllamaBar/OllamaBar.swift`, which defines the `@main` struct.

**Package structure:**
- `Package.swift` — SPM manifest declaring the `OllamaBar` executable target
- `Sources/OllamaBar/` — All source files for the executable

No external dependencies are currently declared. To add dependencies, define them in `Package.swift` under `dependencies:` and reference them in the target's `dependencies:` array, then run `swift package resolve`.
