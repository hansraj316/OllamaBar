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
}
