import AppKit
import QuartzCore

/// A main-thread timer that reports elapsed seconds per tick and can change rate cheaply.
/// Pets tick at their sprite frame rate (2–24 Hz), not at display refresh rate, which keeps
/// idle CPU near zero. Stopping it removes the timer entirely.
@MainActor
final class FrameTicker {
    private var timer: Timer?
    private var last: CFTimeInterval = 0
    private(set) var interval: TimeInterval = 0
    private let handler: (Double) -> Void

    init(handler: @escaping (Double) -> Void) {
        self.handler = handler
    }

    var isRunning: Bool { timer != nil }

    func run(interval newInterval: TimeInterval) {
        let clamped = newInterval.clamped(to: (1.0 / 60)...1.0)
        // Ignore changes under 3 %: restarting the timer re-phases it, and CPU-driven speed
        // drifts a little with every metrics sample.
        if timer != nil, abs(clamped - interval) < interval * 0.03 { return }
        timer?.invalidate()
        interval = clamped
        if last == 0 { last = CACurrentMediaTime() }
        let t = Timer(timeInterval: clamped, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        // A generous tolerance lets macOS fire us together with other timers (fewer CPU
        // wakeups). Rust's frame stepping absorbs lateness up to 0.7 of a frame.
        t.tolerance = clamped * 0.2
        RunLoop.main.add(t, forMode: .common) // keep animating during menu tracking / drags
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        last = 0
    }

    private func fire() {
        let now = CACurrentMediaTime()
        let dt = last == 0 ? interval : now - last
        last = now
        handler(dt)
    }
}
