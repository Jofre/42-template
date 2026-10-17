//! Libft references: Part 2 string functions (subject v19.3, pages 10-12):
//! ft_substr, ft_strjoin, ft_strtrim, ft_split, ft_itoa, ft_strmapi and
//! ft_striteri. The reference emits the LOGICAL result of each call; the
//! reader harness allocates, calls and frees on the C side.
//!
//! Line formats (input fields, then the reference's answer). Byte strings
//! travel as lowercase hex, numbers in decimal:
//!   libft_substr           <hexS>\t<start>\t<len>\t<hexSub>
//!   libft_substr_readings  the same
//!   libft_strjoin          <hexS1>\t<hexS2>\t<hexJoined>
//!   libft_strtrim          <hexS1>\t<hexSet>\t<hexTrimmed>
//!   libft_split            <hexS>\t<hexC>\t<count>\t<hexTok>...\t1
//!   libft_split_readings   the same
//!   libft_itoa             <n>\t<decimal>          (the decimal RAW: digits
//!                                                   and '-' only)
//!   libft_strmapi          <hexS>\t<hexResult>\t1
//!   libft_striteri         <hexS>\t<hexAfter>\t1
//!
//! substr: `start` is an unsigned int, 0..=4294967295. `len` is a size_t,
//! and every len a corpus holds is at most 4294967295 or exactly
//! 18446744073709551615 (SIZE_MAX on LP64): a reader that parses it with
//! strtoull and converts to size_t gets the same value on an ILP32 build,
//! where 2^64-1 becomes that build's SIZE_MAX, and no other value changes.
//! The answer is the bytes from `start` on, at most `len` of them.
//!
//! WHERE THE READINGS PART. ft_substr's subject says nothing of a `start`
//! past the end of `s`. The plain arm holds only start <= strlen(s), which
//! every reading agrees on (start == strlen(s) gives ""); libft_substr_readings
//! holds only start > strlen(s), where this harness's reading is a fresh,
//! empty string. ft_split's subject says nothing of empty fields, of an empty
//! `s` or of c == '\0'. The plain arm holds only a non-empty `s`, c != '\0',
//! and no delimiter at either end or next to another, so every field is a
//! word; libft_split_readings holds only the rest, where this harness's
//! reading is that an empty field gives no string ("" and a string of
//! delimiters give an empty array, NULL-terminated and not NULL), and c ==
//! '\0' splits nothing (a non-empty `s` is one word).
//!
//! split's `<hexC>` is the one delimiter byte, two hex digits ("00" only in
//! the readings arm). The trailing 1 is the array itself: ft_split must return
//! a non-NULL array even when it holds no string, and a count of 0 cannot tell
//! that from NULL (c07_split's convention).
//!
//! THE FIXED f OF strmapi AND striteri. Both arms use one function the C
//! reader implements too, of the index i (an unsigned int) and the byte c
//! (read as an unsigned char, 1..=255):
//!
//!     f(i, c) = ((c + i) mod 255) + 1
//!
//! It depends on both arguments, never gives 0 (so a result never ends early),
//! gives bytes above 0x7f, and for every i is a bijection of 1..=255, so a
//! wrong index or a wrong byte handed to f always shows. ft_strmapi's result
//! is f(i, s[i]) for every i; ft_striteri's f stores f(i, *p) through the
//! pointer it is handed, so `s` afterwards holds the same bytes.
//!
//! strmapi's and striteri's trailing 1 is the reader's call log: 1 when f was
//! called exactly once for each index 0..strlen(s)-1, in index order, with
//! s[i] (strmapi) or the address s+i (striteri), and never for the
//! terminator. The reference always answers 1.
//!
//! Every corpus whose input has no bound (each string, the set, split's
//! words) holds a case past every round capacity (16, 64, 256, 1024, 4096),
//! and so do the outputs that have none: a split token in both split corpora
//! and substr's result in the plain one. check() reads the corpora back and
//! holds them to it, and holds every line to properties it derives apart
//! from the reference: substr's result is the slice of s at start, min(len,
//! room) bytes long, at any start (65537 among them); strmapi's and
//! striteri's give s back through f's inverse at every index (past 255).

use crate::c04::o_putnbr;
use crate::common::{bench_lines, largest_dec, long_text, many_words, o_split, rand_body, sink, to_hex, unhex, widest_hex, Rng};
use std::io::{self, Write};

/// SIZE_MAX on LP64, as the substr corpora write it.
const SIZE_MAX: u64 = u64::MAX;

/// The round capacities a corpus must reach past.
const PAST: usize = 4096;

// ------------------------------------------------------------- oracles

/// ft_substr: the bytes of `s` from `start` on, at most `len` of them; empty
/// for a `start` at or past the end (past it: this harness's reading).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_substr(s: &[u8], start: u32, len: u64) -> Vec<u8> {
    let start = start as usize;
    if start >= s.len() {
        return Vec::new();
    }
    let n = len.min((s.len() - start) as u64) as usize;
    s[start..start + n].to_vec()
}

/// Whether every reading agrees on ft_substr(s, start, _): start inside `s`
/// or on its terminator.
fn substr_agreed(s: &[u8], start: u32) -> bool {
    start as u64 <= s.len() as u64
}

/// ft_strjoin: `a` then `b`.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strjoin(a: &[u8], b: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(a.len() + b.len());
    out.extend_from_slice(a);
    out.extend_from_slice(b);
    out
}

