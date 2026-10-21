# MyPet — Engineering Guidelines

This is the reference for building MyPet: a native macOS menu-bar app (Rust core +
SwiftUI/AppKit shell) with an animated pet that reacts to live CPU and memory conditions.
Read it before writing code. When code and this document disagree, fix one of them in the
same change.

> **Scope change (2026-10-21):** the desktop-overlay pet was removed at the product owner's
> request. MyPet is menu-bar only. The Rust behaviour/movement modules and their FFI
> (`set_area`, `drag`, `poke`) were deleted in ABI v2 as dead code.

---

## 1. Non-negotiables

| Rule | Why |
|---|---|
| Native only: Rust + Swift + AppKit + SwiftUI + Core Animation. No Electron, Tauri, web views, React. | Small footprint, native feel. |
| **Zero third-party Rust crates** in `pet-core`. Mach/sysctl calls are declared by hand in `sys.rs`. | Smaller audit surface, nothing to drift. |
| **One third-party Swift package: Sparkle 2** (updates only), pinned in `macos/Package.resolved`. Nothing else. | Updates must be signed and verified; Sparkle is the audited standard, and writing our own would be riskier. |
| macOS 13+ deployment target, universal binary (arm64 + x86_64). | Spec target. |
| One monitoring engine, sampled on one background queue, shared by every consumer (menu-bar pet, previews, stats UI). | No duplicated sampling. |
| Real assets only. Every pet ships complete sprite strips + tint masks for all 5 animations. | First release must look finished. |
| Local development works without Apple signing credentials (ad-hoc signing). | Anyone can clone and run. |
| Every change ends with a green build and green tests. | No "fix it later" piles. |

---

## 2. Repository layout

```
mypet/
├── Cargo.toml                    # Rust workspace
├── rust/pet-core/src/
│   ├── lib.rs, sys.rs            # sys.rs: hand-written Mach/sysctl declarations
│   ├── monitoring/{mod,cpu,memory}.rs
│   ├── engine/{mod,gradient,animation}.rs
│   └── ffi.rs                    # the only module with `extern "C"` exports
├── include/pet_core.h            # C header, hand-written, layout-checked by a test
├── tests/                        # Rust integration tests (FFI, header layout, no-alloc, live)
├── macos/
│   ├── Package.swift             # SwiftPM build (works with Command Line Tools only)
│   ├── project.yml → mypet.xcodeproj   # XcodeGen spec and generated project
│   ├── CPetCore/module.modulemap # exposes pet_core.h to Swift
│   ├── mypet/{App,MenuBar,Animation,Settings,Bridge,Assets}
│   └── Tests/mypetTests         # XCTest (needs full Xcode)
├── scripts/                      # build-rust, build-app, make-dmg, notarize, generators
├── docs/                         # METRICS.md, PERFORMANCE.md, pets-preview.png
└── .github/workflows/            # ci.yml, release.yml
```

---

## 3. Architecture

```
 Swift main thread                                          Swift "monitor" queue (.utility)
 ─────────────────                                          ────────────────────────────────
 AppDelegate ── SettingsStore (UserDefaults, debounced)     DispatchSourceTimer (1–5 s)
     │               │                                      DispatchSource memoryPressure
     ├─ MenuBarController ── SpriteAnimator ── TintRenderer        │
     │      NSStatusItem + CALayer      │                          ▼
     ├─ SettingsWindowController       PetActorHandle ◄──── MetricsEngine.sample()
     │      SwiftUI panes + previews ───┘       ▲                  │
     └─ MetricsStore (@Published, UI only) ◄────┴──── main.async ──┘
                                        │ C ABI
                    Rust pet-core: monitoring::{cpu,memory} · engine::{gradient,animation,
                                   ffi}
```

### 3.1 Responsibility split

| Concern | Owner |
|---|---|
| Metric sampling (CPU ticks, VM stats, swap, kernel pressure level) | Rust `monitoring` |
| RAM-usage % and pressure score | Rust `monitoring::memory` |
| Colour ramp (OKLab) + smoothing | Rust `engine::gradient` |
| CPU → speed mapping, frame stepping | Rust `engine::animation` |
| Pet state (fixed `run` in the menu bar) | Rust `engine` (`Actor`) |
| Status item, popover, settings UI, rendering, persistence, timers | Swift |

