import SwiftUI

struct StatsView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("TODAY")
            tokenRow(label: "Input",  tokens: vm.usageStore.todayPromptTokens,
                     cost: vm.cost(prompt: vm.usageStore.todayPromptTokens, eval: 0))
            tokenRow(label: "Output", tokens: vm.usageStore.todayEvalTokens,
                     cost: vm.cost(prompt: 0, eval: vm.usageStore.todayEvalTokens))

            if vm.settingsStore.settings.dailyBudgetTokens > 0 {
                budgetBar
            }
            tokenRow(label: "Total", tokens: vm.usageStore.todayTotalTokens,
                     cost: vm.todayCost, bold: true)
            BurnRateView()

            Divider()
            sectionHeader("ALL TIME")
            tokenRow(label: "Total", tokens: vm.usageStore.allTimeTotalTokens,
                     cost: vm.allTimeCost, bold: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
    }

    private func tokenRow(label: String, tokens: Int, cost: Double?, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(bold ? .body.bold() : .body)
            Spacer()
            if let cost, cost > 0 {
                Text(String(format: "($%.2f)", cost)).font(.caption).foregroundStyle(.secondary)
            }
            Text(tokens.formatted()).font(bold ? .body.bold() : .body)
                .monospacedDigit()
                .foregroundStyle(bold ? .primary : .secondary)
        }
    }

    private var budgetBar: some View {
        let budget = vm.settingsStore.settings.dailyBudgetTokens
        let fraction = min(1.0, Double(vm.usageStore.todayTotalTokens) / Double(budget))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(vm.isBudgetExceeded ? .red : vm.isBudgetWarning ? .yellow : .blue)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 4)
        .padding(.vertical, 2)
    }
}

#Preview {
    StatsView()
        .environment(AppViewModel())
}
