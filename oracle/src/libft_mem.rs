//! Libft references: the memory functions of Part 1 (memset bzero memcpy
//! memmove memchr memcmp) and calloc, Common Core milestone 0.
//!
//! Each reference is the man page's definition, held in check() to a second
//! construction that shares none of its code (a byte loop on one side, a std
//! slice method or a wider integer on the other). Buffers travel as lowercase
//! hex and every buffer field is a whole block: the reader allocates it at
//! exactly its own length, so a function that touches a byte past it is out of
//! bounds under ASan. Every number is decimal. A trailing `1` says the function
//! must return the pointer it was handed (`s` or `dest`): the reader prints
//! `ret == arg`.
//!
//! Line formats (input fields, then the reference):
//!   libft_memset           <hexBefore>\t<c>\t<n>\t<hexAfter>\t1
//!                          c in 0..=255 only, the values every reading agrees on
//!   libft_memset_readings  (the same), c OUTSIDE 0..=255 only, and n never 0
//!                          (with n 0 every reading leaves the block as it
//!                          was): the man page says "the constant byte c" and
//!                          no more, so the answer here is this harness's
//!                          reading, c converted to unsigned char (its low byte)
//!   libft_bzero            <hexBefore>\t<n>\t<hexAfter>
//!   libft_memcpy           <hexSrc>\t<n>\t<hexDestBefore>\t<hexDestAfter>\t1
//!                          src and dest are separate blocks: never overlapping
//!   libft_memmove          <hexBuf>\t<srcOff>\t<dstOff>\t<n>\t<hexBufAfter>\t1
//!                          src = buf+srcOff, dest = buf+dstOff, one block:
//!                          both overlap directions, dst == src, disjoint
//!   libft_memchr           <hexBuf>\t<c>\t<n>\t<off|NULL>
//!                          c over -512..=767 and the int extremes; man memchr
//!                          settles it ("Both c and the bytes ... are
//!                          interpreted as unsigned char"); off is the match's
//!                          offset from s
//!   libft_memcmp           <hexA>\t<hexB>\t<n>\t<-1|0|1>
//!                          the SIGN only, which is all man memcmp promises
//!   libft_calloc           <nmemb>\t<size>\t<zeroed|nonnull|NULL>
//!                          zeroed: a block of nmemb*size bytes, every one 0;
//!                          nonnull: nmemb or size is 0, a unique pointer that
//!                          can be passed to free() (the subject's own rule,
//!                          p. 8); NULL: nmemb*size overflows a 64-bit size_t
//!                          (man 3 calloc). Never a large size that does not
//!                          overflow: every zeroed product is at most 1 MiB,
//!                          and every overflowing one wraps to at most 1 MiB or
//!                          past PTRDIFF_MAX, so an answer that forgets the
//!                          overflow asks for a small block or one malloc
//!                          refuses at once, never gigabytes.
//!
//! The buffers hold NUL and bytes above 0x7f throughout; every corpus holds an
//! n (and for calloc a product) past every round capacity (16, 64, 256, 1024,
//! 4096), within its first 200 lines.

use crate::common::{bench_lines, largest_dec, sink, to_hex, unhex, widest_hex, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
/// memset: the first n bytes of s set to c, as a byte. For c outside 0..=255
/// this is this harness's reading (libft_memset_readings), the low byte.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_memset(before: &[u8], c: i32, n: usize) -> Vec<u8> {
    let mut out = before.to_vec();
    let b = c as u8;
    for x in out.iter_mut().take(n) {
        *x = b;
    }
    out
}

/// bzero: the first n bytes of s set to '\0'.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_bzero(before: &[u8], n: usize) -> Vec<u8> {
    let mut out = before.to_vec();
    for x in out.iter_mut().take(n) {
        *x = 0;
    }
    out
}

/// memcpy: n bytes of src copied over the start of dest.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_memcpy(src: &[u8], n: usize, dest: &[u8]) -> Vec<u8> {
    let mut out = dest.to_vec();
    let mut i = 0;
    while i < n {
        out[i] = src[i];
        i += 1;
    }
    out
}

/// memmove, as man memmove defines it: "as though the bytes in src are first
/// copied into a temporary array that does not overlap src or dest, and the
/// bytes are then copied from the temporary array to dest".
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_memmove(buf: &[u8], src: usize, dst: usize, n: usize) -> Vec<u8> {
    let tmp: Vec<u8> = buf[src..src + n].to_vec();
    let mut out = buf.to_vec();
    for (i, &b) in tmp.iter().enumerate() {
        out[dst + i] = b;
    }
    out
}

/// memchr: the offset of the first of the n bytes equal to c as an unsigned
/// char, or None.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_memchr(buf: &[u8], c: i32, n: usize) -> Option<usize> {
    let want = c as u8;
    let mut i = 0;
    while i < n {
        if buf[i] == want {
            return Some(i);
        }
        i += 1;
    }
    None
}

/// memcmp's sign: that of the difference of the first pair of the n bytes,
/// as unsigned chars, that differ; 0 when none does (and when n is 0).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_memcmp(a: &[u8], b: &[u8], n: usize) -> i32 {
    let mut i = 0;
    while i < n {
        if a[i] != b[i] {
            return if a[i] < b[i] { -1 } else { 1 };
        }
        i += 1;
    }
    0
}

/// calloc on a 64-bit size_t: NULL when nmemb*size overflows (man 3 calloc:
/// it "returns an error", and "On error, these functions return NULL");
/// nonnull when either is 0 (the subject's rule); zeroed otherwise.
///
/// Its domain is what gen_calloc emits: a product that overflows, a zero, or
/// a product of at most 1 MiB (`calloc_in_domain`). A product that does not
/// overflow but is past 1 MiB is outside it: a real calloc may well return
/// NULL there ("ENOMEM Out of memory"), so "zeroed" is no answer for it, and
/// check() asserts only the overflow predicate on such a pair, never a label.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_calloc(nmemb: u64, size: u64) -> &'static str {
    if calloc_overflows(nmemb, size) {
        "NULL"
    } else if nmemb == 0 || size == 0 {
        "nonnull"
    } else {
        "zeroed"
    }
}

/// Whether nmemb*size overflows a 64-bit size_t: the case man 3 calloc
/// names, which the true product past SIZE_MAX defines.
fn calloc_overflows(nmemb: u64, size: u64) -> bool {
    nmemb.checked_mul(size).is_none()
}

