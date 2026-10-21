---
name: mypet-perf-check
description: Measure and investigate MyPet's CPU, memory and wakeup cost, and find what makes it slow. Use whenever the user asks how heavy MyPet is, says it uses too much CPU/battery/RAM, wants to verify a performance change, or after any change to rendering, timers, sampling or the menu-bar status item ("CPU kitna le raha hai", "battery drain", "is it lightweight?").
---

# MyPet performance check

Budget (GUIDELINES.md §9): **< 1.5 % CPU** while animating, **≈ 0 %** when paused, **< 40 MB**
physical footprint (not RSS, which also counts shared system pages). Baseline on an M2 with macOS 27: 0.8–1.7 % animating, 0.03 % paused, 17–37 MB.

## Measure

Use cumulative CPU time, not `top` snapshots. `top` readings on this machine swing between
1 % and 15 % from one sample to the next. The bundled script launches the release app with
given settings, skips warm-up, and reports average CPU from `ps` time deltas:

```bash
.claude/skills/mypet-perf-check/scripts/measure.sh "label" '{"json":"settings"}' 30
```

A typical matrix (build first with `MYPET_ARCHS=arm64 scripts/build-app.sh release`):

```bash
S=.claude/skills/mypet-perf-check/scripts/measure.sh
$S "default (cpu-driven)" '{}' 30
$S "manual 1x" '{"menuBar":{"petID":"cat","cpuDrivenSpeed":false,"manualSpeed":1}}' 30
$S "paused" '{"paused":true}' 30
$S "compat rendering" '{"lowCPUMenuBar":false}' 30
```

The script restores the user's settings when it finishes. Keep these traps in mind:
- The **first launch after a fresh build** is expensive for ~30 s while font and SF Symbol
  caches warm up. Run a throwaway launch first, or discard the first reading.
- Faster pets cost more because they produce more frames per second. Compare runs at equal
  speed by using manual speed.
- The user's own activity (opening the popover or Settings) shows up in the numbers.

## Energy (battery drain)

On battery, idle **wakeups** cost more than CPU %. Measure them together with Activity
Monitor's Energy Impact:

```bash
top -l 15 -s 3 -pid "$(pgrep -f MyPet.app/Contents/MacOS/MyPet)" -stats pid,cpu,idlew,power
```

Simulate power states on a Mac without a battery by launching with
`MYPET_SIMULATE_POWER=battery` (8 fps cap) or `MYPET_SIMULATE_POWER=lowpower` (5 fps cap). Also
check that MyPet never holds a sleep assertion: `pmset -g assertions | grep MyPet` should print
nothing. Baseline: about 4.5–6.6 idle wakeups/s and Energy Impact ≈ 0.65 while animating on AC,
and about 0–1 /s when paused. Wakeups are noisy, so run each scenario twice with 15 samples.
The energy rules live in `App/EnergyPolicy.swift`.

## Investigate

```bash
sample $(pgrep -f MyPet.app/Contents/MacOS/MyPet) 10 -file /tmp/mypet.sample
```

Read the main-thread call graph. Lines of the form `N mach_msg2_trap` are idle time; the work
sits in `__CFRunLoopDoTimers` (our `FrameTicker` → `MenuBarController.tick`) and in
`__CFRunLoopDoObservers` (Core Animation commit). Known hot spots and their fixes:

| Symptom in the sample | Cause | Fix |
|---|---|---|
| `-[NSStatusItem _updateReplicant…]`, `_redrawReplicantSnapshot` | `button.image` set every frame | low-CPU layer path (`lowCPUMenuBar`), placeholder refreshed every 3 s |
| `PNGReadPlugin`, `IIO_Reader` under `TintRenderer.render` | crops of a file-backed CGImage get decoded again | decode sheets into a bitmap once (`SpriteLibrary.decode`) |
| Many `TintRenderer.render` calls | cache misses during colour transitions | expected briefly. If constant, check the colour quantisation key |
| A timer firing faster than the frame rate | interval not tied to `spriteInterval` | `FrameTicker.run(interval:)` with the sprite fps × speed |

Most samples showing idle while `ps` still shows high CPU means the time is in the kernel or
the window server on our behalf. That is usually status-item redraw traffic, so compare the
`lowCPUMenuBar` on and off runs.

With full Xcode available, use Instruments as well: Time Profiler, Allocations + Leaks (no
growth over a few minutes) and Energy Log.

## Report

Give a table with each scenario, its CPU %, and memory footprint, plus the machine, the macOS version and
the load conditions (`sysctl -n machdep.cpu.brand_string`, `sw_vers`). State the method (ps
deltas, sample, or Instruments). When the change is significant, update `docs/PERFORMANCE.md`.
