//! pet-core: the platform engine behind mypet.
//!
//! - [`monitoring`] samples CPU and memory from Mach / sysctl.
//! - [`engine`] turns metrics into colour, animation speed and frame stepping.
//! - [`ffi`] exposes a small C ABI consumed by the Swift app (see `include/pet_core.h`).
//!
//! The crate spawns no threads and keeps no global mutable state; every piece of state
//! lives in a handle owned by the caller.

pub mod engine;
pub mod ffi;
pub mod monitoring;
mod sys;

/// Bumped whenever a `#[repr(C)]` type or exported function signature changes.
pub const ABI_VERSION: u32 = 2;
