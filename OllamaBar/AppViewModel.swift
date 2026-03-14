import Foundation
import Observation

@Observable
@MainActor
final class AppViewModel {
    var isProxyRunning = false
    var isOllamaOffline = false
    var isBudgetWarning = false
    var isBudgetExceeded = false
    var blockedRequestCount = 0
    var breakdownMode: BreakdownMode = .byModel
    let usageStore = UsageStore()
    let settingsStore = SettingsStore()

    enum BreakdownMode { case byModel, byApp }
}
