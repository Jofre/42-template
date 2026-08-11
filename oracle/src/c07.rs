//! c-07 allocation family references (strdup, range, ultimate_range, strjoin,
//! convert_base, split). The reference emits the LOGICAL result of each call;
//! the reader harness allocates/frees on the C side. See oracle/README.md for
//! the per-function corpus-line format.

use crate::common::{bench_lines, o_split, rand_body, sink, to_hex, unhex, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles

/// ft_strdup: the duplicate equals the source byte-for-byte.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strdup(src: &[u8]) -> Vec<u8> {
    src.to_vec()
}

/// ft_range: half-open [min, max). Empty (min >= max) => None.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_range(min: i64, max: i64) -> Option<Vec<i64>> {
    if min >= max {
        return None;
    }
    Some((min..max).collect())
}

/// ft_strjoin: concatenate the first `size` strings, `sep` in every gap.
/// size 0 => an (allocated) empty string.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strjoin(size: usize, strs: &[Vec<u8>], sep: &[u8]) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::new();
    let mut i = 0usize;
    while i < size {
        if i > 0 {
            out.extend_from_slice(sep);
        }
        out.extend_from_slice(&strs[i]);
        i += 1;
    }
    out
}

// ----------------------------------------------------- convert_base helpers
const WS: [u8; 6] = [b' ', 9, 10, 11, 12, 13];

/// The two halves of base validity, kept apart because c-07's two base
/// arguments are not doing the same job.
///
/// `ft_convert_base` says "nbr will follow the same rules as ft_atoi_base (from
/// another module). Beware of the characters '+', '-', and whitespaces." So
/// base_from is PARSED, exactly as ft_atoi_base parses, and ft_atoi_base's
/// subject is explicit that its base may not contain "'+', '-', or whitespace
/// characters". base_to is only ever PRINTED with, which is ft_putnbr_base's
/// job, and that subject lists three invalid shapes and does not include
/// whitespace.
///
/// The alternative reading -- whitespace invalid in BOTH -- would reject a
/// `base_to` the subject never forbids, and rejecting a correct student is the
/// one failure this reference must not have. Where the subject is silent, take
/// the reading that fails fewer correct programs.
fn base_valid_display(base: &[u8]) -> bool {
    if base.len() < 2 {
        return false;
    }
    for (i, &c) in base.iter().enumerate() {
        if c == b'+' || c == b'-' {
            return false;
        }
        if base[..i].contains(&c) {
            return false;
        }
    }
    true
}

fn base_valid_parse(base: &[u8]) -> bool {
    base_valid_display(base) && !base.iter().any(|c| WS.contains(c))
}

/// Render a magnitude (>=0) in `base`. mag 0 => the base's zero symbol.
fn render_mag(mag: u64, base: &[u8]) -> Vec<u8> {
    if mag == 0 {
        return vec![base[0]];
    }
    let b = base.len() as u64;
    let mut m = mag;
    let mut out: Vec<u8> = Vec::new();
    while m > 0 {
        out.push(base[(m % b) as usize]);
        m /= b;
    }
    out.reverse();
    out
}

/// Render a signed value in `base` (leading '-' for negatives).
fn render_val(value: i64, base: &[u8]) -> Vec<u8> {
    if value == 0 {
        return vec![base[0]];
    }
    let neg = value < 0;
    let mut v = render_mag(value.unsigned_abs(), base);
    if neg {
        v.insert(0, b'-');
    }
    v
}

/// atoi_base: skip whitespace, fold sign runs, read leading digits in `base`.
fn parse_base(nbr: &[u8], base: &[u8]) -> i64 {
    let n = nbr.len();
    let mut i = 0usize;
    while i < n && WS.contains(&nbr[i]) {
        i += 1;
    }
    let mut sign: i64 = 1;
    while i < n && (nbr[i] == b'+' || nbr[i] == b'-') {
        if nbr[i] == b'-' {
            sign = -sign;
        }
        i += 1;
    }
    let b = base.len() as i64;
    let mut res: i64 = 0;
    while i < n {
        if let Some(d) = base.iter().position(|&c| c == nbr[i]) {
            res = res * b + d as i64;
            i += 1;
        } else {
            break;
        }
    }
    sign * res
}

