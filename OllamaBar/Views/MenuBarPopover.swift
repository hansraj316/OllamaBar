import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    StatsView()
                    Divider()
                    BreakdownView()
                    Divider()
                    HeatmapView()
                    Divider()
                    SettingsView()
                }
            }
            
            Divider()
            footerButtons
        }
        .frame(width: 360, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("OllamaBar")
                .font(.headline)
            Spacer()
            Label(vm.isProxyRunning ? "Proxy Active" : "Proxy Stopped",
                  systemImage: vm.isProxyRunning ? "circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(vm.isProxyRunning ? .green : .red)
                .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 0) {
            footerButton("About OllamaBar...") { }
            Divider()
            footerButton("Reset Stats") { vm.resetStats() }
            Divider()
            footerButton("Quit OllamaBar") { NSApp.terminate(nil) }
        }
    }
    
    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

#Preview {
    MenuBarPopover()
        .environment(AppViewModel())
}
