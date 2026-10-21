---
name: mypet-appkit-menubar
description: Change how MyPet renders and behaves in the macOS menu bar — NSStatusItem, the CALayer sprite path, the popover, frame timers, sleep/wake/battery handling, activation policy and windows. Use for any AppKit or Core Animation work, menu-bar visual bugs (frozen, blurry, flickering, wrong size or position, wrong direction), popover changes, or when CPU rises after a UI change, e.g. "menu bar mein pet bada karo", "pet blur dikh raha hai", "popover mein naya button".
---

# AppKit & menu-bar work

The menu bar is MyPet's whole UI surface and its biggest CPU risk. Profiling showed that the
obvious approach (`button.image = frame` each tick) costs 8–14 % CPU, while the current design
costs about 1 %. Keep that difference in mind for every change here, and read
`.claude/rules/appkit.md` first.

## How rendering works (`MenuBar/MenuBarController.swift`)

1. `FrameTicker` (a `Timer` in `.common` mode with 20 % tolerance) fires at
   `animator.spriteInterval`, which is sprite fps × speed (≈ 7–22 Hz). Never use display rate.
2. `SpriteAnimator.tick` → Rust actor → `TintRenderer` returns a cached, tinted `CGImage`.
3. `render(_:)`
   - **Low-CPU path (default):** the button keeps a transparent placeholder `NSImage` that
     reserves the item's width. The frame goes into `petLayer.contents` inside the button's
     layer, positioned with bounds and position (not frame) so the mirror transform flips
     around the centre. Implicit animations are disabled for contents, bounds, position and
     transform.
   - Every 3 s, `refreshReplicantsIfDue()` sets the placeholder again so menu bars on other
     displays (replicants) re-snapshot.
   - **Compatibility path** (`lowCPUMenuBar == false`): sets an `NSImage` drawn with
     interpolation off, and caches it by (CGImage identity, mirrored).
4. `render` returns early when the CGImage is unchanged, so set `shownImage = nil` to force a
   redraw after a visual setting changes.

## Making a change

- **Size or position:** `displaySize(for:)` sets the height (`min(18, thickness − 4)`). Keep
  `magnificationFilter = .nearest`, set `contentsScale` from the window's backing scale, and
  round positions to whole points. Otherwise the pixel art blurs.
- **New visual state** (badge, flash, overlay): add a sublayer next to `petLayer`. Don't
  re-render the button. Disable implicit actions on anything that changes per frame.
- **Popover:** SwiftUI in `MenuContentView`, hosted by `NSPopover(.transient)`. Keep it about
  290 pt wide, with native controls, and have it read the metrics only through `MetricsStore`.
- **Timers and power:** every timer must stop when `paused` or `PowerMonitor.isSuspended`
  (sleep, screen lock, display sleep) and must be throttled when constrained (battery saver:
  ≤ 8 fps, sampling ≥ 3 s). Start and stop them through `setRunning` / `apply`, never ad hoc.
- **Windows:** the app is `.accessory` (no Dock icon). `openSettings()` switches to `.regular`
  while Settings is open and back on close. New windows must follow the same pattern.
- **Paused state:** shows `animator.image(.sleep, frame: 0)` with no timer running.

## Verify (you can't see the menu bar yourself)

1. `cd macos && swift build` produces no warnings. Then rebuild and relaunch (see the
   `mypet-build-run` skill).
2. **Measure CPU before and after** with the `mypet-perf-check` skill, using both
   `lowCPUMenuBar` true and false. A rendering change that raises the default path above
   ~1.5 % is a regression, even if it looks fine.
3. `screencapture` fails without Screen Recording permission. Ask the user to look, and tell
   them exactly what to expect (for example "the cat should face left and turn every ~10 s").
4. When the menu bar looks frozen on some macOS version, the fallback is the
   `lowCPUMenuBar` setting; never remove it.