/// ft_strtrim: `s` without the bytes of `set` at its beginning and its end.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strtrim(s: &[u8], set: &[u8]) -> Vec<u8> {
    let mut lo = 0usize;
    let mut hi = s.len();
    while lo < hi && set.contains(&s[lo]) {
        lo += 1;
    }
    while hi > lo && set.contains(&s[hi - 1]) {
        hi -= 1;
    }
    s[lo..hi].to_vec()
}

/// ft_split: the maximal runs of bytes other than `c` (common::o_split with a
/// one-byte charset). An empty field gives no string, and c == 0 splits
/// nothing, since `s` holds no NUL: this harness's reading where the two
/// matter, which only the readings corpus reaches.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_split1(s: &[u8], c: u8) -> Vec<Vec<u8>> {
    o_split(s, &[c])
}

/// Whether every reading agrees on ft_split(s, c): a non-empty `s`, a
/// delimiter that is not NUL, and no empty field (no delimiter at either end
/// or next to another).
fn split_agreed(s: &[u8], c: u8) -> bool {
    c != 0 && !s.is_empty() && s.split(|&b| b == c).all(|f| !f.is_empty())
}

/// ft_itoa: the decimal text of `n`, C 04's putnbr rendering.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_itoa(n: i32) -> Vec<u8> {
    o_putnbr(n)
}

/// The FIXED f of strmapi and striteri (module header): ((c + i) mod 255) + 1.
fn fixed_f(i: usize, c: u8) -> u8 {
    ((c as u64 + i as u64) % 255 + 1) as u8
}

/// ft_strmapi with the fixed f: f(i, s[i]) for every i.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strmapi(s: &[u8]) -> Vec<u8> {
    s.iter().enumerate().map(|(i, &c)| fixed_f(i, c)).collect()
}

/// ft_striteri with the fixed f: `s` after f stored f(i, s[i]) at every i.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_striteri(s: &[u8]) -> Vec<u8> {
    let mut v = s.to_vec();
    for (i, b) in v.iter_mut().enumerate() {
        *b = fixed_f(i, *b);
    }
    v
}

// ---------------------------------------------------------- generators

/// A seeded random C-string body of 0..max bytes, letters or every byte but NUL.
fn rand_str(rng: &mut Rng, max: usize) -> Vec<u8> {
    let high = rng.below(2) == 1;
    let n = rng.below(max);
    rand_body(rng, n, high)
}

/// Every byte but NUL, ascending.
fn all_bytes() -> Vec<u8> {
    (1u8..=255).collect()
}

/// A `len` for substr: 0, SIZE_MAX, 4294967295, 2^31, or a small one around
/// what is left of `s`.
fn substr_len(rng: &mut Rng, room: usize) -> u64 {
    match rng.below(6) {
        0 => 0,
        1 => SIZE_MAX,
        2 => u32::MAX as u64,
        3 => 1 << 31,
        _ => rng.below(room + 3) as u64,
    }
}

/// ft_substr's cases: those every reading agrees on (`part` false) or only
/// the others (`part` true). The structured head comes first, then a seeded
/// tail; a small count keeps a prefix of the head.
fn substr_cases(seed: u64, count: usize, part: bool) -> Vec<(Vec<u8>, u32, u64)> {
    let hello = b"Hello, 42!".to_vec();
    let e = b"\xe9t\xe9".to_vec();
    let big = rand_body(&mut Rng::new(5000), 5000, true);
    let mut out: Vec<(Vec<u8>, u32, u64)> = if !part {
        vec![
            (hello.clone(), 0, 5),
            (hello.clone(), 7, 2),
            (hello.clone(), 7, 100),
            (hello.clone(), 0, 0),
            (hello.clone(), 9, 1),
            (hello.clone(), 10, 5),
            (hello.clone(), 10, 0),
            (hello.clone(), 10, SIZE_MAX),
            (hello.clone(), 0, SIZE_MAX),
            (hello.clone(), 7, SIZE_MAX),
            (hello.clone(), 3, u32::MAX as u64),
            (hello.clone(), 1, 1 << 31),
            (vec![], 0, 0),
            (vec![], 0, 5),
            (vec![], 0, SIZE_MAX),
            (e.clone(), 1, 1),
            (e.clone(), 0, SIZE_MAX),
            (vec![0x01, 0x7f, 0x80, 0xff], 2, 2),
            // Capacity cases (finding 041): a result past 4096 bytes from a
            // string past it, the whole of one, a start past 65535 (where a
            // start kept in 16 bits wraps) and a start on the terminator of
            // one. Each string from a seed of its own.
            (big.clone(), 100, 4097),
            (long_text(4100, 4100), 0, SIZE_MAX),
            (long_text(70000, 70000), 65537, 10),
            (big.clone(), 5000, SIZE_MAX),
        ]
    } else {
        vec![
            (hello.clone(), 11, 0),
            (hello.clone(), 11, 5),
            (hello.clone(), 12, SIZE_MAX),
            (hello.clone(), 100, 3),
            (hello.clone(), 1 << 31, 1),
            (hello.clone(), u32::MAX, 5),
            (hello.clone(), u32::MAX, SIZE_MAX),
            (vec![], 1, 0),
            (vec![], 1, 5),
            (vec![], u32::MAX, SIZE_MAX),
            (e.clone(), 4, 1),
            // Capacity cases: strings past 4096 bytes, started past their end.
            (big.clone(), 5001, 4097),
            (big.clone(), u32::MAX, 10),
            (long_text(4100, 4100), 70000, SIZE_MAX),
        ]
    };
    out.truncate(count);
    let mut rng = Rng::new(seed);
    while out.len() < count {
        let s = rand_str(&mut rng, 40);
        let n = s.len();
        let start = if !part {
            rng.below(n + 1) as u32
        } else {
            match rng.below(4) {
                0 => u32::MAX,
                1 => (65536 + n) as u32,
                _ => (n + 1 + rng.below(50)) as u32,
            }
        };
        let len = substr_len(&mut rng, n.saturating_sub(start as usize));
        out.push((s, start, len));
    }
    out
}

