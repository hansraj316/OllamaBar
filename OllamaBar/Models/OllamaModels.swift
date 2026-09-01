import Foundation

/// Shapes returned by Ollama's own management endpoints (`/api/ps`, `/api/tags`, `/api/version`).

struct OllamaModelDetails: Decodable, Equatable {
    let family: String?
    let parameterSize: String?
    let quantizationLevel: String?

    private enum CodingKeys: String, CodingKey {
        case family
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

/// A model currently resident in memory (from `/api/ps`).
struct LoadedModel: Decodable, Identifiable, Equatable {
    let name: String
    let size: Int64
    let sizeVRAM: Int64
    let expiresAt: Date?
    let details: OllamaModelDetails?

    var id: String { name }

    /// Fraction of the model held in GPU memory (1.0 = fully offloaded).
    var gpuFraction: Double {
        guard size > 0 else { return 0 }
        return min(1.0, Double(sizeVRAM) / Double(size))
    }

    private enum CodingKeys: String, CodingKey {
        case name, size, details
        case sizeVRAM = "size_vram"
        case expiresAt = "expires_at"
    }

    init(name: String, size: Int64, sizeVRAM: Int64, expiresAt: Date?, details: OllamaModelDetails?) {
        self.name = name; self.size = size; self.sizeVRAM = sizeVRAM
        self.expiresAt = expiresAt; self.details = details
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        sizeVRAM = try c.decodeIfPresent(Int64.self, forKey: .sizeVRAM) ?? 0
        expiresAt = OllamaDate.parse(try c.decodeIfPresent(String.self, forKey: .expiresAt))
        details = try c.decodeIfPresent(OllamaModelDetails.self, forKey: .details)
    }
}

/// A model available on disk (from `/api/tags`).
struct InstalledModel: Decodable, Identifiable, Equatable {
    let name: String
    let size: Int64
    let modifiedAt: Date?
    let details: OllamaModelDetails?

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, size, details
        case modifiedAt = "modified_at"
    }

    init(name: String, size: Int64, modifiedAt: Date?, details: OllamaModelDetails?) {
        self.name = name; self.size = size; self.modifiedAt = modifiedAt; self.details = details
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        modifiedAt = OllamaDate.parse(try c.decodeIfPresent(String.self, forKey: .modifiedAt))
        details = try c.decodeIfPresent(OllamaModelDetails.self, forKey: .details)
    }
}

struct OllamaModelList<Model: Decodable>: Decodable {
    let models: [Model]
}

struct OllamaVersion: Decodable {
    let version: String
}

/// Ollama emits RFC 3339 timestamps with fractional seconds, which `.iso8601` rejects.
enum OllamaDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return fractional.date(from: raw) ?? plain.date(from: raw)
    }
}

/// Ollama reports `llama3.2` and `llama3.2:latest` interchangeably depending on
/// how the client named the model; compare them on a normalised key.
enum ModelName {
    static func normalize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(":latest") { return String(trimmed.dropLast(":latest".count)) }
        return trimmed
    }
}
