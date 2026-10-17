//! Libft references: the string functions of Part 1 (ft_strlen ft_strlcpy
//! ft_strlcat ft_strchr ft_strrchr ft_strncmp ft_strnstr ft_atoi ft_strdup).
//!
//! Part 1 of the Libft subject (v19.3) asks for "the same prototypes and
//! behaviors as the originals, adhering strictly to their definitions in the
//! man page", so every reference here is the man page's definition: strlcat(3bsd),
//! strchr(3), strncmp(3), strnstr(3bsd) and atoi(3) (which is strtol(3) in
//! base 10, in the C locale). A sentence the man page leaves open is a reading,
//! and its cases live only in a `_readings` corpus; every plain corpus holds
//! only cases every reading agrees on.
//!
//! Numbers are decimal. A size_t field (n, len, size) is never above
//! 4294967295, except 18446744073709551615, which stands for SIZE_MAX: a
//! harness reads it with strtoull and casts it to size_t, which keeps every
//! bit set on any width, so the line means the same under ilp32. Strings
//! travel hex-encoded and never hold a NUL.
//!
//! Arms this module owns (input fields, then the reference):
//!   libft_strlcat           <hexDst>\t<cap>\t<hexSrc>\t<size>\t<hexResult>\t<ret>
//!                           cap is the buffer dst is in: size when strlen(dst)
//!                           < size, else strlen(dst) + 1. hexResult is the
//!                           buffer up to its first NUL, never past cap.
//!                           size is a buffer's size, so it is always under
//!                           2^32 and never SIZE_MAX.
//!   libft_strchr            <hexS>\t<c>\t<off|NULL>     (c in 0..=255)
//!   libft_strchr_readings   (the same; c outside 0..=255)
//!   libft_strrchr           <hexS>\t<c>\t<off|NULL>     (c in 0..=255)
//!   libft_strrchr_readings  (the same; c outside 0..=255)
//!   libft_strncmp           <hexS1>\t<hexS2>\t<n>\t<-1|0|1>   (the SIGN only)
//!   libft_strnstr           <hexBig>\t<hexLittle>\t<len>\t<off|NULL>
//!   libft_atoi              <hexS>\t<int>
//! `off` is the offset of the returned pointer from the string passed in.
//!
//! Arms reused AS IS from the Piscine, because their contract and corpus are
//! Libft's (check() reads each corpus back and holds every line to this
//! module's own reading of the man page, so a later change to one for its
//! Piscine exercise that Libft cannot share turns this check red):
//!   c01_strlen   <hexS>\t<len>
//!   c02_strlcpy  <hexSrc>\t<size>\t<hexDstContent>\t<ret>
//!                (the content is the C string up to its terminator: no byte
//!                 between the terminator and size is ever asserted)
//!   c07_strdup   <hexS>\t<hexDup>
//! ft_strnstr has no length arm of its own: its perf length series is
//! length.rs's c03_strstr_len, with the harness passing len = the line's
//! length, where strnstr(3bsd) searches the whole string as strstr does.

use crate::c03::{long_cmp_cases, o_strlcat, o_strncmp, o_strstr};
use crate::common::{bench_lines, largest_dec, long_text, rand_body, sink, string_pairs, to_hex, unhex, widest_hex, Rng};
use std::io::{self, Write};

/// SIZE_MAX as a corpus writes it (see the header).
const SIZE_MAX: u64 = u64::MAX;

/// size_t values past what an int or an unsigned int holds once negated,
/// each meaning "no limit" for the cases they are drawn for: 2^31 (an `int`
/// copy of it is negative), 2^32 - 1, and SIZE_MAX.
const HUGE: [u64; 3] = [2_147_483_648, 4_294_967_295, SIZE_MAX];

/// The isspace(3) bytes of the C locale: "space, form-feed ('\f'), newline
/// ('\n'), carriage return ('\r'), horizontal tab ('\t'), and vertical tab
/// ('\v')".
const WS: [u8; 6] = [b' ', b'\t', b'\n', 0x0b, 0x0c, b'\r'];

/// A size_t field as the host's usize: SIZE_MAX and the other huge values
/// mean "no limit", which usize::MAX means as well on this 64-bit host.
fn as_usize(n: u64) -> usize {
    usize::try_from(n).unwrap_or(usize::MAX)
}

// ------------------------------------------------------------- oracles

/// ft_strlcat, strlcat(3bsd): "It will append at most size - strlen(dst) - 1
/// bytes, NUL-terminating the result", and returns "the initial length of
/// dst plus the length of src" -- except that "if strlcat() traverses size
/// characters without finding a NUL, the length of the string is considered
/// to be size", and nothing is appended. C 03's reference (wrapped here) holds
/// the return for every size; what it returns as the buffer when strlen(dst)
/// > size is dst cut at size, which its corpus never asks for. Here the
/// buffer is dst, unchanged, as it is.
/// Returns (the buffer up to its first NUL, the return value).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strlcat_libft(dst: &[u8], src: &[u8], size: usize) -> (Vec<u8>, u64) {
    if dst.len() >= size {
        return (dst.to_vec(), (size + src.len()) as u64);
    }
    o_strlcat(dst, src, size)
}

/// The buffer a strlcat case puts dst in: `size` bytes when dst's NUL is
/// within them (the man page's "full size of the buffer"), else room for dst
/// and its NUL, which then lies past size.
fn strlcat_cap(dlen: usize, size: usize) -> usize {
    if dlen < size {
        size
    } else {
        dlen + 1
    }
}

/// The byte a `c` stands for. For c in 0..=255 it is c, in every reading of
/// strchr(3) ("Here "character" means "byte""). Outside that range the man
/// page says nothing; THIS HARNESS'S READING is the low 8 bits of c, as a
/// conversion to unsigned char (or char) gives them, and only the
/// `_readings` corpora hold such a c.
fn byte_of(c: i32) -> u8 {
    (c as u32 & 0xff) as u8
}

/// ft_strchr, strchr(3): the first occurrence of the byte, where "the
/// terminating null byte is considered part of the string, so that if c is
/// specified as '\0', these functions return a pointer to the terminator".
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strchr(s: &[u8], c: i32) -> Option<usize> {
    let b = byte_of(c);
    if b == 0 {
        return Some(s.len());
    }
    s.iter().position(|&x| x == b)
}

/// ft_strrchr, strrchr(3): the last occurrence, the terminator included.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strrchr(s: &[u8], c: i32) -> Option<usize> {
    let b = byte_of(c);
    if b == 0 {
        return Some(s.len());
    }
    s.iter().rposition(|&x| x == b)
}

/// ft_strncmp, strncmp(3), as its SIGN: -1, 0 or 1. The man page promises
/// "an integer less than, equal to, or greater than zero", never a value, so
/// the value is no case of any corpus. C 03's reference (unsigned bytes, at
/// most n, stopping at the first NUL) gives the difference; this keeps its sign.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strncmp_sign(a: &[u8], b: &[u8], n: u64) -> i64 {
    o_strncmp(a, b, as_usize(n)).signum()
}

