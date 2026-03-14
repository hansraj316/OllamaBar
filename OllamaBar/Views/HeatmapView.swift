import SwiftUI

struct HeatmapView: View {
    @Environment(AppViewModel.self) var vm

    private let columns = 13
    private let rows = 7
    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("USAGE HISTORY (91 days)")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

            Canvas { ctx, size in
                let data = vm.usageStore.heatmapData
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
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(cellColor(level: level)))
                    }
                }
            }
            .frame(width: CGFloat(columns) * (cellSize + gap),
                   height: CGFloat(rows) * (cellSize + gap))

            EfficiencyView()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
        case 0: return Color.secondary.opacity(0.1)
        case 1: return Color.blue.opacity(0.25)
        case 2: return Color.blue.opacity(0.5)
        case 3: return Color.blue.opacity(0.75)
        default: return Color.blue
        }
    }
}

#Preview {
    HeatmapView()
        .environment(AppViewModel())
}
