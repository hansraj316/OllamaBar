# OllamaBar v2 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS 14+ menu bar app that transparently proxies Ollama API calls (port 11435 → 11434), counts tokens from streaming NDJSON, and surfaces 6 analytics features: budget enforcement, per-model/app breakdown, burn rate projection, cost estimation, 91-day heatmap, and efficiency scoring.

**Architecture:** `ProxyServer` (non-isolated `NWListener`) forwards requests to Ollama, tees the streaming NDJSON to `NDJSONParser`, and delivers `UsageRecord` values via an `onRecord` closure on the main queue. `UsageStore` and `SettingsStore` are `@MainActor @Observable` and own all aggregation + persistence. `AppViewModel` wires everything and keeps a `BudgetSnapshot` value type that crosses actor boundaries safely.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14.0+, XCTest, Network.framework, URLSession async/await, NWListener

---

## Chunk 1: Project Setup & App Shell

### Task 1: Initialize repo and create Xcode project

**Files:**
- Delete: `Package.swift`, `Sources/`
- Create: `OllamaBar.xcodeproj/` (via Xcode GUI)
- Create: `OllamaBar/OllamaBar.entitlements`

- [ ] **Step 1: Initialize git and remove SPM artifacts**

  ```bash
  cd /Users/hansraj316/OllamaBar
  git init
  rm -f Package.swift
  rm -rf Sources/OllamaBar/OllamaBar.swift
  ```

- [ ] **Step 2: Create Xcode project**

  Open Xcode → File → New → Project → macOS → App
  - Product Name: `OllamaBar`
  - Bundle Identifier: `com.ollamabar.OllamaBar`
  - Interface: SwiftUI, Language: Swift
  - Uncheck "Include Tests"
  - Save to `/Users/hansraj316/OllamaBar/`

  Then:
  - Set deployment target: **macOS 14.0**
  - Add test target: File → New → Target → Unit Testing Bundle → `OllamaBarTests`, host: OllamaBar, deployment: macOS 14.0

- [ ] **Step 3: Configure entitlements**

  In `OllamaBar/OllamaBar.entitlements`:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
      <key>com.apple.security.app-sandbox</key><false/>
      <key>com.apple.security.network.client</key><true/>
      <key>com.apple.security.network.server</key><true/>
  </dict></plist>
  ```

  In Xcode → Target → Signing & Capabilities → confirm App Sandbox is OFF.

- [ ] **Step 4: Configure Info.plist — add LSUIElement**

  Add to `OllamaBar/Info.plist`:
  ```xml
  <key>LSUIElement</key><true/>
  ```

- [ ] **Step 5: Create source directory structure**

  ```bash
  mkdir -p /Users/hansraj316/OllamaBar/OllamaBar/Proxy
  mkdir -p /Users/hansraj316/OllamaBar/OllamaBar/Store
  mkdir -p /Users/hansraj316/OllamaBar/OllamaBar/Models
  mkdir -p /Users/hansraj316/OllamaBar/OllamaBar/Views
  ```

- [ ] **Step 6: Write app entry point**

  `OllamaBar/OllamaBarApp.swift`:
  ```swift
  import SwiftUI

  @main
  struct OllamaBarApp: App {
      @State private var viewModel = AppViewModel()

      var body: some Scene {
          MenuBarExtra {
              MenuBarPopover()
                  .environment(viewModel)
          } label: {
              MenuBarIconView()
                  .environment(viewModel)
          }
          .menuBarExtraStyle(.window)
      }
  }
  ```

- [ ] **Step 7: Write minimal stub files that compile**

  `OllamaBar/AppViewModel.swift`:
  ```swift
  import Foundation
  import Observation

  @Observable
  @MainActor
  final class AppViewModel {
      var isProxyRunning = false
      var isOllamaOffline = false
      var isBudgetWarning = false
      var isBudgetExceeded = false
      var blockedRequestCount = 0
      var breakdownMode: BreakdownMode = .byModel
      let usageStore = UsageStore()
      let settingsStore = SettingsStore()
  }

  enum BreakdownMode { case byModel, byApp }
  ```

  `OllamaBar/Views/MenuBarPopover.swift`:
  ```swift
  import SwiftUI
  struct MenuBarPopover: View {
      var body: some View { Text("OllamaBar").frame(width: 320) }
  }
  ```

  `OllamaBar/Views/MenuBarIconView.swift`:
  ```swift
  import SwiftUI
  struct MenuBarIconView: View {
      var body: some View { Image(systemName: "server.rack") }
  }
  ```

  Create stub files (empty type declarations) for all remaining files:
  - `OllamaBar/Models/UsageRecord.swift` — `struct UsageRecord {}`
  - `OllamaBar/Models/Settings.swift` — `struct Settings {}`
  - `OllamaBar/Models/TokenPair.swift` — `struct TokenPair {}`
  - `OllamaBar/Models/BudgetSnapshot.swift` — `struct BudgetSnapshot {}`
  - `OllamaBar/Store/UsageStore.swift` — `@Observable @MainActor final class UsageStore {}`
  - `OllamaBar/Store/SettingsStore.swift` — `@Observable @MainActor final class SettingsStore {}`
  - `OllamaBar/Store/PersistenceManager.swift` — `final class PersistenceManager {}`
  - `OllamaBar/Proxy/ProxyServer.swift` — `final class ProxyServer {}`
  - `OllamaBar/Proxy/ProxyConnection.swift` — `final class ProxyConnection {}`
  - `OllamaBar/Proxy/NDJSONParser.swift` — `final class NDJSONParser {}`

- [ ] **Step 8: Add all new files to Xcode target**

  In Xcode, drag the new directories (`Proxy/`, `Store/`, `Models/`, `Views/`) into the project navigator under the `OllamaBar` target group. Ensure all `.swift` files are added to the `OllamaBar` target.

- [ ] **Step 9: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 10: Commit**

  ```bash
  git add -A
  git commit -m "feat: scaffold Xcode project — entitlements, LSUIElement, stub files"
  ```

---

## Chunk 2: Models & Persistence

### Task 2: Data Models

**Files:**
- Create: `OllamaBar/Models/UsageRecord.swift`
- Create: `OllamaBar/Models/Settings.swift`
- Create: `OllamaBar/Models/TokenPair.swift`
- Create: `OllamaBar/Models/BudgetSnapshot.swift`

- [ ] **Step 1: Implement all model files**

  `OllamaBar/Models/UsageRecord.swift`:
  ```swift
  import Foundation

  struct UsageRecord: Identifiable, Codable, Equatable {
      let id: UUID
      let timestamp: Date
      let model: String
      let clientApp: String
      let endpoint: String
      let promptTokens: Int
      let evalTokens: Int

      init(id: UUID = UUID(), timestamp: Date = Date(), model: String,
           clientApp: String, endpoint: String, promptTokens: Int, evalTokens: Int) {
          self.id = id; self.timestamp = timestamp; self.model = model
          self.clientApp = clientApp; self.endpoint = endpoint
          self.promptTokens = promptTokens; self.evalTokens = evalTokens
      }
  }
  ```

  `OllamaBar/Models/TokenPair.swift`:
  ```swift
  struct TokenPair: Equatable {
      let prompt: Int
      let eval: Int
      var total: Int { prompt + eval }
  }
  ```

  `OllamaBar/Models/BudgetSnapshot.swift`:
  ```swift
  struct BudgetSnapshot {
      let dailyBudgetTokens: Int
      let todayTotalTokens: Int
      let budgetMode: BudgetMode
  }
  ```

  `OllamaBar/Models/Settings.swift`:
  ```swift
  import Foundation

  enum BudgetMode: String, Codable, CaseIterable { case soft, hard }

  struct Settings: Codable, Equatable {
      var proxyPort: Int = 11435
      var targetURL: String = "http://localhost:11434"
      var dailyBudgetTokens: Int = 0
      var budgetMode: BudgetMode = .soft
      var costPer1kInputTokens: Double = 0.0
      var costPer1kOutputTokens: Double = 0.0
  }
  ```

- [ ] **Step 2: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add OllamaBar/Models/
  git commit -m "feat: add data models — UsageRecord, Settings, TokenPair, BudgetSnapshot"
  ```

