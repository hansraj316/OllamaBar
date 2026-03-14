import Foundation

final class PersistenceManager {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.ollamabar.persistence", qos: .utility)

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = appSupport.appendingPathComponent("OllamaBar")
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private var recordsURL: URL { directory.appendingPathComponent("usage.json") }
    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }

    func saveUsageRecords(_ records: [UsageRecord]) throws {
        let data = try Self.encoder.encode(records)
        var writeError: Error?
        queue.sync {
            do { try data.write(to: recordsURL, options: .atomic) }
            catch { writeError = error }
        }
        if let writeError { throw writeError }
    }

    func loadUsageRecords() throws -> [UsageRecord] {
        guard FileManager.default.fileExists(atPath: recordsURL.path) else { return [] }
        return try Self.decoder.decode([UsageRecord].self, from: Data(contentsOf: recordsURL))
    }

    func saveSettings(_ settings: Settings) throws {
        let data = try Self.encoder.encode(settings)
        var writeError: Error?
        queue.sync {
            do { try data.write(to: settingsURL, options: .atomic) }
            catch { writeError = error }
        }
        if let writeError { throw writeError }
    }

    func loadSettings() throws -> Settings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return Settings() }
        return try Self.decoder.decode(Settings.self, from: Data(contentsOf: settingsURL))
    }
}
