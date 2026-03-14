# GEMINI.md

## Project Overview
OllamaBar is a native macOS Menu Bar application designed to monitor and manage Ollama token usage. It acts as a local proxy (defaulting to port 11435) that intercepts requests to an Ollama server (defaulting to port 11434). The app parses streaming NDJSON responses to track prompt and evaluation tokens in real-time.

### Key Features
- **Token Analytics:** Real-time tracking of input/output tokens with daily and all-time statistics.
- **Budget Management:** Supports "soft" (warning) and "hard" (blocking via HTTP 429) daily token budgets.
- **Usage Insights:** Provides per-model and per-app breakdowns, 91-day heatmaps, burn rate projections, and efficiency scoring.
- **Native Integration:** Built with SwiftUI for macOS 14+, featuring a compact Menu Bar interface.

### Technology Stack
- **Language:** Swift 5.9+ (utilizing the `Observation` framework)
- **Frameworks:** SwiftUI, Network.framework (for `NWListener` proxy), XCTest
- **Architecture:** MVVM (Model-View-ViewModel) with a dedicated Proxy layer
- **Build System:** `xcodegen` (via `project.yml`)

## Building and Running
The project uses `xcodegen` to generate the `.xcodeproj` file. Ensure you have the latest version of Xcode (15+) installed.

### Key Commands
```bash
# Generate/Update Xcode project (if project.yml is modified)
xcodegen generate

# Build the project
xcodebuild -scheme OllamaBar -configuration Debug build

# Run all tests (replace arch as needed, e.g., arm64 for Apple Silicon)
xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64'

# Run specific tests
xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' -only-testing:OllamaBarTests/UsageStoreTests
```

## Project Structure
- `OllamaBar/`: Main application source code.
  - `Models/`: Data structures (`UsageRecord`, `Settings`, `TokenPair`, `BudgetSnapshot`).
  - `Proxy/`: Core proxy logic (`ProxyServer`, `ProxyConnection`, `NDJSONParser`).
  - `Store/`: Persistence and state management (`UsageStore`, `SettingsStore`, `PersistenceManager`).
  - `Views/`: SwiftUI components for the Menu Bar icon and popover.
- `OllamaBarTests/`: Unit and integration tests.
- `docs/`: Design specs and implementation plans.

## Development Conventions
- **Asynchronous Proxy:** `ProxyServer` and `ProxyConnection` are non-isolated to handle `NWListener` callbacks efficiently without blocking the `@MainActor`.
- **Observation:** Uses the `@Observable` macro for modern SwiftUI state management.
- **Persistence:** Data is stored as JSON files in the user's `Application Support/OllamaBar/` directory.
- **TDD:** New features are typically implemented following a Test-Driven Development approach, with tests located in `OllamaBarTests/`.
- **Strict Concurrency:** The project aims for Swift 6 strict concurrency compatibility; ensure any actor hops are handled safely, particularly between the proxy layer and the ViewModel.
