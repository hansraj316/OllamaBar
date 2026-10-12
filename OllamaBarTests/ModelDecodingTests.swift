import XCTest
@testable import OllamaBar

final class ModelDecodingTests: XCTestCase {

    // MARK: - Backwards compatibility with files written by earlier versions

    func test_usageRecord_decodesWithoutDurationField() throws {
        let legacy = """
        {"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","timestamp":"2026-03-13T10:00:00Z",
         "model":"llama3.2","clientApp":"curl","endpoint":"/api/generate","promptTokens":10,"evalTokens":20}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(UsageRecord.self, from: Data(legacy.utf8))
        XCTAssertNil(record.durationMs)
        XCTAssertEqual(record.totalTokens, 30)
        XCTAssertNil(record.tokensPerSecond)
    }

    func test_usageRecord_tokensPerSecond() {
        let record = UsageRecord(model: "m", clientApp: "a", endpoint: "/api/chat",
                                 promptTokens: 5, evalTokens: 100, durationMs: 2000)
        XCTAssertEqual(record.tokensPerSecond!, 50, accuracy: 0.001)
    }

    func test_usageRecord_decodesWithoutCacheOrTimingFields() throws {
        let v30 = """
        {"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","timestamp":"2026-09-01T10:00:00Z",
         "model":"llama3.2","clientApp":"curl","endpoint":"/api/chat","promptTokens":10,"evalTokens":20,"durationMs":900}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(UsageRecord.self, from: Data(v30.utf8))
        XCTAssertEqual(record.durationMs, 900)
        XCTAssertNil(record.cachedPromptTokens)
        XCTAssertNil(record.evalDurationNs)
        XCTAssertFalse(record.isColdLoad)
        XCTAssertNil(record.cacheHitRate)
    }

    func test_usageRecord_speedPrefersOllamaEvalTimerOverWallClock() {
        // 100 tokens in 1 s of generation, but 5 s wall-clock because the model was cold.
        let record = UsageRecord(model: "m", clientApp: "a", endpoint: "/api/chat",
                                 promptTokens: 5, evalTokens: 100, durationMs: 5000,
                                 loadDurationNs: 3_500_000_000, evalDurationNs: 1_000_000_000)
        XCTAssertEqual(record.tokensPerSecond!, 100, accuracy: 0.001)
        XCTAssertTrue(record.hasMeasuredSpeed)
    }

    func test_usageRecord_speedFallsBackToWallClockWithoutEvalTimer() {
        let record = UsageRecord(model: "m", clientApp: "a", endpoint: "/v1/messages",
                                 promptTokens: 5, evalTokens: 100, durationMs: 4000)
        XCTAssertEqual(record.tokensPerSecond!, 25, accuracy: 0.001)
        XCTAssertFalse(record.hasMeasuredSpeed)
    }

    func test_usageRecord_coldLoadThreshold() {
        func record(loadNs: Int?) -> UsageRecord {
            UsageRecord(model: "m", clientApp: "a", endpoint: "/api/chat", promptTokens: 1, evalTokens: 1,
                        loadDurationNs: loadNs)
        }
        XCTAssertFalse(record(loadNs: nil).isColdLoad)
        XCTAssertFalse(record(loadNs: 80_000_000).isColdLoad, "an already-loaded model reports tens of ms")
        XCTAssertTrue(record(loadNs: UsageRecord.coldLoadThresholdNs).isColdLoad)
        XCTAssertTrue(record(loadNs: 2_400_000_000).isColdLoad)
        XCTAssertEqual(record(loadNs: 2_400_000_000).loadDurationMs, 2400)
    }

    func test_usageRecord_cacheHitRateIsClampedToOne() {
        let normal = UsageRecord(model: "m", clientApp: "a", endpoint: "/api/chat",
                                 promptTokens: 200, evalTokens: 1, cachedPromptTokens: 150)
        XCTAssertEqual(normal.cacheHitRate!, 0.75, accuracy: 0.001)
        let odd = UsageRecord(model: "m", clientApp: "a", endpoint: "/api/chat",
                              promptTokens: 10, evalTokens: 1, cachedPromptTokens: 40)
        XCTAssertEqual(odd.cacheHitRate!, 1, accuracy: 0.001)
    }

    func test_settings_decodesLegacyFileWithDefaultsForNewKeys() throws {
        let legacy = #"{"proxyPort":11440,"targetURL":"http://localhost:11434","dailyBudgetTokens":500,"budgetMode":"hard","costPer1kInputTokens":0.1,"costPer1kOutputTokens":0.2}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(settings.proxyPort, 11440)
        XCTAssertEqual(settings.budgetMode, .hard)
        XCTAssertEqual(settings.dailyBudgetTokens, 500)
        XCTAssertFalse(settings.notifyOnBudget)
        XCTAssertTrue(settings.showTokensInMenuBar)
        XCTAssertFalse(settings.showEdgeGauges)
    }

    func test_settings_roundTripsNewKeys() throws {
        var settings = Settings()
        settings.notifyOnBudget = true
        settings.showTokensInMenuBar = false
        settings.showEdgeGauges = true
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
    }

    // MARK: - Ollama management endpoints

    func test_decodesLoadedModelsFromPs() throws {
        let json = """
        {"models":[{"name":"llama3.2:latest","model":"llama3.2:latest","size":4000,"size_vram":3000,
          "expires_at":"2026-03-13T10:05:00.123456-07:00",
          "details":{"family":"llama","parameter_size":"3.2B","quantization_level":"Q4_K_M"}}]}
        """
        let list = try JSONDecoder().decode(OllamaModelList<LoadedModel>.self, from: Data(json.utf8))
        XCTAssertEqual(list.models.count, 1)
        let model = list.models[0]
        XCTAssertEqual(model.name, "llama3.2:latest")
        XCTAssertEqual(model.gpuFraction, 0.75, accuracy: 0.001)
        XCTAssertNotNil(model.expiresAt, "fractional-second RFC 3339 timestamps must parse")
        XCTAssertEqual(model.details?.parameterSize, "3.2B")
    }

    func test_decodesInstalledModelsFromTags_withMissingOptionalFields() throws {
        let json = #"{"models":[{"name":"phi3:mini","size":2300000000,"modified_at":"2026-03-01T08:00:00Z"},{"name":"bare"}]}"#
        let list = try JSONDecoder().decode(OllamaModelList<InstalledModel>.self, from: Data(json.utf8))
        XCTAssertEqual(list.models.map(\.name), ["phi3:mini", "bare"])
        XCTAssertNotNil(list.models[0].modifiedAt)
        XCTAssertEqual(list.models[1].size, 0)
        XCTAssertNil(list.models[1].details)
    }

    func test_decodesVersion() throws {
        let version = try JSONDecoder().decode(OllamaVersion.self, from: Data(#"{"version":"0.6.2"}"#.utf8))
        XCTAssertEqual(version.version, "0.6.2")
    }

    func test_modelNameNormalization() {
        XCTAssertEqual(ModelName.normalize("llama3.2:latest"), "llama3.2")
        XCTAssertEqual(ModelName.normalize("llama3.2"), "llama3.2")
        XCTAssertEqual(ModelName.normalize("qwen2.5:7b"), "qwen2.5:7b")
    }
}