fn gen_substr<W: Write>(w: &mut W, seed: u64, count: usize, part: bool) {
    for (s, start, len) in substr_cases(seed, count, part) {
        let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(&s), start, len, to_hex(&o_substr(&s, start, len)));
    }
}

fn gen_strjoin<W: Write>(w: &mut W, seed: u64, count: usize) {
    let big = rand_body(&mut Rng::new(5000), 5000, true);
    let mut cases: Vec<(Vec<u8>, Vec<u8>)> = vec![
        (b"Hello, ".to_vec(), b"42".to_vec()),
        (vec![], vec![]),
        (vec![], b"b".to_vec()),
        (b"a".to_vec(), vec![]),
        (b"\xe9".to_vec(), b"\xff".to_vec()),
        (vec![0x01, 0x7f, 0x80, 0xff], vec![0xff, 0x80]),
        (b"a\tb\n".to_vec(), b"c".to_vec()),
        // Capacity cases (finding 041): each side past 4096 bytes alone, and
        // both together; each from a seed of its own.
        (long_text(4100, 4100), big.clone()),
        (vec![], big.clone()),
        (big.clone(), vec![]),
    ];
    cases.truncate(count);
    let mut rng = Rng::new(seed);
    while cases.len() < count {
        let a = rand_str(&mut rng, 40);
        let b = rand_str(&mut rng, 40);
        cases.push((a, b));
    }
    for (a, b) in &cases {
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(a), to_hex(b), to_hex(&o_strjoin(a, b)));
    }
}

/// strtrim's capacity cases (finding 041): a string of 4100 set bytes, 5000
/// others and 4100 set bytes again; a set past 4096 bytes (every byte but NUL,
/// 'h' and 'i', over and over); a string past 4096 bytes and an empty set.
fn strtrim_capacity() -> Vec<(Vec<u8>, Vec<u8>)> {
    let set = b" \t\xe9x".to_vec();
    let mut r = Rng::new(9100);
    let edge = |r: &mut Rng| -> Vec<u8> { (0..4100).map(|_| set[r.below(set.len())]).collect() };
    let middle: Vec<u8> = (0..5000).map(|_| b'a' + r.below(23) as u8).collect();
    let mut s1 = edge(&mut r);
    s1.extend_from_slice(&middle);
    s1.extend(edge(&mut r));
    let wide: Vec<u8> = (1u8..=255).filter(|&b| b != b'h' && b != b'i').cycle().take(5000).collect();
    vec![(s1, set.clone()), (b"\x01\xffhi\x80".to_vec(), wide), (middle, vec![])]
}

fn gen_strtrim<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut cases: Vec<(Vec<u8>, Vec<u8>)> = [
        (&b"  hello  "[..], &b" "[..]),
        (b"xxhixx", b"x"),
        (b"abcHELLOcba", b"abc"),
        (b"a b", b" "),
        (b"hello", b""),
        (b"", b"abc"),
        (b"", b""),
        (b"aaaa", b"a"),
        (b"--+hi+-", b"+-+"),
        (b"xxhi", b"x"),
        (b"hixx", b"x"),
        (b"x y x", b"x"),
        (b"ab ba", b"ab"),
        (b"\xe9\xe9hi\xe9", b"\xe9"),
        (b"\x80a\x7f", b"\x7f\x80"),
        (b" \t\nhi\n\t ", b" \t\n"),
    ]
    .iter()
    .map(|(a, b)| (a.to_vec(), b.to_vec()))
    .collect();
    cases.extend(strtrim_capacity());
    cases.truncate(count);
    let mut rng = Rng::new(seed);
    let alpha: &[u8] = b"ab xy\xe9";
    while cases.len() < count {
        let (s, set) = if rng.below(2) == 0 {
            // a small alphabet the set overlaps: runs to trim at both ends
            let ls = rng.below(24);
            let s: Vec<u8> = (0..ls).map(|_| alpha[rng.below(alpha.len())]).collect();
            let lc = rng.below(4);
            let set: Vec<u8> = (0..lc).map(|_| alpha[rng.below(alpha.len())]).collect();
            (s, set)
        } else {
            // every byte but NUL, the set drawn from the string's own bytes
            let s = rand_str(&mut rng, 24);
            let lc = rng.below(4);
            let set: Vec<u8> = if s.is_empty() {
                rand_body(&mut rng, lc, true)
            } else {
                (0..lc).map(|_| s[rng.below(s.len())]).collect()
            };
            (s, set)
        };
        cases.push((s, set));
    }
    for (s, set) in &cases {
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(s), to_hex(set), to_hex(&o_strtrim(s, set)));
    }
}

/// A word of 1..=max bytes, none of them `c` or NUL: letters, or any byte.
fn split_word(rng: &mut Rng, c: u8, max: usize, high: bool) -> Vec<u8> {
    let n = 1 + rng.below(max);
    (0..n)
        .map(|_| loop {
            let b = if high { (1 + rng.below(255)) as u8 } else { b'a' + rng.below(26) as u8 };
            if b != c {
                break b;
            }
        })
        .collect()
}

