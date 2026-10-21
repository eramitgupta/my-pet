import CPetCore
import SwiftUI

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}

extension PetSettings {
    /// The memory figure the pets are coloured by.
    func memoryScore(_ m: PetMetrics) -> Double {
        Double(memoryMode == .usage ? m.ram_used_percent : m.pressure_score)
    }

    /// Gradient colour for a score, computed by the Rust engine (same as the pets).
    func gradientColor(at score: Double) -> Color {
        let c = RustBridge.sampleBands(colors: gradientColors.map(PetColor.init),
                                       thresholds: thresholds.map(Float.init), value: Float(score))
        return c.map { Color(.sRGB, red: Double($0.r), green: Double($0.g), blue: Double($0.b)) } ?? .gray
    }
}

/// Compact live statistics, shared by the menu-bar dropdown and settings.
struct LiveStatsView: View {
    @ObservedObject var metrics: MetricsStore
    let settings: PetSettings

    var body: some View {
        VStack(spacing: 8) {
            if let m = metrics.latest {
                StatRow(title: "CPU", value: "\(Int(m.cpu_percent.rounded()))%",
                        fraction: Double(m.cpu_percent) / 100, tint: .accentColor,
                        detail: speedLabel(m))
                StatRow(title: "Memory", value: "\(Int(m.ram_used_percent.rounded()))%",
                        fraction: Double(m.ram_used_percent) / 100,
                        tint: settings.gradientColor(at: Double(m.ram_used_percent)),
                        detail: "\(bytes(m.ram_used_bytes)) of \(bytes(m.ram_total_bytes))")
                StatRow(title: "Pressure", value: m.pressureLevel.rawValue,
                        fraction: Double(m.pressure_score) / 100,
                        tint: settings.gradientColor(at: Double(m.pressure_score)),
                        detail: "Score \(Int(m.pressure_score.rounded())) · swap \(bytes(m.swap_used_bytes))")
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private func speedLabel(_ m: PetMetrics) -> String {
        let c = m.cpu_percent
        return c < 25 ? "Pet strolls" : c < 65 ? "Pet trots" : "Pet sprints"
    }

    private func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory)
    }
}

struct StatRow: View {
    let title: String
    let value: String
    let fraction: Double
    let tint: Color
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout)
                Spacer()
                Text(value).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(tint)
                        .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
                        .animation(.easeOut(duration: 0.6), value: fraction)
                }
            }
            .frame(height: 5)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
        .accessibilityValue(detail ?? "")
    }
}