### 3.2 Threading rules

1. Rust spawns no threads and holds no global mutable state; state lives in opaque handles.
2. `MetricsEngine` (`PetEngine *`) is used **only** on the monitor serial queue.
3. `PetActorHandle`s (`PetActor *`) are used **only** on the main thread.
4. Only plain-value `PetMetrics` structs cross from the monitor queue to main.
5. Animation uses one `FrameTicker` (a `Timer` in `.common` mode) per visible pet, ticking at
   sprite fps × speed (≈ 7–22 Hz), never at display refresh rate. Timers are invalidated when
   paused, asleep, the screen is locked or the displays sleep.

---

## 4. Rust ↔ Swift FFI contract

- C ABI only, `#[repr(C)]` structs of plain scalars; no strings or Rust collections cross.
- Opaque handles created by `*_new`, released by `*_free`; `*_free(NULL)` is a no-op. Swift
  wraps each in a `final class` that frees in `deinit`.
- Every export null-checks its pointers, runs inside `catch_unwind`, and returns `PetStatus`
  (`PET_OK`, `PET_ERR_NULL`, `PET_ERR_SYS`, `PET_ERR_PANIC`, `PET_ERR_INVALID`).
- Out-pointers are caller-owned; Rust writes them only on `PET_OK` and never retains them.
- A handle must not be used from two threads at once; distinct handles are independent.
- `pet_core_abi_version()` must equal `PET_CORE_ABI_VERSION`; the app refuses to start
  otherwise. Changing a struct = bump `ABI_VERSION`, update the header and `RustBridge.swift`
  in one commit. `tests/header_check.rs` compiles a C probe and compares every size/offset.

Surface: `pet_engine_{new,free,sample,note_pressure_event}`,
`pet_actor_{new,free,configure,set_gradient,set_bands,update_metrics,tick}`,
`pet_gradient_sample_bands` (stateless, for UI previews). See `include/pet_core.h`.

---

## 5. Metrics — exact definitions (also in docs/METRICS.md)

- **CPU %** — `HOST_CPU_LOAD_INFO` tick deltas: `100 × Δ(user+system+nice) / Δ(all)`. 32-bit
  counters wrap; first sample primes the baseline. EMA (α = 0.4) before driving speed.
- **RAM usage %** — the *Memory Used* headline in Activity Monitor:
  `hw.memsize − (free − speculative + external + purgeable) × page_size`, over `hw.memsize`.
  This is larger than App + Wired + Compressed on current macOS; see docs/METRICS.md.
- **Memory pressure score** — kernel level `L` from `kern.memorystatus_vm_pressure_level`
  (also pushed immediately by a Dispatch memory-pressure source) chooses the band
  (normal 0–55, warn 60–80, critical 85–100); measured strain
  `0.45·(1−available) + 0.35·min(compressed/0.35, 1) + 0.20·swap` places it inside the band.
- RAM usage is occupancy, pressure is stress. Never present one as the other.
- Sampling: 1.5 s default (1–5 s); ≥ 3 s on battery with Battery saver; ≥ 5 s in Low Power
  Mode; 15 s while the pet is static and no UI shows numbers; 10 % timer leeway; stopped on
  sleep/lock, immediate sample on resume. All of this is decided in `EnergyPolicy`.

---

## 6. Gradient & tinting

- Four user colours + three thresholds (defaults 35/60/80 → green/yellow/orange/red).
  `Gradient::from_bands` makes each band solid with a ±5-point blend centred on each
  threshold (narrowed automatically for tight bands). Interpolation in **OKLab**.
- Smoothing: `c += (target − c)(1 − e^(−dt/τ))`, τ = 1.2 s — frame-rate independent, no jumps.
- Sprites have neutral-grey tintable bodies plus untinted details (outline, eyes, noses).
  Each strip ships a grayscale `_mask.png`. `TintRenderer` multiplies the colour into masked
  pixels and restores the original alpha. Results are cached per (pet, animation, frame,
  colour quantised to 7 bits/channel), capped at 512 images.
