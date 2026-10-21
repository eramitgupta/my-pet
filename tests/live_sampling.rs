//! Samples the real host and sanity-checks the numbers.

use pet_core::monitoring::Monitor;

#[test]
fn live_metrics_are_sane() {
    let mut mon = Monitor::new();
    let first = mon.sample().expect("first sample");
    assert_eq!(
        first.cpu_percent, 0.0,
        "first sample only primes the CPU baseline"
    );
    // Burn a little CPU so the next reading has something to measure. The kernel's tick
    // counters advance in coarse steps, so retry briefly rather than flake under load.
    let mut x = 0u64;
    let mut m = first;
    for _ in 0..10 {
        let start = std::time::Instant::now();
        while start.elapsed().as_millis() < 200 {
            x = std::hint::black_box(x.wrapping_mul(6364136223846793005).wrapping_add(1));
        }
        m = mon.sample().expect("sample");
        if m.cpu_percent > 0.0 {
            break;
        }
    }
    assert!(
        m.cpu_percent > 0.0 && m.cpu_percent <= 100.0,
        "cpu {}",
        m.cpu_percent
    );
    assert!(m.ram_total_bytes >= 1 << 30);
    assert!(m.ram_used_bytes > 0 && m.ram_used_bytes <= m.ram_total_bytes);
    assert!((0.0..=100.0).contains(&m.ram_used_percent));
    assert!((0.0..=100.0).contains(&m.pressure_score));
    assert!(matches!(m.kernel_pressure_level, 1 | 2 | 4));
    println!(
        "cpu {:.1}%  ram {:.1}% ({:.2} / {:.2} GB)  pressure {:.1} (level {})  swap {} MB  compressed {} MB",
        m.cpu_percent,
        m.ram_used_percent,
        m.ram_used_bytes as f64 / 1e9,
        m.ram_total_bytes as f64 / 1e9,
        m.pressure_score,
        m.kernel_pressure_level,
        m.swap_used_bytes >> 20,
        m.compressed_bytes >> 20
    );
}