/// Full convert_base: None when either base is unusable.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_convert_base(nbr: &[u8], from: &[u8], to: &[u8]) -> Option<Vec<u8>> {
    if !base_valid_parse(from) || !base_valid_display(to) {
        return None;
    }
    Some(render_val(parse_base(nbr, from), to))
}

// ---------------------------------------------------------- generators

/// A random C-string body of length `len` never containing 0x00.
fn body(rng: &mut Rng, len: usize, high: bool) -> Vec<u8> {
    rand_body(rng, len, high)
}

fn gen_strdup(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    // structured: empty, single, ascii text, full-range bytes.
    let fixed: Vec<Vec<u8>> = vec![
        vec![],
        b"a".to_vec(),
        b"42 Barcelona".to_vec(),
        b"\t hi \n".to_vec(),
        vec![0x01, 0x7f, 0x80, 0xff],
    ];
    for s in &fixed {
        if done >= count {
            break;
        }
        let _ = writeln!(w, "{}\t{}", to_hex(s), to_hex(&o_strdup(s)));
        done += 1;
    }
    while done < count {
        let high = rng.below(2) == 1;
        let len = rng.below(40);
        let s = body(&mut rng, len, high);
        let _ = writeln!(w, "{}\t{}", to_hex(&s), to_hex(&o_strdup(&s)));
        done += 1;
    }
}

/// Small [min,max) pairs (many empty / negative / crossing zero).
fn range_pairs(rng: &mut Rng, count: usize) -> Vec<(i64, i64)> {
    let mut out: Vec<(i64, i64)> = vec![
        (1, 5),
        (-3, 3),
        (0, 1),
        (42, 43),
        (-5, -2),
        (5, 5),
        (10, 3),
        (0, 0),
        (-1, 0),
        (-20, -19),
        (100, 120),
        // int boundary corners (sizes 0/1/2 so a correct impl never overflows).
        (2147483646, 2147483647),   // single element just below INT_MAX
        (2147483647, 2147483647),   // empty at INT_MAX -> NULL
        (2147483645, 2147483647),   // two elements ending at INT_MAX
        (-2147483648, -2147483647), // single element at INT_MIN
        (-2147483648, -2147483648), // empty at INT_MIN -> NULL
        (-2147483648, -2147483646), // two elements starting at INT_MIN
    ];
    while out.len() < count {
        let min = (rng.below(1001) as i64) - 500;
        let d = (rng.below(26) as i64) - 5; // -5..=20
        out.push((min, min + d));
    }
    out
}

fn gen_range(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = range_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (min, max) in pairs.iter().take(count) {
        let res = match o_range(*min, *max) {
            None => "NULL".to_string(),
            Some(v) => v
                .iter()
                .map(|x| x.to_string())
                .collect::<Vec<_>>()
                .join(","),
        };
        let _ = writeln!(w, "{}\t{}\t{}", min, max, res);
    }
}

fn gen_ultimate_range(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = range_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (min, max) in pairs.iter().take(count) {
        let (ret, res) = match o_range(*min, *max) {
            None => (0i64, "NULL".to_string()),
            Some(v) => (
                v.len() as i64,
                v.iter()
                    .map(|x| x.to_string())
                    .collect::<Vec<_>>()
                    .join(","),
            ),
        };
        let _ = writeln!(w, "{}\t{}\t{}\t{}", min, max, ret, res);
    }
}