/// ft_strnstr, strnstr(3bsd): "locates the first occurrence of the
/// null-terminated string little in the string big, where not more than len
/// characters are searched. Characters that appear after a '\0' character
/// are not searched." and "If little is an empty string, big is returned; if
/// little occurs nowhere in big, NULL is returned". So an occurrence counts
/// only when it lies whole within the first min(len, strlen(big)) bytes. The
/// search itself is C 03's strstr reference, over that prefix.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strnstr(big: &[u8], little: &[u8], len: u64) -> Option<usize> {
    if little.is_empty() {
        return Some(0);
    }
    let lim = as_usize(len).min(big.len());
    o_strstr(&big[..lim], little)
}

/// strtol(nptr, NULL, 10) in the C locale, without its overflow clamp: "an
/// arbitrary amount of white space (as determined by isspace(3)) followed by
/// a single optional '+' or '-' sign", then decimal digits, "stopping at the
/// first character which is not a valid digit". No digit at all reads 0.
/// The magnitude saturates far above every int, so a check can tell a case
/// that would overflow from one that does not.
fn strtol10(s: &[u8]) -> i128 {
    let mut i = 0usize;
    while i < s.len() && WS.contains(&s[i]) {
        i += 1;
    }
    let mut neg = false;
    if i < s.len() && (s[i] == b'+' || s[i] == b'-') {
        neg = s[i] == b'-';
        i += 1;
    }
    let mut v: i128 = 0;
    while i < s.len() && s[i].is_ascii_digit() {
        v = (v * 10 + (s[i] - b'0') as i128).min(1i128 << 100);
        i += 1;
    }
    if neg {
        -v
    } else {
        v
    }
}

/// ft_atoi, atoi(3): "The behavior is the same as strtol(nptr, NULL, 10);
/// except that atoi() does not detect errors." Every corpus value fits an
/// int (check() holds each line to it), where atoi is strtol's value: a
/// value past int is undefined behaviour, and no corpus holds one. NOT C 04's
/// ft_atoi, whose subject takes any number of signs.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_atoi(s: &[u8]) -> i32 {
    strtol10(s) as i32
}

// ---------------------------------------------------------- second opinions
//
// The same contracts written a second way, sharing no code with the
// references above, so that check() can hold each corpus line to both.

fn alt_strlcat(dst: &[u8], src: &[u8], size: usize) -> (Vec<u8>, u64) {
    // strlen(dst), "considered to be size" when no NUL is met within size.
    let considered = if dst.len() < size { dst.len() } else { size };
    let mut buf = dst.to_vec();
    if considered < size {
        // "append at most size - strlen(dst) - 1 bytes"
        buf.extend(src.iter().take(size - considered - 1));
    }
    (buf, (considered + src.len()) as u64)
}

fn alt_strchr(s: &[u8], c: i32, last: bool) -> Option<usize> {
    let want = c.rem_euclid(256);
    let mut found = None;
    for i in 0..=s.len() {
        let here = if i < s.len() { s[i] as i32 } else { 0 };
        if here == want {
            found = Some(i);
            if !last {
                break;
            }
        }
    }
    found
}

fn alt_strncmp(a: &[u8], b: &[u8], n: u64) -> i64 {
    let mut ea = a.to_vec();
    ea.push(0);
    let mut eb = b.to_vec();
    eb.push(0);
    let la = as_usize(n).min(ea.len());
    let lb = as_usize(n).min(eb.len());
    match ea[..la].cmp(&eb[..lb]) {
        std::cmp::Ordering::Less => -1,
        std::cmp::Ordering::Equal => 0,
        std::cmp::Ordering::Greater => 1,
    }
}

fn alt_strnstr(big: &[u8], little: &[u8], len: u64) -> Option<usize> {
    let len = as_usize(len);
    (0..=big.len()).find(|&i| {
        (0..little.len()).all(|j| i + j < big.len() && i + j < len && big[i + j] == little[j])
    })
}

fn alt_atoi(s: &[u8]) -> Option<i32> {
    let t: Vec<u8> = s.iter().copied().skip_while(|b| b" \t\n\x0b\x0c\r".contains(b)).collect();
    let (sign, rest): (&str, &[u8]) = match t.first() {
        Some(b'-') => ("-", &t[1..]),
        Some(b'+') => ("", &t[1..]),
        _ => ("", &t[..]),
    };
    let digits: String = rest.iter().take_while(|b| b.is_ascii_digit()).map(|&b| b as char).collect();
    if digits.is_empty() {
        return Some(0);
    }
    format!("{}{}", sign, digits).parse::<i32>().ok()
}

// ---------------------------------------------------------- corpus helpers

fn opt(o: Option<usize>) -> String {
    match o {
        Some(i) => i.to_string(),
        None => "NULL".to_string(),
    }
}

/// `n` bytes of every value but NUL and `b`, then `b` at `at` (each index in
/// `at`), from a seed of its own: a long string where `b` stands only there.
fn only_at(n: usize, b: u8, at: &[usize], seed: u64) -> Vec<u8> {
    let mut s: Vec<u8> = rand_body(&mut Rng::new(seed), n, true)
        .into_iter()
        .map(|x| if x == b { if b == 0xff { 0x01 } else { b + 1 } } else { x })
        .collect();
    for &i in at {
        s[i] = b;
    }
    s
}

/// A random string for a search: short, letters or every byte but NUL.
fn small_body(rng: &mut Rng, max: usize) -> Vec<u8> {
    let high = rng.below(2) == 1;
    let len = rng.below(max + 1);
    rand_body(rng, len, high)
}

// ---------------------------------------------------------- generators

