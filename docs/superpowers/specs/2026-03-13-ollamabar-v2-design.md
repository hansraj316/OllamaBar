# OllamaBar v2 — Design Spec

**Date:** 2026-03-13
**Status:** Approved
**Supersedes:** `2026-03-13-ollamabar-design.md` (chat/digest design — discarded)

---

## Overview

OllamaBar is a macOS 14+ menu bar app that acts as a transparent local proxy for Ollama. It intercepts API calls on port `11435`, forwards them unmodified to Ollama on port `11434`, and counts tokens in real-time by parsing the streaming NDJSON response. Six unconventional features sit on top: budget enforcement, per-model/app breakdown, predictive burn rate, cost estimation, usage heatmap, and efficiency scoring.

**Key constraints:**
- macOS 14.0 minimum
- Pure Swift — no Python dependency
- Xcode project (`.xcodeproj`) — delete existing `Package.swift` and create a new macOS App target
- App Sandbox disabled
- Direct download / notarized DMG

---

## Build Setup

- **Target type:** macOS App (Xcode project — not SPM executable)
- **Migration:** Delete `Package.swift` and `Sources/` directory; create new Xcode project in repo root
- **Info.plist:** `LSUIElement = YES` (suppress Dock icon)
- **Entitlements:**
  ```xml
  <key>com.apple.security.app-sandbox</key><false/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.network.server</key><true/>
  ```
- `network.server` is required for `NWListener` on port 11435

Build: `xcodebuild -scheme OllamaBar -configuration Debug build`
Test: `xcodebuild -scheme OllamaBar -destination 'platform=macOS,arch=arm64' test`

---

## Architecture

### App Entry Point

```swift
@main struct OllamaBarApp: App {
    @State private var viewModel = AppViewModel()
    var body: some Scene {
        MenuBarExtra { MenuBarPopover().environment(viewModel) }
        label: { MenuBarIconView().environment(viewModel) }
        .menuBarExtraStyle(.window)
    }
}
```

### Core Components

| Component | Type | Actor Isolation | Responsibility |
|---|---|---|---|
| `ProxyServer` | `@Observable` class | **Non-isolated** | `NWListener` on port 11435; forwards requests to 11434; delivers completed `UsageRecord` values via closure on main actor |
| `ProxyConnection` | `final class` | **Non-isolated** | Per-connection: HTTP receive loop, URLSession forward, NW send, NDJSONParser |
| `UsageStore` | `@Observable` class | `@MainActor` | Append-only `[UsageRecord]`; computes all aggregates; persists to JSON |
| `SettingsStore` | `@Observable` class | `@MainActor` | Settings codable; persists to JSON |
| `AppViewModel` | `@Observable` class | `@MainActor` | Owns all three; wires `ProxyServer.onRecord` closure to `UsageStore`; provides budget snapshot to `ProxyServer` |

**Why `ProxyServer` and `ProxyConnection` are non-isolated:** `NWListener` and `NWConnection` callbacks fire on their own internal queues. Marking either class `@MainActor` would cause Swift 6 strict-concurrency errors on every NW callback. All UI-bound state updates are dispatched explicitly via `DispatchQueue.main.async {}`.

### ProxyServer ↔ AppViewModel Wiring

`ProxyServer` exposes two closures set by `AppViewModel` at init:

```swift
// Set by AppViewModel; called on main queue when a request completes
var onRecord: ((UsageRecord) -> Void)?

// Called by ProxyServer synchronously on its queue to check the budget.
// AppViewModel keeps a `budgetSnapshot: BudgetSnapshot` struct that ProxyServer
// reads without crossing actor boundaries.
var budgetSnapshot: BudgetSnapshot  // value type — safe to copy across queues
```

```swift
struct BudgetSnapshot {
    let dailyBudgetTokens: Int   // 0 = disabled
    let todayTotalTokens: Int
    let budgetMode: BudgetMode
}
```