### Task 3: PersistenceManager (TDD)

**Files:**
- Create: `OllamaBar/Store/PersistenceManager.swift`
- Create: `OllamaBarTests/PersistenceManagerTests.swift`

- [ ] **Step 1: Write failing tests**

  `OllamaBarTests/PersistenceManagerTests.swift`:
  ```swift
  import XCTest
  @testable import OllamaBar

  final class PersistenceManagerTests: XCTestCase {
      var sut: PersistenceManager!
      var tempDir: URL!

      override func setUp() {
          super.setUp()
          tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
          sut = PersistenceManager(directory: tempDir)
      }

      override func tearDown() {
          try? FileManager.default.removeItem(at: tempDir)
          super.tearDown()
      }

      func test_saveAndLoadRecords_roundTrip() throws {
          let records = [
              UsageRecord(model: "llama3.2", clientApp: "curl", endpoint: "/api/generate",
                          promptTokens: 10, evalTokens: 20)
          ]
          try sut.saveUsageRecords(records)
          let loaded = try sut.loadUsageRecords()
          XCTAssertEqual(loaded.count, 1)
          XCTAssertEqual(loaded[0].model, "llama3.2")
          XCTAssertEqual(loaded[0].promptTokens, 10)
      }

      func test_loadRecords_returnsEmptyWhenFileAbsent() throws {
          XCTAssertTrue(try sut.loadUsageRecords().isEmpty)
      }

      func test_saveAndLoadSettings_roundTrip() throws {
          var s = Settings(); s.proxyPort = 11436; s.costPer1kInputTokens = 0.25
          try sut.saveSettings(s)
          let loaded = try sut.loadSettings()
          XCTAssertEqual(loaded.proxyPort, 11436)
          XCTAssertEqual(loaded.costPer1kInputTokens, 0.25, accuracy: 0.001)
      }

      func test_loadSettings_returnsDefaultsWhenFileAbsent() throws {
          XCTAssertEqual(try sut.loadSettings(), Settings())
      }
  }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/PersistenceManagerTests 2>&1 | grep -E "error:|FAIL|Build"
  ```

- [ ] **Step 3: Implement PersistenceManager**

  `OllamaBar/Store/PersistenceManager.swift`:
  ```swift
  import Foundation

  final class PersistenceManager {
      private let directory: URL
      private let queue = DispatchQueue(label: "com.ollamabar.persistence", qos: .utility)

      private static let encoder: JSONEncoder = {
          let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
      }()
      private static let decoder: JSONDecoder = {
          let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
      }()

      init(directory: URL? = nil) {
          if let directory {
              self.directory = directory
          } else {
              let appSupport = FileManager.default
                  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
              self.directory = appSupport.appendingPathComponent("OllamaBar")
          }
          try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
      }

      private var recordsURL: URL { directory.appendingPathComponent("usage.json") }
      private var settingsURL: URL { directory.appendingPathComponent("settings.json") }

      func saveUsageRecords(_ records: [UsageRecord]) throws {
          let data = try Self.encoder.encode(records)
          try queue.sync { try data.write(to: recordsURL, options: .atomic) }
      }

      func loadUsageRecords() throws -> [UsageRecord] {
          guard FileManager.default.fileExists(atPath: recordsURL.path) else { return [] }
          return try Self.decoder.decode([UsageRecord].self, from: Data(contentsOf: recordsURL))
      }

      func saveSettings(_ settings: Settings) throws {
          let data = try Self.encoder.encode(settings)
          try queue.sync { try data.write(to: settingsURL, options: .atomic) }
      }

      func loadSettings() throws -> Settings {
          guard FileManager.default.fileExists(atPath: settingsURL.path) else { return Settings() }
          return try Self.decoder.decode(Settings.self, from: Data(contentsOf: settingsURL))
      }
  }
  ```

- [ ] **Step 4: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/PersistenceManagerTests 2>&1 | grep "Executed"
  ```
  Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Store/PersistenceManager.swift OllamaBarTests/PersistenceManagerTests.swift
  git commit -m "feat: add PersistenceManager with JSON persistence for records and settings"
  ```

---

## Chunk 3: NDJSONParser (TDD)

### Task 4: NDJSONParser

**Files:**
- Create: `OllamaBar/Proxy/NDJSONParser.swift`
- Create: `OllamaBarTests/NDJSONParserTests.swift`

- [ ] **Step 1: Write failing tests**

  `OllamaBarTests/NDJSONParserTests.swift`:
  ```swift
  import XCTest
  @testable import OllamaBar

  final class NDJSONParserTests: XCTestCase {

      func test_extractsTokensFromDoneChunk_generate() {
          let parser = NDJSONParser()
          let lines = [
              #"{"model":"llama3.2","response":"Hello","done":false}"#,
              #"{"model":"llama3.2","response":"","done":true,"prompt_eval_count":15,"eval_count":42}"#
          ]
          lines.forEach { parser.ingest(line: $0) }
          let result = parser.finalize()
          XCTAssertEqual(result?.model, "llama3.2")
          XCTAssertEqual(result?.promptTokens, 15)
          XCTAssertEqual(result?.evalTokens, 42)
      }

      func test_extractsTokensFromDoneChunk_chat() {
          // /api/chat uses same done:true shape
          let parser = NDJSONParser()
          let lines = [
              #"{"model":"mistral","message":{"role":"assistant","content":"Hi"},"done":false}"#,
              #"{"model":"mistral","done":true,"prompt_eval_count":8,"eval_count":20}"#
          ]
          lines.forEach { parser.ingest(line: $0) }
          let result = parser.finalize()
          XCTAssertEqual(result?.model, "mistral")
          XCTAssertEqual(result?.promptTokens, 8)
          XCTAssertEqual(result?.evalTokens, 20)
      }

      func test_returnsZeroTokens_whenDoneChunkHasNoTokenFields() {
          let parser = NDJSONParser()
          parser.ingest(line: #"{"done":true,"model":"llama3.2"}"#)
          let result = parser.finalize()
          XCTAssertNotNil(result)
          XCTAssertEqual(result?.promptTokens, 0)
          XCTAssertEqual(result?.evalTokens, 0)
      }

      func test_returnsNil_whenNoDoneChunkReceived() {
          let parser = NDJSONParser()
          parser.ingest(line: #"{"model":"llama3.2","response":"partial","done":false}"#)
          XCTAssertNil(parser.finalize())
      }

      func test_skipsMalformedLines() {
          let parser = NDJSONParser()
          parser.ingest(line: "not json at all")
          parser.ingest(line: #"{"done":true,"model":"llama3.2","prompt_eval_count":5,"eval_count":10}"#)
          let result = parser.finalize()
          XCTAssertEqual(result?.promptTokens, 5)
      }

      func test_clientAppParser_recognizesCursor() {
          XCTAssertEqual(ClientAppParser.parse(userAgent: "cursor/1.0"), "Cursor")
      }

      func test_clientAppParser_recognizesCurl() {
          XCTAssertEqual(ClientAppParser.parse(userAgent: "curl/7.88.1"), "curl")
      }

      func test_clientAppParser_recognizesOpenWebUI() {
          XCTAssertEqual(ClientAppParser.parse(userAgent: "open-webui/1.0"), "Open WebUI")
      }

      func test_clientAppParser_recognizesPython() {
          XCTAssertEqual(ClientAppParser.parse(userAgent: "python-requests/2.28"), "Python")
      }

      func test_clientAppParser_returnsUnknownForUnrecognized() {
          XCTAssertEqual(ClientAppParser.parse(userAgent: "MyCustomApp/1.0"), "Unknown")
      }
  }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/NDJSONParserTests 2>&1 | grep -E "error:|FAIL|Build"
  ```

