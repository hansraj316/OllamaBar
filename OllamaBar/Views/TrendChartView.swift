import Charts
import SwiftUI

/// Stacked input/output tokens per day for the last two weeks.
struct TrendChartView: View {
    @Environment(AppViewModel.self) var vm

    private let days = 14

    var body: some View {
        let data = vm.usageStore.dailyTotals(days: days)
        let total = data.reduce(0) { $0 + $1.total }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Last 14 days")
                Spacer()
                Text("\(Format.compact(total)) tokens")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if total == 0 {
                EmptyHint(text: "Daily totals will chart here once requests flow through the proxy.")
            } else {
                Chart(data) { day in
                    BarMark(x: .value("Day", day.date, unit: .day),
                            y: .value("Input", day.prompt))
                        .foregroundStyle(Theme.input)
                    BarMark(x: .value("Day", day.date, unit: .day),
                            y: .value("Output", day.eval))
                        .foregroundStyle(Theme.output)
                        .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.day().month(.abbreviated))
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let n = value.as(Int.self) {
                                Text(Format.compact(n)).font(.system(size: 9))
                            }
                        }
                    }
                }
                .frame(height: 96)
            }
        }
        .card()
    }
}

#Preview {
    TrendChartView()
        .environment(AppViewModel())
        .frame(width: 380)
}