`AppViewModel` updates `budgetSnapshot` on the main actor whenever `UsageStore` or `SettingsStore` changes. `ProxyServer` reads it without `await` — it's a value type copy, so there is no data race.

### Request Flow

```
Client → HTTP POST http://localhost:11435/api/generate (or /api/chat)
  → ProxyServer.NWListener accepts → creates ProxyConnection
  → ProxyConnection.start():
      1. Accumulate full HTTP request via NWConnection.receive() loop
         (reads until Content-Length bytes consumed or chunked transfer complete)
      2. Parse User-Agent header from accumulated request
      3. Read budgetSnapshot (value copy — no actor hop needed)
         → if hard limit exceeded: write HTTP/1.1 429, close
      4. Build URLRequest from accumulated bytes; send via URLSession.dataTask
      5. On each data chunk received from URLSession:
         a. Write bytes → NWConnection.send() to client
         b. Feed bytes → NDJSONParser.ingest()
      6. On URLSession completion:
         → NDJSONParser.finalize() returns extracted tokens (or nil if not found)
         → if tokens found: build UsageRecord; call ProxyServer.onRecord on main queue
         → close NWConnection
```

**HTTP request accumulation:** Read `Content-Length` header from the first receive chunk. Then call `NWConnection.receive(minimumIncompleteLength: remaining, maximumLength: remaining)` in a loop until all bytes are buffered. For chunked transfer encoding, read until a zero-length chunk (`0\r\n\r\n`) is seen. This covers all standard Ollama clients.

---

## Data Model

### `UsageRecord`
```swift
struct UsageRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let model: String          // e.g. "llama3.2"
    let clientApp: String      // parsed from User-Agent
    let endpoint: String       // "/api/generate" or "/api/chat"
    let promptTokens: Int      // prompt_eval_count from done:true chunk
    let evalTokens: Int        // eval_count from done:true chunk
}
```

### `TokenPair`
```swift
struct TokenPair: Equatable {
    let prompt: Int
    let eval: Int
    var total: Int { prompt + eval }
}
```

Breakdown computed properties return `[(name: String, tokens: TokenPair)]` sorted descending by `tokens.total` — a concrete array safe for SwiftUI `ForEach` with `\.name` as the stable ID.

### `UsageStore` Aggregates

All derived from `records: [UsageRecord]` (not persisted separately):

| Property | Type | Description |
|---|---|---|
| `todayRecords` | `[UsageRecord]` | Records where timestamp falls on today's calendar day |
| `todayPromptTokens` | `Int` | Sum of promptTokens for today |
| `todayEvalTokens` | `Int` | Sum of evalTokens for today |
| `todayTotalTokens` | `Int` | prompt + eval for today |
| `allTimePromptTokens` | `Int` | All-time sum |
| `allTimeEvalTokens` | `Int` | All-time sum |
| `breakdownByModel` | `[(name: String, tokens: TokenPair)]` | Sorted desc by total |
| `breakdownByApp` | `[(name: String, tokens: TokenPair)]` | Sorted desc by total |
| `heatmapData` | `[Date: Int]` | Total tokens per **start-of-day** `Date`, last 91 days (13 weeks × 7) |
| `burnRate` | `Double?` | Tokens/hr; see formula below |
| `projectedDayTotal` | `Int?` | `todayTotalTokens + burnRate × hoursRemainingToday`; nil when burnRate nil |
| `efficiencyScore` | `Double?` | `todayEvalTokens / todayPromptTokens`; nil when todayPromptTokens == 0 |