- [ ] **Step 3: Implement NDJSONParser + ClientAppParser**

  `OllamaBar/Proxy/NDJSONParser.swift`:
  ```swift
  import Foundation

  struct ParsedTokens {
      let model: String
      let promptTokens: Int
      let evalTokens: Int
  }

  final class NDJSONParser {
      private var result: ParsedTokens?

      private struct DoneChunk: Decodable {
          let done: Bool
          let model: String?
          let promptEvalCount: Int?
          let evalCount: Int?
          enum CodingKeys: String, CodingKey {
              case done, model
              case promptEvalCount = "prompt_eval_count"
              case evalCount = "eval_count"
          }
      }

      func ingest(line: String) {
          guard result == nil,
                let data = line.data(using: .utf8),
                let chunk = try? JSONDecoder().decode(DoneChunk.self, from: data),
                chunk.done
          else { return }
          result = ParsedTokens(
              model: chunk.model ?? "unknown",
              promptTokens: chunk.promptEvalCount ?? 0,
              evalTokens: chunk.evalCount ?? 0
          )
      }

      func finalize() -> ParsedTokens? { result }
  }

  enum ClientAppParser {
      static func parse(userAgent: String) -> String {
          let ua = userAgent.lowercased()
          if ua.contains("cursor")     { return "Cursor" }
          if ua.contains("open-webui") { return "Open WebUI" }
          if ua.contains("curl")       { return "curl" }
          if ua.contains("python")     { return "Python" }
          return "Unknown"
      }
  }
  ```

- [ ] **Step 4: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/NDJSONParserTests 2>&1 | grep "Executed"
  ```
  Expected: `Executed 9 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Proxy/NDJSONParser.swift OllamaBarTests/NDJSONParserTests.swift
  git commit -m "feat: add NDJSONParser and ClientAppParser with full test coverage"
  ```

---

## Chunk 4: UsageStore Aggregates (TDD)

### Task 5: UsageStore

**Files:**
- Create: `OllamaBar/Store/UsageStore.swift`
- Create: `OllamaBarTests/UsageStoreTests.swift`

- [ ] **Step 1: Write failing tests**

  `OllamaBarTests/UsageStoreTests.swift`:
  ```swift
  import XCTest
  @testable import OllamaBar

  @MainActor
  final class UsageStoreTests: XCTestCase {

      func makeRecord(model: String = "llama3.2", app: String = "curl",
                      prompt: Int, eval: Int, daysAgo: Int = 0) -> UsageRecord {
          let ts = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
          return UsageRecord(timestamp: ts, model: model, clientApp: app,
                             endpoint: "/api/generate", promptTokens: prompt, evalTokens: eval)
      }

      func test_todayTotals() {
          let sut = UsageStore(records: [
              makeRecord(prompt: 10, eval: 20),
              makeRecord(prompt: 5,  eval: 15)
          ])
          XCTAssertEqual(sut.todayPromptTokens, 15)
          XCTAssertEqual(sut.todayEvalTokens, 35)
          XCTAssertEqual(sut.todayTotalTokens, 50)
      }

      func test_pastRecordNotCountedInToday() {
          let sut = UsageStore(records: [makeRecord(prompt: 100, eval: 200, daysAgo: 1)])
          XCTAssertEqual(sut.todayTotalTokens, 0)
      }

      func test_allTimeTotals() {
          let sut = UsageStore(records: [
              makeRecord(prompt: 10, eval: 20),
              makeRecord(prompt: 5, eval: 15, daysAgo: 5)
          ])
          XCTAssertEqual(sut.allTimePromptTokens, 15)
          XCTAssertEqual(sut.allTimeEvalTokens, 35)
      }

      func test_breakdownByModel_sortedDescending() {
          let sut = UsageStore(records: [
              makeRecord(model: "llama3.2", prompt: 100, eval: 200),
              makeRecord(model: "mistral", prompt: 10, eval: 20),
              makeRecord(model: "llama3.2", prompt: 50, eval: 100)
          ])
          let breakdown = sut.breakdownByModel
          XCTAssertEqual(breakdown[0].name, "llama3.2")
          XCTAssertEqual(breakdown[0].tokens.total, 450) // 300 + 150
          XCTAssertEqual(breakdown[1].name, "mistral")
      }

      func test_breakdownByApp() {
          let sut = UsageStore(records: [
              makeRecord(app: "Cursor", prompt: 100, eval: 200),
              makeRecord(app: "curl",   prompt: 10,  eval: 20)
          ])
          XCTAssertEqual(sut.breakdownByApp[0].name, "Cursor")
      }

      func test_burnRate_nilWhenFewerThan2Records() {
          let sut = UsageStore(records: [makeRecord(prompt: 100, eval: 200)])
          XCTAssertNil(sut.burnRate)
      }

      func test_burnRate_nonNilWith2OrMoreRecords() {
          let sut = UsageStore(records: [
              makeRecord(prompt: 100, eval: 200),
              makeRecord(prompt: 50,  eval: 100)
          ])
          XCTAssertNotNil(sut.burnRate)
          XCTAssertGreaterThan(sut.burnRate!, 0)
      }

      func test_efficiencyScore_nilWhenNoPromptTokens() {
          let sut = UsageStore(records: [])
          XCTAssertNil(sut.efficiencyScore)
      }

      func test_efficiencyScore_calculatedCorrectly() {
          let sut = UsageStore(records: [makeRecord(prompt: 100, eval: 200)])
          XCTAssertEqual(sut.efficiencyScore!, 2.0, accuracy: 0.001)
      }

      func test_heatmapData_bucketsRecordsByDay() {
          let sut = UsageStore(records: [
              makeRecord(prompt: 10, eval: 20),
              makeRecord(prompt: 5, eval: 15),
              makeRecord(prompt: 100, eval: 200, daysAgo: 3)
          ])
          let today = Calendar.current.startOfDay(for: Date())
          XCTAssertEqual(sut.heatmapData[today], 50)
          let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: today)!
          XCTAssertEqual(sut.heatmapData[threeDaysAgo], 300)
      }

      func test_heatmapData_excludesRecordsOlderThan91Days() {
          let sut = UsageStore(records: [makeRecord(prompt: 10, eval: 20, daysAgo: 92)])
          XCTAssertTrue(sut.heatmapData.isEmpty)
      }
  }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/UsageStoreTests 2>&1 | grep -E "error:|FAIL|Build"
  ```

- [ ] **Step 3: Implement UsageStore**

  `OllamaBar/Store/UsageStore.swift`:
  ```swift
  import Foundation
  import Observation

  @Observable
  @MainActor
  final class UsageStore {
      private(set) var records: [UsageRecord]
      private let persistence: PersistenceManager

      init(records: [UsageRecord] = [], persistence: PersistenceManager = PersistenceManager()) {
          self.records = records
          self.persistence = persistence
      }

      func append(_ record: UsageRecord) {
          records.append(record)
          try? persistence.saveUsageRecords(records)
      }

      func reset() {
          records = []
          try? persistence.saveUsageRecords([])
      }

      func load() {
          records = (try? persistence.loadUsageRecords()) ?? []
      }

      // MARK: - Today
      var todayRecords: [UsageRecord] {
          let today = Calendar.current.startOfDay(for: Date())
          let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
          return records.filter { $0.timestamp >= today && $0.timestamp < tomorrow }
      }

      var todayPromptTokens: Int { todayRecords.reduce(0) { $0 + $1.promptTokens } }
      var todayEvalTokens:   Int { todayRecords.reduce(0) { $0 + $1.evalTokens } }
      var todayTotalTokens:  Int { todayPromptTokens + todayEvalTokens }

      // MARK: - All time
      var allTimePromptTokens: Int { records.reduce(0) { $0 + $1.promptTokens } }
      var allTimeEvalTokens:   Int { records.reduce(0) { $0 + $1.evalTokens } }
      var allTimeTotalTokens:  Int { allTimePromptTokens + allTimeEvalTokens }

      // MARK: - Breakdown
      var breakdownByModel: [(name: String, tokens: TokenPair)] { breakdown(by: \.model) }
      var breakdownByApp:   [(name: String, tokens: TokenPair)] { breakdown(by: \.clientApp) }

      private func breakdown(by keyPath: KeyPath<UsageRecord, String>) -> [(name: String, tokens: TokenPair)] {
          var dict: [String: TokenPair] = [:]
          for r in records {
              let key = r[keyPath: keyPath]
              let existing = dict[key] ?? TokenPair(prompt: 0, eval: 0)
              dict[key] = TokenPair(prompt: existing.prompt + r.promptTokens,
                                    eval: existing.eval + r.evalTokens)
          }
          return dict.map { (name: $0.key, tokens: $0.value) }
              .sorted { $0.tokens.total > $1.tokens.total }
      }

      // MARK: - Heatmap (91 days)
      var heatmapData: [Date: Int] {
          let today = Calendar.current.startOfDay(for: Date())
          guard let cutoff = Calendar.current.date(byAdding: .day, value: -91, to: today) else { return [:] }
          var result: [Date: Int] = [:]
          for r in records where r.timestamp >= cutoff {
              let day = Calendar.current.startOfDay(for: r.timestamp)
              result[day, default: 0] += r.promptTokens + r.evalTokens
          }
          return result
      }

      // MARK: - Burn rate
      var burnRate: Double? {
          guard todayRecords.count >= 2 else { return nil }
          let cal = Calendar.current
          let now = Date()
          let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
          let elapsedHours = max(1.0 / 60.0, Double(minutes) / 60.0)
          return Double(todayTotalTokens) / elapsedHours
      }

      var projectedDayTotal: Int? {
          guard let rate = burnRate else { return nil }
          let cal = Calendar.current
          let now = Date()
          let remainingMinutes = (23 - cal.component(.hour, from: now)) * 60
              + (59 - cal.component(.minute, from: now))
          let remainingHours = Double(remainingMinutes) / 60.0
          return todayTotalTokens + Int(rate * remainingHours)
      }

      // MARK: - Efficiency
      var efficiencyScore: Double? {
          guard todayPromptTokens > 0 else { return nil }
          return Double(todayEvalTokens) / Double(todayPromptTokens)
      }
  }
  ```

- [ ] **Step 4: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/UsageStoreTests 2>&1 | grep "Executed"
  ```
  Expected: `Executed 11 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Store/UsageStore.swift OllamaBarTests/UsageStoreTests.swift
  git commit -m "feat: add UsageStore with all aggregates — totals, breakdown, heatmap, burn rate, efficiency"
  ```

