//! c-11 references: function-pointer family (foreach, map, any, count_if,
//! is_sort, sort_string_tab, advanced_sort_string_tab). Each callback is a
//! single FIXED deterministic function, implemented identically here and in the
//! matching C reader harness — the callback itself is never fuzzed.
//!
//! Fixed callbacks:
//!   foreach   f(x) prints/collects x (visit order check)
//!   map       f(x) = x*3 - 1
//!   any       f(s) = (strlen(s) >= 3)
//!   count_if  f(s) = (s[0] is one of a,e,i,o,u)          (empty -> 0)
//!   is_sort   cmp(a,b) = a - b   (ascending)
//!   sort      strcmp order (unsigned-byte lexicographic)
//!   advanced  cmp = strcmp   (same order as sort)
//!
//! Line formats (input fields, then reference output):
//!   c11_foreach                 <csv>\t<visited-csv>\t<csv-after>
//!   c11_map                     <csv>\t<mapped-csv>\t<csv-after>
//!   c11_any                     <n>\t<tok0,tok1,...>\t<0|1>\t<toks-after>
//!   c11_count_if                <n>\t<tok0,tok1,...>\t<count>\t<toks-after>
//!   c11_is_sort                 <csv>\t<0|1>\t<csv-after>
//!   c11_sort_string_tab         <n>\t<tok0,...>\t<sortedTok0,...>
//!   c11_advanced_sort_string_tab <n>\t<tok0,...>\t<sortedTok0,...>
//! The trailing "<...-after>" field on the non-mutating functions (foreach, map,
//! any, count_if, is_sort) re-echoes the INPUT array/token list; the harness
//! prints its OWN copy of the input array AFTER calling the student function, so
//! any impl that clobbers its input array (or the strings it points at) diverges.
//! csv    = comma-joined decimal ints ("" for size 0)
//! tokN   = lowercase-hex of a NUL-free C string (tokens comma-joined)

use crate::common::{bench_lines, ints_csv, join_csv, rand_body, sink, to_hex, unhex_csv, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
/// ft_map fixed transform f(x) = x*3 - 1. Inputs are range-limited by the
/// generator so this never overflows i32 (matching well-defined C).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_map(x: i32) -> i32 {
    x.wrapping_mul(3).wrapping_sub(1)
}

/// ft_any fixed predicate: string length >= 3.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_any_pred(s: &[u8]) -> bool {
    s.len() >= 3
}

/// ft_count_if fixed predicate: first byte is a lowercase vowel.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_vowel_first(s: &[u8]) -> bool {
    matches!(s.first(), Some(b'a') | Some(b'e') | Some(b'i') | Some(b'o') | Some(b'u'))
}

/// ft_is_sort under cmp(a,b)=a-b: 1 iff the array is non-decreasing.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_is_sort(v: &[i32]) -> i64 {
    for w in v.windows(2) {
        if w[0] > w[1] {
            return 0;
        }
    }
    1
}

/// strcmp order: Vec<u8>'s Ord is unsigned-byte lexicographic, exactly libc
/// strcmp on interior-NUL-free strings.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_sort_strings(v: &[Vec<u8>]) -> Vec<Vec<u8>> {
    let mut r = v.to_vec();
    r.sort();
    r
}

// ------------------------------------------------------------- helpers
/// Comma-joined lowercase-hex of a token list ("" for an empty list).
fn join_tokens(toks: &[Vec<u8>]) -> String {
    let mut s = String::new();
    for (i, t) in toks.iter().enumerate() {
        if i != 0 {
            s.push(',');
        }
        s.push_str(&to_hex(t));
    }
    s
}

/// A signed value in [-lim, lim], biased toward 0 and the two extremes.
fn bounded_val(rng: &mut Rng, lim: i64) -> i32 {
    match rng.below(8) {
        0 => 0,
        1 => lim as i32,
        2 => -lim as i32,
        3 => -(rng.below(1000) as i32),
        4 => rng.below(1000) as i32,
        _ => ((rng.next_u64() % (2 * lim as u64 + 1)) as i64 - lim) as i32,
    }
}