**`burnRate` formula — evaluated in order:**
```
// Step 1: pre-formula nil guard (checked first)
guard todayRecords.count >= 2 else { return nil }

// Step 2: compute elapsed hours with a 1-minute floor
let minutesSinceMidnight = Calendar.current.component(.hour, from: Date()) * 60
    + Calendar.current.component(.minute, from: Date())
let elapsedHours = max(1.0 / 60.0, Double(minutesSinceMidnight) / 60.0)

// Step 3: compute rate
burnRate = Double(todayTotalTokens) / elapsedHours
```
The `< 2 records` guard is applied **before** the formula. The `max(1.0/60.0, ...)` floor is a secondary safety net for the first minute of day only. Both conditions must be satisfied for a non-nil result.

**`heatmapData` key:** `Calendar.current.startOfDay(for: record.timestamp)` — a `Date` normalized to midnight. This is `Hashable` and avoids `DateComponents` entirely.

### `Settings`
```swift
struct Settings: Codable {
    var proxyPort: Int = 11435
    var targetURL: String = "http://localhost:11434"
    var dailyBudgetTokens: Int = 0
    var budgetMode: BudgetMode = .soft
    var costPer1kInputTokens: Double = 0.0
    var costPer1kOutputTokens: Double = 0.0
}
enum BudgetMode: String, Codable { case soft, hard }
```

### `BudgetSnapshot` (value type, shared between actors)
```swift
struct BudgetSnapshot {
    let dailyBudgetTokens: Int
    let todayTotalTokens: Int
    let budgetMode: BudgetMode
}
```

### Client App Detection (User-Agent, case-insensitive, first match)
```
"cursor"     → "Cursor"
"open-webui" → "Open WebUI"
"curl"       → "curl"
"python"     → "Python"
else         → "Unknown"
```

### Persistence
Path: `applicationSupportDirectory/OllamaBar/`
Serial `DispatchQueue(label: "com.ollamabar.persistence", qos: .utility)` for all writes.
- `usage.json` — `[UsageRecord]`, written after each new record
- `settings.json` — `Settings`, written on every change

---

## NDJSONParser — Both Endpoints

Ollama `/api/generate` and `/api/chat` both produce the same terminal chunk shape:

```jsonc
// done:true chunk — both /api/generate and /api/chat
{
  "model": "llama3.2",
  "done": true,
  "prompt_eval_count": 15,
  "eval_count": 42
  // ... other fields
}
```

`NDJSONParser` feeds on raw bytes line-by-line. For each line:
1. Attempt `JSONDecoder` decode into `DoneChunk: Decodable { let done: Bool; let model: String?; let promptEvalCount: Int?; let evalCount: Int? }` with `.convertFromSnakeCase`
2. If `done == true` AND `promptEvalCount != nil`: cache as the extracted result
3. If `done == true` AND `promptEvalCount == nil`: record `promptTokens: 0, evalTokens: 0` (client cancelled mid-stream or non-standard response)
4. Malformed JSON lines: skip silently

---

## Feature Details

### A: Token Budget Enforcer
- Budget disabled when `dailyBudgetTokens == 0`
- `ProxyServer` reads `budgetSnapshot` (value copy) before forwarding each request
- **Hard mode:** if `todayTotalTokens >= dailyBudgetTokens` → return `HTTP 429 {"error":"Daily token budget exceeded"}`
- **Soft mode:** requests always pass through; `AppViewModel.isBudgetWarning` set when `>= 80%`; `AppViewModel.isBudgetExceeded` set when `>= 100%`
- `AppViewModel` updates `budgetSnapshot` after every `UsageStore.append()` call

### B: Per-model + Per-app Breakdown
- Toggle: "By Model" / "By App" (SwiftUI `Picker` segmented style)
- Each row: name + `GeometryReader`-proportional fill bar + token count
- Max 5 rows shown; if more entries exist, a 6th row "Others" aggregates the rest
- Sorted descending by `tokens.total`

### C: Predictive Burn Rate
- Shown only when `burnRate != nil`
- Text: `"Burn rate: ~{burnRate}k tokens/hr  •  Projected: ~{projectedDayTotal}k today"`
- If no today data: `"No activity yet today"`

