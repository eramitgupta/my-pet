---
paths:
  - "rust/**/*.rs"
  - "tests/**/*.rs"
  - "**/Cargo.toml"
---

# Rust rules (pet-core)

- **No third-party crates.** `pet-core` has zero dependencies by design: smaller audit
  surface, nothing to drift. Declare Mach/sysctl APIs by hand in `src/sys.rs`, mirroring the
  SDK headers (`$(xcrun --show-sdk-path)/usr/include/mach/...`), and add a size test for each
  struct.
- **No threads, no globals.** Swift owns threads and timers. All state lives in a handle
  (`Monitor`, `Actor`) owned by the caller: no `static mut`, `lazy_static` or thread-local state.
- **`unsafe` only in `sys.rs` and `ffi.rs`**, and every block gets a `// SAFETY:` comment that
  explains why it is sound.
- **Never panic on system data.** Syscall wrappers return `Option`/`Result`. Treat NaN,
  negative or huge `dt` and zero denominators as normal input: clamp them, or fall back to a
  safe value.
- **Mach counters are `u32` and wrap.** Use `wrapping_sub` on tick deltas.
- **Zero allocation on the per-frame path.** Anything reachable from `Actor::tick` or
  `update_metrics` uses inline arrays and `Copy` types, not `Vec`/`String`/`Box`.
  `tests/no_alloc_tick.rs` enforces this.
- **Determinism.** The engine has no randomness and never reads the clock: all time arrives as
  `dt`, so every result is reproducible in tests. Turn-around randomness lives in Swift
  (`FacingController`, injectable).
- **Frame stepping tolerates timer jitter.** `Animator` shows a frame once it is within
  `FRAME_DUE_TOLERANCE` of due. Don't go back to a strict `>= 1.0`: the ±10 % host-timer jitter
  would skip and double frames, which shows as a stutter (`jittery_ticks_never_skip_or_double`).
- **Colour maths happen in OKLab** (`gradient.rs`), and smoothing must be frame-rate
  independent (`1 − e^(−dt/τ)`).
- **Separate pure logic from syscalls.** Scoring and mapping are plain functions over plain
  data, unit-tested with synthetic inputs. Wrappers only gather data.
- **Every behaviour change comes with tests** next to the code: exact values, both sides of each
  threshold, continuity (no jumps), and garbage input.
- A change to a `#[repr(C)]` type or an exported function is an ABI change. Follow the
  `mypet-ffi-change` skill (ABI bump, header, `header_check`).
- Before finishing, run `cargo fmt --all`, then `cargo clippy --all-targets -- -D warnings`,
  then `cargo test --all-targets`. `cargo` lives in `/opt/homebrew/opt/rustup/bin`.
- Public items get a one-line `///` doc comment. Comments explain *why*.
