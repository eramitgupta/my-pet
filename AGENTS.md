# AGENTS.md — MyPet

Instructions for AI coding agents (Codex, Cursor, GitHub Copilot, Gemini CLI, Claude Code, …)
working in this repository. This file is the shared source of truth. `CLAUDE.md` and
`GEMINI.md` import it.

## Project

MyPet is a native macOS menu-bar app with a pixel-art pet whose colour follows memory usage
or pressure and whose speed follows CPU. Tagline: *Your Mac's Little Companion.*

- **Stack:** Rust core (`rust/pet-core`, static library, C ABI) + Swift (SwiftUI settings and
  popover, AppKit menu bar, Core Animation rendering). macOS 13+, universal arm64 + x86_64.
- **Identity:** display name **MyPet** (`MyPet.app`); identifiers stay lowercase: bundle ID `com.erag.mypet`, repo
  `github.com/eramitgupta/my-pet`, maintainer [@eramitgupta](https://github.com/eramitgupta), MIT.
- **Scope:** menu-bar pet only. The desktop-overlay pet was removed on purpose; don't
  reintroduce it unless asked.
- **Deeper docs:** `GUIDELINES.md` (architecture, FFI contract, budgets), `docs/METRICS.md`
  (exact formulas), `docs/PERFORMANCE.md` (measurements), `CONTRIBUTING.md`.

## Layout

| Path | Contents |
|---|---|
| `rust/pet-core/src/` | `monitoring/` (CPU, memory, pressure), `engine/` (gradient, animation), `ffi.rs`, `sys.rs` |
| `include/pet_core.h` | hand-written C header for the Rust library |
| `tests/` | Rust integration tests (FFI round trip, header layout, no-alloc tick, live sampling) |
| `macos/mypet/` | Swift app: `App/`, `MenuBar/`, `Animation/`, `Settings/`, `Bridge/`, `Assets/` |
| `macos/Tests/mypetTests/` | XCTest suite |
| `macos/project.yml` | XcodeGen spec → `macos/mypet.xcodeproj` (generated) |
| `scripts/` | build, DMG, notarisation, sprite and icon generators |

## Commands

```bash
export PATH=/opt/homebrew/opt/rustup/bin:$PATH        # rustup is keg-only (Homebrew)
cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test --all-targets
scripts/build-rust.sh debug                            # universal libpet_core.a
(cd macos && swift build)                              # quick Swift compile check
MYPET_ARCHS=arm64 scripts/build-app.sh release         # fast app → build/MyPet.app
scripts/build-app.sh release && scripts/make-dmg.sh    # universal app + DMG
pkill -f MyPet.app/Contents/MacOS/MyPet; open build/MyPet.app
(cd macos && xcodegen generate)                        # after adding/removing Swift files
```

Before you call work done: fmt, clippy and `cargo test` pass; `swift build` has zero warnings;
the app builds and launches.

## Environment facts

- Often only the Xcode **Command Line Tools** are installed: no `xcodebuild`, XCTest or
  Instruments. Swift tests run in Xcode or CI. Don't claim they passed if they didn't run.
- On the macOS 27 SDK, SwiftUI's `@State` is a macro the CLT can't expand. Write
  `private let x = State(initialValue: …)` and use `x.wrappedValue` / `x.projectedValue`.
- Agents usually can't see the screen. Verify the process, logs (`log show --predicate
  'subsystem == "com.erag.mypet"'`) and CPU, then ask a human to confirm visuals.

## Non-negotiables

1. **Minimal dependencies.** The Rust core has no crates. The one Swift package is Sparkle 2,
   for signed updates (docs/UPDATES.md). Don't add others.
2. **Cheap to run.** Stay under 1.5 % CPU while animating, ≈ 0 % paused and under 40 MB
   footprint. Never set `NSStatusItem.button.image` per frame; animate a `CALayer`. Ticks run
   at sprite fps with 20 % timer tolerance, never at display rate. Battery and visibility rules
   (stop when hidden or asleep, fps caps on battery and in Low Power Mode, idle sampling) live
   only in `EnergyPolicy`.
3. **Safe boundary.** C-compatible `#[repr(C)]` types only. Every export null-checks its
   pointers, catches panics and returns `PetStatus`. An ABI change updates Rust, the header,
   `tests/header_check.rs` and `RustBridge.swift` together, with a bumped `ABI_VERSION`.
4. **Threading.** Rust spawns no threads. The metrics engine is used only on Swift's monitor
   queue and pet actors only on the main thread.
5. **Tests with behaviour.** Engine logic lives in Rust with unit tests: exact values,
   thresholds, continuity, garbage input.
6. **Native UI.** SwiftUI `Form`/standard controls, semantic colours (light and dark mode),
   accessibility labels. No web-style UI.
7. **Honest reporting.** Say what was verified and how, and what wasn't.

## Area rules (read the matching file before editing that area)

| Before editing… | Read |
|---|---|
| `rust/**`, `tests/**`, `Cargo.toml` | `.agents/rules/rust.md` |
| `ffi.rs`, `include/*.h`, `macos/mypet/Bridge/**` | `.agents/rules/ffi.md` |
| any `*.swift` | `.agents/rules/swift.md` |
| `macos/mypet/Settings/**`, `MenuBar/*View.swift` | `.agents/rules/swiftui.md` |
| `macos/mypet/{App,Animation}/**`, `MenuBarController.swift`, `MonitorService.swift` | `.agents/rules/appkit.md` |
| `scripts/**`, `.github/**`, `project.yml`, `Package.swift` | `.agents/rules/build-scripts.md` |

## Available skills

Step-by-step workflows in `.agents/skills/<name>/SKILL.md`. Open the one that matches the task.

| Skill | Use it to |
|---|---|
| `mypet-build-run` | build, launch, restart, read logs, inject settings for testing |
| `mypet-rust-engine` | change metrics, gradient, speed or frame stepping in Rust, with tests |
| `mypet-ffi-change` | change anything that crosses the Rust ↔ Swift boundary |
| `mypet-add-setting` | add a user preference end-to-end (model → UI → live apply → tests) |
| `mypet-appkit-menubar` | menu-bar rendering, popover, timers, power handling |
| `mypet-add-pet` | add or redesign a pet (sprites, tint masks, manifest) |
| `mypet-perf-check` | measure CPU and memory, find hot paths |
| `mypet-release` | version bump, CHANGELOG, DMG, signing and notarisation, Sparkle appcast, tagging |

## Conventions

- Commits: short imperative summary (`Add owl pet`, `Fix colour flicker on wake`), one change
  per PR, fill in `.github/pull_request_template.md`.
- Comments explain *why*, not *what*. User-facing name strings come from `AppInfo`; URLs come
  from `ProjectLinks`.
- Never commit secrets. Signing credentials come only from the environment or a keychain
  profile.