fn gen_strlcat<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    // The man page's corners: an empty dst and src, size 0 and 1, size below,
    // at and one above strlen(dst) ("traverses size characters without
    // finding a NUL"), room for only the NUL, an exact fit, room to spare,
    // high bytes (signed char), then the capacity cases (finding 041): a dst
    // of 4100 and a src of 5000 with all the room they need (9101), cut at
    // 6000, with none (size 4100 == strlen(dst)); a dst of 1100 and that src
    // at 4097; and a dst of 5000 with size 4097, whose NUL lies past size.
    let hi: &[u8] = &[0x80, b'a'];
    let hs: &[u8] = &[0xff, 0xe9];
    let mut cases: Vec<(Vec<u8>, Vec<u8>, usize)> = vec![
        (b"".to_vec(), b"".to_vec(), 0),
        (b"".to_vec(), b"".to_vec(), 1),
        (b"".to_vec(), b"abc".to_vec(), 0),
        (b"".to_vec(), b"abc".to_vec(), 1),
        (b"".to_vec(), b"abc".to_vec(), 4),
        (b"foo".to_vec(), b"bar".to_vec(), 10),
        (b"foo".to_vec(), b"bar".to_vec(), 7),
        (b"foo".to_vec(), b"bar".to_vec(), 6),
        (b"foo".to_vec(), b"bar".to_vec(), 5),
        (b"foo".to_vec(), b"bar".to_vec(), 4),
        (b"foo".to_vec(), b"bar".to_vec(), 3),
        (b"foo".to_vec(), b"bar".to_vec(), 2),
        (b"foo".to_vec(), b"bar".to_vec(), 1),
        (b"foo".to_vec(), b"bar".to_vec(), 0),
        (b"hello".to_vec(), b"".to_vec(), 3),
        (b"hello".to_vec(), b"".to_vec(), 10),
        (hi.to_vec(), hs.to_vec(), 5),
        (hi.to_vec(), hs.to_vec(), 4),
        (hi.to_vec(), hs.to_vec(), 1),
    ];
    let d = long_text(4100, 4100);
    let s = long_text(5000, 5000);
    cases.push((d.clone(), s.clone(), 9101));
    cases.push((d.clone(), s.clone(), 6000));
    cases.push((d, s.clone(), 4100));
    cases.push((long_text(1100, 1100), s.clone(), 4097));
    cases.push((s, b"abc".to_vec(), 4097));
    while cases.len() < count {
        let size = rng.below(25);
        // One case in four has its NUL at or past size.
        let dlen = if rng.below(4) == 0 { size + rng.below(5) } else { rng.below(size.max(1)) };
        let high = rng.below(2) == 1;
        let d = rand_body(&mut rng, dlen, high);
        let ls = rng.below(25);
        let s = rand_body(&mut rng, ls, high);
        cases.push((d, s, size));
    }
    for (d, s, size) in &cases {
        let (buf, ret) = o_strlcat_libft(d, s, *size);
        let _ = writeln!(
            w,
            "{}\t{}\t{}\t{}\t{}\t{}",
            to_hex(d),
            strlcat_cap(d.len(), *size),
            to_hex(s),
            size,
            to_hex(&buf),
            ret
        );
    }
}

/// ft_strchr's and ft_strrchr's cases: c in 0..=255 (`part` false), or c
/// outside it, the cases only this harness's reading settles (`part` true).
fn chr_cases(seed: u64, count: usize, part: bool) -> Vec<(Vec<u8>, i32)> {
    let mut rng = Rng::new(seed);
    let hello = b"Hello, 42!".to_vec();
    // Every byte but NUL twice over, so each c is found at a first place and
    // a last one that differ.
    let all: Vec<u8> = (1..=255u8).chain(1..=255u8).collect();
    let e9: &[u8] = &[b'a', 0xe9, b'b', 0xe9];
    // Capacity cases (finding 041): '#' only at the end of 5000 bytes of
    // text, and 0xe9 only at the first and the last of 5000 bytes of every
    // value.
    let mut text = long_text(4999, 4999);
    text.push(b'#');
    let wide = only_at(5000, 0xe9, &[0, 4999], 5000);
    let mut cases: Vec<(Vec<u8>, i32)> = Vec::new();
    if !part {
        for c in [b'H', b'l', b'o', b'!', b',', b' ', b'4', b'z', 0] {
            cases.push((hello.clone(), c as i32));
        }
        cases.push((Vec::new(), b'a' as i32));
        cases.push((Vec::new(), 0));
        cases.push((e9.to_vec(), 0xe9));
        cases.push((vec![0xe9, b'z'], b'z' as i32));
        cases.push((vec![0xff, 0x80, 0x7f], 0x80));
        cases.push((vec![0xff, 0x80, 0x7f], 0xff));
        cases.push((b"aaaa".to_vec(), b'a' as i32));
        for c in 0..=255 {
            cases.push((all.clone(), c));
        }
        cases.push((text.clone(), b'#' as i32));
        cases.push((text, 0));
        cases.push((wide.clone(), 0xe9));
        cases.push((wide, 0));
    } else {
        for c in [b'l' as i32 + 256, b'l' as i32 - 256, b'H' as i32 + 512, b'!' as i32 - 512, 256, -256, i32::MIN, i32::MAX] {
            cases.push((hello.clone(), c));
        }
        cases.push((e9.to_vec(), -23));
        cases.push((vec![0xff], -1));
        cases.push((vec![0x7f, 0x80], -129));
        cases.push((vec![0x7f, 0x80], -128));
        cases.push((Vec::new(), 256));
        cases.push((Vec::new(), -1));
        // Every byte, shifted by a multiple of 256: one or two steps either
        // way, or as far as an int goes at either end.
        let ks: [i64; 6] = [1, -1, 2, -2, 0x7f_ffff, -0x80_0000];
        for c in 0..=255i64 {
            cases.push((all.clone(), (c + 256 * ks[c as usize % ks.len()]) as i32));
        }
        cases.push((text.clone(), b'#' as i32 + 256));
        cases.push((text, -256));
        cases.push((wide.clone(), -23));
        cases.push((wide, i32::MIN));
    }
    while cases.len() < count {
        let s = small_body(&mut rng, 40);
        let low: i32 = match rng.below(10) {
            0 => 0,
            1..=4 if !s.is_empty() => s[rng.below(s.len())] as i32,
            _ => rng.below(256) as i32,
        };
        let c = if part {
            // low + 256k, k != 0, within int
            let k = loop {
                let k = rng.below(0x100_0000) as i64 - 0x80_0000;
                if k != 0 {
                    break k;
                }
            };
            (low as i64 + 256 * k) as i32
        } else {
            low
        };
        cases.push((s, c));
    }
    cases
}

fn gen_chr<W: Write>(w: &mut W, seed: u64, count: usize, part: bool, last: bool) {
    for (s, c) in chr_cases(seed, count, part) {
        let r = if last { o_strrchr(&s, c) } else { o_strchr(&s, c) };
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(&s), c, opt(r));
    }
}

