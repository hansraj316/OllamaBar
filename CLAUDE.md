# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OllamaBar is a macOS 14+ menu bar app built with SwiftUI and Xcode. It acts as a transparent streaming HTTP proxy (NWListener on port 11435 → Ollama on port 11434), counts tokens from streaming NDJSON / SSE responses, monitors Ollama's own management endpoints, and surfaces the results in a four-tab menu bar popover (Overview, Models, Activity, Settings).

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
- `ProxyServer` — `NWListener` on port 11435; creates `ProxyConnection` per request; exposes `onRecord`, `onBlocked`, `onReady`, `onError`
- `ProxyConnection` — accumulates the HTTP request (any method/path), applies `BudgetPolicy`, forwards to Ollama through a `URLSession` with itself as `URLSessionDataDelegate`, and relays each received chunk to the client with `Transfer-Encoding: chunked` while feeding it to `NDJSONParser`. Records `durationMs`.
- `NDJSONParser` — byte-buffering line parser; understands native `done:true` chunks (`prompt_eval_count` + `eval_count`) and OpenAI-compatible `usage` objects on plain or `data:`-prefixed SSE lines. `ClientAppParser` maps User-Agent strings to app names.

**Store layer** (`OllamaBar/Store/`) — `@MainActor`:
- `UsageStore` — append-only `[UsageRecord]`; computes all aggregates (totals, ranged breakdowns via `UsageRange`, daily totals, heatmap, streak, burn rate, efficiency, speed)
- `SettingsStore` — `Settings` codable; auto-persists on `didSet`. `Settings.init(from:)` is tolerant so new keys default when loading older files.
- `PersistenceManager` — serial `DispatchQueue` JSON writes to `applicationSupportDirectory/OllamaBar/`
- `OllamaMonitor` — polls `/api/version`, `/api/ps`, `/api/tags` every 20 s; can unload a model with `keep_alive: 0`
- `UsageExporter` — CSV/JSON export; `BudgetNotifier` — 80%/100% notifications via `UserNotifications`

**View layer** (`OllamaBar/Views/`) — all views receive `AppViewModel` via `.environment`
- `MenuBarPopover` — header, tab bar, footer; hosts `OverviewTab`, `ModelsTab`, `ActivityTab`, `SettingsView`
- `Theme` — colour tokens (`input` indigo, `output` teal, status hues), `.card()` modifier, `SectionLabel`, `StatusPill`, `Chip`, `StatTile`, `Format` helpers
- `TrendChartView` uses Swift Charts; `HeatmapView` uses `Canvas`
- `GaugeStripView` / `GaugeStripController` — optional floating `NSPanel` (borderless, non-activating, `.floating` level) pinned to the right screen edge showing `AppViewModel.edgeGauges` rings; toggled by `Settings.showEdgeGauges`
- The popover is always dark (`Theme.ink` + `.preferredColorScheme(.dark)`); usage bars and rings move mint → lime → hot via `Theme.usageColor`

## Key Design Decisions

- `ProxyServer` and `ProxyConnection` are **non-isolated** — `NWListener`/`NWConnection` callbacks fire on internal queues; `@MainActor` would cause Swift 6 strict-concurrency errors
- `BudgetSnapshot` is a **value type** shared between `ProxyServer` (non-isolated) and `AppViewModel` (`@MainActor`) without actor hops — safe because it's a `struct` copy
- `BudgetPolicy` only blocks **POST to generation endpoints** (`/api/generate`, `/api/chat`, `/api/embed*`, `/v1/*completions`, `/v1/embeddings`); `/api/tags`, `/api/ps`, pulls etc. always pass so clients keep working when a hard cap is hit
- Token field names: `prompt_eval_count` and `eval_count` — same in both `/api/generate` and `/api/chat` `done:true` terminal chunks; OpenAI-compatible responses use `usage.prompt_tokens` / `usage.completion_tokens`
- `OllamaMonitor.unload` and health polling talk to Ollama **directly**, never through the proxy, so they are never counted as usage
- `UNUserNotificationCenter` and `SMAppService` are only touched when `Bundle.main` is a real `.app` (guards keep unit tests and previews from crashing)
- Heatmap uses **equal-range** color levels: `maxTokens/4` intervals, evaluated highest-to-lowest
