# OllamaBar — Design Spec

**Date:** 2026-03-13
**Status:** Approved

---

## Overview

OllamaBar is a macOS 14+ (Sonoma) menu bar app built in pure SwiftUI. It provides quick access to locally running Ollama LLMs via a `MenuBarExtra` floating window, with an inline streaming chat and an ambient clipboard-powered context digest that silently feeds relevant context into every conversation.

**Key constraints:**
- macOS 14.0 minimum (required for `@Observable`, `MenuBarExtra`, `.symbolEffect`)
- Built as an **Xcode project** (not a pure SPM CLI) — required for `.app` bundle, `Info.plist`, and entitlements
- Direct download / notarized DMG distribution — App Sandbox **disabled**
- No AppKit in view layer; service layer may use AppKit APIs (`NSPasteboard`, `Process`)

---

## Build Setup

The project is an **Xcode project** (`.xcodeproj`), not a pure SPM command-line tool. Key project settings:

- **Target type:** macOS App
- **Info.plist:** Must include `LSUIElement = YES` (Application is agent) to suppress Dock icon and app switcher entry
- **Entitlements file (`OllamaBar.entitlements`):**
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
      <key>com.apple.security.app-sandbox</key><false/>
      <key>com.apple.security.network.client</key><true/>
  </dict></plist>
  ```
- Sandboxing disabled allows `Process` to launch subprocesses and unrestricted `NSPasteboard` access

Build command: `xcodebuild -scheme OllamaBar -configuration Debug build`
Test command: `xcodebuild -scheme OllamaBar -configuration Debug test`

---

## Architecture

### App Entry Point

`@main struct OllamaBarApp: App` with:
```swift
var body: some Scene {
    MenuBarExtra { MenuBarPopover() } label: { MenuBarIconView() }
        .menuBarExtraStyle(.window)
}
```

### Services

| Service | Type | Responsibility |
|---|---|---|
| `OllamaService` | `@Observable` class | REST client — list models, stream chat, launch `ollama serve` |
| `ClipboardWatcher` | `@Observable` class | Polls `NSPasteboard` every 2s on background queue; feeds `DigestEngine` |
| `DigestEngine` | `@Observable` class | Rolling clipboard buffer, periodic compression, pinned items |

All owned by `AppViewModel` (`@Observable`, `@MainActor`). Injected via `.environment(appViewModel)`. Views access it with `@Environment(AppViewModel.self) var appViewModel` and mutate via `@Bindable var appViewModel`.

### Threading Model

- `ClipboardWatcher`: polls on a private `DispatchQueue(label: "clipboard", qos: .background)`. New entries dispatched back via `DispatchQueue.main.async { self.newEntry = entry }`.
- `OllamaService`: streaming via `URLSession.bytes(for:)` in Swift async/await. All published property updates wrapped in `await MainActor.run { }`.
- `DigestEngine`: compression launched as `Task { await compress() }` from the main actor; results applied on `@MainActor`. A `Bool` flag `isCompressing` guards against concurrent compression calls — if `isCompressing` is true when a trigger fires, the trigger is ignored (not queued).

### View Layer

```
MenuBarExtra (.window style)
└── MenuBarPopover          ← root container; keyboard shortcuts; outside-click dismiss
    ├── StatusBar            — server status, model selector, start/stop controls
    ├── QuickChatView        — scrollable chat history + token-by-token streaming
    ├── DigestPanel          — collapsible; shows digest + pinned clipboard entries
    └── InputBar             — text field, send, inject controls (always visible)
```

**Outside-click dismiss:** `MenuBarPopover` stores the window reference via `NSViewRepresentable` bridge (read from `NSView.window` on appear) and calls `window.orderOut(nil)` on a background tap gesture. This targets the specific OllamaBar window reference, not `NSApp.windows`.

---

## Data Flow

### Ollama REST API

All requests to `http://localhost:11434`.

**`OllamaService` uses a shared `JSONDecoder` configured as:**
```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
decoder.dateDecodingStrategy = .iso8601  // for modified_at on OllamaModel
```

**Chat endpoint** (`POST /api/chat`):
- Request: `{ "model": "...", "messages": [{"role": "user", "content": "..."}], "stream": true }`
- Chunks: `{ "message": { "role": "assistant", "content": "<token>" }, "done": false }`
- Terminal: `{ "done": true }` (content may be empty string)
- Parsing: iterate `URLSession.bytes(for:)` line-by-line, decode each non-empty line as `ChatChunk: Decodable`, append `content` token to in-progress message, stop on `done == true`

