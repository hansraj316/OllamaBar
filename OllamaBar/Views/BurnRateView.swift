import SwiftUI

struct BurnRateView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        if let rate = vm.usageStore.burnRate, let projected = vm.usageStore.projectedDayTotal {
            Text("Burn: ~\(Int(rate / 1000))k/hr  •  Projected: ~\(projected / 1000)k today")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No activity yet today")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    BurnRateView()
        .environment(AppViewModel())
}