fn gen_strncmp<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let ff: &[u8] = &[0xff];
    // The sign at every boundary: n of 0, n stopping before the difference,
    // at it and past both terminators; n of 2^31, 2^32 - 1 and SIZE_MAX (a
    // size_t, never an int); unsigned bytes (0x80 against 0x01, 0xff against
    // 'a'); a prefix against the longer string.
    let mut cases: Vec<(Vec<u8>, Vec<u8>, u64)> = vec![
        (b"abc".to_vec(), b"abd".to_vec(), 3),
        (b"abc".to_vec(), b"abd".to_vec(), 2),
        (b"abd".to_vec(), b"abc".to_vec(), 3),
        (b"abc".to_vec(), b"abd".to_vec(), SIZE_MAX),
        (b"abc".to_vec(), b"abc".to_vec(), SIZE_MAX),
        (b"".to_vec(), b"".to_vec(), 0),
        (b"".to_vec(), b"".to_vec(), SIZE_MAX),
        (b"a".to_vec(), b"".to_vec(), 1),
        (b"".to_vec(), b"a".to_vec(), 1),
        (b"abc".to_vec(), b"ab".to_vec(), 2),
        (b"abc".to_vec(), b"ab".to_vec(), 3),
        (b"ab".to_vec(), b"abc".to_vec(), SIZE_MAX),
        (b"ab".to_vec(), b"ab".to_vec(), 4),
        (b"abc".to_vec(), b"xyz".to_vec(), 0),
        (vec![0x80], vec![0x01], 1),
        (vec![0x01], vec![0x80], 1),
        (ff.to_vec(), b"a".to_vec(), 1),
        (b"a".to_vec(), ff.to_vec(), 1),
        (b"Hello".to_vec(), b"Hella".to_vec(), HUGE[0]),
        (b"Hello".to_vec(), b"Hella".to_vec(), HUGE[1]),
        (b"Hella".to_vec(), b"Hello".to_vec(), HUGE[2]),
    ];
    // Capacity cases (finding 041): C 03's, and 5000 equal bytes with no
    // limit.
    for (a, b, n) in long_cmp_cases() {
        cases.push((a, b, n as u64));
    }
    let t = long_text(5000, 5000);
    cases.push((t.clone(), t, SIZE_MAX));
    for (a, b) in string_pairs(&mut rng, count.saturating_sub(cases.len())) {
        let m = a.len().max(b.len());
        // Where they first differ, if anywhere within both.
        let diff = a.iter().zip(b.iter()).position(|(x, y)| x != y).unwrap_or(m);
        let n: u64 = match rng.below(8) {
            0 => 0,
            1 => diff as u64,
            2 => diff as u64 + 1,
            3 => HUGE[rng.below(3)],
            _ => rng.below(m + 2) as u64,
        };
        cases.push((a, b, n));
    }
    for (a, b, n) in &cases {
        let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(a), to_hex(b), n, o_strncmp_sign(a, b, *n));
    }
}

fn gen_strnstr<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let h = b"Hello, 42 world".to_vec();
    let foo = b"Foo Bar Baz".to_vec();
    let s = |x: &[u8]| x.to_vec();
    // The man page's example (only the first 4 characters searched), every
    // len around an occurrence's end, an empty little (big is returned, len
    // 0 too), len 0 with a non-empty little, little longer than big, len
    // past big's NUL, high bytes, a partial match before the real one.
    let mut cases: Vec<(Vec<u8>, Vec<u8>, u64)> = vec![
        (foo.clone(), s(b"Bar"), 4),
        (foo.clone(), s(b"Bar"), 6),
        (foo.clone(), s(b"Bar"), 7),
        (foo, s(b"Baz"), 11),
        (h.clone(), s(b"42"), 15),
        (h.clone(), s(b"42"), 9),
        (h.clone(), s(b"42"), 8),
        (h.clone(), s(b"world"), 15),
        (h.clone(), s(b"world"), 14),
        (h.clone(), s(b""), 0),
        (h.clone(), s(b""), 15),
        (h.clone(), s(b"o"), 4),
        (h.clone(), s(b"o"), 5),
        (h.clone(), s(b"H"), 0),
        (h.clone(), s(b"H"), 1),
        (h.clone(), s(b"42"), SIZE_MAX),
        (h.clone(), s(b"42"), HUGE[0]),
        (h.clone(), s(b"42"), HUGE[1]),
        (h.clone(), s(b"xyz"), SIZE_MAX),
        (h, s(b"Hello, 42 world!"), SIZE_MAX),
        (s(b"abc"), s(b"c"), 10),
        (s(b"abc"), s(b"abcd"), 10),
        (s(b"abc"), s(b"abc"), 3),
        (s(b"abc"), s(b"abc"), 2),
        (s(b"abc"), s(b""), SIZE_MAX),
        (s(b"aaaab"), s(b"aaab"), 5),
        (s(b"aaaab"), s(b"aaab"), 4),
        (s(b""), s(b""), 0),
        (s(b""), s(b""), SIZE_MAX),
        (s(b""), s(b"a"), SIZE_MAX),
        (vec![b'a', 0xe9], vec![0xe9], 2),
        (vec![b'a', 0xe9], vec![0xe9], 1),
        (vec![0x80, 0xff, 0x80], vec![0xff, 0x80], SIZE_MAX),
    ];
    // Capacity cases (finding 041): a '#' only at the end of 5000 bytes, with
    // len reaching it and stopping one short; a little of 4097 bytes found
    // only at the end of 5001, the same way; a len past big's NUL with
    // nothing to find.
    let mut end = long_text(4999, 4999);
    end.push(b'#');
    cases.push((end.clone(), s(b"#"), 5000));
    cases.push((end.clone(), s(b"#"), 4999));
    let mut big = long_text(5000, 5000);
    big.push(b'#');
    let little = big[big.len() - 4097..].to_vec();
    cases.push((big.clone(), little.clone(), 5001));
    cases.push((big, little, 5000));
    cases.push((long_text(5000, 5000), s(b"#"), 6000));
    while cases.len() < count {
        let big = small_body(&mut rng, 24);
        let little = match rng.below(4) {
            0 if !big.is_empty() => {
                let at = rng.below(big.len());
                let l = 1 + rng.below((big.len() - at).min(6));
                big[at..at + l].to_vec()
            }
            1 => Vec::new(),
            _ => small_body(&mut rng, 4),
        };
        // len around where an occurrence ends, if there is one in big.
        let end = o_strstr(&big, &little).map(|i| i + little.len());
        let len: u64 = match (rng.below(6), end) {
            (0, Some(e)) => e as u64,
            (1, Some(e)) => e.saturating_sub(1) as u64,
            (2, _) => HUGE[rng.below(3)],
            (3, _) => 0,
            _ => rng.below(big.len() + 3) as u64,
        };
        cases.push((big, little, len));
    }
    for (b, l, len) in &cases {
        let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(b), to_hex(l), len, opt(o_strnstr(b, l, *len)));
    }
}

