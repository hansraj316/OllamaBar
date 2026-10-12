import Foundation

struct UsageRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let model: String
    let clientApp: String
    let endpoint: String
    /// Total input tokens, cached ones included.
    let promptTokens: Int
    let evalTokens: Int
    /// Wall-clock time for the whole request in milliseconds.
    /// `nil` for records written by versions that did not measure latency.
    let durationMs: Int?
    /// Input tokens served from Ollama's prompt cache; a subset of `promptTokens`.
    /// `nil` when the response did not report it (older Ollama, or a dialect without it).
    let cachedPromptTokens: Int?
    /// Ollama's own timers from the native `done:true` chunk, in nanoseconds.
    /// `nil` for OpenAI- and Anthropic-compatible responses, which do not carry them.
    let loadDurationNs: Int?
    let promptEvalDurationNs: Int?
    let evalDurationNs: Int?

    /// A model load at least this long means it was read from disk rather than already resident.
    static let coldLoadThresholdNs = 500_000_000

    init(id: UUID = UUID(), timestamp: Date = Date(), model: String,
         clientApp: String, endpoint: String, promptTokens: Int, evalTokens: Int,
         durationMs: Int? = nil, cachedPromptTokens: Int? = nil,
         loadDurationNs: Int? = nil, promptEvalDurationNs: Int? = nil, evalDurationNs: Int? = nil) {
        self.id = id; self.timestamp = timestamp; self.model = model
        self.clientApp = clientApp; self.endpoint = endpoint
        self.promptTokens = promptTokens; self.evalTokens = evalTokens
        self.durationMs = durationMs
        self.cachedPromptTokens = cachedPromptTokens
        self.loadDurationNs = loadDurationNs
        self.promptEvalDurationNs = promptEvalDurationNs
        self.evalDurationNs = evalDurationNs
    }

    var totalTokens: Int { promptTokens + evalTokens }

    /// Output tokens generated per second. Uses Ollama's own generation timer when the response
    /// reported one, so model loading and prompt processing do not drag the number down; falls
    /// back to wall-clock time otherwise.
    var tokensPerSecond: Double? {
        guard evalTokens > 0 else { return nil }
        if let evalDurationNs, evalDurationNs > 0 {
            return Double(evalTokens) / (Double(evalDurationNs) / 1_000_000_000)
        }
        guard let durationMs, durationMs > 0 else { return nil }
        return Double(evalTokens) / (Double(durationMs) / 1000.0)
    }

    /// True when `tokensPerSecond` comes from Ollama's generation timer rather than wall-clock.
    var hasMeasuredSpeed: Bool { (evalDurationNs ?? 0) > 0 && evalTokens > 0 }

    var loadDurationMs: Int? { loadDurationNs.map { $0 / 1_000_000 } }

    /// The model had to be loaded into memory for this request.
    var isColdLoad: Bool { (loadDurationNs ?? 0) >= Self.coldLoadThresholdNs }

    /// Share of this request's prompt served from cache, when the response reported it.
    var cacheHitRate: Double? {
        guard let cachedPromptTokens, promptTokens > 0 else { return nil }
        return min(1, Double(cachedPromptTokens) / Double(promptTokens))
    }
}
