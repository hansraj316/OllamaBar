import XCTest
import Network
@testable import OllamaBar

final class ProxyServerTests: XCTestCase {

    // URLSession with short timeout
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    func test_fullProxyRoundTrip_forwardsResponseAndRecordsTokens() async throws {
        // 1. Start mock Ollama server
        let mockPort: NWEndpoint.Port = 19434
        let mockBody = """
        {"model":"test-model","response":"Hello","done":false}
        {"model":"test-model","response":"","done":true,"prompt_eval_count":15,"eval_count":42}
        """
        let mockServer = MockHTTPServer(port: mockPort, responseBody: mockBody)
        try await mockServer.startAndWaitReady()
        defer { mockServer.stop() }

        // 2. Start proxy pointing at mock
        var receivedRecord: UsageRecord?
        let proxy = ProxyServer(
            port: 19435,
            targetURL: URL(string: "http://127.0.0.1:19434")!
        )
        proxy.onRecord = { record in receivedRecord = record }
        proxy.budgetSnapshot = BudgetSnapshot(dailyBudgetTokens: 0, todayTotalTokens: 0, budgetMode: .soft)
        try await proxy.startAndWaitReady()
        defer { proxy.stop() }

        // 3. Send request through proxy
        let url = URL(string: "http://127.0.0.1:19435/api/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = #"{"model":"test-model","prompt":"hi","stream":true}"#.data(using: .utf8)
        req.setValue("curl/7.88", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await session.data(for: req)

        // 4. Assert response bytes match mock output
        let responseStr = String(data: data, encoding: .utf8)!
        XCTAssertTrue(responseStr.contains("Hello"))

        // 5. Assert UsageRecord created
        try await Task.sleep(nanoseconds: 200_000_000)
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
        try await proxy.startAndWaitReady()
        defer { proxy.stop() }

        let url = URL(string: "http://127.0.0.1:19436/api/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = "{}".data(using: .utf8)
        let (_, response) = try await session.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 429)
    }
}

// MARK: - ProxyServer async start helper

extension ProxyServer {
    func startAndWaitReady() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            self.onReady = {
                guard !resumed else { return }
                resumed = true
                cont.resume()
            }
            do {
                try self.start()
            } catch {
                resumed = true
                cont.resume(throwing: error)
            }
        }
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

    func startAndWaitReady() async throws {
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
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            listener?.stateUpdateHandler = { state in
                if case .ready = state, !resumed {
                    resumed = true
                    cont.resume()
                }
            }
            listener?.start(queue: .global())
        }
    }

    func stop() { listener?.cancel() }
}
