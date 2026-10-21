import AppKit
import Combine
import CPetCore
import SwiftUI
import os

private let log = Logger(subsystem: "com.erag.mypet", category: "app")

/// Owns every long-lived object and applies settings and power state to the pets.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    let metrics = MetricsStore()
    let power = PowerMonitor()
    let login = LoginItemManager()
    private(set) var updates: UpdateController!
    let library = SpriteLibrary.shared

    private var monitor: MonitorService?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard RustBridge.isCompatible else {
            fail("The \(AppInfo.name) engine library (ABI \(RustBridge.libraryABI)) doesn't match this app (ABI \(RustBridge.expectedABI)). Rebuild with scripts/build-app.sh.")
            return
        }
        library.loadAll()
        guard !library.pets.isEmpty else {
            fail("No pets were found in the app bundle.")
            return
        }
        guard let monitor = MonitorService(deliver: { [weak self] m in self?.deliver(m) }) else {
            fail("Couldn't start system monitoring.")
            return
        }
        self.monitor = monitor

        updates = UpdateController() // starts Sparkle's scheduled background checks
        NotificationCenter.default.publisher(for: .mypetWillRelaunchForUpdate)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.store.flush() } }
            .store(in: &cancellables)

        NSApp.mainMenu = makeMainMenu()
        menuBar = MenuBarController(
            library: library,
            popoverContent: { [unowned self] in
                MenuContentView(store: store, metrics: metrics, updates: updates,
                                openSettings: { [weak self] in self?.openSettings() },
                                quit: { NSApp.terminate(nil) })
            })
        // Menu-bar visibility and popover open/close change how much work is worthwhile.
        menuBar?.onStateChange = { [weak self] in self?.reapply() }

        // @Published emits before the property changes, so use the delivered value.
        store.$settings.removeDuplicates().sink { [weak self] s in self?.apply(s) }.store(in: &cancellables)
        power.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reapply() } }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .sink { [weak self] n in
                MainActor.assumeIsolated {
                    guard (n.object as? NSWindow) === self?.settingsWindow?.window else { return }
                    NSApp.setActivationPolicy(.accessory)
                    // The window still counts as visible during willClose; re-evaluate after.
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.reapply() } }
                }
            }
            .store(in: &cancellables)

        apply(store.settings)
        log.info("\(AppInfo.name, privacy: .public) started with \(self.library.pets.count) pets")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings() // opening the app again from Finder shows settings
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        store.flush()
    }

    // MARK: Applying state

    private func reapply() { apply(store.settings) }

    private func apply(_ s: PetSettings) {
        let policy = EnergyPolicy(.init(
            paused: s.paused,
            suspended: power.isSuspended,
            menuBarVisible: menuBar?.isMenuBarVisible ?? true,
            uiOpen: (menuBar?.isPopoverShown ?? false) || (settingsWindow?.window?.isVisible ?? false),
            onBattery: power.onBattery,
            lowPowerMode: power.lowPowerMode,
            batterySaver: s.batterySaver,
            samplingInterval: s.samplingInterval))

        if let monitor {
            if let interval = policy.samplingInterval {
                if monitor.isRunning {
                    monitor.setInterval(interval)
                } else {
                    monitor.start(interval: interval) // first sample fires immediately (also after wake)
                }
            } else {
                monitor.stop()
            }
        }

        menuBar?.apply(s, maxFPS: policy.maxFPS)
        menuBar?.setRunning(policy.animate)
    }

    private func deliver(_ m: PetMetrics) {
        metrics.publish(m)
        menuBar?.update(metrics: m)
    }

    // MARK: Windows

    func openSettings() {
        menuBar?.closePopover()
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(store)
                .environmentObject(metrics)
                .environmentObject(login)
                .environmentObject(updates)
            settingsWindow = SettingsWindowController(rootView: root)
        }
        // Show in the Dock and app switcher while settings are open.
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.present()
        reapply() // live stats are on screen now: sample at the normal rate
    }

    private func fail(_ message: String) {
        log.fault("\(message, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) can't start"
        alert.informativeText = message
        alert.alertStyle = .critical
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "About \(AppInfo.name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction(_:)), keyEquivalent: ",")
        settings.target = self
        app.addItem(settings)
        let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesAction(_:)), keyEquivalent: "")
        checkUpdates.target = self
        app.addItem(checkUpdates)
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(AppInfo.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window
        return main
    }

    @objc private func openSettingsAction(_ sender: Any?) { openSettings() }
    @objc private func checkForUpdatesAction(_ sender: Any?) {
        menuBar?.closePopover()
        updates.checkForUpdates()
    }
}
