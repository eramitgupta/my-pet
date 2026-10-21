import AppKit
import Combine
import os
import Sparkle

private let log = Logger(subsystem: "com.erag.mypet", category: "updates")

/// App updates via Sparkle 2. Sparkle supplies everything user-facing and security-critical:
/// the native "update available" window (current and new version, release notes, Install
/// Update / Remind Me Later / Skip), the "You're up to date" alert, error alerts, the download,
/// EdDSA signature verification of both the appcast feed and the archive, installation and
/// relaunch. This class only wires it into mypet's UI and preferences.
///
/// Settings survive updates: they live in UserDefaults (`com.erag.mypet`) and user pets in
/// Application Support, outside the app bundle Sparkle replaces.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let releasesPage = URL(string: "https://github.com/eramitgupta/mypet/releases")!

    /// True when this build carries an update signing key and feed. Local development builds
    /// made without a key can't verify updates, so they don't start the updater.
    let isConfigured: Bool

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastUpdateCheck: Date?
    @Published var automaticallyChecks: Bool {
        didSet { if automaticallyChecks != updater?.automaticallyChecksForUpdates { updater?.automaticallyChecksForUpdates = automaticallyChecks } }
    }
    @Published var automaticallyDownloads: Bool {
        didSet { if automaticallyDownloads != updater?.automaticallyDownloadsUpdates { updater?.automaticallyDownloadsUpdates = automaticallyDownloads } }
    }

    private var controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }
    private var observations: [NSKeyValueObservation] = []

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        isConfigured = !key.isEmpty && !key.hasPrefix("$(") && URL(string: feed)?.scheme == "https"
        automaticallyChecks = false
        automaticallyDownloads = false
        super.init()

        guard isConfigured else {
            log.notice("Updates disabled: this build has no Sparkle signing key or feed URL")
            return
        }
        // startingUpdater: true schedules automatic background checks per the user's choice.
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                      userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        lastUpdateCheck = updater.lastUpdateCheckDate

        // Sparkle's properties are KVO-observable; mirror them for SwiftUI.
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] u, _ in
                let value = u.canCheckForUpdates
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] u, _ in
                let value = u.lastUpdateCheckDate
                Task { @MainActor in self?.lastUpdateCheck = value }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] u, _ in
                let value = u.automaticallyChecksForUpdates
                Task { @MainActor in if self?.automaticallyChecks != value { self?.automaticallyChecks = value } }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] u, _ in
                let value = u.automaticallyDownloadsUpdates
                Task { @MainActor in if self?.automaticallyDownloads != value { self?.automaticallyDownloads = value } }
            },
        ]
    }

    /// User-initiated check. Sparkle shows the update window, "You're up to date", or an error.
    /// Works whether or not automatic checks are on.
    func checkForUpdates() {
        guard let controller else {
            showNotConfiguredAlert()
            return
        }
        NSApp.activate(ignoringOtherApps: true) // an accessory app must come forward for the dialog
        controller.checkForUpdates(nil)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func showNotConfiguredAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Updates aren’t available in this build"
        alert.informativeText = "This copy of \(AppInfo.name) was built without an update signing key, so it can’t verify downloads. Get the latest version from GitHub Releases instead."
        alert.addButton(withTitle: "Open Releases Page")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.releasesPage)
        }
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateController: SPUUpdaterDelegate {
    /// Test hook: MYPET_FEED_URL points the updater at a local appcast. Safe to leave in
    /// release builds because every update must still carry a valid EdDSA signature from the
    /// key embedded in this app, and the feed itself must be signed (SURequireSignedFeed).
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["MYPET_FEED_URL"]
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log.notice("Update available: \(item.displayVersionString, privacy: .public) (\(item.versionString, privacy: .public))")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        log.info("No update found: \(error.localizedDescription, privacy: .public)")
    }

    /// Network failures, missing releases and bad signatures end here. For user-initiated
    /// checks Sparkle has already shown a native alert; background failures stay silent.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let e = error as NSError
        log.error("Update aborted: \(e.domain, privacy: .public) \(e.code): \(e.localizedDescription, privacy: .public)")
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        log.notice("Relaunching to finish the update")
        Task { @MainActor in NotificationCenter.default.post(name: .mypetWillRelaunchForUpdate, object: nil) }
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension UpdateController: SPUStandardUserDriverDelegate {
    /// mypet is a menu-bar (accessory) app: let Sparkle show scheduled updates gently,
    /// without stealing focus from whatever the user is doing.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}

extension Notification.Name {
    static let mypetWillRelaunchForUpdate = Notification.Name("mypetWillRelaunchForUpdate")
}