### Task 6: SettingsStore (TDD)

**Files:**
- Create: `OllamaBar/Store/SettingsStore.swift`
- Create: `OllamaBarTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing tests**

  `OllamaBarTests/SettingsStoreTests.swift`:
  ```swift
  import XCTest
  @testable import OllamaBar

  @MainActor
  final class SettingsStoreTests: XCTestCase {

      func test_defaults() {
          let sut = SettingsStore(persistence: PersistenceManager(directory:
              FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
          XCTAssertEqual(sut.settings.proxyPort, 11435)
          XCTAssertEqual(sut.settings.targetURL, "http://localhost:11434")
          XCTAssertEqual(sut.settings.budgetMode, .soft)
      }

      func test_updatePersists() throws {
          let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          let persistence = PersistenceManager(directory: dir)
          let sut = SettingsStore(persistence: persistence)
          sut.settings.proxyPort = 11440
          // reload from same persistence
          let sut2 = SettingsStore(persistence: persistence)
          XCTAssertEqual(sut2.settings.proxyPort, 11440)
      }
  }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/SettingsStoreTests 2>&1 | grep -E "error:|FAIL"
  ```

- [ ] **Step 3: Implement SettingsStore**

  `OllamaBar/Store/SettingsStore.swift`:
  ```swift
  import Foundation
  import Observation

  @Observable
  @MainActor
  final class SettingsStore {
      var settings: Settings {
          didSet { try? persistence.saveSettings(settings) }
      }

      private let persistence: PersistenceManager

      init(persistence: PersistenceManager = PersistenceManager()) {
          self.persistence = persistence
          self.settings = (try? persistence.loadSettings()) ?? Settings()
      }
  }
  ```

- [ ] **Step 4: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/SettingsStoreTests 2>&1 | grep "Executed"
  ```
  Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Store/SettingsStore.swift OllamaBarTests/SettingsStoreTests.swift
  git commit -m "feat: add SettingsStore with auto-persist on change"
  ```

---

## Chunk 5: Proxy Server (Integration TDD)

### Task 7: ProxyServer + ProxyConnection

**Files:**
- Create: `OllamaBar/Proxy/ProxyServer.swift`
- Create: `OllamaBar/Proxy/ProxyConnection.swift`
- Create: `OllamaBarTests/ProxyServerTests.swift`

- [ ] **Step 1: Write integration tests**

  `OllamaBarTests/ProxyServerTests.swift`:
  ```swift
  import XCTest
  import Network
  @testable import OllamaBar

  final class ProxyServerTests: XCTestCase {

      // Spins up a mock Ollama server that returns a known NDJSON response
      func test_fullProxyRoundTrip_forwardsResponseAndRecordsTokens() async throws {
          // 1. Start mock Ollama server
          let mockPort: NWEndpoint.Port = 19434
          let mockBody = """
          {"model":"test-model","response":"Hello","done":false}
          {"model":"test-model","response":"","done":true,"prompt_eval_count":15,"eval_count":42}
          """
          let mockServer = MockHTTPServer(port: mockPort, responseBody: mockBody)
          try mockServer.start()
          defer { mockServer.stop() }

          // 2. Start proxy pointing at mock
          var receivedRecord: UsageRecord?
          let proxy = ProxyServer(
              port: 19435,
              targetURL: URL(string: "http://127.0.0.1:19434")!
          )
          proxy.onRecord = { record in receivedRecord = record }
          proxy.budgetSnapshot = BudgetSnapshot(dailyBudgetTokens: 0, todayTotalTokens: 0, budgetMode: .soft)
          try proxy.start()
          defer { proxy.stop() }

          // Wait for server to be ready
          try await Task.sleep(nanoseconds: 200_000_000)

          // 3. Send request through proxy
          let url = URL(string: "http://127.0.0.1:19435/api/generate")!
          var req = URLRequest(url: url)
          req.httpMethod = "POST"
          req.httpBody = #"{"model":"test-model","prompt":"hi","stream":true}"#.data(using: .utf8)
          req.setValue("curl/7.88", forHTTPHeaderField: "User-Agent")
          req.setValue("application/json", forHTTPHeaderField: "Content-Type")
          let (data, _) = try await URLSession.shared.data(for: req)

          // 4. Assert response bytes match mock output
          let responseStr = String(data: data, encoding: .utf8)!
          XCTAssertTrue(responseStr.contains("Hello"))

          // 5. Assert UsageRecord created
          try await Task.sleep(nanoseconds: 100_000_000)
          XCTAssertNotNil(receivedRecord)
          XCTAssertEqual(receivedRecord?.promptTokens, 15)
          XCTAssertEqual(receivedRecord?.evalTokens, 42)
          XCTAssertEqual(receivedRecord?.model, "test-model")
          XCTAssertEqual(receivedRecord?.clientApp, "curl")
      }

      func test_hardBudgetBlock_returns429() async throws {
          let proxy = ProxyServer(
              port: 19436,
              targetURL: URL(string: "http://127.0.0.1:11434")!
          )
          proxy.budgetSnapshot = BudgetSnapshot(
              dailyBudgetTokens: 100,
              todayTotalTokens: 100,  // already at limit
              budgetMode: .hard
          )
          try proxy.start()
          defer { proxy.stop() }

          try await Task.sleep(nanoseconds: 200_000_000)

          let url = URL(string: "http://127.0.0.1:19436/api/generate")!
          var req = URLRequest(url: url)
          req.httpMethod = "POST"
          req.httpBody = "{}".data(using: .utf8)
          let (_, response) = try await URLSession.shared.data(for: req)
          XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 429)
      }
  }

  // MARK: - MockHTTPServer

  final class MockHTTPServer {
      private let port: NWEndpoint.Port
      private let responseBody: String
      private var listener: NWListener?

      init(port: NWEndpoint.Port, responseBody: String) {
          self.port = port
          self.responseBody = responseBody
      }

      func start() throws {
          listener = try NWListener(using: .tcp, on: port)
          listener?.newConnectionHandler = { [weak self] conn in
              guard let self else { return }
              conn.start(queue: .global())
              conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                  guard data != nil else { return }
                  let body = self.responseBody
                  let http = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                  conn.send(content: http.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
              }
          }
          listener?.start(queue: .global())
      }

      func stop() { listener?.cancel() }
  }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/ProxyServerTests 2>&1 | grep -E "error:|FAIL|Build"
  ```

- [ ] **Step 3: Implement ProxyServer**

  `OllamaBar/Proxy/ProxyServer.swift`:
  ```swift
  import Foundation
  import Network

  final class ProxyServer {
      var onRecord: ((UsageRecord) -> Void)?
      var onError: ((ProxyError) -> Void)?
      var budgetSnapshot = BudgetSnapshot(dailyBudgetTokens: 0, todayTotalTokens: 0, budgetMode: .soft)

      private let port: NWEndpoint.Port
      private let targetURL: URL
      private var listener: NWListener?

      enum ProxyError: Error { case portConflict, listenerFailed }

      init(port: Int = 11435, targetURL: URL = URL(string: "http://127.0.0.1:11434")!) {
          self.port = NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
          self.targetURL = targetURL
      }

      func start() throws {
          let l = try NWListener(using: .tcp, on: port)
          l.stateUpdateHandler = { [weak self] state in
              if case .failed = state {
                  self?.onError?(.listenerFailed)
              }
          }
          l.newConnectionHandler = { [weak self] conn in
              guard let self else { return }
              let connection = ProxyConnection(
                  connection: conn,
                  targetURL: self.targetURL,
                  budgetSnapshot: self.budgetSnapshot,
                  onRecord: self.onRecord
              )
              connection.start()
          }
          l.start(queue: .global(qos: .userInitiated))
          listener = l
      }

      func stop() {
          listener?.cancel()
          listener = nil
      }
  }
  ```

- [ ] **Step 4: Implement ProxyConnection**

  `OllamaBar/Proxy/ProxyConnection.swift`:
  ```swift
  import Foundation
  import Network

  final class ProxyConnection {
      private let connection: NWConnection
      private let targetURL: URL
      private let budgetSnapshot: BudgetSnapshot
      private let onRecord: ((UsageRecord) -> Void)?
      private var accumulatedRequest = Data()
      private var userAgent = "Unknown"
      private var endpoint = "/api/generate"

      init(connection: NWConnection, targetURL: URL,
           budgetSnapshot: BudgetSnapshot, onRecord: ((UsageRecord) -> Void)?) {
          self.connection = connection
          self.targetURL = targetURL
          self.budgetSnapshot = budgetSnapshot
          self.onRecord = onRecord
      }

      func start() {
          connection.start(queue: .global(qos: .userInitiated))
          receiveRequest()
      }

      private func receiveRequest() {
          connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
              guard let self else { return }
              if let data { self.accumulatedRequest.append(data) }
              if isComplete || self.isRequestComplete() {
                  self.processRequest()
              } else {
                  self.receiveRequest()
              }
          }
      }

      private func isRequestComplete() -> Bool {
          // Simple heuristic: if we have headers + body matching Content-Length
          guard let str = String(data: accumulatedRequest, encoding: .utf8),
                let range = str.range(of: "\r\n\r\n") else { return false }
          let headers = String(str[str.startIndex..<range.lowerBound])
          let body = String(str[range.upperBound...])
          if let clLine = headers.components(separatedBy: "\r\n")
              .first(where: { $0.lowercased().hasPrefix("content-length:") }),
             let cl = Int(clLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") {
              return body.utf8.count >= cl
          }
          return true // no Content-Length → assume complete
      }

      private func processRequest() {
          // Parse headers
          if let str = String(data: accumulatedRequest, encoding: .utf8) {
              let lines = str.components(separatedBy: "\r\n")
              if let firstLine = lines.first {
                  let parts = firstLine.components(separatedBy: " ")
                  if parts.count >= 2 { endpoint = parts[1] }
              }
              for line in lines {
                  if line.lowercased().hasPrefix("user-agent:") {
                      userAgent = ClientAppParser.parse(userAgent: line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
                  }
              }
          }

          // Check hard budget
          if budgetSnapshot.budgetMode == .hard &&
             budgetSnapshot.dailyBudgetTokens > 0 &&
             budgetSnapshot.todayTotalTokens >= budgetSnapshot.dailyBudgetTokens {
              let response = "HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"error\":\"Daily token budget exceeded\"}"
              connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
                  self?.connection.cancel()
              })
              return
          }

          // Forward to Ollama
          forwardToOllama()
      }

      private func forwardToOllama() {
          guard let str = String(data: accumulatedRequest, encoding: .utf8),
                let headerEnd = str.range(of: "\r\n\r\n") else {
              connection.cancel(); return
          }
          let body = String(str[headerEnd.upperBound...])
          var components = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)!
          components.path = endpoint
          guard let url = components.url else { connection.cancel(); return }

          var req = URLRequest(url: url)
          req.httpMethod = "POST"
          req.httpBody = body.data(using: .utf8)
          req.setValue("application/json", forHTTPHeaderField: "Content-Type")

          let parser = NDJSONParser()
          let capturedEndpoint = endpoint
          let capturedApp = userAgent

          let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
              guard let self else { return }
              if let data {
                  // Forward to client
                  let httpHeader = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
                  var responseData = httpHeader.data(using: .utf8)!
                  responseData.append(data)
                  self.connection.send(content: responseData, completion: .contentProcessed { _ in
                      self.connection.cancel()
                  })
                  // Parse NDJSON
                  let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                  for line in lines { parser.ingest(line: line) }
                  if let tokens = parser.finalize() {
                      let record = UsageRecord(
                          model: tokens.model,
                          clientApp: capturedApp,
                          endpoint: capturedEndpoint,
                          promptTokens: tokens.promptTokens,
                          evalTokens: tokens.evalTokens
                      )
                      DispatchQueue.main.async { self.onRecord?(record) }
                  }
              } else {
                  let errResp = "HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n"
                  self.connection.send(content: errResp.data(using: .utf8), completion: .contentProcessed { _ in
                      self.connection.cancel()
                  })
              }
          }
          task.resume()
      }
  }
  ```

- [ ] **Step 5: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/ProxyServerTests 2>&1 | grep "Executed"
  ```
  Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 6: Commit**

  ```bash
  git add OllamaBar/Proxy/ OllamaBarTests/ProxyServerTests.swift
  git commit -m "feat: add ProxyServer and ProxyConnection with NWListener forwarding and token extraction"
  ```

