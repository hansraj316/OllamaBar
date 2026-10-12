import Foundation

struct ParsedTokens {
    let model: String
    /// Total input tokens, cached ones included, in every dialect.
    let promptTokens: Int
    let evalTokens: Int
    /// Input tokens served from the prompt cache; a subset of `promptTokens`.
    var cachedPromptTokens: Int? = nil
    /// Ollama's own timers from the native `done:true` chunk, in nanoseconds.
    var loadDurationNs: Int? = nil
    var promptEvalDurationNs: Int? = nil
    var evalDurationNs: Int? = nil
}

/// Watches a streamed Ollama response for the chunks that carry token counts.
///
/// Understands the three response dialects Ollama speaks:
/// - Native NDJSON (`/api/generate`, `/api/chat`): the `done:true` line carries
///   `prompt_eval_count`, `eval_count`, `prompt_eval_cached_count` and nanosecond timings.
/// - OpenAI-compatible (`/v1/chat/completions` …): NDJSON or SSE `data:` lines where the
///   final chunk carries `usage.prompt_tokens` / `usage.completion_tokens`.
/// - Native embeddings (`/api/embed`): a single JSON body with `embeddings`, `prompt_eval_count`
///   and `load_duration`, but no `done` flag and no output count.
/// - Anthropic-compatible (`/v1/messages`): a single JSON body with `usage.input_tokens` /
///   `usage.output_tokens`, or an SSE stream where `message_start` carries the input count
///   and `message_delta` the cumulative output count.
final class NDJSONParser {
    private var model: String?
    private var prompt: Int?
    private var eval: Int?
    private var cached: Int?
    private var loadNs: Int?
    private var promptEvalNs: Int?
    private var evalNs: Int?
    /// Set once a terminal chunk has been seen; later lines are ignored.
    private var complete = false
    private var pending = Data()

    private struct Usage: Decodable {
        struct PromptDetails: Decodable {
            let cachedTokens: Int?
            private enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                cachedTokens = c.lenient(Int.self, .cachedTokens)
            }
        }