### D: Cost Estimator
- `cost(record) = (record.promptTokens / 1000.0) × costPer1kInput + (record.evalTokens / 1000.0) × costPer1kOutput`
- Shown as `"($0.12)"` inline next to token counts
- Hidden when both rates are `0.0`

### E: Usage Heatmap
- 91-day (13 × 7) grid rendered with SwiftUI `Canvas`
- Color: 5 levels of `.blue` opacity using **equal-range** thresholds:
  - Level 0: `0` tokens — `.clear`
  - Levels 1–4: computed from `maxTokensInWindow = heatmapData.values.max() ?? 1`
    - Level 1: `tokens >= 1`
    - Level 2: `tokens >= maxTokensInWindow / 4`
    - Level 3: `tokens >= maxTokensInWindow / 2`
    - Level 4: `tokens >= (maxTokensInWindow * 3) / 4`
    - Boundaries are `>=` (inclusive). Evaluated highest-to-lowest: assign the highest matching level.
  - Fallback when all non-zero days have the same value: all non-zero days render at Level 4
- `.help()` tooltip: `"Jan 15: 12,400 tokens"`
- Oldest cell top-left; newest cell bottom-right
- Weekday labels on left axis; month labels on top axis

### F: Token Efficiency Score
- `score = todayEvalTokens / todayPromptTokens` (nil when no today data)
- `score > 2.0` → "Verbose"
- `score 1.0–2.0` → "Balanced"
- `score 0.5–1.0` → "Tight"
- `score < 0.5` → "Ultra-efficient"
- Hidden when `efficiencyScore == nil`

---

## UI / UX

### Menu Bar Icon (`MenuBarIconView`)

| State | Appearance |
|---|---|
| Running, normal | `server.rack` + compact token string e.g. "100k" |
| Budget warning (soft ≥ 80%) | `server.rack` `.yellow` tint |
| Budget exceeded (soft or hard) | `server.rack` `.red` tint |
| Proxy stopped / port error | `server.rack.slash` |

### Popover Layout (320pt wide, scrollable VStack)

```
┌──────────────────────────────────┐
│ OllamaBar           [Proxy Active]│
├──────────────────────────────────┤
│ TODAY                             │
│ Input     99,459    ($0.10)       │
│ Output     1,174    ($0.02)       │
│ [budget bar — only if budget set] │
│ Total    100,633    ($0.12)       │
│ Burn: ~12k/hr • Proj: ~144k      │
├──────────────────────────────────┤
│ ALL TIME                          │
│ Total    100,633    ($0.12)       │
├──────────────────────────────────┤
│ BREAKDOWN  [By Model | By App]    │
│ llama3.2  ████████░  89,201      │
│ mistral   ██░░░░░░░  11,432      │
├──────────────────────────────────┤
│ USAGE HISTORY (91 days)           │
│ [13-week heatmap canvas]          │
│ Efficiency: Tight ⚡               │
├──────────────────────────────────┤
│ SETTINGS                          │
│ Proxy Port  [11435    ]           │
│ Target      [localhost:11434]     │
│ Budget      [0       ] [Soft ▾]   │
│ Cost/1k in  [$0.00   ]           │
│ Cost/1k out [$0.00   ]           │
├──────────────────────────────────┤
│ [About OllamaBar...]              │
│ [Check for Updates...]            │
│ [Reset Stats]                     │
│ [Quit OllamaBar]                  │
└──────────────────────────────────┘
```

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Ollama not running (502) | Proxy writes `502 Bad Gateway` to client; `ProxyServer.onError` → `AppViewModel.isOllamaOffline = true`; icon shows `server.rack.slash` |
| Port 11435 in use | `NWListener` start fails; `ProxyServer.onError(.portConflict)` → AppViewModel shows "Port in use" in popover |
| Malformed NDJSON | NDJSONParser skips line; if `done:true` chunk has no token fields, record saved with `0` tokens |
| Client cancels before `done:true` | `URLSession` task cancelled; NDJSONParser result is nil; record discarded |
| Persistence write fails | In-memory store unaffected; logged internally; retry on next write |
| Hard budget block | `429` written; `AppViewModel.blockedRequestCount` incremented on main actor |
| Settings port changed while running | `AppViewModel` calls `proxyServer.stop()` then `proxyServer.start(port:)` |

