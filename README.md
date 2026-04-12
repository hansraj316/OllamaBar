
# OllamaBar

> Native macOS Menu Bar application to monitor your Ollama token usage, with real-time analytics and budget enforcement.

[![Indian Avengers](https://img.shields.io/badge/Managed%20By-Indian%20Avengers-orange?style=flat-square&logo=gitbook)](https://github.com/hansraj316/mission-control-openclaw)
[![Status](https://img.shields.io/badge/Status-Sentinel%20Audited-green?style=flat-square)](https://github.com/hansraj316/OllamaBar)

OllamaBar acts as a local proxy for your Ollama server, intercepting requests to count tokens, track usage patterns, and enforce optional daily budgets.

## The Mission

OllamaBar is a critical observability pillar of the **Indian Avengers** organization. It provides the **Token Efficiency & Budget Enforcement** required to scale a multi-agent "GitHub Factory" toward the **$1,000,000 revenue goal**. Every agent, from **Anusandhan (The Sentinel)** to **Parmanu (Engineering Commander)**, uses OllamaBar to ensure token usage is optimized and operational costs are locked.

![OllamaBar Screenshot](screenshot.png)

## Features

- **Token Tracking** — Real-time prompt (input) and eval (output) token counts
- **Daily & All-time Stats** — Usage for today and your all-time total, with optional cost estimation
- **Token Budget Enforcer** — Set a daily token cap; soft mode warns, hard mode blocks requests with HTTP 429
- **Per-model & Per-app Breakdown** — See which models and clients (Cursor, Open-WebUI, curl) are burning tokens
- **Predictive Burn Rate** — Projects your end-of-day total based on current pace
- **91-day Usage Heatmap** — GitHub-style contribution grid of your token history
- **Token Efficiency Score** — Rates how efficiently you're prompting (Verbose / Balanced / Tight / Ultra-efficient)

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

Works with Cursor, Open-WebUI, Cline, curl, or any HTTP client.

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
