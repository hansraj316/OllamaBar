import Foundation
struct ParsedTokens { let model: String; let promptTokens: Int; let evalTokens: Int }
final class NDJSONParser {
    func ingest(line: String) {}
    func finalize() -> ParsedTokens? { nil }
}
enum ClientAppParser {
    static func parse(userAgent: String) -> String { "Unknown" }
}
