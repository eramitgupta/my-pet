//! C ABI for the Swift app. Contract (see GUIDELINES.md §4 and include/pet_core.h):
//!
//! - Handles are opaque and owned by the caller: `*_new` allocates, `*_free` releases.
//!   `*_free(NULL)` is a no-op. Using a handle after freeing it is undefined behaviour.
//! - A handle must not be used from two threads at once. Different handles are independent.
//! - Output is written through caller-owned out-pointers; Rust never retains them.
//! - Every entry point catches panics and reports `PET_ERR_PANIC`; nothing unwinds into C.

use std::panic::{catch_unwind, AssertUnwindSafe};

use crate::engine::gradient::{Gradient, Rgb, Stop};
use crate::engine::{Actor, ActorConfig, Frame};
use crate::monitoring::memory::PressureLevel;
use crate::monitoring::{Metrics, Monitor};

pub type PetStatus = i32;
pub const PET_OK: PetStatus = 0;
pub const PET_ERR_NULL: PetStatus = 1;
pub const PET_ERR_SYS: PetStatus = 2;
pub const PET_ERR_PANIC: PetStatus = 3;
pub const PET_ERR_INVALID: PetStatus = 4;

/// Shared metrics sampler. One per app, used from a single background queue.
pub struct PetEngine {
    monitor: Monitor,
}

/// One animated pet.
pub struct PetActor {
    actor: Actor,
}

fn guard(f: impl FnOnce() -> PetStatus) -> PetStatus {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(PET_ERR_PANIC)
}

/// Returns `crate::ABI_VERSION`; Swift refuses to run against a mismatched library.
#[no_mangle]
pub extern "C" fn pet_core_abi_version() -> u32 {
    crate::ABI_VERSION
}

// ---- Engine -------------------------------------------------------------------------------

