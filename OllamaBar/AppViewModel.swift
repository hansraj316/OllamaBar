import AppKit
import Foundation
import Observation
import ServiceManagement
import UniformTypeIdentifiers

@Observable
@MainActor
final class AppViewModel {
    let usageStore: UsageStore
    let settingsStore: SettingsStore
    let monitor: OllamaMonitor
    var proxyServer: ProxyServer

    var isProxyRunning = false
    var proxyStatusMessage: String?
    var isBudgetWarning = false
    var isBudgetExceeded = false
    var blockedRequestCount = 0

    var selectedTab: Tab = .overview
    var breakdownMode: BreakdownMode = .byModel
    var breakdownRange: UsageRange = .today

    var launchAtLogin = false
    var launchAtLoginError: String?
    var exportMessage: String?
    var isConfirmingReset = false

    enum BreakdownMode { case byModel, byApp }

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case models = "Models"
        case activity = "Activity"
        case settings = "Settings"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .overview: return "chart.bar.xaxis"
            case .models:   return "cpu"
            case .activity: return "list.bullet.rectangle"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    static let repositoryURL = URL(string: "https://github.com/hansraj316/OllamaBar")!
    static let defaultTargetURL = URL(string: "http://localhost:11434")!

    private let notifier = BudgetNotifier()

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var proxyURLString: String { "http://127.0.0.1:\(settingsStore.settings.proxyPort)" }

    init() {
        let persistence = PersistenceManager()
        let usage = UsageStore(persistence: persistence)
        let settings = SettingsStore(persistence: persistence)

        self.usageStore = usage
        self.settingsStore = settings

        let target = URL(string: settings.settings.targetURL) ?? Self.defaultTargetURL
        let proxy = ProxyServer(port: settings.settings.proxyPort, targetURL: target)
        self.proxyServer = proxy
        self.monitor = OllamaMonitor(baseURL: target)

        usage.load()
        refreshLaunchAtLogin()
        setupAndStartProxy(proxy)
        monitor.startPolling()
    }

    private func setupAndStartProxy(_ proxy: ProxyServer) {
        proxy.onRecord = { [weak self] record in
            guard let self else { return }
            Task { @MainActor in
                self.usageStore.append(record)
                self.refreshBudgetSnapshot()
            }
        }

        proxy.onBlocked = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.blockedRequestCount += 1
            }
        }

        proxy.onError = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.isProxyRunning = false
                switch error {
                case .portConflict:
                    self.proxyStatusMessage = "Port \(self.settingsStore.settings.proxyPort) is already in use."
                case .listenerFailed:
                    self.proxyStatusMessage = "The proxy listener stopped unexpectedly."
                }
            }
        }

        proxy.onReady = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isProxyRunning = true
                self.proxyStatusMessage = nil
            }
        }

        refreshBudgetSnapshot()

        do {
            try proxy.start()
        } catch {
            isProxyRunning = false
            proxyStatusMessage = "Could not open port \(settingsStore.settings.proxyPort): \(error.localizedDescription)"
        }
    }

    func refreshBudgetSnapshot() {
        let s = settingsStore.settings
        let today = usageStore.todayTotalTokens
        proxyServer.budgetSnapshot = BudgetSnapshot(
            dailyBudgetTokens: s.dailyBudgetTokens,
            todayTotalTokens: today,
            budgetMode: s.budgetMode
        )
        let budget = s.dailyBudgetTokens
        isBudgetWarning  = budget > 0 && today >= Int(Double(budget) * 0.8)
        isBudgetExceeded = budget > 0 && today >= budget
        notifier.update(isWarning: isBudgetWarning, isExceeded: isBudgetExceeded,
                        enabled: s.notifyOnBudget, todayTokens: today, budget: budget)
    }

    /// Fraction of today's budget consumed, clamped to 0...1. `nil` when no budget is set.
    var budgetFraction: Double? {
        let budget = settingsStore.settings.dailyBudgetTokens
        guard budget > 0 else { return nil }
        return min(1.0, Double(usageStore.todayTotalTokens) / Double(budget))
    }

    func resetStats() {
        usageStore.reset()
        blockedRequestCount = 0
        refreshBudgetSnapshot()
    }

    /// Tears down the listener and starts a fresh one on the current settings.
    /// Called from Settings after the port or target changes.
    func restartProxy() {
        proxyServer.stop()
        isProxyRunning = false

        let s = settingsStore.settings
        let target = URL(string: s.targetURL) ?? Self.defaultTargetURL
        let newProxy = ProxyServer(port: s.proxyPort, targetURL: target)
        self.proxyServer = newProxy
        monitor.baseURL = target
        setupAndStartProxy(newProxy)
        Task { await monitor.refresh() }
    }

    // MARK: - Notifications

    func setNotifyOnBudget(_ enabled: Bool) {
        settingsStore.settings.notifyOnBudget = enabled
        if enabled { notifier.requestAuthorization() }
    }

    // MARK: - Launch at login

    private var canManageLoginItem: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func refreshLaunchAtLogin() {
        guard canManageLoginItem else { return }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard canManageLoginItem else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    // MARK: - Export

    func exportUsage(as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ollamabar-usage.\(format.fileExtension)"
        panel.allowedContentTypes = [format == .csv ? UTType.commaSeparatedText : UTType.json]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try UsageExporter.data(usageStore.records, format: format).write(to: url, options: .atomic)
            exportMessage = "Saved \(usageStore.records.count.formatted()) requests to \(url.lastPathComponent)"
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func copyProxyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(proxyURLString, forType: .string)
    }

    func openRepository() {
        NSWorkspace.shared.open(Self.repositoryURL)
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

    // MARK: - Efficiency

    var efficiencyLabel: String? {
        guard let score = usageStore.efficiencyScore else { return nil }
        switch score {
        case let s where s > 2.0:  return "Verbose"
        case let s where s >= 1.0: return "Balanced"
        case let s where s >= 0.5: return "Tight"
        default:                   return "Ultra-efficient"
        }
    }
}
