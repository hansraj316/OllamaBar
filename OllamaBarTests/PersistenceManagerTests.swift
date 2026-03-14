import XCTest
@testable import OllamaBar

final class PersistenceManagerTests: XCTestCase {
    var sut: PersistenceManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = PersistenceManager(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_saveAndLoadRecords_roundTrip() throws {
        let records = [
            UsageRecord(model: "llama3.2", clientApp: "curl", endpoint: "/api/generate",
                        promptTokens: 10, evalTokens: 20)
        ]
        try sut.saveUsageRecords(records)
        let loaded = try sut.loadUsageRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].model, "llama3.2")
        XCTAssertEqual(loaded[0].promptTokens, 10)
    }

    func test_loadRecords_returnsEmptyWhenFileAbsent() throws {
        XCTAssertTrue(try sut.loadUsageRecords().isEmpty)
    }

    func test_saveAndLoadSettings_roundTrip() throws {
        var s = Settings(); s.proxyPort = 11436; s.costPer1kInputTokens = 0.25
        try sut.saveSettings(s)
        let loaded = try sut.loadSettings()
        XCTAssertEqual(loaded.proxyPort, 11436)
        XCTAssertEqual(loaded.costPer1kInputTokens, 0.25, accuracy: 0.001)
    }

    func test_loadSettings_returnsDefaultsWhenFileAbsent() throws {
        XCTAssertEqual(try sut.loadSettings(), Settings())
    }
}
