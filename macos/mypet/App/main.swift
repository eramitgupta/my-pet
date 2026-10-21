import AppKit

// AppKit entry point. mypet is a menu-bar utility (LSUIElement), so there is no Dock icon
// until the settings window is opened.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
