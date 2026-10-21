//! Hand-written declarations for the handful of Mach and sysctl APIs pet-core uses.
//! Layouts mirror <mach/host_info.h>, <mach/vm_statistics.h> and <sys/sysctl.h>.

#![allow(non_camel_case_types)]

use std::ffi::{c_char, c_int, c_uint, c_void, CStr};
use std::mem::{size_of, MaybeUninit};

pub type kern_return_t = c_int;
pub type mach_port_t = c_uint;
pub type natural_t = c_uint;
pub type integer_t = c_int;
pub type mach_msg_type_number_t = natural_t;
pub type vm_size_t = usize;

pub const KERN_SUCCESS: kern_return_t = 0;

pub const HOST_CPU_LOAD_INFO: c_int = 3;
pub const HOST_VM_INFO64: c_int = 4;

pub const CPU_STATE_USER: usize = 0;
pub const CPU_STATE_SYSTEM: usize = 1;
pub const CPU_STATE_IDLE: usize = 2;
pub const CPU_STATE_NICE: usize = 3;
pub const CPU_STATE_MAX: usize = 4;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct host_cpu_load_info {
    pub cpu_ticks: [natural_t; CPU_STATE_MAX],
}

#[repr(C, align(8))]
#[derive(Clone, Copy, Default)]
pub struct vm_statistics64 {
    pub free_count: natural_t,
    pub active_count: natural_t,
    pub inactive_count: natural_t,
    pub wire_count: natural_t,
    pub zero_fill_count: u64,
    pub reactivations: u64,
    pub pageins: u64,
    pub pageouts: u64,
    pub faults: u64,
    pub cow_faults: u64,
    pub lookups: u64,
    pub hits: u64,
    pub purges: u64,
    pub purgeable_count: natural_t,
    pub speculative_count: natural_t,
    pub decompressions: u64,
    pub compressions: u64,
    pub swapins: u64,
    pub swapouts: u64,
    pub compressor_page_count: natural_t,
    pub throttled_count: natural_t,
    pub external_page_count: natural_t,
    pub internal_page_count: natural_t,
    pub total_uncompressed_pages_in_compressor: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct xsw_usage {
    pub xsu_total: u64,
    pub xsu_avail: u64,
    pub xsu_used: u64,
    pub xsu_pagesize: u32,
    pub xsu_encrypted: c_int,
}

extern "C" {
    static mach_task_self_: mach_port_t;

    fn mach_host_self() -> mach_port_t;
    fn mach_port_deallocate(task: mach_port_t, name: mach_port_t) -> kern_return_t;
    fn host_statistics(
        host: mach_port_t,
        flavor: c_int,
        info: *mut integer_t,
        count: *mut mach_msg_type_number_t,
    ) -> kern_return_t;
    fn host_statistics64(
        host: mach_port_t,
        flavor: c_int,
        info: *mut integer_t,
        count: *mut mach_msg_type_number_t,
    ) -> kern_return_t;
    fn host_page_size(host: mach_port_t, out: *mut vm_size_t) -> kern_return_t;
    fn sysctlbyname(
        name: *const c_char,
        oldp: *mut c_void,
        oldlenp: *mut usize,
        newp: *mut c_void,
        newlen: usize,
    ) -> c_int;
}

/// An owned send right to the host port, released on drop.
///
/// `mach_host_self()` adds a user reference on every call, so we take it once per engine.
pub struct HostPort(mach_port_t);

impl HostPort {
    pub fn new() -> Self {
        // SAFETY: mach_host_self has no preconditions.
        HostPort(unsafe { mach_host_self() })
    }

    pub fn cpu_load(&self) -> Option<host_cpu_load_info> {
        let mut info = host_cpu_load_info::default();
        let mut count = (size_of::<host_cpu_load_info>() / size_of::<integer_t>()) as natural_t;
        // SAFETY: `info` is a correctly sized, writable host_cpu_load_info and `count`
        // holds its size in integer_t units, as host_statistics requires.
        let kr = unsafe {
            host_statistics(
                self.0,
                HOST_CPU_LOAD_INFO,
                &mut info as *mut _ as *mut integer_t,
                &mut count,
            )
        };
        (kr == KERN_SUCCESS).then_some(info)
    }

    pub fn vm_stats(&self) -> Option<vm_statistics64> {
        let mut info = vm_statistics64::default();
        let mut count = (size_of::<vm_statistics64>() / size_of::<integer_t>()) as natural_t;
        // SAFETY: as above, for vm_statistics64 / HOST_VM_INFO64.
        let kr = unsafe {
            host_statistics64(
                self.0,
                HOST_VM_INFO64,
                &mut info as *mut _ as *mut integer_t,
                &mut count,
            )
        };
        (kr == KERN_SUCCESS).then_some(info)
    }

    pub fn page_size(&self) -> Option<u64> {
        let mut size: vm_size_t = 0;
        // SAFETY: `size` is a valid out-pointer.
        let kr = unsafe { host_page_size(self.0, &mut size) };
        (kr == KERN_SUCCESS && size > 0).then_some(size as u64)
    }
}

impl Default for HostPort {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for HostPort {
    fn drop(&mut self) {
        // SAFETY: we own exactly one user reference to this port, taken in `new`.
        unsafe {
            mach_port_deallocate(mach_task_self_, self.0);
        }
    }
}

/// Reads a fixed-size value with `sysctlbyname`. Returns `None` on error or size mismatch.
pub fn sysctl_value<T: Copy>(name: &CStr) -> Option<T> {
    let mut value = MaybeUninit::<T>::zeroed();
    let mut len = size_of::<T>();
    // SAFETY: `value` provides `len` writable bytes; the kernel writes at most `len`.
    let rc = unsafe {
        sysctlbyname(
            name.as_ptr(),
            value.as_mut_ptr() as *mut c_void,
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc == 0 && len == size_of::<T>() {
        // SAFETY: the kernel filled all size_of::<T>() bytes and T is plain data.
        Some(unsafe { value.assume_init() })
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn struct_sizes_match_sdk() {
        // We declare the rev1 prefix of vm_statistics64 (HOST_VM_INFO64_REV1_COUNT = 38).
        // The kernel fills only `count` integers, so newer SDK fields are simply omitted.
        assert_eq!(size_of::<vm_statistics64>(), 152);
        assert_eq!(size_of::<host_cpu_load_info>(), 16);
        assert_eq!(size_of::<xsw_usage>(), 32);
    }
}
