---
paths:
  - "macos/**"
  - "rust/**"
  - "include/**"
  - "scripts/**"
---

# Project structure & test rules

Every file has one obvious home. A developer who knows what a file *does* should be able to
guess its folder without searching. When adding, moving or splitting files, follow this map.

## Where code goes

### Rust (`rust/pet-core/`)

| Folder | Holds | Never holds |
|---|---|---|
| `src/monitoring/` | reading the system (CPU, memory, pressure) through `sys.rs` | colour, animation, FFI |
| `src/engine/` | pure logic: gradient, speed, frame stepping, actors | syscalls, `extern "C"` |
| `src/sys.rs` | hand-written Mach/sysctl declarations | logic |
| `src/ffi.rs` | every `extern "C"` export and `#[repr(C)]` boundary type | logic beyond argument checks |
| `tests/` | integration tests that use the crate from outside (FFI, header, allocation, live) | unit tests |

### Swift (`macos/mypet/`, module `mypet`)

| Folder | Holds | Example |
|---|---|---|
| `App/` | entry point, app lifecycle, app-wide constants | `main.swift`, `AppDelegate`, `AppInfo` |
| `Bridge/` | the Swift wrapper over the C API. The only folder that calls `pet_*` | `RustBridge.swift` |
| `Models/` | plain values, `Codable` data, persistence, observable stores. No AppKit views | `PetSettings`, `SettingsStore`, `PetManifest`, `MetricsStore` |
| `Services/` | long-lived system integrations and policies: timers, notifications, Sparkle, login item | `MonitorService`, `PowerMonitor`, `EnergyPolicy`, `UpdateController` |
| `Animation/` | sprite loading, tinting, frame timing, facing, the shared sprite view | `SpriteLibrary`, `TintRenderer`, `FrameTicker` |
| `MenuBar/` | the status item controller and the popover's SwiftUI view | `MenuBarController`, `MenuContentView` |
| `Settings/` | the settings window controller and its SwiftUI views | `SettingsView`, `StatsViews` |
| `Resources/` | files copied into the bundle | `Assets.xcassets`, `AppIcon.icns`, `Pets/` |
| `Support/` | bundle configuration, not code | `Info.plist`, `mypet.entitlements` |

Deciding between folders:
- Can it be tested without a window or the real system? It is a **Model** (data) or a pure
  policy in **Services** (like `EnergyPolicy`).
- Does it observe or talk to macOS (IOKit, NSWorkspace, SMAppService, Sparkle)? **Services**.
- Does it draw pixels or advance frames? **Animation**.
- Is it a SwiftUI view or window? The feature folder it belongs to (**MenuBar** or **Settings**).
  A new feature with its own UI gets its own folder, named after the feature.
- Calls a C function? **Bridge**, and nowhere else.

Don't create a folder until it has two files that belong together. Don't create `Utils/`,
`Helpers/`, `Misc/` or `Common/`: name the folder after what the code does.

## File rules

- **One main type per file, named after it** (`SettingsStore` → `SettingsStore.swift`). Small
  private helpers and extensions used only by that type may share its file.
- **Split a file that passes ~400 lines** or holds unrelated types. Split along features (one
  view per file for large settings panes), not alphabetically.
- **Constants live with their owner.** App-wide names and URLs live only in `App/AppInfo.swift`
  (`AppInfo`, `ProjectLinks`).
- **Folder and module names are stable:** `macos/mypet/` and the module `mypet` never change
  (see `swift.md`). Restructure *inside* them.
- After adding, moving or removing a Swift file, run `cd macos && xcodegen generate`. SwiftPM
  needs no change, except when a non-code folder must be added to `exclude:` in `Package.swift`.
- When a path moves, update every reference in the same change: `Package.swift`, `project.yml`,
  `scripts/`, `.github/`, these rules, the skills, `AGENTS.md`, `GUIDELINES.md` and
  `CONTRIBUTING.md`. Check with `grep -rn "<old path>" --exclude-dir=target --exclude-dir=build .`

## Test rules

Every behaviour change ships with a test that fails without it. "Behaviour" means anything a
user could notice or a later change could silently break: values, thresholds, persistence,
validation, timing, file formats, the FFI contract.

### Where tests go

| Code | Test location | Style |
|---|---|---|
| Rust logic in `src/**` | `#[cfg(test)] mod tests` at the bottom of the same file | exact values, thresholds, continuity, garbage input (NaN, ∞, negatives, out of range) |
| Rust crossing the boundary | `rust/pet-core/tests/<topic>.rs` | through the public / `extern "C"` API only |
| Swift in `macos/mypet/<Folder>/X.swift` | `macos/Tests/mypetTests/<Folder>/XTests.swift` | XCTest, one `final class XTests` per file |
| Sparkle update flow | `macos/Tests/UpdateHarness/`, run by `scripts/test-updates.sh` | end to end against a local feed |

The Swift test tree **mirrors** the app tree: `Models/SettingsStore.swift` is tested in
`mypetTests/Models/SettingsTests.swift`, `Services/EnergyPolicy.swift` in
`mypetTests/Services/EnergyPolicyTests.swift`. Add the folder when you add its first test.

### What every test file needs

- Start with `import XCTest` and `@testable import mypet` (add `import CPetCore` when the test
  uses C types). Mark the class `@MainActor` when it touches main-actor types.
- Name tests after the behaviour, not the method: `testThresholdsStayOrdered`, not
  `testSanitize2`.
- Cover the normal case, the edges (empty, zero, maximum, exactly on a threshold) and bad input.
  Pure logic should be deterministic: no sleeps, no real clock, no network, no global
  `UserDefaults` (use a suite name and remove it in `tearDown`).
- Keep engine logic in Rust where it can be tested without a Mac UI. Swift tests cover the Swift
  layer: persistence, manifests, assets, tinting, policies and the FFI wrappers.

### Required checks before calling work done

- `cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test --all-targets`.
- `cd macos && swift build` with zero warnings.
- Swift tests need full Xcode (`xcodebuild test` or ⌘U). With only the Command Line Tools,
  check pure logic with a `swiftc` harness in the scratchpad and say that XCTest did not run.
- Release or update changes: `scripts/test-updates.sh`.
