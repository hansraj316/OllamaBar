import SwiftUI

struct HeatmapView: View {
    @Environment(AppViewModel.self) var vm

    private let columns = 13
    private let rows = 7
    private let cellSize: CGFloat = 13
    private let gap: CGFloat = 3

    var body: some View {
        let store = vm.usageStore
        let data = store.heatmapData
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Last 91 days")
                Spacer()
                legend
            }

            HStack(alignment: .top, spacing: 16) {
                Canvas { ctx, _ in
                    let maxVal = data.values.max() ?? 1
                    for col in 0..<columns {
                        for row in 0..<rows {
                            let dayIndex = col * rows + row
                            let date = dayDate(daysAgo: 90 - dayIndex)
                            let tokens = data[date] ?? 0
                            let level = colorLevel(tokens: tokens, maxTokens: maxVal)
                            let x = CGFloat(col) * (cellSize + gap)
                            let y = CGFloat(row) * (cellSize + gap)
                            let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                                     with: .color(cellColor(level: level)))
                        }
                    }
                }
                .frame(width: CGFloat(columns) * cellSize + CGFloat(columns - 1) * gap,
                       height: CGFloat(rows) * cellSize + CGFloat(rows - 1) * gap)

                VStack(alignment: .leading, spacing: 9) {
                    MiniStat(label: "Active days", value: "\(store.activeDayCount)")
                    MiniStat(label: "Streak", value: "\(store.usageStreakDays)d")
                    MiniStat(label: "Peak day", value: Format.compact(store.peakDayTokens))
                }
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("Less").font(.system(size: 9)).foregroundStyle(.tertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(cellColor(level: level))
                    .frame(width: 8, height: 8)
            }
            Text("More").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    private func dayDate(daysAgo: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
    }

    private func colorLevel(tokens: Int, maxTokens: Int) -> Int {
        guard tokens > 0 else { return 0 }
        let max = max(1, maxTokens)
        if tokens >= (max * 3) / 4 { return 4 }
        if tokens >= max / 2       { return 3 }
        if tokens >= max / 4       { return 2 }
        return 1
    }

    private func cellColor(level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.07)
        case 1: return Theme.output.opacity(0.3)
        case 2: return Theme.output.opacity(0.55)
        case 3: return Theme.output.opacity(0.8)
        default: return Theme.output
        }
    }
}

private struct MiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    HeatmapView()
        .environment(AppViewModel())
        .frame(width: 380)
}
