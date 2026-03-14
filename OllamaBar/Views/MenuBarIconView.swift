import SwiftUI

struct MenuBarIconView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName).foregroundStyle(iconColor)
            if vm.usageStore.todayTotalTokens > 0 {
                Text(compactTokenString(vm.usageStore.todayTotalTokens))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }

    private var iconName: String {
        vm.isProxyRunning ? "server.rack" : "server.rack.slash"
    }

    private var iconColor: Color {
        if !vm.isProxyRunning { return .secondary }
        if vm.isBudgetExceeded { return .red }
        if vm.isBudgetWarning  { return .yellow }
        return .primary
    }

    private func compactTokenString(_ n: Int) -> String {
        switch n {
        case 0..<1000:    return "\(n)"
        case 0..<1000000: return "\(n / 1000)k"
        default:          return "\(n / 1000000)M"
        }
    }
}

#Preview {
    MenuBarIconView()
        .environment(AppViewModel())
}
