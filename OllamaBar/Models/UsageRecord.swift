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
