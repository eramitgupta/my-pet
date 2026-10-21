---
name: mypet-build-run
description: Build, launch, restart and debug the MyPet menu-bar app (Rust core + SwiftUI/AppKit). Use this whenever the user wants to run, test-drive, rebuild, relaunch or "see" MyPet, check that a code change works in the real app, read its logs, or reset its settings — even if they just say "chala ke dikhao", "run it", "app kholo" or "did it work?".
---

# Build & run MyPet

MyPet builds with only the Xcode Command Line Tools: `scripts/build-app.sh` builds the
universal Rust library, compiles the Swift app with SwiftPM, assembles `build/MyPet.app` and
ad-hoc signs it. Run everything from the repo root (`mypet/`).

## Environment gotchas

- `rustup` comes from Homebrew and is keg-only, so `cargo` is often missing from `PATH`.
  Prefix Rust commands with `export PATH=/opt/homebrew/opt/rustup/bin:$PATH`. The build scripts
  already search there.
- With no full Xcode installed, `xcodebuild`, XCTest (`swift test`) and Instruments are
  unavailable. Do not report Swift tests as passed unless they actually ran (Xcode or CI).
- On the macOS 27 SDK, `@State` is a macro whose plugin only ships with Xcode. Using it breaks
  the CLT build with "external macro implementation type 'SwiftUIMacros.StateMacro' could not
  be found". Use `private let x = State(initialValue: …)` with `x.wrappedValue` and
  `x.projectedValue` instead (see GUIDELINES.md §8.2).

## Build

| Goal | Command |
|---|---|
| Quick check that Swift compiles | `cd macos && swift build` (needs `scripts/build-rust.sh debug` once first) |
| Fast app for this Mac | `MYPET_ARCHS=arm64 scripts/build-app.sh release` |
| Universal release app | `scripts/build-app.sh release` |
| Rust only | `scripts/build-rust.sh release` |

A clean Swift build prints `Build complete!`. The `ld: warning: search path … not found` and
`libswiftCompatibilityPacks.a … missing arch 'x86_64'` warnings are harmless, so filter them out
when you show output.

## Launch / restart

Only one instance should run, because two would show two menu-bar pets:

```bash
pkill -f MyPet.app/Contents/MacOS/MyPet; open build/MyPet.app
```

Then confirm that it is running: `pgrep -lf MyPet.app`. MyPet is a menu-bar app
(LSUIElement): it has no Dock icon until Settings opens. You can't see the menu bar yourself
(`screencapture` lacks permission), so ask the user to look, or verify indirectly through the
process and the logs.

## Logs and crashes

```bash
log show --last 5m --info --predicate 'subsystem == "com.erag.mypet"' --style compact
```

Categories: `app` (startup, fatal errors) and `sprites` (pet loading, skipped pets). For a
crash, check `~/Library/Logs/DiagnosticReports/MyPet-*.ips`.

## Driving it with specific settings

Settings live as JSON in UserDefaults (`com.erag.mypet`, key `settings.v1`). Missing keys
fall back to defaults, so you only need the keys you care about:

```bash
HEX=$(printf '%s' '{"paused":true,"memoryMode":"pressure"}' | xxd -p | tr -d '\n')
defaults write com.erag.mypet settings.v1 -data "$HEX"
```

Keys: `menuBar` {`petID`, `cpuDrivenSpeed`, `manualSpeed`}, `gradientEnabled`,
`gradientColors` [{r,g,b}×4], `thresholds` [3], `memoryMode` (`usage`|`pressure`), `paused`,
`batterySaver`, `samplingInterval`, `lowCPUMenuBar`. Run `defaults delete com.erag.mypet
settings.v1` afterwards to restore the user's defaults, unless they asked for the change to stay.

## Updates (Sparkle)

- Builds without `SPARKLE_PUBLIC_KEY` (the default until `scripts/sparkle-keys.sh` has run) don't
  start the updater, and *Check for Updates…* shows a "not available in this build" alert. That
  is expected.
- Test the real update flow offline with `scripts/test-updates.sh`. It deletes `build/MyPet.app`
  afterwards, because those builds carry a throwaway key, so rebuild before launching.
- `MYPET_FEED_URL=http://127.0.0.1:8765/appcast.xml` points a build at a test feed. The update
  window will appear on the user's screen, so warn them first. Afterwards, remove the test's
  `SU*` keys from `com.erag.mypet` defaults.
- Any app copy you *launch* from a temp folder gets registered with LaunchServices, and shows up
  as a second "MyPet" in Spotlight even after the folder is deleted. Unregister it with
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <path>.app`
  and check with `lsregister -dump | grep -i 'path:.*mypet'`.
- Never trigger SwiftPM network resolution casually: Sparkle comes from GitHub, and git's
  credential helper can pop up a password prompt. The build scripts already disable that.

## Before saying "done"

When the change touched Rust, run `cargo test --all-targets` and
`cargo clippy --all-targets -- -D warnings`. Rebuild the app, relaunch it, and confirm that the
process stays up. Report what you verified and what you could not verify (visuals, XCTest).
