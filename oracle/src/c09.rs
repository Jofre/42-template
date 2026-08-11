//! c-09 references. c-09 is a libft rebuild of earlier modules, so its
//! references mirror the documented contracts already covered elsewhere:
//!   c09_split   ft_split(char *str, char *charset) -> char**  (== c-07 split)
//!   c09_strcmp  ft_strcmp(char *s1, char *s2) -> int          (== c-03 strcmp)
//!
//! Line formats (input fields, then reference output):
//!   split   <hexStr>\t<hexCharset>\t<nonnull=1>\t<count>[\t<hexTok>...]
//!   strcmp  <hexA>\t<hexB>\t<(uchar)a[k]-(uchar)b[k] at first diff>
//!
//! The `nonnull` field asserts ft_split returned a non-NULL array even when the
//! result has 0 tokens — without it a NULL-returning stub matches every
//! all-separator / empty case (both print count 0).

use crate::common::{bench_lines, o_split, o_strcmp, rand_body, sink, string_pairs, to_hex, unhex, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
// ---------------------------------------------------------- generators
fn body(rng: &mut Rng, len: usize, high: bool) -> Vec<u8> {
    rand_body(rng, len, high)
}

fn emit_split<W: Write>(w: &mut W, s: &[u8], charset: &[u8]) {
    let toks = o_split(s, charset);
    // nonnull=1: ft_split must return a non-NULL array (even for 0 tokens).
    let _ = write!(w, "{}\t{}\t1\t{}", to_hex(s), to_hex(charset), toks.len());
    for t in &toks {
        let _ = write!(w, "\t{}", to_hex(t));
    }
    let _ = writeln!(w);
}

fn gen_split(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;

    let fixed: Vec<(&[u8], &[u8])> = vec![
        (b"hello world 42", b" "),
        (b"x", b" "),
        (b"no-separators-here", b" "),
        (b"singleton", b""),
        (b"  multiple   spaces  ", b" "),
        (b",leading", b","),
        (b"trailing,", b","),
        (b"a,b,c;d;e", b",;"),
        (b"a,;b", b",;"),
        (b"split\tby\ttabs and spaces", b" \t"),
        (b"", b" "),
        (b"   ", b" "),
        (b" ,; ,;", b" ,;"),
        (b"", b""),
        // high-byte separators / bodies: a signed-char `contains` test mis-splits.
        (b"a\xffb\xffc", b"\xff"),
        (b"\x80\x81 \x82", b" "),
        (b"\x80mid\x80", b"\x80"),
        (b"\xfe\xff\xfe", b"\xff"),
        (b"lone", b"\xff"),
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
                // full-range bytes, separators drawn from the string so some split
                let high = rng.below(2) == 1;
                let sl = rng.below(20);
                let s = body(&mut rng, sl, high);
                let lc = rng.below(4);
                let cs = if lc == 0 || s.is_empty() {
                    body(&mut rng, lc, high)
                } else {
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

fn gen_strcmp(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;

    // Module-pinned corners (string_pairs adds shorter variants; these fix the
    // longer-string cases: differ only at a late byte, deep strict prefix, and
    // high-vs-low signedness both orders).
    let fixed: &[(&[u8], &[u8])] = &[
        (b"", b""),
        (b"", b"abcdef"),
        (b"abcdef", b""),
        (b"identical string here", b"identical string here"),
        (b"prefix of a longer one", b"prefix of a longer one!"),
        (b"differ at the last bytA", b"differ at the last bytB"),
        (&[0x80], &[0x7f]),
        (&[0x7f], &[0x80]),
        (b"abc\xff", b"abc\x01"),
        (b"abc\x01", b"abc\xff"),
    ];
    for (a, b) in fixed {
        if done >= count {
            break;
        }
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(a), to_hex(b), o_strcmp(a, b));
        done += 1;
    }

    if done < count {
        let pairs = string_pairs(&mut rng, count - done);
        for (a, b) in &pairs {
            let _ = writeln!(w, "{}\t{}\t{}", to_hex(a), to_hex(b), o_strcmp(a, b));
        }
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c09_split" => gen_split(seed, count),
        "c09_strcmp" => gen_strcmp(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- split hand cases.
    let sp: &[(&[u8], &[u8], &[&[u8]])] = &[
        (b"hello world 42", b" ", &[b"hello", b"world", b"42"]),
        (b"x", b" ", &[b"x"]),
        (b"singleton", b"", &[b"singleton"]),
        (b"  multiple   spaces  ", b" ", &[b"multiple", b"spaces"]),
        (b",leading", b",", &[b"leading"]),
        (b"trailing,", b",", &[b"trailing"]),
        (b"a,b,c;d;e", b",;", &[b"a", b"b", b"c", b"d", b"e"]),
        (b"a,;b", b",;", &[b"a", b"b"]),
        (b"", b" ", &[]),
        (b"   ", b" ", &[]),
        (b" ,; ,;", b" ,;", &[]),
        (b"", b"", &[]),
        (b"a\xffb\xffc", b"\xff", &[b"a", b"b", b"c"]),
        (b"\x80mid\x80", b"\x80", &[b"mid"]),
        (b"lone", b"\xff", &[b"lone"]),
    ];
    for (s, cs, want) in sp {
        let got = o_split(s, cs);
        let wv: Vec<Vec<u8>> = want.iter().map(|x| x.to_vec()).collect();
        if got != wv {
            eprintln!("CHECK FAIL c09 split({:?},{:?})", s, cs);
            fails += 1;
        }
    }

    // ---- strcmp hand cases (exact byte difference, incl. high bytes).
    let cases: &[(&[u8], &[u8], i64)] = &[
        (b"abc", b"abc", 0),
        (b"abc", b"abd", -1),
        (b"abd", b"abc", 1),
        (b"abc", b"abcd", -100),
        (b"abcd", b"abc", 100),
        (b"", b"", 0),
        (b"", b"a", -97),
        (b"a", b"", 97),
        (&[0x80], &[0x01], 127),
        (&[0xff], &[b'a'], 158),
        (&[b'A', 0x80], &[b'A', 0x7f], 1),
        (&[0x80], &[0x7f], 1),
        (&[0x7f], &[0x80], -1),
        (b"abc\xff", b"abc\x01", 254),
        (b"abc\x01", b"abc\xff", -254),
        (b"prefix", b"prefix!", -33),
    ];
    for (a, b, want) in cases {
        if o_strcmp(a, b) != *want {
            eprintln!("CHECK FAIL c09 strcmp({:?},{:?})", a, b);
            fails += 1;
        }
    }

    // ---- property sweep.
    let mut rng = Rng::new(909);
    for _ in 0..20000 {
        // split: tokens non-empty, separator-free, order-preserving reconstruction.
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
                eprintln!("CHECK FAIL c09 split token invariant");
                fails += 1;
            }
        }
        let kept: Vec<u8> = s.iter().cloned().filter(|c| !cs.contains(c)).collect();
        let joined: Vec<u8> = toks.concat();
        if kept != joined {
            eprintln!("CHECK FAIL c09 split reconstruction");
            fails += 1;
        }

        // strcmp: reflexive == 0, antisymmetric in sign.
        let la = rng.below(8);
        let a = rand_body(&mut rng, la, true);
        let lb = rng.below(8);
        let b = rand_body(&mut rng, lb, true);
        if o_strcmp(&a, &a) != 0 || o_strcmp(&a, &b).signum() != -o_strcmp(&b, &a).signum() {
            eprintln!("CHECK FAIL c09 strcmp property");
            fails += 1;
        }
    }

    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "c09_split" | "c09_strcmp") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        if f.len() < 2 { continue; }
        if name == "c09_split" { sink(o_split(&unhex(f[0]), &unhex(f[1]))); }
        else { sink(o_strcmp(&unhex(f[0]), &unhex(f[1]))); }
    }
    true
}
