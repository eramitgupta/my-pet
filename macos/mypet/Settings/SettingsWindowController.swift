import AppKit
import SwiftUI

/// Hosts SettingsView in a standard window. Created lazily and reused.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    convenience init(rootView: some View) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "\(AppInfo.name) Settings"
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("mypetSettings")
        window.contentViewController = NSHostingController(rootView: rootView)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.center()
        self.init(window: window)
        window.delegate = self
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