/// Whether o_calloc's label is an answer for this pair: an overflow, a zero,
/// or a block of at most 1 MiB.
fn calloc_in_domain(nmemb: u64, size: u64) -> bool {
    nmemb.checked_mul(size).map_or(true, |p| p <= MIB)
}

// ------------------------------------------------------------- helpers
/// The most bytes a zeroed calloc answer asks for, and the most an overflow
/// may wrap to on its small side.
const MIB: u64 = 1 << 20;

/// Whether every reading agrees on memset's answer: a c that is a byte.
fn memset_settled(c: i32) -> bool {
    (0..=255).contains(&c)
}

/// The lengths of the capacity cases, past every round capacity.
const BIG: [usize; 2] = [4097, 5000];

/// `n` bytes of every value, NUL and those above 0x7f included, drawn from a
/// seed of the case's own so a corpus's head is the same whatever its seed.
fn long_bytes(n: usize, seed: u64) -> Vec<u8> {
    let mut rng = Rng::new(seed);
    (0..n).map(|_| rng.next_u64() as u8).collect()
}

/// A short block for the random tails, in one of four textures: any byte,
/// letters, NULs among high bytes, and the boundary bytes alone.
fn rand_bytes(rng: &mut Rng, len: usize) -> Vec<u8> {
    let kind = rng.below(4);
    (0..len)
        .map(|_| match kind {
            0 => rng.next_u64() as u8,
            1 => b'a' + rng.below(26) as u8,
            2 => {
                if rng.below(3) == 0 {
                    0
                } else {
                    0x80 + rng.below(128) as u8
                }
            }
            _ => [0u8, 0x01, 0x7f, 0x80, 0xff, b'X'][rng.below(6)],
        })
        .collect()
}

/// A dirty block for a write target: never all zero, so a write of zeros shows.
fn dirty(len: usize) -> Vec<u8> {
    vec![b'X'; len]
}

/// A c outside 0..=255 for memset's readings corpus: just past either end,
/// the next 256 on either side, or any int.
fn c_outside(rng: &mut Rng) -> i32 {
    loop {
        let c = match rng.below(4) {
            0 => 256 + rng.below(512) as i32,
            1 => -1 - rng.below(512) as i32,
            2 => rng.next_u64() as i32,
            _ => [256, -1, -256, 511, 512, -255, i32::MIN, i32::MAX][rng.below(8)],
        };
        if !memset_settled(c) {
            return c;
        }
    }
}

/// An overflowing (nmemb, size) pair, built backwards from what it wraps to:
/// nmemb*size == k*2^64 + w, with 1 <= k < a, so the true product is past
/// SIZE_MAX and the wrapped one is w: the first value at or past w0 that
/// makes k*2^64 + w a multiple of a, so below w0 + a (which must not pass
/// SIZE_MAX).
fn overflow_small(a: u64, k: u64, w0: u64) -> (u64, u64) {
    let full = ((k as u128) << 64) + w0 as u128;
    let w = w0 as u128 + (a as u128 - full % a as u128) % a as u128;
    let b = (((k as u128) << 64) + w) / a as u128;
    (a, b as u64)
}

// ------------------------------------------------------------- generators
fn gen_memset<W: Write>(w: &mut W, seed: u64, count: usize, readings: bool) {
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    let emit = |w: &mut W, before: &[u8], c: i32, n: usize, done: &mut usize| {
        if *done < count {
            let _ = writeln!(w, "{}\t{}\t{}\t{}\t1", to_hex(before), c, n, to_hex(&o_memset(before, c, n)));
            *done += 1;
        }
    };
    if !readings {
        // Hand corners: part of a block, n 0, NUL, a high byte, the whole
        // block, an empty block, a c the block already holds.
        let x = dirty(10);
        for (c, n) in [(b'a' as i32, 5usize), (b'a' as i32, 0), (0, 10), (0xe9, 3), (0xff, 10), (0x80, 1), (b'X' as i32, 4)] {
            emit(w, &x, c, n, &mut done);
        }
        emit(w, &[], b'a' as i32, 0, &mut done);
        emit(w, &[0, 0, 0], b'z' as i32, 2, &mut done);
        // Capacity cases: n 5000 into 5001 bytes (the last one untouched),
        // and a whole block of 4097.
        emit(w, &long_bytes(BIG[1] + 1, 5001), b'a' as i32, BIG[1], &mut done);
        emit(w, &long_bytes(BIG[0], 4097), 0x80, BIG[0], &mut done);
        // Every byte value once.
        for c in 0..=255 {
            emit(w, &[0x55, 0xaa, 0x00, 0xff], c, 3, &mut done);
        }
    } else {
        // Hand corners: one past either end, a letter plus 256, a high byte
        // minus 256, the int extremes.
        let x = dirty(10);
        for c in [256, 256 + b'a' as i32, -1, -23, -256, -255, -129, -128, 511, 512, 0x100ff, i32::MIN, i32::MIN + 1, i32::MAX] {
            emit(w, &x, c, 5, &mut done);
        }
        emit(w, &long_bytes(BIG[1] + 1, 5001), 256 + b'a' as i32, BIG[1], &mut done);
        emit(w, &long_bytes(BIG[0], 4097), -1, BIG[0], &mut done);
    }
    while done < count {
        // The readings tail never draws n 0, where every reading agrees.
        let len = if readings { 1 + rng.below(47) } else { rng.below(48) };
        let before = rand_bytes(&mut rng, len);
        let n = if readings { 1 + rng.below(len) } else { rng.below(len + 1) };
        let c = if readings { c_outside(&mut rng) } else { rng.below(256) as i32 };
        emit(w, &before, c, n, &mut done);
    }
}

fn gen_bzero<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    let emit = |w: &mut W, before: &[u8], n: usize, done: &mut usize| {
        if *done < count {
            let _ = writeln!(w, "{}\t{}\t{}", to_hex(before), n, to_hex(&o_bzero(before, n)));
            *done += 1;
        }
    };
    let x = dirty(10);
    for n in [5usize, 0, 1, 10] {
        emit(w, &x, n, &mut done);
    }
    emit(w, &[], 0, &mut done);
    emit(w, &[0x80, 0xff, 0x7f, 0x01], 3, &mut done);
    emit(w, &[0, 0, 0], 3, &mut done);
    emit(w, &long_bytes(BIG[1] + 1, 5001), BIG[1], &mut done);
    emit(w, &long_bytes(BIG[0], 4097), BIG[0], &mut done);
    while done < count {
        let len = rng.below(48);
        let before = rand_bytes(&mut rng, len);
        let n = rng.below(len + 1);
        emit(w, &before, n, &mut done);
    }
}

