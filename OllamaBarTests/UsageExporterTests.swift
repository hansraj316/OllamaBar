import XCTest
@testable import OllamaBar

final class UsageExporterTests: XCTestCase {

    private func record(model: String = "llama3.2", app: String = "curl",
                        prompt: Int = 10, eval: Int = 20, durationMs: Int? = 1500) -> UsageRecord {
        UsageRecord(timestamp: Date(timeIntervalSince1970: 1_700_000_000), model: model, clientApp: app,
                    endpoint: "/api/chat", promptTokens: prompt, evalTokens: eval, durationMs: durationMs)
    }

    func test_csv_hasHeaderAndOneRowPerRecord() {
        let csv = UsageExporter.csv([record(), record(prompt: 1, eval: 2, durationMs: nil)])
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "timestamp,model,client_app,endpoint,prompt_tokens,eval_tokens,total_tokens,duration_ms")
        XCTAssertEqual(lines[1], "2023-11-14T22:13:20Z,llama3.2,curl,/api/chat,10,20,30,1500")
        XCTAssertTrue(lines[2].hasSuffix(",1,2,3,"), "missing duration exports as an empty field")
    }

    func test_csv_quotesFieldsContainingCommasOrQuotes() {
        let csv = UsageExporter.csv([record(model: "my,model", app: "say \"hi\"")])
        XCTAssertTrue(csv.contains("\"my,model\""))
        XCTAssertTrue(csv.contains("\"say \"\"hi\"\"\""))
    }

    func test_json_roundTripsThroughDecoder() throws {
        let original = [record(), record(model: "phi3", durationMs: nil)]
        let data = try UsageExporter.json(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([UsageRecord].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_data_dispatchesOnFormat() throws {
        let records = [record()]
        XCTAssertEqual(try UsageExporter.data(records, format: .csv), Data(UsageExporter.csv(records).utf8))
        XCTAssertEqual(try UsageExporter.data(records, format: .json), try UsageExporter.json(records))
    }
}
