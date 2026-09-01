# Changelog

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