/// ft_split's cases, split as substr_cases's are.
fn split_cases(seed: u64, count: usize, part: bool) -> Vec<(Vec<u8>, u8)> {
    let mut out: Vec<(Vec<u8>, u8)> = if !part {
        let mut v: Vec<(Vec<u8>, u8)> = [
            (&b"hello"[..], b' '),
            (b"a b c", b' '),
            (b"hello world 42", b' '),
            (b"a,b", b','),
            (b"abc", b'x'),
            (b"x", b'y'),
            (b"a\xe9b", 0xe9),
            (b"\xe9 \xff", b' '),
            (b"\x80\x7f\x80", 0x7f),
            (b"hello\tworld", b'\t'),
            (b"a\xffb\xffc", 0xff),
        ]
        .iter()
        .map(|(s, c)| (s.to_vec(), *c))
        .collect();
        // Capacity cases (finding 041): 5000 words, one space between each,
        // past every capacity an array of words is usually given, in a string
        // past 4096 bytes; and one word of 5000 bytes of every byte but NUL
        // and the delimiter.
        let words: Vec<String> = (0..5000).map(|i| format!("w{}", i)).collect();
        v.push((words.join(" ").into_bytes(), b' '));
        let one: Vec<u8> =
            rand_body(&mut Rng::new(5001), 5000, true).into_iter().map(|b| if b == b',' { b'x' } else { b }).collect();
        v.push((one, b','));
        v
    } else {
        let mut v: Vec<(Vec<u8>, u8)> = [
            (&b"  hello  world  "[..], b' '),
            (b"", b' '),
            (b"   ", b' '),
            (b",a,,b,", b','),
            (b"abc", 0),
            (b"", 0),
            (b",", b','),
            (b"a,", b','),
            (b",a", b','),
            (b"a,,b", b','),
            (b"\xe9\xe9a\xe9", 0xe9),
            (b"\xff", 0xff),
        ]
        .iter()
        .map(|(s, c)| (s.to_vec(), *c))
        .collect();
        // Capacity cases: 5000 words with runs of one to three spaces between
        // them and after the last; 5000 delimiters and nothing else; and a
        // string past 4096 bytes split on NUL.
        v.push((many_words(5000, b" "), b' '));
        v.push((vec![b','; 5000], b','));
        v.push((rand_body(&mut Rng::new(5002), 5000, true), 0));
        v
    };
    out.truncate(count);
    let mut rng = Rng::new(seed);
    while out.len() < count {
        if !part {
            // built to agree: one delimiter between words, none at the ends
            let high = rng.below(2) == 1;
            let c = if high { (1 + rng.below(255)) as u8 } else { b" ,;"[rng.below(3)] };
            let mut s = Vec::new();
            for k in 0..1 + rng.below(6) {
                if k > 0 {
                    s.push(c);
                }
                s.extend(split_word(&mut rng, c, 8, high));
            }
            out.push((s, c));
        } else {
            // drawn, and kept only where the readings part
            let (s, c) = match rng.below(6) {
                0 => (rand_str(&mut rng, 16), 0),
                1 => {
                    let alpha: &[u8] = &[0xe9, b'a', 0x80];
                    let n = rng.below(16);
                    ((0..n).map(|_| alpha[rng.below(3)]).collect(), 0xe9)
                }
                _ => {
                    let n = rng.below(16);
                    ((0..n).map(|_| b"ab,"[rng.below(3)]).collect(), b',')
                }
            };
            if !split_agreed(&s, c) {
                out.push((s, c));
            }
        }
    }
    out
}

fn gen_split<W: Write>(w: &mut W, seed: u64, count: usize, part: bool) {
    for (s, c) in split_cases(seed, count, part) {
        let toks = o_split1(&s, c);
        let _ = write!(w, "{}\t{}\t{}", to_hex(&s), to_hex(&[c]), toks.len());
        for t in &toks {
            let _ = write!(w, "\t{}", to_hex(t));
        }
        let _ = writeln!(w, "\t1");
    }
}

/// itoa's head: zero, one digit and its negative, the powers of ten and their
/// negatives, both ends of int and their neighbours.
const ITOA_HEAD: [i32; 20] = [
    0, 7, 42, 10, 100, 1000000000, -7, -42, -100, -1000000000, 2147483647, 2147483646, -2147483647, i32::MIN,
    1, -1, 9, -9, 99, -99,
];

fn gen_itoa<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    for k in 0..count {
        let n = if k < ITOA_HEAD.len() { ITOA_HEAD[k] } else { rng.i32val() };
        let _ = w.write_all(format!("{}\t", n).as_bytes());
        let _ = w.write_all(&o_itoa(n));
        let _ = w.write_all(b"\n");
    }
}

/// strmapi's and striteri's strings: the empty one, short ones, every byte but
/// NUL in both orders, 300 bytes of 0xff (the index passes 255, where f's
/// shift comes round again), and strings past 4096 bytes (finding 041).
fn mapi_cases(seed: u64, count: usize) -> Vec<Vec<u8>> {
    let mut out: Vec<Vec<u8>> = vec![
        vec![],
        b"a".to_vec(),
        b"aaaa".to_vec(),
        b"abc".to_vec(),
        b"Hello, 42!".to_vec(),
        all_bytes(),
        all_bytes().into_iter().rev().collect(),
        vec![0xff; 300],
        rand_body(&mut Rng::new(5000), 5000, true),
        long_text(4100, 4100),
    ];
    out.truncate(count);
    let mut rng = Rng::new(seed);
    while out.len() < count {
        out.push(rand_str(&mut rng, 40));
    }
    out
}

fn gen_mapi<W: Write>(w: &mut W, seed: u64, count: usize, iteri: bool) {
    for s in mapi_cases(seed, count) {
        let r = if iteri { o_striteri(&s) } else { o_strmapi(&s) };
        let _ = writeln!(w, "{}\t{}\t1", to_hex(&s), to_hex(&r));
    }
}

