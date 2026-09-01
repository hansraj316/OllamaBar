
# OllamaBar

> Native macOS Menu Bar application to monitor your Ollama token usage, with real-time analytics and budget enforcement.

[![Indian Avengers](https://img.shields.io/badge/Managed%20By-Indian%20Avengers-orange?style=flat-square&logo=gitbook)](https://github.com/hansraj316/mission-control-openclaw)
[![Status](https://img.shields.io/badge/Status-Sentinel%20Audited-green?style=flat-square)](https://github.com/hansraj316/OllamaBar)

OllamaBar acts as a local proxy for your Ollama server, intercepting requests to count tokens, track usage patterns, and enforce optional daily budgets.

## The Mission

OllamaBar is a critical observability pillar of the **Indian Avengers** organization. It provides the **Token Efficiency & Budget Enforcement** required to scale a multi-agent "GitHub Factory" toward the **$1,000,000 revenue goal**. Every agent, from **Anusandhan (The Sentinel)** to **Parmanu (Engineering Commander)**, uses OllamaBar to ensure token usage is optimized and operational costs are locked.

![OllamaBar Screenshot](screenshot.png)

## Features

**Proxy**
- **Transparent streaming proxy** — every method and path is forwarded to Ollama and streamed back chunk by chunk, so clients see tokens as they are generated. Upstream status codes are preserved.
- **Native and OpenAI-compatible token counting** — reads `prompt_eval_count` / `eval_count` from `/api/generate` and `/api/chat`, and `usage` from `/v1/chat/completions` (SSE or JSON).
- **Token Budget Enforcer** — set a daily cap; *Warn* mode changes the menu bar colour, *Block* mode answers generation requests with HTTP 429 while model listing and pulling keep working.
- **Latency and speed** — each request records wall-clock time and output tokens per second.

**Insights**
- **Overview** — today's total with input/output split, change versus yesterday, cost estimate, burn rate, projected end-of-day total, efficiency score, and average speed.
- **14-day trend** — stacked input/output chart.
- **Breakdown by model or client app** for Today, 7 days, 30 days, or all time. Detects Cursor, Open WebUI, Cline, Continue, Zed, Aider, Raycast, the Ollama CLI, OpenAI SDKs, curl, Python, Node and more.
- **91-day heatmap** with active days, streak, and peak day.
- **Activity feed** — the last 60 requests with model, app, endpoint, tokens, duration, and tok/s.

**Ollama**
- **Health monitor** — online/offline status and version, refreshed every 20 seconds.
- **Loaded models** — what is resident in memory, GPU share, size, when it unloads, and a one-click **Unload**.
- **Installed models** — every model on disk with size, parameters, quantisation, and all-time tokens.

**App**
- **Edge gauges** — optional floating strip pinned to the screen edge with ring gauges for today's budget and each app's share of today's tokens (Settings → General).
- Launch at login, budget notifications at 80% and 100%, CSV/JSON export, and settings that apply without relaunching.

## Installation
1. Download the [latest release](https://github.com/hansraj316/OllamaBar/releases) (OllamaBar.zip)
2. Unzip and move `OllamaBar.app` to your `/Applications` folder
3. **⚠️ Security Bypass (First Run Only):**
   Open your Terminal and run the following to allow the app to run:
   ```bash
   xattr -cr /Applications/OllamaBar.app
   ```
4. Open `OllamaBar.app` — a server icon appears in your Menu Bar

## Usage
Change your Ollama client's API URL to the OllamaBar proxy port:
- **Direct Ollama:** `http://127.0.0.1:11434`
- **OllamaBar Proxy:** `http://127.0.0.1:11435`

Works with Cursor, Open-WebUI, Cline, curl, or any HTTP client. The proxy also passes through the OpenAI-compatible API, so point an OpenAI SDK at `http://127.0.0.1:11435/v1`.

```bash
# Native API
curl http://127.0.0.1:11435/api/chat -d '{"model":"llama3.2","messages":[{"role":"user","content":"hi"}]}'

# OpenAI-compatible API (counted too)
curl http://127.0.0.1:11435/v1/chat/completions \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"hi"}],"stream":true,"stream_options":{"include_usage":true}}'
```

## Development

Requirements: Xcode 15+, macOS 14+

```bash
# Build
xcodebuild -scheme OllamaBar -configuration Debug build

# Run tests
xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64'

# Run a single test class
xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
  -only-testing:OllamaBarTests/UsageStoreTests
```

## Claude Code / OpenClaw Integration

OllamaBar pairs with the [Mission Control dashboard](https://github.com/hansraj316/mission-control-openclaw) to give full-stack observability across the Indian Avengers org:

- **OllamaBar** → monitors local Ollama LLM usage (token budget, per-model breakdown)
- **Mission Control** → monitors the 25-agent org (cron jobs, agent activity, security telemetry)

Agents running via OpenClaw that use local models (Aditya, Dhruva) route through `http://127.0.0.1:11435` for token tracking.

## License
MIT
