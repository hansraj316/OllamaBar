# OllamaBar Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS 14+ menu bar app in pure SwiftUI that provides inline Ollama chat and an ambient clipboard-powered context digest.

**Architecture:** `MenuBarExtra` (.window style) hosts a popover with `StatusBar`, `QuickChatView`, `DigestPanel`, and `InputBar`. Three services (`OllamaService`, `ClipboardWatcher`, `DigestEngine`) are owned by an `@Observable @MainActor AppViewModel` injected via `.environment`. All persistence is Codable JSON written to a serial queue.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14.0+, XCTest, URLSession async/await, NSPasteboard, Process

---

## Chunk 1: Project Setup & App Shell

### Task 1: Create the Xcode Project

**Files:**
- Create: `OllamaBar.xcodeproj/` (via Xcode GUI)
- Create: `OllamaBar/OllamaBarApp.swift`
- Create: `OllamaBar/Info.plist`
- Create: `OllamaBar/OllamaBar.entitlements`

- [ ] **Step 1: Initialize git repository**

  ```bash
  cd /Users/hansraj316/OllamaBar && git init
  ```

- [ ] **Step 2: Create project in Xcode**

  Open Xcode → File → New → Project → macOS → App.
  - Product Name: `OllamaBar`
  - Bundle Identifier: `com.ollamabar.OllamaBar`
  - Interface: SwiftUI
  - Language: Swift
  - Uncheck "Include Tests" (we'll add a test target manually)
  - Save into `/Users/hansraj316/OllamaBar/`

- [ ] **Step 3: Set deployment target**

  In Xcode → Project → OllamaBar target → General → Minimum Deployments → **macOS 14.0**

- [ ] **Step 4: Add test target**

  Xcode → File → New → Target → macOS → Unit Testing Bundle.
  - Product Name: `OllamaBarTests`
  - Target to be tested: `OllamaBar`

- [ ] **Step 5: Configure Info.plist**

  Add to `OllamaBar/Info.plist`:
  ```xml
  <key>LSUIElement</key><true/>
  <key>NSPasteboardUsageDescription</key>
  <string>OllamaBar reads your clipboard history to build a context digest for your AI conversations.</string>
  ```

- [ ] **Step 6: Configure entitlements**

  In `OllamaBar/OllamaBar.entitlements`, set:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
      <key>com.apple.security.app-sandbox</key><false/>
      <key>com.apple.security.network.client</key><true/>
  </dict></plist>
  ```
  In Xcode → Target → Signing & Capabilities → confirm "App Sandbox" is OFF.

- [ ] **Step 7: Write the app entry point**

  Replace the Xcode-generated `ContentView.swift` and `OllamaBarApp.swift` with:

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

- [ ] **Step 8: Create stub files so the project builds**

  Create the following empty stubs (just enough to compile):

  `OllamaBar/AppViewModel.swift`:
  ```swift
  import SwiftUI

  @Observable
  @MainActor
  final class AppViewModel {
      var isOllamaRunning = false
      var availableModels: [OllamaModel] = []
      var selectedModel: OllamaModel?
      var chatMessages: [ChatMessage] = []
      var digest = ""
      var pinnedEntries: [ClipboardEntry] = []
      var clipboardAccessDenied = false
      var isDigestPanelExpanded = true
      var newDigestAvailable = false
      var isStreaming = false
  }
  ```

  `OllamaBar/Views/MenuBarPopover.swift`:
  ```swift
  import SwiftUI

  struct MenuBarPopover: View {
      var body: some View {
          Text("OllamaBar")
              .frame(width: 380)
      }
  }
  ```

  `OllamaBar/Views/MenuBarIconView.swift`:
  ```swift
  import SwiftUI

  struct MenuBarIconView: View {
      var body: some View {
          Image(systemName: "brain")
      }
  }
  ```

  `OllamaBar/Models/OllamaModel.swift`:
  ```swift
  import Foundation
  struct OllamaModel: Identifiable, Codable, Hashable {
      var id: String { name }
      let name: String
      let modifiedAt: Date
      let size: Int64
  }
  ```

  `OllamaBar/Models/ChatMessage.swift`:
  ```swift
  import Foundation
  struct ChatMessage: Identifiable, Codable {
      enum Role: String, Codable { case user, assistant }
      let id: UUID
      let role: Role
      var content: String
      let timestamp: Date
      init(role: Role, content: String) {
          self.id = UUID()
          self.role = role
          self.content = content
          self.timestamp = Date()
      }
  }
  ```

  `OllamaBar/Models/ClipboardEntry.swift`:
  ```swift
  import Foundation
  struct ClipboardEntry: Identifiable, Codable {
      let id: UUID
      let text: String
      let timestamp: Date
      init(text: String) {
          self.id = UUID()
          self.text = text
          self.timestamp = Date()
      }
  }
  ```

  `OllamaBar/Models/DigestState.swift`:
  ```swift
  import Foundation
  struct DigestState: Codable {
      var digest: String
      var pinnedEntries: [ClipboardEntry]
  }
  ```

- [ ] **Step 9: Verify project builds**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 10: Commit**

  ```bash
  git add -A
  git commit -m "feat: scaffold Xcode project with app entry point and stub files"
  ```

---

## Chunk 2: Data Models & Persistence Layer

### Task 2: Persistence Manager

**Files:**
- Create: `OllamaBar/Services/PersistenceManager.swift`
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
          tempDir = FileManager.default.temporaryDirectory
              .appendingPathComponent(UUID().uuidString)
          try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
          sut = PersistenceManager(baseDirectory: tempDir)
      }

      override func tearDown() {
          try? FileManager.default.removeItem(at: tempDir)
          super.tearDown()
      }

      func test_saveAndLoadDigestState_roundTrips() throws {
          let state = DigestState(
              digest: "test digest",
              pinnedEntries: [ClipboardEntry(text: "pinned")]
          )
          try sut.saveDigestState(state)
          let loaded = try sut.loadDigestState()
          XCTAssertEqual(loaded.digest, "test digest")
          XCTAssertEqual(loaded.pinnedEntries.count, 1)
          XCTAssertEqual(loaded.pinnedEntries[0].text, "pinned")
      }

      func test_loadDigestState_returnsEmptyWhenFileAbsent() throws {
          let loaded = try sut.loadDigestState()
          XCTAssertTrue(loaded.digest.isEmpty)
          XCTAssertTrue(loaded.pinnedEntries.isEmpty)
      }

      func test_saveAndLoadHistory_roundTrips() throws {
          let messages = [
              ChatMessage(role: .user, content: "hello"),
              ChatMessage(role: .assistant, content: "world")
          ]
          try sut.saveHistory(messages)
          let loaded = try sut.loadHistory()
          XCTAssertEqual(loaded.count, 2)
          XCTAssertEqual(loaded[0].content, "hello")
      }

      func test_saveHistory_capsAt100() throws {
          let messages = (0..<110).map { ChatMessage(role: .user, content: "\($0)") }
          try sut.saveHistory(messages)
          let loaded = try sut.loadHistory()
          XCTAssertEqual(loaded.count, 100)
          // oldest dropped: first saved message was "0", loaded[0] should be "10"
          XCTAssertEqual(loaded[0].content, "10")
      }

      func test_loadHistory_returnsEmptyWhenFileAbsent() throws {
          let loaded = try sut.loadHistory()
          XCTAssertTrue(loaded.isEmpty)
      }
  }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/PersistenceManagerTests 2>&1 | grep -E "FAIL|error:|Build"
  ```
  Expected: build error — `PersistenceManager` does not exist.

- [ ] **Step 3: Implement PersistenceManager**

  `OllamaBar/Services/PersistenceManager.swift`:
  ```swift
  import Foundation

  /// All public methods are synchronous and safe to call from any thread.
  /// Writes are serialised through an internal queue to prevent concurrent write races.
  final class PersistenceManager {
      private let baseDirectory: URL
      private let queue = DispatchQueue(label: "com.ollamabar.persistence", qos: .utility)

      init(baseDirectory: URL? = nil) {
          if let baseDirectory {
              self.baseDirectory = baseDirectory
          } else {
              let appSupport = FileManager.default
                  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
              self.baseDirectory = appSupport.appendingPathComponent("OllamaBar")
          }
          try? FileManager.default.createDirectory(
              at: self.baseDirectory, withIntermediateDirectories: true)
      }

      private var digestURL: URL { baseDirectory.appendingPathComponent("digest.json") }
      private var historyURL: URL { baseDirectory.appendingPathComponent("history.json") }

      private static let encoder: JSONEncoder = {
          let e = JSONEncoder()
          e.dateEncodingStrategy = .iso8601
          return e
      }()

      private static let decoder: JSONDecoder = {
          let d = JSONDecoder()
          d.dateDecodingStrategy = .iso8601
          d.keyDecodingStrategy = .convertFromSnakeCase
          return d
      }()

      func saveDigestState(_ state: DigestState) throws {
          let data = try Self.encoder.encode(state)
          try queue.sync { try data.write(to: digestURL, options: .atomic) }
      }

      func loadDigestState() throws -> DigestState {
          guard FileManager.default.fileExists(atPath: digestURL.path) else {
              return DigestState(digest: "", pinnedEntries: [])
          }
          let data = try Data(contentsOf: digestURL)
          return try Self.decoder.decode(DigestState.self, from: data)
      }

      func saveHistory(_ messages: [ChatMessage]) throws {
          let capped = messages.count > 100
              ? Array(messages.dropFirst(messages.count - 100))
              : messages
          let data = try Self.encoder.encode(capped)
          try queue.sync { try data.write(to: historyURL, options: .atomic) }
      }

      func loadHistory() throws -> [ChatMessage] {
          guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
          let data = try Data(contentsOf: historyURL)
          return try Self.decoder.decode([ChatMessage].self, from: data)
      }
  }
  ```

- [ ] **Step 4: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/PersistenceManagerTests 2>&1 | grep -E "PASS|FAIL|Executed"
  ```
  Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Services/PersistenceManager.swift OllamaBarTests/PersistenceManagerTests.swift
  git commit -m "feat: add PersistenceManager with Codable JSON persistence"
  ```

---

## Chunk 3: OllamaService

### Task 3: REST Client — Tags & Generate Endpoints

**Files:**
- Create: `OllamaBar/Services/OllamaService.swift`
- Create: `OllamaBarTests/Helpers/MockURLProtocol.swift`
- Create: `OllamaBarTests/OllamaServiceTests.swift`

- [ ] **Step 1: Create MockURLProtocol helper**

  `OllamaBarTests/Helpers/MockURLProtocol.swift`:
  ```swift
  import Foundation

  final class MockURLProtocol: URLProtocol {
      static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
          guard let handler = MockURLProtocol.handler else {
              client?.urlProtocol(self, didFailWithError: URLError(.unknown))
              return
          }
          do {
              let (response, data) = try handler(request)
              client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
              client?.urlProtocol(self, didLoad: data)
              client?.urlProtocolDidFinishLoading(self)
          } catch {
              client?.urlProtocol(self, didFailWithError: error)
          }
      }
      override func stopLoading() {}
  }

  extension URLSession {
      static func mock() -> URLSession {
          let config = URLSessionConfiguration.ephemeral
          config.protocolClasses = [MockURLProtocol.self]
          return URLSession(configuration: config)
      }
  }
  ```

- [ ] **Step 2: Write failing tests for tags + generate**

  `OllamaBarTests/OllamaServiceTests.swift`:
  ```swift
  import XCTest
  @testable import OllamaBar

  final class OllamaServiceTests: XCTestCase {
      var sut: OllamaService!

      override func setUp() {
          super.setUp()
          sut = OllamaService(session: .mock())
      }

      // MARK: - fetchModels

      func test_fetchModels_parsesValidResponse() async throws {
          let json = """
          {"models":[{"name":"llama3.2","modified_at":"2024-01-15T10:23:45Z","size":2000000000}]}
          """
          MockURLProtocol.handler = { _ in
              (.init(url: URL(string:"http://localhost:11434/api/tags")!,
                     statusCode: 200, httpVersion: nil, headerFields: nil)!,
               json.data(using: .utf8)!)
          }
          let models = try await sut.fetchModels()
          XCTAssertEqual(models.count, 1)
          XCTAssertEqual(models[0].name, "llama3.2")
          XCTAssertEqual(models[0].size, 2_000_000_000)
      }

      func test_fetchModels_throwsOnNon200() async {
          MockURLProtocol.handler = { _ in
              (.init(url: URL(string:"http://localhost:11434/api/tags")!,
                     statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
          }
          do {
              _ = try await sut.fetchModels()
              XCTFail("Should throw")
          } catch OllamaError.httpError(let code) {
              XCTAssertEqual(code, 503)
          } catch {
              XCTFail("Wrong error: \(error)")
          }
      }

      // MARK: - generate (digest compression)

      func test_generate_returnsResponseText() async throws {
          let json = """
          {"response":"summarized content","done":true}
          """
          MockURLProtocol.handler = { _ in
              (.init(url: URL(string:"http://localhost:11434/api/generate")!,
                     statusCode: 200, httpVersion: nil, headerFields: nil)!,
               json.data(using: .utf8)!)
          }
          let result = try await sut.generate(model: "llama3.2", prompt: "summarize this")
          XCTAssertEqual(result, "summarized content")
      }

      func test_generate_includesCorrectRequestBody() async throws {
          var capturedRequest: URLRequest?
          MockURLProtocol.handler = { req in
              capturedRequest = req
              let json = """{"response":"ok","done":true}"""
              return (.init(url: req.url!, statusCode: 200,
                            httpVersion: nil, headerFields: nil)!,
                      json.data(using: .utf8)!)
          }
          _ = try await sut.generate(model: "llama3.2", prompt: "hello")
          let body = try JSONSerialization.jsonObject(
              with: capturedRequest!.httpBody!) as! [String: Any]
          XCTAssertEqual(body["model"] as? String, "llama3.2")
          XCTAssertEqual(body["stream"] as? Bool, false)
      }
  }
  ```

- [ ] **Step 3: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/OllamaServiceTests 2>&1 | grep -E "error:|FAIL|Build"
  ```
  Expected: build error — `OllamaService` does not exist.

- [ ] **Step 4: Implement OllamaService (non-streaming parts)**

  `OllamaBar/Services/OllamaService.swift`:
  ```swift
  import Foundation

  enum OllamaError: Error {
      case httpError(Int)
      case decodingError(Error)
      case ollamaNotRunning
  }

  @Observable
  final class OllamaService {
      private let baseURL = URL(string: "http://localhost:11434")!
      private let session: URLSession

      private static let decoder: JSONDecoder = {
          let d = JSONDecoder()
          d.keyDecodingStrategy = .convertFromSnakeCase
          d.dateDecodingStrategy = .iso8601
          return d
      }()

      init(session: URLSession = .shared) {
          self.session = session
      }

      // MARK: - Models

      func fetchModels() async throws -> [OllamaModel] {
          let url = baseURL.appendingPathComponent("api/tags")
          let (data, response) = try await session.data(from: url)
          try validate(response)
          let decoded = try Self.decoder.decode(TagsResponse.self, from: data)
          return decoded.models
      }

      // MARK: - Generate (for DigestEngine)

      func generate(model: String, prompt: String) async throws -> String {
          let url = baseURL.appendingPathComponent("api/generate")
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false]
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, response) = try await session.data(for: request)
          try validate(response)
          let decoded = try Self.decoder.decode(GenerateResponse.self, from: data)
          return decoded.response
      }

      // MARK: - Private

      private func validate(_ response: URLResponse) throws {
          guard let http = response as? HTTPURLResponse else { return }
          guard (200..<300).contains(http.statusCode) else {
              throw OllamaError.httpError(http.statusCode)
          }
      }
  }

  // MARK: - Response types (file-private)

  private struct TagsResponse: Decodable {
      let models: [OllamaModel]
  }

  private struct GenerateResponse: Decodable {
      let response: String
      let done: Bool
  }
  ```

- [ ] **Step 5: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/OllamaServiceTests 2>&1 | grep -E "PASS|FAIL|Executed"
  ```
  Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 6: Commit**

  ```bash
  git add OllamaBar/Services/OllamaService.swift OllamaBarTests/
  git commit -m "feat: add OllamaService with fetchModels and generate endpoints"
  ```

