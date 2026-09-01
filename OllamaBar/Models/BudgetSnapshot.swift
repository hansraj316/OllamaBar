import Foundation

struct BudgetSnapshot {
    let dailyBudgetTokens: Int
    let todayTotalTokens: Int
    let budgetMode: BudgetMode

    var isExceeded: Bool { dailyBudgetTokens > 0 && todayTotalTokens >= dailyBudgetTokens }
}

/// Decides which requests a hard budget may refuse.
/// Only generation endpoints consume tokens; listing models, pulling, or version
/// checks must keep working so clients like Open WebUI do not break when the cap is hit.
enum BudgetPolicy {
    static let meteredPaths: Set<String> = [
        "/api/generate", "/api/chat", "/api/embed", "/api/embeddings",
        "/v1/chat/completions", "/v1/completions", "/v1/embeddings"
    ]

    static func isMetered(method: String, path: String) -> Bool {
        guard method.uppercased() == "POST" else { return false }
        let clean = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? path
        return meteredPaths.contains(clean)
    }

    static func shouldBlock(_ snapshot: BudgetSnapshot, method: String, path: String) -> Bool {
        snapshot.budgetMode == .hard && snapshot.isExceeded && isMetered(method: method, path: path)
    }
}
