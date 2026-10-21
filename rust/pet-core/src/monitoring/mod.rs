//! Live system metrics. Pure scoring functions are separated from the syscalls so they
//! can be unit-tested with synthetic inputs.

pub mod cpu;
pub mod memory;

use crate::sys::HostPort;
use cpu::CpuMonitor;
use memory::{MemoryMonitor, PressureLevel};

/// One complete metrics sample, mirrored 1:1 by the C struct `PetMetrics`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Metrics {
    pub cpu_percent: f32,
    pub ram_used_percent: f32,
    pub pressure_score: f32,
    pub kernel_pressure_level: u8,
    pub ram_used_bytes: u64,
    pub ram_total_bytes: u64,
    pub swap_used_bytes: u64,
    pub compressed_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SampleError {
    /// A Mach or sysctl call failed; the sample is not trustworthy.
    System,
}

/// Owns everything needed to take samples: the host port and CPU tick baseline.
pub struct Monitor {
    host: HostPort,
    cpu: CpuMonitor,
    memory: MemoryMonitor,
}

impl Monitor {
    pub fn new() -> Self {
        let host = HostPort::new();
        let memory = MemoryMonitor::new(&host);
        Monitor {
            host,
            cpu: CpuMonitor::default(),
            memory,
        }
    }

    pub fn sample(&mut self) -> Result<Metrics, SampleError> {
        let cpu_percent = self.cpu.sample(&self.host).ok_or(SampleError::System)?;
        let mem = self.memory.sample(&self.host).ok_or(SampleError::System)?;
        Ok(Metrics {
            cpu_percent,
            ram_used_percent: mem.ram_used_percent,
            pressure_score: mem.pressure_score,
            kernel_pressure_level: mem.level as u8,
            ram_used_bytes: mem.ram_used_bytes,
            ram_total_bytes: mem.ram_total_bytes,
            swap_used_bytes: mem.swap_used_bytes,
            compressed_bytes: mem.compressed_bytes,
        })
    }

    /// Records a level delivered by a Dispatch memory-pressure source.
    pub fn note_pressure_event(&mut self, level: PressureLevel) {
        self.memory.note_pressure_event(level);
    }
}

impl Default for Monitor {
    fn default() -> Self {
        Self::new()
    }
}