fn gen_strjoin(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;

    // structured mirrors of the curated cases.
    let fixed: Vec<(Vec<Vec<u8>>, Vec<u8>)> = vec![
        (vec![b"Hello".to_vec()], b"-".to_vec()),
        (vec![b"ab".to_vec(), b"cd".to_vec()], b"-".to_vec()),
        (
            vec![b"Hello".to_vec(), b"World".to_vec(), b"42".to_vec()],
            b", ".to_vec(),
        ),
        (vec![b"Hello".to_vec(), b"World".to_vec()], b"".to_vec()),
        (
            vec![b"".to_vec(), b"x".to_vec(), b"".to_vec()],
            b"-".to_vec(),
        ),
        (vec![], b"-".to_vec()),
        // corners: single empty element (size 1 -> "" with no sep emitted),
        // all-empty elements with a non-empty sep (-> just the joins), and a
        // multi-element join with an empty separator.
        (vec![b"".to_vec()], b"-".to_vec()),
        (vec![b"".to_vec(), b"".to_vec()], b"ab".to_vec()),
        (
            vec![b"a".to_vec(), b"b".to_vec(), b"c".to_vec()],
            b"".to_vec(),
        ),
    ];
    for (strs, sep) in &fixed {
        if done >= count {
            break;
        }
        let size = strs.len();
        emit_strjoin(&mut w, size, strs, sep);
        done += 1;
    }
    while done < count {
        let size = rng.below(6);
        let mut strs: Vec<Vec<u8>> = Vec::with_capacity(size);
        let high = rng.below(2) == 1;
        for _ in 0..size {
            let l = rng.below(8);
            strs.push(body(&mut rng, l, high));
        }
        let sl = rng.below(4);
        let sep = body(&mut rng, sl, high);
        emit_strjoin(&mut w, size, &strs, &sep);
        done += 1;
    }
}

fn emit_strjoin<W: Write>(w: &mut W, size: usize, strs: &[Vec<u8>], sep: &[u8]) {
    let res = o_strjoin(size, strs, sep);
    let _ = write!(w, "{}\t{}\t{}\t", size, size, to_hex(sep));
    for s in strs.iter().take(size) {
        let _ = write!(w, "{}\t", to_hex(s));
    }
    let _ = writeln!(w, "{}", to_hex(&res));
}

// ------------------------------------------------ convert_base generation
fn valid_bases() -> Vec<Vec<u8>> {
    vec![
        b"01".to_vec(),
        b"012".to_vec(),
        b"0123456789".to_vec(),
        b"0123456789abcdef".to_vec(),
        b"0123456789ABCDEF".to_vec(),
        b"abcdef".to_vec(),
        b"poneyvif".to_vec(),
        b"0123456789abcdefghijklmnopqrstuvwxyz".to_vec(),
    ]
}

fn invalid_bases() -> Vec<Vec<u8>> {
    vec![
        b"".to_vec(),
        b"0".to_vec(),
        b"aa".to_vec(),
        b"01+".to_vec(),
        b"01-".to_vec(),
        b"0120".to_vec(),
        b"0123456789+".to_vec(),
    ]
}

fn pick_i32(rng: &mut Rng) -> i64 {
    match rng.below(10) {
        0 => 0,
        1 => i32::MAX as i64,
        2 => i32::MIN as i64,
        3 => -(rng.below(1000) as i64),
        4 => rng.below(1000) as i64,
        5 => rng.below(1_000_000) as i64,
        6 => -(rng.below(1_000_000) as i64),
        _ => (rng.next_u64() as i32) as i64,
    }
}

/// A byte guaranteed not to be a `base` digit (stops a parse).
fn junk_byte(base: &[u8]) -> u8 {
    for c in b'a'..=b'z' {
        if !base.contains(&c) {
            return c;
        }
    }
    for c in b'A'..=b'Z' {
        if !base.contains(&c) {
            return c;
        }
    }
    b'.'
}

/// Build an nbr string that atoi_base(., from) parses to exactly `v`.
fn build_nbr(rng: &mut Rng, v: i64, from: &[u8]) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::new();
    // leading whitespace
    let wsn = rng.below(3);
    for _ in 0..wsn {
        out.push(WS[rng.below(6)]);
    }
    // sign run with the right parity of '-'
    let mut signs: Vec<u8> = Vec::new();
    let pairs = rng.below(3);
    for _ in 0..(pairs * 2 + if v < 0 { 1 } else { 0 }) {
        signs.push(b'-');
    }
    for _ in 0..rng.below(3) {
        signs.push(b'+');
    }
    // deterministic shuffle (order is irrelevant to the parity result)
    let sl = signs.len();
    for i in 0..sl {
        let j = rng.below(sl);
        signs.swap(i, j);
    }
    out.extend_from_slice(&signs);
    // optional leading zeros then the magnitude digits
    for _ in 0..rng.below(3) {
        out.push(from[0]);
    }
    out.extend(render_mag(v.unsigned_abs(), from));
    // optional trailing junk (parse stops at the first non-digit)
    if rng.below(2) == 0 {
        out.push(junk_byte(from));
        for _ in 0..rng.below(3) {
            out.push(b'a' + (rng.below(26) as u8));
        }
    }
    out
}

