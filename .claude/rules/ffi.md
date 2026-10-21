---
paths:
  - "rust/pet-core/src/ffi.rs"
  - "rust/pet-core/src/lib.rs"
  - "include/**/*.h"
  - "macos/CPetCore/**"
  - "macos/mypet/Bridge/**/*.swift"
  - "tests/header_check.rs"
  - "tests/ffi_roundtrip.rs"
---

# Rust ↔ Swift boundary rules

`include/pet_core.h` is hand-written, so the compiler can't catch a Rust/C mismatch. These
rules exist because a silent layout mismatch corrupts memory.

- **Plain C only:** `#[repr(C)]` structs of scalars (`u8`/`u32`/`u64`/`f32`/`f64`), opaque
  handle pointers, and `PetStatus` (`i32`) return codes. No `bool` (use `u8`), and no strings,
  slices or Rust enums by value. Make padding explicit with `reserved: [u8; N]`.
- **Every export:** `#[no_mangle] pub unsafe extern "C"`, null-checks all pointers, runs inside
  `guard`/`with_actor` (`catch_unwind`), returns a `PetStatus`, writes out-pointers only on
  `PET_OK`, and never keeps a caller pointer.
- **Ownership:** `*_new` → `Box::into_raw`, `*_free` → `Box::from_raw`, and `*_free(NULL)` is a
  no-op. Swift wraps each handle in a `final class` that frees it in `deinit`.
- **Threading:** `PetEngine` is used only on the monitor queue and `PetActor` only on the main
  thread. A handle is never shared across threads.
- **One change, all layers, one commit:** Rust type/function → bump `ABI_VERSION` (`lib.rs`) and
  `PET_CORE_ABI_VERSION` (header) together → header → `tests/header_check.rs` probe and
  `rust_layout()` → `tests/ffi_roundtrip.rs` → `RustBridge.swift`.
- **Only `macos/mypet/Bridge/RustBridge.swift` calls C functions.** Everything else uses its
  wrappers (`MetricsEngine`, `PetActorHandle`, `RustBridge.sampleBands`). Compare statuses with
  `PetStatus(PET_OK)`.
- When `header_check` fails, fix the header or the Rust struct. Don't edit the test to match.
- After changing Rust, rebuild the static library (`scripts/build-rust.sh debug`) before
  `swift build`. `cargo test` builds only the rlib.
