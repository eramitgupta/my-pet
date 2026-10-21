//! RAM usage and memory-pressure scoring. See docs/METRICS.md for the definitions.
//!
//! *RAM usage* is occupancy: how much physical memory holds app, wired and compressed data.
//! *Memory pressure* is stress: whether the kernel is struggling to supply free pages.
//! macOS keeps RAM full of cache on purpose, so high usage alone is not a problem.

use crate::sys::{self, HostPort};

/// Kernel pressure levels, as reported by `kern.memorystatus_vm_pressure_level` and
/// `DISPATCH_MEMORYPRESSURE_*`.
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum PressureLevel {
    Normal = 1,
    Warn = 2,
    Critical = 4,
}

impl PressureLevel {
    pub fn from_raw(raw: i64) -> Option<Self> {
        match raw {
            1 => Some(Self::Normal),
            2 => Some(Self::Warn),
            4 => Some(Self::Critical),
            _ => None,
        }
    }

    /// (base, span): the score band this level maps to.
    fn band(self) -> (f32, f32) {
        match self {
            Self::Normal => (0.0, 55.0),
            Self::Warn => (60.0, 20.0),
            Self::Critical => (85.0, 15.0),
        }
    }
}

/// Page counts from `HOST_VM_INFO64` plus machine constants.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct VmSnapshot {
    pub page_size: u64,
    pub total_bytes: u64,
    pub free: u64,
    pub active: u64,
    pub inactive: u64,
    pub wired: u64,
    pub purgeable: u64,
    pub speculative: u64,
    pub compressor: u64,
    pub internal: u64,
    pub external: u64,
}

impl VmSnapshot {
    pub fn total_pages(&self) -> u64 {
        (self.total_bytes / self.page_size.max(1)).max(1)
    }
}

/// Bytes in use, matching Activity Monitor's "Memory Used" headline:
/// physical memory minus *Cached Files* (file-backed + purgeable pages) minus free pages.
///
/// This is larger than App + Wired + Compressed (the breakdown Activity Monitor lists below
/// it): current macOS counts memory that fits neither category as used, too. The kernel's
/// `free_count` includes speculative (read-ahead) pages, which are already file-backed, so
/// they're taken out of "free" to avoid subtracting them twice.
pub fn ram_used_bytes(vm: &VmSnapshot) -> u64 {
    let free = vm.free.saturating_sub(vm.speculative);
    let reclaimable = (free + vm.external + vm.purgeable) * vm.page_size;
    vm.total_bytes.saturating_sub(reclaimable)
}

pub fn ram_used_percent(vm: &VmSnapshot) -> f32 {
    if vm.total_bytes == 0 {
        return 0.0;
    }
    (ram_used_bytes(vm) as f64 / vm.total_bytes as f64 * 100.0).clamp(0.0, 100.0) as f32
}

/// Inputs to the pressure estimate.
#[derive(Clone, Copy, Debug)]
pub struct PressureInputs {
    pub level: PressureLevel,
    pub vm: VmSnapshot,
    pub swap_used: u64,
    pub swap_total: u64,
}

/// Measured strain in 0..=1: weighted mix of scarce available pages, compressor
/// occupancy and swap use.
pub fn strain(inputs: &PressureInputs) -> f32 {
    let vm = &inputs.vm;
    let total = vm.total_pages() as f32;
    let available = (vm.free + vm.inactive + vm.purgeable) as f32 / total;
    let compressed = vm.compressor as f32 / total;
    let swap = if inputs.swap_total == 0 {
        0.0
    } else {
        inputs.swap_used as f32 / inputs.swap_total as f32
    };
    let s = 0.45 * (1.0 - available.clamp(0.0, 1.0))
        + 0.35 * (compressed / 0.35).min(1.0)
        + 0.20 * swap.clamp(0.0, 1.0);
    s.clamp(0.0, 1.0)
}

