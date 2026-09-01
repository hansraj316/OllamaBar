import Foundation
import Network

/// One client connection: reads the HTTP request, applies the budget policy,
/// forwards it to Ollama, and streams the response back chunk by chunk while
/// a `NDJSONParser` watches for token counts.
///
/// The response is relayed with `Transfer-Encoding: chunked` as bytes arrive,
/// so clients see tokens as Ollama produces them instead of waiting for the
/// whole reply.
final class ProxyConnection: NSObject {
    var onDone: (() -> Void)?

    private let connection: NWConnection
    private let targetURL: URL
    private let budgetSnapshot: BudgetSnapshot
    private let onRecord: ((UsageRecord) -> Void)?
    private let onBlocked: (() -> Void)?

    private var accumulatedRequest = Data()
    private var method = "POST"
    private var path = "/api/generate"
    private var headers: [(name: String, value: String)] = []
    private var clientApp = "Unknown"
    private var startedAt = Date()

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let parser = NDJSONParser()
    private var sentResponseHead = false

    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private static let hopByHopHeaders: Set<String> = [
        "host", "content-length", "connection", "transfer-encoding",
        "accept-encoding", "keep-alive", "proxy-connection", "upgrade"
    ]

    init(connection: NWConnection, targetURL: URL,
         budgetSnapshot: BudgetSnapshot, onRecord: ((UsageRecord) -> Void)?,
         onBlocked: (() -> Void)? = nil) {
        self.connection = connection
        self.targetURL = targetURL
        self.budgetSnapshot = budgetSnapshot
        self.onRecord = onRecord
        self.onBlocked = onBlocked
        super.init()
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                // Client went away: stop asking Ollama for more and let the server forget us.
                self?.task?.cancel()
                self?.onDone?()
                self?.onDone = nil
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest()
    }

    // MARK: - Request

    private func receiveRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.accumulatedRequest.append(data) }
            if error != nil {
                self.close()
            } else if isComplete || self.isRequestComplete() {
                self.processRequest()
            } else {
                self.receiveRequest()
            }
        }
    }

    private var headerEnd: Range<Data.Index>? {
        accumulatedRequest.range(of: Self.headerTerminator)
    }

    private func isRequestComplete() -> Bool {
        guard let end = headerEnd else { return false }
        let headData = accumulatedRequest.subdata(in: accumulatedRequest.startIndex..<end.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else { return true }
        let bodyCount = accumulatedRequest.endIndex - end.upperBound
        if let contentLength = Self.contentLength(in: head) {
            return bodyCount >= contentLength
        }
        return true
    }

    private static func contentLength(in head: String) -> Int? {
        for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            return Int(value)
        }
        return nil
    }

    private func processRequest() {
        guard let end = headerEnd else {
            sendAndClose(status: 400, body: #"{"error":"Malformed HTTP request"}"#)
            return
        }
        let headData = accumulatedRequest.subdata(in: accumulatedRequest.startIndex..<end.lowerBound)
        let body = accumulatedRequest.subdata(in: end.upperBound..<accumulatedRequest.endIndex)
        parseHead(String(data: headData, encoding: .utf8) ?? "")
        startedAt = Date()

        if BudgetPolicy.shouldBlock(budgetSnapshot, method: method, path: path) {
            onBlocked?()
            sendAndClose(status: 429, body: #"{"error":"Daily token budget exceeded"}"#)
            return
        }
        forward(body: body)
    }

    private func parseHead(_ head: String) {
        let lines = head.components(separatedBy: "\r\n")
        if let requestLine = lines.first {
            let parts = requestLine.split(separator: " ")
            if parts.count >= 2 {
                method = String(parts[0])
                path = String(parts[1])
            }
        }
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            headers.append((name: name, value: value))
            if name.lowercased() == "user-agent" {
                clientApp = ClientAppParser.parse(userAgent: value)
            }
        }
    }

    // MARK: - Forwarding

    private func forward(body: Data) {
        var base = targetURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let requestPath = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: base + requestPath) else {
            sendAndClose(status: 400, body: #"{"error":"Invalid request path"}"#)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        for header in headers where !Self.hopByHopHeaders.contains(header.name.lowercased()) {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if !body.isEmpty { request.httpBody = body }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600      // long generations
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    // MARK: - Responses

    private static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default:  return "Status"
        }
    }

    private func sendAndClose(status: Int, body: String) {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(payload.count)\r\n"
            + "Connection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(payload)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func close() {
        connection.cancel()
        onDone?()
        onDone = nil
    }
}

extension ProxyConnection: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 200
        let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "application/json"
        let head = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Transfer-Encoding: chunked\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Connection: close\r\n\r\n"
        sentResponseHead = true
        connection.send(content: Data(head.utf8), completion: .idempotent)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !data.isEmpty else { return }
        var chunk = Data(String(data.count, radix: 16).utf8)
        chunk.append(contentsOf: [0x0D, 0x0A])
        chunk.append(data)
        chunk.append(contentsOf: [0x0D, 0x0A])
        connection.send(content: chunk, completion: .idempotent)
        parser.ingest(data: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }

        guard sentResponseHead else {
            sendAndClose(status: 502, body: #"{"error":"OllamaBar could not reach Ollama"}"#)
            return
        }

        connection.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { [weak self] _ in
            self?.close()
        })

        if let tokens = parser.finalize() {
            let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
            let record = UsageRecord(
                model: tokens.model,
                clientApp: clientApp,
                endpoint: path,
                promptTokens: tokens.promptTokens,
                evalTokens: tokens.evalTokens,
                durationMs: duration
            )
            let onRecord = self.onRecord
            DispatchQueue.main.async { onRecord?(record) }
        }
    }
}