**Generate endpoint** (`POST /api/generate`) — `DigestEngine` only, `stream: false`:
- Request: `{ "model": "...", "prompt": "...", "stream": false }`
- Response: `{ "response": "<text>", "done": true }`

**Tags endpoint** (`GET /api/tags`):
- Response: `{ "models": [{ "name": "...", "modified_at": "2024-01-15T10:23:45Z", "size": 43000000000 }] }`
- `OllamaModel: Identifiable, Codable` — `name: String`, `modifiedAt: Date`, `size: Int64`

### Clipboard Pipeline

```
NSPasteboard.general (poll every 2s, background DispatchQueue)
  → if changeCount == lastChangeCount: skip
  → read .string(forType: .string); if nil for 5 consecutive polls → emit .denied signal
  → ClipboardEntry(id: UUID, text: String, timestamp: Date)
  → DispatchQueue.main.async → DigestEngine.ingest(entry)

DigestEngine (main actor):
  → buffer: [ClipboardEntry], max 50
      eviction: if count >= 50, removeFirst() BEFORE appending new entry
  → increment newSinceLastCompression counter
  → compression triggers:
      (a) newSinceLastCompression >= 10 AND !isCompressing
      (b) repeating 5-min Timer (created at DigestEngine.init, repeats, fires on main RunLoop)
          timer handler: if !isCompressing { compress() }
          timer invalidated when ClipboardWatcher emits .denied signal
  → on compression start: isCompressing = true; newSinceLastCompression = 0
  → on compression success: isCompressing = false; digest = result; save digest.json
  → on compression failure: isCompressing = false; newSinceLastCompression stays 0
      (counter stays reset — next trigger requires 10 more entries, avoiding retry storms)
```

**TCC denial detection in `ClipboardWatcher`:**
If `NSPasteboard.general.string(forType: .string)` returns `nil` for 5 consecutive polls while `changeCount` has incremented, emit a `.clipboardDenied` signal to `AppViewModel`. `AppViewModel` sets `clipboardAccessDenied = true` → `DigestPanel` hides, `ClipboardWatcher` stops polling.

### Context Injection

System prompt assembled per `/api/chat` call. The system prompt is **not stored in `history.json`** — it is assembled fresh from the current `DigestEngine` state on every send:
```
[Context Digest]: <digest string, or omitted if empty>
[Pinned Items]: <pinned entry texts newline-separated, or omitted if none>
```
`history.json` stores only `ChatMessage` values (user + assistant turns), not the system prompt.

### Persistence

