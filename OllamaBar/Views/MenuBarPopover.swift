import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                Divider()
                StatsView()
                Divider()
                BreakdownView()
                Divider()
                HeatmapView()
                Divider()
                SettingsView()
                Divider()
                footerButtons
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 600)
    }

    private var header: some View {
        HStack {
            Text("OllamaBar").font(.headline)
            Spacer()
            Label(vm.isProxyRunning ? "Proxy Active" : "Proxy Stopped",
                  systemImage: vm.isProxyRunning ? "circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(vm.isProxyRunning ? .green : .red)
                .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footerButtons: some View {
        VStack(spacing: 0) {
            Divider()
            Button("About OllamaBar...") { }
                .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Button("Reset Stats") { vm.resetStats() }
                .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Button("Quit OllamaBar") { NSApp.terminate(nil) }
                .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    MenuBarPopover()
        .environment(AppViewModel())
}
