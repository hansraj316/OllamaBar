import XCTest
@testable import OllamaBar

@MainActor
final class SettingsStoreTests: XCTestCase {

    func test_defaults() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sut = SettingsStore(persistence: PersistenceManager(directory: dir))
        XCTAssertEqual(sut.settings.proxyPort, 11435)
        XCTAssertEqual(sut.settings.targetURL, "http://localhost:11434")
        XCTAssertEqual(sut.settings.budgetMode, .soft)
    }

    func test_updatePersists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let persistence = PersistenceManager(directory: dir)
        let sut = SettingsStore(persistence: persistence)
        sut.settings.proxyPort = 11440
        // reload from same persistence
        let sut2 = SettingsStore(persistence: persistence)
        XCTAssertEqual(sut2.settings.proxyPort, 11440)
    }
}
