import SwiftUI

struct BreakdownView: View {
    @Environment(AppViewModel.self) var vm

    var rows: [(name: String, tokens: TokenPair)] {
        let data = vm.breakdownMode == .byModel
            ? vm.usageStore.breakdownByModel
            : vm.usageStore.breakdownByApp
        guard data.count > 5 else { return data }
        let top5 = Array(data.prefix(5))
        let restTokens = data.dropFirst(5).reduce(TokenPair(prompt: 0, eval: 0)) {
            TokenPair(prompt: $0.prompt + $1.tokens.prompt, eval: $0.eval + $1.tokens.eval)
        }
        return top5 + [(name: "Others", tokens: restTokens)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BREAKDOWN").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.breakdownMode },
                    set: { vm.breakdownMode = $0 }
                )) {
                    Text("By Model").tag(AppViewModel.BreakdownMode.byModel)
                    Text("By App").tag(AppViewModel.BreakdownMode.byApp)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .controlSize(.mini)
            }

            let maxTotal = rows.first?.tokens.total ?? 1
            ForEach(rows, id: \.name) { row in
                HStack(spacing: 8) {
                    Text(row.name).font(.caption).frame(width: 80, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.7))
                                .frame(width: geo.size.width * CGFloat(row.tokens.total) / CGFloat(maxTotal))
                        }
                    }
                    .frame(height: 12)
                    Text(row.tokens.total.formatted())
                        .font(.caption).monospacedDigit().frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

#Preview {
    BreakdownView()
        .environment(AppViewModel())
}
