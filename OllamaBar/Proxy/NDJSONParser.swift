import Foundation

struct ParsedTokens {
    let model: String
    let promptTokens: Int
    let evalTokens: Int
}

final class NDJSONParser {
    private var result: ParsedTokens?

    private struct DoneChunk: Decodable {
        let done: Bool
        let model: String?
        let promptEvalCount: Int?
        let evalCount: Int?
        enum CodingKeys: String, CodingKey {
            case done, model
            case promptEvalCount = "prompt_eval_count"
            case evalCount = "eval_count"
        }
    }

    func ingest(line: String) {
        guard result == nil,
              let data = line.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(DoneChunk.self, from: data),
              chunk.done
        else { return }
        result = ParsedTokens(
            model: chunk.model ?? "unknown",
            promptTokens: chunk.promptEvalCount ?? 0,
            evalTokens: chunk.evalCount ?? 0
        )
    }

    func finalize() -> ParsedTokens? { result }
}

enum ClientAppParser {
    static func parse(userAgent: String) -> String {
        let ua = userAgent.lowercased()
        if ua.contains("cursor")     { return "Cursor" }
        if ua.contains("open-webui") { return "Open WebUI" }
        if ua.contains("curl")       { return "curl" }
        if ua.contains("python")     { return "Python" }
        return "Unknown"
    }
}
