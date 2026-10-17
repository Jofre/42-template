//! Two stand-ins for C 02 ex10's function, for one arm of
//! //tools/tests:selftest_slow and nothing else.
//!
//! The manual page the subject sends to (man 3bsd strlcpy) fixes three
//! things: the bytes of src that fit in size - 1, then a terminator, written
//! into the first `size` bytes of dst, nothing written at all when size is 0,
//! and the length of src returned. It says nothing of the bytes between the
//! terminator and size. So the exercise's output fixture must pass an answer
//! that leaves them as they were and one that writes them, and the arm builds
//! that fixture over each of these two, which differ there and only there.
//! They are exported under names of their own, never the exercise's: the arm
//! compiles the fixture with its call renamed to one of them (-D).
//!
//! Grader-side only, and deliberately not C: a C copy outside the turn-in
//! folder would be the exercise's answer outside the zone (AGENTS.md section
//! 0). Compiled like the grader's own functions under grader/, by
//! grader_library() (tools/grader_lib.bzl): no std, no unwinding.
#![no_std]

use core::slice::{from_raw_parts, from_raw_parts_mut};

/// The string at `s`, without its terminator.
///
/// # Safety
/// `s` points at a NUL-terminated string.
unsafe fn c_str<'a>(s: *const u8) -> &'a [u8] {
    let mut n = 0;
    while *s.add(n) != 0 {
        n += 1;
    }
    from_raw_parts(s, n)
}

/// What the page fixes, written into the first `size` bytes of `dst`: the
/// length of src, and the index the terminator went to (None for size 0,
/// where nothing is written).
///
/// # Safety
/// `src` is NUL-terminated and `dst` holds at least `size` bytes.
unsafe fn fixed(dst: *mut u8, src: *const u8, size: usize) -> (usize, Option<usize>) {
    let text = c_str(src);
    if size == 0 {
        return (text.len(), None);
    }
    let kept = &text[..text.len().min(size - 1)];
    let window = from_raw_parts_mut(dst, size);
    window[..kept.len()].copy_from_slice(kept);
    window[kept.len()] = 0;
    (text.len(), Some(kept.len()))
}

/// The bytes between the terminator and size left as they were.
///
/// # Safety
/// As `fixed`.
#[no_mangle]
pub unsafe extern "C" fn standin_strlcpy_tail_kept(dst: *mut u8, src: *const u8, size: u32) -> u32 {
    fixed(dst, src, size as usize).0 as u32
}

/// The bytes between the terminator and size all set to 0.
///
/// # Safety
/// As `fixed`.
#[no_mangle]
pub unsafe extern "C" fn standin_strlcpy_tail_zeroed(dst: *mut u8, src: *const u8, size: u32) -> u32 {
    let (len, nul) = fixed(dst, src, size as usize);
    if let Some(at) = nul {
        from_raw_parts_mut(dst, size as usize)[at..].fill(0);
    }
    len as u32
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
