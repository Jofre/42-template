//! The grader's own `ft_create_elem`, for C 12 exercise 01 onward.
//!
//! The subject: "From exercise 01 onward, we'll use our ft_create_elem". So
//! every program the harness builds for ex01..ex17 links this copy, never the
//! student's ex00, and a bug in ex00 stays ex00's (finding 136). It is built on
//! the structure the subject prints, so a header that lays `t_list` out any
//! other way shows up as the wrong answer it would be at the grader (finding
//! 132), and the prototype layer says why (tests/layout/ft_list.h).
//!
//! Grader-side only, and deliberately not C: see tools/grader_lib.bzl for why,
//! and for how it is compiled (x86_64 and i686, no std, no unwinding).
#![no_std]

use core::ffi::c_void;
use core::ptr::null_mut;

/// `t_list` as the subject prints it: `next`, then `data`.
#[repr(C)]
pub struct TList {
    pub next: *mut TList,
    pub data: *mut c_void,
}

extern "C" {
    fn malloc(size: usize) -> *mut c_void;
}

/// `t_list *ft_create_elem(void *data)`: a new element holding `data`, whose
/// `next` is NULL; NULL when malloc refuses.
///
/// # Safety
/// Called from C with any pointer; it is stored, never read.
#[no_mangle]
pub unsafe extern "C" fn ft_create_elem(data: *mut c_void) -> *mut TList {
    let elem = malloc(core::mem::size_of::<TList>()) as *mut TList;
    if !elem.is_null() {
        elem.write(TList { next: null_mut(), data });
    }
    elem
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
