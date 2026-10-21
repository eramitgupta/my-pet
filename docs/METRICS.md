# How MyPet measures your Mac

All metrics are sampled by the Rust core (`rust/pet-core/src/monitoring`) on one background
queue, every 1.5 s by default (Settings → General → *Sample every*, 1–5 s; at least 3 s on
battery with Battery saver on).

## CPU usage

Source: `host_statistics(HOST_CPU_LOAD_INFO)` — cumulative tick counters for all cores.

```
cpu% = 100 × Δ(user + system + nice) / Δ(user + system + nice + idle)
```

- Deltas between consecutive samples; counters are 32-bit and wrap, so subtraction wraps.
- The very first sample only primes the baseline and reports 0 %.
- Before it drives the pet's speed, CPU is smoothed with an exponential moving average
  (α = 0.4) so a one-second spike doesn't make the pet sprint.

| Smoothed CPU | Pet speed |
|---|---|
| below 25 % | 0.6× (strolls) |
| 25–65 % | 1.0× |
| above 65 % | 1.8× (sprints) |

Transitions are blended over ±5 points around 25 % and 65 % (smoothstep), so speed never snaps.

## RAM usage (default colour mode)

Sources: `host_statistics64(HOST_VM_INFO64)`, `sysctl hw.memsize`, `host_page_size`.

```
free         = free_count − speculative_count        (speculative pages are already file-backed)
cached_files = external_page_count + purgeable_count
used         = hw.memsize − (free + cached_files) × page_size
ram%         = used / hw.memsize × 100
```

This matches the **Memory Used** headline in Activity Monitor (Memory tab → bottom panel).
On current macOS that headline is *larger* than App Memory + Wired + Compressed, the breakdown
listed next to it. For example, an 8 GB Mac showed Memory Used 6.97 GB while the breakdown
added up to 6.48 GB. MyPet follows the headline, because that's the number people compare with.
Activity Monitor uses binary units (1 GB = 1024³ bytes), and so does MyPet's popover.

RAM usage measures *occupancy*. macOS deliberately fills RAM with caches and compressed data,
so a high figure is often perfectly healthy.

## Memory pressure (alternative colour mode)

Pressure measures *stress*: is the system struggling to find free memory? macOS publishes only
three discrete levels, so MyPet combines the kernel's level with VM statistics:

- `L` — kernel level from `sysctl kern.memorystatus_vm_pressure_level` (1 normal, 2 warning,
  4 critical). A `DispatchSource.makeMemoryPressureSource` handler also forwards level changes
  to the engine and triggers an immediate resample, so changes show up without waiting for the
  next timer tick.
- `available = (free + inactive + purgeable) / total_pages` — pages obtainable without
  compressing or swapping.
- `compressed = compressor_pages / total_pages`
- `swap = vm.swapusage.used / vm.swapusage.total` (0 if no swap file)

```
strain = clamp(0.45·(1 − available) + 0.35·min(compressed / 0.35, 1) + 0.20·swap, 0, 1)

level      band       score
normal     0 – 55     0  + 55 · strain
warning    60 – 80    60 + 20 · strain
critical   85 – 100   85 + 15 · strain
```

The kernel level decides the band, so the score can never contradict macOS (a "normal"
system never shows red with the default thresholds); strain positions the score within its
band. This is an **estimate** — there is no public numeric pressure API.

## Colour

The score (RAM % or pressure score, 0–100) is mapped through four user-configurable colours
and three thresholds (defaults: green ≤ 35, yellow ≤ 60, orange ≤ 80, red above). Each band is
solid in its middle and blends over ±5 points around each threshold. Interpolation happens in
the OKLab colour space; the displayed colour then eases toward the target with a 1.2 s time
constant, independent of frame rate, so it never flickers or jumps.
