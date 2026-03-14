import Foundation
import Observation

@Observable
@MainActor
final class UsageStore {
    private(set) var records: [UsageRecord]
    private let persistence: PersistenceManager

    init(records: [UsageRecord] = [], persistence: PersistenceManager = PersistenceManager()) {
        self.records = records
        self.persistence = persistence
    }

    func append(_ record: UsageRecord) {
        records.append(record)
        try? persistence.saveUsageRecords(records)
    }

    func reset() {
        records = []
        try? persistence.saveUsageRecords([])
    }

    func load() {
        records = (try? persistence.loadUsageRecords()) ?? []
    }

    // MARK: - Today
    var todayRecords: [UsageRecord] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return records.filter { $0.timestamp >= today && $0.timestamp < tomorrow }
    }

    var todayPromptTokens: Int { todayRecords.reduce(0) { $0 + $1.promptTokens } }
    var todayEvalTokens:   Int { todayRecords.reduce(0) { $0 + $1.evalTokens } }
    var todayTotalTokens:  Int { todayPromptTokens + todayEvalTokens }

    // MARK: - All time
    var allTimePromptTokens: Int { records.reduce(0) { $0 + $1.promptTokens } }
    var allTimeEvalTokens:   Int { records.reduce(0) { $0 + $1.evalTokens } }
    var allTimeTotalTokens:  Int { allTimePromptTokens + allTimeEvalTokens }

    // MARK: - Breakdown
    var breakdownByModel: [(name: String, tokens: TokenPair)] { breakdown(by: \.model) }
    var breakdownByApp:   [(name: String, tokens: TokenPair)] { breakdown(by: \.clientApp) }

    private func breakdown(by keyPath: KeyPath<UsageRecord, String>) -> [(name: String, tokens: TokenPair)] {
        var dict: [String: TokenPair] = [:]
        for r in records {
            let key = r[keyPath: keyPath]
            let existing = dict[key] ?? TokenPair(prompt: 0, eval: 0)
            dict[key] = TokenPair(prompt: existing.prompt + r.promptTokens,
                                  eval: existing.eval + r.evalTokens)
        }
        return dict.map { (name: $0.key, tokens: $0.value) }
            .sorted { $0.tokens.total > $1.tokens.total }
    }

    // MARK: - Heatmap (91 days)
    var heatmapData: [Date: Int] {
        let today = Calendar.current.startOfDay(for: Date())
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -91, to: today) else { return [:] }
        var result: [Date: Int] = [:]
        for r in records where r.timestamp >= cutoff {
            let day = Calendar.current.startOfDay(for: r.timestamp)
            result[day, default: 0] += r.promptTokens + r.evalTokens
        }
        return result
    }

    // MARK: - Burn rate
    var burnRate: Double? {
        guard todayRecords.count >= 2 else { return nil }
        let cal = Calendar.current
        let now = Date()
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let elapsedHours = max(1.0 / 60.0, Double(minutes) / 60.0)
        return Double(todayTotalTokens) / elapsedHours
    }

    var projectedDayTotal: Int? {
        guard let rate = burnRate else { return nil }
        let cal = Calendar.current
        let now = Date()
        let remainingMinutes = (23 - cal.component(.hour, from: now)) * 60
            + (59 - cal.component(.minute, from: now))
        let remainingHours = Double(remainingMinutes) / 60.0
        return todayTotalTokens + Int(rate * remainingHours)
    }

    // MARK: - Efficiency
    var efficiencyScore: Double? {
        guard todayPromptTokens > 0 else { return nil }
        return Double(todayEvalTokens) / Double(todayPromptTokens)
    }
}
