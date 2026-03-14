# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OllamaBar is a macOS 14+ menu bar app built with SwiftUI and Xcode. It acts as a transparent HTTP proxy (NWListener on port 11435 → Ollama on port 11434), counts tokens from streaming NDJSON responses, and surfaces 6 analytics features in a menu bar popover.

## Commands

```bash
# Regenerate Xcode project
xcodegen generate

# Build
xcodebuild -scheme OllamaBar -configuration Debug build

# Run all tests
xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64'

# Run a single test class
xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
  -only-testing:OllamaBarTests/ClassName

# Run a single test method
xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
  -only-testing:OllamaBarTests/ClassName/testMethodName

# Release build
xcodebuild -scheme OllamaBar -configuration Release build
```

## Architecture

Three core layers owned by `AppViewModel` (`@Observable @MainActor`):

**Proxy layer** (`OllamaBar/Proxy/`) — non-isolated (no `@MainActor`):
- `ProxyServer` — `NWListener` on port 11435; creates `ProxyConnection` per request
- `ProxyConnection` — accumulates HTTP request, checks `BudgetSnapshot`, forwards to Ollama via `URLSession`, tees response to `NDJSONParser`
- `NDJSONParser` — line-by-line NDJSON parser watching for `done:true` chunks; extracts `prompt_eval_count` + `eval_count`

**Store layer** (`OllamaBar/Store/`) — `@MainActor`:
- `UsageStore` — append-only `[UsageRecord]`; computes all aggregates (totals, breakdowns, heatmap, burn rate, efficiency)
- `SettingsStore` — `Settings` codable; auto-persists on `didSet`
- `PersistenceManager` — serial `DispatchQueue` JSON writes to `applicationSupportDirectory/OllamaBar/`

**View layer** (`OllamaBar/Views/`) — all views receive `AppViewModel` via `.environment`

## Key Design Decisions

- `ProxyServer` and `ProxyConnection` are **non-isolated** — `NWListener`/`NWConnection` callbacks fire on internal queues; `@MainActor` would cause Swift 6 strict-concurrency errors
- `BudgetSnapshot` is a **value type** shared between `ProxyServer` (non-isolated) and `AppViewModel` (`@MainActor`) without actor hops — safe because it's a `struct` copy
- Token field names: `prompt_eval_count` and `eval_count` — same in both `/api/generate` and `/api/chat` `done:true` terminal chunks
- Heatmap uses **equal-range** color levels: `maxTokens/4` intervals, evaluated highest-to-lowest
