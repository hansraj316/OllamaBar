import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        @Bindable var store = vm.settingsStore
        ScrollView {
            VStack(spacing: 10) {
                SettingsSection("Proxy") {
                    LabeledRow("Port") {
                        TextField("11435", value: $store.settings.proxyPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 76)
                    }
                    LabeledRow("Ollama URL") {
                        TextField("http://localhost:11434", text: $store.settings.targetURL)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }
                    HStack {
                        Text(proxyStatus)
                            .font(.system(size: 10.5))
                            .foregroundStyle(vm.isProxyRunning ? Color.secondary : Theme.danger)
                            .lineLimit(2)
                        Spacer()
                        Button("Apply & restart") { vm.restartProxy() }
                            .controlSize(.small)
                    }
                }

                SettingsSection("Budget") {
                    LabeledRow("Daily cap") {
                        HStack(spacing: 6) {
                            TextField("0 = off", value: $store.settings.dailyBudgetTokens, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(width: 96)
                            Text("tokens").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    LabeledRow("When exceeded") {
                        Picker("", selection: $store.settings.budgetMode) {
                            Text("Warn").tag(BudgetMode.soft)
                            Text("Block").tag(BudgetMode.hard)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    Toggle("Notify me at 80% and 100%", isOn: Binding(
                        get: { store.settings.notifyOnBudget },
                        set: { vm.setNotifyOnBudget($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11.5))
                    Text("Block answers generation requests with HTTP 429 once the cap is hit. Listing and pulling models keep working.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                SettingsSection("Cost estimate") {
                    LabeledRow("Per 1k input") {
                        CurrencyField(value: $store.settings.costPer1kInputTokens)
                    }
                    LabeledRow("Per 1k output") {
                        CurrencyField(value: $store.settings.costPer1kOutputTokens)
                    }
                    Text("Leave at zero to hide cost. Useful for comparing local usage against a hosted API's price.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                SettingsSection("General") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { vm.launchAtLogin },
                        set: { vm.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11.5))
                    if let error = vm.launchAtLoginError {
                        Text(error).font(.system(size: 10)).foregroundStyle(Theme.danger)
                    }
                    Toggle("Show today's tokens in the menu bar", isOn: $store.settings.showTokensInMenuBar)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11.5))
                    Toggle("Edge gauges: floating rings at the screen edge", isOn: $store.settings.showEdgeGauges)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11.5))
                    Text("Rings show today's budget and each app's share of today's tokens. Drag the strip to move it.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                SettingsSection("Data") {
                    HStack(spacing: 8) {
                        Button("Export CSV") { vm.exportUsage(as: .csv) }
                        Button("Export JSON") { vm.exportUsage(as: .json) }
                        Spacer()
                        Button("Reset stats", role: .destructive) { vm.isConfirmingReset = true }
                    }
                    .controlSize(.small)
                    if let message = vm.exportMessage {
                        Text(message).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text("\(vm.usageStore.records.count.formatted()) requests stored locally in Application Support.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
        }
        .onChange(of: store.settings) { vm.refreshBudgetSnapshot() }
        .alert("Reset all usage data?", isPresented: Binding(
            get: { vm.isConfirmingReset },
            set: { vm.isConfirmingReset = $0 }
        )) {
            Button("Reset", role: .destructive) { vm.resetStats() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every recorded request. Settings are kept.")
        }
    }

    private var proxyStatus: String {
        if let message = vm.proxyStatusMessage { return message }
        return vm.isProxyRunning
            ? "Listening on \(vm.proxyURLString)"
            : "Proxy is not running."
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content
        }
        .card()
    }
}

private struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .frame(width: 100, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

private struct CurrencyField: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 4) {
            Text("$").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("0.00", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 76)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppViewModel())
        .frame(width: 380, height: 600)
}
