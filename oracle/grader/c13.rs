//! The grader's own `btree_create_node`, for C 13 exercise 01 onward.
//!
//! The subject: "From exercise 01 onward, we'll use our btree_create_node". So
//! every program the harness builds for ex01..ex07 links this copy, never the
//! student's ex00, and a bug in ex00 stays ex00's (finding 136). It is built on
//! the structure the subject prints, so a header that lays `t_btree` out any
//! other way shows up as the wrong answer it would be at the grader (finding
//! 132), and the prototype layer says why (tests/layout/ft_btree.h).
//!
//! Grader-side only, and deliberately not C: see tools/grader_lib.bzl for why,
//! and for how it is compiled (x86_64 and i686, no std, no unwinding).
#![no_std]

use core::ffi::c_void;
use core::ptr::null_mut;

/// `t_btree` as the subject prints it: `left`, `right`, then `item`.
#[repr(C)]
pub struct TBtree {
    pub left: *mut TBtree,
    pub right: *mut TBtree,
    pub item: *mut c_void,
}

extern "C" {
    fn malloc(size: usize) -> *mut c_void;
}

/// `t_btree *btree_create_node(void *item)`: a new node holding `item`, with
/// both children NULL; NULL when malloc refuses.
///
/// # Safety
/// Called from C with any pointer; it is stored, never read.
#[no_mangle]
pub unsafe extern "C" fn btree_create_node(item: *mut c_void) -> *mut TBtree {
    let node = malloc(core::mem::size_of::<TBtree>()) as *mut TBtree;
    if !node.is_null() {
        node.write(TBtree { left: null_mut(), right: null_mut(), item });
    }
    node
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
