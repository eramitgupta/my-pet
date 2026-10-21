import AppKit
import IOKit.ps

/// Tracks the conditions that should slow down or stop animation:
/// battery power / Low Power Mode (throttle) and sleep / screen lock / display sleep (stop).
@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var onBattery = false
    @Published private(set) var lowPowerMode = false
    @Published private(set) var systemAsleep = false
    @Published private(set) var screensAsleep = false
    @Published private(set) var screenLocked = false

    /// Nothing is visible to the user: stop all timers.
    var isSuspended: Bool { systemAsleep || screensAsleep || screenLocked }

    private var runLoopSource: CFRunLoopSource?
    /// Each observer token with the center it was registered on, so deinit removes it there.
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// Test hook for machines without a battery: MYPET_SIMULATE_POWER=battery|lowpower.
    private let simulated = ProcessInfo.processInfo.environment["MYPET_SIMULATE_POWER"]

    init() {
        refreshPowerSource()
        lowPowerMode = simulated == "lowpower" || ProcessInfo.processInfo.isLowPowerModeEnabled

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refreshPowerSource() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            runLoopSource = src
        }

        let ws = NSWorkspace.shared.notificationCenter
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (PowerMonitor) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self { body(self) }
                }
            }
            observers.append((center, token))
        }
        on(ws, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        on(ws, NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        on(ws, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        on(ws, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        let dnc = DistributedNotificationCenter.default()
        on(dnc, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        on(dnc, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
        on(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) {
            $0.lowPowerMode = $0.simulated == "lowpower" || ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    deinit {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func refreshPowerSource() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { onBattery = false; return }
        let battery = simulated == "battery" || simulated == "lowpower" || type == kIOPSBatteryPowerValue
        if battery != onBattery { onBattery = battery }
    }
}