### Task 4: OllamaService — Chat Streaming

**Files:**
- Modify: `OllamaBar/Services/OllamaService.swift`
- Modify: `OllamaBarTests/OllamaServiceTests.swift`

- [ ] **Step 1: Write failing test for streaming**

  Add to `OllamaBarTests/OllamaServiceTests.swift`:
  ```swift
  func test_chat_streamsTokens() async throws {
      // Build a newline-delimited JSON stream
      let chunks = [
          #"{"message":{"role":"assistant","content":"Hello"},"done":false}"#,
          #"{"message":{"role":"assistant","content":" world"},"done":false}"#,
          #"{"message":{"role":"assistant","content":""},"done":true}"#,
      ].joined(separator: "\n").appending("\n")

      MockURLProtocol.handler = { _ in
          (.init(url: URL(string:"http://localhost:11434/api/chat")!,
                 statusCode: 200, httpVersion: nil, headerFields: nil)!,
           chunks.data(using: .utf8)!)
      }
      let messages = [ChatMessage(role: .user, content: "hi")]
      var tokens: [String] = []
      for try await token in sut.chat(model: "llama3.2", messages: messages,
                                       systemPrompt: nil) {
          tokens.append(token)
      }
      XCTAssertEqual(tokens, ["Hello", " world", ""])
  }
  ```

