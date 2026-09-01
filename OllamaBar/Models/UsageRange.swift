import Foundation

enum UsageRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7D"
    case month = "30D"
    case all = "All"

    var id: String { rawValue }

    /// Inclusive lower bound for the range, or `nil` for all time.
    var startDate: Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch self {
        case .today: return today
        case .week:  return cal.date(byAdding: .day, value: -6, to: today)
        case .month: return cal.date(byAdding: .day, value: -29, to: today)
        case .all:   return nil
        }
    }
}
