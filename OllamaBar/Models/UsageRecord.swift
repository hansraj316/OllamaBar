import Foundation

struct UsageRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let model: String
    let clientApp: String
    let endpoint: String
    let promptTokens: Int
    let evalTokens: Int
    /// Wall-clock time for the whole request in milliseconds.
    /// `nil` for records written by versions that did not measure latency.
    let durationMs: Int?

    init(id: UUID = UUID(), timestamp: Date = Date(), model: String,
         clientApp: String, endpoint: String, promptTokens: Int, evalTokens: Int,
         durationMs: Int? = nil) {
        self.id = id; self.timestamp = timestamp; self.model = model
        self.clientApp = clientApp; self.endpoint = endpoint
        self.promptTokens = promptTokens; self.evalTokens = evalTokens
        self.durationMs = durationMs
    }

    var totalTokens: Int { promptTokens + evalTokens }

    /// Output tokens generated per second, when the request duration is known.
    var tokensPerSecond: Double? {
        guard let durationMs, durationMs > 0, evalTokens > 0 else { return nil }
        return Double(evalTokens) / (Double(durationMs) / 1000.0)
    }
}
