import SwiftUI

struct OverviewTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HeroCard()
                StatTiles()
                TrendChartView()
                BreakdownView()
                HeatmapView()
            }
            .padding(14)
        }
    }
}

private struct HeroCard: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        let store = vm.usageStore
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionLabel("Today")
                Spacer()
                if let delta = store.todayVersusYesterday {
                    HStack(spacing: 3) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(Format.percent(abs(delta))) vs yesterday")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                Text("\(store.todayRequestCount) requests")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.todayTotalTokens.formatted())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("tokens")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                if let cost = vm.todayCost {
                    Text(Format.cost(cost))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            SplitBar(prompt: store.todayPromptTokens, eval: store.todayEvalTokens)

            HStack(spacing: 14) {
                LegendDot(color: Theme.input, label: "Input", value: store.todayPromptTokens)
                LegendDot(color: Theme.output, label: "Output", value: store.todayEvalTokens)
                Spacer()
                Text("All time \(Format.compact(store.allTimeTotalTokens))")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            if let fraction = vm.budgetFraction {
                BudgetRow(fraction: fraction)
            }
        }
        .card()
    }
}

struct SplitBar: View {
    let prompt: Int
    let eval: Int

    var body: some View {
        GeometryReader { geo in
            let total = prompt + eval
            if total == 0 {
                Capsule().fill(Theme.track)
            } else {
                let promptWidth = geo.size.width * CGFloat(prompt) / CGFloat(total)
                HStack(spacing: prompt > 0 && eval > 0 ? 2 : 0) {
                    Capsule().fill(Theme.input).frame(width: promptWidth)
                    Capsule().fill(Theme.output)
                }
            }
        }
        .frame(height: 8)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
            Text(value.formatted()).fontWeight(.medium).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

private struct BudgetRow: View {
    @Environment(AppViewModel.self) var vm
    let fraction: Double

    var body: some View {
        let settings = vm.settingsStore.settings
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Budget")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Chip(text: settings.budgetMode == .hard ? "BLOCKS" : "WARNS", tint: .secondary)
                Spacer()
                Text("\(Format.percent(fraction)) of \(Format.compact(settings.dailyBudgetTokens))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
        .padding(.top, 2)
    }

    private var color: Color {
        if vm.isBudgetExceeded { return Theme.danger }
        if vm.isBudgetWarning { return Theme.warning }
        return Theme.input
    }
}

private struct StatTiles: View {
    @Environment(AppViewModel.self) var vm

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let store = vm.usageStore
        LazyVGrid(columns: columns, spacing: 10) {
            StatTile(
                title: "Burn rate",
                value: store.burnRate.map { Format.compact(Int($0)) + "/hr" } ?? "—",
                detail: store.burnRate == nil ? "Needs two requests today" : "Averaged since midnight",
                symbol: "flame"
            )
            StatTile(
                title: "Projected",
                value: store.projectedDayTotal.map { Format.compact($0) } ?? "—",
                detail: store.projectedDayTotal == nil ? "No pace yet" : "By end of day at this pace",
                symbol: "chart.line.uptrend.xyaxis"
            )
            StatTile(
                title: "Efficiency",
                value: vm.efficiencyLabel ?? "—",
                detail: store.efficiencyScore.map { String(format: "%.1f× output per input token", $0) } ?? "No prompts yet",
                symbol: "scope"
            )
            StatTile(
                title: "Speed",
                value: store.averageTokensPerSecond.map { Format.rate($0) } ?? "—",
                detail: store.averageLatencyMs.map { "Avg \(Format.duration(ms: $0)) per request" } ?? "Measured per response",
                symbol: "gauge.with.dots.needle.67percent"
            )
        }
    }
}

#Preview {
    OverviewTab()
        .environment(AppViewModel())
        .frame(width: 380)
}
