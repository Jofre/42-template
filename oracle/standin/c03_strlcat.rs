//! Two stand-ins for C 03 ex05's function, for one arm of
//! //tools/tests:selftest_slow and nothing else.
//!
//! The manual page the subject sends to (man 3bsd strlcat) fixes what is
//! appended (at most size - strlen(dst) - 1 bytes of src), the terminator
//! after it, no terminator when dst holds none within size, and the return
//! value. It says nothing of the bytes between the new terminator and size.
//! So the exercise's output fixture must pass an answer that leaves them as
//! they were and one that writes them, and the arm builds that fixture over
//! each of these two, which differ there and only there. They are exported under names of their own, never the
//! exercise's: the arm compiles the fixture with its call renamed to one of
//! them (-D).
//!
//! Grader-side only, and deliberately not C: a C copy outside the turn-in
//! folder would be the exercise's answer outside the zone (AGENTS.md section
//! 0). Compiled like the grader's own functions under grader/, by
//! grader_library() (tools/grader_lib.bzl): no std, no unwinding.
#![no_std]

/// How many bytes before `limit` are not 0, read from `s`.
///
/// # Safety
/// `s` points at `limit` readable bytes, or at a string that ends before.
unsafe fn len_within(s: *const u8, limit: usize) -> usize {
    let mut n = 0;
    while n < limit && *s.add(n) != 0 {
        n += 1;
    }
    n
}

/// What the page fixes, written into the first `size` bytes of `dst`: the
/// return value, and the index the terminator went to (None when dst holds
/// no terminator within size, where nothing is written). Raw writes, no
/// slices: an index the optimiser cannot prove in bounds would link a panic
/// path from core, and with it a personality routine no C link provides.
///
/// # Safety
/// `src` is NUL-terminated and `dst` holds at least `size` bytes.
unsafe fn fixed(dst: *mut u8, src: *const u8, size: usize) -> (usize, Option<usize>) {
    let dlen = len_within(dst, size);
    let slen = len_within(src, usize::MAX);
    if dlen == size {
        return (size + slen, None);
    }
    let room = size - dlen - 1;
    let kept = if slen < room { slen } else { room };
    let mut i = 0;
    while i < kept {
        *dst.add(dlen + i) = *src.add(i);
        i += 1;
    }
    *dst.add(dlen + kept) = 0;
    (dlen + slen, Some(dlen + kept))
}

/// The bytes between the terminator and size left as they were.
///
/// # Safety
/// As `fixed`.
#[no_mangle]
pub unsafe extern "C" fn standin_strlcat_tail_kept(dst: *mut u8, src: *const u8, size: u32) -> u32 {
    fixed(dst, src, size as usize).0 as u32
}

/// The bytes between the terminator and size all set to 0.
///
/// # Safety
/// As `fixed`.
#[no_mangle]
pub unsafe extern "C" fn standin_strlcat_tail_zeroed(dst: *mut u8, src: *const u8, size: u32) -> u32 {
    let (ret, nul) = fixed(dst, src, size as usize);
    if let Some(mut at) = nul {
        while at < size as usize {
            *dst.add(at) = 0;
            at += 1;
        }
    }
    ret as u32
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
