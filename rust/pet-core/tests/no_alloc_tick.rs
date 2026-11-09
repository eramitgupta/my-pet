//! The per-frame path (update_metrics + tick) must not touch the heap.

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use pet_core::engine::gradient::{Gradient, DEFAULT_COLORS};
use pet_core::engine::Actor;
use pet_core::monitoring::Metrics;

struct Counting;
static ALLOCS: AtomicUsize = AtomicUsize::new(0);
static ARMED: AtomicBool = AtomicBool::new(false);

unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if ARMED.load(Ordering::Relaxed) {
            ALLOCS.fetch_add(1, Ordering::Relaxed);
        }
        unsafe { System.alloc(layout) }
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) }
    }
}

#[global_allocator]
static GLOBAL: Counting = Counting;

#[test]
fn tick_does_not_allocate() {
    let mut a = Actor::new();
    a.set_gradient(Gradient::from_bands(DEFAULT_COLORS, [30.0, 50.0, 70.0]).unwrap());
    let m = Metrics {
        cpu_percent: 30.0,
        ram_used_percent: 55.0,
        kernel_pressure_level: 1,
        ..Default::default()
    };
    ARMED.store(true, Ordering::SeqCst);
    for i in 0..10_000 {
        a.update_metrics(&m);
        let f = a.tick(1.0 / 30.0 + (i % 7) as f32 * 0.001);
        std::hint::black_box(f);
    }
    ARMED.store(false, Ordering::SeqCst);
    assert_eq!(ALLOCS.load(Ordering::SeqCst), 0);
}
