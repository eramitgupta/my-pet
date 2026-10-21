//! Whole-machine CPU utilisation from `HOST_CPU_LOAD_INFO` tick counters.

use crate::sys::{self, HostPort};

/// Cumulative ticks for all cores: user, system, idle, nice.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CpuTicks {
    pub user: u32,
    pub system: u32,
    pub idle: u32,
    pub nice: u32,
}

impl CpuTicks {
    fn from_sys(info: &sys::host_cpu_load_info) -> Self {
        CpuTicks {
            user: info.cpu_ticks[sys::CPU_STATE_USER],
            system: info.cpu_ticks[sys::CPU_STATE_SYSTEM],
            idle: info.cpu_ticks[sys::CPU_STATE_IDLE],
            nice: info.cpu_ticks[sys::CPU_STATE_NICE],
        }
    }
}

/// Busy percentage between two tick snapshots. Counters are 32-bit and wrap, so deltas
/// use wrapping subtraction. Returns 0 when no time has elapsed.
pub fn cpu_percent(prev: CpuTicks, cur: CpuTicks) -> f32 {
    let busy = u64::from(cur.user.wrapping_sub(prev.user))
        + u64::from(cur.system.wrapping_sub(prev.system))
        + u64::from(cur.nice.wrapping_sub(prev.nice));
    let idle = u64::from(cur.idle.wrapping_sub(prev.idle));
    let total = busy + idle;
    if total == 0 {
        return 0.0;
    }
    (busy as f64 / total as f64 * 100.0).clamp(0.0, 100.0) as f32
}

/// Holds the previous tick snapshot. The first sample only primes the baseline.
#[derive(Default)]
pub struct CpuMonitor {
    prev: Option<CpuTicks>,
}

impl CpuMonitor {
    pub fn sample(&mut self, host: &HostPort) -> Option<f32> {
        let cur = CpuTicks::from_sys(&host.cpu_load()?);
        Some(self.push(cur))
    }

    /// Feeds a snapshot and returns utilisation since the previous one.
    pub fn push(&mut self, cur: CpuTicks) -> f32 {
        let pct = self.prev.map_or(0.0, |prev| cpu_percent(prev, cur));
        self.prev = Some(cur);
        pct
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(user: u32, system: u32, idle: u32, nice: u32) -> CpuTicks {
        CpuTicks {
            user,
            system,
            idle,
            nice,
        }
    }

    #[test]
    fn delta_percentage() {
        let a = t(100, 50, 1000, 0);
        let b = t(130, 60, 1060, 0); // busy 40, idle 60
        assert!((cpu_percent(a, b) - 40.0).abs() < 1e-4);
    }

    #[test]
    fn nice_counts_as_busy() {
        let a = t(0, 0, 0, 0);
        let b = t(0, 0, 50, 50);
        assert!((cpu_percent(a, b) - 50.0).abs() < 1e-4);
    }

    #[test]
    fn first_sample_primes_baseline() {
        let mut m = CpuMonitor::default();
        assert_eq!(m.push(t(10, 10, 10, 0)), 0.0);
        assert!((m.push(t(20, 10, 20, 0)) - 50.0).abs() < 1e-4);
    }

    #[test]
    fn no_elapsed_time_is_zero() {
        let a = t(5, 5, 5, 5);
        assert_eq!(cpu_percent(a, a), 0.0);
    }

    #[test]
    fn counter_wraparound() {
        let a = t(u32::MAX - 9, 0, u32::MAX - 9, 0);
        let b = t(10, 0, 10, 0); // +20 busy, +20 idle across the wrap
        assert!((cpu_percent(a, b) - 50.0).abs() < 1e-4);
    }
}
