import SwiftUI

/// One ring on the edge strip.
struct EdgeGauge: Identifiable {
    let id: String
    let fraction: Double
    let color: Color
    /// SF Symbol drawn inside the ring, or `nil` to show `initial` instead.
    let symbol: String?
    let initial: String?
    let label: String
    let help: String
}

struct RingGauge: View {
    let gauge: EdgeGauge

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.015, min(1, gauge.fraction)))
                    .stroke(gauge.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy(duration: 0.4), value: gauge.fraction)
                if let symbol = gauge.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(gauge.initial ?? "?")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 56, height: 56)

            Text(gauge.label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .help(gauge.help)
    }
}

/// The floating strip that hugs the right edge of the screen.
struct GaugeStripView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        VStack(spacing: 22) {
            ForEach(vm.edgeGauges) { gauge in
                RingGauge(gauge: gauge)
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 28)
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .frame(width: 104)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 30, style: .continuous)
                .fill(Color.black)
        )
        .preferredColorScheme(.dark)
    }
}

#Preview {
    GaugeStripView()
        .environment(AppViewModel())
}