/// Every arm of this module, with its generator.
fn corpus<W: Write>(w: &mut W, name: &str, seed: u64, count: usize) -> bool {
    match name {
        "libft_substr" => gen_substr(w, seed, count, false),
        "libft_substr_readings" => gen_substr(w, seed, count, true),
        "libft_strjoin" => gen_strjoin(w, seed, count),
        "libft_strtrim" => gen_strtrim(w, seed, count),
        "libft_split" => gen_split(w, seed, count, false),
        "libft_split_readings" => gen_split(w, seed, count, true),
        "libft_itoa" => gen_itoa(w, seed, count),
        "libft_strmapi" => gen_mapi(w, seed, count, false),
        "libft_striteri" => gen_mapi(w, seed, count, true),
        _ => return false,
    }
    true
}

/// The arms, in the order check() walks them.
const ARMS: [&str; 9] = [
    "libft_substr",
    "libft_substr_readings",
    "libft_strjoin",
    "libft_strtrim",
    "libft_split",
    "libft_split_readings",
    "libft_itoa",
    "libft_strmapi",
    "libft_striteri",
];

/// The corpus generators; false for a name this module does not own.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    corpus(&mut io::BufWriter::new(io::stdout()), name, seed, count)
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !ARMS.contains(&name) {
        return false;
    }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        match name {
            "libft_substr" | "libft_substr_readings" => {
                if f.len() >= 3 {
                    if let (Ok(st), Ok(n)) = (f[1].parse::<u32>(), f[2].parse::<u64>()) {
                        sink(o_substr(&unhex(f[0]), st, n));
                    }
                }
            }
            "libft_strjoin" => {
                if f.len() >= 2 {
                    sink(o_strjoin(&unhex(f[0]), &unhex(f[1])));
                }
            }
            "libft_strtrim" => {
                if f.len() >= 2 {
                    sink(o_strtrim(&unhex(f[0]), &unhex(f[1])));
                }
            }
            "libft_split" | "libft_split_readings" => {
                if f.len() >= 2 {
                    sink(o_split1(&unhex(f[0]), unhex(f[1]).first().copied().unwrap_or(0)));
                }
            }
            "libft_itoa" => {
                if let Ok(n) = f[0].parse::<i32>() {
                    sink(o_itoa(n));
                }
            }
            "libft_strmapi" => sink(o_strmapi(&unhex(f[0]))),
            _ => sink(o_striteri(&unhex(f[0]))),
        }
    }
    true
}

// ------------------------------------------------------------- self-check

/// What an arm writes for (seed, count), as bytes.
fn written(name: &str, seed: u64, count: usize) -> Vec<u8> {
    let mut v = Vec::new();
    corpus(&mut v, name, seed, count);
    v
}

/// The lines of a corpus, each split into its fields.
fn records(corpus: &[u8]) -> Vec<Vec<String>> {
    String::from_utf8_lossy(corpus)
        .lines()
        .map(|l| l.split('\t').map(str::to_string).collect())
        .collect()
}