---

## Chunk 6: AppViewModel Wiring

### Task 8: AppViewModel

**Files:**
- Modify: `OllamaBar/AppViewModel.swift`

- [ ] **Step 1: Replace stub with full implementation**

  `OllamaBar/AppViewModel.swift`:
  ```swift
  import Foundation
  import Observation

  @Observable
  @MainActor
  final class AppViewModel {
      let usageStore: UsageStore
      let settingsStore: SettingsStore
      let proxyServer: ProxyServer

      var isProxyRunning = false
      var isOllamaOffline = false
      var isBudgetWarning = false
      var isBudgetExceeded = false
      var blockedRequestCount = 0
      var breakdownMode: BreakdownMode = .byModel

      enum BreakdownMode { case byModel, byApp }

      init() {
          let persistence = PersistenceManager()
          let usage = UsageStore(persistence: persistence)
          let settings = SettingsStore(persistence: persistence)
          let proxy = ProxyServer(
              port: settings.settings.proxyPort,
              targetURL: URL(string: settings.settings.targetURL)!
          )

          self.usageStore = usage
          self.settingsStore = settings
          self.proxyServer = proxy

          // Load persisted records
          usage.load()

          // Wire proxy callbacks
          proxy.onRecord = { [weak self] record in
              guard let self else { return }
              self.usageStore.append(record)
              self.refreshBudgetSnapshot()
          }

          proxy.onError = { [weak self] error in
              guard let self else { return }
              switch error {
              case .portConflict: break   // surfaced via isProxyRunning = false
              case .listenerFailed: self.isProxyRunning = false
              }
          }

          // Initial budget snapshot
          refreshBudgetSnapshot()

          // Start proxy
          do {
              try proxy.start()
              isProxyRunning = true
          } catch {
              isProxyRunning = false
          }
      }

      func refreshBudgetSnapshot() {
          let s = settingsStore.settings
          proxyServer.budgetSnapshot = BudgetSnapshot(
              dailyBudgetTokens: s.dailyBudgetTokens,
              todayTotalTokens: usageStore.todayTotalTokens,
              budgetMode: s.budgetMode
          )
          let budget = s.dailyBudgetTokens
          let today = usageStore.todayTotalTokens
          isBudgetWarning  = budget > 0 && today >= Int(Double(budget) * 0.8)
          isBudgetExceeded = budget > 0 && today >= budget
      }

      func resetStats() {
          usageStore.reset()
          refreshBudgetSnapshot()
      }

      func restartProxy() {
          proxyServer.stop()
          let s = settingsStore.settings
          let newProxy = ProxyServer(
              port: s.proxyPort,
              targetURL: URL(string: s.targetURL)!
          )
          // Re-wire (same closures pattern as init)
          do {
              try newProxy.start()
              isProxyRunning = true
          } catch {
              isProxyRunning = false
          }
      }

      // MARK: - Cost helpers
      func cost(prompt: Int, eval: Int) -> Double? {
          let s = settingsStore.settings
          guard s.costPer1kInputTokens > 0 || s.costPer1kOutputTokens > 0 else { return nil }
          return (Double(prompt) / 1000.0) * s.costPer1kInputTokens
               + (Double(eval)   / 1000.0) * s.costPer1kOutputTokens
      }

      var todayCost: Double? { cost(prompt: usageStore.todayPromptTokens, eval: usageStore.todayEvalTokens) }
      var allTimeCost: Double? { cost(prompt: usageStore.allTimePromptTokens, eval: usageStore.allTimeEvalTokens) }
  }
  ```

