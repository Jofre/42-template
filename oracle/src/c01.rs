//! c-01 references: swap, div_mod, ultimate_div_mod, putstr, strlen,
//! rev_int_tab, sort_int_tab. See oracle/README.md for the corpus-line format.
//!
//! Line formats (input fields, then reference output):
//!   swap             <a>\t<b>\t<newA>\t<newB>            (ints decimal)
//!   div_mod          <a>\t<b>\t<div>\t<mod>
//!   ultimate_div_mod <a>\t<b>\t<newA>\t<newB>
//!   putstr           <hexstr>\t<rawstring>               (raw bytes, no 0x0a)
//!   strlen           <hexstr>\t<len>
//!   rev_int_tab      <csv>\t<reversed-csv>               (comma-joined decimals)
//!   sort_int_tab     <csv>\t<sorted-csv>

use crate::common::{bench_lines, ints_csv, join_csv, rand_body, sink, to_hex, unhex, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
/// ft_swap: after the call *a == old *b and *b == old *a.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_swap(a: i32, b: i32) -> (i32, i32) {
    (b, a)
}

/// ft_div_mod / ft_ultimate_div_mod: (a/b, a%b), C truncated-toward-zero.
/// Callers must exclude b == 0 and (a == INT_MIN && b == -1) — both UB in C.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_div_mod(a: i32, b: i32) -> (i32, i32) {
    (a / b, a % b)
}

/// ft_strlen: bytes before the terminating NUL. Inputs never contain 0x00.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strlen(s: &[u8]) -> i64 {
    s.len() as i64
}

#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_rev(v: &[i32]) -> Vec<i32> {
    let mut r = v.to_vec();
    r.reverse();
    r
}

#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_sort(v: &[i32]) -> Vec<i32> {
    let mut r = v.to_vec();
    r.sort_unstable();
    r
}

// ------------------------------------------------------------- helpers
/// A random C-string body of `len` bytes with NO 0x00 (terminator) and NO 0x0a
/// (would split the corpus line the harness replays). `high` uses the full byte
/// range (minus those two), else lowercase letters.
fn rand_body_nonl(rng: &mut Rng, len: usize, high: bool) -> Vec<u8> {
    (0..len)
        .map(|_| {
            if high {
                loop {
                    let b = (1 + rng.below(255)) as u8;
                    if b != b'\n' {
                        return b;
                    }
                }
            } else {
                (b'a' as usize + rng.below(26)) as u8
            }
        })
        .collect()
}

/// A non-zero divisor `b` and a dividend `a` that never trigger C UB
/// (b != 0, and never INT_MIN / -1).
fn safe_div_pair(rng: &mut Rng) -> (i32, i32) {
    loop {
        let a = rng.i32val();
        let mut b = rng.i32val();
        if b == 0 {
            b = 1;
        }
        if b == -1 && a == i32::MIN {
            continue;
        }
        return (a, b);
    }
}

/// Structured contract corners for div/mod, then a random UB-free tail. Every
/// pair is safe in C (b != 0, never INT_MIN / -1). Pins: zero dividend (both
/// divisor signs and boundary divisors), all four sign combinations that decide
/// C's truncate-toward-zero direction, INT_MIN / INT_MAX as dividend, INT_MAX/-1
/// (the sign-flip that is NOT UB), a divisor larger in magnitude than the
/// dividend (quotient 0, remainder == dividend), and same-boundary pairs.
fn div_pairs(rng: &mut Rng, count: usize) -> Vec<(i32, i32)> {
    let mut out: Vec<(i32, i32)> = vec![
        (0, 1),
        (0, -1),
        (0, i32::MAX),
        (0, i32::MIN),
        (1, 1),
        (5, 1),
        (5, -1),
        (7, 3),
        (-7, 3),
        (7, -3),
        (-7, -3),
        (i32::MIN, 1),
        (i32::MAX, 1),
        (i32::MIN, 2),
        (i32::MAX, 2),
        (i32::MIN, -2),
        (i32::MAX, -1),
        (i32::MIN, i32::MAX),
        (i32::MAX, i32::MIN),
        (i32::MIN, i32::MIN),
        (i32::MAX, i32::MAX),
        (10, i32::MAX),
        (-10, i32::MAX),
        (3, 7),
        (-3, 7),
    ];
    while out.len() < count {
        out.push(safe_div_pair(rng));
    }
    out.truncate(count);
    out
}

