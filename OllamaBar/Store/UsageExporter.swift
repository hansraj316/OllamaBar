import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv, json
    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum UsageExporter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func csv(_ records: [UsageRecord]) -> String {
        var lines = ["timestamp,model,client_app,endpoint,prompt_tokens,eval_tokens,total_tokens,duration_ms"]
        for r in records {
            lines.append([
                isoFormatter.string(from: r.timestamp),
                escape(r.model),
                escape(r.clientApp),
                escape(r.endpoint),
                String(r.promptTokens),
                String(r.evalTokens),
                String(r.totalTokens),
                r.durationMs.map(String.init) ?? ""
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func json(_ records: [UsageRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    static func data(_ records: [UsageRecord], format: ExportFormat) throws -> Data {
        switch format {
        case .csv:  return Data(csv(records).utf8)
        case .json: return try json(records)
        }
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
