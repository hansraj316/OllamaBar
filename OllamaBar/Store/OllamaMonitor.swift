import Foundation
import Observation

/// Polls Ollama's management endpoints so the popover can show whether the
/// server is reachable, which models are loaded in memory, and what is installed.
@Observable
@MainActor
final class OllamaMonitor {
    private(set) var isOnline = false
    private(set) var version: String?
    private(set) var loadedModels: [LoadedModel] = []
    private(set) var installedModels: [InstalledModel] = []
    private(set) var lastChecked: Date?
    private(set) var isRefreshing = false
    private(set) var unloadingModel: String?

    var baseURL: URL

    private var pollTask: Task<Void, Never>?
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        self.session = URLSession(configuration: config)
    }

    func startPolling(every interval: TimeInterval = 20) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let base = baseURL
        async let versionResult = Self.fetch(OllamaVersion.self, from: base.appendingPathComponent("api/version"), session: session)
        async let loadedResult = Self.fetch(OllamaModelList<LoadedModel>.self, from: base.appendingPathComponent("api/ps"), session: session)
        async let installedResult = Self.fetch(OllamaModelList<InstalledModel>.self, from: base.appendingPathComponent("api/tags"), session: session)
        let (versionInfo, loaded, installed) = await (versionResult, loadedResult, installedResult)

        isOnline = versionInfo != nil
        version = versionInfo?.version
        loadedModels = loaded?.models ?? []
        installedModels = (installed?.models ?? []).sorted { $0.name < $1.name }
        lastChecked = Date()
    }

    /// Asks Ollama to evict a model from memory immediately (`keep_alive: 0`).
    /// Goes straight to Ollama, not through the proxy, so it is never counted as usage.
    func unload(_ model: LoadedModel) async {
        unloadingModel = model.name
        defer { unloadingModel = nil }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model.name, "keep_alive": 0])
        _ = try? await session.data(for: request)
        await refresh()
    }

    nonisolated private static func fetch<T: Decodable>(_ type: T.Type, from url: URL, session: URLSession) async -> T? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