- [ ] **Step 2: Run test, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/OllamaServiceTests/test_chat_streamsTokens 2>&1 | grep -E "error:|FAIL"
  ```

- [ ] **Step 3: Implement chat streaming**

  Add to `OllamaBar/Services/OllamaService.swift`:
  ```swift
  // MARK: - Chat (streaming)

  func chat(
      model: String,
      messages: [ChatMessage],
      systemPrompt: String?
  ) -> AsyncThrowingStream<String, Error> {
      AsyncThrowingStream { continuation in
          Task {
              do {
                  let url = baseURL.appendingPathComponent("api/chat")
                  var request = URLRequest(url: url)
                  request.httpMethod = "POST"
                  request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                  var apiMessages: [[String: String]] = []
                  if let systemPrompt {
                      apiMessages.append(["role": "system", "content": systemPrompt])
                  }
                  apiMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }

                  let body: [String: Any] = [
                      "model": model,
                      "messages": apiMessages,
                      "stream": true
                  ]
                  request.httpBody = try JSONSerialization.data(withJSONObject: body)

                  let (asyncBytes, response) = try await session.bytes(for: request)
                  try validate(response)

                  for try await line in asyncBytes.lines {
                      guard !line.isEmpty,
                            let data = line.data(using: .utf8),
                            let chunk = try? Self.decoder.decode(ChatChunk.self, from: data)
                      else { continue }
                      continuation.yield(chunk.message.content)
                      if chunk.done { break }
                  }
                  continuation.finish()
              } catch {
                  continuation.finish(throwing: error)
              }
          }
      }
  }
  ```

  Add to the private response types section:
  ```swift
  private struct ChatChunk: Decodable {
      struct Message: Decodable { let role: String; let content: String }
      let message: Message
      let done: Bool
  }
  ```

- [ ] **Step 4: Run all OllamaService tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/OllamaServiceTests 2>&1 | grep -E "PASS|FAIL|Executed"
  ```
  Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Services/OllamaService.swift OllamaBarTests/OllamaServiceTests.swift
  git commit -m "feat: add streaming chat to OllamaService"
  ```

### Task 5: OllamaService — Launch Ollama via Process

**Files:**
- Modify: `OllamaBar/Services/OllamaService.swift`
- Modify: `OllamaBarTests/OllamaServiceTests.swift`

- [ ] **Step 1: Write failing tests**

  Add to `OllamaBarTests/OllamaServiceTests.swift`:
  ```swift
  func test_resolveOllamaBinary_returnsNilForFakePath() {
      let result = OllamaService.resolveOllamaBinary(searchPaths: ["/nonexistent/ollama"])
      XCTAssertNil(result)
  }

  func test_resolveOllamaBinary_returnsFirstExistingPath() {
      // /usr/bin/true exists on all macOS systems and is executable
      let result = OllamaService.resolveOllamaBinary(
          searchPaths: ["/nonexistent/ollama", "/usr/bin/true"])
      XCTAssertEqual(result, URL(fileURLWithPath: "/usr/bin/true"))
  }

  func test_launchOllamaServe_throwsWhenBinaryNotFound() {
      do {
          try sut.launchOllamaServe(searchPaths: ["/nonexistent/ollama"])
          XCTFail("Should throw")
      } catch OllamaError.ollamaNotRunning {
          // expected
      } catch {
          XCTFail("Wrong error: \(error)")
      }
  }
  ```

  Update `launchOllamaServe` signature to accept an injectable `searchPaths` parameter with a default value so it is testable:
  ```swift
  func launchOllamaServe(
      searchPaths: [String] = ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"]
  ) throws { ... }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/OllamaServiceTests/test_resolveOllamaBinary_returnsNilForFakePath 2>&1 | grep -E "error:|FAIL"
  ```

- [ ] **Step 3: Implement binary resolution + launch**

  Add to `OllamaBar/Services/OllamaService.swift`:
  ```swift
  // MARK: - Launch Ollama

  static func resolveOllamaBinary(
      searchPaths: [String] = ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"]
  ) -> URL? {
      searchPaths
          .map { URL(fileURLWithPath: $0) }
          .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  func checkReachable() async -> Bool {
      do { _ = try await fetchModels(); return true }
      catch { return false }
  }

  /// Launches `ollama serve` via Process. Call `checkReachable()` first if you want to skip when already running.
  /// Throws `OllamaError.ollamaNotRunning` if the binary cannot be found.
  func launchOllamaServe(
      searchPaths: [String] = ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"]
  ) throws {
      guard let binary = Self.resolveOllamaBinary(searchPaths: searchPaths) else {
          throw OllamaError.ollamaNotRunning
      }
      let process = Process()
      process.executableURL = binary
      process.arguments = ["serve"]
      try process.run()
  }
  ```

  > Note: `AppViewModel.startOllama()` calls `await checkReachable()` before calling `launchOllamaServe()` — see Task 8.

- [ ] **Step 4: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/OllamaServiceTests 2>&1 | grep "Executed"
  ```
  Expected: `Executed 8 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Services/OllamaService.swift OllamaBarTests/OllamaServiceTests.swift
  git commit -m "feat: add Ollama binary resolution and Process-based launch"
  ```

---

## Chunk 4: ClipboardWatcher

### Task 6: ClipboardWatcher — Polling & TCC Detection

**Files:**
- Create: `OllamaBar/Services/ClipboardWatcher.swift`
- Create: `OllamaBarTests/ClipboardWatcherTests.swift`

- [ ] **Step 1: Write failing tests**

  `OllamaBarTests/ClipboardWatcherTests.swift`:
  ```swift
  import XCTest
  import AppKit
  @testable import OllamaBar

  final class ClipboardWatcherTests: XCTestCase {

      func test_poll_emitsEntryWhenChangeCountIncreases() {
          // Start at changeCount 0 so init seeds lastChangeCount=0,
          // then second call returns 1 — triggering the emission.
          var callCount = 0
          let sut = ClipboardWatcher(pasteboardProvider: {
              MockPasteboard(changeCount: callCount, string: "hello")
          })
          sut.onNewEntry = { _ in }
          // First poll: count==0, seeds lastChangeCount=0 in init already, no change.
          // So increment before polling:
          callCount = 1
          var emitted: ClipboardEntry?
          sut.onNewEntry = { emitted = $0 }
          sut.pollOnce()
          XCTAssertEqual(emitted?.text, "hello")
      }

      func test_poll_doesNotEmitWhenChangeCountSame() {
          var callCount = 0
          let sut = ClipboardWatcher(pasteboardProvider: {
              // Always returns changeCount 0 — never changes
              MockPasteboard(changeCount: 0, string: "hello")
          })
          sut.onNewEntry = { _ in callCount += 1 }
          sut.pollOnce()
          sut.pollOnce()
          XCTAssertEqual(callCount, 0) // changeCount never changed
      }

      func test_poll_emitsDeniedAfter5NilReadsWithChangingCount() {
          var deniedEmitted = false
          var count = 0
          // Init seeds lastChangeCount = 0 (first call)
          let sut = ClipboardWatcher(pasteboardProvider: {
              let result = MockPasteboard(changeCount: count, string: nil)
              count += 1
              return result
          })
          sut.onDenied = { deniedEmitted = true }
          // Each pollOnce sees a new changeCount (1,2,3,4,5) — all return nil string
          for _ in 0..<5 { sut.pollOnce() }
          XCTAssertTrue(deniedEmitted)
      }

      func test_poll_doesNotEmitDeniedBefore5NilReads() {
          var deniedEmitted = false
          var count = 0
          let sut = ClipboardWatcher(pasteboardProvider: {
              let result = MockPasteboard(changeCount: count, string: nil)
              count += 1
              return result
          })
          sut.onDenied = { deniedEmitted = true }
          for _ in 0..<4 { sut.pollOnce() }
          XCTAssertFalse(deniedEmitted)
      }
  }

  // MARK: - Test Helpers

  struct MockPasteboard: PasteboardProtocol {
      let changeCount: Int
      private let _string: String?
      init(changeCount: Int, string: String?) {
          self.changeCount = changeCount
          self._string = string
      }
      func string(forType: NSPasteboard.PasteboardType) -> String? { _string }
  }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/ClipboardWatcherTests 2>&1 | grep -E "error:|FAIL|Build"
  ```

- [ ] **Step 3: Implement ClipboardWatcher**

  `OllamaBar/Services/ClipboardWatcher.swift`:
  ```swift
  import AppKit
  import Foundation

  protocol PasteboardProtocol {
      var changeCount: Int { get }
      func string(forType: NSPasteboard.PasteboardType) -> String?
  }

  extension NSPasteboard: PasteboardProtocol {}

  @Observable
  final class ClipboardWatcher {
      var onNewEntry: ((ClipboardEntry) -> Void)?
      var onDenied: (() -> Void)?

      private let pasteboardProvider: () -> PasteboardProtocol
      private var lastChangeCount: Int = -1
      private var consecutiveNilCount = 0
      private var timer: DispatchSourceTimer?
      private let queue = DispatchQueue(label: "com.ollamabar.clipboard", qos: .background)

      init(pasteboardProvider: @escaping () -> PasteboardProtocol = { NSPasteboard.general }) {
          self.pasteboardProvider = pasteboardProvider
          self.lastChangeCount = pasteboardProvider().changeCount
      }

      func start() {
          let t = DispatchSource.makeTimerSource(queue: queue)
          t.schedule(deadline: .now(), repeating: 2.0)
          t.setEventHandler { [weak self] in self?.pollOnce() }
          t.resume()
          timer = t
      }

      func stop() {
          timer?.cancel()
          timer = nil
      }

      func pollOnce() {
          let pasteboard = pasteboardProvider()
          let currentCount = pasteboard.changeCount
          guard currentCount != lastChangeCount else { return }
          lastChangeCount = currentCount

          guard let text = pasteboard.string(forType: .string) else {
              consecutiveNilCount += 1
              if consecutiveNilCount >= 5 {
                  DispatchQueue.main.async { self.onDenied?() }
              }
              return
          }
          consecutiveNilCount = 0
          let entry = ClipboardEntry(text: text)
          DispatchQueue.main.async { self.onNewEntry?(entry) }
      }
  }
  ```

- [ ] **Step 4: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/ClipboardWatcherTests 2>&1 | grep "Executed"
  ```
  Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Services/ClipboardWatcher.swift OllamaBarTests/ClipboardWatcherTests.swift
  git commit -m "feat: add ClipboardWatcher with TCC denial detection"
  ```

---

## Chunk 5: DigestEngine

### Task 7: DigestEngine — Buffer, Eviction, and Compression

**Files:**
- Create: `OllamaBar/Services/DigestEngine.swift`
- Create: `OllamaBarTests/DigestEngineTests.swift`

- [ ] **Step 1: Write failing tests**

  `OllamaBarTests/DigestEngineTests.swift`:
  ```swift
  import XCTest
  @testable import OllamaBar

  @MainActor
  final class DigestEngineTests: XCTestCase {

      // MARK: - Buffer eviction

      func test_ingest_bufferCapsAt50() {
          let sut = DigestEngine(compress: { _, _ in "summary" })
          for i in 0..<52 {
              sut.ingest(ClipboardEntry(text: "item \(i)"))
          }
          XCTAssertEqual(sut.buffer.count, 50)
      }

      func test_ingest_dropsOldestWhenFull() {
          let sut = DigestEngine(compress: { _, _ in "summary" })
          for i in 0..<51 {
              sut.ingest(ClipboardEntry(text: "item \(i)"))
          }
          XCTAssertEqual(sut.buffer.first?.text, "item 1") // "item 0" was evicted
      }

      // MARK: - Compression trigger

      func test_ingest_triggersCompressionAfter10Entries() async {
          var compressionCallCount = 0
          let sut = DigestEngine(compress: { entries, model in
              compressionCallCount += 1
              return "compressed"
          })
          for i in 0..<10 {
              sut.ingest(ClipboardEntry(text: "item \(i)"))
          }
          // Give async Task time to run
          try? await Task.sleep(nanoseconds: 100_000_000)
          XCTAssertEqual(compressionCallCount, 1)
      }

      func test_ingest_doesNotTriggerCompressionBefore10Entries() async {
          var compressionCallCount = 0
          let sut = DigestEngine(compress: { _, _ in
              compressionCallCount += 1
              return "compressed"
          })
          for i in 0..<9 {
              sut.ingest(ClipboardEntry(text: "item \(i)"))
          }
          try? await Task.sleep(nanoseconds: 100_000_000)
          XCTAssertEqual(compressionCallCount, 0)
      }

      func test_compression_updatesDigest() async {
          let sut = DigestEngine(compress: { _, _ in "my digest result" })
          for i in 0..<10 { sut.ingest(ClipboardEntry(text: "item \(i)")) }
          try? await Task.sleep(nanoseconds: 200_000_000)
          XCTAssertEqual(sut.digest, "my digest result")
      }

      func test_compression_resetsCounterOnFailure() async {
          var callCount = 0
          let sut = DigestEngine(compress: { _, _ in
              callCount += 1
              throw TestError.compression
          })
          for i in 0..<10 { sut.ingest(ClipboardEntry(text: "item \(i)")) }
          try? await Task.sleep(nanoseconds: 200_000_000)
          // After failure, counter reset — need 10 more to trigger again
          XCTAssertEqual(sut.newSinceLastCompression, 0)
          XCTAssertEqual(callCount, 1)
      }

      // MARK: - Concurrency guard

      func test_ingest_doesNotTriggerConcurrentCompression() async {
          var callCount = 0
          let sut = DigestEngine(compress: { _, _ in
              callCount += 1
              try? await Task.sleep(nanoseconds: 100_000_000) // slow compression
              return "done"
          })
          // Trigger twice in quick succession
          for i in 0..<10 { sut.ingest(ClipboardEntry(text: "a\(i)")) }
          for i in 0..<10 { sut.ingest(ClipboardEntry(text: "b\(i)")) }
          try? await Task.sleep(nanoseconds: 500_000_000)
          XCTAssertEqual(callCount, 1) // second trigger ignored while first in-flight
      }

      // MARK: - Pinned entries

      func test_pin_addsEntryToPinnedList() {
          let sut = DigestEngine(compress: { _, _ in "" })
          let entry = ClipboardEntry(text: "important")
          sut.pin(entry)
          XCTAssertTrue(sut.pinnedEntries.contains(where: { $0.id == entry.id }))
      }

      func test_unpin_removesEntryFromPinnedList() {
          let sut = DigestEngine(compress: { _, _ in "" })
          let entry = ClipboardEntry(text: "important")
          sut.pin(entry)
          sut.unpin(entry)
          XCTAssertFalse(sut.pinnedEntries.contains(where: { $0.id == entry.id }))
      }
  }

  enum TestError: Error { case compression }
  ```

- [ ] **Step 2: Run tests, verify FAIL**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/DigestEngineTests 2>&1 | grep -E "error:|FAIL|Build"
  ```

- [ ] **Step 3: Implement DigestEngine**

  `OllamaBar/Services/DigestEngine.swift`:
  ```swift
  import Foundation

  @Observable
  @MainActor
  final class DigestEngine {
      private(set) var buffer: [ClipboardEntry] = []
      private(set) var digest: String = ""
      private(set) var pinnedEntries: [ClipboardEntry] = []
      private(set) var newSinceLastCompression: Int = 0
      private(set) var isCompressing: Bool = false

      private let compress: ([ClipboardEntry], String) async throws -> String
      private var compressionModel: String = "llama3.2"
      private var timer: Timer?

      init(
          compress: @escaping ([ClipboardEntry], String) async throws -> String,
          model: String = "llama3.2"
      ) {
          self.compress = compress
          self.compressionModel = model
          startTimer()
      }

      func setModel(_ model: String) { compressionModel = model }

      func ingest(_ entry: ClipboardEntry) {
          if buffer.count >= 50 { buffer.removeFirst() }
          buffer.append(entry)
          newSinceLastCompression += 1
          if newSinceLastCompression >= 10 { triggerCompression() }
      }

      func pin(_ entry: ClipboardEntry) {
          guard !pinnedEntries.contains(where: { $0.id == entry.id }) else { return }
          pinnedEntries.append(entry)
      }

      func unpin(_ entry: ClipboardEntry) {
          pinnedEntries.removeAll { $0.id == entry.id }
      }

      func invalidateTimer() { timer?.invalidate(); timer = nil }

      // MARK: - Private

      private func startTimer() {
          timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
              Task { @MainActor [weak self] in self?.triggerCompression() }
          }
      }

      private func triggerCompression() {
          guard !isCompressing else { return }
          isCompressing = true
          newSinceLastCompression = 0
          let entries = buffer
          let model = compressionModel
          Task { @MainActor in
              do {
                  let result = try await compress(entries, model)
                  self.digest = result
              } catch {
                  // intentional no-op: counter already reset, retry after 10 more entries
              }
              self.isCompressing = false
          }
      }
  }
  ```

- [ ] **Step 4: Run tests, verify PASS**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/DigestEngineTests 2>&1 | grep "Executed"
  ```
  Expected: `Executed 8 tests, with 0 failures`

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Services/DigestEngine.swift OllamaBarTests/DigestEngineTests.swift
  git commit -m "feat: add DigestEngine with rolling buffer, compression triggers, and pinning"
  ```

---

## Chunk 6: AppViewModel — Wiring Services Together

### Task 8: AppViewModel

**Files:**
- Modify: `OllamaBar/AppViewModel.swift`

- [ ] **Step 1: Replace stub AppViewModel with full implementation**

  `OllamaBar/AppViewModel.swift`:
  ```swift
  import SwiftUI

  @Observable
  @MainActor
  final class AppViewModel {
      // MARK: - Published state
      var isOllamaRunning = false
      var availableModels: [OllamaModel] = []
      var selectedModel: OllamaModel?
      var chatMessages: [ChatMessage] = []
      var clipboardAccessDenied = false
      var isDigestPanelExpanded = true
      var newDigestAvailable = false
      var isStreaming = false

      // MARK: - Services
      let ollamaService: OllamaService
      let clipboardWatcher: ClipboardWatcher
      let digestEngine: DigestEngine
      let persistence: PersistenceManager

      // MARK: - Computed
      var digest: String { digestEngine.digest }
      var pinnedEntries: [ClipboardEntry] { digestEngine.pinnedEntries }

      // MARK: - Init
      init(
          ollamaService: OllamaService = OllamaService(),
          persistence: PersistenceManager = PersistenceManager()
      ) {
          self.ollamaService = ollamaService
          self.persistence = persistence

          let engine = DigestEngine(
              compress: { entries, model in
                  let text = entries.map(\.text).joined(separator: "\n")
                  return try await ollamaService.generate(
                      model: model,
                      prompt: "Summarize the following clipboard history concisely in 2-3 sentences:\n\(text)"
                  )
              }
          )
          self.digestEngine = engine

          let watcher = ClipboardWatcher()
          self.clipboardWatcher = watcher

          watcher.onNewEntry = { [weak engine] entry in engine?.ingest(entry) }
          watcher.onDenied = { [weak self] in
              self?.clipboardAccessDenied = true
              watcher.stop()
              engine.invalidateTimer()
          }

          loadPersistedState()
          Task { await startPollingOllama() }
          clipboardWatcher.start()
      }

      // MARK: - Ollama control

      func startOllama() {
          Task {
              do {
                  // Skip launch if already reachable (port conflict scenario)
                  if await ollamaService.checkReachable() {
                      await startPollingOllama()
                      return
                  }
                  try ollamaService.launchOllamaServe()
                  try? await Task.sleep(nanoseconds: 2_000_000_000) // wait for startup
                  await startPollingOllama()
              } catch {
                  isOllamaRunning = false
              }
          }
      }

      func stopOllama() {
          isOllamaRunning = false
          availableModels = []
      }

      private func startPollingOllama() async {
          do {
              let models = try await ollamaService.fetchModels()
              availableModels = models
              if selectedModel == nil { selectedModel = models.first }
              isOllamaRunning = true
              digestEngine.setModel(selectedModel?.name ?? "llama3.2")
          } catch {
              isOllamaRunning = false
          }
      }

      // MARK: - Chat

      func sendMessage(_ text: String) {
          guard let model = selectedModel, !isStreaming else { return }
          let userMessage = ChatMessage(role: .user, content: text)
          chatMessages.append(userMessage)
          isStreaming = true

          let systemPrompt = buildSystemPrompt()
          var assistantMessage = ChatMessage(role: .assistant, content: "")
          chatMessages.append(assistantMessage)
          let idx = chatMessages.count - 1

          Task {
              do {
                  for try await token in ollamaService.chat(
                      model: model.name,
                      messages: chatMessages.dropLast(), // exclude empty assistant stub
                      systemPrompt: systemPrompt
                  ) {
                      chatMessages[idx].content += token
                  }
              } catch {
                  chatMessages[idx].content = "Error: \(error.localizedDescription)"
              }
              isStreaming = false
              saveHistory()
          }
      }

      func clearChat() {
          chatMessages = []
          try? persistence.saveHistory([])
      }

      // MARK: - Digest controls

      func injectDigestIntoInput() -> String { digest }

      // MARK: - Private

      private func buildSystemPrompt() -> String? {
          var parts: [String] = []
          if !digest.isEmpty { parts.append("[Context Digest]: \(digest)") }
          if !pinnedEntries.isEmpty {
              let pinned = pinnedEntries.map(\.text).joined(separator: "\n")
              parts.append("[Pinned Items]: \(pinned)")
          }
          return parts.isEmpty ? nil : parts.joined(separator: "\n")
      }

      private func loadPersistedState() {
          if let state = try? persistence.loadDigestState() {
              digestEngine.digest = state.digest  // need to expose setter — see note below
          }
          chatMessages = (try? persistence.loadHistory()) ?? []
      }

      private func saveHistory() {
          try? persistence.saveHistory(chatMessages)
      }
  }
  ```

  > **Note:** `DigestEngine.digest` needs a `fileprivate(set)` or internal setter to allow `AppViewModel` to restore persisted state on launch. Change `private(set) var digest` to `var digest` in `DigestEngine.swift`.

- [ ] **Step 2: Update DigestEngine to allow external digest assignment**

  In `OllamaBar/Services/DigestEngine.swift`, change:
  ```swift
  private(set) var digest: String = ""
  ```
  to:
  ```swift
  var digest: String = ""
  ```

- [ ] **Step 3: Build and verify no regressions**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep "Executed"
  ```
  Expected: build succeeds, all prior tests still pass.

