---
paths:
  - "macos/mypet/App/**/*.swift"
  - "macos/mypet/MenuBar/MenuBarController.swift"
  - "macos/mypet/Animation/**/*.swift"
  - "macos/mypet/Bridge/MonitorService.swift"
---

# AppKit & Core Animation rules

MyPet runs all day in the menu bar, so idle cost matters more than anything else here.
The budget is < 1.5 % CPU animating and ≈ 0 % paused (measured: ~1 % and 0.03 %).

- **Never set `NSStatusItem.button.image` per frame.** It redraws the button and re-snapshots
  every menu bar (8–14 % CPU). Animate the `petLayer` contents instead, re-set the placeholder
  image at most every 3 s for replicants, and keep the `lowCPUMenuBar` fallback.
- **Layers that change per frame** disable implicit actions (`layer.actions = [key: NSNull()]`
  or `CATransaction.setDisableActions(true)`). Position them with bounds and position when a
  transform is applied, round to whole points, set `contentsScale` from the backing scale, and
  use `magnificationFilter = .nearest` so pixel art stays crisp.
- **Timers:** use `FrameTicker` only (a `Timer` in `.common` mode with 20 % tolerance) at
  sprite fps × speed. Never tick at display refresh rate or busy-loop. Change rates through
  `run(interval:)`, which skips no-op restarts.
- **Energy rules live only in `App/EnergyPolicy.swift`** (pure, tested). It stops animation when
  nothing is visible (paused, asleep, locked, displays off, or the menu bar hidden by full screen
  or auto-hide, detected from status-item window occlusion), samples every 15 s when nothing
  shows numbers, and caps fps on battery (8) and in Low Power Mode (5). Feed it new inputs; don't
  scatter `if onBattery` checks elsewhere.
- **Wakeups matter more than CPU % for battery.** Keep the frame timer tolerance at 20 % so macOS
  can coalesce it, and measure idle wakeups (`top -stats pid,cpu,idlew,power`) after timer
  changes. `MYPET_SIMULATE_POWER=battery|lowpower` simulates power states on a Mac without a
  battery.
- **Sampling** is one `DispatchSourceTimer` with leeway on a `.utility` serial queue, plus the
  memory-pressure source. Don't add a second sampler: every consumer reads `MetricsStore` or
  receives `deliver(_:)`.
- **Images:** decode sprite sheets once into bitmaps (`SpriteLibrary.decode`). Tinted frames
  come from `TintRenderer`'s cache. Never create `NSImage`/`CGImage` objects per frame on the
  default path.
- **Activation policy:** the app is `.accessory` (LSUIElement). Switch to `.regular` only while
  a window such as Settings is open, and back on close.
- **Windows and panels** must not steal focus unexpectedly. Activate the app only in response
  to an explicit user action (opening Settings or the popover).
- **Notifications and observers** (NSWorkspace, distributed, IOPS run-loop source) are removed
  in `deinit`. C callbacks get context via `Unmanaged.passUnretained`.
- A rendering or timer change needs a before/after CPU measurement (the `mypet-perf-check`
  skill). Report the numbers.
