import Foundation
import Network

final class ProxyConnection {
    var onDone: (() -> Void)?
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
        guard let str = String(data: accumulatedRequest, encoding: .utf8),
              let range = str.range(of: "\r\n\r\n") else { return false }
        let headers = String(str[str.startIndex..<range.lowerBound])
        let body = String(str[range.upperBound...])
        if let clLine = headers.components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") }),
           let cl = Int(clLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") {
            return body.utf8.count >= cl
        }
        return true
    }

    private func processRequest() {
        if let str = String(data: accumulatedRequest, encoding: .utf8) {
            let lines = str.components(separatedBy: "\r\n")
            if let firstLine = lines.first {
                let parts = firstLine.components(separatedBy: " ")
                if parts.count >= 2 { endpoint = parts[1] }
            }
            for line in lines {
                if line.lowercased().hasPrefix("user-agent:") {
                    userAgent = ClientAppParser.parse(
                        userAgent: line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
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
                self?.onDone?()
            })
            return
        }

        forwardToOllama()
    }

    private func forwardToOllama() {
        guard let str = String(data: accumulatedRequest, encoding: .utf8),
              let headerEnd = str.range(of: "\r\n\r\n") else {
            connection.cancel()
            onDone?()
            return
        }
        let body = String(str[headerEnd.upperBound...])
        var components = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)!
        components.path = endpoint
        guard let url = components.url else {
            connection.cancel()
            onDone?()
            return
        }

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
                let httpHeader = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
                var responseData = httpHeader.data(using: .utf8)!
                responseData.append(data)
                self.connection.send(content: responseData, completion: .contentProcessed { [weak self] _ in
                    self?.connection.cancel()
                    self?.onDone?()
                })
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
                self.connection.send(content: errResp.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
                    self?.connection.cancel()
                    self?.onDone?()
                })
            }
        }
        task.resume()
    }
}
