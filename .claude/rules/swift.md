---
paths:
  - "macos/**/*.swift"
  - "macos/Package.swift"
---

# Swift rules (all app code)

- **Swift 5 language mode, macOS 13 deployment target.** Guard newer APIs with
  `if #available(macOS 14, *)`.
- **Apple frameworks plus Sparkle only.** Sparkle 2 (updates) is the one allowed package,
  pinned in `macos/Package.resolved`. All Sparkle use stays in `App/UpdateController.swift`, and
  Sparkle's own UI and verification are used as-is (no custom updater). Don't add other
  packages.
- **The build must work with only the Command Line Tools.** The SwiftPM path
  (`scripts/build-app.sh`) is how most contributors and CI build, so avoid features that need
  the plugins that ship with full Xcode, such as the `@State` macro (see `swiftui.md`).
- **Threading:**
  - UI controllers, stores and anything touching AppKit are `@MainActor`.
  - `MetricsEngine` lives only on `MonitorService`'s serial queue. Only finished `PetMetrics`
    values hop to main (`DispatchQueue.main.async` + `MainActor.assumeIsolated`).
  - Closure-based observers and timers capture `[weak self]`.
- **Types:** `final class` by default; `struct`/`enum` for plain values and logic, which keeps
  them testable (see `FacingController`, `PetSettings`).
- **No force-unwraps** outside tests, `fatalError` in `init(coder:)`, and URLs or colours that
  are compile-time constants.
- **Logging:** `Logger(subsystem: "com.erag.mypet", category: …)`. Never use `print` in app code.
- **Settings** go through `SettingsStore` (`update { }` / `binding(\.path)`). Never write
  UserDefaults directly elsewhere. Adding one follows the `mypet-add-setting` skill.
- **Naming:** people see **MyPet** (`MyPet.app`, menus, alerts); use `AppInfo.name` and
  `AppInfo.tagline` instead of repeating the string. Identifiers stay lowercase and must not
  change, or settings and updates break: bundle ID `com.erag.mypet`, the defaults domain, the log
  subsystem, the repo and URLs, the `macos/mypet/` folder and the Swift module `mypet`.
- **New files:** after adding or removing a Swift file, run `cd macos && xcodegen generate` so
  `mypet.xcodeproj` stays in sync. SwiftPM picks files up automatically.
- **Tests** are XCTest in `macos/Tests/mypetTests`. They can't run with the CLT; verify pure
  logic with a `swiftc` harness in the scratchpad, and say which method you used.
- `cd macos && swift build` must finish with zero warnings (the linker's
  `search path … not found` and `libswiftCompatibilityPacks` messages are known and harmless).
