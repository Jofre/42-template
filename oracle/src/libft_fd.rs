//! Libft references: file-descriptor output (subject v19.3, page 13):
//! ft_putstr_fd, ft_putendl_fd and ft_putnbr_fd. ft_putchar_fd has no arm:
//! its fixture writes all 256 bytes, which is every input it has.
//!
//! Line formats (input, then the bytes the call must write to the fd, as
//! lowercase hex -- a string's bytes are any but NUL, a newline among them,
//! so they never travel raw):
//!   libft_putstr_fd    <hexS>\t<hexWritten>     (s's bytes, nothing added)
//!   libft_putendl_fd   <hexS>\t<hexWritten>     (s's bytes, then exactly one
//!                                                newline)
//!   libft_putnbr_fd    <n>\t<hexWritten>        (n's decimal text, C 04's
//!                                                putnbr rendering)
//!
//! The reader writes to a file on an fd of 3 or more and reads it back, so
//! what it compares is every byte written, in order, whatever the number of
//! write() calls. The putstr and putendl corpora hold strings past 4096
//! bytes and one of 70000, past 65536 (finding 041); check() reads the
//! corpora back and holds them to it, and holds every line, apart from the
//! reference, to written bytes that are s itself (putendl: then one newline)
//! at any length, 70000 among them.

use crate::c04::o_putnbr;
use crate::common::{bench_lines, long_text, rand_body, sink, to_hex, unhex, widest_hex, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles

/// ft_putstr_fd: the string's bytes.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_putstr_fd(s: &[u8]) -> Vec<u8> {
    s.to_vec()
}

/// ft_putendl_fd: the string's bytes "followed by a newline".
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_putendl_fd(s: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(s.len() + 1);
    v.extend_from_slice(s);
    v.push(b'\n');
    v
}

/// ft_putnbr_fd: the decimal text of `n`.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_putnbr_fd(n: i32) -> Vec<u8> {
    o_putnbr(n)
}

// ---------------------------------------------------------- generators

/// putstr's and putendl's strings: the empty one, short ones with a tab and
/// newlines, UTF-8 and bytes above 0x7f, every byte but NUL, and strings past
/// 4096 and past 65536 bytes, each from a seed of its own; then a seeded tail.
fn str_cases(seed: u64, count: usize) -> Vec<Vec<u8>> {
    let mut out: Vec<Vec<u8>> = vec![
        b"Hello".to_vec(),
        vec![],
        b"a\tb\nc".to_vec(),
        b"\n".to_vec(),
        b"caf\xc3\xa9\xff".to_vec(),
        (1u8..=255).collect(),
        long_text(5000, 5000),
        rand_body(&mut Rng::new(70000), 70000, true),
    ];
    out.truncate(count);
    let mut rng = Rng::new(seed);
    while out.len() < count {
        let high = rng.below(2) == 1;
        let n = rng.below(40);
        out.push(rand_body(&mut rng, n, high));
    }
    out
}

/// putnbr's head: zero, one digit and its negative, the powers of ten and
/// their negatives, both ends of int and their neighbours (C 04's rows).
const PUTNBR_HEAD: [i32; 20] = [
    0, 7, 42, 10, 100, 1000000000, -7, -42, -100, -1000000000, 2147483647, 2147483646, -2147483647, i32::MIN,
    1, -1, 9, -9, 99, -99,
];

fn corpus<W: Write>(w: &mut W, name: &str, seed: u64, count: usize) -> bool {
    match name {
        "libft_putstr_fd" | "libft_putendl_fd" => {
            for s in str_cases(seed, count) {
                let out = if name == "libft_putstr_fd" { o_putstr_fd(&s) } else { o_putendl_fd(&s) };
                let _ = writeln!(w, "{}\t{}", to_hex(&s), to_hex(&out));
            }
        }
        "libft_putnbr_fd" => {
            let mut rng = Rng::new(seed);
            for k in 0..count {
                let n = if k < PUTNBR_HEAD.len() { PUTNBR_HEAD[k] } else { rng.i32val() };
                let _ = writeln!(w, "{}\t{}", n, to_hex(&o_putnbr_fd(n)));
            }
        }
        _ => return false,
    }
    true
}

const ARMS: [&str; 3] = ["libft_putstr_fd", "libft_putendl_fd", "libft_putnbr_fd"];

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
        let f = l.split('\t').next().unwrap_or("");
        match name {
            "libft_putstr_fd" => sink(o_putstr_fd(&unhex(f))),
            "libft_putendl_fd" => sink(o_putendl_fd(&unhex(f))),
            _ => {
                if let Ok(n) = f.parse::<i32>() {
                    sink(o_putnbr_fd(n));
                }
            }
        }
    }
    true
}

// ------------------------------------------------------------- self-check

fn written(name: &str, seed: u64, count: usize) -> Vec<u8> {
    let mut v = Vec::new();
    corpus(&mut v, name, seed, count);
    v
}