/// Structured + boundary + random int arrays (sizes 0..=12).
fn int_tabs(rng: &mut Rng, count: usize) -> Vec<Vec<i32>> {
    let mut out: Vec<Vec<i32>> = Vec::new();
    out.push(vec![]);
    out.push(vec![42]);
    out.push(vec![i32::MIN]);
    out.push(vec![i32::MAX]);
    out.push(vec![1, 2]);
    out.push(vec![2, 1]);
    out.push(vec![1, 2, 3, 4, 5]);
    out.push(vec![5, 4, 3, 2, 1]);
    out.push(vec![7, 7, 7, 7]);
    out.push(vec![0, -1, 1, i32::MIN, i32::MAX, -3]);
    out.push(vec![i32::MAX, i32::MIN, 0, i32::MAX, i32::MIN]);
    while out.len() < count {
        let size = rng.below(13);
        let v: Vec<i32> = (0..size).map(|_| rng.i32val()).collect();
        out.push(v);
    }
    out
}

// ---------------------------------------------------------- generators
fn gen_swap(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    // structured boundary pairs first
    let mut pairs: Vec<(i32, i32)> = vec![
        (0, 0),
        (11, 22),
        (-5, 7),
        (i32::MIN, i32::MAX),
        (i32::MAX, i32::MIN),
        (i32::MIN, i32::MIN),
    ];
    while pairs.len() < count {
        pairs.push((rng.i32val(), rng.i32val()));
    }
    pairs.truncate(count);
    for (a, b) in &pairs {
        let (na, nb) = o_swap(*a, *b);
        let _ = writeln!(w, "{}\t{}\t{}\t{}", a, b, na, nb);
    }
}

fn gen_div_mod(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = div_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (a, b) in &pairs {
        let (d, m) = o_div_mod(*a, *b);
        let _ = writeln!(w, "{}\t{}\t{}\t{}", a, b, d, m);
    }
}

fn gen_ultimate_div_mod(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = div_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (a, b) in &pairs {
        let (d, m) = o_div_mod(*a, *b);
        // after the call *a becomes a/b and *b becomes a%b
        let _ = writeln!(w, "{}\t{}\t{}\t{}", a, b, d, m);
    }
}

fn gen_putstr(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    // Structured corners (never a 0x00 or 0x0a): the empty string (must write
    // nothing), a single byte, plain ASCII words, the full printable ASCII run,
    // and high/boundary bytes (0x7f, 0x80, 0xff) to catch signed-char handling.
    let mut structured: Vec<Vec<u8>> = vec![
        vec![],
        vec![b'a'],
        b"42".to_vec(),
        b"Hello, World!".to_vec(),
        vec![0x7f],
        vec![0x80],
        vec![0xff, 0x01, 0x7f, 0x80],
        (0x20u8..=0x7e).collect(),
    ];
    for s in structured.drain(..) {
        if done >= count {
            break;
        }
        let _ = w.write_all(to_hex(&s).as_bytes());
        let _ = w.write_all(b"\t");
        let _ = w.write_all(&s);
        let _ = w.write_all(b"\n");
        done += 1;
    }
    while done < count {
        let high = rng.below(2) == 1;
        let len = rng.below(33);
        let s = rand_body_nonl(&mut rng, len, high);
        let _ = w.write_all(to_hex(&s).as_bytes());
        let _ = w.write_all(b"\t");
        let _ = w.write_all(&s);
        let _ = w.write_all(b"\n");
        done += 1;
    }
}

