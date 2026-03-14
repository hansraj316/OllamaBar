import Foundation
final class ProxyServer {
    init(port: Int = 11435, targetURL: URL = URL(string: "http://127.0.0.1:11434")!) {}
}
