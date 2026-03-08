import SwiftUI
import Foundation
import Combine

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

class UsageTracker: ObservableObject {
    @Published var usage: UsageData = UsageData()
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
    
    func startProxy() {
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
                self.proxyProcess = process
                process.waitUntilExit()
            } catch {
                print("Failed to start python proxy: \(error)")
            }
        }
    }
}

@main
struct OllamaBarApp: App {
    @StateObject var tracker = UsageTracker()

    var todayUsage: Int {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        // Python proxy uses YYYY-MM-DD
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return tracker.usage.daily[dateString]?.total ?? 0
    }

    var body: some Scene {
        MenuBarExtra("OllamaBar", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ollama Usage")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                HStack {
                    Text("Today's Tokens:")
                    Spacer()
                    Text("\(todayUsage)")
                        .bold()
                }
                
                HStack {
                    Text("Total Tokens:")
                    Spacer()
                    Text("\(tracker.usage.total.total)")
                        .bold()
                }
                
                Divider()
                
                Text("⚠️ Set your API URL to:")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("http://127.0.0.1:11435")
                    .font(.system(.caption, design: .monospaced))
                
                Divider()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
            .frame(width: 250)
        }
        .menuBarExtraStyle(.window)
    }
}
