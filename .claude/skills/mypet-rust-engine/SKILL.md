---
name: mypet-rust-engine
description: Change or extend MyPet's Rust core (rust/pet-core) — monitoring (CPU, memory, pressure, new system metrics via Mach/sysctl), the gradient/colour engine, animation speed or frame stepping — and test it properly. Use whenever a task touches .rs files, adds a new metric, changes how colour/speed/scores are computed, or needs a new macOS syscall, e.g. "pressure score ko tweak karo", "add GPU/battery/disk metric", "colour transition slow karo".
---

# Working on the Rust engine

`pet-core` is a zero-dependency static library. It samples the system and turns metrics into
what the pet looks like. Swift owns threads, timers and UI; Rust owns the numbers. Read
`.claude/rules/rust.md` for the always-on rules. This skill is the workflow.

## Where things go

| Change | File | Notes |
|---|---|---|
| New Mach/sysctl call | `src/sys.rs` | Declare it by hand: no `libc` or `mach2` crate. Mirror the SDK layout exactly (check `$(xcrun --show-sdk-path)/usr/include/...`). Add a size test. |
| New metric | `src/monitoring/*.rs` | Split a **pure function** (synthetic inputs → value) from the syscall wrapper so it can be unit-tested. |
| Colour logic | `src/engine/gradient.rs` | Interpolate in OKLab, smooth with `ColorSmoother` (frame-rate independent). |
| Speed / frames | `src/engine/animation.rs` | `cpu_speed` uses smoothstep blending, so speed never snaps. |
| Shown animation / config | `src/engine/mod.rs` (`Actor`, `ActorConfig`) | Small on purpose: colour, speed and the frame index. |
| Exposing to Swift | `src/ffi.rs` + header | Follow the `mypet-ffi-change` skill. |

## Adding a metric (pattern used by RAM usage and pressure)

1. In `sys.rs`, add the raw call returning `Option<T>` (`None` on any failure; never panic).
2. In `monitoring/<area>.rs`, add a plain-data snapshot struct, a pure scoring function, and a
   small monitor struct that calls `sys` and the scoring function.
3. Add the field to `monitoring::Metrics` (`#[repr(C)]`) and fill it in `Monitor::sample`.
   This changes the ABI, so continue with the `mypet-ffi-change` skill.
4. Document the exact formula in `docs/METRICS.md`. Users rely on knowing what a number means.

## Testing patterns (match the existing tests)

- **Pure functions with synthetic inputs**: build a snapshot by hand and assert exact values,
  as in `memory.rs` `ram_used_matches_activity_monitor_formula`.
- **Band and threshold edges**: test both sides of every boundary, and monotonicity across
  transitions (`transitions_are_monotonic_across_levels`).
- **Continuity**: sample densely (for example 0.0…100.0 in 0.1 steps) and assert that
  neighbouring outputs stay close. This catches snaps and flicker.
- **Frame-rate independence**: 10 × 0.1 s must land where 1 × 1.0 s lands.
- **Determinism**: no clock reads or randomness in the engine; feed `dt` explicitly.
- **Cadence**: model the host timer (fixed grid, up to ~15 % late) and assert one frame per tick,
  as in `jittery_ticks_never_skip_or_double`.
- **Garbage in**: NaN, negative, huge `dt` and zero denominators must not panic or produce
  non-finite output.
- **Counters**: Mach tick counters are `u32` and wrap, so use `wrapping_sub` and test the wrap.
- **Per-frame path**: anything called from `Actor::tick` must keep `tests/no_alloc_tick.rs`
  at zero allocations. Use inline arrays, not `Vec`.
- **Live sanity**: if the new metric reads the real system, extend `tests/live_sampling.rs`
  with range checks and keep exact values out of it.

## Verify

```bash
export PATH=/opt/homebrew/opt/rustup/bin:$PATH
cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test --all-targets
cargo test --test live_sampling -- --nocapture   # prints the real numbers on this Mac
scripts/build-rust.sh debug                      # the universal .a that Swift links
```

Report the test count and any behaviour changes visible to the user (colour or speed).
