//! Exercises the C ABI the way the Swift app does.

use pet_core::engine::animation::AnimSpec;
use pet_core::engine::gradient::Rgb;
use pet_core::engine::{ActorConfig, Frame};
use pet_core::ffi::*;
use pet_core::monitoring::Metrics;

#[test]
fn abi_version_is_exposed() {
    assert_eq!(pet_core_abi_version(), pet_core::ABI_VERSION);
}

#[test]
fn engine_samples_live_metrics() {
    unsafe {
        let e = pet_engine_new();
        assert!(!e.is_null());
        let mut m = Metrics::default();
        assert_eq!(pet_engine_sample(e, &mut m), PET_OK);
        std::thread::sleep(std::time::Duration::from_millis(150));
        assert_eq!(pet_engine_sample(e, &mut m), PET_OK);
        assert!(m.ram_total_bytes > 0);
        assert!((0.0..=100.0).contains(&m.cpu_percent));
        pet_engine_free(e);
    }
}

#[test]
fn menu_bar_actor_full_cycle() {
    // The same sequence the Swift MenuBarController performs.
    unsafe {
        let a = pet_actor_new();
        assert!(!a.is_null());
        let cfg = ActorConfig {
            cpu_driven_speed: 0,
            manual_speed: 1.0,
            animations: [
                AnimSpec::new(4, 4.0, true),
                AnimSpec::new(6, 8.0, true),
                AnimSpec::new(6, 12.0, true),
                AnimSpec::new(6, 10.0, false),
                AnimSpec::new(4, 2.0, true),
            ],
            ..ActorConfig::default()
        };
        assert_eq!(pet_actor_configure(a, &cfg), PET_OK);
        let colors = [
            Rgb::hex(0x00ff00),
            Rgb::hex(0xffff00),
            Rgb::hex(0xff8800),
            Rgb::hex(0xff0000),
        ];
        let thresholds = [35.0f32, 60.0, 80.0];
        assert_eq!(
            pet_actor_set_bands(a, colors.as_ptr(), thresholds.as_ptr()),
            PET_OK
        );
        let m = Metrics {
            cpu_percent: 50.0,
            ram_used_percent: 90.0,
            kernel_pressure_level: 1,
            ..Default::default()
        };
        assert_eq!(pet_actor_update_metrics(a, &m), PET_OK);
        let mut f = Frame::default();
        let mut frames = std::collections::HashSet::new();
        for _ in 0..300 {
            assert_eq!(pet_actor_tick(a, 1.0 / 12.0, &mut f), PET_OK);
            assert_eq!(f.state, 2); // run
            frames.insert(f.frame_index);
        }
        assert_eq!(frames.len(), 6, "every run frame is shown");
        assert!(f.tint.r > 0.9 && f.tint.g < 0.2, "{:?}", f.tint);
        assert_eq!(pet_actor_tick(a, 0.1, std::ptr::null_mut()), PET_ERR_NULL);
        pet_actor_free(a);
    }
}

#[test]
fn ui_gradient_helper() {
    unsafe {
        let colors = [
            Rgb::hex(0x00ff00),
            Rgb::hex(0xffff00),
            Rgb::hex(0xff8800),
            Rgb::hex(0xff0000),
        ];
        let thresholds = [35.0f32, 60.0, 80.0];
        let mut out = Rgb::default();
        assert_eq!(
            pet_gradient_sample_bands(colors.as_ptr(), thresholds.as_ptr(), 10.0, &mut out),
            PET_OK
        );
        assert_eq!(out, colors[0]);
        let bad = [60.0f32, 35.0, 80.0];
        assert_eq!(
            pet_gradient_sample_bands(colors.as_ptr(), bad.as_ptr(), 10.0, &mut out),
            PET_ERR_INVALID
        );
        assert_eq!(
            pet_gradient_sample_bands(std::ptr::null(), thresholds.as_ptr(), 1.0, &mut out),
            PET_ERR_NULL
        );
    }
}
