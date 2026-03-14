import Foundation
import Observation

@Observable
@MainActor
final class AppViewModel {
    let usageStore: UsageStore
    let settingsStore: SettingsStore
    var proxyServer: ProxyServer

    var isProxyRunning = false
    var isOllamaOffline = false
    var isBudgetWarning = false
    var isBudgetExceeded = false
    var blockedRequestCount = 0
    var breakdownMode: BreakdownMode = .byModel

    enum BreakdownMode { case byModel, byApp }

    init() {
        let persistence = PersistenceManager()
        let usage = UsageStore(persistence: persistence)
        let settings = SettingsStore(persistence: persistence)
        
        self.usageStore = usage
        self.settingsStore = settings
        
        // Initial proxy setup
        let proxy = ProxyServer(
            port: settings.settings.proxyPort,
            targetURL: URL(string: settings.settings.targetURL)!
        )
        self.proxyServer = proxy

        // Load persisted records
        usage.load()

        setupAndStartProxy(proxy)
    }

    private func setupAndStartProxy(_ proxy: ProxyServer) {
        // Wire proxy callbacks
        proxy.onRecord = { [weak self] record in
            guard let self else { return }
            Task { @MainActor in
                self.usageStore.append(record)
                self.refreshBudgetSnapshot()
            }
        }

        proxy.onError = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                switch error {
                case .portConflict: break   // surfaced via isProxyRunning = false
                case .listenerFailed: self.isProxyRunning = false
                }
            }
        }
        
        proxy.onReady = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isProxyRunning = true
            }
        }

        // Initial budget snapshot
        refreshBudgetSnapshot()

        // Start proxy
        do {
            try proxy.start()
        } catch {
            isProxyRunning = false
        }
    }

    func refreshBudgetSnapshot() {
        let s = settingsStore.settings
        proxyServer.budgetSnapshot = BudgetSnapshot(
            dailyBudgetTokens: s.dailyBudgetTokens,
            todayTotalTokens: usageStore.todayTotalTokens,
            budgetMode: s.budgetMode
        )
        let budget = s.dailyBudgetTokens
        let today = usageStore.todayTotalTokens
        isBudgetWarning  = budget > 0 && today >= Int(Double(budget) * 0.8)
        isBudgetExceeded = budget > 0 && today >= budget
    }

    func resetStats() {
        usageStore.reset()
        refreshBudgetSnapshot()
    }

    func restartProxy() {
        proxyServer.stop()
        isProxyRunning = false
        
        let s = settingsStore.settings
        let newProxy = ProxyServer(
            port: s.proxyPort,
            targetURL: URL(string: s.targetURL)!
        )
        self.proxyServer = newProxy
        setupAndStartProxy(newProxy)
    }

    // MARK: - Cost helpers
    func cost(prompt: Int, eval: Int) -> Double? {
        let s = settingsStore.settings
        guard s.costPer1kInputTokens > 0 || s.costPer1kOutputTokens > 0 else { return nil }
        return (Double(prompt) / 1000.0) * s.costPer1kInputTokens
             + (Double(eval)   / 1000.0) * s.costPer1kOutputTokens
    }

    var todayCost: Double? { cost(prompt: usageStore.todayPromptTokens, eval: usageStore.todayEvalTokens) }
    var allTimeCost: Double? { cost(prompt: usageStore.allTimePromptTokens, eval: usageStore.allTimeEvalTokens) }
}
