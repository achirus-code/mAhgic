import SwiftUI
import mAhgicCore

// MARK: - Palette ("dark chocolate" with cookie amber and charge green)

enum Theme {
    static let backgroundTop = Color(hex: 0x1E1713)
    static let backgroundBottom = Color(hex: 0x120E0B)
    static let card = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.07)
    static let cream = Color(hex: 0xF6EDE2)
    static let muted = Color(hex: 0xF6EDE2).opacity(0.58)
    static let faint = Color(hex: 0xF6EDE2).opacity(0.34)
    static let amber = Color(hex: 0xE8A95B)
    static let green = Color(hex: 0x4CD37E)
    static let orange = Color(hex: 0xF0A23B)
    static let red = Color(hex: 0xE5634D)
    static let blue = Color(hex: 0x6CB4F0)
    static let violet = Color(hex: 0xC792EA)

    static func health(_ percent: Double?) -> Color {
        guard let percent else { return muted }
        return percent >= 80 ? green : percent >= 60 ? orange : red
    }

    static func charge(_ percent: Double?) -> Color {
        guard let percent else { return muted }
        return percent > 20 ? green : percent > 10 ? orange : red
    }

    static var background: some View {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Formatting

enum Fmt {
    static func mAh(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value.formatted()) mAh"
    }

    static func percent(_ value: Double?, digits: Int = 0) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits))) + " %"
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func temperature(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return number(value) + " °C"
    }

    static func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    static func duration(minutes: Int?) -> String {
        guard let minutes else { return "—" }
        return String(format: "%d:%02d h", minutes / 60, minutes % 60)
    }

    static func volts(_ millivolts: Int?) -> String {
        guard let millivolts else { return "—" }
        return number(Double(millivolts) / 1000, digits: 2) + " V"
    }

    static func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
}

func ageString(since date: Date) -> String {
    let comps = Calendar.current.dateComponents([.year, .month], from: date, to: Date())
    let years = comps.year ?? 0, months = comps.month ?? 0
    if years == 0 { return "\(months) month\(months == 1 ? "" : "s")" }
    return "\(years) y \(months) m"
}

/// What is happening with power right now, e.g. "Charging with 42,4 W".
struct PowerState {
    var text: String
    var symbol: String
    var tint: Color

    init(amperage: Int?, watts: Double?, externalConnected: Bool, fullyCharged: Bool) {
        if let a = amperage, let w = watts, a > 0 {
            (text, symbol, tint) = ("Charging with \(Fmt.number(abs(w))) W", "bolt.fill", Theme.green)
        } else if let a = amperage, let w = watts, a < 0 {
            (text, symbol, tint) = ("Discharging with \(Fmt.number(abs(w))) W", "arrow.down.right", Theme.amber)
        } else if externalConnected {
            (text, symbol, tint) = (fullyCharged ? "On adapter · fully charged" : "On adapter · not charging",
                                    "powerplug.fill", Theme.blue)
        } else {
            (text, symbol, tint) = ("Running on battery", "battery.75percent", Theme.amber)
        }
    }
}

// MARK: - Building blocks

struct RingGauge: View {
    var fraction: Double
    var tint: Color
    var value: String
    var caption: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.001), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.4), radius: 5)
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cream)
                Text(caption.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 90, height: 90)
    }
}

struct MiniRing: View {
    var fraction: Double
    var tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.001), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct StatSpec: Identifiable {
    var id: String { title }
    var symbol: String
    var tint: Color
    var title: String
    var value: String
    var note: String? = nil
}

struct StatCell: View {
    var stat: StatSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: stat.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(stat.tint)
                    .frame(width: 11)
                Text(stat.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Text(stat.value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .textSelection(.enabled)
            Text(stat.note ?? " ")
                .font(.system(size: 9))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
    }
}

typealias KVSection = (title: String, rows: [(String, String)])

/// Compact key/value list used on the "Details" segment.
struct KVList: View {
    var sections: [KVSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.amber)
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.0).foregroundStyle(Theme.muted)
                            Spacer(minLength: 4)
                            Text(row.1)
                                .foregroundStyle(Theme.cream)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 10.5))
                    }
                }
            }
        }
    }
}

struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Small custom segmented control that matches the theme.
struct SegmentBar<T: Hashable>: View {
    var items: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let selected = item.0 == selection
                Button {
                    selection = item.0
                } label: {
                    Text(item.1)
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color(hex: 0x1E1713) : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(Capsule().fill(selected ? Theme.amber : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}
