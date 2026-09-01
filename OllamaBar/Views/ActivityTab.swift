import SwiftUI

struct ActivityTab: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        let recent = vm.usageStore.recentRecords(limit: 60)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionLabel("Recent requests")
                    Spacer()
                    Text("\(vm.usageStore.todayRequestCount) today")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if vm.blockedRequestCount > 0 {
                        Chip(text: "\(vm.blockedRequestCount) blocked", tint: Theme.danger)
                    }
                }
                .padding(.horizontal, 2)

                if recent.isEmpty {
                    EmptyActivity()
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(recent) { record in
                            ActivityRow(record: record)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct EmptyActivity: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No requests yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Point any Ollama client at the proxy and every request shows up here with its tokens, latency, and speed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Text(vm.proxyURLString)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.track))
                Button("Copy") { vm.copyProxyURL() }
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .card()
    }
}

private struct ActivityRow: View {
    let record: UsageRecord

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(endpointTint)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.model)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Chip(text: record.clientApp)
                }
                HStack(spacing: 4) {
                    Text(endpointLabel)
                    Text("·")
                    Text(record.timestamp, format: .dateTime.hour().minute())
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.input)
                        Text(Format.compact(record.promptTokens))
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.output)
                        Text(Format.compact(record.evalTokens))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()

                if let ms = record.durationMs {
                    Text(speedText(ms: ms))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardFill))
    }

    private var endpointLabel: String {
        var path = record.endpoint.split(separator: "?", maxSplits: 1).first.map(String.init) ?? record.endpoint
        for prefix in ["/api/", "/v1/"] where path.hasPrefix(prefix) {
            path = String(path.dropFirst(prefix.count))
        }
        return path
    }

    private var endpointTint: Color {
        let path = record.endpoint
        if path.contains("chat") { return Theme.output }
        if path.contains("generate") || path.contains("completions") { return Theme.input }
        if path.contains("embed") { return Theme.warning }
        return .secondary
    }

    private func speedText(ms: Int) -> String {
        var text = Format.duration(ms: ms)
        if let rate = record.tokensPerSecond { text += " · " + Format.rate(rate) }
        return text
    }
}

#Preview {
    ActivityTab()
        .environment(AppViewModel())
        .frame(width: 380, height: 600)
}