fn gen_strlen(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    // a few structured lengths first: empty, single, words, and bodies made of
    // high/boundary bytes (0x7f, 0x80, 0xff) so a signed-char length loop that
    // mishandles bytes >= 0x80 is caught deterministically.
    let structured: &[&[u8]] = &[
        b"",
        b"a",
        b"hello",
        b"42 is the answer",
        &[0xff, 0x80, 0x7f, 0x01],
        &[0x80, 0x80, 0x80, 0x80, 0x80],
    ];
    for s in structured {
        if done >= count {
            break;
        }
        let _ = writeln!(w, "{}\t{}", to_hex(s), o_strlen(s));
        done += 1;
    }
    while done < count {
        let high = rng.below(2) == 1;
        let len = rng.below(64);
        let s = rand_body(&mut rng, len, high);
        let _ = writeln!(w, "{}\t{}", to_hex(&s), o_strlen(&s));
        done += 1;
    }
}

fn gen_rev_int_tab(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let tabs = int_tabs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &tabs {
        let r = o_rev(v);
        let _ = writeln!(w, "{}\t{}", join_csv(v), join_csv(&r));
    }
}

fn gen_sort_int_tab(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let tabs = int_tabs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &tabs {
        let r = o_sort(v);
        let _ = writeln!(w, "{}\t{}", join_csv(v), join_csv(&r));
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c01_swap" => gen_swap(seed, count),
        "c01_div_mod" => gen_div_mod(seed, count),
        "c01_ultimate_div_mod" => gen_ultimate_div_mod(seed, count),
        "c01_putstr" => gen_putstr(seed, count),
        "c01_strlen" => gen_strlen(seed, count),
        "c01_rev_int_tab" => gen_rev_int_tab(seed, count),
        "c01_sort_int_tab" => gen_sort_int_tab(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- swap ----
    let swap_cases: &[(i32, i32)] = &[(3, 7), (i32::MIN, i32::MAX), (0, 0), (-1, 5)];
    for (a, b) in swap_cases {
        if o_swap(*a, *b) != (*b, *a) {
            eprintln!("CHECK FAIL c01 swap({},{})", a, b);
            fails += 1;
        }
        // swap is its own inverse
        let (x, y) = o_swap(*a, *b);
        if o_swap(x, y) != (*a, *b) {
            eprintln!("CHECK FAIL c01 swap involutive");
            fails += 1;
        }
    }

    // ---- div_mod (hand-verified against C semantics) ----
    let dm: &[(i32, i32, i32, i32)] = &[
        (7, 3, 2, 1),
        (-7, 3, -2, -1),
        (7, -3, -2, 1),
        (-7, -3, 2, -1),
        (i32::MIN, 2, -1073741824, 0),
        (i32::MAX, -1, -2147483647, 0),
        (0, 5, 0, 0),
        (5, 1, 5, 0),
        // divisor larger in magnitude than the dividend: quotient 0, remainder
        // is the whole (signed) dividend.
        (10, i32::MAX, 0, 10),
        (-10, i32::MAX, 0, -10),
        (0, i32::MIN, 0, 0),
        (i32::MIN, -2, 1073741824, 0),
        (i32::MIN, i32::MIN, 1, 0),
        (i32::MAX, i32::MAX, 1, 0),
    ];
    for (a, b, d, m) in dm {
        if o_div_mod(*a, *b) != (*d, *m) {
            eprintln!("CHECK FAIL c01 div_mod({},{})", a, b);
            fails += 1;
        }
    }

    // ---- strlen ----
    let sl: &[(&[u8], i64)] = &[(b"", 0), (b"a", 1), (b"hello", 5), (&[0xff, 0x80, 0x01], 3)];
    for (s, l) in sl {
        if o_strlen(s) != *l {
            eprintln!("CHECK FAIL c01 strlen({:?})", s);
            fails += 1;
        }
    }

    // ---- rev / sort hand cases ----
    if o_rev(&[1, 2, 3]) != vec![3, 2, 1] {
        eprintln!("CHECK FAIL c01 rev [1,2,3]");
        fails += 1;
    }
    if o_rev(&[]) != Vec::<i32>::new() || o_rev(&[5]) != vec![5] {
        eprintln!("CHECK FAIL c01 rev empty/single");
        fails += 1;
    }
    if o_sort(&[3, 1, 2]) != vec![1, 2, 3] {
        eprintln!("CHECK FAIL c01 sort [3,1,2]");
        fails += 1;
    }
    if o_sort(&[i32::MAX, i32::MIN, 0]) != vec![i32::MIN, 0, i32::MAX] {
        eprintln!("CHECK FAIL c01 sort boundary");
        fails += 1;
    }

    // ---- properties over seeded random inputs ----
    let mut rng = Rng::new(101);
    for _ in 0..20000 {
        // div_mod: a == (a/b)*b + a%b  (compute in i128 to dodge overflow)
        let (a, b) = safe_div_pair(&mut rng);
        let (d, m) = o_div_mod(a, b);
        if (d as i128) * (b as i128) + (m as i128) != a as i128 {
            eprintln!("CHECK FAIL c01 div_mod identity a={} b={}", a, b);
            fails += 1;
        }
        // |m| < |b| and m has the sign of a (or is zero)
        if (m as i128).abs() >= (b as i128).abs() {
            eprintln!("CHECK FAIL c01 div_mod remainder magnitude");
            fails += 1;
        }
        if m != 0 && (m < 0) != (a < 0) {
            eprintln!("CHECK FAIL c01 div_mod remainder sign");
            fails += 1;
        }

        // swap involution
        let (sa, sb) = (rng.i32val(), rng.i32val());
        let (na, nb) = o_swap(sa, sb);
        if (na, nb) != (sb, sa) || o_swap(na, nb) != (sa, sb) {
            eprintln!("CHECK FAIL c01 swap prop");
            fails += 1;
        }

        // rev: double-reverse is identity, and reversed[i] == v[n-1-i]
        let size = rng.below(13);
        let v: Vec<i32> = (0..size).map(|_| rng.i32val()).collect();
        let r = o_rev(&v);
        if o_rev(&r) != v {
            eprintln!("CHECK FAIL c01 rev double");
            fails += 1;
        }
        for i in 0..v.len() {
            if r[i] != v[v.len() - 1 - i] {
                eprintln!("CHECK FAIL c01 rev index");
                fails += 1;
                break;
            }
        }

        // sort: output is ascending AND a permutation (multiset) of the input
        let s = o_sort(&v);
        if s.windows(2).any(|w| w[0] > w[1]) {
            eprintln!("CHECK FAIL c01 sort not ordered");
            fails += 1;
        }
        let mut a1 = v.clone();
        let mut a2 = s.clone();
        a1.sort_unstable();
        a2.sort_unstable();
        if a1 != a2 {
            eprintln!("CHECK FAIL c01 sort not a permutation");
            fails += 1;
        }

        // strlen matches byte count for a NUL-free body
        let blen = rng.below(20);
        let body = rand_body(&mut rng, blen, true);
        if o_strlen(&body) != body.len() as i64 {
            eprintln!("CHECK FAIL c01 strlen prop");
            fails += 1;
        }
    }

    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        match name {
            "c01_swap" if f.len() >= 2 => {
                if let (Ok(a), Ok(b)) = (f[0].parse::<i32>(), f[1].parse::<i32>()) { sink(o_swap(a, b)); }
            }
            "c01_div_mod" | "c01_ultimate_div_mod" if f.len() >= 2 => {
                if let (Ok(a), Ok(b)) = (f[0].parse::<i32>(), f[1].parse::<i32>()) { sink(o_div_mod(a, b)); }
            }
            "c01_strlen" => sink(o_strlen(&unhex(f[0]))),
            // ft_putstr's job is emitting the bytes, so the reference work is
            // producing them. Taking a length instead measured nothing: this arm
            // used to run in 4ms against a 200k corpus and the ratio came out NA.
            "c01_putstr" => { let v = unhex(f[0]); let mut o = Vec::with_capacity(v.len()); o.extend_from_slice(&v); sink(o); }
            "c01_rev_int_tab" => sink(o_rev(&ints_csv(f[0]))),
            "c01_sort_int_tab" => sink(o_sort(&ints_csv(f[0]))),
            _ => return false,
        }
    }
    matches!(name, "c01_swap" | "c01_div_mod" | "c01_ultimate_div_mod" | "c01_strlen"
        | "c01_putstr" | "c01_rev_int_tab" | "c01_sort_int_tab")
}
