# Changelog

## Unreleased

### Fixed
- **Claude Code and other Anthropic-API clients are counted correctly.** Requests to Ollama's Anthropic-compatible `/v1/messages` endpoint were recorded as zero-token requests from an "unknown" model, because any `usage` object locked in a 0/0 record even when it used Anthropic's field names. Both the JSON body and the streamed `message_start` / `message_delta` events are now parsed, `/v1/messages` counts toward hard budgets, and Claude Code and the Anthropic SDKs are labelled by name.

### Added
- **True generation speed.** Tokens per second now comes from Ollama's own `eval_duration` timer on native API responses, so model loading and prompt processing no longer drag the number down. OpenAI- and Anthropic-compatible responses, which carry no timers, still fall back to wall-clock time.
- **Cold loads.** Requests where Ollama had to load the model from disk (`load_duration` of 0.5 s or more) are flagged in Activity, and the Overview counts today's cold loads and the time spent on them.
- **Prompt cache hits.** Reads `prompt_eval_cached_count` (native), `prompt_tokens_details.cached_tokens` (OpenAI) and `cache_read_input_tokens` (Anthropic). The Overview shows the share of today's prompt tokens served from cache, and each Activity row shows its own hit rate.
- CSV export gains `cached_prompt_tokens`, `load_ms` and `eval_ms` columns.

## 3.0.1 — 2026-09-02

Build fixes. No functional changes.

### Fixed
- The app icon is now compiled into the bundle. `project.yml` listed the asset catalog twice and the second entry pointed outside the repo, so every previous build shipped with a generic Finder icon.
- The app reports its version again. `CFBundleShortVersionString` and `CFBundleVersion` were dropped from the generated Info.plist because no marketing or build version was set.
- The committed Xcode project is in sync with the sources. It referenced only 17 of the 29 Swift files and did not build without `xcodegen generate`.

### Housekeeping
- `build/`, the derived-data path used by CI and local builds, is ignored by git.

## 3.0.0 — 2026-09-01

The proxy became a real streaming proxy, the popover became a four-tab app, and the whole thing got a new look.

### Proxy
- Streams responses chunk-by-chunk as Ollama produces them, instead of buffering the whole reply.
- Forwards every method and path with the upstream status code, so `/api/tags`, `/api/ps`, pulls and the OpenAI-compatible `/v1` API all work through the proxy.
- Counts tokens from OpenAI-compatible `usage` objects (SSE or JSON), not only native `done:true` chunks.
- Records wall-clock duration per request; tokens per second and average latency are derived from it.
- Hard budgets only block generation requests. Model listing and pulling keep working when the cap is hit.

### New in the popover
- **Overview**: usage card with daily budget (or pace when no budget is set) and a "resets at" note, rolling last hour, input/output split, change vs yesterday, burn rate, projected total, efficiency, speed, 14-day stacked trend, breakdown by model or app for Today / 7D / 30D / All, and the 91-day heatmap with active days, streak and peak.
- **Models**: Ollama online/offline and version, models loaded in memory with GPU share, size and unload time plus a one-click Unload, and every installed model with all-time tokens.
- **Activity**: the last 60 requests with model, app, endpoint, tokens, duration and tok/s.
- **Settings**: port and Ollama URL with Apply & restart, budget cap and mode, budget notifications, cost per 1k tokens, launch at login, menu bar token count, edge gauges, CSV/JSON export, reset with confirmation.

### Edge gauges
- Optional floating strip pinned to the right edge of the screen with ring gauges for today's budget and each app's share of today's tokens. Draggable, stays above other windows.

### Look and feel
- Always-dark "ink" surface. Bars and rings move mint → lime → hot as usage fills.
- Menu bar glyph reflects proxy and budget state.

### Compatibility
- Existing `usage.json` and `settings.json` files load unchanged; new fields default.
- More clients recognised: Cline, Continue, Zed, Aider, Raycast, Ollama CLI, OpenAI SDK, Node, Go, and more.

## 2.0

- Initial menu bar app: proxy on 11435, token counting, daily and all-time stats, budget enforcer, per-model and per-app breakdown, burn rate, heatmap, efficiency score.