fn emit_convert<W: Write>(w: &mut W, nbr: &[u8], from: &[u8], to: &[u8]) {
    let res = match o_convert_base(nbr, from, to) {
        None => "NULL".to_string(),
        Some(v) => to_hex(&v),
    };
    let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(nbr), to_hex(from), to_hex(to), res);
}

fn gen_convert_base(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;

    let fixed: Vec<(&[u8], &[u8], &[u8])> = vec![
        (b"42", b"0123456789", b"01"),
        (b"0", b"0123456789", b"01"),
        (b"+42", b"0123456789", b"0123456789"),
        (b"FF", b"0123456789ABCDEF", b"0123456789"),
        (b"-42", b"0123456789", b"0123456789ABCDEF"),
        (b"101010", b"01", b"0123456789"),
        (b"ff", b"0123456789abcdef", b"0123456789ABCDEF"),
        (b"   ---+--+42ab", b"0123456789", b"01"),
        (b"2147483647", b"0123456789", b"0123456789ABCDEF"),
        (b"-2147483648", b"0123456789", b"0123456789ABCDEF"),
        (b"42", b"0123456789", b"bad+base"),
        (b"42", b"0123456789", b"aa"),
        (b"42", b"0", b"0123456789"),
        (b"42", b"0123456789", b""),
        (b"42", b"01+", b"0123456789"),
        (b"42", b"0123456789", b"01-"),
        (b"42", b"00", b"0123456789"),
        // nbr corners that all parse to value 0.
        (b"", b"0123456789", b"01"),             // empty nbr
        (b"-", b"0123456789", b"0123456789"),    // lone sign
        (b"+-+", b"0123456789", b"0123456789"),  // sign run, no digits
        (b"   ", b"0123456789", b"0123456789"),  // whitespace only
        (b"z", b"0123456789", b"0123456789"),    // leading junk, no digits
        (b"0", b"0123456789", b"poneyvif"),      // zero -> the to-base's zero symbol
    ];
    for (nbr, from, to) in &fixed {
        if done >= count {
            break;
        }
        emit_convert(&mut w, nbr, from, to);
        done += 1;
    }

    let vb = valid_bases();
    let ib = invalid_bases();
    while done < count {
        let mode = rng.below(6);
        if mode == 0 {
            // invalid base somewhere => expect NULL
            let good = &vb[rng.below(vb.len())];
            let bad = &ib[rng.below(ib.len())];
            let v = pick_i32(&mut rng);
            let nbr = build_nbr(&mut rng, v, good);
            if rng.below(2) == 0 {
                emit_convert(&mut w, &nbr, bad, good);
            } else {
                emit_convert(&mut w, &nbr, good, bad);
            }
        } else {
            let from = &vb[rng.below(vb.len())];
            let to = &vb[rng.below(vb.len())];
            let v = pick_i32(&mut rng);
            let nbr = build_nbr(&mut rng, v, from);
            emit_convert(&mut w, &nbr, from, to);
        }
        done += 1;
    }
}

