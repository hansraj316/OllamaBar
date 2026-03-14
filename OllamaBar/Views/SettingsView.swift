import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETTINGS").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

            settingRow("Proxy Port") {
                TextField("11435", value: Binding(
                    get: { vm.settingsStore.settings.proxyPort },
                    set: { vm.settingsStore.settings.proxyPort = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 70)
            }

            settingRow("Target") {
                TextField("localhost:11434", text: Binding(
                    get: { vm.settingsStore.settings.targetURL },
                    set: { vm.settingsStore.settings.targetURL = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            settingRow("Budget (tokens/day)") {
                HStack {
                    TextField("0 = off", value: Binding(
                        get: { vm.settingsStore.settings.dailyBudgetTokens },
                        set: { vm.settingsStore.settings.dailyBudgetTokens = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 80)

                    Picker("", selection: Binding(
                        get: { vm.settingsStore.settings.budgetMode },
                        set: { vm.settingsStore.settings.budgetMode = $0 }
                    )) {
                        Text("Soft").tag(BudgetMode.soft)
                        Text("Hard").tag(BudgetMode.hard)
                    }
                    .pickerStyle(.segmented).frame(width: 90).controlSize(.mini)
                }
            }

            settingRow("Cost/1k input ($)") {
                TextField("0.00", value: Binding(
                    get: { vm.settingsStore.settings.costPer1kInputTokens },
                    set: { vm.settingsStore.settings.costPer1kInputTokens = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 70)
            }

            settingRow("Cost/1k output ($)") {
                TextField("0.00", value: Binding(
                    get: { vm.settingsStore.settings.costPer1kOutputTokens },
                    set: { vm.settingsStore.settings.costPer1kOutputTokens = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 70)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.callout).frame(width: 140, alignment: .leading)
            content()
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppViewModel())
}
