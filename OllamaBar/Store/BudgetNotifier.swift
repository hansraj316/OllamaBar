import Foundation
import UserNotifications

/// Posts a system notification the first time today's usage crosses 80% and 100%
/// of the daily budget. Silent until the user opts in from Settings.
@MainActor
final class BudgetNotifier {
    private var primed = false
    private var wasWarning = false
    private var wasExceeded = false

    /// `UNUserNotificationCenter` requires a real app bundle; skip it in tests and previews.
    private var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func update(isWarning: Bool, isExceeded: Bool, enabled: Bool, todayTokens: Int, budget: Int) {
        defer {
            wasWarning = isWarning
            wasExceeded = isExceeded
            primed = true
        }
        // The first observation after launch only records state, so a budget that was
        // already blown yesterday evening does not re-notify on every start.
        guard primed, enabled, isAvailable else { return }

        if isExceeded && !wasExceeded {
            post(title: "Daily token budget reached",
                 body: "\(todayTokens.formatted()) of \(budget.formatted()) tokens used today.")
        } else if isWarning && !wasWarning && !isExceeded {
            post(title: "80% of today's token budget used",
                 body: "\(todayTokens.formatted()) of \(budget.formatted()) tokens so far.")
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
