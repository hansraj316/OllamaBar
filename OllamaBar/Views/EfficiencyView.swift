import SwiftUI

struct EfficiencyView: View {
    @Environment(AppViewModel.self) var vm

    var label: String {
        guard let score = vm.usageStore.efficiencyScore else { return "" }
        switch score {
        case let s where s > 2.0:  return "Verbose"
        case let s where s >= 1.0: return "Balanced"
        case let s where s >= 0.5: return "Tight ⚡"
        default:                   return "Ultra-efficient 🎯"
        }
    }

    var body: some View {
        if vm.usageStore.efficiencyScore != nil {
            HStack {
                Text("Efficiency:").font(.caption).foregroundStyle(.secondary)
                Text(label).font(.caption.bold())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }
}

#Preview {
    EfficiencyView()
        .environment(AppViewModel())
}
