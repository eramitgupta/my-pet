import AppKit
import Sparkle

// Headless Sparkle driver used by scripts/test-updates.sh: runs the real SPUUpdater against an
// installed copy of mypet and auto-answers "Install". harness <app> <feed-url> install|probe
let args = CommandLine.arguments
let appPath = args[1], feedURL = args[2], mode = args[3]
func out(_ s: String) { print(s); fflush(stdout) }

final class AutoDriver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { out("· checking \(feedURL)") }
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        out("· FOUND update \(item.displayVersionString) (build \(item.versionString)), current \(Bundle(path: appPath)!.infoDictionary!["CFBundleShortVersionString"]!)")
        out("· release notes in appcast: \(item.itemDescription?.isEmpty == false ? "yes" : "no")")
        if mode == "install" { reply(.install) } else { reply(.dismiss); exit(0) }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        out("· NOT FOUND: \(error.localizedDescription)"); acknowledgement(); exit(3)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let e = error as NSError
        out("· ERROR (\(e.domain) \(e.code)): \(e.localizedDescription)")
        if let r = e.localizedFailureReason { out("  reason: \(r)") }
        acknowledgement(); exit(4)
    }
    var expected: UInt64 = 0, received: UInt64 = 0
    func showDownloadInitiated(cancellation: @escaping () -> Void) { out("· downloading") }
    func showDownloadDidReceiveExpectedContentLength(_ n: UInt64) { expected = n }
    func showDownloadDidReceiveData(ofLength n: UInt64) { received += n }
    func showDownloadDidStartExtractingUpdate() { out("· downloaded \(received)/\(expected) bytes; verifying + extracting") }
    func showExtractionReceivedProgress(_ p: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { out("· ready to install"); reply(.install) }
    func showInstallingUpdate(withApplicationTerminated t: Bool, retryTerminatingApplication: @escaping () -> Void) { out("· installing (app terminated: \(t))") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        out("· INSTALLED (relaunched: \(relaunched))"); acknowledgement()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
    }
    func dismissUpdateInstallation() { out("· dismissed") }
    func showUpdateInFocus() {}
}

final class Delegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? { feedURL }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let driver = AutoDriver(), delegate = Delegate()
let bundle = Bundle(path: appPath)!
let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: delegate)
do { try updater.start() } catch { out("· start failed: \(error)"); exit(5) }
updater.checkForUpdates()
DispatchQueue.main.asyncAfter(deadline: .now() + 120) { out("· TIMEOUT"); exit(6) }
app.run()