// --------------------------------------------------------- split generation
fn gen_split(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;

    let fixed: Vec<(&[u8], &[u8])> = vec![
        (b"hello", b" "),
        (b"a b c", b" "),
        (b"  hello   world 42 ", b" "),
        (b"a,b;c", b",;"),
        (b"a,,;,b", b",;"),
        (b"hello world", b""),
        (b"", b" "),
        (b"   ", b" "),
        (b"x", b"x"),       // lone char that IS a separator -> 0 tokens
        (b"x", b"y"),       // lone char, not a separator -> 1 token
        (b",", b",;"),      // one separator byte only -> 0 tokens
        (b"hello", b"xyz"), // charset disjoint from str -> 1 whole token
        (b",hello,", b","), // leading + trailing separators -> 1 token
    ];
    for (s, cs) in &fixed {
        if done >= count {
            break;
        }
        emit_split(&mut w, s, cs);
        done += 1;
    }

    let alpha: &[u8] = b"abcd ,;.";
    while done < count {
        let mode = rng.below(3);
        let (s, cs): (Vec<u8>, Vec<u8>) = match mode {
            0 => {
                // small alphabet that overlaps the charset -> real splits
                let ls = rng.below(24);
                let s: Vec<u8> = (0..ls).map(|_| alpha[rng.below(alpha.len())]).collect();
                let seps: &[u8] = b" ,;.";
                let lc = rng.below(4);
                let cs: Vec<u8> = (0..lc).map(|_| seps[rng.below(seps.len())]).collect();
                (s, cs)
            }
            1 => {
                // full-range bytes, a few random separators
                let high = rng.below(2) == 1;
                let sl = rng.below(20);
                let s = body(&mut rng, sl, high);
                let lc = rng.below(4);
                let cs = if lc == 0 || s.is_empty() {
                    body(&mut rng, lc, high)
                } else {
                    // pick separators FROM s so at least some split
                    (0..lc).map(|_| s[rng.below(s.len())]).collect()
                };
                (s, cs)
            }
            _ => {
                // empty charset -> whole string is one token
                let sl = rng.below(20);
                let high = rng.below(2) == 1;
                let s = body(&mut rng, sl, high);
                (s, vec![])
            }
        };
        emit_split(&mut w, &s, &cs);
        done += 1;
    }
}

