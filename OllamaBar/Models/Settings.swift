import Foundation

enum BudgetMode: String, Codable, CaseIterable { case soft, hard }

struct Settings: Codable, Equatable {
    var proxyPort: Int = 11435
    var targetURL: String = "http://localhost:11434"
    var dailyBudgetTokens: Int = 0
    var budgetMode: BudgetMode = .soft
    var costPer1kInputTokens: Double = 0.0
    var costPer1kOutputTokens: Double = 0.0
    var notifyOnBudget: Bool = false
    var showTokensInMenuBar: Bool = true
    var showEdgeGauges: Bool = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case proxyPort, targetURL, dailyBudgetTokens, budgetMode
        case costPer1kInputTokens, costPer1kOutputTokens
        case notifyOnBudget, showTokensInMenuBar, showEdgeGauges
    }

    /// Tolerant decoding: settings files written by older versions lack the newer keys,
    /// and each missing key falls back to its default instead of failing the whole load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        proxyPort             = try c.decodeIfPresent(Int.self,        forKey: .proxyPort)             ?? d.proxyPort
        targetURL             = try c.decodeIfPresent(String.self,     forKey: .targetURL)             ?? d.targetURL
        dailyBudgetTokens     = try c.decodeIfPresent(Int.self,        forKey: .dailyBudgetTokens)     ?? d.dailyBudgetTokens
        budgetMode            = try c.decodeIfPresent(BudgetMode.self, forKey: .budgetMode)            ?? d.budgetMode
        costPer1kInputTokens  = try c.decodeIfPresent(Double.self,     forKey: .costPer1kInputTokens)  ?? d.costPer1kInputTokens
        costPer1kOutputTokens = try c.decodeIfPresent(Double.self,     forKey: .costPer1kOutputTokens) ?? d.costPer1kOutputTokens
        notifyOnBudget        = try c.decodeIfPresent(Bool.self,       forKey: .notifyOnBudget)        ?? d.notifyOnBudget
        showTokensInMenuBar   = try c.decodeIfPresent(Bool.self,       forKey: .showTokensInMenuBar)   ?? d.showTokensInMenuBar
        showEdgeGauges        = try c.decodeIfPresent(Bool.self,       forKey: .showEdgeGauges)        ?? d.showEdgeGauges
    }
}
