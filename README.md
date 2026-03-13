# OllamaBar 􀢋

A native macOS Menu Bar application to monitor your Ollama token usage, inspired by [CodexBar](https://github.com/steipete/CodexBar).

OllamaBar acts as a local proxy for your Ollama server. It intercepts requests, counts the input/output tokens in real-time, and displays your daily and total consumption directly in your macOS Menu Bar.

![OllamaBar Screenshot](screenshot.png)

## Features
- **Token Tracking:** Real-time monitoring of Prompt (Input) and Eval (Output) tokens.
- **Daily & Total Stats:** View usage for the current day and your all-time total.
- **Embedded Proxy:** Automatically runs a lightweight Python proxy on port `11435`.
- **Zero Configuration:** Simple Menu Bar interface with a "Quit" option.

## Installation
1. Download the [latest release](https://github.com/hansraj316/OllamaBar/releases) (OllamaBar.zip).
2. Unzip and move `OllamaBar.app` to your `/Applications` folder.
3. Open `OllamaBar.app`. You will see a server icon in your Menu Bar.

## Usage
To track tokens, change your client's Ollama API URL to the proxy port:
- **Default:** `http://127.0.0.1:11434`
- **OllamaBar Proxy:** `http://127.0.0.1:11435`

### Supported Clients
Works with any client that connects to Ollama, including:
- [Cursor](https://cursor.sh)
- [Open-WebUI](https://github.com/open-webui/open-webui)
- [Cline](https://github.com/cline/cline)
- `curl` or any custom scripts.

## How it Works
Ollama doesn't store aggregate token usage locally. OllamaBar solves this by:
1. Running a native SwiftUI app with a Menu Bar extra.
2. Embedding a Python-based `http.server` proxy.
3. Parsing the response stream for `prompt_eval_count` and `eval_count`.
4. Saving stats to `~/.ollama/ollamabar_usage.json`.

## Development
To build from source, you need Xcode or the Swift toolchain:
```bash
swift build -c release
```

## License
MIT
