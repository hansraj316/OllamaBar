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

    func test_clientAppParser_returnsUnknownForUnrecognized() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "MyCustomApp/1.0"), "Unknown")
    }
}
