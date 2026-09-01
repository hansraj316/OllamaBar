import SwiftUI

struct BreakdownView: View {
    @Environment(AppViewModel.self) var vm

    private var rows: [(name: String, tokens: TokenPair)] {
        let data = vm.breakdownMode == .byModel
            ? vm.usageStore.breakdownByModel(in: vm.breakdownRange)
            : vm.usageStore.breakdownByApp(in: vm.breakdownRange)
        guard data.count > 5 else { return data }
        let top5 = Array(data.prefix(5))
        let restTokens = data.dropFirst(5).reduce(TokenPair(prompt: 0, eval: 0)) {
            TokenPair(prompt: $0.prompt + $1.tokens.prompt, eval: $0.eval + $1.tokens.eval)
        }
        return top5 + [(name: "Others", tokens: restTokens)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Breakdown")
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.breakdownMode },
                    set: { vm.breakdownMode = $0 }
                )) {
                    Text("Model").tag(AppViewModel.BreakdownMode.byModel)
                    Text("App").tag(AppViewModel.BreakdownMode.byApp)
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .labelsHidden()
                .frame(width: 110)
            }

            HStack(spacing: 4) {
                ForEach(UsageRange.allCases) { range in
                    RangeChip(title: range.rawValue, selected: vm.breakdownRange == range) {
                        vm.breakdownRange = range
                    }
                }
            }

            let rows = self.rows
            if rows.isEmpty {
                EmptyHint(text: "No requests in this range yet.")
            } else {
                let maxTotal = max(1, rows.first?.tokens.total ?? 1)
                VStack(spacing: 7) {
                    ForEach(rows, id: \.name) { row in
                        HStack(spacing: 8) {
                            Text(row.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 96, alignment: .leading)
                            GeometryReader { geo in
                                let width = geo.size.width * CGFloat(row.tokens.total) / CGFloat(maxTotal)
                                let promptWidth = width * CGFloat(row.tokens.prompt) / CGFloat(max(1, row.tokens.total))
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.track)
                                    HStack(spacing: 0) {
                                        Rectangle().fill(Theme.input).frame(width: promptWidth)
                                        Rectangle().fill(Theme.output).frame(width: max(0, width - promptWidth))
                                    }
                                    .clipShape(Capsule())
                                }
                            }
                            .frame(height: 8)
                            Text(Format.compact(row.tokens.total))
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 46, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .card()
    }
}

struct RangeChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? Color.primary.opacity(0.12) : Theme.cardFill))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BreakdownView()
        .environment(AppViewModel())
        .frame(width: 380)
}