Path: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("OllamaBar/")`

All file writes go through a dedicated serial `DispatchQueue(label: "persistence", qos: .utility)` to prevent concurrent write races under Swift 6 strict concurrency.

- `digest.json` — `DigestState: Codable { digest: String, pinnedEntries: [ClipboardEntry] }` — written after each successful compression
- `history.json` — `[ChatMessage]`, cap 100. On write: if array count > 100, drop oldest entries (lowest indices) until count == 100. Written after each assistant message completes (not after each streaming token).

---

## UI / UX

### Menu Bar Icon (`MenuBarIconView`)

A SwiftUI `Label`-like view used as the `MenuBarExtra` label:

| State | Appearance |
|---|---|
| Running, idle | `Image(systemName: "brain")` |
| Model responding | `Image(systemName: "brain.fill").symbolEffect(.pulse)` |
| Ollama unreachable | `Image(systemName: "exclamationmark.triangle")` |
| New digest ready | `brain` + `Circle().fill(.blue).frame(6,6)` overlay at `.topTrailing` |

### Popover Layout

Fixed width: **380pt**. Max height: **600pt**.

```
┌─────────────────────────────────────┐
│  ● llama3.2  ▾    [Start] [Stop]   │  ← StatusBar
│  ● Connected  last digest: 2m ago   │
├─────────────────────────────────────┤
│                                     │
│  [Scrollable chat / streaming]      │  ← QuickChatView
│                                     │
├─────────────────────────────────────┤
│  ▸ Context Digest          [inject] │  ← DigestPanel (collapsible)
│    "Working on Swift menu bar..."   │
│    📌 NSPasteboard docs             │
├─────────────────────────────────────┤
│  [Type a message...]  [⏎] [digest▾]│  ← InputBar (always visible)
└─────────────────────────────────────┘
```

### Empty / Disabled States

- `[inject]` button: disabled (`.disabled(true)`) when `digest.isEmpty`
- `[digest▾]` Menu: disabled when `pinnedEntries.isEmpty`; when non-empty, shows each pinned entry's text truncated to 40 characters as Menu items
- `DigestPanel` body: shows "No context yet — copy some text to get started" placeholder when both `digest.isEmpty` and `pinnedEntries.isEmpty`

### Keyboard Shortcuts

Registered on `MenuBarPopover` (the always-key window when open):
- `⌘K` — clears `ChatMessage` history (in memory + `history.json`)
- `⌘D` — toggles `DigestPanel` expanded/collapsed

### Ambient Behavior

- `ClipboardWatcher` and `DigestEngine` run continuously in background
- New digest ready → dot badge appears on menu bar icon; clears when user opens popover
- No system notifications or banners

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Ollama not running | Warning icon; "Start Ollama" button; launches `ollama serve` via `Process` with explicit `executableURL` resolved by searching `/usr/local/bin/ollama`, `/opt/homebrew/bin/ollama`; if binary not found, shows "Ollama not installed" with link to ollama.com |
| `ollama serve` already running (port conflict) | Process exits non-zero; StatusBar polls `/api/tags`; if it succeeds, treat as connected |
| Model not found | Inline error bubble: "Model not found. Run: `ollama pull <model>`" |
| Stream interrupted | Partial response shown + "↻ Retry" button |
| Digest compression fails | `isCompressing = false`; counter reset to 0; retry after 10 more entries |
| Clipboard TCC denied (5 consecutive nil reads) | `DigestPanel` hidden; `ClipboardWatcher` stops; 5-min timer invalidated |

---

## Testing Strategy

### Unit Tests (`Tests/OllamaBarTests/`)

- **`OllamaServiceTests`** — inject mock `URLProtocol` subclass into `URLSession`; verify `/api/tags` decoding (including `Int64` size and `Date` from ISO 8601 string), chat streaming chunk parsing, `done: true` termination, and request construction
- **`DigestEngineTests`** — feed exactly 10 entries → assert `isCompressing` becomes true; feed 49 entries + 2 more → assert buffer count stays 50 (eviction); assert failed compression sets `isCompressing = false` and resets counter to 0; assert `[inject]` disabled state when digest empty
- **`ClipboardWatcherTests`** — stub `NSPasteboard` changeCount; assert entry emitted on increment; assert no entry on stable count; assert `.clipboardDenied` emitted after 5 consecutive nil reads with changing changeCount

### Integration Tests

Gate: `OLLAMA_INTEGRATION_TESTS=1` (Xcode: Edit Scheme → Test → Environment Variables).
Requires running Ollama with ≥1 model pulled.
Tests: `/api/chat` round-trip with streaming, `/api/generate` compression, `/api/tags` model list.

### SwiftUI Previews

`#Preview` blocks for `StatusBar`, `QuickChatView`, `DigestPanel`, `InputBar` with a stubbed `AppViewModel` populated with sample data.

---

## File Structure

```
OllamaBar.xcodeproj/
Sources/OllamaBar/
├── OllamaBarApp.swift          — @main, MenuBarExtra scene
├── AppViewModel.swift          — @Observable @MainActor, owns all services
├── Services/
│   ├── OllamaService.swift     — URLSession REST + streaming; JSONDecoder config
│   ├── ClipboardWatcher.swift  — NSPasteboard polling, TCC denial detection
│   └── DigestEngine.swift      — rolling buffer, compression, timer, pinned items
├── Models/
│   ├── ClipboardEntry.swift    — id: UUID, text: String, timestamp: Date
│   ├── ChatMessage.swift       — id: UUID, role: Role, content: String, timestamp: Date
│   ├── OllamaModel.swift       — name: String, modifiedAt: Date, size: Int64
│   └── DigestState.swift       — digest: String, pinnedEntries: [ClipboardEntry]
└── Views/
    ├── MenuBarPopover.swift     — root container, keyboard shortcuts, window dismiss
    ├── MenuBarIconView.swift    — dynamic icon with badge overlay
    ├── StatusBar.swift
    ├── QuickChatView.swift
    ├── DigestPanel.swift
    └── InputBar.swift
Tests/OllamaBarTests/
├── OllamaServiceTests.swift
├── DigestEngineTests.swift
└── ClipboardWatcherTests.swift
```
