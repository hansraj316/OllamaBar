import SwiftUI

/// Shared visual vocabulary for the popover: two data hues (input / output),
/// three status hues, and a translucent card treatment that follows the system appearance.
enum Theme {
    static let input   = Color(red: 0.42, green: 0.49, blue: 0.98)
    static let output  = Color(red: 0.15, green: 0.76, blue: 0.62)
    static let warning = Color(red: 0.98, green: 0.70, blue: 0.18)
    static let danger  = Color(red: 0.96, green: 0.35, blue: 0.35)
    static let success = Color(red: 0.30, green: 0.78, blue: 0.45)

    static let cardFill   = Color.primary.opacity(0.045)
    static let cardStroke = Color.primary.opacity(0.07)
    static let track      = Color.primary.opacity(0.08)
    static let radius: CGFloat = 12

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