- Gradient off ⇒ the pet uses its manifest `baseColor` (natural colours).

---

## 7. Animation & assets

- Pet folder: `manifest.json` + `{idle,walk,run,jump,sleep}.png` horizontal strips + optional
  `*_mask.png`. Bundled pets: cat, dog, fox, rabbit, dinosaur, panda (32×32 frames), generated
  by `scripts/generate-sprites.swift`; PNGs are committed.
- Extra pets can be dropped into `~/Library/Application Support/MyPet/Pets` (same format) —
  no rebuild needed; invalid manifests are logged and skipped.
- Sheets are decoded once into in-memory bitmaps (crops of file-backed images would re-run
  the PNG decoder on every draw) and sliced into shared-pixel crops.
- Direction (`PetFacing`: right / left / turn around): sprites are drawn facing right and
  mirrored with a layer transform (`CATransform3DMakeScale(-1, 1, 1)`, actions disabled) or a
  flipped draw in the compatibility path. `FacingController` turns the pet every 6–14 s in
  turn-around mode. It is pure Swift with no FFI change, and is shared by the menu bar and previews.
- Speed: CPU-driven `<25 % → 0.6×`, `25–65 % → 1.0×`, `>65 % → 1.8×` (smoothstep-blended ±5
  points), or a manual 0.25–3× slider. Paused ⇒ static sleeping frame, no timer.

---

## 8. macOS shell

| Component | Responsibility |
|---|---|
| `AppDelegate` | Lifecycle, `.accessory` policy (Dock icon only while settings are open), applies settings + power state. |
| `MonitorService` / `MetricsEngine` | Monitor queue, timer, memory-pressure source; delivers `PetMetrics` to main. |
| `MetricsStore` | `@Published` latest sample — the only thing SwiftUI stats views observe. |
| `SettingsStore` | Versioned (`settings.v1`) JSON in UserDefaults, tolerant decoding, 300 ms debounced writes, sanitised values. |
| `MenuBarController` | `NSStatusItem`, popover, low-CPU layer rendering (§8.1). |
| `SpriteLibrary` / `TintRenderer` / `SpriteAnimator` | Asset loading, tint cache, per-pet driver shared by menu bar and previews. |
| `PowerMonitor` | Battery/AC (IOPS notifications), Low Power Mode, sleep/wake, screen lock, display sleep. |
| `LoginItemManager` | `SMAppService.mainApp` register/unregister/status. |
| `SettingsWindowController` | NSWindow hosting the SwiftUI `NavigationSplitView` (Pets, Appearance, Behaviour, General, About). |

### 8.1 Menu-bar rendering (measured, see docs/PERFORMANCE.md)

Setting `NSStatusItem.button.image` every frame makes AppKit redraw the button and
re-snapshot it for every menu bar ("replicants"): ~8–14 % CPU on an M2. MyPet instead keeps a
transparent placeholder image (to reserve width) and swaps the contents of a `CALayer` added
to the button: ~0.8–1.4 %. The placeholder is re-set every 3 s so replicants on other displays
stay roughly current. Settings → General → *Low-CPU menu bar animation* falls back to the
image path if a future macOS stops showing layer content.

### 8.2 SDK note

On the macOS 27 SDK, SwiftUI's `@State` is a macro whose plugin ships only with full Xcode.
Views use `State` as a plain stored `DynamicProperty` (`private let x = State(initialValue:)`,
`x.wrappedValue`, `x.projectedValue`) so the Command Line Tools build keeps working.

---

## 9. Performance budget

| Scenario | Budget | Measured (M2, macOS 27) |
|---|---|---|
| Menu-bar pet animating | < 1.5 % CPU | 0.8–1.7 % |
| Paused | ≈ 0 % | 0.05 % |
| Idle wakeups while animating | as few as possible | 4.5–6.6 /s (Energy Impact ≈ 0.65) |
| Resident memory | < 40 MB | 17–37 MB |