fn gen_memcpy<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    let emit = |w: &mut W, src: &[u8], n: usize, dest: &[u8], done: &mut usize| {
        if *done < count {
            let _ = writeln!(w, "{}\t{}\t{}\t{}\t1", to_hex(src), n, to_hex(dest), to_hex(&o_memcpy(src, n, dest)));
            *done += 1;
        }
    };
    // Hand corners: a word into a larger block, n 0, embedded NULs (a copy
    // that stops at one is wrong), high bytes, a src longer than n, blocks
    // of exactly n, an empty pair.
    emit(w, b"Hello", 5, &dirty(10), &mut done);
    emit(w, b"Hello", 0, &dirty(10), &mut done);
    emit(w, b"a\0b", 3, &dirty(5), &mut done);
    emit(w, &[0x80, 0xff, 0xe9, 0x00, 0x7f], 5, &dirty(5), &mut done);
    emit(w, b"Hello, world", 5, &dirty(8), &mut done);
    emit(w, b"\0\0\0", 2, &dirty(2), &mut done);
    emit(w, &[], 0, &[], &mut done);
    // Capacity cases: 5000 bytes into 5001, and 4097 into exactly 4097.
    emit(w, &long_bytes(BIG[1], 5000), BIG[1], &dirty(BIG[1] + 1), &mut done);
    emit(w, &long_bytes(BIG[0], 4097), BIG[0], &long_bytes(BIG[0], 4098), &mut done);
    while done < count {
        let n = rng.below(48);
        let sl = n + rng.below(4);
        let src = rand_bytes(&mut rng, sl);
        let dl = n + rng.below(4);
        let dest = rand_bytes(&mut rng, dl);
        emit(w, &src, n, &dest, &mut done);
    }
}

fn gen_memmove<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    let emit = |w: &mut W, buf: &[u8], src: usize, dst: usize, n: usize, done: &mut usize| {
        if *done < count {
            let _ = writeln!(
                w,
                "{}\t{}\t{}\t{}\t{}\t1",
                to_hex(buf),
                src,
                dst,
                n,
                to_hex(&o_memmove(buf, src, dst, n))
            );
            *done += 1;
        }
    };
    // Hand corners on "123456789": dest after src and overlapping (a forward
    // byte copy smears), dest before src and overlapping (a backward one
    // does), dst == src, overlap by all but one byte either way, disjoint,
    // n 0; then embedded NULs and high bytes, which a copy that stops at a
    // NUL or sign-extends gets wrong.
    let d: &[u8] = b"123456789";
    for (src, dst, n) in [(0usize, 2usize, 5usize), (2, 0, 5), (3, 3, 4), (0, 0, 9), (0, 1, 8), (1, 0, 8), (0, 5, 4), (5, 0, 4), (1, 5, 0)] {
        emit(w, d, src, dst, n, &mut done);
    }
    let z: &[u8] = &[b'a', 0, 0x80, 0, 0xff, 0, b'z', 0];
    emit(w, z, 0, 2, 6, &mut done);
    emit(w, z, 2, 0, 6, &mut done);
    emit(w, &[], 0, 0, 0, &mut done);
    // Capacity cases: 5000 bytes shifted by 100 each way, and 4097 shifted by
    // one each way, every one overlapping.
    let big = long_bytes(BIG[1] + 100, 5100);
    emit(w, &big, 0, 100, BIG[1], &mut done);
    emit(w, &big, 100, 0, BIG[1], &mut done);
    let b2 = long_bytes(BIG[0] + 1, 4098);
    emit(w, &b2, 0, 1, BIG[0], &mut done);
    emit(w, &b2, 1, 0, BIG[0], &mut done);
    while done < count {
        let len = rng.below(48);
        let buf = rand_bytes(&mut rng, len);
        let n = rng.below(len + 1);
        let room = len - n;
        let src = rng.below(room + 1);
        // Mostly overlapping: dest within n of src on either side.
        let dst = if rng.below(4) == 0 || n == 0 {
            rng.below(room + 1)
        } else {
            let lo = src.saturating_sub(n - 1);
            let hi = (src + n - 1).min(room);
            lo + rng.below(hi - lo + 1)
        };
        emit(w, &buf, src, dst, n, &mut done);
    }
}

fn gen_memchr<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    let emit = |w: &mut W, buf: &[u8], c: i32, n: usize, done: &mut usize| {
        if *done < count {
            let r = match o_memchr(buf, c, n) {
                Some(o) => o.to_string(),
                None => "NULL".to_string(),
            };
            let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(buf), c, n, r);
            *done += 1;
        }
    };
    // Hand corners on "Hello\0World": past the NUL, the NUL itself, a match
    // just outside n and just inside, n 0, a byte that is absent; then c
    // outside 0..=255, which man memchr reads as an unsigned char.
    let hw: &[u8] = b"Hello\0World";
    for (c, n) in [(b'W' as i32, 11usize), (0, 11), (b'o' as i32, 4), (b'o' as i32, 5), (b'H' as i32, 0), (b'z' as i32, 11), (256 + b'H' as i32, 11), (-256, 11), (512, 11)] {
        emit(w, hw, c, n, &mut done);
    }
    emit(w, &[b'a', 0xe9], 0xe9, 2, &mut done);
    emit(w, &[b'a', 0xe9], -23, 2, &mut done);
    emit(w, &[b'a', b'b', 0], i32::MIN, 3, &mut done);
    emit(w, &[b'a', 0xff], i32::MAX, 2, &mut done);
    emit(w, &[b'a', 0xff], -1, 2, &mut done);
    emit(w, b"abcX", b'X' as i32, 3, &mut done);
    emit(w, &[], b'a' as i32, 0, &mut done);
    // Capacity cases: the only match at the last of 5000 bytes, found with n
    // 5000 and missed with 4999; and at the last of 4097.
    for (len, seed) in [(BIG[1], 5000u64), (BIG[0], 4097)] {
        let mut buf: Vec<u8> = long_bytes(len, seed).into_iter().map(|b| if b == b'*' { b'+' } else { b }).collect();
        buf[len - 1] = b'*';
        emit(w, &buf, b'*' as i32, len, &mut done);
        emit(w, &buf, b'*' as i32 - 512, len, &mut done);
        emit(w, &buf, b'*' as i32, len - 1, &mut done);
    }
    // Every c from -512 to 767 over a block holding each byte value once, in
    // an order that is not the byte's own: five ints name each byte.
    let perm: Vec<u8> = (0..=255u8).map(|i| i.wrapping_mul(167).wrapping_add(13)).collect();
    for c in -512..=767 {
        emit(w, &perm, c, 256, &mut done);
    }
    while done < count {
        let len = rng.below(48);
        let buf = rand_bytes(&mut rng, len);
        let n = rng.below(len + 1);
        // Mostly a byte the block holds, shifted by a multiple of 256.
        let base = if len > 0 && rng.below(4) != 0 { buf[rng.below(len)] as i32 } else { rng.below(256) as i32 };
        let c = base + 256 * (rng.below(4) as i32 - 2);
        emit(w, &buf, c, n, &mut done);
    }
}

