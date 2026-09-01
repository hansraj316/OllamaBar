import SwiftUI

/// Shared visual vocabulary: an always-dark "ink" surface, two data hues
/// (input / output), and three usage hues that a bar or ring moves through as
/// it fills (mint → lime → hot).
enum Theme {
    static let ink     = Color(red: 0.04, green: 0.04, blue: 0.045)
    static let input   = Color(red: 0.42, green: 0.49, blue: 0.98)
    static let output  = Color(red: 0.15, green: 0.76, blue: 0.62)

    static let mint    = Color(red: 0.24, green: 0.88, blue: 0.52)
    static let lime    = Color(red: 0.91, green: 1.00, blue: 0.23)
    static let hot     = Color(red: 1.00, green: 0.25, blue: 0.06)

    static let warning = lime
    static let danger  = hot
    static let success = mint

    static let cardFill   = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.08)
    static let track      = Color.white.opacity(0.13)
    static let radius: CGFloat = 14

    /// Colour for a usage fraction: calm while there is headroom, hot when it is nearly gone.
    static func usageColor(_ fraction: Double) -> Color {
        if fraction >= 0.8 { return hot }
        if fraction >= 0.5 { return lime }
        return mint
    }

    /// Distinct hue for the n-th ring / share in a small set.
    static func shareColor(_ index: Int) -> Color {
        [hot, mint, lime, input, output][index % 5]
    }

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [input, output], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardModifier(padding: padding)) }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }
}

struct StatusPill: View {
    let label: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isOn ? Theme.success : Theme.danger)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.cardFill))
        .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
        .help(isOn ? "\(label) is reachable" : "\(label) is not reachable")
    }
}

struct Chip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .foregroundStyle(tint)
    }
}

struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                Text(title.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.5)
            }
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .card(padding: 12)
    }
}

enum Format {
    static func compact(_ n: Int) -> String {
        let value = Double(n)
        switch n {
        case ..<1000:      return "\(n)"
        case ..<1_000_000: return trim(value / 1000) + "k"
        default:           return trim(value / 1_000_000) + "M"
        }
    }

    private static func trim(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func duration(ms: Int) -> String {
        ms < 1000 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1000)
    }

    static func rate(_ tokensPerSecond: Double) -> String {
        String(format: "%.0f tok/s", tokensPerSecond)
    }

    static func cost(_ amount: Double) -> String {
        amount > 0 && amount < 0.01 ? String(format: "$%.4f", amount) : String(format: "$%.2f", amount)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
