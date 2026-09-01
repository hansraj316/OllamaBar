import SwiftUI

struct MenuBarIconView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
            if vm.settingsStore.settings.showTokensInMenuBar, vm.usageStore.todayTotalTokens > 0 {
                Text(Format.compact(vm.usageStore.todayTotalTokens))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }

    private var iconName: String {
        if !vm.isProxyRunning { return "exclamationmark.triangle" }
        if vm.isBudgetExceeded { return "hand.raised" }
        return "waveform.path.ecg"
    }

    private var iconColor: Color {
        if !vm.isProxyRunning { return .secondary }
        if vm.isBudgetExceeded { return Theme.danger }
        if vm.isBudgetWarning  { return Theme.warning }
        return .primary
    }
}

#Preview {
    MenuBarIconView()
        .environment(AppViewModel())
}