fn emit_split<W: Write>(w: &mut W, s: &[u8], charset: &[u8]) {
    let toks = o_split(s, charset);
    let _ = write!(w, "{}\t{}\t{}", to_hex(s), to_hex(charset), toks.len());
    for t in &toks {
        let _ = write!(w, "\t{}", to_hex(t));
    }
    // trailing 1: ft_split must return a NON-NULL allocated array even when it
    // yields zero tokens (empty/all-separator input). The token count alone
    // cannot distinguish that from a NULL return, so assert it explicitly.
    let _ = writeln!(w, "\t1");
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c07_strdup" => gen_strdup(seed, count),
        "c07_range" => gen_range(seed, count),
        "c07_ultimate_range" => gen_ultimate_range(seed, count),
        "c07_strjoin" => gen_strjoin(seed, count),
        "c07_convert_base" => gen_convert_base(seed, count),
        "c07_split" => gen_split(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- strdup: independent copy, byte-equal.
    for s in [b"".as_ref(), b"a", b"hello", &[0x01, 0xff, 0x80]] {
        if o_strdup(s) != s.to_vec() {
            eprintln!("CHECK FAIL c07 strdup {:?}", s);
            fails += 1;
        }
    }

    // ---- range hand cases (mirror the curated expected.txt).
    let rc: &[(i64, i64, Option<Vec<i64>>)] = &[
        (1, 5, Some(vec![1, 2, 3, 4])),
        (-3, 3, Some(vec![-3, -2, -1, 0, 1, 2])),
        (0, 1, Some(vec![0])),
        (-5, -2, Some(vec![-5, -4, -3])),
        (5, 5, None),
        (10, 3, None),
    ];
    for (min, max, want) in rc {
        if o_range(*min, *max) != *want {
            eprintln!("CHECK FAIL c07 range({},{})", min, max);
            fails += 1;
        }
    }

    // ---- strjoin hand cases.
    let sj: &[(usize, &[&[u8]], &[u8], &[u8])] = &[
        (1, &[b"Hello"], b"-", b"Hello"),
        (2, &[b"ab", b"cd"], b"-", b"ab-cd"),
        (3, &[b"Hello", b"World", b"42"], b", ", b"Hello, World, 42"),
        (2, &[b"Hello", b"World"], b"", b"HelloWorld"),
        (3, &[b"", b"x", b""], b"-", b"-x-"),
        (0, &[], b"-", b""),
        (1, &[b""], b"-", b""),
        (2, &[b"", b""], b"ab", b"ab"),
        (3, &[b"a", b"b", b"c"], b"", b"abc"),
    ];
    for (size, strs, sep, want) in sj {
        let sv: Vec<Vec<u8>> = strs.iter().map(|x| x.to_vec()).collect();
        if o_strjoin(*size, &sv, sep) != want.to_vec() {
            eprintln!("CHECK FAIL c07 strjoin {:?}", strs);
            fails += 1;
        }
    }

    // ---- convert_base hand cases (mirror curated expected.txt).
    let cb: &[(&[u8], &[u8], &[u8], Option<&[u8]>)] = &[
        (b"42", b"0123456789", b"01", Some(b"101010")),
        (b"0", b"0123456789", b"01", Some(b"0")),
        (b"+42", b"0123456789", b"0123456789", Some(b"42")),
        (b"FF", b"0123456789ABCDEF", b"0123456789", Some(b"255")),
        (b"-42", b"0123456789", b"0123456789ABCDEF", Some(b"-2A")),
        (b"101010", b"01", b"0123456789", Some(b"42")),
        (b"ff", b"0123456789abcdef", b"0123456789ABCDEF", Some(b"FF")),
        (b"   ---+--+42ab", b"0123456789", b"01", Some(b"-101010")),
        (b"2147483647", b"0123456789", b"0123456789ABCDEF", Some(b"7FFFFFFF")),
        (b"-2147483648", b"0123456789", b"0123456789ABCDEF", Some(b"-80000000")),
        (b"42", b"0123456789", b"bad+base", None),
        (b"42", b"0123456789", b"aa", None),
        (b"42", b"0", b"0123456789", None),
        (b"42", b"0123456789", b"", None),
        (b"42", b"01+", b"0123456789", None),
        (b"42", b"0123456789", b"01-", None),
        (b"42", b"00", b"0123456789", None),
        (b"", b"0123456789", b"01", Some(b"0")),
        (b"-", b"0123456789", b"0123456789", Some(b"0")),
        (b"+-+", b"0123456789", b"0123456789", Some(b"0")),
        (b"   ", b"0123456789", b"0123456789", Some(b"0")),
        (b"z", b"0123456789", b"0123456789", Some(b"0")),
        (b"0", b"0123456789", b"poneyvif", Some(b"p")),
    ];
    for (nbr, from, to, want) in cb {
        let got = o_convert_base(nbr, from, to);
        let want_v = want.map(|w| w.to_vec());
        if got != want_v {
            eprintln!(
                "CHECK FAIL c07 convert_base({:?},{:?},{:?}) got {:?}",
                nbr, from, to, got
            );
            fails += 1;
        }
    }

    // ---- split hand cases.
    let sp: &[(&[u8], &[u8], &[&[u8]])] = &[
        (b"hello", b" ", &[b"hello"]),
        (b"a b c", b" ", &[b"a", b"b", b"c"]),
        (b"  hello   world 42 ", b" ", &[b"hello", b"world", b"42"]),
        (b"a,b;c", b",;", &[b"a", b"b", b"c"]),
        (b"a,,;,b", b",;", &[b"a", b"b"]),
        (b"hello world", b"", &[b"hello world"]),
        (b"", b" ", &[]),
        (b"   ", b" ", &[]),
        (b"x", b"x", &[]),
        (b"x", b"y", &[b"x"]),
        (b",", b",;", &[]),
        (b"hello", b"xyz", &[b"hello"]),
        (b",hello,", b",", &[b"hello"]),
    ];
    for (s, cs, want) in sp {
        let got = o_split(s, cs);
        let wv: Vec<Vec<u8>> = want.iter().map(|x| x.to_vec()).collect();
        if got != wv {
            eprintln!("CHECK FAIL c07 split({:?},{:?})", s, cs);
            fails += 1;
        }
    }

    // ---- property sweep.
    let mut rng = Rng::new(99);
    let vb = valid_bases();
    for _ in 0..20000 {
        // range: length == max-min, first==min, last==max-1, contiguous.
        let min = (rng.below(200) as i64) - 100;
        let d = (rng.below(20) as i64) - 3;
        let max = min + d;
        match o_range(min, max) {
            None => {
                if min < max {
                    eprintln!("CHECK FAIL c07 range None but min<max");
                    fails += 1;
                }
            }
            Some(v) => {
                if v.len() as i64 != max - min
                    || v[0] != min
                    || *v.last().unwrap() != max - 1
                    || v.windows(2).any(|w| w[1] - w[0] != 1)
                {
                    eprintln!("CHECK FAIL c07 range property");
                    fails += 1;
                }
            }
        }

        // strjoin: length == sum(len) + sep*(n-1); n==0 -> empty.
        let size = rng.below(5);
        let mut strs: Vec<Vec<u8>> = Vec::new();
        for _ in 0..size {
            let l = rng.below(6);
            strs.push(body(&mut rng, l, true));
        }
        let sepl = rng.below(3);
        let sep = body(&mut rng, sepl, true);
        let j = o_strjoin(size, &strs, &sep);
        let want_len: usize = strs.iter().map(|s| s.len()).sum::<usize>()
            + if size > 0 { (size - 1) * sep.len() } else { 0 };
        if j.len() != want_len {
            eprintln!("CHECK FAIL c07 strjoin length property");
            fails += 1;
        }

        // convert_base: round-trip base10 -> baseX -> base10 preserves value.
        let v = pick_i32(&mut rng);
        let from = b"0123456789".as_ref();
        let to = &vb[rng.below(vb.len())];
        let enc = o_convert_base(v.to_string().as_bytes(), from, to).unwrap();
        let back = o_convert_base(&enc, to, from).unwrap();
        if back != v.to_string().into_bytes() {
            eprintln!("CHECK FAIL c07 convert_base round-trip v={}", v);
            fails += 1;
        }
        // parse(render(v)) == v across bases.
        for b in &vb {
            if parse_base(&render_val(v, b), b) != v {
                eprintln!("CHECK FAIL c07 convert_base parse/render v={}", v);
                fails += 1;
            }
        }

        // split: tokens are non-empty, separator-free, and their concatenation
        // (with a single sep between) is a subsequence-preserving reconstruction.
        let sl = rng.below(16);
        let s = body(&mut rng, sl, false);
        let cs = if rng.below(2) == 0 {
            let cl = rng.below(3);
            body(&mut rng, cl, false)
        } else {
            vec![]
        };
        let toks = o_split(&s, &cs);
        for t in &toks {
            if t.is_empty() || t.iter().any(|c| cs.contains(c)) {
                eprintln!("CHECK FAIL c07 split token invariant");
                fails += 1;
            }
        }
        // every non-separator byte of s appears across tokens in order.
        let kept: Vec<u8> = s.iter().cloned().filter(|c| !cs.contains(c)).collect();
        let joined: Vec<u8> = toks.concat();
        if kept != joined {
            eprintln!("CHECK FAIL c07 split reconstruction");
            fails += 1;
        }
    }

    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "c07_strdup" | "c07_range" | "c07_ultimate_range" | "c07_strjoin"
        | "c07_split" | "c07_convert_base") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        match name {
            "c07_strdup" => sink(o_strdup(&unhex(f[0]))),
            "c07_range" | "c07_ultimate_range" => {
                if f.len() >= 2 {
                    if let (Ok(a), Ok(b)) = (f[0].parse::<i64>(), f[1].parse::<i64>()) { sink(o_range(a, b)); }
                }
            }
            // <size>\t<count>\t<hexSep>\t<hexStr>...\t<result>
            "c07_strjoin" => {
                if f.len() >= 4 {
                    if let Ok(size) = f[0].parse::<usize>() {
                        let strs: Vec<Vec<u8>> = f[3..f.len() - 1].iter().map(|x| unhex(x)).collect();
                        sink(o_strjoin(size, &strs, &unhex(f[2])));
                    }
                }
            }
            "c07_split" => { if f.len() >= 2 { sink(o_split(&unhex(f[0]), &unhex(f[1]))); } }
            _ => { if f.len() >= 3 { sink(o_convert_base(&unhex(f[0]), &unhex(f[1]), &unhex(f[2]))); } }
        }
    }
    true
}