- [ ] **Step 2: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add OllamaBar/AppViewModel.swift
  git commit -m "feat: wire AppViewModel — connects proxy, store, budget snapshot, cost helpers"
  ```

---

## Chunk 7: Views

### Task 9: StatsView + BurnRateView

**Files:**
- Create: `OllamaBar/Views/StatsView.swift`
- Create: `OllamaBar/Views/BurnRateView.swift`

- [ ] **Step 1: Implement StatsView**

  `OllamaBar/Views/StatsView.swift`:
  ```swift
  import SwiftUI

  struct StatsView: View {
      @Environment(AppViewModel.self) var vm

      var body: some View {
          VStack(alignment: .leading, spacing: 6) {
              sectionHeader("TODAY")
              tokenRow(label: "Input",  tokens: vm.usageStore.todayPromptTokens,
                       cost: vm.cost(prompt: vm.usageStore.todayPromptTokens, eval: 0))
              tokenRow(label: "Output", tokens: vm.usageStore.todayEvalTokens,
                       cost: vm.cost(prompt: 0, eval: vm.usageStore.todayEvalTokens))

              if vm.settingsStore.settings.dailyBudgetTokens > 0 {
                  budgetBar
              }
              tokenRow(label: "Total", tokens: vm.usageStore.todayTotalTokens,
                       cost: vm.todayCost, bold: true)
              BurnRateView()

              Divider()
              sectionHeader("ALL TIME")
              tokenRow(label: "Total", tokens: vm.usageStore.allTimeTotalTokens,
                       cost: vm.allTimeCost, bold: true)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
      }

      private func sectionHeader(_ text: String) -> some View {
          Text(text).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
      }

      private func tokenRow(label: String, tokens: Int, cost: Double?, bold: Bool = false) -> some View {
          HStack {
              Text(label).font(bold ? .body.bold() : .body)
              Spacer()
              if let cost, cost > 0 {
                  Text(String(format: "($%.2f)", cost)).font(.caption).foregroundStyle(.secondary)
              }
              Text(tokens.formatted()).font(bold ? .body.bold() : .body)
                  .monospacedDigit()
                  .foregroundStyle(bold ? .primary : .secondary)
          }
      }

      private var budgetBar: some View {
          let budget = vm.settingsStore.settings.dailyBudgetTokens
          let fraction = min(1.0, Double(vm.usageStore.todayTotalTokens) / Double(budget))
          return GeometryReader { geo in
              ZStack(alignment: .leading) {
                  RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2))
                  RoundedRectangle(cornerRadius: 3)
                      .fill(vm.isBudgetExceeded ? .red : vm.isBudgetWarning ? .yellow : .blue)
                      .frame(width: geo.size.width * fraction)
              }
          }
          .frame(height: 4)
          .padding(.vertical, 2)
      }
  }

  #Preview { StatsView().environment(AppViewModel()) }
  ```

  `OllamaBar/Views/BurnRateView.swift`:
  ```swift
  import SwiftUI

  struct BurnRateView: View {
      @Environment(AppViewModel.self) var vm

      var body: some View {
          if let rate = vm.usageStore.burnRate, let projected = vm.usageStore.projectedDayTotal {
              Text("Burn: ~\(Int(rate / 1000))k/hr  •  Projected: ~\(projected / 1000)k today")
                  .font(.caption)
                  .foregroundStyle(.secondary)
          } else {
              Text("No activity yet today")
                  .font(.caption)
                  .foregroundStyle(.tertiary)
          }
      }
  }

  #Preview { BurnRateView().environment(AppViewModel()) }
  ```

- [ ] **Step 2: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add OllamaBar/Views/StatsView.swift OllamaBar/Views/BurnRateView.swift
  git commit -m "feat: add StatsView with today/all-time stats, budget bar, and BurnRateView"
  ```

