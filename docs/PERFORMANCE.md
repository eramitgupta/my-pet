# Performance

## Results

Measured 2026-10-21 on a Mac mini (Apple M2, 8 GB RAM, macOS 27), release build, default
settings unless noted. The machine was under real load during the runs (≈ 30 % system CPU,
kernel memory-pressure level *warning*, ~5.8 GB swap in use), i.e. not an idle lab machine.

| Scenario | CPU (cumulative, 30–60 s) | Resident memory |
|---|---|---|
| Menu-bar pet, CPU-driven speed | **0.83 %** | 17–32 MB |
| Menu-bar pet, manual speed 1.0× | 1.26–1.40 % | 37 MB |
| Menu-bar pet, manual speed 1.75× | 1.70 % | — |
| Paused | **0.03 %** | 26 MB |
| *Compatibility* rendering (re-set `button.image` each frame) | 7.6–10 % | 20–29 MB |

CPU-driven speed is cheapest here because the pet slows down when the system is quiet
(fewer frames per second).

**After the optimisation pass (2026-10-21, ABI v2), same machine and method:**

| Scenario | CPU | Memory footprint |
|---|---|---|
| Default (CPU-driven) | 0.87 % | 20.8 MB |
| Manual speed 1.0× | 1.07 % (was 1.26–1.40 %) | 21.2 MB |
| Turn-around facing | 1.00 % | 22.1 MB |
| Paused | 0.05 % | 18.0 MB |

### Method

Instruments was not available on the build machine (Command Line Tools only, no Xcode), so
numbers come from the kernel's own accounting:

```bash
# cumulative CPU seconds of the process, sampled 5 s after launch and again N seconds later
ps -o time= -p <pid>     # (t2 − t1) / N × 100 = average CPU %
ps -o rss=  -p <pid>     # resident memory
sample <pid> 10          # call stacks, to locate hot paths
```

`top` snapshots were also taken but proved noisy; they are not used for the table. The first
launch after a fresh build is noticeably more expensive for ~30 s (font/SF Symbol cache
warm-up) and is excluded.

With full Xcode, profile with Instruments: *Time Profiler* (main-thread work per frame),
*Allocations* + *Leaks* (steady state should show no growth), *Energy Log* (wakeups).

## Energy (battery drain)

On a laptop, battery drain is driven less by CPU % than by **wakeups**: each time the CPU
leaves its idle state. The measurements use `top -stats pid,cpu,idlew,power` (idle wakeups/s
and Activity Monitor's *Energy Impact*). The test Mac has no battery, so battery and Low Power
Mode were simulated with the `MYPET_SIMULATE_POWER=battery|lowpower` launch variable. That
variable exercises the same code paths as the real power notifications.

| Scenario | Idle wakeups/s (before → after) | Energy impact (before → after) |
|---|---|---|
| Animating on AC | 28 → 4.5–6.6 | 0.76 → 0.62–0.67 |
| Paused | 3.7 → 0–1 | 0.01 → 0.00–0.01 |
| On battery (Battery saver: ≤ 8 fps, sampling ≥ 3 s) | — → 1.4–7.8 | — → 0.58–0.69 |
| Low Power Mode (≤ 5 fps, sampling ≥ 5 s) | — → 1.9–5.3 | — → 0.45–0.58 |

The menu bar never holds a power assertion, so it never keeps the Mac awake
(`pmset -g assertions`). The energy rules live in one place, `EnergyPolicy`:

- **Nothing visible, nothing animates:** paused, system asleep, screen locked, displays off,
  *or the menu bar hidden by a full-screen app or auto-hide* (detected from the status item
  window's occlusion state).
- **Idle sampling:** when the pet isn't animating and neither the popover nor Settings is
  open, metrics are sampled every 15 s instead of every 1.5 s.
- **Battery tiers:** on battery with Battery saver, the cap is 8 fps and sampling is at least
  3 s. Low Power Mode always applies, with a cap of 5 fps and sampling of at least 5 s.
- **Coalescing:** the frame timer has 20 % tolerance, so macOS can fire it together with other
  timers. The Rust frame stepping absorbs up to 70 % lateness without a skipped or doubled
  frame (tested at 30 %).
- **Settings window:** only the selected or hovered gallery card animates (it used to be 7
  timers), and previews stop when the window is hidden.

## What made the difference

1. **Layer-based menu-bar animation.** Profiling showed that setting
   `NSStatusItem.button.image` per frame triggers a full button redraw plus a re-snapshot for
   every menu bar ("replicants") — ~20 ms of main-thread work per frame. MyPet now reserves the
   status item's width with a transparent placeholder image and swaps the contents of a
   `CALayer` instead (≈ 10–15× cheaper). The placeholder is re-set every 3 s so other displays'
   menu bars stay current. The old path remains available as a fallback setting.
2. **Decode sprite sheets into bitmaps once.** Crops of a file-backed `CGImage` re-ran the PNG
   decoder each time a frame was tinted. Sheets are now decoded into in-memory bitmaps at load.
3. **Tick at sprite rate, not refresh rate.** The timer interval is `1 / (fps × speed)`
   (≈ 7–22 Hz) with 10 % tolerance, and the timer is removed entirely when paused, asleep,
   locked or when displays sleep.
4. **Cache tinted frames.** Keyed by (pet, animation, frame, colour at 7 bits/channel); during a
   colour transition only displayed frames are rendered.
5. **Zero-allocation Rust tick.** `tests/no_alloc_tick.rs` runs 10 000 ticks under a counting
   global allocator and asserts zero allocations.
6. **Jitter-proof frame stepping.** The host timer fires up to ~10 % late on any tick. With a
   strict "frame due at ≥ 1.0" rule, an early tick showed nothing and the next jumped two
   frames, a visible stutter. `Animator` now shows a frame once it is within 0.3 of due. A test
   models the timer grid and asserts exactly one new frame per tick over 2 000 ticks.
7. **No per-frame image allocation in the menu bar.** The pet's area is selected with
   `CALayer.contentsRect` (computed once per pet) instead of `CGImage.cropping` every frame.
8. **Popover built on demand.** Its SwiftUI tree is created when it opens and released when it
   closes, so a closed popover does no work on metric updates.
9. **Settings reach Rust only when changed.** The gradient and actor config are diffed before
   calling into Rust, and the frame timer ignores interval changes under 3 % (CPU-driven speed
   drifts slightly with every sample).
10. **One sampler, coalescable timer.** A single `DispatchSourceTimer` with 10 % leeway on a
   utility-QoS queue; SwiftUI views observe only the metrics store, never per-frame state.