- [ ] **Step 4: Commit**

  ```bash
  git add OllamaBar/AppViewModel.swift OllamaBar/Services/DigestEngine.swift
  git commit -m "feat: wire AppViewModel with full service coordination and chat loop"
  ```

---

## Chunk 7: Views

### Task 9: MenuBarIconView — Dynamic States

**Files:**
- Modify: `OllamaBar/Views/MenuBarIconView.swift`

- [ ] **Step 1: Implement dynamic icon**

  `OllamaBar/Views/MenuBarIconView.swift`:
  ```swift
  import SwiftUI

  struct MenuBarIconView: View {
      @Environment(AppViewModel.self) var viewModel

      var body: some View {
          ZStack(alignment: .topTrailing) {
              iconImage
              if viewModel.newDigestAvailable {
                  Circle()
                      .fill(.blue)
                      .frame(width: 6, height: 6)
                      .offset(x: 2, y: -2)
              }
          }
      }

      @ViewBuilder
      private var iconImage: some View {
          if !viewModel.isOllamaRunning {
              Image(systemName: "exclamationmark.triangle")
          } else if viewModel.isStreaming {
              Image(systemName: "brain.fill")
                  .symbolEffect(.pulse)
          } else {
              Image(systemName: "brain")
          }
      }
  }

  #Preview {
      MenuBarIconView()
          .environment(AppViewModel())
  }
  ```

