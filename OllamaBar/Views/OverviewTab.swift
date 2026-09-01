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
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .bold))
                Text("Usage today")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(store.todayTotalTokens.formatted())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let fraction = vm.budgetFraction {
                let budget = vm.settingsStore.settings.dailyBudgetTokens
                UsageRow(
                    title: "Daily budget",
                    trailing: "Resets at \(midnight, format: .dateTime.hour().minute())",
                    fraction: fraction,
                    color: Theme.usageColor(fraction),
                    caption: "\(Format.percent(fraction)) used · \(Format.compact(store.todayTotalTokens)) of \(Format.compact(budget))"
                        + (vm.settingsStore.settings.budgetMode == .hard ? " · blocks when full" : "")
                )
            } else {
                let projected = store.projectedDayTotal ?? 0
                let pace = projected > 0 ? min(1, Double(store.todayTotalTokens) / Double(projected)) : 0
                UsageRow(
                    title: "Pace",
                    trailing: "Resets at \(midnight, format: .dateTime.hour().minute())",
                    fraction: pace,
                    color: Theme.mint,
                    caption: projected > 0
                        ? "On track for ~\(Format.compact(projected)) today · no budget set"
                        : "No budget set · add one in Settings to see headroom"
                )
            }

            let peak = max(1, store.peakHourTokensToday)
            UsageRow(
                title: "Last hour",
                trailing: "Rolling 60 min",
                fraction: min(1, Double(store.lastHourTokens) / Double(peak)),
                color: Theme.input,
                caption: "\(Format.compact(store.lastHourTokens)) tokens"
                    + (store.averageTokensPerSecond.map { " · \(Format.rate($0))" } ?? "")
                    + (store.todayVersusYesterday.map { " · \($0 >= 0 ? "up" : "down") \(Format.percent(abs($0))) vs yesterday" } ?? "")
            )

            VStack(alignment: .leading, spacing: 6) {
                SplitBar(prompt: store.todayPromptTokens, eval: store.todayEvalTokens)
                HStack(spacing: 14) {
                    LegendDot(color: Theme.input, label: "Input", value: store.todayPromptTokens)
                    LegendDot(color: Theme.output, label: "Output", value: store.todayEvalTokens)
                    Spacer()
                    Text("\(store.todayRequestCount) requests")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .card(padding: 16)
    }
}

/// One labelled bar: title and reset note above, thin bar, caption below.
struct UsageRow: View {
    let title: String
    let trailing: LocalizedStringKey
    let fraction: Double
    let color: Color
    let caption: String

    init(title: String, trailing: LocalizedStringKey, fraction: Double, color: Color, caption: String) {
        self.title = title; self.trailing = trailing; self.fraction = fraction
        self.color = color; self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(trailing).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(color)
                        .frame(width: max(fraction > 0 ? 6 : 0, geo.size.width * min(1, fraction)))
                }
            }
            .frame(height: 6)
            .animation(.snappy(duration: 0.35), value: fraction)
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
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