/// ft_atoi's structured head: atoi(3)'s and strtol(3)'s corners, then the
/// capacity cases. Every value fits an int.
fn atoi_structured() -> Vec<Vec<u8>> {
    let mut v: Vec<Vec<u8>> = [
        &b"42"[..], b"0", b"-0", b"+0", b"7", b"000123", b"+42", b"-42", b"007",
        b"+000", b"-000",
        // the six isspace bytes, together and alone
        b" \t\n\x0b\x0c\r-123", b"\x0b-9", b"\x0c+8", b"\r7", b"\n\n42",
        // ONE optional sign: a second one is no digit, and nothing is read
        b"+-1", b"-+1", b"--1", b"++1", b"  --42", b"+-", b"-", b"+",
        // a space between the sign and the digits, or inside the number
        b"- 1", b"+ 1", b" +7 8",
        // digits end at the first non-digit
        b"12-3", b"  -0042abc", b"42abc", b"3.14", b"1e3", b"0x1A",
        // nothing to read
        b"", b"   ", b"abc", b"  +a",
        // a byte that is not isspace in the C locale where a space may stand:
        // above 0x7f (signed char), or a control byte
        b"\x80 1", b"\xa042", b"\x8542", b"\x1c42", b"\x0e7", b"\x01 5", b"-\x805",
        // the int boundaries, which fit
        b"2147483647", b"-2147483648", b"+2147483647", b"-2147483647",
        b"2147483647abc", b"  -2147483648", b"-00002147483648",
    ]
    .iter()
    .map(|s| s.to_vec())
    .collect();
    // Capacity cases (finding 041): each run atoi may meet at any length, past
    // 4096 bytes -- whitespace, leading zeros, what follows the number -- and
    // a sign then 4100 signs, which read nothing.
    let mut a: Vec<u8> = (0..5000).map(|i| WS[i % WS.len()]).collect();
    a.extend_from_slice(b"-7");
    v.push(a);
    let mut a: Vec<u8> = (0..5000).map(|i| WS[(i * 5) % WS.len()]).collect();
    a.extend_from_slice(b"-2147483648");
    v.push(a);
    let mut z = vec![b'0'; 5000];
    z.extend_from_slice(b"42");
    v.push(z);
    let mut z = b"-".to_vec();
    z.extend_from_slice(&[b'0'; 5000]);
    z.extend_from_slice(b"2147483648");
    v.push(z);
    let mut t = b"42".to_vec();
    t.extend_from_slice(&long_text(5000, 5000));
    v.push(t);
    let mut g = b"+".to_vec();
    g.extend((0..4100).map(|i| if i % 2 == 0 { b'-' } else { b'+' }));
    g.extend_from_slice(b"5");
    v.push(g);
    v
}

/// A magnitude for an int: biased to the small and to the boundary.
fn magnitude(rng: &mut Rng, neg: bool) -> u64 {
    let top: u64 = if neg { 2_147_483_648 } else { 2_147_483_647 };
    match rng.below(6) {
        0 => 0,
        1 => top,
        2 => rng.below(10) as u64,
        3 => rng.below(1000) as u64,
        4 => rng.below(1_000_000) as u64,
        _ => rng.below(top as usize + 1) as u64,
    }
}

fn gen_atoi<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut cases = atoi_structured();
    while cases.len() < count {
        let mut s = Vec::new();
        for _ in 0..rng.below(5) {
            s.push(WS[rng.below(WS.len())]);
        }
        // now and then a byte that looks like a space and is not one
        if rng.below(12) == 0 {
            s.push([0x1c, 0x1f, 0x85, 0xa0, 0x0e][rng.below(5)]);
        }
        let sign = rng.below(5);
        match sign {
            0 | 1 => {}
            2 => s.push(b'+'),
            3 => s.push(b'-'),
            _ => {
                s.push(if rng.below(2) == 0 { b'+' } else { b'-' });
                s.push(if rng.below(2) == 0 { b'+' } else { b'-' });
            }
        }
        if rng.below(8) != 0 {
            for _ in 0..rng.below(3) {
                s.push(b'0');
            }
            s.extend_from_slice(magnitude(&mut rng, sign == 3).to_string().as_bytes());
        }
        if rng.below(2) == 0 {
            let junk = small_body(&mut rng, 4);
            // the first junk byte is no digit, so the number ends there
            s.push(b'a' + rng.below(26) as u8);
            s.extend_from_slice(&junk);
        }
        cases.push(s);
    }
    for s in &cases {
        let _ = writeln!(w, "{}\t{}", to_hex(s), o_atoi(s));
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    let mut w = io::BufWriter::new(io::stdout());
    match name {
        "libft_strlcat" => gen_strlcat(&mut w, seed, count),
        "libft_strchr" => gen_chr(&mut w, seed, count, false, false),
        "libft_strchr_readings" => gen_chr(&mut w, seed, count, true, false),
        "libft_strrchr" => gen_chr(&mut w, seed, count, false, true),
        "libft_strrchr_readings" => gen_chr(&mut w, seed, count, true, true),
        "libft_strncmp" => gen_strncmp(&mut w, seed, count),
        "libft_strnstr" => gen_strnstr(&mut w, seed, count),
        "libft_atoi" => gen_atoi(&mut w, seed, count),
        _ => return false,
    }
    true
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !matches!(
        name,
        "libft_strlcat"
            | "libft_strchr"
            | "libft_strchr_readings"
            | "libft_strrchr"
            | "libft_strrchr_readings"
            | "libft_strncmp"
            | "libft_strnstr"
            | "libft_atoi"
    ) {
        return false;
    }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        if f.len() < 2 {
            continue;
        }
        let a = unhex(f[0]);
        match name {
            "libft_strlcat" if f.len() >= 4 => {
                if let Ok(size) = f[3].parse::<usize>() {
                    sink(o_strlcat_libft(&a, &unhex(f[2]), size));
                }
            }
            "libft_strchr" | "libft_strchr_readings" => {
                if let Ok(c) = f[1].parse::<i32>() {
                    sink(o_strchr(&a, c));
                }
            }
            "libft_strrchr" | "libft_strrchr_readings" => {
                if let Ok(c) = f[1].parse::<i32>() {
                    sink(o_strrchr(&a, c));
                }
            }
            "libft_strncmp" if f.len() >= 3 => {
                if let Ok(n) = f[2].parse::<u64>() {
                    sink(o_strncmp_sign(&a, &unhex(f[1]), n));
                }
            }
            "libft_strnstr" if f.len() >= 3 => {
                if let Ok(n) = f[2].parse::<u64>() {
                    sink(o_strnstr(&a, &unhex(f[1]), n));
                }
            }
            "libft_atoi" => sink(o_atoi(&a)),
            _ => {}
        }
    }
    true
}

// ---------------------------------------------------------- self-check

/// Every line of `corpus`, split at its tabs.
fn rows(corpus: &[u8]) -> Vec<Vec<String>> {
    String::from_utf8_lossy(corpus)
        .lines()
        .map(|l| l.split('\t').map(str::to_string).collect())
        .collect()
}

/// What a generator writes, into a buffer.
fn corpus(g: &dyn Fn(&mut Vec<u8>)) -> Vec<u8> {
    let mut v = Vec::new();
    g(&mut v);
    v
}

