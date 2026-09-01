import SwiftUI

struct ModelsTab: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        let monitor = vm.monitor
        let usage = vm.usageStore.tokensByNormalizedModel
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                statusCard

                SectionLabel("Loaded in memory")
                    .padding(.top, 4)
                    .padding(.leading, 2)
                if monitor.loadedModels.isEmpty {
                    EmptyHint(text: monitor.isOnline
                              ? "Nothing loaded. A model loads on its first request and stays resident for a few minutes."
                              : "Connect to Ollama to see which models are resident.")
                        .card()
                } else {
                    ForEach(monitor.loadedModels) { model in
                        LoadedModelRow(model: model)
                    }
                }

                SectionLabel("Installed (\(monitor.installedModels.count))")
                    .padding(.top, 4)
                    .padding(.leading, 2)
                if monitor.installedModels.isEmpty {
                    EmptyHint(text: monitor.isOnline
                              ? "No models installed. Pull one with `ollama pull <model>`."
                              : "Ollama is offline.")
                        .card()
                } else {
                    ForEach(monitor.installedModels) { model in
                        InstalledModelRow(model: model,
                                          tokens: usage[ModelName.normalize(model.name)] ?? 0)
                    }
                }
            }
            .padding(14)
        }
    }

    private var statusCard: some View {
        let monitor = vm.monitor
        let tint = monitor.isOnline ? Theme.success : Theme.danger
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.15))
                Image(systemName: monitor.isOnline ? "checkmark" : "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.isOnline ? "Ollama is online" : "Ollama is unreachable")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                Task { await vm.monitor.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(monitor.isRefreshing)
            .help("Refresh now")
        }
        .card()
    }

    private var statusDetail: String {
        let monitor = vm.monitor
        let target = vm.settingsStore.settings.targetURL
        let checked = monitor.lastChecked.map { "checked \(Format.relative($0))" } ?? "not checked yet"
        if monitor.isOnline {
            let version = monitor.version.map { "v\($0)" } ?? "version unknown"
            return "\(version) at \(target) · \(checked)"
        }
        return "\(target) · start it with `ollama serve` · \(checked)"
    }
}

private struct LoadedModelRow: View {
    @Environment(AppViewModel.self) var vm
    let model: LoadedModel

    private var isUnloading: Bool { vm.monitor.unloadingModel == model.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 4) {
                        if let size = model.details?.parameterSize { Chip(text: size, tint: Theme.input) }
                        if let quant = model.details?.quantizationLevel { Chip(text: quant) }
                        if let family = model.details?.family { Chip(text: family) }
                    }
                }
                Spacer()
                Button(isUnloading ? "Unloading…" : "Unload") {
                    Task { await vm.monitor.unload(model) }
                }
                .controlSize(.small)
                .disabled(isUnloading)
                .help("Evict this model from memory now")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.gpuFraction >= 0.999 ? "100% on GPU" : "\(Format.percent(model.gpuFraction)) on GPU")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.bytes(model.size))
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let expires = model.expiresAt {
                        Text("· unloads \(Format.relative(expires))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(Theme.output).frame(width: geo.size.width * model.gpuFraction)
                    }
                }
                .frame(height: 5)
            }
        }
        .card(padding: 12)
    }
}

private struct InstalledModelRow: View {
    let model: InstalledModel
    let tokens: Int

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.compact(tokens))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("tokens")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .card(padding: 12)
    }

    private var detail: String {
        var parts = [Format.bytes(model.size)]
        if let size = model.details?.parameterSize { parts.append(size) }
        if let quant = model.details?.quantizationLevel { parts.append(quant) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    ModelsTab()
        .environment(AppViewModel())
        .frame(width: 380, height: 600)
}