- [ ] **Step 2: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add OllamaBar/Views/MenuBarIconView.swift
  git commit -m "feat: dynamic menu bar icon with state indicators"
  ```

### Task 10: StatusBar View

**Files:**
- Create: `OllamaBar/Views/StatusBar.swift`
- Modify: `OllamaBar/Services/DigestEngine.swift`
- Create: `OllamaBar/Extensions/Date+Relative.swift`

- [ ] **Step 1: Add lastDigestTime to DigestEngine and Date helper (required before StatusBar compiles)**

  In `OllamaBar/Services/DigestEngine.swift`, after `var digest: String = ""` add:
  ```swift
  var lastDigestTime: Date?
  ```
  In the success branch of `triggerCompression()`:
  ```swift
  self.digest = result
  self.lastDigestTime = Date()
  ```

  `OllamaBar/Extensions/Date+Relative.swift`:
  ```swift
  import Foundation
  extension Date {
      var relativeDescription: String {
          let formatter = RelativeDateTimeFormatter()
          formatter.unitsStyle = .abbreviated
          return formatter.localizedString(for: self, relativeTo: Date())
      }
  }
  ```

- [ ] **Step 2: Implement StatusBar**

  `OllamaBar/Views/StatusBar.swift`:
  ```swift
  import SwiftUI

  struct StatusBar: View {
      @Environment(AppViewModel.self) var viewModel

      var body: some View {
          VStack(spacing: 4) {
              HStack {
                  modelSelector
                  Spacer()
                  controlButtons
              }
              HStack {
                  statusDot
                  statusText
                  Spacer()
                  if !viewModel.digest.isEmpty {
                      Text("last digest: \(viewModel.digestEngine.lastDigestTime?.relativeDescription ?? "never")")
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                  }
              }
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
      }

      private var modelSelector: some View {
          Menu {
              ForEach(viewModel.availableModels) { model in
                  Button(model.name) { viewModel.selectedModel = model }
              }
          } label: {
              HStack(spacing: 4) {
                  Text(viewModel.selectedModel?.name ?? "No model")
                      .font(.system(.body, design: .monospaced))
                  Image(systemName: "chevron.down")
                      .font(.caption)
              }
          }
          .disabled(viewModel.availableModels.isEmpty)
      }

      private var controlButtons: some View {
          HStack(spacing: 8) {
              Button("Start") { viewModel.startOllama() }
                  .disabled(viewModel.isOllamaRunning)
              Button("Stop") { viewModel.stopOllama() }
                  .disabled(!viewModel.isOllamaRunning)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
      }

      private var statusDot: some View {
          Circle()
              .fill(viewModel.isOllamaRunning ? Color.green : Color.red)
              .frame(width: 8, height: 8)
      }

      private var statusText: some View {
          Text(viewModel.isOllamaRunning ? "Connected" : "Ollama not running")
              .font(.caption)
              .foregroundStyle(.secondary)
      }
  }

  #Preview {
      StatusBar().environment(AppViewModel())
  }
  ```

- [ ] **Step 3: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add OllamaBar/Views/StatusBar.swift OllamaBar/Services/DigestEngine.swift \
    OllamaBar/Extensions/Date+Relative.swift
  git commit -m "feat: StatusBar with model selector and Ollama start/stop controls"
  ```

### Task 11: QuickChatView

**Files:**
- Create: `OllamaBar/Views/QuickChatView.swift`

- [ ] **Step 1: Implement chat view**

  `OllamaBar/Views/QuickChatView.swift`:
  ```swift
  import SwiftUI

  struct QuickChatView: View {
      @Environment(AppViewModel.self) var viewModel

      var body: some View {
          ScrollViewReader { proxy in
              ScrollView {
                  LazyVStack(alignment: .leading, spacing: 8) {
                      ForEach(viewModel.chatMessages) { message in
                          MessageBubble(message: message)
                              .id(message.id)
                      }
                  }
                  .padding(12)
              }
              .onChange(of: viewModel.chatMessages.count) { _, _ in
                  if let last = viewModel.chatMessages.last {
                      withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                  }
              }
          }
      }
  }

  private struct MessageBubble: View {
      let message: ChatMessage

      var body: some View {
          HStack {
              if message.role == .user { Spacer(minLength: 40) }
              Text(message.content)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(message.role == .user ? Color.blue : Color(nsColor: .controlBackgroundColor))
                  .foregroundStyle(message.role == .user ? .white : .primary)
                  .clipShape(RoundedRectangle(cornerRadius: 12))
              if message.role == .assistant { Spacer(minLength: 40) }
          }
      }
  }

  #Preview {
      QuickChatView().environment(AppViewModel())
  }
  ```

- [ ] **Step 2: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add OllamaBar/Views/QuickChatView.swift
  git commit -m "feat: QuickChatView with streaming message bubbles"
  ```

### Task 12: DigestPanel

**Files:**
- Create: `OllamaBar/Views/DigestPanel.swift`

- [ ] **Step 1: Implement DigestPanel**

  `OllamaBar/Views/DigestPanel.swift`:
  ```swift
  import SwiftUI

  struct DigestPanel: View {
      @Environment(AppViewModel.self) var viewModel

      var body: some View {
          VStack(spacing: 0) {
              Divider()
              DisclosureGroup(
                  isExpanded: Binding(
                      get: { viewModel.isDigestPanelExpanded },
                      set: { viewModel.isDigestPanelExpanded = $0 }
                  )
              ) {
                  digestContent
              } label: {
                  HStack {
                      Text("Context Digest")
                          .font(.caption)
                          .fontWeight(.semibold)
                          .foregroundStyle(.secondary)
                      Spacer()
                      injectButton
                  }
                  .padding(.vertical, 6)
              }
              .padding(.horizontal, 12)
          }
      }

      @ViewBuilder
      private var digestContent: some View {
          VStack(alignment: .leading, spacing: 6) {
              if viewModel.digest.isEmpty && viewModel.pinnedEntries.isEmpty {
                  Text("No context yet — copy some text to get started")
                      .font(.caption)
                      .foregroundStyle(.tertiary)
                      .padding(.bottom, 6)
              } else {
                  if !viewModel.digest.isEmpty {
                      Text(viewModel.digest)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                          .lineLimit(3)
                  }
                  ForEach(viewModel.pinnedEntries) { entry in
                      HStack {
                          Text("📌")
                          Text(entry.text)
                              .font(.caption)
                              .lineLimit(1)
                              .truncationMode(.tail)
                          Spacer()
                          Button {
                              viewModel.digestEngine.unpin(entry)
                          } label: {
                              Image(systemName: "xmark.circle.fill")
                                  .foregroundStyle(.secondary)
                          }
                          .buttonStyle(.plain)
                      }
                  }
              }
          }
          .padding(.bottom, 8)
      }

      private var injectButton: some View {
          Button("inject") {
              // Handled by InputBar via viewModel.pendingInject
              viewModel.pendingInject = viewModel.digest
          }
          .font(.caption)
          .buttonStyle(.plain)
          .foregroundStyle(.blue)
          .disabled(viewModel.digest.isEmpty)
      }
  }

  #Preview {
      DigestPanel().environment(AppViewModel())
  }
  ```

  > **Note:** Add `var pendingInject: String? = nil` to `AppViewModel` for the inject signal.

- [ ] **Step 2: Add pendingInject to AppViewModel**

  In `OllamaBar/AppViewModel.swift`, add to the published state section:
  ```swift
  var pendingInject: String? = nil
  ```

- [ ] **Step 3: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add OllamaBar/Views/DigestPanel.swift OllamaBar/AppViewModel.swift
  git commit -m "feat: DigestPanel with digest display, pinned entries, and inject control"
  ```