Rules: decode once; no per-frame heap allocation in Rust (`tests/no_alloc_tick.rs`); tick at
sprite rate; no SwiftUI view receives per-frame updates; stop timers whenever nothing is
visible. Profile with Instruments (Time Profiler, Allocations, Leaks, Energy) when full Xcode is
available; otherwise `ps`/`top`/`sample` — and say which was used.

---

## 10. Testing

- Rust (`cargo test`, 53 tests): gradient stops/interpolation/thresholds/smoothing, memory
  formulas and pressure band transitions, CPU deltas/wraparound, speed mapping, frame stepping,
  jitter-proof frame stepping, FFI null/invalid/panic handling, C header layout,
  zero-allocation tick, live sampling sanity.
- Swift (`mypetTests`, XCTest — requires full Xcode or CI): settings round trip/migration/
  sanitising, manifest validation, every bundled pet loads, tinting preserves alpha and
  outlines, FFI wrappers.

---

## 11. Build & distribution

- `scripts/build-rust.sh [debug|release]` → universal `target/universal/<cfg>/libpet_core.a`.
- `scripts/build-app.sh [debug|release]` → `build/MyPet.app` via SwiftPM (CLT-only friendly),
  ad-hoc signed unless `MYPET_SIGN_IDENTITY` is set.
- `macos/mypet.xcodeproj` (generated from `project.yml` by XcodeGen) runs `build-rust.sh` as a
  pre-build phase; Debug/Release configurations.
- `scripts/make-dmg.sh` → `build/MyPet-<version>.dmg` (hdiutil, /Applications symlink).
- `scripts/notarize.sh` — needs `MYPET_SIGN_IDENTITY` (Developer ID Application) and either a
  `notarytool` keychain profile (`MYPET_NOTARY_PROFILE`) or `APPLE_ID` + `APPLE_TEAM_ID` +
  `APPLE_APP_PASSWORD`. Missing credentials ⇒ clear error; dev builds stay ad-hoc.
- GitHub Actions: `ci.yml` (fmt, clippy, cargo test, Xcode build + XCTest) and `release.yml`
  (tagged builds, optional signing/notarisation, DMG artifact).

---

## 11a. Updates (Sparkle 2)

- `App/UpdateController.swift` wraps `SPUStandardUpdaterController`. Sparkle provides all update
  UI (the update window with versions and release notes, "up to date", errors), the EdDSA
  verification, installation and relaunch. Entry points: the popover, the app menu, and
  Settings → General (automatic checks and automatic install toggles, Check Now).
- Info.plist: `SUFeedURL` and `SUPublicEDKey` come from `SPARKLE_FEED_URL` and
  `SPARKLE_PUBLIC_KEY` in `macos/project.yml`. Also set: `SURequireSignedFeed`,
  `SUVerifyUpdateBeforeExtraction`, `SUEnableAutomaticChecks` (daily), and
  `SUAutomaticallyUpdate` = false.
- A build without a public key doesn't start the updater, and "Check for Updates…" explains why.
- `CFBundleVersion` equals the release version. Sparkle compares it, so never reuse a version.
- Release pipeline and key handling: [docs/UPDATES.md](docs/UPDATES.md). End-to-end test:
  `scripts/test-updates.sh`, which uses the real Sparkle framework, works offline and runs in CI.

## 12. Known limitations

- macOS exposes only three memory-pressure levels; the numeric score is an estimate (§5).
- Launch at login via `SMAppService` works best from `/Applications`; ad-hoc builds may show
  "requires approval" in System Settings → Login Items.
- On notched MacBooks a crowded menu bar can hide status items behind the notch.
- Instruments, `xcodebuild`, XCTest and notarisation require full Xcode.

---

## 13. Code style

- Rust: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`; `unsafe` only in `sys.rs` and
  `ffi.rs`, each block with a `// SAFETY:` comment.
- Swift: Swift 5 language mode, `final class` by default, `@MainActor` on UI controllers, no
  force-unwraps outside tests and bundled-asset loading.
- Comments explain *why*, not *what*.
