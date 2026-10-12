//! c-03 string family references (strcmp, strncmp, strcat, strncat, strstr,
//! strlcat). See oracle/README.md for the corpus-line format per function.

use crate::common::{bench_lines, largest_dec, long_text, o_strcmp, rand_body, sink, string_pairs, to_hex, unhex, widest_hex, Rng};
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
/// `cases` with `long` put in at `at` (the end of a structured head), cut
/// back to `count` cases or to the head and `long`, whichever is more: a
/// small --count keeps the capacity cases, a large one stays exact.
fn with_long<T>(mut cases: Vec<T>, at: usize, long: Vec<T>, count: usize) -> Vec<T> {
    let keep = count.max(at + long.len());
    let tail = cases.split_off(at.min(cases.len()));
    cases.extend(long);
    cases.extend(tail);
    cases.truncate(keep);
    cases
}

/// strcmp's and strncmp's capacity cases (finding 041), with strncmp's n:
/// every pair the corpus held was at most 32 bytes, so a comparison that
/// copied its strings into room of a round size (16, 64, 256, 1024, 4096)
/// passed every case. Equal through 5000 bytes; 4100 bytes that differ in
/// the last one, with n reaching it and n stopping one short; a prefix of
/// 4100 against 4101; and a last byte above 0x7f against one below it, after
/// 4097 equal ones. Each string from a seed of its own.
fn long_cmp_cases() -> Vec<(Vec<u8>, Vec<u8>, usize)> {
    let t5000 = long_text(5000, 5000);
    let t4100 = long_text(4100, 4100);
    let mut last = t4100.clone();
    last[4099] = b'#'; // a byte long_text never holds
    let mut longer = t4100.clone();
    longer.push(b'x');
    let mut hi = long_text(4097, 4097);
    let mut lo = hi.clone();
    hi.push(0x80);
    lo.push(0x01);
    vec![
        (t5000.clone(), t5000, 6000),
        (t4100.clone(), last.clone(), 4100),
        (t4100.clone(), last, 4099),
        (longer, t4100, 4101),
        (hi, lo, 4098),
    ]
}

/// strcat's and strncat's capacity cases (finding 041), with strncat's nb:
/// dest and src were at most 24 bytes each. A dest of 4100 and a src of
/// 5000, whole and with nb past it; a dest of 1100 and that src cut at 4097;
/// a dest of 5000 and an empty src. Each from a seed of its own, and every
/// dest past the 1000 bytes the cycles layer's max_unit leaves out.
fn long_cat_cases() -> Vec<(Vec<u8>, Vec<u8>, usize)> {
    let d = long_text(4100, 4100);
    let s = long_text(5000, 5000);
    vec![
        (d.clone(), s.clone(), 5000),
        (d, s.clone(), 6000),
        (long_text(1100, 1100), s.clone(), 4097),
        (s, Vec::new(), 5000),
    ]
}

/// strstr's capacity cases (finding 041): every str was at most 19 bytes and
/// every to_find at most 19. A needle of 4097 bytes found only at the end of
/// 5001, the one place a '#' stands; one of 4097 found at the start of 5000;
/// one a byte longer than its 4100-byte str; a '#' that 5000 bytes never
/// hold. Each from a seed of its own.
fn long_strstr_cases() -> Vec<(Vec<u8>, Vec<u8>)> {
    let mut end = long_text(5000, 5000);
    end.push(b'#');
    let at_end = end[end.len() - 4097..].to_vec();
    let t5000 = long_text(5000, 5000);
    let t4100 = long_text(4100, 4100);
    let mut over = t4100.clone();
    over.push(b'x');
    vec![
        (end, at_end),
        (t5000.clone(), t5000[..4097].to_vec()),
        (t4100, over),
        (t5000, b"#".to_vec()),
    ]
}

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

fn gen_strcmp<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let head = string_pairs(&mut Rng::new(seed), 0).len();
    let long = long_cmp_cases().into_iter().map(|(a, b, _)| (a, b)).collect();
    let pairs = with_long(string_pairs(&mut rng, count), head, long, count);
    for (a, b) in &pairs {
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(a), to_hex(b), o_strcmp(a, b));
    }
}

fn gen_strncmp<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let head = string_pairs(&mut Rng::new(seed), 0).len();
    let mut cases: Vec<(Vec<u8>, Vec<u8>, usize)> = Vec::new();
    for (a, b) in string_pairs(&mut rng, count) {
        let m = a.len().max(b.len());
        let n = if m == 0 { 0 } else { rng.below(m + 2) };
        cases.push((a, b, n));
    }
    for (a, b, n) in &with_long(cases, head, long_cmp_cases(), count) {
        let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(a), to_hex(b), n, o_strncmp(a, b, *n));
    }
}

fn gen_strcat<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let long = long_cat_cases().into_iter().map(|(d, s, _)| (d, s)).collect();
    let pairs = with_long(cat_pairs(&mut rng, count), 4, long, count);
    for (d, s) in &pairs {
        let cap = d.len() + s.len() + 1;
        let r = o_strcat(d, s);
        // trailing 1: strcat must return the dest pointer it was given.
        let _ = writeln!(w, "{}\t{}\t{}\t{}\t1", to_hex(d), cap, to_hex(s), to_hex(&r));
    }
}

