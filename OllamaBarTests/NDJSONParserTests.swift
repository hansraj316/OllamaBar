import XCTest
@testable import OllamaBar

final class NDJSONParserTests: XCTestCase {

    func test_extractsTokensFromDoneChunk_generate() {
        let parser = NDJSONParser()
        let lines = [
            #"{"model":"llama3.2","response":"Hello","done":false}"#,
            #"{"model":"llama3.2","response":"","done":true,"prompt_eval_count":15,"eval_count":42}"#
        ]
        lines.forEach { parser.ingest(line: $0) }
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "llama3.2")
        XCTAssertEqual(result?.promptTokens, 15)
        XCTAssertEqual(result?.evalTokens, 42)
    }

    func test_extractsTokensFromDoneChunk_chat() {
        let parser = NDJSONParser()
        let lines = [
            #"{"model":"mistral","message":{"role":"assistant","content":"Hi"},"done":false}"#,
            #"{"model":"mistral","done":true,"prompt_eval_count":8,"eval_count":20}"#
        ]
        lines.forEach { parser.ingest(line: $0) }
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "mistral")
        XCTAssertEqual(result?.promptTokens, 8)
        XCTAssertEqual(result?.evalTokens, 20)
    }

    func test_returnsZeroTokens_whenDoneChunkHasNoTokenFields() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"done":true,"model":"llama3.2"}"#)
        let result = parser.finalize()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.promptTokens, 0)
        XCTAssertEqual(result?.evalTokens, 0)
    }

    func test_returnsNil_whenNoDoneChunkReceived() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"llama3.2","response":"partial","done":false}"#)
        XCTAssertNil(parser.finalize())
    }

    func test_skipsMalformedLines() {
        let parser = NDJSONParser()
        parser.ingest(line: "not json at all")
        parser.ingest(line: #"{"done":true,"model":"llama3.2","prompt_eval_count":5,"eval_count":10}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.promptTokens, 5)
    }

    // MARK: - Streaming byte ingestion

    func test_ingestData_reassemblesLinesSplitAcrossChunks() {
        let parser = NDJSONParser()
        let full = "{\"model\":\"llama3.2\",\"done\":false}\n{\"model\":\"llama3.2\",\"done\":true,\"prompt_eval_count\":7,\"eval_count\":9}\n"
        let bytes = Array(full.utf8)
        let cut = 50
        parser.ingest(data: Data(bytes[..<cut]))
        parser.ingest(data: Data(bytes[cut...]))
        let result = parser.finalize()
        XCTAssertEqual(result?.promptTokens, 7)
        XCTAssertEqual(result?.evalTokens, 9)
    }

    func test_ingestData_flushesTrailingLineWithoutNewlineOnFinalize() {
        let parser = NDJSONParser()
        parser.ingest(data: Data(#"{"model":"phi3","done":true,"prompt_eval_count":3,"eval_count":4}"#.utf8))
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "phi3")
        XCTAssertEqual(result?.evalTokens, 4)
    }

    func test_ingestData_survivesMultibyteCharacterSplitAcrossChunks() {
        let parser = NDJSONParser()
        let line = "{\"model\":\"llama3.2\",\"response\":\"héllo\",\"done\":true,\"prompt_eval_count\":1,\"eval_count\":2}\n"
        let bytes = Array(line.utf8)
        // Split inside the two-byte "é" (bytes 0xC3 0xA9).
        let split = bytes.firstIndex(of: 0xC3)! + 1
        parser.ingest(data: Data(bytes[..<split]))
        parser.ingest(data: Data(bytes[split...]))
        XCTAssertEqual(parser.finalize()?.evalTokens, 2)
    }

    // MARK: - OpenAI-compatible responses

    func test_parsesOpenAIStreamingUsageFromSSE() {
        let parser = NDJSONParser()
        let lines = [
            #"data: {"id":"chatcmpl-1","model":"llama3.2","choices":[{"delta":{"content":"Hi"}}]}"#,
            "",
            #"data: {"id":"chatcmpl-1","model":"llama3.2","choices":[],"usage":{"prompt_tokens":12,"completion_tokens":30}}"#,
            "",
            "data: [DONE]"
        ]
        lines.forEach { parser.ingest(line: $0) }
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "llama3.2")
        XCTAssertEqual(result?.promptTokens, 12)
        XCTAssertEqual(result?.evalTokens, 30)
    }

    func test_parsesOpenAINonStreamingUsage() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"id":"chatcmpl-2","model":"gemma","choices":[{"message":{"content":"x"}}],"usage":{"prompt_tokens":5,"completion_tokens":6,"total_tokens":11}}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "gemma")
        XCTAssertEqual(result?.promptTokens, 5)
        XCTAssertEqual(result?.evalTokens, 6)
    }

    func test_ignoresChunksWithNullUsage() {
        let parser = NDJSONParser()
        parser.ingest(line: #"data: {"model":"llama3.2","choices":[{"delta":{"content":"a"}}],"usage":null}"#)
        XCTAssertNil(parser.finalize())
    }

    // MARK: - Native timings and prompt cache

    func test_native_capturesOllamaTimingsAndCachedCount() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"llama3.2","done":true,"done_reason":"stop","prompt_eval_count":120,"prompt_eval_cached_count":96,"eval_count":40,"total_duration":2600000000,"load_duration":2100000000,"prompt_eval_duration":130000000,"eval_duration":320000000}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.promptTokens, 120)
        XCTAssertEqual(result?.evalTokens, 40)
        XCTAssertEqual(result?.cachedPromptTokens, 96)
        XCTAssertEqual(result?.loadDurationNs, 2_100_000_000)
        XCTAssertEqual(result?.promptEvalDurationNs, 130_000_000)
        XCTAssertEqual(result?.evalDurationNs, 320_000_000)
    }

    func test_native_olderOllamaWithoutTimingsLeavesThemNil() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"llama3.2","done":true,"prompt_eval_count":5,"eval_count":6}"#)
        let result = parser.finalize()
        XCTAssertNil(result?.cachedPromptTokens)
        XCTAssertNil(result?.evalDurationNs)
        XCTAssertNil(result?.loadDurationNs)
    }

    func test_native_chatDoneChunkWithMessageObjectStillParses() {
        // /api/chat chunks carry a `message` object; it must not get in the way of the counts.
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"qwen3","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"f","arguments":{}}}]},"done":true,"prompt_eval_count":30,"eval_count":12}"#)
        XCTAssertEqual(parser.finalize()?.evalTokens, 12)
    }

    func test_unexpectedFieldTypesDoNotDiscardTheCounts() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"m","message":"not an object","usage":[1,2],"load_duration":"soon","done":true,"prompt_eval_count":3,"eval_count":4}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.promptTokens, 3)
        XCTAssertEqual(result?.evalTokens, 4)
        XCTAssertNil(result?.loadDurationNs)
    }

    func test_openAI_readsCachedTokensFromPromptDetails() {
        let parser = NDJSONParser()
        parser.ingest(line: #"data: {"model":"llama3.2","choices":[],"usage":{"prompt_tokens":200,"completion_tokens":20,"prompt_tokens_details":{"cached_tokens":150}}}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.promptTokens, 200)
        XCTAssertEqual(result?.cachedPromptTokens, 150)
    }

    // MARK: - Anthropic-compatible (/v1/messages)

    func test_anthropic_nonStreamingResponse() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"id":"msg_1","type":"message","role":"assistant","model":"qwen3-coder","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":25,"output_tokens":15}}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "qwen3-coder")
        XCTAssertEqual(result?.promptTokens, 25)
        XCTAssertEqual(result?.evalTokens, 15)
        XCTAssertNil(result?.cachedPromptTokens)
    }

    func test_anthropic_streamingTakesInputFromStartAndOutputFromLastDelta() {
        let parser = NDJSONParser()
        let stream = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"qwen3-coder","content":[],"usage":{"input_tokens":40,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":27}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        parser.ingest(data: Data(stream.utf8))
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "qwen3-coder")
        XCTAssertEqual(result?.promptTokens, 40)
        XCTAssertEqual(result?.evalTokens, 27, "message_delta's cumulative count replaces the placeholder")
    }

    func test_anthropic_streamingSurvivesChunkBoundaries() {
        let parser = NDJSONParser()
        let stream = "data: {\"type\":\"message_start\",\"message\":{\"model\":\"m\",\"usage\":{\"input_tokens\":9,\"output_tokens\":1}}}\n"
            + "data: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":33}}\n"
        let bytes = Array(stream.utf8)
        for start in stride(from: 0, to: bytes.count, by: 7) {
            parser.ingest(data: Data(bytes[start..<min(start + 7, bytes.count)]))
        }
        let result = parser.finalize()
        XCTAssertEqual(result?.promptTokens, 9)
        XCTAssertEqual(result?.evalTokens, 33)
    }

    func test_anthropic_foldsCacheReadsAndWritesIntoPromptTokens() {
        // Anthropic reports cache tokens outside input_tokens; prompt tokens stay "total input".
        let parser = NDJSONParser()
        parser.ingest(line: #"{"type":"message","model":"m","usage":{"input_tokens":10,"cache_read_input_tokens":70,"cache_creation_input_tokens":20,"output_tokens":5}}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.promptTokens, 100)
        XCTAssertEqual(result?.cachedPromptTokens, 70)
    }

    func test_usageWithoutRecognisedFieldsDoesNotRecordZeroTokens() {
        // Regression: any `usage` object used to lock in a 0/0 record, so Anthropic-style
        // responses were logged as zero-token requests from an "unknown" model.
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"m","usage":{}}"#)
        parser.ingest(line: #"{"model":"m","usage":{"something_else":5}}"#)
        XCTAssertNil(parser.finalize())
    }

    func test_responsesWithoutAnyCountsProduceNoRecord() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"models":[{"name":"llama3.2:latest"}]}"#)
        parser.ingest(line: #"{"status":"pulling manifest"}"#)
        XCTAssertNil(parser.finalize())
    }

    // MARK: - Embeddings

    func test_embed_countsInputTokensWithZeroOutput() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"embeddinggemma","embeddings":[[0.010071029,-0.0017594862,0.05007221]],"total_duration":14143917,"load_duration":1019500,"prompt_eval_count":8}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "embeddinggemma")
        XCTAssertEqual(result?.promptTokens, 8)
        XCTAssertEqual(result?.evalTokens, 0)
        XCTAssertEqual(result?.loadDurationNs, 1_019_500)
        XCTAssertNil(result?.evalDurationNs)
    }

    func test_embed_batchOfInputsIsOneRecord() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"nomic-embed-text","embeddings":[[0.1,0.2],[0.3,0.4],[0.5,0.6]],"prompt_eval_count":27}"#)
        XCTAssertEqual(parser.finalize()?.promptTokens, 27)
    }

    func test_embed_withoutCountRecordsNothing() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"model":"m","embeddings":[[0.1,0.2]]}"#)
        XCTAssertNil(parser.finalize())
    }

    func test_legacyEmbeddingsEndpointHasNoCountsToRecord() {
        // The deprecated /api/embeddings returns a bare vector and no usage at all.
        let parser = NDJSONParser()
        parser.ingest(line: #"{"embedding":[0.5670403838157654,0.009260174818336964]}"#)
        XCTAssertNil(parser.finalize())
    }

    func test_openAIEmbeddings_countInputWithZeroOutput() {
        let parser = NDJSONParser()
        parser.ingest(line: #"{"object":"list","data":[{"object":"embedding","embedding":[0.1,0.2],"index":0}],"model":"all-minilm","usage":{"prompt_tokens":8,"total_tokens":8}}"#)
        let result = parser.finalize()
        XCTAssertEqual(result?.model, "all-minilm")
        XCTAssertEqual(result?.promptTokens, 8)
        XCTAssertEqual(result?.evalTokens, 0)
    }

    // MARK: - Client detection

    func test_clientAppParser_recognizesCursor() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "cursor/1.0"), "Cursor")
    }

    func test_clientAppParser_recognizesCurl() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "curl/7.88.1"), "curl")
    }

    func test_clientAppParser_recognizesOpenWebUI() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "open-webui/1.0"), "Open WebUI")
    }

    func test_clientAppParser_recognizesPython() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "python-requests/2.28"), "Python")
    }

    func test_clientAppParser_recognizesNewerClients() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "Cline/3.2.0"), "Cline")
        XCTAssertEqual(ClientAppParser.parse(userAgent: "Continue/0.9"), "Continue")
        XCTAssertEqual(ClientAppParser.parse(userAgent: "Zed/0.150"), "Zed")
        XCTAssertEqual(ClientAppParser.parse(userAgent: "ollama/0.5.1 (arm64 darwin) Go/go1.22"), "Ollama CLI")
        XCTAssertEqual(ClientAppParser.parse(userAgent: "OpenAI/Python 1.40.0"), "OpenAI SDK")
        XCTAssertEqual(ClientAppParser.parse(userAgent: "node-fetch/1.0"), "Node.js")
        XCTAssertEqual(ClientAppParser.parse(userAgent: "Go-http-client/1.1"), "Go")
    }

    func test_clientAppParser_recognizesClaudeCodeAndAnthropicSDK() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "claude-cli/2.0.14 (external, cli)"), "Claude Code")
        XCTAssertEqual(ClientAppParser.parse(userAgent: "Anthropic/Python 0.69.0"), "Anthropic SDK",
                       "the SDK must win over the generic Python match")
        XCTAssertEqual(ClientAppParser.parse(userAgent: "Anthropic/JS 0.65.0"), "Anthropic SDK")
    }

    func test_clientAppParser_returnsUnknownForUnrecognized() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "MyCustomApp/1.0"), "Unknown")
    }
}