---

## Testing Strategy

### Unit Tests

- **`NDJSONParserTests`** — feed known NDJSON lines including `done:true` with tokens, `done:true` without tokens (cancelled), and malformed JSON; assert correct extraction or nil result
- **`UsageStoreTests`** — inject known `[UsageRecord]` with controlled timestamps; assert all aggregates (today totals, breakdown sorting, heatmap bucketing, burnRate with floor, efficiency score, projectedDayTotal); verify `burnRate == nil` when < 2 records and `== nil` when elapsed < 1 min
- **`SettingsStoreTests`** — `Codable` round-trip for `Settings` and `BudgetMode`; verify defaults
- **`ClientAppParserTests`** — Cursor, curl, Python, Open WebUI, unknown User-Agent strings
- **`PersistenceManagerTests`** — round-trip `[UsageRecord]` and `Settings`; cap/eviction for large record arrays if applicable

### Integration Tests

- **`ProxyServerTests`** — spin up `MockOllamaServer` (`NWListener` on random port) emitting a known NDJSON stream with `prompt_eval_count: 15, eval_count: 42, model: "test-model"`; point `ProxyServer` at it; send HTTP POST through proxy; assert:
  - Client receives identical bytes to mock server output
  - `onRecord` closure receives `UsageRecord` with `promptTokens: 15`, `evalTokens: 42`, `model: "test-model"`
  - Hard budget block (`dailyBudgetTokens: 1, budgetSnapshot.todayTotalTokens: 1`) returns `HTTP 429`

### SwiftUI Previews

`#Preview` blocks for `MenuBarPopover`, `StatsView`, `BreakdownView`, `HeatmapView`, `SettingsView` with stubbed `AppViewModel`.

---

## File Structure

```
OllamaBar.xcodeproj/
Sources/OllamaBar/
├── OllamaBarApp.swift
├── AppViewModel.swift              — @Observable @MainActor; owns all three; wires onRecord closure; maintains budgetSnapshot
├── Proxy/
│   ├── ProxyServer.swift           — NWListener; non-isolated; onRecord + budgetSnapshot properties
│   ├── ProxyConnection.swift       — per-connection: receive loop, URLSession forward, NW send, NDJSONParser
│   └── NDJSONParser.swift          — line-by-line parser; DoneChunk decodable; handles both endpoints
├── Store/
│   ├── UsageStore.swift            — @MainActor; records array; all computed aggregates
│   ├── SettingsStore.swift         — @MainActor; Settings; persistence
│   └── PersistenceManager.swift    — serial DispatchQueue; JSON read/write
├── Models/
│   ├── UsageRecord.swift           — Identifiable, Codable
│   ├── Settings.swift              — Codable; BudgetMode enum
│   ├── TokenPair.swift             — Equatable; prompt+eval+total
│   └── BudgetSnapshot.swift        — value type; shared across actor boundaries
└── Views/
    ├── MenuBarPopover.swift
    ├── MenuBarIconView.swift
    ├── StatsView.swift
    ├── BurnRateView.swift
    ├── BreakdownView.swift
    ├── HeatmapView.swift           — SwiftUI Canvas; 91-day 13×7 grid
    ├── EfficiencyView.swift
    └── SettingsView.swift
Tests/OllamaBarTests/
├── NDJSONParserTests.swift
├── UsageStoreTests.swift
├── SettingsStoreTests.swift
├── ClientAppParserTests.swift
├── PersistenceManagerTests.swift
└── ProxyServerTests.swift
```