/// This module's self-check failures.
pub fn check() -> usize {
    let mut fails = 0usize;
    macro_rules! want {
        ($cond:expr, $($msg:tt)+) => {
            if !($cond) {
                eprintln!("CHECK FAIL libft_str {}", format!($($msg)+));
                fails += 1;
            }
        };
    }
    let past = 4096usize;

    // ================================================== 1. hand-written tables
    //
    // strlcat(3bsd): "append at most size - strlen(dst) - 1 bytes", return
    // "the initial length of dst plus the length of src", and "if strlcat()
    // traverses size characters without finding a NUL, the length of the
    // string is considered to be size".
    let sl: &[(&[u8], &[u8], usize, &[u8], u64)] = &[
        (b"", b"", 0, b"", 0),
        (b"", b"abc", 0, b"", 3),
        (b"", b"abc", 1, b"", 3),
        (b"", b"abc", 4, b"abc", 3),
        (b"foo", b"bar", 10, b"foobar", 6),
        (b"foo", b"bar", 7, b"foobar", 6),
        (b"foo", b"bar", 6, b"fooba", 6),
        (b"foo", b"bar", 4, b"foo", 6),
        (b"foo", b"bar", 3, b"foo", 6),
        (b"foo", b"bar", 2, b"foo", 5),
        (b"foo", b"bar", 0, b"foo", 3),
        (b"hello", b"", 3, b"hello", 3),
        (&[0x80, b'a'], &[0xff, 0xe9], 4, &[0x80, b'a', 0xff], 4),
    ];
    for (d, s, size, buf, ret) in sl {
        want!(o_strlcat_libft(d, s, *size) == (buf.to_vec(), *ret), "strlcat table {:?} {:?} {}", d, s, size);
    }
    want!(strlcat_cap(3, 10) == 10 && strlcat_cap(3, 3) == 4 && strlcat_cap(5, 2) == 6 && strlcat_cap(0, 0) == 1, "strlcat cap rule");

    // strchr(3)/strrchr(3): first and last occurrence; "if c is specified as
    // '\0', these functions return a pointer to the terminator".
    let h: &[u8] = b"Hello, 42!";
    let ch: &[(&[u8], i32, Option<usize>, Option<usize>)] = &[
        (h, b'H' as i32, Some(0), Some(0)),
        (h, b'l' as i32, Some(2), Some(3)),
        (h, b'!' as i32, Some(9), Some(9)),
        (h, b'z' as i32, None, None),
        (h, 0, Some(10), Some(10)),
        (b"", b'a' as i32, None, None),
        (b"", 0, Some(0), Some(0)),
        (&[b'a', 0xe9, b'b', 0xe9], 0xe9, Some(1), Some(3)),
        (&[0xe9, b'z'], b'z' as i32, Some(1), Some(1)),
        // this harness's reading, c outside 0..=255: its low 8 bits
        (h, b'l' as i32 + 256, Some(2), Some(3)),
        (&[b'a', 0xe9], -23, Some(1), Some(1)),
        (h, 256, Some(10), Some(10)),
        (h, i32::MIN, Some(10), Some(10)),
        (&[0xff], -1, Some(0), Some(0)),
        (h, i32::MAX, None, None),
    ];
    for (s, c, first, last) in ch {
        want!(o_strchr(s, *c) == *first && o_strrchr(s, *c) == *last, "strchr/strrchr table {:?} {}", s, c);
    }

    // strncmp(3): the sign; "compares only the first (at most) n bytes";
    // "The comparison is done using unsigned characters".
    let nc: &[(&[u8], &[u8], u64, i64)] = &[
        (b"abc", b"abd", 3, -1),
        (b"abc", b"abd", 2, 0),
        (b"abd", b"abc", 3, 1),
        (b"abc", b"abd", SIZE_MAX, -1),
        (b"abc", b"abc", SIZE_MAX, 0),
        (b"", b"", 0, 0),
        (b"", b"", SIZE_MAX, 0),
        (b"a", b"", 1, 1),
        (b"", b"a", 1, -1),
        (b"abc", b"ab", 2, 0),
        (b"abc", b"ab", 3, 1),
        (b"ab", b"abc", SIZE_MAX, -1),
        (b"ab", b"ab", 4, 0),
        (b"abc", b"xyz", 0, 0),
        (&[0x80], &[0x01], 1, 1),
        (&[0xff], b"a", 1, 1),
        (b"a", &[0xff], 1, -1),
        (b"Hello", b"Hella", 2_147_483_648, 1),
    ];
    for (a, b, n, s) in nc {
        want!(o_strncmp_sign(a, b, *n) == *s, "strncmp table {:?} {:?} {}", a, b, n);
    }

    // strnstr(3bsd): its own example ("only the first 4 characters of
    // largestring are searched" -> NULL), "If little is an empty string, big
    // is returned", and nothing past len or past big's NUL.
    let foo: &[u8] = b"Foo Bar Baz";
    let hw: &[u8] = b"Hello, 42 world";
    let ns: &[(&[u8], &[u8], u64, Option<usize>)] = &[
        (foo, b"Bar", 4, None),
        (foo, b"Bar", 6, None),
        (foo, b"Bar", 7, Some(4)),
        (hw, b"42", 15, Some(7)),
        (hw, b"42", 9, Some(7)),
        (hw, b"42", 8, None),
        (hw, b"world", 14, None),
        (hw, b"world", 15, Some(10)),
        (hw, b"", 0, Some(0)),
        (hw, b"o", 4, None),
        (hw, b"o", 5, Some(4)),
        (hw, b"H", 0, None),
        (hw, b"42", SIZE_MAX, Some(7)),
        (b"abc", b"c", 10, Some(2)),
        (b"abc", b"abcd", 10, None),
        (b"aaaab", b"aaab", 5, Some(1)),
        (b"aaaab", b"aaab", 4, None),
        (b"", b"", SIZE_MAX, Some(0)),
        (b"", b"a", SIZE_MAX, None),
        (&[b'a', 0xe9], &[0xe9], 2, Some(1)),
    ];
    for (b, l, len, r) in ns {
        want!(o_strnstr(b, l, *len) == *r, "strnstr table {:?} {:?} {}", b, l, len);
    }

    // atoi(3) = strtol(nptr, NULL, 10): isspace(3)'s six bytes in the C
    // locale, "a single optional '+' or '-' sign", digits to the first
    // non-digit, 0 when there are none.
    let at: &[(&[u8], i32)] = &[
        (b"42", 42),
        (b"-0", 0),
        (b"000123", 123),
        (b"+42", 42),
        (b"-42", -42),
        (b" \t\n\x0b\x0c\r-123", -123),
        (b"+-1", 0),
        (b"-+1", 0),
        (b"--1", 0),
        (b"++1", 0),
        (b"- 1", 0),
        (b"12-3", 12),
        (b"  -0042abc", -42),
        (b"", 0),
        (b"   ", 0),
        (b"+", 0),
        (b"-", 0),
        (b"\x80 1", 0),
        (b"\xa042", 0),
        (b"\x1c42", 0),
        (b"\x8542", 0),
        (b"0x1A", 0),
        (b"3.14", 3),
        (b"2147483647", i32::MAX),
        (b"-2147483648", i32::MIN),
        (b"-00002147483648", i32::MIN),
    ];
    for (s, v) in at {
        want!(o_atoi(s) == *v, "atoi table {:?}", s);
    }

    // ================================================== 2. properties
    let mut rng = Rng::new(0x11bf7);
    for _ in 0..20000 {
        let a = small_body(&mut rng, 12);
        let b = if rng.below(3) == 0 { a.clone() } else { small_body(&mut rng, 12) };
        let n = if rng.below(8) == 0 { HUGE[rng.below(3)] } else { rng.below(16) as u64 };
        let size = rng.below(20);
        let c = if rng.below(4) == 0 { rng.next_u64() as i32 } else { rng.below(256) as i32 };

        // strlcat: the man page's formula, written a second way.
        let (buf, ret) = o_strlcat_libft(&a, &b, size);
        want!((buf.clone(), ret) == alt_strlcat(&a, &b, size), "prop strlcat {:?} {:?} {}", a, b, size);
        want!(buf.starts_with(&a), "prop strlcat keeps dst");
        want!(a.len() >= size || buf.len() < size, "prop strlcat writes past size");

        // strchr/strrchr: the second scan; a hit holds the byte, nothing before
        // (after) it does.
        let f = o_strchr(&a, c);
        let l = o_strrchr(&a, c);
        want!(f == alt_strchr(&a, c, false) && l == alt_strchr(&a, c, true), "prop strchr {:?} {}", a, c);
        want!(f.is_some() == l.is_some() && f <= l, "prop strchr first after last");
        if let Some(i) = f {
            let mut t = a.clone();
            t.push(0);
            want!(t[i] == byte_of(c) && !t[..i].contains(&byte_of(c)), "prop strchr first");
        }

        // strncmp: the slice comparison; antisymmetry; n 0 is equal; SIZE_MAX
        // agrees with the whole-string sign.
        let sg = o_strncmp_sign(&a, &b, n);
        want!(sg == alt_strncmp(&a, &b, n), "prop strncmp {:?} {:?} {}", a, b, n);
        want!(sg == -o_strncmp_sign(&b, &a, n) && o_strncmp_sign(&a, &b, 0) == 0, "prop strncmp antisymmetric");
        want!(o_strncmp_sign(&a, &a, n) == 0, "prop strncmp reflexive");

        // strnstr: the brute force; a hit is little, whole within len and
        // strlen(big); len SIZE_MAX is strstr.
        let r = o_strnstr(&a, &b, n);
        want!(r == alt_strnstr(&a, &b, n), "prop strnstr {:?} {:?} {}", a, b, n);
        if let Some(i) = r {
            want!(b.is_empty() || (a[i..i + b.len()] == b[..] && i + b.len() <= as_usize(n).min(a.len())), "prop strnstr hit");
        }
        want!(o_strnstr(&a, &b, SIZE_MAX) == o_strstr(&a, &b), "prop strnstr unbounded");

        // atoi: the round trip from the decimal of any int, with whitespace
        // and one sign before it and junk after it; two signs read 0.
        let v = rng.i32val();
        let mut s: Vec<u8> = (0..rng.below(4)).map(|_| WS[rng.below(6)]).collect();
        if v >= 0 && rng.below(2) == 0 {
            s.push(b'+');
        }
        s.extend_from_slice(v.to_string().as_bytes());
        s.push(b'x');
        want!(o_atoi(&s) == v && alt_atoi(&s) == Some(v), "prop atoi {:?}", s);
        let mut two = b"+-".to_vec();
        two.extend_from_slice(v.unsigned_abs().to_string().as_bytes());
        want!(o_atoi(&two) == 0, "prop atoi two signs {:?}", two);
    }

    // ================================================== 3. generator self-checks
    //
    // Each corpus read back from what its generator writes: every line agrees
    // with the second opinion, the plain corpora hold only the agreed cases and
    // the readings corpora only the open ones, every unbounded input reaches
    // past every round capacity (16, 64, 256, 1024, 4096; finding 041), and the
    // same seed writes the same bytes.
    let n = 2000;

    // ---- libft_strlcat
    let c = corpus(&|w| gen_strlcat(w, 1, n));
    want!(c == corpus(&|w| gen_strlcat(w, 1, n)), "strlcat corpus is not deterministic");
    want!(widest_hex(&c, 0) > past && widest_hex(&c, 2) > past, "strlcat corpus holds no dst and src past 4096 bytes");
    want!(largest_dec(&c, 3) > past as i64, "strlcat corpus holds no size past 4096");
    let (mut over, mut at_size, mut cut) = (false, false, false);
    for f in rows(&c) {
        let (d, cap, s, size_raw, buf, ret) = (unhex(&f[0]), f[1].parse::<usize>().unwrap_or(0), unhex(&f[2]), f[3].parse::<u64>().unwrap_or(u64::MAX), unhex(&f[4]), f[5].parse::<u64>().unwrap_or(0));
        // size is the size of a buffer the harness allocates, so it is never
        // SIZE_MAX here: under 2^32, which also means the same under ilp32.
        want!(size_raw <= 4_294_967_295, "strlcat size {} is not under 2^32", f[3]);
        let size = as_usize(size_raw);
        want!((buf.clone(), ret) == alt_strlcat(&d, &s, size), "strlcat line {:?} {:?} {}", f[0], f[2], size);
        // The cap rule of the header, written apart from strlcat_cap(): the
        // larger of size and room for dst and its NUL. Exactly size whenever
        // dst's NUL lies inside it, so a write at dst[size] is past the buffer.
        want!(cap == size.max(d.len() + 1), "strlcat line cap {} for dst {} size {}", cap, d.len(), size);
        want!(buf.len() < cap, "strlcat line result {} does not fit cap {}", buf.len(), cap);
        over |= d.len() > size && !s.is_empty();
        at_size |= d.len() == size && size > 0;
        cut |= d.len() < size && buf.len() == size - 1 && d.len() + s.len() >= size;
    }
    want!(over && at_size && cut, "strlcat corpus lacks a dst past size ({}), at size ({}) or a cut ({})", over, at_size, cut);

    // ---- libft_strchr / libft_strrchr, plain and readings
    for (last, name) in [(false, "strchr"), (true, "strrchr")] {
        for part in [false, true] {
            let c = corpus(&|w| gen_chr(w, 7, n, part, last));
            want!(c == corpus(&|w| gen_chr(w, 7, n, part, last)), "{} corpus ({}) is not deterministic", name, part);
            want!(widest_hex(&c, 0) > past, "{} corpus ({}) holds no string past 4096 bytes", name, part);
            let (mut nul, mut high, mut hit_open) = (false, false, false);
            for f in rows(&c) {
                let (s, cv) = (unhex(&f[0]), f[1].parse::<i32>().unwrap_or(0));
                let got = if f[2] == "NULL" { None } else { f[2].parse::<usize>().ok() };
                want!(got == alt_strchr(&s, cv, last), "{} line {} {}", name, f[0], cv);
                let inside = (0..=255).contains(&cv);
                want!(inside != part, "{} {} corpus holds c {}", name, if part { "readings" } else { "plain" }, cv);
                nul |= byte_of(cv) == 0 && got == Some(s.len());
                high |= byte_of(cv) >= 0x80 && got.is_some_and(|i| i < s.len());
                hit_open |= got.is_some();
            }
            want!(nul && high && hit_open, "{} corpus ({}) lacks a terminator ({}) or high-byte hit ({})", name, part, nul, high);
        }
    }

    // ---- libft_strncmp
    let c = corpus(&|w| gen_strncmp(w, 3, n));
    want!(c == corpus(&|w| gen_strncmp(w, 3, n)), "strncmp corpus is not deterministic");
    want!(widest_hex(&c, 0) > past && widest_hex(&c, 1) > past, "strncmp corpus holds no s1 and s2 past 4096 bytes");
    let (mut zero, mut huge, mut big, mut stop) = (false, false, false, false);
    for f in rows(&c) {
        let (a, b, nn) = (unhex(&f[0]), unhex(&f[1]), f[2].parse::<u64>().unwrap_or(0));
        let sg = f[3].parse::<i64>().unwrap_or(9);
        want!(sg == alt_strncmp(&a, &b, nn) && (-1..=1).contains(&sg), "strncmp line {} {} {}", f[0], f[1], nn);
        want!(nn <= 4_294_967_295 || nn == SIZE_MAX, "strncmp n {} is neither under 2^32 nor SIZE_MAX", nn);
        zero |= nn == 0 && a != b;
        huge |= nn == SIZE_MAX && sg != 0;
        big |= nn > past as u64 && nn < 1 << 31 && a.len() > past;
        stop |= sg == 0 && alt_strncmp(&a, &b, SIZE_MAX) != 0;
    }
    want!(zero && huge && big && stop, "strncmp corpus lacks n 0 ({}), SIZE_MAX ({}), past 4096 ({}) or a stop before the difference ({})", zero, huge, big, stop);

    // ---- libft_strnstr
    let c = corpus(&|w| gen_strnstr(w, 5, n));
    want!(c == corpus(&|w| gen_strnstr(w, 5, n)), "strnstr corpus is not deterministic");
    want!(widest_hex(&c, 0) > past && widest_hex(&c, 1) > past, "strnstr corpus holds no big and little past 4096 bytes");
    let (mut beyond, mut exact, mut empty0, mut huge, mut nul) = (false, false, false, false, false);
    for f in rows(&c) {
        let (b, l, len) = (unhex(&f[0]), unhex(&f[1]), f[2].parse::<u64>().unwrap_or(0));
        let got = if f[3] == "NULL" { None } else { f[3].parse::<usize>().ok() };
        want!(got == alt_strnstr(&b, &l, len), "strnstr line {} {} {}", f[0], f[1], len);
        want!(len <= 4_294_967_295 || len == SIZE_MAX, "strnstr len {} is neither under 2^32 nor SIZE_MAX", len);
        let free = o_strstr(&b, &l);
        beyond |= got.is_none() && free.is_some() && len > past as u64;
        exact |= !l.is_empty() && got.is_some_and(|i| (i + l.len()) as u64 == len) && len > past as u64;
        empty0 |= l.is_empty() && len == 0 && got == Some(0);
        huge |= len == SIZE_MAX && got.is_some() && !l.is_empty();
        nul |= len > b.len() as u64 && len != SIZE_MAX && got.is_none() && !l.is_empty();
    }
    want!(beyond && exact && empty0 && huge && nul, "strnstr corpus lacks a hit past len ({}), one ending at len ({}), \"\" at len 0 ({}), SIZE_MAX ({}) or len past the NUL ({})", beyond, exact, empty0, huge, nul);

    // ---- libft_atoi
    let c = corpus(&|w| gen_atoi(w, 9, n));
    want!(c == corpus(&|w| gen_atoi(w, 9, n)), "atoi corpus is not deterministic");
    want!(widest_hex(&c, 0) > past, "atoi corpus holds no string past 4096 bytes");
    let (mut two, mut lim) = (false, 0u8);
    for f in rows(&c) {
        let s = unhex(&f[0]);
        let v = strtol10(&s);
        want!((i32::MIN as i128..=i32::MAX as i128).contains(&v), "atoi corpus overflows int: {}", f[0]);
        want!(f[1].parse::<i32>().ok() == alt_atoi(&s), "atoi line {}", f[0]);
        two |= s.windows(2).any(|p| (p[0] == b'+' || p[0] == b'-') && (p[1] == b'+' || p[1] == b'-'));
        lim |= (v == i32::MIN as i128) as u8 | (((v == i32::MAX as i128) as u8) << 1);
    }
    want!(two && lim == 3, "atoi corpus lacks two signs ({}) or both int limits ({})", two, lim);

    // ---- the reused Piscine arms, held to Libft's reading
    let c = corpus(&|w| crate::c01::gen_strlen(w, 1, n));
    want!(widest_hex(&c, 0) > past, "c01_strlen corpus holds no string past 4096 bytes");
    for f in rows(&c) {
        let s = unhex(&f[0]);
        want!(!s.contains(&0) && f[1].parse::<usize>().ok() == Some(s.len()), "c01_strlen line {} is not strlen(3)", f[0]);
    }
    let c = corpus(&|w| crate::c02::gen_strlcpy(w, 1, n));
    want!(widest_hex(&c, 0) > past && largest_dec(&c, 1) > past as i64, "c02_strlcpy corpus holds no src and size past 4096");
    for f in rows(&c) {
        let (s, size, content, ret) = (unhex(&f[0]), f[1].parse::<usize>().unwrap_or(0), unhex(&f[2]), f[3].parse::<usize>().ok());
        // "copies up to size - 1 characters ... NUL-terminating the result",
        // returning "the length of src"; the content is a C string, so no
        // byte between its terminator and size is asserted.
        let want_content = if size == 0 { Vec::new() } else { s[..s.len().min(size - 1)].to_vec() };
        want!(!s.contains(&0) && content == want_content && ret == Some(s.len()), "c02_strlcpy line {} {} is not strlcpy(3bsd)", f[0], size);
    }
    let c = corpus(&|w| crate::c07::gen_strdup(w, 1, n));
    want!(widest_hex(&c, 0) > past, "c07_strdup corpus holds no string past 4096 bytes");
    for f in rows(&c) {
        want!(f.len() == 2 && f[0] == f[1] && !unhex(&f[0]).contains(&0), "c07_strdup line {} is not strdup(3)", f[0]);
    }

    fails
}