fn gen_strncat<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut cases: Vec<(Vec<u8>, Vec<u8>, usize)> = Vec::new();
    for (d, s) in cat_pairs(&mut rng, count) {
        let n = if s.is_empty() { 0 } else { rng.below(s.len() + 2) };
        cases.push((d, s, n));
    }
    for (d, s, n) in &with_long(cases, 4, long_cat_cases(), count) {
        let n = *n;
        let k = n.min(s.len());
        let cap = d.len() + k + 1;
        let r = o_strncat(d, s, n);
        // trailing 1: strncat must return the dest pointer it was given.
        let _ = writeln!(w, "{}\t{}\t{}\t{}\t{}\t1", to_hex(d), cap, to_hex(s), n, to_hex(&r));
    }
}

fn gen_strstr<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pairs = with_long(strstr_pairs(&mut rng, count), 8, long_strstr_cases(), count);
    for (h, nd) in &pairs {
        let res = match o_strstr(h, nd) {
            Some(i) => to_hex(&h[i..]),
            None => "NULL".to_string(),
        };
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(h), to_hex(nd), res);
    }
}

fn gen_strlcat<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    // Capacity cases (finding 041): every dest, src and size below is at most
    // 24. A dest of 4100 and a src of 5000 in exactly the room they need, cut
    // at size 6000, and with size the length of dest (no room at all); a
    // dest of 1100 and that src cut at size 4097. Each from a seed of its
    // own, every dest past the 1000 bytes the cycles layer's max_unit leaves
    // out, after the first 40 cases, so the first differences a report shows
    // are short lines.
    let d = long_text(4100, 4100);
    let s = long_text(5000, 5000);
    let mut long = vec![(d.clone(), s.clone(), 9101usize), (d.clone(), s.clone(), 6000), (d, s.clone(), 4100), (long_text(1100, 1100), s, 4097)];
    while done < count || !long.is_empty() {
        if done == 40.min(count) && !long.is_empty() {
            for (d, s, size) in long.drain(..) {
                let (buf, ret) = o_strlcat(&d, &s, size);
                let _ = writeln!(w, "{}\t{}\t{}\t{}\t{}\t{}", to_hex(&d), size + 1, to_hex(&s), size, to_hex(&buf), ret);
                done += 1;
            }
            continue;
        }
        if done >= count {
            break;
        }
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
        "c03_strcmp" => gen_strcmp(&mut io::BufWriter::new(io::stdout()), seed, count),
        "c03_strncmp" => gen_strncmp(&mut io::BufWriter::new(io::stdout()), seed, count),
        "c03_strcat" => gen_strcat(&mut io::BufWriter::new(io::stdout()), seed, count),
        "c03_strncat" => gen_strncat(&mut io::BufWriter::new(io::stdout()), seed, count),
        "c03_strstr" => gen_strstr(&mut io::BufWriter::new(io::stdout()), seed, count),
        "c03_strlcat" => gen_strlcat(&mut io::BufWriter::new(io::stdout()), seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- every unbounded input past the round capacities (finding 041) ----
    // Each corpus holds a case past every capacity a function is usually
    // given room for (16, 64, 256, 1024, 4096), read back from what its
    // generator writes: each string, and the n or size beside them.
    {
        let past = 4096usize;
        let head = |g: &dyn Fn(&mut Vec<u8>)| -> Vec<u8> {
            let mut v = Vec::new();
            g(&mut v);
            v
        };
        let mut want = |ok: bool, arm: &str, what: &str| {
            if !ok {
                eprintln!("CHECK FAIL c03 {} corpus holds no {} past 4096", arm, what);
                fails += 1;
            }
        };
        let c = head(&|w| gen_strcmp(w, 1, 1000));
        want(widest_hex(&c, 0) > past && widest_hex(&c, 1) > past, "strcmp", "s1 and s2");
        let c = head(&|w| gen_strncmp(w, 1, 1000));
        want(widest_hex(&c, 0) > past && widest_hex(&c, 1) > past, "strncmp", "s1 and s2");
        want(largest_dec(&c, 2) > past as i64, "strncmp", "n");
        let c = head(&|w| gen_strcat(w, 1, 200));
        want(widest_hex(&c, 0) > past && widest_hex(&c, 2) > past, "strcat", "dest and src");
        let c = head(&|w| gen_strncat(w, 1, 200));
        want(widest_hex(&c, 0) > past && widest_hex(&c, 2) > past, "strncat", "dest and src");
        want(largest_dec(&c, 3) > past as i64, "strncat", "nb");
        let c = head(&|w| gen_strstr(w, 1, 200));
        want(widest_hex(&c, 0) > past && widest_hex(&c, 1) > past, "strstr", "str and to_find");
        let c = head(&|w| gen_strlcat(w, 1, 200));
        want(widest_hex(&c, 0) > past && widest_hex(&c, 2) > past, "strlcat", "dest and src");
        want(largest_dec(&c, 3) > past as i64, "strlcat", "size");
    }

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