/// Self-check: hand-verified tables, properties over a seeded sweep, and the
/// corpora read back. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;
    let mut fail = |what: String| {
        eprintln!("CHECK FAIL libft_fd {}", what);
        fails += 1;
    };

    // ---- hand tables ----
    let ps: &[(&[u8], &[u8], &[u8])] = &[
        (b"Hello", b"Hello", b"Hello\n"),
        (b"", b"", b"\n"),
        (b"a\tb\nc", b"a\tb\nc", b"a\tb\nc\n"),
        (b"\n", b"\n", b"\n\n"),
        (b"caf\xc3\xa9\xff", b"caf\xc3\xa9\xff", b"caf\xc3\xa9\xff\n"),
    ];
    for &(s, put, endl) in ps {
        if o_putstr_fd(s) != put || o_putendl_fd(s) != endl {
            fail(format!("putstr_fd/putendl_fd({:?})", s));
        }
    }
    let pn: &[(i32, &[u8])] = &[
        (0, b"0"),
        (7, b"7"),
        (-7, b"-7"),
        (42, b"42"),
        (-42, b"-42"),
        (100, b"100"),
        (-1000000000, b"-1000000000"),
        (2147483647, b"2147483647"),
        (-2147483647, b"-2147483647"),
        (i32::MIN, b"-2147483648"),
    ];
    for &(n, want) in pn {
        if o_putnbr_fd(n) != want {
            fail(format!("putnbr_fd({})", n));
        }
    }

    // ---- properties over a seeded sweep (20 000) ----
    let mut rng = Rng::new(0xfd);
    for _ in 0..20000 {
        let high = rng.below(2) == 1;
        let n = rng.below(40);
        let s = rand_body(&mut rng, n, high);
        // putendl is putstr and exactly one newline more
        let e = o_putendl_fd(&s);
        if o_putstr_fd(&s) != s || e.len() != n + 1 || e[..n] != s[..] || e[n] != b'\n' {
            fail(format!("putstr/putendl property {:?}", s));
        }
        // putnbr reads back to n, '-' only for a negative, no leading zero
        let v = rng.i32val();
        let t = o_putnbr_fd(v);
        let back = std::str::from_utf8(&t).ok().and_then(|x| x.parse::<i32>().ok());
        let digits = if v < 0 { &t[1..] } else { &t[..] };
        if back != Some(v) || (t[0] == b'-') != (v < 0) || (digits.len() > 1 && digits[0] == b'0') {
            fail(format!("putnbr_fd property {}", v));
        }
    }

    // ---- the corpora, read back ----
    let count = 200usize;
    for name in ARMS {
        let a = written(name, 1, count);
        if a != written(name, 1, count) {
            fail(format!("{}: the same seed gave another corpus", name));
        }
        if a == written(name, 2, count) {
            fail(format!("{}: another seed gave the same corpus", name));
        }
        if !a.starts_with(&written(name, 1, 3)) {
            fail(format!("{}: a small count is not a prefix of the corpus", name));
        }
        let text = String::from_utf8_lossy(&a).into_owned();
        let lines: Vec<&str> = text.lines().collect();
        if lines.len() != count {
            fail(format!("{}: {} lines for a count of {}", name, lines.len(), count));
        }
        for l in &lines {
            let f: Vec<&str> = l.split('\t').collect();
            let ok = f.len() == 2
                && match name {
                    // and, apart from the reference, the bytes written are
                    // s itself (putendl: then one '\n'), at any length
                    "libft_putstr_fd" => {
                        let (s, w) = (unhex(f[0]), unhex(f[1]));
                        !s.contains(&0) && w == o_putstr_fd(&s) && w == s
                    }
                    "libft_putendl_fd" => {
                        let (s, w) = (unhex(f[0]), unhex(f[1]));
                        !s.contains(&0)
                            && w == o_putendl_fd(&s)
                            && w.len() == s.len() + 1
                            && w[..s.len()] == s[..]
                            && w[s.len()] == b'\n'
                    }
                    _ => f[0].parse::<i32>().is_ok_and(|n| unhex(f[1]) == o_putnbr_fd(n)),
                };
            if !ok {
                fail(format!("{}: a line that is not the reference's own answer, or breaks a property: {:.120}", name, l));
                break;
            }
        }
        if name != "libft_putnbr_fd" {
            // past every round capacity, and past 65536 (finding 041)
            if widest_hex(&a, 0) <= 65536 {
                fail(format!("{}: no string past 65536 bytes", name));
            }
            if !lines.iter().any(|l| l.starts_with('\t')) {
                fail(format!("{}: no empty string", name));
            }
            if !lines.iter().any(|l| unhex(l.split('\t').next().unwrap_or("")).iter().any(|&b| b > 0x7f)) {
                fail(format!("{}: no byte above 0x7f", name));
            }
        } else {
            for want in [0, i32::MIN, i32::MAX, -1] {
                if !lines.iter().any(|l| l.split('\t').next() == Some(want.to_string().as_str())) {
                    fail(format!("{}: no case of {}", name, want));
                }
            }
        }
    }
    if corpus(&mut Vec::new(), "libft_nope", 1, 1) || bench("libft_nope") {
        fail("an unknown arm was claimed".to_string());
    }

    fails
}
