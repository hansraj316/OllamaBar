import Foundation

struct ParsedTokens {
    let model: String
    let promptTokens: Int
    let evalTokens: Int
}

/// Watches a streamed Ollama response for the terminal chunk that carries token counts.
///
/// Understands both response dialects Ollama speaks:
/// - Native NDJSON (`/api/generate`, `/api/chat`): the `done:true` line carries
///   `prompt_eval_count` and `eval_count`.
/// - OpenAI-compatible (`/v1/...`): NDJSON or SSE `data:` lines where the final
///   chunk carries a `usage` object with `prompt_tokens` and `completion_tokens`.
final class NDJSONParser {
    private var result: ParsedTokens?
    private var pending = Data()

    private struct Chunk: Decodable {
        struct Usage: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?
            private enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
            }
        }
        let done: Bool?
        let model: String?
        let promptEvalCount: Int?
        let evalCount: Int?
        let usage: Usage?
        private enum CodingKeys: String, CodingKey {
            case done, model, usage
            case promptEvalCount = "prompt_eval_count"
            case evalCount = "eval_count"
        }
    }

    /// Feed raw bytes as they stream in. Lines are split on `\n`, so a line
    /// broken across two network reads is reassembled before parsing.
    func ingest(data: Data) {
        guard result == nil else { return }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending.subdata(in: pending.startIndex..<newline)
            pending.removeSubrange(pending.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                ingest(line: line)
            }
        }
    }

    func ingest(line: String) {
        guard result == nil else { return }
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("data:") {
            text = String(text.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty, text != "[DONE]",
              let data = text.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else { return }

        if chunk.done == true {
            result = ParsedTokens(
                model: chunk.model ?? "unknown",
                promptTokens: chunk.promptEvalCount ?? 0,
                evalTokens: chunk.evalCount ?? 0
            )
        } else if let usage = chunk.usage {
            result = ParsedTokens(
                model: chunk.model ?? "unknown",
                promptTokens: usage.promptTokens ?? 0,
                evalTokens: usage.completionTokens ?? 0
            )
        }
    }

    func finalize() -> ParsedTokens? {
        if result == nil, !pending.isEmpty, let tail = String(data: pending, encoding: .utf8) {
            pending.removeAll()
            ingest(line: tail)
        }
        return result
    }
}

enum ClientAppParser {
    /// Ordered: earlier entries win, so specific products come before generic runtimes.
    private static let signatures: [(needle: String, name: String)] = [
        ("cursor", "Cursor"),
        ("open-webui", "Open WebUI"), ("openwebui", "Open WebUI"),
        ("cline", "Cline"),
        ("roo-code", "Roo Code"),
        ("continue", "Continue"),
        ("zed", "Zed"),
        ("aider", "Aider"),
        ("raycast", "Raycast"),
        ("enchanted", "Enchanted"),
        ("lm-studio", "LM Studio"),
        ("ollama", "Ollama CLI"),
        ("langchain", "LangChain"),
        ("llamaindex", "LlamaIndex"),
        ("openai", "OpenAI SDK"),
        ("curl", "curl"),
        ("httpie", "HTTPie"),
        ("postman", "Postman"),
        ("insomnia", "Insomnia"),
        ("python", "Python"),
        ("node", "Node.js"), ("undici", "Node.js"), ("axios", "Node.js"),
        ("bun", "Bun"),
        ("deno", "Deno"),
        ("go-http-client", "Go"),
        ("java", "Java"),
        ("dart", "Dart"),
        ("swift", "Swift"),
        ("rust", "Rust"), ("reqwest", "Rust")
    ]

    static func parse(userAgent: String) -> String {
        let ua = userAgent.lowercased()
        for signature in signatures where ua.contains(signature.needle) {
            return signature.name
        }
        return "Unknown"
    }
}
