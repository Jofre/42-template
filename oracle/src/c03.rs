//! c-03 string family references (strcmp, strncmp, strcat, strncat, strstr,
//! strlcat). See oracle/README.md for the corpus-line format per function.

use crate::common::{bench_lines, o_strcmp, rand_body, sink, string_pairs, to_hex, unhex, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strncmp(a: &[u8], b: &[u8], n: usize) -> i64 {
    let mut i = 0usize;
    while i < n {
        let av = *a.get(i).unwrap_or(&0);
        let bv = *b.get(i).unwrap_or(&0);
        if av != bv || av == 0 {
            return av as i64 - bv as i64;
        }
        i += 1;
    }
    0
}

#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strcat(dest: &[u8], src: &[u8]) -> Vec<u8> {
    let mut v = dest.to_vec();
    v.extend_from_slice(src);
    v
}

#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strncat(dest: &[u8], src: &[u8], n: usize) -> Vec<u8> {
    let k = n.min(src.len());
    let mut v = dest.to_vec();
    v.extend_from_slice(&src[..k]);
    v
}

#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strstr(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    if needle.len() > hay.len() {
        return None;
    }
    let mut i = 0usize;
    while i + needle.len() <= hay.len() {
        if &hay[i..i + needle.len()] == needle {
            return Some(i);
        }
        i += 1;
    }
    None
}

#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strlcat(dest: &[u8], src: &[u8], size: usize) -> (Vec<u8>, u64) {
    let dlen = dest.len().min(size);
    let slen = src.len();
    if dlen == size {
        return (dest[..dlen].to_vec(), (size + slen) as u64);
    }
    let room = size - dlen - 1;
    let k = room.min(slen);
    let mut v = dest[..dlen].to_vec();
    v.extend_from_slice(&src[..k]);
    (v, (dlen + slen) as u64)
}

// ---------------------------------------------------------- generators
fn cat_pairs(rng: &mut Rng, count: usize) -> Vec<(Vec<u8>, Vec<u8>)> {
    let mut out: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
    out.push((vec![], vec![]));
    out.push((vec![], vec![b'a', b'b', b'c']));
    out.push((vec![b'x', b'y'], vec![]));
    out.push((vec![b'A'], vec![b'B']));
    while out.len() < count {
        let high = rng.below(2) == 1;
        let ld = rng.below(25);
        let d = rand_body(rng, ld, high);
        let ls = rng.below(25);
        let s = rand_body(rng, ls, high);
        out.push((d, s));
    }
    out
}

fn strstr_pairs(rng: &mut Rng, count: usize) -> Vec<(Vec<u8>, Vec<u8>)> {
    let mut out: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
    out.push((b"abc".to_vec(), vec![]));
    out.push((b"abc".to_vec(), b"abc".to_vec()));
    out.push((b"abc".to_vec(), b"bc".to_vec()));
    out.push((b"abc".to_vec(), b"b".to_vec()));
    out.push((b"abc".to_vec(), b"x".to_vec()));
    out.push((b"abc".to_vec(), b"abcd".to_vec()));
    out.push((vec![], b"a".to_vec()));
    out.push((b"aaaa".to_vec(), b"aab".to_vec()));
    while out.len() < count {
        let high = rng.below(2) == 1;
        let lh = rng.below(20);
        let hay = rand_body(rng, lh, high);
        let mode = rng.below(3);
        let needle = if mode == 0 && !hay.is_empty() {
            let start = rng.below(hay.len());
            let l = 1 + rng.below(hay.len() - start);
            hay[start..start + l].to_vec()
        } else if mode == 1 {
            vec![]
        } else {
            let ln = rng.below(6);
            rand_body(rng, ln, high)
        };
        out.push((hay, needle));
    }
    out
}

fn gen_strcmp(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = string_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (a, b) in &pairs {
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(a), to_hex(b), o_strcmp(a, b));
    }
}

fn gen_strncmp(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = string_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (a, b) in &pairs {
        let m = a.len().max(b.len());
        let n = if m == 0 { 0 } else { rng.below(m + 2) };
        let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(a), to_hex(b), n, o_strncmp(a, b, n));
    }
}

fn gen_strcat(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = cat_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (d, s) in &pairs {
        let cap = d.len() + s.len() + 1;
        let r = o_strcat(d, s);
        // trailing 1: strcat must return the dest pointer it was given.
        let _ = writeln!(w, "{}\t{}\t{}\t{}\t1", to_hex(d), cap, to_hex(s), to_hex(&r));
    }
}

fn gen_strncat(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = cat_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (d, s) in &pairs {
        let n = if s.is_empty() { 0 } else { rng.below(s.len() + 2) };
        let k = n.min(s.len());
        let cap = d.len() + k + 1;
        let r = o_strncat(d, s, n);
        // trailing 1: strncat must return the dest pointer it was given.
        let _ = writeln!(w, "{}\t{}\t{}\t{}\t{}\t1", to_hex(d), cap, to_hex(s), n, to_hex(&r));
    }
}

fn gen_strstr(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = strstr_pairs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (h, nd) in &pairs {
        let res = match o_strstr(h, nd) {
            Some(i) => to_hex(&h[i..]),
            None => "NULL".to_string(),
        };
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(h), to_hex(nd), res);
    }
}

