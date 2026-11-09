//! Compiles a C program against include/pet_core.h and checks that every shared struct
//! has the same size and field offsets as its Rust #[repr(C)] twin.

use std::mem::{offset_of, size_of};
use std::path::PathBuf;
use std::process::Command;

use pet_core::engine::animation::AnimSpec;
use pet_core::engine::gradient::{Rgb, Stop};
use pet_core::engine::{ActorConfig, Frame};
use pet_core::monitoring::Metrics;

const PROBE: &str = r#"
#include <stdio.h>
#include "pet_core.h"
#define F(T, f) printf(#T "." #f "=%zu\n", offsetof(T, f))
#define S(T) printf(#T "=%zu\n", sizeof(T))
int main(void) {
    S(PetColor); F(PetColor, r); F(PetColor, g); F(PetColor, b);
    S(PetGradientStop); F(PetGradientStop, threshold); F(PetGradientStop, color);
    S(PetMetrics); F(PetMetrics, cpu_percent); F(PetMetrics, ram_used_percent);
    F(PetMetrics, pressure_score); F(PetMetrics, kernel_pressure_level);
    F(PetMetrics, ram_used_bytes); F(PetMetrics, ram_total_bytes);
    F(PetMetrics, swap_used_bytes); F(PetMetrics, compressed_bytes);
    S(PetAnimSpec); F(PetAnimSpec, frames); F(PetAnimSpec, fps); F(PetAnimSpec, looping);
    S(PetActorConfig); F(PetActorConfig, memory_mode); F(PetActorConfig, cpu_driven_speed);
    F(PetActorConfig, state); F(PetActorConfig, manual_speed); F(PetActorConfig, animations);
    S(PetFrame); F(PetFrame, speed_multiplier); F(PetFrame, memory_score); F(PetFrame, tint);
    F(PetFrame, frame_index); F(PetFrame, state);
    printf("ABI=%d\n", PET_CORE_ABI_VERSION);
    return 0;
}
"#;

fn rust_layout() -> Vec<(String, usize)> {
    macro_rules! s {
        ($v:ident, $c:literal, $t:ty) => {
            $v.push(($c.to_string(), size_of::<$t>()))
        };
    }
    macro_rules! f {
        ($v:ident, $c:literal, $t:ty, $field:ident) => {
            $v.push((
                format!("{}.{}", $c, stringify!($field)),
                offset_of!($t, $field),
            ))
        };
    }
    let mut v = Vec::new();
    s!(v, "PetColor", Rgb);
    f!(v, "PetColor", Rgb, r);
    f!(v, "PetColor", Rgb, g);
    f!(v, "PetColor", Rgb, b);
    s!(v, "PetGradientStop", Stop);
    f!(v, "PetGradientStop", Stop, threshold);
    f!(v, "PetGradientStop", Stop, color);
    s!(v, "PetMetrics", Metrics);
    f!(v, "PetMetrics", Metrics, cpu_percent);
    f!(v, "PetMetrics", Metrics, ram_used_percent);
    f!(v, "PetMetrics", Metrics, pressure_score);
    f!(v, "PetMetrics", Metrics, kernel_pressure_level);
    f!(v, "PetMetrics", Metrics, ram_used_bytes);
    f!(v, "PetMetrics", Metrics, ram_total_bytes);
    f!(v, "PetMetrics", Metrics, swap_used_bytes);
    f!(v, "PetMetrics", Metrics, compressed_bytes);
    s!(v, "PetAnimSpec", AnimSpec);
    f!(v, "PetAnimSpec", AnimSpec, frames);
    f!(v, "PetAnimSpec", AnimSpec, fps);
    f!(v, "PetAnimSpec", AnimSpec, looping);
    s!(v, "PetActorConfig", ActorConfig);
    f!(v, "PetActorConfig", ActorConfig, memory_mode);
    f!(v, "PetActorConfig", ActorConfig, cpu_driven_speed);
    f!(v, "PetActorConfig", ActorConfig, state);
    f!(v, "PetActorConfig", ActorConfig, manual_speed);
    f!(v, "PetActorConfig", ActorConfig, animations);
    s!(v, "PetFrame", Frame);
    f!(v, "PetFrame", Frame, speed_multiplier);
    f!(v, "PetFrame", Frame, memory_score);
    f!(v, "PetFrame", Frame, tint);
    f!(v, "PetFrame", Frame, frame_index);
    f!(v, "PetFrame", Frame, state);
    v.push(("ABI".into(), pet_core::ABI_VERSION as usize));
    v
}

#[test]
fn c_header_matches_rust_layout() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let out = PathBuf::from(env!("CARGO_TARGET_TMPDIR"));
    let src = out.join("probe.c");
    let exe = out.join("probe");
    std::fs::write(&src, PROBE).unwrap();
    let status = Command::new("cc")
        .args(["-std=c11", "-Wall", "-Werror", "-I"])
        .arg(root.join("include"))
        .arg(&src)
        .arg("-o")
        .arg(&exe)
        .status()
        .expect("a C compiler (cc) is required for the header check");
    assert!(
        status.success(),
        "probe failed to compile against pet_core.h"
    );
    let output = Command::new(&exe).output().unwrap();
    let text = String::from_utf8(output.stdout).unwrap();
    let c: Vec<(String, usize)> = text
        .lines()
        .map(|l| {
            let (k, v) = l.split_once('=').unwrap();
            (k.to_string(), v.parse().unwrap())
        })
        .collect();
    assert_eq!(c, rust_layout());
}