fn gen_memcmp<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    let emit = |w: &mut W, a: &[u8], b: &[u8], n: usize, done: &mut usize| {
        if *done < count {
            let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(a), to_hex(b), n, o_memcmp(a, b, n));
            *done += 1;
        }
    };
    // Hand corners: equal, a last-byte difference inside and outside n, n 0
    // over different bytes, the high bytes an int of signed char reads as
    // negative, a difference after a NUL (where a string compare stops), and
    // after n.
    emit(w, b"abc", b"abc", 3, &mut done);
    emit(w, b"abc", b"abd", 3, &mut done);
    emit(w, b"abd", b"abc", 3, &mut done);
    emit(w, b"abc", b"abd", 2, &mut done);
    emit(w, b"a", b"b", 0, &mut done);
    emit(w, &[0x80], &[0x01], 1, &mut done);
    emit(w, &[0x01], &[0x80], 1, &mut done);
    emit(w, &[0xff], &[0x00], 1, &mut done);
    emit(w, &[0x00], &[0xff], 1, &mut done);
    emit(w, b"a\0b", b"a\0c", 3, &mut done);
    emit(w, b"ab\0x", b"ab\0y", 4, &mut done);
    emit(w, b"\0\0", b"\0\0", 2, &mut done);
    emit(w, b"abcX", b"abcY", 3, &mut done);
    emit(w, &[], &[], 0, &mut done);
    // Capacity cases: 5000 equal bytes, then a difference at the last of
    // 5000 either way, and at the last of 4097.
    let a = long_bytes(BIG[1], 5000);
    emit(w, &a, &a, BIG[1], &mut done);
    for (len, seed) in [(BIG[1], 5000u64), (BIG[0], 4097)] {
        let a = long_bytes(len, seed);
        let mut b = a.clone();
        b[len - 1] = a[len - 1].wrapping_add(1 + (a[len - 1] == 0xff) as u8);
        emit(w, &a, &b, len, &mut done);
        emit(w, &b, &a, len, &mut done);
        emit(w, &a, &b, len - 1, &mut done);
    }
    // Every byte value against 0x80 and against NUL, both ways round.
    for v in 0..=255u8 {
        emit(w, &[v], &[0x80], 1, &mut done);
        emit(w, &[0x00], &[v], 1, &mut done);
    }
    while done < count {
        let la = rng.below(40);
        let a = rand_bytes(&mut rng, la);
        let b = match rng.below(4) {
            0 => a.clone(),
            1 if la > 0 => {
                let mut b = a.clone();
                let i = rng.below(la);
                b[i] = rng.next_u64() as u8;
                b
            }
            _ => {
                let lb = rng.below(40);
                rand_bytes(&mut rng, lb)
            }
        };
        let n = rng.below(la.min(b.len()) + 1);
        emit(w, &a, &b, n, &mut done);
    }
}

fn gen_calloc<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    let emit = |w: &mut W, nmemb: u64, size: u64, done: &mut usize| {
        if *done < count {
            let _ = writeln!(w, "{}\t{}\t{}", nmemb, size, o_calloc(nmemb, size));
            *done += 1;
        }
    };
    let max = u64::MAX;
    let half = 1u64 << 63;
    // Hand corners: small blocks; blocks past every round capacity; each
    // zero (with the other at SIZE_MAX, where dividing by the zero to test
    // for overflow crashes); then overflows that wrap to 2, to 0, to 1 and
    // past PTRDIFF_MAX, each both ways round.
    for (a, b) in [
        (3u64, 4u64),
        (1, 1),
        (1, 5000),
        (5000, 1),
        (4097, 3),
        (3, 4097),
        (1024, 1024),
        (1, MIB),
        (0, 5),
        (5, 0),
        (0, 0),
        (0, max),
        (max, 0),
        (half + 1, 2),
        (2, half + 1),
        (1 << 32, 1 << 32),
        (half, 2),
        (1 << 62, 4),
        (max, max),
        (max, 2),
        (2, max),
        overflow_small(3, 1, 2),
        overflow_small(1000, 999, MIB - 1000),
    ] {
        emit(w, a, b, &mut done);
    }
    while done < count {
        let (a, b) = match rng.below(6) {
            // small blocks, most of them a few bytes, some up to 1 MiB
            0 | 1 => (1 + rng.below(64) as u64, 1 + rng.below(64) as u64),
            2 => (1 + rng.below(1024) as u64, 1 + rng.below(1024) as u64),
            // a zero beside any size
            3 => {
                let other = if rng.below(2) == 0 { rng.next_u64() } else { rng.below(100) as u64 };
                if rng.below(2) == 0 { (0, other) } else { (other, 0) }
            }
            // an overflow that wraps to at most 1 MiB
            4 => {
                let a = if rng.below(2) == 0 { 1u64 << (1 + rng.below(19)) } else { 2 + rng.below(999) as u64 };
                let k = 1 + rng.below((a - 1) as usize) as u64;
                let (x, y) = overflow_small(a, k, rng.below((MIB / 4) as usize) as u64);
                if rng.below(2) == 0 { (x, y) } else { (y, x) }
            }
            // an overflow that wraps past PTRDIFF_MAX
            _ => {
                let a = 2 + rng.below(999) as u64;
                let k = 1 + rng.below((a - 1) as usize) as u64;
                let (x, y) = overflow_small(a, k, half | (rng.next_u64() >> 2));
                if rng.below(2) == 0 { (x, y) } else { (y, x) }
            }
        };
        emit(w, a, b, &mut done);
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    let w = &mut io::BufWriter::new(io::stdout());
    match name {
        "libft_memset" => gen_memset(w, seed, count, false),
        "libft_memset_readings" => gen_memset(w, seed, count, true),
        "libft_bzero" => gen_bzero(w, seed, count),
        "libft_memcpy" => gen_memcpy(w, seed, count),
        "libft_memmove" => gen_memmove(w, seed, count),
        "libft_memchr" => gen_memchr(w, seed, count),
        "libft_memcmp" => gen_memcmp(w, seed, count),
        "libft_calloc" => gen_calloc(w, seed, count),
        _ => return false,
    }
    true
}

