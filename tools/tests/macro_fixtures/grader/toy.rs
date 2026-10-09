//! An INVENTED grader function for the toy exercise ex15: what C 12's own
//! ft_create_elem is to a real module (tools/grader_lib.bzl), for a function
//! no subject has. The toy's harness calls it, so ex15's programs build only
//! where the macros link the library its contract's `linked` names.
#![no_std]

/// `int toy_base(int n)`: n, unchanged.
#[no_mangle]
pub extern "C" fn toy_base(n: i32) -> i32 {
    n
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