        // OpenAI
        let promptTokens: Int?
        let completionTokens: Int?
        let promptTokensDetails: PromptDetails?
        // Anthropic
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case promptTokensDetails = "prompt_tokens_details"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            promptTokens = c.lenient(Int.self, .promptTokens)
            completionTokens = c.lenient(Int.self, .completionTokens)
            promptTokensDetails = c.lenient(PromptDetails.self, .promptTokensDetails)
            inputTokens = c.lenient(Int.self, .inputTokens)
            outputTokens = c.lenient(Int.self, .outputTokens)
            cacheReadInputTokens = c.lenient(Int.self, .cacheReadInputTokens)
            cacheCreationInputTokens = c.lenient(Int.self, .cacheCreationInputTokens)
        }

        var isOpenAI: Bool { promptTokens != nil || completionTokens != nil }
        var isAnthropic: Bool { inputTokens != nil || outputTokens != nil }

        /// Anthropic reports cache reads and writes outside `input_tokens`. Folding them back in
        /// keeps "prompt tokens" meaning total input in every dialect, with cached a subset of it.
        var anthropicTotalInput: Int? {
            guard let inputTokens else { return nil }
            return inputTokens + (cacheReadInputTokens ?? 0) + (cacheCreationInputTokens ?? 0)
        }
    }

    /// The `message` object of an Anthropic `message_start` event. Native `/api/chat` chunks also
    /// carry a `message` (role and content), which simply decodes with both fields absent.
    private struct Message: Decodable {
        let model: String?
        let usage: Usage?
        private enum CodingKeys: String, CodingKey { case model, usage }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            model = c.lenient(String.self, .model)
            usage = c.lenient(Usage.self, .usage)
        }
    }

    private struct Chunk: Decodable {
        let done: Bool?
        let type: String?
        let model: String?
        let promptEvalCount: Int?
        let promptEvalCachedCount: Int?
        let evalCount: Int?
        let loadDuration: Int?
        let promptEvalDuration: Int?
        let evalDuration: Int?
        let usage: Usage?
        let message: Message?
        /// The body carries an `embeddings` array. Only its presence matters, so the
        /// (potentially large) vectors are never decoded.
        let hasEmbeddings: Bool

        private enum CodingKeys: String, CodingKey {
            case done, type, model, usage, message, embeddings
            case promptEvalCount = "prompt_eval_count"
            case promptEvalCachedCount = "prompt_eval_cached_count"
            case evalCount = "eval_count"
            case loadDuration = "load_duration"
            case promptEvalDuration = "prompt_eval_duration"
            case evalDuration = "eval_duration"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            done = c.lenient(Bool.self, .done)
            type = c.lenient(String.self, .type)
            model = c.lenient(String.self, .model)
            promptEvalCount = c.lenient(Int.self, .promptEvalCount)
            promptEvalCachedCount = c.lenient(Int.self, .promptEvalCachedCount)
            evalCount = c.lenient(Int.self, .evalCount)
            loadDuration = c.lenient(Int.self, .loadDuration)
            promptEvalDuration = c.lenient(Int.self, .promptEvalDuration)
            evalDuration = c.lenient(Int.self, .evalDuration)
            usage = c.lenient(Usage.self, .usage)
            message = c.lenient(Message.self, .message)
            hasEmbeddings = c.contains(.embeddings)
        }
    }

    /// Feed raw bytes as they stream in. Lines are split on `\n`, so a line
    /// broken across two network reads is reassembled before parsing.
    func ingest(data: Data) {
        guard !complete else { return }
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
        guard !complete else { return }
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("data:") {
            text = String(text.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
        }
        // SSE `event:` lines and `[DONE]` are not JSON and fall through the decode below.
        guard !text.isEmpty, text != "[DONE]",
              let data = text.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else { return }
        apply(chunk)
    }

    private func apply(_ chunk: Chunk) {
        if model == nil, let name = chunk.model ?? chunk.message?.model { model = name }

        if chunk.done == true {
            if let name = chunk.model { model = name }
            prompt = chunk.promptEvalCount ?? 0
            eval = chunk.evalCount ?? 0
            cached = chunk.promptEvalCachedCount
            loadNs = chunk.loadDuration
            promptEvalNs = chunk.promptEvalDuration
            evalNs = chunk.evalDuration
            complete = true
            return
        }

        // `/api/embed` answers in one body with no `done` flag. Embedding models read input
        // but generate nothing, so output is zero. Without a count there is nothing to record.
        if chunk.hasEmbeddings, let count = chunk.promptEvalCount {
            if let name = chunk.model { model = name }
            prompt = count
            eval = 0
            loadNs = chunk.loadDuration
            complete = true
            return
        }

        switch chunk.type ?? "" {
        case "message_start":
            if let usage = chunk.message?.usage { applyAnthropic(usage) }
            return
        case "message_delta":
            if let usage = chunk.usage { applyAnthropic(usage) }
            return
        case "message_stop":
            complete = true
            return
        default:
            break
        }

        // A `usage` object counts only if it carries fields we recognise; an empty or
        // foreign one must not lock in a zero-token record.
        guard let usage = chunk.usage else { return }
        if usage.isOpenAI {
            if let name = chunk.model { model = name }
            prompt = usage.promptTokens ?? 0
            eval = usage.completionTokens ?? 0
            cached = usage.promptTokensDetails?.cachedTokens
            complete = true
        } else if usage.isAnthropic {
            if let name = chunk.model { model = name }
            applyAnthropic(usage)
            complete = true
        }
    }

    /// Streaming Anthropic splits counts across events, so each one only overwrites what it carries.
    /// `message_delta` output counts are cumulative, so the last one wins.
    private func applyAnthropic(_ usage: Usage) {
        if let total = usage.anthropicTotalInput { prompt = total }
        if let read = usage.cacheReadInputTokens { cached = read }
        if let output = usage.outputTokens { eval = output }
    }

    func finalize() -> ParsedTokens? {
        if !complete, !pending.isEmpty, let tail = String(data: pending, encoding: .utf8) {
            pending.removeAll()
            ingest(line: tail)
        }
        guard prompt != nil || eval != nil else { return nil }
        return ParsedTokens(
            model: model ?? "unknown",
            promptTokens: prompt ?? 0,
            evalTokens: eval ?? 0,
            cachedPromptTokens: cached,
            loadDurationNs: loadNs,
            promptEvalDurationNs: promptEvalNs,
            evalDurationNs: evalNs
        )
    }
}

private extension KeyedDecodingContainer {
    /// Decodes an optional value, treating a missing key, `null`, or a value of an unexpected
    /// type all as absent, so one odd field never discards a chunk's token counts.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}

enum ClientAppParser {
    /// Ordered: earlier entries win, so specific products come before generic runtimes.
    private static let signatures: [(needle: String, name: String)] = [
        ("cursor", "Cursor"),
        ("claude-cli", "Claude Code"), ("claude-code", "Claude Code"),
        ("anthropic", "Anthropic SDK"),
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