// ------------------------------------------------------------- self-check
/// One generator's corpus, written into memory.
fn corpus(g: fn(&mut Vec<u8>, u64, usize), seed: u64, count: usize) -> Vec<u8> {
    let mut v = Vec::new();
    g(&mut v, seed, count);
    v
}

/// A corpus's lines, split into fields. Every field is ASCII.
fn lines(c: &[u8]) -> Vec<Vec<String>> {
    String::from_utf8_lossy(c)
        .lines()
        .map(|l| l.split('\t').map(str::to_string).collect())
        .collect()
}

fn num<T: std::str::FromStr>(s: &str) -> Option<T> {
    s.parse::<T>().ok()
}

/// Self-check: hand-verified cases, properties, and the corpora read back.
/// Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;
    macro_rules! want {
        ($cond:expr, $msg:expr) => {
            if !($cond) {
                eprintln!("CHECK FAIL libft_mem {}", $msg);
                fails += 1;
            }
        };
    }

    // ---- hand tables, each from its man page ----
    // memset: "fills the first n bytes ... with the constant byte c" and
    // "returns a pointer to the memory area s" (the trailing 1).
    want!(o_memset(b"XXXXXXXXXX", b'a' as i32, 5) == b"aaaaaXXXXX", "memset a n5");
    want!(o_memset(b"XXXXXXXXXX", b'a' as i32, 0) == b"XXXXXXXXXX", "memset n0");
    want!(o_memset(b"XXX", 0, 3) == b"\0\0\0", "memset NUL");
    want!(o_memset(b"XXX", 0xe9, 2) == b"\xe9\xe9X", "memset high byte");
    want!(o_memset(b"", b'a' as i32, 0).is_empty(), "memset empty");
    // this harness's reading for c outside 0..=255: its low byte
    want!(o_memset(b"XX", 256 + b'a' as i32, 2) == b"aa", "memset reading 256+a");
    want!(o_memset(b"XX", -1, 1) == b"\xffX", "memset reading -1");
    want!(o_memset(b"XX", i32::MIN, 2) == b"\0\0", "memset reading INT_MIN");
    want!(o_memset(b"XX", i32::MAX, 2) == b"\xff\xff", "memset reading INT_MAX");
    // bzero: "writing zeros (bytes containing '\0') to that area"
    want!(o_bzero(b"XXXXXXXXXX", 5) == b"\0\0\0\0\0XXXXX", "bzero n5");
    want!(o_bzero(b"XXX", 0) == b"XXX", "bzero n0");
    want!(o_bzero(b"\x80\xff", 2) == b"\0\0", "bzero high bytes");
    // memcpy: "copies n bytes from memory area src to memory area dest"
    want!(o_memcpy(b"Hello", 5, b"XXXXXXXXXX") == b"HelloXXXXX", "memcpy Hello");
    want!(o_memcpy(b"Hello", 0, b"XXX") == b"XXX", "memcpy n0");
    want!(o_memcpy(b"a\0b", 3, b"XXXX") == b"a\0bX", "memcpy past a NUL");
    want!(o_memcpy(b"Hello, world", 5, b"XXXXX") == b"Hello", "memcpy src longer than n");
    // memmove: the design's two shifts of "123456789", worked by hand
    want!(o_memmove(b"123456789", 0, 2, 5) == b"121234589", "memmove dest after src");
    want!(o_memmove(b"123456789", 2, 0, 5) == b"345676789", "memmove dest before src");
    want!(o_memmove(b"123456789", 3, 3, 4) == b"123456789", "memmove dst == src");
    want!(o_memmove(b"123456789", 0, 1, 8) == b"112345678", "memmove right by one");
    want!(o_memmove(b"123456789", 1, 0, 8) == b"234567899", "memmove left by one");
    want!(o_memmove(b"123456789", 1, 5, 0) == b"123456789", "memmove n0");
    // memchr: "the first instance of c", "interpreted as unsigned char", NULL
    // "if the character does not occur in the given memory area"
    let hw: &[u8] = b"Hello\0World";
    want!(o_memchr(hw, b'W' as i32, 11) == Some(6), "memchr past the NUL");
    want!(o_memchr(hw, 0, 11) == Some(5), "memchr the NUL");
    want!(o_memchr(hw, b'o' as i32, 4).is_none(), "memchr o n4");
    want!(o_memchr(hw, b'o' as i32, 5) == Some(4), "memchr o n5");
    want!(o_memchr(hw, b'l' as i32, 11) == Some(2), "memchr first of two");
    want!(o_memchr(hw, b'H' as i32, 0).is_none(), "memchr n0");
    want!(o_memchr(b"a\xe9", 0xe9, 2) == Some(1), "memchr 233");
    want!(o_memchr(b"a\xe9", -23, 2) == Some(1), "memchr -23");
    want!(o_memchr(hw, 256 + b'H' as i32, 11) == Some(0), "memchr 256+H");
    want!(o_memchr(hw, -256, 11) == Some(5), "memchr -256 is NUL");
    want!(o_memchr(b"ab\0", i32::MIN, 3) == Some(2), "memchr INT_MIN is NUL");
    want!(o_memchr(b"a\xff", i32::MAX, 2) == Some(1), "memchr INT_MAX is 0xff");
    // memcmp: the sign of "the first pair of bytes (interpreted as unsigned
    // char) that differ"; "If n is zero, the return value is zero."
    want!(o_memcmp(b"abc", b"abc", 3) == 0, "memcmp equal");
    want!(o_memcmp(b"abc", b"abd", 3) == -1, "memcmp abc abd");
    want!(o_memcmp(b"abc", b"abd", 2) == 0, "memcmp abc abd n2");
    want!(o_memcmp(b"a", b"b", 0) == 0, "memcmp n0");
    want!(o_memcmp(b"\x80", b"\x01", 1) == 1, "memcmp 0x80 0x01");
    want!(o_memcmp(b"a\0b", b"a\0c", 3) == -1, "memcmp past a NUL");
    want!(o_memcmp(b"\xff", b"\0", 1) == 1, "memcmp 0xff NUL");
    want!(o_memcmp(b"abcX", b"abcY", 3) == 0, "memcmp difference after n");
    // calloc: "The memory is set to zero"; the subject's rule for a zero
    // nmemb or size; "If the multiplication of nmemb and size would result
    // in integer overflow, then calloc() returns an error" and "On error,
    // these functions return NULL".
    want!(o_calloc(3, 4) == "zeroed" && o_calloc(1, MIB) == "zeroed", "calloc small");
    want!(o_calloc(0, 5) == "nonnull" && o_calloc(5, 0) == "nonnull" && o_calloc(0, 0) == "nonnull", "calloc zero");
    want!(o_calloc(0, u64::MAX) == "nonnull" && o_calloc(u64::MAX, 0) == "nonnull", "calloc zero beside SIZE_MAX");
    want!(o_calloc((1 << 63) + 1, 2) == "NULL", "calloc wraps to 2");
    want!(o_calloc(1 << 32, 1 << 32) == "NULL", "calloc wraps to 0");
    want!(o_calloc(u64::MAX, u64::MAX) == "NULL", "calloc wraps to 1");
    // Outside o_calloc's domain (no overflow, past 1 MiB) only the overflow
    // predicate is asserted: a real calloc may return NULL there for want of
    // memory, so no label is right for it.
    want!(!calloc_in_domain(1 << 32, (1 << 32) - 1), "calloc just under SIZE_MAX is outside the domain");
    want!(!calloc_overflows(1 << 32, (1 << 32) - 1), "calloc (2^32)*(2^32-1) is no overflow");
    want!(!calloc_overflows((1 << 32) + 1, (1 << 32) - 1), "calloc (2^32+1)*(2^32-1) == SIZE_MAX is no overflow");
    want!(calloc_overflows(1 << 32, 1 << 32) && calloc_overflows(u64::MAX, 2), "calloc overflow predicate");
    want!(calloc_in_domain(1, MIB) && !calloc_in_domain(1, MIB + 1) && calloc_in_domain(0, u64::MAX), "calloc domain edges");
    want!(overflow_small(3, 1, 2) == (3, 6_148_914_691_236_517_206), "overflow_small 3 1 2");

    // ---- properties over a seeded sweep, each against a second construction ----
    let mut rng = Rng::new(0x11bf7);
    for _ in 0..20000 {
        let len = rng.below(40);
        let buf = rand_bytes(&mut rng, len);
        let n = rng.below(len + 1);
        let c = rng.next_u64() as i32;
        // memset: [..n] is c mod 256, the rest untouched
        let m = o_memset(&buf, c, n);
        let byte = c.rem_euclid(256) as u8;
        want!(m.len() == len && m[..n].iter().all(|&x| x == byte) && m[n..] == buf[n..], "prop memset");
        want!(o_bzero(&buf, n) == o_memset(&buf, 0, n), "prop bzero is memset 0");
        // memcpy against copy_from_slice
        let dest = rand_bytes(&mut rng, len);
        let mut want_cpy = dest.clone();
        want_cpy[..n].copy_from_slice(&buf[..n]);
        want!(o_memcpy(&buf, n, &dest) == want_cpy, "prop memcpy");
        // memmove against copy_within, Rust's own overlapping copy
        let src = rng.below(len - n + 1);
        let dst = rng.below(len - n + 1);
        let mut want_mv = buf.clone();
        want_mv.copy_within(src..src + n, dst);
        want!(o_memmove(&buf, src, dst, n) == want_mv, "prop memmove");
        // memchr against position(), on c reduced by rem_euclid
        let cc = rng.below(1280) as i32 - 512;
        want!(o_memchr(&buf, cc, n) == buf[..n].iter().position(|&x| x == cc.rem_euclid(256) as u8), "prop memchr");
        // memcmp against slice ordering, and antisymmetric
        let other = if rng.below(2) == 0 { buf.clone() } else { rand_bytes(&mut rng, len) };
        let ord = match buf[..n].cmp(&other[..n]) {
            std::cmp::Ordering::Less => -1,
            std::cmp::Ordering::Equal => 0,
            std::cmp::Ordering::Greater => 1,
        };
        want!(o_memcmp(&buf, &other, n) == ord && o_memcmp(&other, &buf, n) == -ord, "prop memcmp");
        // calloc against the u128 product: over any pair, the overflow
        // predicate; inside o_calloc's domain, the label too.
        let (a, b) = (rng.next_u64() >> rng.below(64), rng.next_u64() >> rng.below(64));
        let p = a as u128 * b as u128;
        want!(calloc_overflows(a, b) == (p > u64::MAX as u128), format!("prop calloc overflow {} {}", a, b));
        want!(calloc_in_domain(a, b) == (p > u64::MAX as u128 || p <= MIB as u128), format!("prop calloc domain {} {}", a, b));
        if calloc_in_domain(a, b) {
            let cat = if p > u64::MAX as u128 { "NULL" } else if p == 0 { "nonnull" } else { "zeroed" };
            want!(o_calloc(a, b) == cat, format!("prop calloc {} {}", a, b));
        }
        // and a pair drawn inside the domain, every product at most 1 MiB
        let (a, b) = (rng.below(1025) as u64, rng.below(1025) as u64);
        let cat = if a * b == 0 { "nonnull" } else { "zeroed" };
        want!(calloc_in_domain(a, b) && o_calloc(a, b) == cat, format!("prop calloc in domain {} {}", a, b));
    }
    if fails > 0 {
        return fails;
    }

    // ---- the corpora, read back ----
    type G = fn(&mut Vec<u8>, u64, usize);
    let memset_plain: G = |w, s, c| gen_memset(w, s, c, false);
    let memset_readings: G = |w, s, c| gen_memset(w, s, c, true);
    // name, generator, fields per line, lines in its structured head
    let arms: [(&str, G, usize, usize); 8] = [
        ("libft_memset", memset_plain, 5, 9 + 2 + 256),
        ("libft_memset_readings", memset_readings, 5, 14 + 2),
        ("libft_bzero", gen_bzero, 3, 9),
        ("libft_memcpy", gen_memcpy, 5, 9),
        ("libft_memmove", gen_memmove, 6, 12 + 4),
        ("libft_memchr", gen_memchr, 4, 16 + 6 + 1280),
        ("libft_memcmp", gen_memcmp, 4, 14 + 7 + 512),
        ("libft_calloc", gen_calloc, 3, 23),
    ];
    for (name, g, nf, head_lines) in arms {
        // Deterministic for a seed, the head (hand corners and capacity
        // cases) the same whatever the seed, and the tail drawn from it.
        let a = corpus(g, 1, 3000);
        let ls = lines(&a);
        want!(a == corpus(g, 1, 3000), format!("{} is not deterministic", name));
        want!(a != corpus(g, 2, 3000), format!("{} ignores its seed", name));
        let other = lines(&corpus(g, 7, 3000));
        let same = ls.iter().zip(&other).take_while(|(x, y)| x == y).count();
        want!(same >= head_lines && same < 3000, format!("{} shares {} head lines across seeds, not {}", name, same, head_lines));
        want!(ls.len() == 3000, format!("{} wrote {} lines for 3000", name, ls.len()));
        want!(ls.iter().all(|l| l.len() == nf), format!("{} has a line without {} fields", name, nf));
        // Capacity: an n (or a product) past 4096 within the first 200 lines.
        let head = corpus(g, 1, 200);
        let n_field = match name {
            "libft_memset" | "libft_memset_readings" => 2,
            "libft_bzero" | "libft_memcpy" => 1,
            "libft_memmove" => 3,
            _ => 2,
        };
        if name == "libft_calloc" {
            let big = lines(&head).iter().any(|l| {
                o_calloc(num(&l[0]).unwrap_or(0), num(&l[1]).unwrap_or(0)) == "zeroed"
                    && num::<u64>(&l[0]).unwrap_or(0) * num::<u64>(&l[1]).unwrap_or(0) > 4096
            });
            want!(big, "libft_calloc holds no zeroed block past 4096 bytes in its head");
        } else {
            want!(largest_dec(&head, n_field) > 4096, format!("{} holds no n past 4096 in its head", name));
            want!(widest_hex(&head, 0) > 4096, format!("{} holds no block past 4096 bytes in its head", name));
        }
    }

    // Each line's answer, recomputed by the second constructions above, and
    // each corpus's own shape.
    let at = |l: &Vec<String>, k: usize| -> usize { num(&l[k]).unwrap_or(usize::MAX) };
    for (readings, g) in [(false, memset_plain), (true, memset_readings)] {
        let ls = lines(&corpus(g, 1, 3000));
        let mut cs = std::collections::BTreeSet::new();
        for l in &ls {
            let before = unhex(&l[0]);
            let c: i32 = num(&l[1]).unwrap_or(0);
            let n = at(l, 2);
            cs.insert(c);
            want!(memset_settled(c) != readings, format!("memset corpus (readings {}) holds c {}", readings, c));
            // n 0 leaves the block as it was under every reading: not open.
            want!(!readings || n > 0, format!("memset readings corpus holds n 0 ({:?} {})", &l[0], c));
            let ok = n <= before.len() && {
                let mut m = before.clone();
                m[..n].fill(c.rem_euclid(256) as u8);
                unhex(&l[3]) == m
            };
            want!(ok && l[4] == "1", format!("memset line {:?} {} {}", &l[0], c, n));
        }
        if !readings {
            want!((0..=255).all(|c| cs.contains(&c)), "memset corpus lacks a byte value");
        } else {
            want!(cs.contains(&-1) && cs.contains(&256) && cs.contains(&i32::MIN) && cs.contains(&i32::MAX), "memset readings corpus lacks an edge");
        }
    }
    for l in lines(&corpus(gen_bzero, 1, 3000)) {
        let before = unhex(&l[0]);
        let n = at(&l, 1);
        let ok = n <= before.len() && {
            let mut m = before.clone();
            m[..n].fill(0);
            unhex(&l[2]) == m
        };
        want!(ok, format!("bzero line {:?} {}", &l[0], n));
    }
    for l in lines(&corpus(gen_memcpy, 1, 3000)) {
        let (src, n, dest) = (unhex(&l[0]), at(&l, 1), unhex(&l[2]));
        let ok = n <= src.len() && n <= dest.len() && {
            let mut m = dest.clone();
            m[..n].copy_from_slice(&src[..n]);
            unhex(&l[3]) == m
        };
        want!(ok && l[4] == "1", format!("memcpy line {:?} {}", &l[0], n));
    }
    {
        let (mut fwd, mut back, mut same, mut apart, mut big_fwd, mut big_back) = (false, false, false, false, false, false);
        for l in lines(&corpus(gen_memmove, 1, 3000)) {
            let (buf, src, dst, n) = (unhex(&l[0]), at(&l, 1), at(&l, 2), at(&l, 3));
            let ok = src.saturating_add(n) <= buf.len() && dst.saturating_add(n) <= buf.len() && {
                let mut m = buf.clone();
                m.copy_within(src..src + n, dst);
                unhex(&l[4]) == m
            };
            want!(ok && l[5] == "1", format!("memmove line {} {} {}", src, dst, n));
            if !ok {
                continue;
            }
            fwd |= n > 0 && src < dst && dst < src + n;
            back |= n > 0 && dst < src && src < dst + n;
            same |= n > 0 && src == dst;
            apart |= n > 0 && (src + n <= dst || dst + n <= src);
            big_fwd |= n > 4096 && src < dst && dst < src + n;
            big_back |= n > 4096 && dst < src && src < dst + n;
        }
        want!(fwd && back && same && apart, "memmove corpus lacks an overlap direction, dst == src or a disjoint pair");
        want!(big_fwd && big_back, "memmove corpus lacks an overlap past 4096 bytes either way");
    }
    {
        let (mut neg, mut over, mut nul, mut miss_in, mut miss_past) = (false, false, false, false, false);
        let mut cs = std::collections::BTreeSet::new();
        for l in lines(&corpus(gen_memchr, 1, 3000)) {
            let (buf, c, n) = (unhex(&l[0]), num::<i32>(&l[1]).unwrap_or(0), at(&l, 2));
            let byte = c.rem_euclid(256) as u8;
            let ok = n <= buf.len() && {
                let r = buf[..n].iter().position(|&x| x == byte);
                l[3] == r.map_or("NULL".to_string(), |o| o.to_string())
            };
            want!(ok, format!("memchr line {:?} {} {}", &l[0], c, n));
            if !ok {
                continue;
            }
            cs.insert(c);
            let found = l[3] != "NULL";
            neg |= found && c < 0;
            over |= found && c > 255;
            nul |= found && byte == 0 && buf[..n].iter().any(|&x| x != 0);
            miss_in |= !found && n > 0;
            miss_past |= !found && buf[n..].contains(&byte);
        }
        want!((-512..=767).all(|c| cs.contains(&c)), "memchr corpus lacks a c in -512..=767");
        want!(neg && over && nul && miss_in && miss_past, "memchr corpus lacks a negative c, a c past 255, a NUL found, a miss, or a match just past n");
    }
    {
        let (mut signs, mut past_nul, mut high, mut zero_n, mut past_n) = ([false; 3], false, false, false, false);
        for l in lines(&corpus(gen_memcmp, 1, 3000)) {
            let (a, b, n) = (unhex(&l[0]), unhex(&l[1]), at(&l, 2));
            let ok = n <= a.len() && n <= b.len() && {
                let s = match a[..n].cmp(&b[..n]) {
                    std::cmp::Ordering::Less => "-1",
                    std::cmp::Ordering::Equal => "0",
                    std::cmp::Ordering::Greater => "1",
                };
                l[3] == s
            };
            want!(ok, format!("memcmp line {:?} {:?} {}", &l[0], &l[1], n));
            if !ok {
                continue;
            }
            let r: i32 = num(&l[3]).unwrap_or(9);
            signs[(r + 1) as usize] = true;
            let first = (0..n).find(|&i| a[i] != b[i]);
            if let Some(i) = first {
                past_nul |= a[..i].contains(&0);
                // signed char would give the other sign
                high |= ((a[i] as i8) < (b[i] as i8)) != (a[i] < b[i]);
            }
            zero_n |= n == 0 && a.first().is_some() && a.first() != b.first();
            past_n |= r == 0 && a.len() > n && b.len() > n && a[n] != b[n];
        }
        want!(signs.iter().all(|&s| s), "memcmp corpus lacks a sign");
        want!(past_nul && high && zero_n && past_n, "memcmp corpus lacks a difference past a NUL, a high byte, n 0 over different bytes, or a difference just past n");
    }
    {
        let (mut z, mut nn, mut null, mut wrap0, mut wrap_small, mut wrap_far) = (false, false, false, false, false, false);
        for l in lines(&corpus(gen_calloc, 1, 3000)) {
            let (a, b) = (num::<u64>(&l[0]), num::<u64>(&l[1]));
            let (Some(a), Some(b)) = (a, b) else {
                want!(false, format!("calloc line {:?} is not two size_t", l));
                continue;
            };
            let p = a as u128 * b as u128;
            let cat = if p > u64::MAX as u128 { "NULL" } else if p == 0 { "nonnull" } else { "zeroed" };
            want!(l[2] == cat, format!("calloc line {} {}", a, b));
            // never a large size that does not overflow: o_calloc's domain
            want!(p > u64::MAX as u128 || p <= MIB as u128, format!("calloc {} {} asks for more than 1 MiB", a, b));
            if p > u64::MAX as u128 {
                let wrapped = (p & u64::MAX as u128) as u64;
                want!(wrapped <= MIB || wrapped > i64::MAX as u64, format!("calloc {} {} wraps to {}", a, b, wrapped));
                wrap0 |= wrapped == 0;
                wrap_small |= wrapped > 0 && wrapped <= MIB;
                wrap_far |= wrapped > i64::MAX as u64;
            }
            z |= cat == "zeroed";
            nn |= cat == "nonnull";
            null |= cat == "NULL";
        }
        want!(z && nn && null && wrap0 && wrap_small && wrap_far, "calloc corpus lacks a class");
    }
    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "libft_memset" | "libft_memset_readings" | "libft_bzero" | "libft_memcpy"
        | "libft_memmove" | "libft_memchr" | "libft_memcmp" | "libft_calloc") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        let p = |k: usize| f.get(k).and_then(|s| s.parse::<usize>().ok());
        match name {
            "libft_calloc" => {
                if let (Some(a), Some(b)) = (f.first().and_then(|s| s.parse().ok()), f.get(1).and_then(|s| s.parse().ok())) {
                    sink(o_calloc(a, b));
                }
            }
            "libft_memset" | "libft_memset_readings" => {
                let a = unhex(f[0]);
                if let (Some(c), Some(n)) = (f.get(1).and_then(|s| s.parse::<i32>().ok()), p(2)) {
                    if n <= a.len() { sink(o_memset(&a, c, n)); }
                }
            }
            "libft_bzero" => {
                let a = unhex(f[0]);
                if let Some(n) = p(1) { if n <= a.len() { sink(o_bzero(&a, n)); } }
            }
            "libft_memcpy" => {
                let (s, d) = (unhex(f[0]), unhex(f.get(2).copied().unwrap_or("")));
                if let Some(n) = p(1) { if n <= s.len() && n <= d.len() { sink(o_memcpy(&s, n, &d)); } }
            }
            "libft_memmove" => {
                let a = unhex(f[0]);
                if let (Some(s), Some(d), Some(n)) = (p(1), p(2), p(3)) {
                    if s.saturating_add(n) <= a.len() && d.saturating_add(n) <= a.len() { sink(o_memmove(&a, s, d, n)); }
                }
            }
            "libft_memchr" => {
                let a = unhex(f[0]);
                if let (Some(c), Some(n)) = (f.get(1).and_then(|s| s.parse::<i32>().ok()), p(2)) {
                    if n <= a.len() { sink(o_memchr(&a, c, n)); }
                }
            }
            _ => {
                let (a, b) = (unhex(f[0]), unhex(f.get(1).copied().unwrap_or("")));
                if let Some(n) = p(2) { if n <= a.len() && n <= b.len() { sink(o_memcmp(&a, &b, n)); } }
            }
        }
    }
    true
}