/// Pressure score in 0..=100. The kernel level picks the band; strain places the score
/// inside it, so the score can never contradict the kernel (normal never reads as red).
pub fn pressure_score(inputs: &PressureInputs) -> f32 {
    let (base, span) = inputs.level.band();
    base + span * strain(inputs)
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MemorySample {
    pub ram_used_percent: f32,
    pub pressure_score: f32,
    pub level: PressureLevel,
    pub ram_used_bytes: u64,
    pub ram_total_bytes: u64,
    pub swap_used_bytes: u64,
    pub compressed_bytes: u64,
}

pub struct MemoryMonitor {
    page_size: u64,
    total_bytes: u64,
    last_event: Option<PressureLevel>,
}

impl MemoryMonitor {
    pub fn new(host: &HostPort) -> Self {
        MemoryMonitor {
            page_size: host.page_size().unwrap_or(16_384),
            total_bytes: sys::sysctl_value::<u64>(c"hw.memsize").unwrap_or(0),
            last_event: None,
        }
    }

    pub fn note_pressure_event(&mut self, level: PressureLevel) {
        self.last_event = Some(level);
    }

    fn kernel_level(&self) -> PressureLevel {
        sys::sysctl_value::<i32>(c"kern.memorystatus_vm_pressure_level")
            .and_then(|raw| PressureLevel::from_raw(raw.into()))
            .or(self.last_event)
            .unwrap_or(PressureLevel::Normal)
    }

    pub fn sample(&mut self, host: &HostPort) -> Option<MemorySample> {
        if self.total_bytes == 0 {
            return None;
        }
        let s = host.vm_stats()?;
        let vm = VmSnapshot {
            page_size: self.page_size,
            total_bytes: self.total_bytes,
            free: s.free_count.into(),
            active: s.active_count.into(),
            inactive: s.inactive_count.into(),
            wired: s.wire_count.into(),
            purgeable: s.purgeable_count.into(),
            speculative: s.speculative_count.into(),
            compressor: s.compressor_page_count.into(),
            internal: s.internal_page_count.into(),
            external: s.external_page_count.into(),
        };
        let swap = sys::sysctl_value::<sys::xsw_usage>(c"vm.swapusage").unwrap_or_default();
        let inputs = PressureInputs {
            level: self.kernel_level(),
            vm,
            swap_used: swap.xsu_used,
            swap_total: swap.xsu_total,
        };
        Some(MemorySample {
            ram_used_percent: ram_used_percent(&vm),
            pressure_score: pressure_score(&inputs),
            level: inputs.level,
            ram_used_bytes: ram_used_bytes(&vm),
            ram_total_bytes: vm.total_bytes,
            swap_used_bytes: swap.xsu_used,
            compressed_bytes: vm.compressor * vm.page_size,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAGE: u64 = 16_384;
    const TOTAL_PAGES: u64 = 1_000_000; // ~16 GB

    fn vm(free: u64, inactive: u64, internal: u64, wired: u64, compressor: u64) -> VmSnapshot {
        VmSnapshot {
            page_size: PAGE,
            total_bytes: TOTAL_PAGES * PAGE,
            free,
            inactive,
            internal,
            wired,
            compressor,
            ..Default::default()
        }
    }

    fn inputs(level: PressureLevel, vm: VmSnapshot, swap_used: u64) -> PressureInputs {
        PressureInputs {
            level,
            vm,
            swap_used,
            swap_total: 4 << 30,
        }
    }

    #[test]
    fn ram_used_matches_activity_monitor() {
        // Numbers from a real Activity Monitor window on an 8 GB Mac (macOS 27):
        // Physical 8.00 GB, Cached Files 992.5 MB, Memory Used 6.97 GB.
        let page = 16_384u64;
        let gib = 1u64 << 30;
        let mut v = VmSnapshot {
            page_size: page,
            total_bytes: 8 * gib,
            ..Default::default()
        };
        v.external = (992.5 * 1024.0 * 1024.0) as u64 / page; // Cached Files
        v.purgeable = 0;
        v.speculative = 4_000; // part of free_count *and* of the file-backed pages
                               // Activity Monitor uses binary units; the free memory it doesn't show is what's left.
        let free_gib = 8.0 - 6.97 - 992.5 / 1024.0;
        v.free = 4_000 + (free_gib * gib as f64) as u64 / page;
        let used_gib = ram_used_bytes(&v) as f64 / gib as f64;
        assert!((used_gib - 6.97).abs() < 0.01, "used {used_gib:.3} GiB");
        assert!((ram_used_percent(&v) - 87.1).abs() < 0.2);
    }

    #[test]
    fn speculative_pages_are_not_subtracted_twice() {
        let mut v = vm(100_000, 0, 0, 0, 0);
        v.external = 50_000;
        let before = ram_used_bytes(&v);
        v.speculative = 30_000; // inside free_count: moving them there changes nothing
        assert_eq!(ram_used_bytes(&v), before + 30_000 * PAGE);
    }

    #[test]
    fn ram_used_is_clamped() {
        let v = vm(0, 0, 2_000_000, 0, 0);
        assert_eq!(ram_used_percent(&v), 100.0);
        let mut over = vm(2_000_000, 0, 0, 0, 0); // more reclaimable than physical: 0, not underflow
        over.external = 10;
        assert_eq!(ram_used_bytes(&over), 0);
        assert_eq!(VmSnapshot::default().total_pages(), 1);
        assert_eq!(ram_used_percent(&VmSnapshot::default()), 0.0);
    }

    #[test]
    fn normal_level_never_leaves_its_band() {
        let relaxed = inputs(PressureLevel::Normal, vm(900_000, 50_000, 0, 0, 0), 0);
        let strained = inputs(PressureLevel::Normal, vm(0, 0, 0, 0, 900_000), 4 << 30);
        assert!(pressure_score(&relaxed) < 5.0);
        assert!(pressure_score(&strained) <= 55.0);
        assert!(pressure_score(&strained) > 50.0);
    }

    #[test]
    fn warn_and_critical_band_edges() {
        let relaxed = vm(1_000_000, 0, 0, 0, 0);
        let strained = vm(0, 0, 0, 0, 1_000_000);
        let w0 = pressure_score(&inputs(PressureLevel::Warn, relaxed, 0));
        let w1 = pressure_score(&inputs(PressureLevel::Warn, strained, 4 << 30));
        assert!((w0 - 60.0).abs() < 1e-3);
        assert!((w1 - 80.0).abs() < 1e-3);
        let c0 = pressure_score(&inputs(PressureLevel::Critical, relaxed, 0));
        let c1 = pressure_score(&inputs(PressureLevel::Critical, strained, 4 << 30));
        assert!((c0 - 85.0).abs() < 1e-3);
        assert!((c1 - 100.0).abs() < 1e-3);
    }

    #[test]
    fn transitions_are_monotonic_across_levels() {
        // Same VM state, escalating kernel level: the score must only go up.
        let v = vm(200_000, 100_000, 500_000, 100_000, 100_000);
        let n = pressure_score(&inputs(PressureLevel::Normal, v, 0));
        let w = pressure_score(&inputs(PressureLevel::Warn, v, 0));
        let c = pressure_score(&inputs(PressureLevel::Critical, v, 0));
        assert!(n < w && w < c, "{n} {w} {c}");
    }

    #[test]
    fn strain_rises_with_compression_and_swap() {
        let base = vm(300_000, 100_000, 400_000, 100_000, 0);
        let mut compressed = base;
        compressed.compressor = 200_000;
        let s0 = strain(&inputs(PressureLevel::Normal, base, 0));
        let s1 = strain(&inputs(PressureLevel::Normal, compressed, 0));
        let s2 = strain(&inputs(PressureLevel::Normal, compressed, 2 << 30));
        assert!(s0 < s1 && s1 < s2);
    }

    #[test]
    fn zero_swap_total_is_safe() {
        let mut i = inputs(PressureLevel::Normal, vm(0, 0, 0, 0, 0), 123);
        i.swap_total = 0;
        assert!(strain(&i).is_finite());
    }

    #[test]
    fn raw_level_parsing() {
        assert_eq!(PressureLevel::from_raw(1), Some(PressureLevel::Normal));
        assert_eq!(PressureLevel::from_raw(2), Some(PressureLevel::Warn));
        assert_eq!(PressureLevel::from_raw(4), Some(PressureLevel::Critical));
        assert_eq!(PressureLevel::from_raw(3), None);
    }
}