### Task 10: BreakdownView + EfficiencyView

**Files:**
- Create: `OllamaBar/Views/BreakdownView.swift`
- Create: `OllamaBar/Views/EfficiencyView.swift`

- [ ] **Step 1: Implement BreakdownView**

  `OllamaBar/Views/BreakdownView.swift`:
  ```swift
  import SwiftUI

  struct BreakdownView: View {
      @Environment(AppViewModel.self) var vm

      var rows: [(name: String, tokens: TokenPair)] {
          let data = vm.breakdownMode == .byModel
              ? vm.usageStore.breakdownByModel
              : vm.usageStore.breakdownByApp
          guard data.count > 5 else { return data }
          let top5 = Array(data.prefix(5))
          let rest = data.dropFirst(5).reduce(TokenPair(prompt: 0, eval: 0)) {
              TokenPair(prompt: $0.prompt + $1.tokens.prompt, eval: $0.eval + $1.tokens.eval)
          }
          return top5 + [(name: "Others", tokens: rest)]
      }

      var body: some View {
          VStack(alignment: .leading, spacing: 6) {
              HStack {
                  Text("BREAKDOWN").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                  Spacer()
                  Picker("", selection: Binding(
                      get: { vm.breakdownMode },
                      set: { vm.breakdownMode = $0 }
                  )) {
                      Text("By Model").tag(AppViewModel.BreakdownMode.byModel)
                      Text("By App").tag(AppViewModel.BreakdownMode.byApp)
                  }
                  .pickerStyle(.segmented)
                  .frame(width: 160)
                  .controlSize(.mini)
              }

              let maxTotal = rows.first?.tokens.total ?? 1
              ForEach(rows, id: \.name) { row in
                  HStack(spacing: 8) {
                      Text(row.name).font(.caption).frame(width: 80, alignment: .leading)
                      GeometryReader { geo in
                          ZStack(alignment: .leading) {
                              RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                              RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.7))
                                  .frame(width: geo.size.width * CGFloat(row.tokens.total) / CGFloat(maxTotal))
                          }
                      }
                      .frame(height: 12)
                      Text(row.tokens.total.formatted())
                          .font(.caption).monospacedDigit().frame(width: 60, alignment: .trailing)
                  }
              }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
      }
  }

  #Preview { BreakdownView().environment(AppViewModel()) }
  ```

  `OllamaBar/Views/EfficiencyView.swift`:
  ```swift
  import SwiftUI

  struct EfficiencyView: View {
      @Environment(AppViewModel.self) var vm

      var label: String {
          guard let score = vm.usageStore.efficiencyScore else { return "" }
          switch score {
          case let s where s > 2.0:  return "Verbose"
          case let s where s >= 1.0: return "Balanced"
          case let s where s >= 0.5: return "Tight ⚡"
          default:                   return "Ultra-efficient 🎯"
          }
      }

      var body: some View {
          if vm.usageStore.efficiencyScore != nil {
              HStack {
                  Text("Efficiency:").font(.caption).foregroundStyle(.secondary)
                  Text(label).font(.caption.bold())
              }
              .padding(.horizontal, 16)
              .padding(.bottom, 4)
          }
      }
  }

  #Preview { EfficiencyView().environment(AppViewModel()) }
  ```

- [ ] **Step 2: Build verify + commit**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  git add OllamaBar/Views/BreakdownView.swift OllamaBar/Views/EfficiencyView.swift
  git commit -m "feat: add BreakdownView (model/app bar charts) and EfficiencyView"
  ```

### Task 11: HeatmapView (Canvas)

**Files:**
- Create: `OllamaBar/Views/HeatmapView.swift`

- [ ] **Step 1: Implement HeatmapView**

  `OllamaBar/Views/HeatmapView.swift`:
  ```swift
  import SwiftUI

  struct HeatmapView: View {
      @Environment(AppViewModel.self) var vm

      private let columns = 13
      private let rows = 7
      private let cellSize: CGFloat = 12
      private let gap: CGFloat = 2

      var body: some View {
          VStack(alignment: .leading, spacing: 4) {
              Text("USAGE HISTORY (91 days)")
                  .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

              Canvas { ctx, size in
                  let data = vm.usageStore.heatmapData
                  let maxVal = data.values.max() ?? 1

                  for col in 0..<columns {
                      for row in 0..<rows {
                          let dayIndex = col * rows + row
                          let date = dayDate(daysAgo: 90 - dayIndex)
                          let tokens = data[date] ?? 0
                          let level = colorLevel(tokens: tokens, maxTokens: maxVal)
                          let x = CGFloat(col) * (cellSize + gap)
                          let y = CGFloat(row) * (cellSize + gap)
                          let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                          ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                                   with: .color(cellColor(level: level)))
                      }
                  }
              }
              .frame(width: CGFloat(columns) * (cellSize + gap),
                     height: CGFloat(rows) * (cellSize + gap))

              EfficiencyView()
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
      }

      private func dayDate(daysAgo: Int) -> Date {
          let today = Calendar.current.startOfDay(for: Date())
          return Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
      }

      private func colorLevel(tokens: Int, maxTokens: Int) -> Int {
          guard tokens > 0 else { return 0 }
          let max = max(1, maxTokens)
          if tokens >= (max * 3) / 4 { return 4 }
          if tokens >= max / 2       { return 3 }
          if tokens >= max / 4       { return 2 }
          return 1
      }

      private func cellColor(level: Int) -> Color {
          switch level {
          case 0: return Color.secondary.opacity(0.1)
          case 1: return Color.blue.opacity(0.25)
          case 2: return Color.blue.opacity(0.5)
          case 3: return Color.blue.opacity(0.75)
          default: return Color.blue
          }
      }
  }

  #Preview { HeatmapView().environment(AppViewModel()) }
  ```

- [ ] **Step 2: Build verify + commit**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  git add OllamaBar/Views/HeatmapView.swift
  git commit -m "feat: add HeatmapView — 91-day Canvas grid with equal-range color levels"
  ```

### Task 12: SettingsView

**Files:**
- Create: `OllamaBar/Views/SettingsView.swift`

