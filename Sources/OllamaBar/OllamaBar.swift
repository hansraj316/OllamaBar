import SwiftUI
import Foundation
import Combine
import AppKit

// MARK: - Models

struct TokenUsage: Codable {
    var prompt: Int = 0
    var eval: Int = 0
    var total: Int { prompt + eval }
}

struct UsageData: Codable {
    var daily: [String: TokenUsage] = [:]
    var weekly: [String: TokenUsage] = [:]
    var total: TokenUsage = TokenUsage()
}

// MARK: - Store

class UsageTracker: ObservableObject {
    @Published var usage: UsageData = UsageData()
    @Published var isProxyRunning: Bool = false
    private var proxyProcess: Process?
    private var timer: AnyCancellable?
    
    let usageURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ollama/ollamabar_usage.json")

    init() {
        startProxy()
        loadUsage()
        
        timer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.loadUsage()
                self?.checkProxyStatus()
            }
    }
    
    deinit {
        proxyProcess?.terminate()
    }

    func loadUsage() {
        do {
            if FileManager.default.fileExists(atPath: usageURL.path) {
                let data = try Data(contentsOf: usageURL)
                let decoded = try JSONDecoder().decode(UsageData.self, from: data)
                DispatchQueue.main.async {
                    self.usage = decoded
                }
            }
        } catch {
            print("Failed to load usage: \(error)")
        }
    }
    
    func checkProxyStatus() {
        // Simple check if process is still alive
        if let process = proxyProcess {
            isProxyRunning = process.isRunning
        } else {
            isProxyRunning = false
        }
    }
    
    func startProxy() {
        // Kill any existing proxy on port 11435 first
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-f", "proxy.py"]
        try? killTask.run()
        killTask.waitUntilExit()

        guard let scriptPath = Bundle.module.path(forResource: "proxy", ofType: "py") else {
            print("Could not find proxy.py")
            return
        }
        
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [scriptPath]
            
            do {
                try process.run()
                DispatchQueue.main.async {
                    self.proxyProcess = process
                    self.isProxyRunning = true
                }
                process.waitUntilExit()
            } catch {
                print("Failed to start python proxy: \(error)")
            }
        }
    }
}

// MARK: - Views

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            
            VStack(spacing: 5) {
                Text("OllamaBar")
                    .font(.title)
                    .bold()
                Text("v1.1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("A beautiful token tracker for Ollama, inspired by CodexBar.")
                .multilineTextAlignment(.center)
                .font(.body)
                .padding(.horizontal)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Link("View on GitHub", destination: URL(string: "https://github.com/hansraj316/OllamaBar")!)
                    .font(.subheadline)
                Text("Created by Hansraj Singh")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Close") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(width: 300)
    }
}

struct UsageRow: View {
    let label: String
    let prompt: Int
    let eval: Int
    let total: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .bold()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Input")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("\(prompt)")
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Output")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                    Text("\(eval)")
                        .font(.system(.body, design: .monospaced))
                }
            }
            
            ProgressView(value: Double(prompt), total: Double(max(1, total)))
                .accentColor(.blue)
                .scaleEffect(x: 1, y: 0.5, anchor: .center)
            
            HStack {
                Text("Total")
                    .font(.headline)
                Spacer()
                Text("\(total)")
                    .font(.system(.headline, design: .monospaced))
                    .bold()
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

@main
struct OllamaBarApp: App {
    @StateObject var tracker = UsageTracker()

    var todayUsage: TokenUsage {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return tracker.usage.daily[dateString] ?? TokenUsage()
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(tracker.isProxyRunning ? .green : .red)
                    Text("OllamaBar")
                        .font(.headline)
                    Spacer()
                    if tracker.isProxyRunning {
                        Text("Proxy Active")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 5)

                Divider()

                UsageRow(label: "TODAY", 
                         prompt: todayUsage.prompt, 
                         eval: todayUsage.eval, 
                         total: todayUsage.total)

                UsageRow(label: "ALL TIME", 
                         prompt: tracker.usage.total.prompt, 
                         eval: tracker.usage.total.eval, 
                         total: tracker.usage.total.total)

                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Proxy Port: 11435")
                        .font(.system(size: 11, design: .monospaced))
                    Text("Target: localhost:11434")
                        .font(.system(size: 11, design: .monospaced))
                }
                .padding(.horizontal, 5)

                Divider()

                Group {
                    Button("About OllamaBar...") {
                        showAbout()
                    }
                    
                    Button("Check for Updates...") {
                        if let url = URL(string: "https://github.com/hansraj316/OllamaBar/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Divider()

                    Button("Quit OllamaBar") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
            }
            .padding(12)
            .frame(width: 280)
        } label: {
            HStack(spacing: 4) {
                // Using a server rack icon as a fallback, 
                // but this will show up in the menu bar.
                Image(systemName: "server.rack")
                Text("\(todayUsage.total)")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
    
    func showAbout() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