/// Structured + boundary + random int arrays (sizes 0..=12) within [-lim,lim].
fn bounded_tabs(rng: &mut Rng, count: usize, lim: i64) -> Vec<Vec<i32>> {
    let mut out: Vec<Vec<i32>> = Vec::new();
    out.push(vec![]);
    out.push(vec![0]);
    out.push(vec![lim as i32]);
    out.push(vec![-lim as i32]);
    out.push(vec![1, 2, 3, 4, 5]);
    out.push(vec![5, 4, 3, 2, 1]);
    out.push(vec![7, 7, 7, 7]);
    out.push(vec![-lim as i32, 0, lim as i32]);
    while out.len() < count {
        let size = rng.below(13);
        let v: Vec<i32> = (0..size).map(|_| bounded_val(rng, lim)).collect();
        out.push(v);
    }
    // No truncation: count.max(len) is never below len, so this only ever
    // raised the corpus. A small --count therefore keeps the whole
    // structured head rather than cutting into it, which is the policy;
    // it used to be spelled as a call that could not do anything.
    out
}

/// A random list of NUL-free C-string tokens (list len 0..=maxn, each 0..=maxl).
fn rand_tokens(rng: &mut Rng, maxn: usize, maxl: usize, high: bool) -> Vec<Vec<u8>> {
    let n = rng.below(maxn + 1);
    (0..n)
        .map(|_| {
            let l = rng.below(maxl + 1);
            rand_body(rng, l, high)
        })
        .collect()
}

// ---------------------------------------------------------- generators
fn gen_foreach(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let tabs = bounded_tabs(&mut rng, count, i32::MAX as i64);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &tabs {
        // foreach visits each element once, in order: the visited sequence == v.
        // The trailing field re-echoes the input: foreach must not mutate `tab`.
        let csv = join_csv(v);
        let _ = writeln!(w, "{}\t{}\t{}", csv, csv, csv);
    }
}

fn gen_map(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    // f(x)=x*3-1 must not overflow i32 => |x| <= 700_000_000.
    let tabs = bounded_tabs(&mut rng, count, 700_000_000);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &tabs {
        let mapped: Vec<i32> = v.iter().map(|&x| o_map(x)).collect();
        // trailing field: map returns a NEW array and must leave `tab` untouched.
        let csv = join_csv(v);
        let _ = writeln!(w, "{}\t{}\t{}", csv, join_csv(&mapped), csv);
    }
}

fn gen_any(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    // structured cases first
    let structured: &[Vec<Vec<u8>>] = &[
        vec![],                                                  // empty array -> 0
        vec![b"".to_vec()],                                      // one empty string -> 0
        vec![b"ab".to_vec()],                                    // len 2, just under boundary
        vec![b"abc".to_vec()],                                   // len exactly 3 -> 1
        vec![b"abcd".to_vec()],                                  // len 4 -> 1
        vec![b"x".to_vec(), b"yy".to_vec()],                     // all below boundary -> 0
        vec![b"a".to_vec(), b"bb".to_vec(), b"ccc".to_vec()],    // last one triggers -> 1
    ];
    for toks in structured {
        if done >= count {
            break;
        }
        let res = if toks.iter().any(|t| o_any_pred(t)) { 1 } else { 0 };
        let tk = join_tokens(toks);
        // trailing field: any must not mutate the array or the strings it holds.
        let _ = writeln!(w, "{}\t{}\t{}\t{}", toks.len(), tk, res, tk);
        done += 1;
    }
    while done < count {
        let high = rng.below(4) == 0;
        // short strings around the length-3 boundary
        let toks = rand_tokens(&mut rng, 6, 5, high);
        let res = if toks.iter().any(|t| o_any_pred(t)) { 1 } else { 0 };
        let tk = join_tokens(&toks);
        let _ = writeln!(w, "{}\t{}\t{}\t{}", toks.len(), tk, res, tk);
        done += 1;
    }
}

fn gen_count_if(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    let structured: &[Vec<Vec<u8>>] = &[
        vec![],                                                       // empty array -> 0
        vec![b"".to_vec()],                                           // one empty string -> 0
        vec![b"apple".to_vec()],                                      // vowel-first -> 1
        vec![b"banana".to_vec()],                                     // consonant-first -> 0
        vec![b"aeiou".to_vec()],                                      // starts 'a' -> 1
        // empty + vowel + consonant + vowel: exercises the empty-first edge and a count of 2
        vec![b"".to_vec(), b"echo".to_vec(), b"x".to_vec(), b"oak".to_vec()],
    ];
    for toks in structured {
        if done >= count {
            break;
        }
        let c = toks.iter().filter(|t| o_vowel_first(t)).count();
        let tk = join_tokens(toks);
        // trailing field: count_if is read-only over its array and strings.
        let _ = writeln!(w, "{}\t{}\t{}\t{}", toks.len(), tk, c, tk);
        done += 1;
    }
    while done < count {
        // lowercase letters so the vowel predicate actually splits the input
        let toks = rand_tokens(&mut rng, 8, 6, false);
        let c = toks.iter().filter(|t| o_vowel_first(t)).count();
        let tk = join_tokens(&toks);
        let _ = writeln!(w, "{}\t{}\t{}\t{}", toks.len(), tk, c, tk);
        done += 1;
    }
}

