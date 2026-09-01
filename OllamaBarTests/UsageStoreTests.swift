import XCTest
@testable import OllamaBar

@MainActor
final class UsageStoreTests: XCTestCase {

    func makeRecord(model: String = "llama3.2", app: String = "curl",
                    prompt: Int, eval: Int, daysAgo: Int = 0) -> UsageRecord {
        let ts = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return UsageRecord(timestamp: ts, model: model, clientApp: app,
                           endpoint: "/api/generate", promptTokens: prompt, evalTokens: eval)
    }

    func test_todayTotals() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 10, eval: 20),
            makeRecord(prompt: 5,  eval: 15)
        ])
        XCTAssertEqual(sut.todayPromptTokens, 15)
        XCTAssertEqual(sut.todayEvalTokens, 35)
        XCTAssertEqual(sut.todayTotalTokens, 50)
    }

    func test_pastRecordNotCountedInToday() {
        let sut = UsageStore(records: [makeRecord(prompt: 100, eval: 200, daysAgo: 1)])
        XCTAssertEqual(sut.todayTotalTokens, 0)
    }

    func test_allTimeTotals() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 10, eval: 20),
            makeRecord(prompt: 5, eval: 15, daysAgo: 5)
        ])
        XCTAssertEqual(sut.allTimePromptTokens, 15)
        XCTAssertEqual(sut.allTimeEvalTokens, 35)
    }

    func test_breakdownByModel_sortedDescending() {
        let sut = UsageStore(records: [
            makeRecord(model: "llama3.2", prompt: 100, eval: 200),
            makeRecord(model: "mistral", prompt: 10, eval: 20),
            makeRecord(model: "llama3.2", prompt: 50, eval: 100)
        ])
        let breakdown = sut.breakdownByModel
        XCTAssertEqual(breakdown[0].name, "llama3.2")
        XCTAssertEqual(breakdown[0].tokens.total, 450)
        XCTAssertEqual(breakdown[1].name, "mistral")
    }

    func test_breakdownByApp() {
        let sut = UsageStore(records: [
            makeRecord(app: "Cursor", prompt: 100, eval: 200),
            makeRecord(app: "curl",   prompt: 10,  eval: 20)
        ])
        XCTAssertEqual(sut.breakdownByApp[0].name, "Cursor")
    }

    func test_burnRate_nilWhenFewerThan2Records() {
        let sut = UsageStore(records: [makeRecord(prompt: 100, eval: 200)])
        XCTAssertNil(sut.burnRate)
    }

    func test_burnRate_nonNilWith2OrMoreRecords() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 100, eval: 200),
            makeRecord(prompt: 50,  eval: 100)
        ])
        XCTAssertNotNil(sut.burnRate)
        XCTAssertGreaterThan(sut.burnRate!, 0)
    }

    func test_efficiencyScore_nilWhenNoPromptTokens() {
        let sut = UsageStore(records: [])
        XCTAssertNil(sut.efficiencyScore)
    }

    func test_efficiencyScore_calculatedCorrectly() {
        let sut = UsageStore(records: [makeRecord(prompt: 100, eval: 200)])
        XCTAssertEqual(sut.efficiencyScore!, 2.0, accuracy: 0.001)
    }

    func test_heatmapData_bucketsRecordsByDay() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 10, eval: 20),
            makeRecord(prompt: 5, eval: 15),
            makeRecord(prompt: 100, eval: 200, daysAgo: 3)
        ])
        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(sut.heatmapData[today], 50)
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: today)!
        XCTAssertEqual(sut.heatmapData[threeDaysAgo], 300)
    }

    func test_heatmapData_excludesRecordsOlderThan91Days() {
        let sut = UsageStore(records: [makeRecord(prompt: 10, eval: 20, daysAgo: 92)])
        XCTAssertTrue(sut.heatmapData.isEmpty)
    }

    // MARK: - Ranges and trend

    func test_usageInRange_filtersByStartDate() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 1, eval: 1),
            makeRecord(prompt: 2, eval: 2, daysAgo: 3),
            makeRecord(prompt: 4, eval: 4, daysAgo: 10),
            makeRecord(prompt: 8, eval: 8, daysAgo: 40)
        ])
        XCTAssertEqual(sut.totalTokens(in: .today), 2)
        XCTAssertEqual(sut.totalTokens(in: .week), 6)
        XCTAssertEqual(sut.totalTokens(in: .month), 14)
        XCTAssertEqual(sut.totalTokens(in: .all), 30)
    }

    func test_breakdownInRange_onlyCountsRecordsInside() {
        let sut = UsageStore(records: [
            makeRecord(model: "old", prompt: 100, eval: 100, daysAgo: 20),
            makeRecord(model: "new", prompt: 1, eval: 1)
        ])
        XCTAssertEqual(sut.breakdownByModel(in: .today).map(\.name), ["new"])
        XCTAssertEqual(sut.breakdownByModel(in: .all).map(\.name), ["old", "new"])
    }

    func test_dailyTotals_zeroFillsAndOrdersOldestFirst() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 10, eval: 5),
            makeRecord(prompt: 1, eval: 2, daysAgo: 2)
        ])
        let totals = sut.dailyTotals(days: 7)
        XCTAssertEqual(totals.count, 7)
        XCTAssertEqual(totals.last?.total, 15)
        XCTAssertEqual(totals[4].total, 3)
        XCTAssertEqual(totals[4].prompt, 1)
        XCTAssertEqual(totals[0].total, 0)
        XCTAssertTrue(zip(totals, totals.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    func test_todayVersusYesterday() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 100, eval: 100, daysAgo: 1),
            makeRecord(prompt: 200, eval: 100)
        ])
        XCTAssertEqual(sut.yesterdayTotalTokens, 200)
        XCTAssertEqual(sut.todayVersusYesterday!, 0.5, accuracy: 0.001)
        XCTAssertNil(UsageStore(records: [makeRecord(prompt: 1, eval: 1)]).todayVersusYesterday)
    }

    // MARK: - Activity

    func test_recentRecords_newestFirstAndLimited() {
        let records = (0..<5).map { i in
            UsageRecord(timestamp: Date(timeIntervalSinceNow: Double(i)), model: "m\(i)",
                        clientApp: "curl", endpoint: "/api/chat", promptTokens: 1, evalTokens: 1)
        }
        let sut = UsageStore(records: records)
        XCTAssertEqual(sut.recentRecords(limit: 3).map(\.model), ["m4", "m3", "m2"])
    }

    func test_averageSpeedAndLatency_ignoreRecordsWithoutDuration() {
        let sut = UsageStore(records: [
            UsageRecord(model: "a", clientApp: "x", endpoint: "/api/chat", promptTokens: 1, evalTokens: 100, durationMs: 1000),
            UsageRecord(model: "a", clientApp: "x", endpoint: "/api/chat", promptTokens: 1, evalTokens: 50, durationMs: 2000),
            UsageRecord(model: "a", clientApp: "x", endpoint: "/api/chat", promptTokens: 1, evalTokens: 999)
        ])
        XCTAssertEqual(sut.averageTokensPerSecond!, 62.5, accuracy: 0.001)
        XCTAssertEqual(sut.averageLatencyMs, 1500)
        XCTAssertNil(UsageStore(records: []).averageTokensPerSecond)
    }

    func test_tokensByNormalizedModel_mergesLatestTag() {
        let sut = UsageStore(records: [
            makeRecord(model: "llama3.2", prompt: 1, eval: 1),
            makeRecord(model: "llama3.2:latest", prompt: 2, eval: 2)
        ])
        XCTAssertEqual(sut.tokensByNormalizedModel["llama3.2"], 6)
    }

    // MARK: - Heatmap stats

    func test_activeDaysPeakAndStreak() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 10, eval: 10),
            makeRecord(prompt: 50, eval: 50, daysAgo: 1),
            makeRecord(prompt: 5, eval: 5, daysAgo: 2),
            makeRecord(prompt: 5, eval: 5, daysAgo: 5)
        ])
        XCTAssertEqual(sut.activeDayCount, 4)
        XCTAssertEqual(sut.peakDayTokens, 100)
        XCTAssertEqual(sut.usageStreakDays, 3)
    }

    func test_streak_countsFromYesterdayWhenTodayIsQuiet() {
        let sut = UsageStore(records: [
            makeRecord(prompt: 1, eval: 1, daysAgo: 1),
            makeRecord(prompt: 1, eval: 1, daysAgo: 2)
        ])
        XCTAssertEqual(sut.usageStreakDays, 2)
        XCTAssertEqual(UsageStore(records: []).usageStreakDays, 0)
    }
}
