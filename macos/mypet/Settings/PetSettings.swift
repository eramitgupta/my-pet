import Foundation

enum MemoryMode: String, Codable, CaseIterable, Identifiable {
    case usage, pressure
    var id: Self { self }
    var title: String { self == .usage ? "RAM Usage" : "Memory Pressure" }
    var explanation: String {
        switch self {
        case .usage:
            return "How much of your physical RAM is in use. It's the same “Memory Used” figure as Activity Monitor's Memory tab. macOS keeps RAM full on purpose, so high usage is often fine."
        case .pressure:
            return "How hard macOS is working to find free memory. The kernel's pressure level (normal / warning / critical) picks the colour band; free pages, compression and swap place it within the band."
        }
    }
}

/// Which way the pet looks. Sprites are drawn facing right; left mirrors them.
enum PetFacing: String, Codable, CaseIterable, Identifiable {
    case right, left, turnAround
    var id: Self { self }
    var title: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .turnAround: return "Turn around"
        }
    }
    var symbol: String {
        switch self {
        case .right: return "arrow.right"
        case .left: return "arrow.left"
        case .turnAround: return "arrow.left.arrow.right"
        }
    }
    /// The opposite fixed direction (used by the quick "Flip" button).
    var flipped: PetFacing { self == .left ? .right : .left }
}

/// sRGB colour, components 0...1.
struct RGB: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    static let green = RGB(hex: "#34C759")!
    static let yellow = RGB(hex: "#FFD60A")!
    static let orange = RGB(hex: "#FF9F0A")!
    static let red = RGB(hex: "#FF453A")!
}

/// Which pet runs in the menu bar and how fast.
struct PetSlot: Codable, Equatable {
    var petID: String
    var cpuDrivenSpeed = true
    var manualSpeed = 1.0

    init(petID: String, cpuDrivenSpeed: Bool = true, manualSpeed: Double = 1.0) {
        self.petID = petID
        self.cpuDrivenSpeed = cpuDrivenSpeed
        self.manualSpeed = manualSpeed
    }
}

struct PetSettings: Codable, Equatable {
    static let defaultColors = [RGB.green, .yellow, .orange, .red]
    static let defaultThresholds = [35.0, 60.0, 80.0]
    static let speedRange = 0.25...3.0
    static let intervalRange = 1.0...5.0

    var menuBar = PetSlot(petID: "cat")
    var gradientEnabled = true
    var gradientColors = PetSettings.defaultColors
    var thresholds = PetSettings.defaultThresholds
    var memoryMode = MemoryMode.usage
    var paused = false
    var batterySaver = true
    var samplingInterval = 1.5
    /// Animate the menu-bar pet with a layer instead of re-setting the button image.
    var lowCPUMenuBar = true
    var facing = PetFacing.right

    init() {}

    /// Values clamped into their valid ranges (used after decoding and before applying).
    var sanitized: PetSettings {
        var s = self
        s.samplingInterval = samplingInterval.clamped(to: Self.intervalRange)
        s.menuBar.manualSpeed = menuBar.manualSpeed.clamped(to: Self.speedRange)
        if gradientColors.count != 4 { s.gradientColors = Self.defaultColors }
        s.thresholds = Self.sanitizeThresholds(thresholds)
        return s
    }

    /// Keeps 0 < t1 < t2 < t3 < 100 with at least `gap` points between neighbours.
    static func sanitizeThresholds(_ t: [Double], gap: Double = 5) -> [Double] {
        guard t.count == 3, t.allSatisfy({ $0.isFinite }) else { return defaultThresholds }
        let t1 = t[0].clamped(to: gap...(100 - 3 * gap))
        let t2 = t[1].clamped(to: (t1 + gap)...(100 - 2 * gap))
        let t3 = t[2].clamped(to: (t2 + gap)...(100 - gap))
        return [t1, t2, t3]
    }

    // Decoding tolerates missing or unknown keys so settings survive app upgrades.
    enum CodingKeys: String, CodingKey {
        case menuBar, gradientEnabled, gradientColors, thresholds, memoryMode, paused, batterySaver,
             samplingInterval, lowCPUMenuBar, facing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PetSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        menuBar = v(.menuBar, d.menuBar)
        gradientEnabled = v(.gradientEnabled, d.gradientEnabled)
        gradientColors = v(.gradientColors, d.gradientColors)
        thresholds = v(.thresholds, d.thresholds)
        memoryMode = v(.memoryMode, d.memoryMode)
        paused = v(.paused, d.paused)
        batterySaver = v(.batterySaver, d.batterySaver)
        samplingInterval = v(.samplingInterval, d.samplingInterval)
        lowCPUMenuBar = v(.lowCPUMenuBar, d.lowCPUMenuBar)
        facing = v(.facing, d.facing)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