fn gen_is_sort(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    // cmp(a,b)=a-b must not overflow int => keep |a|,|b| within 1e9 (diff < 2^31).
    let lim: i64 = 1_000_000_000;
    // structured cases whose answer is identical under every reasonable
    // is_sort reading (ascending-only vs. either-direction): sorted-ascending,
    // constant, and clearly-unsorted arrays. Purely-descending arrays (the only
    // case where the two readings differ) are deliberately excluded below.
    let structured: &[Vec<i32>] = &[
        vec![],
        vec![42],
        vec![1, 2, 3, 4],
        vec![1, 1, 2, 2, 3],
        vec![7, 7, 7],
        vec![1, 3, 2],
        vec![-lim as i32, 0, lim as i32],
    ];
    for v in structured {
        if done >= count {
            break;
        }
        // trailing field: is_sort is a pure query and must not reorder `tab`.
        let csv = join_csv(v);
        let _ = writeln!(w, "{}\t{}\t{}", csv, o_is_sort(v), csv);
        done += 1;
    }
    while done < count {
        let size = rng.below(13);
        let mut v: Vec<i32> = (0..size).map(|_| bounded_val(&mut rng, lim)).collect();
        // Mode 0: force a genuinely-sorted (non-decreasing) array (answer 1).
        if rng.below(2) == 0 {
            v.sort_unstable();
        }
        // Exclude non-increasing-with-a-drop arrays: those are the only inputs on
        // which "ascending only" and "either direction" is_sort disagree. Keep
        // len<=1, constant, or arrays that contain at least one strict increase.
        let has_up = v.windows(2).any(|w| w[0] < w[1]);
        let constant = v.windows(2).all(|w| w[0] == w[1]);
        if v.len() >= 2 && !has_up && !constant {
            continue;
        }
        let csv = join_csv(&v);
        let _ = writeln!(w, "{}\t{}\t{}", csv, o_is_sort(&v), csv);
        done += 1;
    }
}

