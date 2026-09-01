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

    // MARK: - Ranges

    func usage(in range: UsageRange) -> [UsageRecord] {
        guard let start = range.startDate else { return records }
        return records.filter { $0.timestamp >= start }
    }

    func totalTokens(in range: UsageRange) -> Int {
        usage(in: range).reduce(0) { $0 + $1.totalTokens }
    }

    /// Tokens used on the calendar day `daysAgo` days before today.
    func totalTokens(daysAgo: Int) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -daysAgo, to: today),
              let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return records.filter { $0.timestamp >= start && $0.timestamp < end }
            .reduce(0) { $0 + $1.totalTokens }
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
    var todayRequestCount: Int { todayRecords.count }
    var yesterdayTotalTokens: Int { totalTokens(daysAgo: 1) }

    /// Change versus yesterday as a fraction (0.25 = up 25%). `nil` when yesterday had no usage.
    var todayVersusYesterday: Double? {
        let yesterday = yesterdayTotalTokens
        guard yesterday > 0 else { return nil }
        return Double(todayTotalTokens - yesterday) / Double(yesterday)
    }

    // MARK: - All time
    var allTimePromptTokens: Int { records.reduce(0) { $0 + $1.promptTokens } }
    var allTimeEvalTokens:   Int { records.reduce(0) { $0 + $1.evalTokens } }
    var allTimeTotalTokens:  Int { allTimePromptTokens + allTimeEvalTokens }

    // MARK: - Breakdown
    var breakdownByModel: [(name: String, tokens: TokenPair)] { breakdownByModel(in: .all) }
    var breakdownByApp:   [(name: String, tokens: TokenPair)] { breakdownByApp(in: .all) }

    func breakdownByModel(in range: UsageRange) -> [(name: String, tokens: TokenPair)] {
        breakdown(usage(in: range), by: \.model)
    }

    func breakdownByApp(in range: UsageRange) -> [(name: String, tokens: TokenPair)] {
        breakdown(usage(in: range), by: \.clientApp)
    }

    /// All-time tokens per model keyed on the normalised model name, for matching
    /// against Ollama's own model list.
    var tokensByNormalizedModel: [String: Int] {
        var dict: [String: Int] = [:]
        for r in records {
            dict[ModelName.normalize(r.model), default: 0] += r.totalTokens
        }
        return dict
    }

    private func breakdown(_ source: [UsageRecord],
                           by keyPath: KeyPath<UsageRecord, String>) -> [(name: String, tokens: TokenPair)] {
        var dict: [String: TokenPair] = [:]
        for r in source {
            let key = r[keyPath: keyPath]
            let existing = dict[key] ?? TokenPair(prompt: 0, eval: 0)
            dict[key] = TokenPair(prompt: existing.prompt + r.promptTokens,
                                  eval: existing.eval + r.evalTokens)
        }
        return dict.map { (name: $0.key, tokens: $0.value) }
            .sorted { $0.tokens.total > $1.tokens.total }
    }

    // MARK: - Daily trend

    struct DailyTotal: Identifiable, Equatable {
        let date: Date
        let prompt: Int
        let eval: Int
        var total: Int { prompt + eval }
        var id: Date { date }
    }

    /// One entry per calendar day for the last `days` days, oldest first, zero-filled.
    func dailyTotals(days: Int) -> [DailyTotal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard days > 0, let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        var buckets: [Date: TokenPair] = [:]
        for r in records where r.timestamp >= start {
            let day = cal.startOfDay(for: r.timestamp)
            let existing = buckets[day] ?? TokenPair(prompt: 0, eval: 0)
            buckets[day] = TokenPair(prompt: existing.prompt + r.promptTokens,
                                     eval: existing.eval + r.evalTokens)
        }
        return (0..<days).compactMap { offset -> DailyTotal? in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let pair = buckets[day] ?? TokenPair(prompt: 0, eval: 0)
            return DailyTotal(date: day, prompt: pair.prompt, eval: pair.eval)
        }
    }

    // MARK: - Activity

    /// Most recent requests, newest first.
    func recentRecords(limit: Int) -> [UsageRecord] {
        Array(records.suffix(limit).reversed())
    }

    /// Mean output speed across today's requests that recorded a duration.
    var averageTokensPerSecond: Double? {
        let rates = todayRecords.compactMap(\.tokensPerSecond)
        guard !rates.isEmpty else { return nil }
        return rates.reduce(0, +) / Double(rates.count)
    }

    /// Mean wall-clock time across today's requests that recorded a duration.
    var averageLatencyMs: Int? {
        let durations = todayRecords.compactMap(\.durationMs)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / durations.count
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

    /// Days with any usage in the heatmap window.
    var activeDayCount: Int { heatmapData.values.filter { $0 > 0 }.count }

    /// Busiest day in the heatmap window.
    var peakDayTokens: Int { heatmapData.values.max() ?? 0 }

    /// Consecutive days with usage ending today (or yesterday, if today is still quiet).
    var usageStreakDays: Int {
        let data = heatmapData
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var cursor = today
        if (data[today] ?? 0) == 0 {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while (data[cursor] ?? 0) > 0 {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
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
