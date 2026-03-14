import Foundation
import Network

final class ProxyServer {
    var onRecord: ((UsageRecord) -> Void)?
    var onError: ((ProxyError) -> Void)?
    var onReady: (() -> Void)?
    var budgetSnapshot = BudgetSnapshot(dailyBudgetTokens: 0, todayTotalTokens: 0, budgetMode: .soft)

    private let port: NWEndpoint.Port
    private let targetURL: URL
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: ProxyConnection] = [:]
    private let connectionsLock = NSLock()

    enum ProxyError: Error { case portConflict, listenerFailed }

    init(port: Int = 11435, targetURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.port = NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
        self.targetURL = targetURL
    }

    func start() throws {
        let l = try NWListener(using: .tcp, on: port)
        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onReady?()
            case .failed:
                self.onError?(.listenerFailed)
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            let connection = ProxyConnection(
                connection: conn,
                targetURL: self.targetURL,
                budgetSnapshot: self.budgetSnapshot,
                onRecord: self.onRecord
            )
            let key = ObjectIdentifier(connection)
            self.connectionsLock.withLock { self.activeConnections[key] = connection }
            connection.onDone = { [weak self, weak connection] in
                guard let self, let connection else { return }
                let k = ObjectIdentifier(connection)
                self.connectionsLock.withLock { self.activeConnections.removeValue(forKey: k) }
            }
            connection.start()
        }
        l.start(queue: .global(qos: .userInitiated))
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
