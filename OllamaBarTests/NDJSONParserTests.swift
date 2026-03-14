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

    func test_clientAppParser_returnsUnknownForUnrecognized() {
        XCTAssertEqual(ClientAppParser.parse(userAgent: "MyCustomApp/1.0"), "Unknown")
    }
}