fn gen_sort_common(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    let structured: &[Vec<Vec<u8>>] = &[
        vec![],
        vec![b"a".to_vec()],
        vec![b"banana".to_vec(), b"apple".to_vec(), b"cherry".to_vec()],
        vec![b"b".to_vec(), b"b".to_vec(), b"a".to_vec()],
        vec![b"".to_vec(), b"a".to_vec(), b"".to_vec()],
    ];
    for toks in structured {
        if done >= count {
            break;
        }
        let sorted = o_sort_strings(toks);
        let _ = writeln!(w, "{}\t{}\t{}", toks.len(), join_tokens(toks), join_tokens(&sorted));
        done += 1;
    }
    while done < count {
        let high = rng.below(4) == 0;
        // small alphabet + short lengths => plenty of ties and shared prefixes
        let toks = rand_tokens(&mut rng, 8, 6, high);
        let sorted = o_sort_strings(&toks);
        let _ = writeln!(w, "{}\t{}\t{}", toks.len(), join_tokens(&toks), join_tokens(&sorted));
        done += 1;
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c11_foreach" => gen_foreach(seed, count),
        "c11_map" => gen_map(seed, count),
        "c11_any" => gen_any(seed, count),
        "c11_count_if" => gen_count_if(seed, count),
        "c11_is_sort" => gen_is_sort(seed, count),
        "c11_sort_string_tab" => gen_sort_common(seed, count),
        "c11_advanced_sort_string_tab" => gen_sort_common(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- map ----
    let mc: &[(i32, i32)] = &[(0, -1), (1, 2), (-1, -4), (10, 29), (700_000_000, 2_099_999_999)];
    for (x, want) in mc {
        if o_map(*x) != *want {
            eprintln!("CHECK FAIL c11 map({})", x);
            fails += 1;
        }
    }

    // ---- any predicate ----
    let ap: &[(&[u8], bool)] = &[(b"", false), (b"ab", false), (b"abc", true), (b"abcd", true)];
    for (s, want) in ap {
        if o_any_pred(s) != *want {
            eprintln!("CHECK FAIL c11 any_pred({:?})", s);
            fails += 1;
        }
    }

    // ---- vowel predicate ----
    let vp: &[(&[u8], bool)] = &[
        (b"", false),
        (b"apple", true),
        (b"echo", true),
        (b"xyz", false),
        (b"oak", true),
        (b"Apple", false),
    ];
    for (s, want) in vp {
        if o_vowel_first(s) != *want {
            eprintln!("CHECK FAIL c11 vowel_first({:?})", s);
            fails += 1;
        }
    }

    // ---- is_sort hand cases ----
    let ic: &[(&[i32], i64)] = &[
        (&[], 1),
        (&[5], 1),
        (&[1, 2, 3], 1),
        (&[1, 1, 2], 1),
        (&[1, 3, 2], 0),
        (&[3, 2, 1], 0),
    ];
    for (v, want) in ic {
        if o_is_sort(v) != *want {
            eprintln!("CHECK FAIL c11 is_sort({:?})", v);
            fails += 1;
        }
    }

    // ---- sort_strings hand cases ----
    if o_sort_strings(&[b"b".to_vec(), b"a".to_vec(), b"c".to_vec()])
        != vec![b"a".to_vec(), b"b".to_vec(), b"c".to_vec()]
    {
        eprintln!("CHECK FAIL c11 sort_strings basic");
        fails += 1;
    }
    // unsigned-byte order: high byte 0x80 sorts after 'z' (0x7a)
    if o_sort_strings(&[vec![0x80], b"z".to_vec()]) != vec![b"z".to_vec(), vec![0x80]] {
        eprintln!("CHECK FAIL c11 sort_strings unsigned");
        fails += 1;
    }

    // ---- properties over seeded random inputs ----
    let mut rng = Rng::new(211);
    for _ in 0..20000 {
        // map: reversible via inputs stay bounded, and f is exact
        let x = bounded_val(&mut rng, 700_000_000);
        if o_map(x) as i64 != x as i64 * 3 - 1 {
            eprintln!("CHECK FAIL c11 map identity");
            fails += 1;
        }

        // is_sort: a sorted copy is always is_sort==1; a strictly-desc >=2 is 0
        let size = rng.below(10);
        let mut v: Vec<i32> = (0..size).map(|_| bounded_val(&mut rng, 1_000_000_000)).collect();
        v.sort_unstable();
        if o_is_sort(&v) != 1 {
            eprintln!("CHECK FAIL c11 is_sort sorted");
            fails += 1;
        }
        if v.len() >= 2 && v[0] != v[v.len() - 1] {
            let mut d = v.clone();
            d.reverse();
            if o_is_sort(&d) != 0 {
                eprintln!("CHECK FAIL c11 is_sort reversed");
                fails += 1;
            }
        }

        // sort_strings: output is ordered AND a permutation of the input
        let toks = rand_tokens(&mut rng, 6, 5, true);
        let s = o_sort_strings(&toks);
        if s.windows(2).any(|w| w[0] > w[1]) {
            eprintln!("CHECK FAIL c11 sort_strings not ordered");
            fails += 1;
        }
        let mut a1 = toks.clone();
        let mut a2 = s.clone();
        a1.sort();
        a2.sort();
        if a1 != a2 {
            eprintln!("CHECK FAIL c11 sort_strings not a permutation");
            fails += 1;
        }

        // any == (count_if-style existence) consistency
        let anyv = toks.iter().any(|t| o_any_pred(t));
        let cnt = toks.iter().filter(|t| o_any_pred(t)).count();
        if anyv != (cnt > 0) {
            eprintln!("CHECK FAIL c11 any/count consistency");
            fails += 1;
        }
    }

    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "c11_foreach" | "c11_map" | "c11_any" | "c11_count_if" | "c11_is_sort"
        | "c11_sort_string_tab" | "c11_advanced_sort_string_tab") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        match name {
            // <csv>\t...
            "c11_foreach" => sink(ints_csv(f[0]).iter().fold(0i64, |a, &x| a.wrapping_add(x as i64))),
            "c11_map" => sink(ints_csv(f[0]).iter().map(|&x| o_map(x)).collect::<Vec<i32>>()),
            "c11_is_sort" => sink(o_is_sort(&ints_csv(f[0]))),
            // <n>\t<tok0,tok1,...>\t...
            "c11_any" => { if f.len() >= 2 { sink(unhex_csv(f[1]).iter().any(|t| o_any_pred(t))); } }
            "c11_count_if" => { if f.len() >= 2 { sink(unhex_csv(f[1]).iter().filter(|t| o_vowel_first(t)).count()); } }
            _ => { if f.len() >= 2 { sink(o_sort_strings(&unhex_csv(f[1]))); } }
        }
    }
    true
}
