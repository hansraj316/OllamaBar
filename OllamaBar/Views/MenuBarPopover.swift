import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            TabBar()
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            FooterView()
        }
        .frame(width: 380, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await vm.monitor.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.selectedTab {
        case .overview: OverviewTab()
        case .models:   ModelsTab()
        case .activity: ActivityTab()
        case .settings: SettingsView()
        }
    }
}

private struct HeaderView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.heroGradient)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("OllamaBar").font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(label: "Proxy", isOn: vm.isProxyRunning)
            StatusPill(label: "Ollama", isOn: vm.monitor.isOnline)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        let s = vm.settingsStore.settings
        let targetPort = URL(string: s.targetURL)?.port.map { ":\($0)" } ?? s.targetURL
        return "Proxy :\(s.proxyPort) → \(targetPort)"
    }
}

private struct TabBar: View {
    @Environment(AppViewModel.self) var vm
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppViewModel.Tab.allCases) { tab in
                let selected = vm.selectedTab == tab
                Button {
                    withAnimation(.snappy(duration: 0.22)) { vm.selectedTab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 10.5, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.09))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardFill))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

private struct FooterView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        HStack(spacing: 12) {
            Button { vm.openRepository() } label: {
                Label("OllamaBar \(vm.appVersion)", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open OllamaBar on GitHub")

            Spacer()

            if vm.blockedRequestCount > 0 {
                Label("\(vm.blockedRequestCount) blocked", systemImage: "hand.raised.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.danger)
            }

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    MenuBarPopover()
        .environment(AppViewModel())
}
