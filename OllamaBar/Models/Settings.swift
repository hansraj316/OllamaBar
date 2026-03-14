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
