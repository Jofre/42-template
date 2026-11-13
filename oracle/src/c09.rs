//! c-09 references. c-09 is a libft rebuild of earlier modules, so its
//! references mirror the documented contracts already covered elsewhere:
//!   c09_split   ft_split(char *str, char *charset) -> char**  (== c-07 split)
//!
//! ex00's ft_strcmp is C 03 ex00's function, so it has no arm here: its
//! layers replay C 03's c03_strcmp_sign and c03_strcmp, one corpus for one
//! function, capacity cases included (finding 041), as Piscine Reloaded
//! ex17 does. This module's check() keeps its hand table of o_strcmp.
//!
//! Line formats (input fields, then reference output):
//!   split   <hexStr>\t<hexCharset>\t<nonnull=1>\t<count>[\t<hexTok>...]
//!
//! The `nonnull` field asserts ft_split returned a non-NULL array even when the
//! result has 0 tokens — without it a NULL-returning stub matches every
//! all-separator / empty case (both print count 0).

use crate::common::{
    bench_lines, largest_dec, many_words, o_split, o_strcmp, rand_body, sink, split_draw, split_prop, to_hex, unhex, Rng,
    SPLIT_LARGE,
};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
// ---------------------------------------------------------- generators
fn emit_split<W: Write>(w: &mut W, s: &[u8], charset: &[u8]) {
    let toks = o_split(s, charset);
    // nonnull=1: ft_split must return a non-NULL array (even for 0 tokens).
    let _ = write!(w, "{}\t{}\t1\t{}", to_hex(s), to_hex(charset), toks.len());
    for t in &toks {
        let _ = write!(w, "\t{}", to_hex(t));
    }
    let _ = writeln!(w);
}

fn gen_split<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
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
        emit_split(w, s, cs);
        done += 1;
    }
    for (n, sep) in SPLIT_LARGE {
        if done >= count {
            break;
        }
        emit_split(w, &many_words(n, sep), sep);
        done += 1;
    }
    while done < count {
        let (s, cs) = split_draw(&mut rng);
        emit_split(w, &s, &cs);
        done += 1;
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c09_split" => gen_split(&mut io::BufWriter::new(io::stdout()), seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- the split corpus holds a string of more than 4096 words (finding
    //      041; c07's check holds SPLIT_LARGE to its words), read back from
    //      what the generator writes.
    let mut c = Vec::new();
    gen_split(&mut c, 1, 200);
    if largest_dec(&c, 3) <= 4096 {
        eprintln!("CHECK FAIL c09 split corpus holds no string of more than 4096 words");
        fails += 1;
    }

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
        // split: common::split_prop, one draw from this loop's rng.
        fails += split_prop(&mut rng, "c09");

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
    if name != "c09_split" { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        if f.len() < 2 { continue; }
        sink(o_split(&unhex(f[0]), &unhex(f[1])));
    }
    true
}
