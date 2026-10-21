---
name: mypet-ffi-change
description: "Safely change the Rust↔Swift boundary in MyPet — add or modify an exported pet_* function, a #[repr(C)] struct (PetMetrics, PetFrame, PetActorConfig…), or a new metric/setting that must flow from Rust to Swift. Use whenever a task touches rust/pet-core/src/ffi.rs, include/pet_core.h, RustBridge.swift or the ABI version, or when a feature needs new data from the Rust engine (\"Rust se naya value Swift mein chahiye\", \"add GPU usage\", \"expose battery to the pet\")."
---

# Changing the MyPet FFI

The Swift app talks to `libpet_core.a` only through `include/pet_core.h`. That header is
**hand-written**. The safety net is `tests/header_check.rs`, which compiles a C probe against
the header and compares every struct size and field offset with the Rust layout. A mismatch
that slips through corrupts memory silently, so make the whole change in one go.

## Checklist (in this order)

1. **Rust type/function**
   - Structs: `#[repr(C)]`, plain scalars only (no `bool`: use `u8`; no `String`/`Vec`).
     Add padding explicitly as `reserved: [u8; N]` so the C side sees the same layout.
   - Exports go in `ffi.rs` only: `#[no_mangle] pub unsafe extern "C"`, null-check every
     pointer, wrap the body in `guard(…)` / `with_actor(…)` (catch_unwind), return
     `PetStatus`, write out-pointers only on `PET_OK`, add `// SAFETY:` comments, and a doc
     comment with a `# Safety` section.
   - Threading: an engine handle is used only on the monitor queue and actor handles only on
     main. A new handle type needs its own rule documented in the header comment.
2. **Bump `ABI_VERSION`** in `rust/pet-core/src/lib.rs` and **`PET_CORE_ABI_VERSION`** in the
   header, to the same value. The app refuses to start on a mismatch, which is intended.
3. **Header**: mirror the struct or prototype in `include/pet_core.h` with the same field order
   and types (`uint8_t`/`uint32_t`/`uint64_t`/`float`), and add enum constants as anonymous
   `enum { … }`.
4. **Layout test**: add the new struct and every field to `PROBE` and `rust_layout()` in
   `tests/header_check.rs`.
5. **Behaviour tests**: unit tests next to the Rust code, plus a round trip in
   `tests/ffi_roundtrip.rs` (null pointers → `PET_ERR_NULL`, bad values → `PET_ERR_INVALID`).
   When the function sits in the per-frame path, keep `tests/no_alloc_tick.rs` green: no heap
   allocation per tick.
6. **Swift wrapper**: only `macos/mypet/Bridge/RustBridge.swift` calls C functions. Wrap the
   new call there (handle classes free in `deinit`, compare statuses with `PetStatus(PET_OK)`,
   fixed C arrays import as tuples). Everything else uses the wrapper.
7. **Verify**:
   ```bash
   export PATH=/opt/homebrew/opt/rustup/bin:$PATH
   cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test --all-targets
   scripts/build-rust.sh debug && (cd macos && swift build)
   ```
   Then rebuild and launch the app (see the `mypet-build-run` skill). The ABI check runs at
   launch.
8. **Docs**: update the FFI surface list in GUIDELINES.md §4, and docs/METRICS.md when the
   change adds a new metric.

## Common mistakes

- Adding a Rust field without updating the header. `header_check` fails, which is the purpose
  of that test, so update the header rather than the test.
- Using `bool` in a repr(C) struct. Its size is fine, but Swift imports it differently than
  `uint8_t`, so stay consistent with the existing `u8` flags.
- Calling a handle from a second thread "just once". Route the call through the owning queue.
- Forgetting that `cargo test` builds the rlib, not the staticlib. Swift links the universal
  `target/universal/<cfg>/libpet_core.a`, so rerun `scripts/build-rust.sh` before `swift build`.