/// Self-check: hand-verified tables, properties over a seeded sweep, and the
/// corpora read back. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;
    let mut fail = |what: String| {
        eprintln!("CHECK FAIL libft_part2 {}", what);
        fails += 1;
    };

    // ---- substr: the subject's box, "starts at index 'start' and has a
    //      maximum length of 'len'" ----
    let hello: &[u8] = b"Hello, 42!";
    let sub: &[(&[u8], u32, u64, &[u8])] = &[
        (hello, 0, 5, b"Hello"),
        (hello, 7, 2, b"42"),
        (hello, 7, 100, b"42!"),
        (hello, 0, 0, b""),
        (hello, 9, 1, b"!"),
        (hello, 10, 5, b""),
        (hello, 0, SIZE_MAX, b"Hello, 42!"),
        (hello, 7, SIZE_MAX, b"42!"),
        (hello, 3, u32::MAX as u64, b"lo, 42!"),
        (b"", 0, 0, b""),
        (b"", 0, SIZE_MAX, b""),
        (b"\xe9t\xe9", 1, 1, b"t"),
        (b"\xe9t\xe9", 2, 1, b"\xe9"),
        // this harness's reading, start past the end: a fresh empty string
        (hello, 11, 5, b""),
        (hello, u32::MAX, SIZE_MAX, b""),
        (b"", 1, 0, b""),
    ];
    for &(s, st, n, want) in sub {
        if o_substr(s, st, n) != want {
            fail(format!("substr({:?}, {}, {})", s, st, n));
        }
    }
    for &(s, st, want) in &[(hello, 10u32, true), (hello, 11, false), (&b""[..], 0, true), (&b""[..], 1, false)] {
        if substr_agreed(s, st) != want {
            fail(format!("substr_agreed({:?}, {})", s, st));
        }
    }

    // ---- strjoin ----
    let join: &[(&[u8], &[u8], &[u8])] = &[
        (b"Hello, ", b"42", b"Hello, 42"),
        (b"", b"", b""),
        (b"", b"b", b"b"),
        (b"a", b"", b"a"),
        (b"\xe9", b"\xff", b"\xe9\xff"),
    ];
    for &(a, b, want) in join {
        if o_strjoin(a, b) != want {
            fail(format!("strjoin({:?}, {:?})", a, b));
        }
    }

    // ---- strtrim: "characters from 'set' removed from the beginning and the
    //      end", every one of them, never from the middle ----
    let trim: &[(&[u8], &[u8], &[u8])] = &[
        (b"  hello  ", b" ", b"hello"),
        (b"xxhixx", b"x", b"hi"),
        (b"abcHELLOcba", b"abc", b"HELLO"),
        (b"a b", b" ", b"a b"),
        (b"hello", b"", b"hello"),
        (b"", b"abc", b""),
        (b"", b"", b""),
        (b"aaaa", b"a", b""),
        (b"--+hi+-", b"+-+", b"hi"),
        (b"xxhi", b"x", b"hi"),
        (b"hixx", b"x", b"hi"),
        (b"x y x", b"x", b" y "),
        (b"ab ba", b"ab", b" "),
        (b"\xe9\xe9hi\xe9", b"\xe9", b"hi"),
        (b"\x80a\x7f", b"\x7f\x80", b"a"),
        (b" \t\nhi\n\t ", b" \t\n", b"hi"),
    ];
    for &(s, set, want) in trim {
        if o_strtrim(s, set) != want {
            fail(format!("strtrim({:?}, {:?})", s, set));
        }
    }

    // ---- split ----
    let toks = |v: &[&[u8]]| -> Vec<Vec<u8>> { v.iter().map(|t| t.to_vec()).collect() };
    let spl: &[(&[u8], u8, Vec<Vec<u8>>, bool)] = &[
        (b"hello", b' ', toks(&[b"hello"]), true),
        (b"a b c", b' ', toks(&[b"a", b"b", b"c"]), true),
        (b"hello world 42", b' ', toks(&[b"hello", b"world", b"42"]), true),
        (b"abc", b'x', toks(&[b"abc"]), true),
        (b"a\xe9b", 0xe9, toks(&[b"a", b"b"]), true),
        (b"\xe9 \xff", b' ', toks(&[b"\xe9", b"\xff"]), true),
        // this harness's reading: an empty field gives no string, "" and a
        // string of delimiters an empty array, and NUL splits nothing
        (b"  hello  world  ", b' ', toks(&[b"hello", b"world"]), false),
        (b"", b' ', vec![], false),
        (b"   ", b' ', vec![], false),
        (b",a,,b,", b',', toks(&[b"a", b"b"]), false),
        (b"a,", b',', toks(&[b"a"]), false),
        (b",a", b',', toks(&[b"a"]), false),
        (b"abc", 0, toks(&[b"abc"]), false),
        (b"", 0, vec![], false),
    ];
    for (s, c, want, agreed) in spl {
        if o_split1(s, *c) != *want || split_agreed(s, *c) != *agreed {
            fail(format!("split({:?}, {:#x})", s, c));
        }
    }

    // ---- itoa: "Negative numbers must be handled" ----
    let it: &[(i32, &[u8])] = &[
        (0, b"0"),
        (7, b"7"),
        (-7, b"-7"),
        (42, b"42"),
        (-42, b"-42"),
        (10, b"10"),
        (-100, b"-100"),
        (1000000000, b"1000000000"),
        (-1000000000, b"-1000000000"),
        (2147483647, b"2147483647"),
        (-2147483647, b"-2147483647"),
        (i32::MIN, b"-2147483648"),
    ];
    for &(n, want) in it {
        if o_itoa(n) != want {
            fail(format!("itoa({})", n));
        }
    }

    // ---- the fixed f, worked by hand from ((c + i) mod 255) + 1 ----
    let ff: &[(usize, u8, u8)] = &[
        (0, b'a', b'b'),
        (3, b'a', b'e'),
        (0, 0xfe, 0xff),
        (0, 0xff, 0x01),
        (1, 0xff, 0x02),
        (254, 0x01, 0x01),
        (255, b'a', b'b'),
        (0, 0x7f, 0x80),
    ];
    for &(i, c, want) in ff {
        if fixed_f(i, c) != want {
            fail(format!("fixed f({}, {:#x})", i, c));
        }
    }
    if o_strmapi(b"aaaa") != b"bcde" || o_strmapi(b"") != b"" || o_strmapi(b"\xff\xff") != b"\x01\x02" {
        fail("strmapi hand cases".to_string());
    }
    if o_striteri(b"aaaa") != b"bcde" || o_striteri(b"") != b"" {
        fail("striteri hand cases".to_string());
    }
    // f is a bijection of 1..=255 for every index the corpora reach past, never
    // 0, and moves with both arguments.
    for i in [0usize, 1, 254, 255, 256, 4097, 69999] {
        let mut seen = [false; 256];
        for c in 1u8..=255 {
            let v = fixed_f(i, c);
            if v == 0 || seen[v as usize] || v == fixed_f(i + 1, c) {
                fail(format!("fixed f is not a bijection that moves with i at i={}", i));
                break;
            }
            seen[v as usize] = true;
        }
    }

    // ---- properties over a seeded sweep (20 000) ----
    let mut rng = Rng::new(0x11bf2);
    for _ in 0..20000 {
        let s = rand_str(&mut rng, 30);
        let n = s.len();

        // substr: a slice of s at start, as long as len and the room allow
        let start = rng.below(n + 4) as u32;
        let len = substr_len(&mut rng, n);
        let r = o_substr(&s, start, len);
        let room = n.saturating_sub(start as usize) as u64;
        if r.len() as u64 != len.min(room) || (!r.is_empty() && s[start as usize..start as usize + r.len()] != r[..]) {
            fail(format!("substr property ({:?}, {}, {})", s, start, len));
        }

        // strjoin: a then b, nothing between
        let b = rand_str(&mut rng, 30);
        let j = o_strjoin(&s, &b);
        if j.len() != n + b.len() || j[..n] != s[..] || j[n..] != b[..] {
            fail("strjoin property".to_string());
        }

        // strtrim: a slice of s whose ends are not in set, with only set
        // bytes cut on either side; trimming twice changes nothing
        let set: Vec<u8> = (0..rng.below(4)).map(|_| if n > 0 { s[rng.below(n)] } else { b'a' }).collect();
        let t = o_strtrim(&s, &set);
        let at = (0..=n - t.len()).find(|&k| s[k..k + t.len()] == t[..] && s[..k].iter().all(|x| set.contains(x)));
        let ok = match at {
            Some(k) => s[k + t.len()..].iter().all(|x| set.contains(x)),
            None => false,
        };
        if !ok
            || t.first().is_some_and(|x| set.contains(x))
            || t.last().is_some_and(|x| set.contains(x))
            || o_strtrim(&t, &set) != t
        {
            fail(format!("strtrim property ({:?}, {:?})", s, set));
        }

        // split: no token is empty or holds c; the tokens are s without its
        // delimiters; where the readings agree, joining them with c gives s
        let c = if n > 0 && rng.below(2) == 0 { s[rng.below(n)] } else { (rng.below(256)) as u8 };
        let tk = o_split1(&s, c);
        let rest: Vec<u8> = s.iter().copied().filter(|&x| x != c).collect();
        if tk.iter().any(|t| t.is_empty() || t.contains(&c)) || tk.concat() != rest {
            fail(format!("split property ({:?}, {:#x})", s, c));
        }
        if split_agreed(&s, c) && tk.join(&[c][..]) != s {
            fail(format!("split round trip ({:?}, {:#x})", s, c));
        }

        // itoa: reads back to n, '-' only for a negative, no leading zero
        let v = rng.i32val();
        let txt = o_itoa(v);
        let back = std::str::from_utf8(&txt).ok().and_then(|x| x.parse::<i32>().ok());
        let digits = if v < 0 { &txt[1..] } else { &txt[..] };
        if back != Some(v) || (txt[0] == b'-') != (v < 0) || (digits.len() > 1 && digits[0] == b'0') {
            fail(format!("itoa property {}", v));
        }

        // strmapi / striteri: as long as s, no NUL, and s comes back from the
        // result through f's inverse at every index
        let m = o_strmapi(&s);
        let undo = m.iter().enumerate().all(|(i, &y)| (y as u64 - 1 + 255 - i as u64 % 255) % 255 == s[i] as u64 % 255);
        if m.len() != n || m.contains(&0) || !undo || o_striteri(&s) != m {
            fail(format!("strmapi/striteri property {:?}", s));
        }
    }

    // ---- the corpora, read back ----
    let count = 300usize;
    for name in ARMS {
        let a = written(name, 1, count);
        if a != written(name, 1, count) {
            fail(format!("{}: the same seed gave another corpus", name));
        }
        if a == written(name, 2, count) {
            fail(format!("{}: another seed gave the same corpus", name));
        }
        let recs = records(&a);
        if recs.len() != count {
            fail(format!("{}: {} lines for a count of {}", name, recs.len(), count));
        }
        if written(name, 1, 3).len() >= a.len() || !a.starts_with(&written(name, 1, 3)) {
            fail(format!("{}: a small count is not a prefix of the corpus", name));
        }
        // Each answer is the reference's own for the inputs on its line.
        for r in &recs {
            let ok = match name {
                "libft_substr" | "libft_substr_readings" => {
                    let s = unhex(&r[0]);
                    match (r[1].parse::<u32>(), r[2].parse::<u64>()) {
                        (Ok(st), Ok(n)) => {
                            // and, apart from o_substr, the slice of s at
                            // start, min(len, room) bytes long, at any start
                            let room = (s.len() as u64).saturating_sub(st as u64);
                            let k = n.min(room) as usize;
                            let slice: &[u8] = if k == 0 { &[] } else { &s[st as usize..st as usize + k] };
                            r.len() == 4
                                && unhex(&r[3]) == o_substr(&s, st, n)
                                && unhex(&r[3]) == slice
                                && substr_agreed(&s, st) == (name == "libft_substr")
                                && (n <= u32::MAX as u64 || n == SIZE_MAX)
                        }
                        _ => false,
                    }
                }
                "libft_strjoin" => r.len() == 3 && unhex(&r[2]) == o_strjoin(&unhex(&r[0]), &unhex(&r[1])),
                "libft_strtrim" => r.len() == 3 && unhex(&r[2]) == o_strtrim(&unhex(&r[0]), &unhex(&r[1])),
                "libft_split" | "libft_split_readings" => {
                    let s = unhex(&r[0]);
                    let c = unhex(&r[1]);
                    let tk: Vec<Vec<u8>> = r[3..r.len().saturating_sub(1)].iter().map(|t| unhex(t)).collect();
                    r.len() >= 4
                        && r[1].len() == 2
                        && !s.contains(&0)
                        && r[r.len() - 1] == "1"
                        && r[2].parse::<usize>() == Ok(tk.len())
                        && tk == o_split1(&s, c[0])
                        && split_agreed(&s, c[0]) == (name == "libft_split")
                }
                "libft_itoa" => r.len() == 2 && r[0].parse::<i32>().is_ok_and(|n| r[1].as_bytes() == o_itoa(n)),
                _ => {
                    let s = unhex(&r[0]);
                    let want = if name == "libft_strmapi" { o_strmapi(&s) } else { o_striteri(&s) };
                    // and, apart from the reference, s comes back through f's
                    // inverse at every index, however far past 255
                    let y = unhex(&r[1]);
                    let undo = y.len() == s.len()
                        && !y.contains(&0)
                        && y.iter().zip(&s).enumerate().all(|(i, (&y, &c))| {
                            (y as u64 + 254 - i as u64 % 255) % 255 == c as u64 % 255
                        });
                    r.len() == 3 && !s.contains(&0) && y == want && undo && r[2] == "1"
                }
            };
            if !ok {
                fail(format!("{}: a line that is not the reference's own answer, or breaks a property: {:.120}", name, r.join("\t")));
                break;
            }
        }
        // No input holds a NUL where a C string is read.
        if name != "libft_itoa" && recs.iter().any(|r| unhex(&r[0]).contains(&0)) {
            fail(format!("{}: an input string holds a NUL", name));
        }
        // Every unbounded input reaches past every round capacity (finding 041).
        let wide: &[usize] = match name {
            "libft_strjoin" | "libft_strtrim" => &[0, 1],
            "libft_itoa" => &[],
            _ => &[0],
        };
        for &k in wide {
            if widest_hex(&a, k) <= PAST {
                fail(format!("{}: field {} holds nothing past {} bytes", name, k, PAST));
            }
        }
        if name.starts_with("libft_split") && largest_dec(&a, 2) <= PAST as i64 {
            fail(format!("{}: no case of more than {} words", name, PAST));
        }
        // ...and so does what comes out: a token, and substr's result
        if name.starts_with("libft_split")
            && !recs.iter().any(|r| r.len() > 4 && r[3..r.len() - 1].iter().any(|t| t.len() / 2 > PAST))
        {
            fail(format!("{}: no token past {} bytes", name, PAST));
        }
        if name == "libft_substr" && widest_hex(&a, 3) <= PAST {
            fail(format!("{}: no result past {} bytes", name, PAST));
        }
        if name == "libft_strtrim" || name == "libft_strjoin" {
            // each side past 4096 alone, with the other short
            for k in [0usize, 1] {
                let alone = recs.iter().any(|r| r[k].len() / 2 > PAST && r[1 - k].len() / 2 < 16);
                if !alone {
                    fail(format!("{}: no case where field {} alone is past {} bytes", name, k, PAST));
                }
            }
        }
    }

    // ---- what each corpus is there to hold ----
    let has = |name: &str, what: &str, p: &dyn Fn(&[String]) -> bool| -> Option<String> {
        if records(&written(name, 1, count)).iter().any(|r| p(r)) {
            None
        } else {
            Some(format!("{}: no case of {}", name, what))
        }
    };
    let need: Vec<Option<String>> = vec![
        has("libft_substr", "start on the terminator", &|r| r[1].parse::<usize>() == Ok(r[0].len() / 2)),
        has("libft_substr", "len SIZE_MAX past start 0", &|r| r[2] == SIZE_MAX.to_string() && r[1] != "0"),
        has("libft_substr", "a start past 65535", &|r| r[1].parse::<u32>().is_ok_and(|s| s > 65535)),
        has("libft_substr", "a byte above 0x7f", &|r| unhex(&r[0]).iter().any(|&b| b > 0x7f)),
        has("libft_substr_readings", "start one past the terminator", &|r| {
            r[1].parse::<usize>() == Ok(r[0].len() / 2 + 1)
        }),
        has("libft_substr_readings", "start 4294967295", &|r| r[1] == u32::MAX.to_string()),
        has("libft_substr_readings", "an empty s", &|r| r[0].is_empty()),
        has("libft_strtrim", "an empty set", &|r| r[1].is_empty()),
        has("libft_strtrim", "a string of set bytes only", &|r| !r[0].is_empty() && r[2].is_empty()),
        has("libft_strtrim", "a set byte kept in the middle", &|r| {
            let t = unhex(&r[2]);
            let set = unhex(&r[1]);
            t.len() > 2 && t[1..t.len() - 1].iter().any(|x| set.contains(x))
        }),
        has("libft_split", "a delimiter above 0x7f", &|r| unhex(&r[1])[0] > 0x7f),
        has("libft_split", "a delimiter absent from s", &|r| r[2] == "1"),
        has("libft_split_readings", "an empty s", &|r| r[0].is_empty()),
        has("libft_split_readings", "c == NUL", &|r| r[1] == "00"),
        has("libft_split_readings", "delimiters only", &|r| !r[0].is_empty() && r[2] == "0" && r[1] != "00"),
        has("libft_split_readings", "a doubled delimiter", &|r| {
            let s = unhex(&r[0]);
            let c = unhex(&r[1])[0];
            c != 0 && s.windows(2).any(|w| w == [c, c])
        }),
        has("libft_split_readings", "a delimiter at the start", &|r| {
            let s = unhex(&r[0]);
            s.len() > 1 && s[0] == unhex(&r[1])[0]
        }),
        has("libft_split_readings", "a delimiter at the end", &|r| {
            let s = unhex(&r[0]);
            s.len() > 1 && s[s.len() - 1] == unhex(&r[1])[0]
        }),
        has("libft_itoa", "INT_MIN", &|r| r[0] == i32::MIN.to_string()),
        has("libft_itoa", "INT_MAX", &|r| r[0] == i32::MAX.to_string()),
        has("libft_itoa", "zero", &|r| r[0] == "0"),
        has("libft_strmapi", "the empty string", &|r| r[0].is_empty()),
        has("libft_strmapi", "an index past 255", &|r| r[0].len() / 2 > 256),
        has("libft_striteri", "the empty string", &|r| r[0].is_empty()),
    ];
    for msg in need.into_iter().flatten() {
        fail(msg);
    }
    if corpus(&mut Vec::new(), "libft_nope", 1, 1) || bench("libft_nope") {
        fail("an unknown arm was claimed".to_string());
    }

    fails
}
