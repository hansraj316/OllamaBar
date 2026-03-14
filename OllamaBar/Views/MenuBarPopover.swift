import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
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
        .frame(width: 320, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
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
        .padding(.vertical, 12)
    }

    private var footerButtons: some View {
        VStack(spacing: 0) {
            Button(action: { }) {
                Text("About OllamaBar...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            Button(action: { vm.resetStats() }) {
                Text("Reset Stats")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit OllamaBar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    MenuBarPopover()
        .environment(AppViewModel())
}
