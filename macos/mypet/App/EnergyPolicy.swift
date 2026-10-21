import Foundation

/// Decides how much work mypet may do right now. All battery and visibility rules live
/// here, as pure value logic, so they are easy to read and to test.
///
/// The biggest energy cost is waking the CPU, so the policy cuts wakeups: no animation
/// while nothing is visible, a lower frame rate on battery, and slow sampling when no one is
/// looking at the numbers.
struct EnergyPolicy: Equatable {
    struct Inputs: Equatable {
        var paused = false
        /// System asleep, screen locked or displays off.
        var suspended = false
        /// False while a full-screen app or an auto-hidden menu bar hides the status item.
        var menuBarVisible = true
        /// The popover or the Settings window is open and shows live numbers.
        var uiOpen = false
        var onBattery = false
        var lowPowerMode = false
        var batterySaver = true
        var samplingInterval: TimeInterval = 1.5
    }

    /// Sampling interval while the pet is static and no UI shows metrics.
    static let idleSamplingInterval: TimeInterval = 15

    /// Whether the pet animates at all.
    let animate: Bool
    /// Frame-rate cap, or nil for the pet's natural rate (sprite fps × speed).
    let maxFPS: Double?
    /// How often to sample metrics, or nil to stop sampling.
    let samplingInterval: TimeInterval?

    init(_ i: Inputs) {
        // Low Power Mode is the user's explicit request to save energy, so it always applies.
        // Battery alone applies only with Battery saver on.
        let (cap, minSampling): (Double?, TimeInterval) =
            i.lowPowerMode ? (5, 5)
            : (i.onBattery && i.batterySaver) ? (8, 3)
            : (nil, 0)

        animate = !i.paused && !i.suspended && i.menuBarVisible
        maxFPS = cap
        if i.suspended {
            samplingInterval = nil
        } else if !animate && !i.uiOpen {
            samplingInterval = max(Self.idleSamplingInterval, i.samplingInterval)
        } else {
            samplingInterval = max(i.samplingInterval, minSampling)
        }
    }
}