### Task 13: InputBar

**Files:**
- Create: `OllamaBar/Views/InputBar.swift`

- [ ] **Step 1: Implement InputBar**

  `OllamaBar/Views/InputBar.swift`:
  ```swift
  import SwiftUI

  struct InputBar: View {
      @Environment(AppViewModel.self) var viewModel
      @State private var inputText = ""
      @FocusState private var isFocused: Bool

      var body: some View {
          VStack(spacing: 0) {
              Divider()
              HStack(spacing: 8) {
                  TextField("Type a message...", text: $inputText, axis: .vertical)
                      .lineLimit(1...4)
                      .textFieldStyle(.plain)
                      .focused($isFocused)
                      .onSubmit { sendIfNotEmpty() }

                  sendButton
                  digestMenu
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
          }
          .onChange(of: viewModel.pendingInject) { _, value in
              if let value {
                  inputText += (inputText.isEmpty ? "" : "\n") + value
                  viewModel.pendingInject = nil
                  isFocused = true
              }
          }
      }

      private var sendButton: some View {
          Button {
              sendIfNotEmpty()
          } label: {
              Image(systemName: "arrow.up.circle.fill")
                  .font(.title2)
          }
          .buttonStyle(.plain)
          .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isStreaming
                    || !viewModel.isOllamaRunning)
      }

      private var digestMenu: some View {
          Menu {
              if viewModel.pinnedEntries.isEmpty {
                  Text("No pinned items")
              } else {
                  ForEach(viewModel.pinnedEntries) { entry in
                      Button(String(entry.text.prefix(40))) {
                          inputText += (inputText.isEmpty ? "" : "\n") + entry.text
                      }
                  }
              }
          } label: {
              Image(systemName: "list.bullet.rectangle")
                  .font(.title3)
          }
          .menuStyle(.borderlessButton)
          .frame(width: 28)
          .disabled(viewModel.pinnedEntries.isEmpty)
      }

      private func sendIfNotEmpty() {
          let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty, !viewModel.isStreaming else { return }
          viewModel.sendMessage(trimmed)
          inputText = ""
      }
  }

  #Preview {
      InputBar().environment(AppViewModel())
  }
  ```

