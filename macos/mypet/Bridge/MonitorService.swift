import CPetCore
import Foundation

/// Latest metrics for the UI. Main-thread only; the only object views subscribe to.
@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var latest: PetMetrics?

    func publish(_ m: PetMetrics) { latest = m }
}

/// Samples system metrics on one background serial queue and delivers each sample to the
/// main thread. Owns the single shared `MetricsEngine`, so both pets read the same data.
final class MonitorService {
    private let queue = DispatchQueue(label: "com.erag.mypet.monitor", qos: .utility)
    private let engine: MetricsEngine
    private let deliver: @MainActor (PetMetrics) -> Void

    // Touched only on the main thread.
    private var timer: DispatchSourceTimer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private(set) var interval: TimeInterval = 1.5

    init?(deliver: @escaping @MainActor (PetMetrics) -> Void) {
        guard let engine = MetricsEngine() else { return nil }
        self.engine = engine
        self.deliver = deliver
    }

    deinit { stop() }

    var isRunning: Bool { timer != nil }

    func start(interval: TimeInterval) {
        self.interval = interval
        stopTimer()
        let t = DispatchSource.makeTimerSource(queue: queue)
        // 10% leeway lets the OS coalesce our wakeups with others.
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(Int(interval * 100)))
        t.setEventHandler { [weak self] in self?.sampleOnQueue() }
        t.resume()
        timer = t
        startPressureSource()
    }

    func stop() {
        stopTimer()
        pressureSource?.cancel()
        pressureSource = nil
    }

    func setInterval(_ newValue: TimeInterval) {
        guard abs(newValue - interval) > 0.01 || timer == nil else { return }
        if timer != nil { start(interval: newValue) } else { interval = newValue }
    }

    func sampleNow() {
        queue.async { [weak self] in self?.sampleOnQueue() }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func startPressureSource() {
        guard pressureSource == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let event = src?.data else { return }
            let level: UInt8 = event.contains(.critical) ? 4 : event.contains(.warning) ? 2 : 1
            self.engine.notePressureEvent(level: level)
            self.sampleOnQueue() // reflect the change now, not at the next tick
        }
        src.resume()
        pressureSource = src
    }

    private func sampleOnQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let m = engine.sample() else { return }
        let deliver = self.deliver
        DispatchQueue.main.async {
            MainActor.assumeIsolated { deliver(m) }
        }
    }
}