fn gen_strlcat(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    while done < count {
        let size = rng.below(25);
        let dlen = if size == 0 { 0 } else { rng.below(size + 1) };
        let high = rng.below(2) == 1;
        let d = rand_body(&mut rng, dlen, high);
        let ls = rng.below(25);
        let s = rand_body(&mut rng, ls, high);
        let cap = size + 1;
        let (buf, ret) = o_strlcat(&d, &s, size);
        let _ = writeln!(
            w,
            "{}\t{}\t{}\t{}\t{}\t{}",
            to_hex(&d), cap, to_hex(&s), size, to_hex(&buf), ret
        );
        done += 1;
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c03_strcmp" => gen_strcmp(seed, count),
        "c03_strncmp" => gen_strncmp(seed, count),
        "c03_strcat" => gen_strcat(seed, count),
        "c03_strncat" => gen_strncat(seed, count),
        "c03_strstr" => gen_strstr(seed, count),
        "c03_strlcat" => gen_strlcat(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    let cases: &[(&[u8], &[u8], i64)] = &[
        (b"Hello", b"Hello", 0),
        (b"Hello", b"Hella", 14),
        (b"Hello", b"Helloo", -111),
        (b"Helloo", b"Hello", 111),
        (b"", b"", 0),
        (b"", b"a", -97),
        (b"a", b"", 97),
        (b"abc", b"abd", -1),
        (b"abz", b"abc", 23),
        (&[0x80], &[0x01], 127),
        (&[0x01], &[0x80], -127),
        (&[b'A', 0x80], &[b'A', 0x7f], 1),
        (&[0xff], &[b'a'], 158),
    ];
    for (a, b, want) in cases {
        if o_strcmp(a, b) != *want {
            eprintln!("CHECK FAIL c03 strcmp({:?},{:?})", a, b);
            fails += 1;
        }
    }

    let sl: &[(&[u8], &[u8], usize, &[u8], u64)] = &[
        (b"foo", b"bar", 10, b"foobar", 6),
        (b"foo", b"bar", 4, b"foo", 6),
        (b"abcd", b"x", 4, b"abcd", 5),
        (b"", b"hi", 5, b"hi", 2),
        (b"ab", b"", 5, b"ab", 2),
    ];
    for (d, s, size, buf, ret) in sl {
        let (gb, gr) = o_strlcat(d, s, *size);
        if gb != *buf || gr != *ret {
            eprintln!("CHECK FAIL c03 strlcat({:?},{:?},{})", d, s, size);
            fails += 1;
        }
    }

    let mut rng = Rng::new(7);
    for _ in 0..5000 {
        let ld = rng.below(8);
        let d = rand_body(&mut rng, ld, true);
        let ls = rng.below(8);
        let s = rand_body(&mut rng, ls, true);
        if o_strcmp(&d, &d) != 0 || o_strcmp(&d, &s).signum() != -o_strcmp(&s, &d).signum() {
            eprintln!("CHECK FAIL c03 strcmp property");
            fails += 1;
        }
        let cat = o_strcat(&d, &s);
        if cat.len() != d.len() + s.len() || !cat.starts_with(&d) || !cat.ends_with(&s) {
            eprintln!("CHECK FAIL c03 strcat property");
            fails += 1;
        }
        let n = rng.below(s.len() + 2);
        if o_strncat(&d, &s, n).len() != d.len() + n.min(s.len()) {
            eprintln!("CHECK FAIL c03 strncat property");
            fails += 1;
        }
        if o_strncmp(&d, &d, ld) != 0 || o_strncmp(&d, &s, 0) != 0 {
            eprintln!("CHECK FAIL c03 strncmp reflexive/zero");
            fails += 1;
        }
        if o_strncmp(&d, &s, 999).signum() != o_strcmp(&d, &s).signum() {
            eprintln!("CHECK FAIL c03 strncmp vs strcmp");
            fails += 1;
        }
        if let Some(i) = o_strstr(&d, &s) {
            if !s.is_empty() && &d[i..i + s.len()] != s.as_slice() {
                eprintln!("CHECK FAIL c03 strstr match");
                fails += 1;
            }
        }
        let size = rng.below(d.len() + 3);
        let (_b, r) = o_strlcat(&d, &s, size);
        if r != (d.len().min(size) + s.len()) as u64 {
            eprintln!("CHECK FAIL c03 strlcat return");
            fails += 1;
        }
    }
    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
/// Field order follows each gen_* emit: inputs first, reference output last.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "c03_strcmp" | "c03_strncmp" | "c03_strcat" | "c03_strncat"
        | "c03_strstr" | "c03_strlcat") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        if f.len() < 2 { continue; }
        let a = unhex(f[0]);
        match name {
            "c03_strcmp" => sink(o_strcmp(&a, &unhex(f[1]))),
            "c03_strstr" => sink(o_strstr(&a, &unhex(f[1]))),
            "c03_strncmp" => { if f.len() >= 3 { if let Ok(n) = f[2].parse::<usize>() { sink(o_strncmp(&a, &unhex(f[1]), n)); } } }
            // dest, cap, src, ...
            "c03_strcat" => { if f.len() >= 3 { sink(o_strcat(&a, &unhex(f[2]))); } }
            "c03_strncat" => { if f.len() >= 4 { if let Ok(n) = f[3].parse::<usize>() { sink(o_strncat(&a, &unhex(f[2]), n)); } } }
            _ => { if f.len() >= 4 { if let Ok(sz) = f[3].parse::<usize>() { sink(o_strlcat(&a, &unhex(f[2]), sz)); } } }
        }
    }
    true
}