- [ ] **Step 2: Build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add OllamaBar/Views/InputBar.swift
  git commit -m "feat: InputBar with send, inject, and digest picker controls"
  ```

### Task 14: MenuBarPopover — Full Assembly

**Files:**
- Modify: `OllamaBar/Views/MenuBarPopover.swift`

- [ ] **Step 1: Assemble full popover with keyboard shortcuts and dismiss**

  `OllamaBar/Views/MenuBarPopover.swift`:
  ```swift
  import SwiftUI
  import AppKit

  struct MenuBarPopover: View {
      @Environment(AppViewModel.self) var viewModel

      var body: some View {
          VStack(spacing: 0) {
              StatusBar()
              Divider()
              QuickChatView()
                  .frame(minHeight: 200, maxHeight: .infinity)
              DigestPanel()
              InputBar()
          }
          .frame(width: 380)
          .frame(maxHeight: 600)
          .background(WindowAccessor())
          .onKeyPress(.init("k"), phases: .down, action: { event in
              guard event.modifiers.contains(.command) else { return .ignored }
              viewModel.clearChat()
              return .handled
          })
      }
  }

  // Captures the NSWindow reference for outside-click dismiss
  private struct WindowAccessor: NSViewRepresentable {
      func makeNSView(context: Context) -> NSView {
          let view = DismissableView()
          return view
      }
      func updateNSView(_ nsView: NSView, context: Context) {}
  }

  private final class DismissableView: NSView {
      private var monitor: Any?

      override func viewDidMoveToWindow() {
          super.viewDidMoveToWindow()
          guard let window else { return }
          monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak window] _ in
              window?.orderOut(nil)
          }
      }

      deinit {
          if let monitor { NSEvent.removeMonitor(monitor) }
      }
  }

  #Preview {
      MenuBarPopover().environment(AppViewModel())
  }
  ```

- [ ] **Step 2: Wire ⌘D for DigestPanel toggle in MenuBarPopover**

  Add to `MenuBarPopover.body` after the existing `.onKeyPress`:
  ```swift
  .onKeyPress(.init("d"), phases: .down, action: { event in
      guard event.modifiers.contains(.command) else { return .ignored }
      viewModel.isDigestPanelExpanded.toggle()
      return .handled
  })
  ```

- [ ] **Step 3: Full build verify**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Debug build 2>&1 | tail -3
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all tests**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep "Executed"
  ```
  Expected: all tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add OllamaBar/Views/MenuBarPopover.swift
  git commit -m "feat: assemble full MenuBarPopover with keyboard shortcuts and outside-click dismiss"
  ```

---

## Chunk 8: Integration & Polish

### Task 15: Integration Test (Manual Gate)

**Files:**
- Create: `OllamaBarTests/IntegrationTests.swift`

- [ ] **Step 1: Write integration tests**

  `OllamaBarTests/IntegrationTests.swift`:
  ```swift
  import XCTest
  @testable import OllamaBar

  final class IntegrationTests: XCTestCase {
      var sut: OllamaService!

      override func setUp() {
          super.setUp()
          guard ProcessInfo.processInfo.environment["OLLAMA_INTEGRATION_TESTS"] == "1" else {
              throw XCTSkip("Set OLLAMA_INTEGRATION_TESTS=1 to run integration tests")
          }
          sut = OllamaService()
      }

      func test_fetchModels_returnsAtLeastOneModel() async throws {
          let models = try await sut.fetchModels()
          XCTAssertFalse(models.isEmpty, "No models found — run `ollama pull llama3.2` first")
      }

      func test_chat_streamingRoundTrip() async throws {
          guard let model = try await sut.fetchModels().first else {
              XCTFail("No models available")
              return
          }
          let messages = [ChatMessage(role: .user, content: "Reply with exactly the word: PONG")]
          var response = ""
          for try await token in sut.chat(model: model.name, messages: messages, systemPrompt: nil) {
              response += token
          }
          XCTAssertTrue(response.lowercased().contains("pong"), "Got: \(response)")
      }

      func test_generate_returnsNonEmptyResponse() async throws {
          guard let model = try await sut.fetchModels().first else { return }
          let result = try await sut.generate(model: model.name, prompt: "Say hello")
          XCTAssertFalse(result.isEmpty)
      }
  }
  ```

- [ ] **Step 2: Verify integration tests skip cleanly without env var**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' \
    -only-testing:OllamaBarTests/IntegrationTests 2>&1 | grep -E "skipped|Executed"
  ```
  Expected: tests marked as skipped, 0 failures.

- [ ] **Step 3: Commit**

  ```bash
  git add OllamaBarTests/IntegrationTests.swift
  git commit -m "test: add integration tests gated on OLLAMA_INTEGRATION_TESTS=1"
  ```

### Task 16: Final Verification

- [ ] **Step 1: Clean build**

  ```bash
  xcodebuild -scheme OllamaBar -configuration Release build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Full test run**

  ```bash
  xcodebuild test -scheme OllamaBar -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
  ```
  Expected: all unit tests pass, integration tests skipped.

- [ ] **Step 3: Manual smoke test (requires Ollama running locally)**

  - Run `ollama serve` in terminal
  - Launch `OllamaBar.app` from Xcode
  - Verify: brain icon appears in menu bar (not Dock)
  - Click icon: popover appears at 380pt wide
  - Model selector shows available models
  - Type a message and press Return: response streams token by token
  - Copy text from another app: after 10 copies, digest updates
  - `[inject]` button: appends digest to input
  - `⌘K`: clears chat
  - `⌘D`: collapses/expands digest panel
  - Click outside popover: popover dismisses

- [ ] **Step 4: Final commit**

  ```bash
  git add -A
  git commit -m "feat: complete OllamaBar v1.0 — menu bar Ollama client with context digest"
  ```