- [ ] **Step 1: Implement SettingsView**

  `OllamaBar/Views/SettingsView.swift`:
  ```swift
  import SwiftUI

  struct SettingsView: View {
      @Environment(AppViewModel.self) var vm

      var body: some View {
          VStack(alignment: .leading, spacing: 8) {
              Text("SETTINGS").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

              settingRow("Proxy Port") {
                  TextField("11435", value: Binding(
                      get: { vm.settingsStore.settings.proxyPort },
                      set: { vm.settingsStore.settings.proxyPort = $0 }
                  ), format: .number)
                  .textFieldStyle(.roundedBorder).frame(width: 70)
              }

              settingRow("Target") {
                  TextField("localhost:11434", text: Binding(
                      get: { vm.settingsStore.settings.targetURL },
                      set: { vm.settingsStore.settings.targetURL = $0 }
                  ))
                  .textFieldStyle(.roundedBorder)
              }

              settingRow("Budget (tokens/day)") {
                  HStack {
                      TextField("0 = off", value: Binding(
                          get: { vm.settingsStore.settings.dailyBudgetTokens },
                          set: { vm.settingsStore.settings.dailyBudgetTokens = $0 }
                      ), format: .number)
                      .textFieldStyle(.roundedBorder).frame(width: 80)

                      Picker("", selection: Binding(
                          get: { vm.settingsStore.settings.budgetMode },
                          set: { vm.settingsStore.settings.budgetMode = $0 }
                      )) {
                          Text("Soft").tag(BudgetMode.soft)
                          Text("Hard").tag(BudgetMode.hard)
                      }
                      .pickerStyle(.segmented).frame(width: 90).controlSize(.mini)
                  }
              }

              settingRow("Cost/1k input ($)") {
                  TextField("0.00", value: Binding(
                      get: { vm.settingsStore.settings.costPer1kInputTokens },
                      set: { vm.settingsStore.settings.costPer1kInputTokens = $0 }
                  ), format: .number)
                  .textFieldStyle(.roundedBorder).frame(width: 70)
              }

              settingRow("Cost/1k output ($)") {
                  TextField("0.00", value: Binding(
                      get: { vm.settingsStore.settings.costPer1kOutputTokens },
                      set: { vm.settingsStore.settings.costPer1kOutputTokens = $0 }
                  ), format: .number)
                  .textFieldStyle(.roundedBorder).frame(width: 70)
              }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
      }

      private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
          HStack {
              Text(label).font(.callout).frame(width: 140, alignment: .leading)
              content()
          }
      }
  }

  #Preview { SettingsView().environment(AppViewModel()) }
  ```

- [ ] **Step 2: Build verify + commit**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  git add OllamaBar/Views/SettingsView.swift
  git commit -m "feat: add SettingsView with port, target, budget, and cost configuration"
  ```

---

## Chunk 8: Final Assembly

### Task 13: MenuBarIconView + MenuBarPopover

**Files:**
- Modify: `OllamaBar/Views/MenuBarIconView.swift`
- Modify: `OllamaBar/Views/MenuBarPopover.swift`

- [ ] **Step 1: Implement MenuBarIconView**

  `OllamaBar/Views/MenuBarIconView.swift`:
  ```swift
  import SwiftUI

  struct MenuBarIconView: View {
      @Environment(AppViewModel.self) var vm

      var body: some View {
          HStack(spacing: 3) {
              Image(systemName: iconName).foregroundStyle(iconColor)
              if vm.usageStore.todayTotalTokens > 0 {
                  Text(compactTokenString(vm.usageStore.todayTotalTokens))
                      .font(.system(size: 11, weight: .medium, design: .monospaced))
              }
          }
      }

      private var iconName: String {
          vm.isProxyRunning ? "server.rack" : "server.rack.slash"
      }

      private var iconColor: Color {
          if !vm.isProxyRunning { return .secondary }
          if vm.isBudgetExceeded { return .red }
          if vm.isBudgetWarning  { return .yellow }
          return .primary
      }

      private func compactTokenString(_ n: Int) -> String {
          switch n {
          case 0..<1000:    return "\(n)"
          case 0..<1000000: return "\(n / 1000)k"
          default:          return "\(n / 1000000)M"
          }
      }
  }

  #Preview { MenuBarIconView().environment(AppViewModel()) }
  ```

- [ ] **Step 2: Implement MenuBarPopover**

  `OllamaBar/Views/MenuBarPopover.swift`:
  ```swift
  import SwiftUI

  struct MenuBarPopover: View {
      @Environment(AppViewModel.self) var vm

      var body: some View {
          ScrollView {
              VStack(spacing: 0) {
                  header
                  Divider()
                  StatsView()
                  Divider()
                  BreakdownView()
                  Divider()
                  HeatmapView()
                  Divider()
                  SettingsView()
                  Divider()
                  footerButtons
              }
          }
          .frame(width: 320)
          .frame(maxHeight: 600)
      }

      private var header: some View {
          HStack {
              Text("OllamaBar").font(.headline)
              Spacer()
              Label(vm.isProxyRunning ? "Proxy Active" : "Proxy Stopped",
                    systemImage: vm.isProxyRunning ? "circle.fill" : "circle")
                  .font(.caption)
                  .foregroundStyle(vm.isProxyRunning ? .green : .red)
                  .labelStyle(.titleAndIcon)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
      }

      private var footerButtons: some View {
          VStack(spacing: 0) {
              Divider()
              Button("About OllamaBar...") { }
                  .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8)
                  .frame(maxWidth: .infinity, alignment: .leading)
              Divider()
              Button("Reset Stats") { vm.resetStats() }
                  .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8)
                  .frame(maxWidth: .infinity, alignment: .leading)
              Divider()
              Button("Quit OllamaBar") { NSApp.terminate(nil) }
                  .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8)
                  .frame(maxWidth: .infinity, alignment: .leading)
          }
      }
  }

  #Preview { MenuBarPopover().environment(AppViewModel()) }
  ```

- [ ] **Step 3: Full build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Full test run**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
  ```
  Expected: all tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Views/
  git commit -m "feat: complete view assembly — MenuBarPopover, MenuBarIconView with dynamic states"
  ```

---

## Chunk 9: Documentation & Git Push

### Task 14: Update README and CLAUDE.md

- [ ] **Step 1: Update README.md**

  Rewrite `README.md` to reflect the v2 Swift implementation:
  ```markdown
  # OllamaBar

  A native macOS Menu Bar application to monitor your Ollama token usage, with real-time analytics and budget enforcement.

  OllamaBar acts as a local proxy for your Ollama server, intercepting requests to count tokens, track usage patterns, and enforce optional daily budgets.

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
  3. Open `OllamaBar.app` — a server icon appears in your Menu Bar

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

  ## License
  MIT
  ```

- [ ] **Step 2: Update CLAUDE.md**

  Rewrite `CLAUDE.md` to reflect the v2 Xcode project:
  ```markdown
  # CLAUDE.md

  This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

  ## Project Overview

  OllamaBar is a macOS 14+ menu bar app built with SwiftUI and Xcode. It acts as a transparent HTTP proxy (NWListener on port 11435 → Ollama on port 11434), counts tokens from streaming NDJSON responses, and surfaces 6 analytics features in a menu bar popover.

  ## Commands

  ```bash
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
  ```

- [ ] **Step 3: Commit docs**

  ```bash
  git add README.md CLAUDE.md
  git commit -m "docs: update README and CLAUDE.md for v2 Swift proxy implementation"
  ```

- [ ] **Step 4: Push to remote**

  ```bash
  git remote -v
  # If remote exists:
  git push origin main
  # If no remote set, add it first:
  # git remote add origin https://github.com/hansraj316/OllamaBar.git
  # git push -u origin main
  ```

### Task 15: Final Smoke Test

- [ ] **Step 1: Run all tests one last time**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
  ```
  Expected: all tests pass, 0 failures.

- [ ] **Step 2: Manual smoke test (requires Ollama running)**

  - Build and run `OllamaBar.app` from Xcode
  - Verify: server icon appears in menu bar (not Dock)
  - Click icon: popover shows TODAY section with 0 tokens
  - Run: `curl -s http://127.0.0.1:11435/api/generate -d '{"model":"llama3.2","prompt":"hello","stream":true}'`
  - Verify: response streams to terminal AND token counts update in menu bar
  - Set a small budget (e.g. 10 tokens, Hard mode) and repeat curl — verify 429 response
  - Change proxy port in Settings — proxy restarts on new port