/// Creates the metrics engine. Returns NULL on failure.
#[no_mangle]
pub extern "C" fn pet_engine_new() -> *mut PetEngine {
    catch_unwind(|| {
        Box::into_raw(Box::new(PetEngine {
            monitor: Monitor::new(),
        }))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `engine` must be NULL or a pointer returned by `pet_engine_new` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn pet_engine_free(engine: *mut PetEngine) {
    if !engine.is_null() {
        // SAFETY: per the contract, `engine` came from Box::into_raw and is freed once.
        let _ = catch_unwind(AssertUnwindSafe(|| drop(unsafe { Box::from_raw(engine) })));
    }
}

/// Takes one metrics sample. The first call primes the CPU baseline and reports 0% CPU.
///
/// # Safety
/// `engine` must be a live engine handle; `out` must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn pet_engine_sample(engine: *mut PetEngine, out: *mut Metrics) -> PetStatus {
    guard(|| {
        // SAFETY: null-checked; validity is the caller's contract.
        let (Some(engine), Some(out)) = (unsafe { engine.as_mut() }, unsafe { out.as_mut() })
        else {
            return PET_ERR_NULL;
        };
        match engine.monitor.sample() {
            Ok(m) => {
                *out = m;
                PET_OK
            }
            Err(_) => PET_ERR_SYS,
        }
    })
}

/// Forwards a Dispatch memory-pressure event level (1 normal, 2 warn, 4 critical).
///
/// # Safety
/// `engine` must be a live engine handle.
#[no_mangle]
pub unsafe extern "C" fn pet_engine_note_pressure_event(
    engine: *mut PetEngine,
    level: u8,
) -> PetStatus {
    guard(|| {
        // SAFETY: null-checked; validity is the caller's contract.
        let Some(engine) = (unsafe { engine.as_mut() }) else {
            return PET_ERR_NULL;
        };
        match PressureLevel::from_raw(level.into()) {
            Some(l) => {
                engine.monitor.note_pressure_event(l);
                PET_OK
            }
            None => PET_ERR_INVALID,
        }
    })
}

// ---- Actor --------------------------------------------------------------------------------

/// Creates a pet with the default config (running animation). Returns NULL on failure.
#[no_mangle]
pub extern "C" fn pet_actor_new() -> *mut PetActor {
    catch_unwind(|| {
        Box::into_raw(Box::new(PetActor {
            actor: Actor::new(),
        }))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `actor` must be NULL or a pointer returned by `pet_actor_new` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn pet_actor_free(actor: *mut PetActor) {
    if !actor.is_null() {
        // SAFETY: per the contract, `actor` came from Box::into_raw and is freed once.
        let _ = catch_unwind(AssertUnwindSafe(|| drop(unsafe { Box::from_raw(actor) })));
    }
}

/// Runs `f` on the actor behind `actor`, translating NULL into `PET_ERR_NULL`.
///
/// # Safety
/// `actor` must be NULL or a live actor handle not used concurrently.
unsafe fn with_actor(actor: *mut PetActor, f: impl FnOnce(&mut Actor) -> PetStatus) -> PetStatus {
    guard(|| match unsafe { actor.as_mut() } {
        Some(a) => f(&mut a.actor),
        None => PET_ERR_NULL,
    })
}

/// Applies a configuration. Invalid configs are rejected and the old one is kept.
///
/// # Safety
/// `actor` must be a live actor handle; `config` must point to a valid `PetActorConfig`.
#[no_mangle]
pub unsafe extern "C" fn pet_actor_configure(
    actor: *mut PetActor,
    config: *const ActorConfig,
) -> PetStatus {
    with_actor(actor, |a| {
        // SAFETY: null-checked; validity is the caller's contract.
        let Some(cfg) = (unsafe { config.as_ref() }) else {
            return PET_ERR_NULL;
        };
        match a.configure(*cfg) {
            Ok(()) => PET_OK,
            Err(_) => PET_ERR_INVALID,
        }
    })
}

/// Sets an explicit gradient: 2..=8 stops, ascending thresholds in 0..=100.
///
/// # Safety
/// `stops` must point to `count` readable `PetGradientStop`s.
#[no_mangle]
pub unsafe extern "C" fn pet_actor_set_gradient(
    actor: *mut PetActor,
    stops: *const Stop,
    count: usize,
) -> PetStatus {
    with_actor(actor, |a| {
        if stops.is_null() {
            return PET_ERR_NULL;
        }
        if count > crate::engine::gradient::MAX_STOPS {
            return PET_ERR_INVALID;
        }
        // SAFETY: non-null and the caller guarantees `count` elements.
        let slice = unsafe { std::slice::from_raw_parts(stops, count) };
        match Gradient::new(slice) {
            Ok(g) => {
                a.set_gradient(g);
                PET_OK
            }
            Err(_) => PET_ERR_INVALID,
        }
    })
}

/// # Safety
/// `colors` → 4 readable `PetColor`s, `thresholds` → 3 readable floats.
unsafe fn read_bands(colors: *const Rgb, thresholds: *const f32) -> Result<Gradient, PetStatus> {
    if colors.is_null() || thresholds.is_null() {
        return Err(PET_ERR_NULL);
    }
    // SAFETY: non-null and sized per the documented contract.
    let (c, t) = unsafe {
        (
            *(colors as *const [Rgb; 4]),
            *(thresholds as *const [f32; 3]),
        )
    };
    Gradient::from_bands(c, t).map_err(|_| PET_ERR_INVALID)
}

/// Sets the four-band gradient (green/yellow/orange/red colours, three band thresholds).
///
/// # Safety
/// `colors` must point to 4 `PetColor`s and `thresholds` to 3 floats.
#[no_mangle]
pub unsafe extern "C" fn pet_actor_set_bands(
    actor: *mut PetActor,
    colors: *const Rgb,
    thresholds: *const f32,
) -> PetStatus {
    with_actor(actor, |a| match unsafe { read_bands(colors, thresholds) } {
        Ok(g) => {
            a.set_gradient(g);
            PET_OK
        }
        Err(e) => e,
    })
}

/// Stateless helper for the settings UI: colour of `value` on a four-band gradient.
///
/// # Safety
/// `colors` → 4 `PetColor`s, `thresholds` → 3 floats, `out` valid for writes.
#[no_mangle]
pub unsafe extern "C" fn pet_gradient_sample_bands(
    colors: *const Rgb,
    thresholds: *const f32,
    value: f32,
    out: *mut Rgb,
) -> PetStatus {
    guard(|| {
        // SAFETY: null-checked; validity is the caller's contract.
        let Some(out) = (unsafe { out.as_mut() }) else {
            return PET_ERR_NULL;
        };
        match unsafe { read_bands(colors, thresholds) } {
            Ok(g) => {
                *out = g.sample(value);
                PET_OK
            }
            Err(e) => e,
        }
    })
}

/// Feeds the latest metrics sample (from `pet_engine_sample`).
///
/// # Safety
/// `metrics` must point to a valid `PetMetrics`.
#[no_mangle]
pub unsafe extern "C" fn pet_actor_update_metrics(
    actor: *mut PetActor,
    metrics: *const Metrics,
) -> PetStatus {
    with_actor(actor, |a| {
        // SAFETY: null-checked; validity is the caller's contract.
        match unsafe { metrics.as_ref() } {
            Some(m) => {
                a.update_metrics(m);
                PET_OK
            }
            None => PET_ERR_NULL,
        }
    })
}

/// Advances the pet by `dt_seconds` and writes the frame to draw.
///
/// # Safety
/// `out` must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn pet_actor_tick(
    actor: *mut PetActor,
    dt_seconds: f64,
    out: *mut Frame,
) -> PetStatus {
    with_actor(actor, |a| {
        // SAFETY: null-checked; validity is the caller's contract.
        match unsafe { out.as_mut() } {
            Some(out) => {
                *out = a.tick(dt_seconds as f32);
                PET_OK
            }
            None => PET_ERR_NULL,
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn null_handles_are_reported() {
        unsafe {
            let mut m = Metrics::default();
            assert_eq!(
                pet_engine_sample(std::ptr::null_mut(), &mut m),
                PET_ERR_NULL
            );
            let mut f = Frame::default();
            assert_eq!(
                pet_actor_tick(std::ptr::null_mut(), 0.1, &mut f),
                PET_ERR_NULL
            );
            pet_engine_free(std::ptr::null_mut());
            pet_actor_free(std::ptr::null_mut());
        }
    }

    #[test]
    fn panics_are_contained() {
        assert_eq!(guard(|| panic!("boom")), PET_ERR_PANIC);
    }

    #[test]
    fn invalid_inputs_are_rejected() {
        unsafe {
            let a = pet_actor_new();
            let bad = ActorConfig {
                state: 9,
                ..ActorConfig::default()
            };
            assert_eq!(pet_actor_configure(a, &bad), PET_ERR_INVALID);
            let stops = [Stop::default(); 9];
            assert_eq!(
                pet_actor_set_gradient(a, stops.as_ptr(), 9),
                PET_ERR_INVALID
            );
            let e = pet_engine_new();
            assert_eq!(pet_engine_note_pressure_event(e, 3), PET_ERR_INVALID);
            assert_eq!(pet_engine_note_pressure_event(e, 4), PET_OK);
            pet_engine_free(e);
            pet_actor_free(a);
        }
    }
}
