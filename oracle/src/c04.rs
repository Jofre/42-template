//! c-04 references: putnbr, atoi, putnbr_base, atoi_base.
//!
//! Line formats (see oracle/README.md):
//!   c04_putnbr       <n>\t<printed-decimal>            (printed bytes, RAW ASCII)
//!   c04_atoi         <hexstr>\t<int>                    (libc-atoi cross-checkable)
//!   c04_putnbr_base  <n>\t<hexbase>\t<printed-bytes>   (printed bytes, RAW, safe-printable)
//!   c04_atoi_base    <hexstr>\t<hexbase>\t<int>
//!
//! Encoding rules honoured: byte-strings as lowercase hex, ints as decimal.
//! putnbr / putnbr_base emit their PRINTED output raw because it is ASCII / a
//! safe-printable subset by construction (no NUL, tab or newline), so the raw
//! bytes never disturb the line structure and the reader harness — which lets
//! the student's function write() directly — matches byte-for-byte.

use crate::common::{bench_lines, sink, to_hex, unhex, Rng};
use std::io::{self, Write};

/// The isspace(3) bytes atoi / atoi_base skip and reject inside a base.
const WS: [u8; 6] = [b' ', b'\t', b'\n', 0x0b, 0x0c, b'\r'];

fn is_ws(b: u8) -> bool {
    WS.contains(&b)
}

// ------------------------------------------------------------- oracles

/// ft_putnbr: the decimal text a correct impl write()s for `n` (handles INT_MIN).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_putnbr(n: i32) -> Vec<u8> {
    format!("{}", n).into_bytes()
}

/// ft_atoi as the c-04 SUBJECT defines it — which is NOT libc's atoi: "the
/// string may be preceded by an arbitrary number of '+' and '-' signs. A '-'
/// sign will invert the result depending on whether the number of '-' signs is
/// odd or even", with the subject's own example `" ---+--+1234ab567"` -> -1234.
/// So: skip isspace, consume a RUN of signs, then digits, stopping at the first
/// non-digit. libc is therefore NOT a valid cross-check here (it consumes one
/// sign and returns 0 for "--5"); correctness rests on the subject's example,
/// the curated tests/ex03 fixture, and the atoi/putnbr round-trip property.
/// Accumulates in i64 and every generated magnitude is <= INT_MAX, so the
/// result fits i32 and no overflow-UB is ever exercised.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_atoi(s: &[u8]) -> i32 {
    let mut i = 0usize;
    while i < s.len() && is_ws(s[i]) {
        i += 1;
    }
    let mut sign: i64 = 1;
    while i < s.len() && (s[i] == b'+' || s[i] == b'-') {
        if s[i] == b'-' {
            sign = -sign;
        }
        i += 1;
    }
    let mut val: i64 = 0;
    while i < s.len() && s[i].is_ascii_digit() {
        val = val * 10 + (s[i] - b'0') as i64;
        i += 1;
    }
    (sign * val) as i32
}

/// Is `base` usable for DISPLAYING a number? c-04 ex04's subject
/// (`ft_putnbr_base`) lists exactly three ways a base can be invalid: it is
/// "empty or has only one character", it "contains duplicate characters", or it
/// "contains '+' or '-'". Whitespace is NOT among them.
fn base_valid_display(base: &[u8]) -> bool {
    if base.len() < 2 {
        return false;
    }
    for (k, &c) in base.iter().enumerate() {
        if c == b'+' || c == b'-' {
            return false;
        }
        if base[..k].contains(&c) {
            return false;
        }
    }
    true
}

/// Is `base` usable for PARSING a number? c-04 ex05's subject
/// (`ft_atoi_base`) repeats ex04's three rules and adds one: the base may not
/// contain "'+', '-', or whitespace characters". That single extra clause is
/// the whole difference between the two, and it is a difference the subject
/// draws deliberately -- a space is a fine symbol to PRINT with and an
/// impossible one to READ back, because atoi's own leading-whitespace rule
/// would have consumed it before the digit loop ever saw it.
///
/// These were one function until 2026-08-09, applying the parse rule to both,
/// which made the reference stricter than ex04's subject. It was inert rather
/// than wrong in effect -- `safe_pool()` is 0x21..=0x7e, so no generated case
/// ever held whitespace -- but a reference that disagrees with the subject is
/// a false red waiting for the corpus to widen.
fn base_valid_parse(base: &[u8]) -> bool {
    if !base_valid_display(base) {
        return false;
    }
    !base.iter().any(|&c| is_ws(c))
}

/// Position of byte `c` in `base` = its digit value, else None.
fn digit_in_base(c: u8, base: &[u8]) -> Option<usize> {
    base.iter().position(|&x| x == c)
}

/// Encode non-negative magnitude `m` in `base` (MSB first); 0 -> "base[0]".
fn encode_base(mut m: i64, base: &[u8]) -> Vec<u8> {
    let b = base.len() as i64;
    if m == 0 || b <= 1 {
        return vec![base[0]];
    }
    let mut digs = Vec::new();
    while m > 0 {
        digs.push(base[(m % b) as usize]);
        m /= b;
    }
    digs.reverse();
    digs
}

/// ft_putnbr_base: None (prints nothing) for an invalid base, else the printed
/// bytes. Uses an i64 magnitude so INT_MIN is handled without overflow.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_putnbr_base(nbr: i32, base: &[u8]) -> Option<Vec<u8>> {
    if !base_valid_display(base) {
        return None;
    }
    let mut out = Vec::new();
    let mut m = nbr as i64;
    if m < 0 {
        out.push(b'-');
        m = -m;
    }
    out.extend_from_slice(&encode_base(m, base));
    Some(out)
}

/// ft_atoi_base: invalid base -> 0. Else skip isspace, consume a RUN of '+'/'-'
/// (negative iff an odd count of '-'), then digits (value = index in base),
/// stopping at the first byte not in the base. i64 accumulation; generated
/// magnitudes are bounded to keep the result in i32 range.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_atoi_base(s: &[u8], base: &[u8]) -> i32 {
    if !base_valid_parse(base) {
        return 0;
    }
    let b = base.len() as i64;
    let mut i = 0usize;
    while i < s.len() && is_ws(s[i]) {
        i += 1;
    }
    let mut sign: i64 = 1;
    while i < s.len() && (s[i] == b'+' || s[i] == b'-') {
        if s[i] == b'-' {
            sign = -sign;
        }
        i += 1;
    }
    let mut val: i64 = 0;
    while i < s.len() {
        match digit_in_base(s[i], base) {
            Some(d) => {
                val = val * b + d as i64;
                i += 1;
            }
            None => break,
        }
    }
    (sign * val) as i32
}

// ---------------------------------------------------------- input helpers

/// Printable, non-whitespace bytes usable as base characters (0x21..=0x7e minus
/// '+' and '-'). A base drawn from this pool makes putnbr_base's raw output a
/// tab/newline-free byte string, so it never corrupts a corpus line.
fn safe_pool() -> Vec<u8> {
    (0x21u8..=0x7e).filter(|&c| c != b'+' && c != b'-').collect()
}

/// A distinct-character valid base of random length in [minlen, maxlen].
fn rand_valid_base(rng: &mut Rng, pool: &[u8], minlen: usize, maxlen: usize) -> Vec<u8> {
    let len = minlen + rng.below(maxlen - minlen + 1);
    let mut p = pool.to_vec();
    let n = p.len();
    let mut base = Vec::with_capacity(len);
    for k in 0..len {
        let j = k + rng.below(n - k);
        p.swap(k, j);
        base.push(p[k]);
    }
    base
}

/// A magnitude in [0, INT_MAX], biased to small values and boundaries.
fn rand_magnitude(rng: &mut Rng) -> i64 {
    match rng.below(6) {
        0 => 0,
        1 => 2147483647,
        2 => rng.below(10) as i64,
        3 => rng.below(1000) as i64,
        4 => rng.below(1_000_000) as i64,
        _ => rng.below(2147483648) as i64, // [0, 2147483647]
    }
}

/// Any non-NUL byte.
fn rand_nonnul(rng: &mut Rng) -> u8 {
    (1 + rng.below(255)) as u8
}

/// A non-NUL byte that is not an ASCII digit (a valid "stop" byte for atoi).
fn rand_nondigit(rng: &mut Rng) -> u8 {
    loop {
        let c = rand_nonnul(rng);
        if !c.is_ascii_digit() {
            return c;
        }
    }
}

/// A non-NUL byte that is not in `base` (a valid "stop" byte for atoi_base).
fn rand_not_in_base(rng: &mut Rng, base: &[u8]) -> u8 {
    loop {
        let c = rand_nonnul(rng);
        if !base.contains(&c) {
            return c;
        }
    }
}

// ---------------------------------------------------------- generators

fn atoi_structured() -> Vec<Vec<u8>> {
    let mut v: Vec<Vec<u8>> = Vec::new();
    for s in [
        &b""[..], b" ", b"+", b"-", b"  +", b"7", b"0", b"42", b"000123",
        b"+42", b"-42", b"\t-5", b"   +1", b"abc", b"   ", b"   +a", b"12-3",
        b"  +0042xyz", b"- 42", b"+ 7", b"2147483647", b"-2147483647",
        b"42abc", b"+000", b"-000",
        // INT_MIN / INT_MAX boundaries (correct impl returns them exactly).
        b"-2147483648", b"+2147483647", b"2147483647abc", b"  -2147483648",
        // a RUN of signs is consumed (subject rule): the parity of '-' decides.
        b"+-", b"--", b"-+", b"++", b"+-5", b"--5", b"-+5", b"++5", b"  --42",
        b" ---+--+1234ab567", b"++--++-456", b"   +--+1234ab567", b"  +-+",
    ] {
        v.push(s.to_vec());
    }
    // all isspace bytes then a signed number
    let mut ws = WS.to_vec();
    ws.extend_from_slice(b"-123");
    v.push(ws);
    v
}

fn gen_putnbr(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let structured: Vec<i32> = vec![
        0, 7, 42, 10, 100, 1000000000, -7, -42, -100, -1000000000,
        2147483647, 2147483646, -2147483647, i32::MIN, 1, -1, 9, -9, 99, -99,
    ];
    let mut done = 0usize;
    let mut idx = 0usize;
    while done < count {
        let n = if idx < structured.len() {
            let v = structured[idx];
            idx += 1;
            v
        } else {
            rng.i32val()
        };
        let _ = w.write_all(format!("{}\t", n).as_bytes());
        let _ = w.write_all(&o_putnbr(n));
        let _ = w.write_all(b"\n");
        done += 1;
    }
}

fn gen_atoi(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let structured = atoi_structured();
    let mut done = 0usize;
    let mut idx = 0usize;
    while done < count {
        let s: Vec<u8> = if idx < structured.len() {
            let v = structured[idx].clone();
            idx += 1;
            v
        } else {
            let mut s = Vec::new();
            for _ in 0..rng.below(5) {
                s.push(WS[rng.below(6)]);
            }
            match rng.below(3) {
                0 => {}
                1 => s.push(b'+'),
                _ => s.push(b'-'),
            }
            if rng.below(6) != 0 {
                for _ in 0..rng.below(3) {
                    s.push(b'0');
                }
                let m = rand_magnitude(&mut rng);
                s.extend_from_slice(format!("{}", m).as_bytes());
            }
            if rng.below(2) == 0 {
                s.push(rand_nondigit(&mut rng));
                for _ in 0..rng.below(4) {
                    s.push(rand_nonnul(&mut rng));
                }
            }
            s
        };
        let _ = writeln!(w, "{}\t{}", to_hex(&s), o_atoi(&s));
        done += 1;
    }
}

fn putnbr_base_structured() -> Vec<(i32, Vec<u8>)> {
    let mut v: Vec<(i32, Vec<u8>)> = Vec::new();
    let valid: &[&[u8]] = &[
        b"0123456789", b"01", b"0123456789ABCDEF", b"poneygua",
        b"0123456789abcdef", b"abcdefghijklmnop",
    ];
    for base in valid {
        for &n in &[0i32, 42, -42, 255, 123456, -123456, 1, -1, i32::MIN, 2147483647] {
            v.push((n, base.to_vec()));
        }
    }
    // invalid bases (documented kinds): print nothing regardless of n
    let invalid: &[&[u8]] = &[b"", b"a", b"aba", b"00", b"ab+c", b"ab-c", b"z"];
    for base in invalid {
        for &n in &[42i32, 0, -42] {
            v.push((n, base.to_vec()));
        }
    }
    v
}

fn gen_putnbr_base(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pool = safe_pool();
    let mut w = io::BufWriter::new(io::stdout());
    let structured = putnbr_base_structured();
    let mut done = 0usize;
    let mut idx = 0usize;
    while done < count {
        let (n, base): (i32, Vec<u8>) = if idx < structured.len() {
            let (n, b) = structured[idx].clone();
            idx += 1;
            (n, b)
        } else {
            let n = rng.i32val();
            let base = if rng.below(10) == 0 {
                // an invalid base of a documented kind (empty / len1 / dup / +/-)
                match rng.below(5) {
                    0 => Vec::new(),
                    1 => vec![pool[rng.below(pool.len())]],
                    2 => {
                        let mut b = rand_valid_base(&mut rng, &pool, 2, 7);
                        b.push(b[0]); // duplicate -> invalid
                        b
                    }
                    3 => {
                        let mut b = rand_valid_base(&mut rng, &pool, 2, 7);
                        b.push(b'+');
                        b
                    }
                    _ => {
                        let mut b = rand_valid_base(&mut rng, &pool, 2, 7);
                        b.push(b'-');
                        b
                    }
                }
            } else {
                rand_valid_base(&mut rng, &pool, 2, 20) // len 2..=20
            };
            (n, base)
        };
        let _ = w.write_all(format!("{}\t{}\t", n, to_hex(&base)).as_bytes());
        if let Some(o) = o_putnbr_base(n, &base) {
            let _ = w.write_all(&o);
        }
        let _ = w.write_all(b"\n");
        done += 1;
    }
}

fn atoi_base_structured() -> Vec<(Vec<u8>, Vec<u8>)> {
    let mut v: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
    let mut p = |s: &[u8], b: &[u8]| v.push((s.to_vec(), b.to_vec()));
    // documented parse / sign / stop cases (all within i32 range, no overflow)
    p(b"42", b"0123456789");
    p(b"101010", b"01");
    p(b"2A", b"0123456789ABCDEF");
    p(b"euoopp", b"poneygua");
    p(b"1A", b"0123456789");
    p(b"1012", b"01");
    p(b"   -101010", b"01");
    p(b"-euo", b"poneygua");
    p(b"   ---+--+42ab", b"0123456789");
    p(b"--101", b"01");
    p(b"- 42", b"0123456789");
    p(b"+ 7", b"0123456789");
    p(b"2147483647", b"0123456789");
    // INT_MIN / INT_MAX boundaries in decimal and hex bases (no overflow-UB).
    p(b"-2147483648", b"0123456789");
    p(b"-80000000", b"0123456789abcdef");
    p(b"7fffffff", b"0123456789abcdef");
    p(b"-10000000000000000000000000000000", b"01"); // INT_MIN in base 2
    p(b"0", b"01"); // a plain zero digit
    p(b"", b"01");
    p(b"   ", b"01");
    p(b"  +-+", b"01");
    // invalid bases -> 0
    p(b"42", b"");
    p(b"42", b"a");
    p(b"42", b"aba");
    p(b"42", b"ab+c");
    p(b"42", b"ab-c");
    p(b"42", b"ab c");
    p(b"42", b"ab\tc");
    p(b"101", b"01 ");
    p(b"11", b"01+");
    p(b"11", b"01-");
    v
}

fn gen_atoi_base(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let pool = safe_pool();
    let mut w = io::BufWriter::new(io::stdout());
    let structured = atoi_base_structured();
    let mut done = 0usize;
    let mut idx = 0usize;
    while done < count {
        let (s, base): (Vec<u8>, Vec<u8>) = if idx < structured.len() {
            let (s, b) = structured[idx].clone();
            idx += 1;
            (s, b)
        } else {
            let mut base = rand_valid_base(&mut rng, &pool, 2, 20);
            let corrupt = rng.below(12) == 0;
            if corrupt {
                match rng.below(6) {
                    0 => base.clear(),
                    1 => base.truncate(1),
                    2 => base.push(base[0]),
                    3 => base.push(b'+'),
                    4 => base.push(b'-'),
                    _ => base.push(WS[rng.below(6)]),
                }
            }
            let mut s = Vec::new();
            for _ in 0..rng.below(5) {
                s.push(WS[rng.below(6)]);
            }
            let mut neg = false;
            for _ in 0..rng.below(5) {
                if rng.below(2) == 0 {
                    s.push(b'+');
                } else {
                    s.push(b'-');
                    neg = !neg;
                }
            }
            let _ = neg; // value is recomputed by o_atoi_base from the bytes
            if base.len() >= 2 && rng.below(6) != 0 {
                for _ in 0..rng.below(3) {
                    s.push(base[0]);
                }
                let m = rand_magnitude(&mut rng);
                s.extend_from_slice(&encode_base(m, &base));
            }
            if rng.below(2) == 0 {
                s.push(rand_not_in_base(&mut rng, &base));
                for _ in 0..rng.below(4) {
                    s.push(rand_nonnul(&mut rng));
                }
            }
            (s, base)
        };
        let _ = writeln!(w, "{}\t{}\t{}", to_hex(&s), to_hex(&base), o_atoi_base(&s, &base));
        done += 1;
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c04_putnbr" => gen_putnbr(seed, count),
        "c04_atoi" => gen_atoi(seed, count),
        "c04_putnbr_base" => gen_putnbr_base(seed, count),
        "c04_atoi_base" => gen_atoi_base(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- putnbr ----
    let pn: &[(i32, &[u8])] = &[
        (0, b"0"),
        (7, b"7"),
        (-7, b"-7"),
        (42, b"42"),
        (-42, b"-42"),
        (100, b"100"),
        (1000000000, b"1000000000"),
        (2147483647, b"2147483647"),
        (-2147483647, b"-2147483647"),
        (i32::MIN, b"-2147483648"),
    ];
    for (n, want) in pn {
        if o_putnbr(*n) != *want {
            eprintln!("CHECK FAIL c04 putnbr({})", n);
            fails += 1;
        }
    }

    // ---- atoi (single-sign / libc semantics) ----
    let at: &[(&[u8], i32)] = &[
        (b"42", 42),
        (b"7", 7),
        (b"0", 0),
        (b"000123", 123),
        (b"+42", 42),
        (b"-42", -42),
        (b"\t-5", -5),
        (b"   +1", 1),
        (b"", 0),
        (b"abc", 0),
        (b"   ", 0),
        (b"   +a", 0),
        (b"12-3", 12),
        (b"  +0042xyz", 42),
        (b"- 42", 0),
        (b"+ 7", 0),
        (b"2147483647", 2147483647),
        (b"-2147483647", -2147483647),
        (b"-2147483648", -2147483648),
        (b"+2147483647", 2147483647),
        // sign runs: value is negated once per '-', i.e. by the parity of '-'
        (b"+-", 0),
        (b"--", 0),
        (b"-+", 0),
        (b"++", 0),
        (b"+-5", -5),
        (b"--5", 5),
        (b"-+5", -5),
        (b"++5", 5),
        (b"  --42", 42),
        (b"++--++-456", -456),
        // the subject's own worked example
        (b" ---+--+1234ab567", -1234),
    ];
    for (s, want) in at {
        if o_atoi(s) != *want {
            eprintln!("CHECK FAIL c04 atoi({:?})", s);
            fails += 1;
        }
    }

    // ---- putnbr_base ----
    let pb: &[(i32, &[u8], Option<&[u8]>)] = &[
        (42, b"0123456789", Some(b"42")),
        (-42, b"0123456789", Some(b"-42")),
        (42, b"01", Some(b"101010")),
        (0, b"01", Some(b"0")),
        (255, b"0123456789ABCDEF", Some(b"FF")),
        (123456, b"poneygua", Some(b"euoopp")),
        (-123456, b"poneygua", Some(b"-euoopp")),
        (i32::MIN, b"0123456789", Some(b"-2147483648")),
        (i32::MIN, b"01", Some(b"-10000000000000000000000000000000")),
        (42, b"", None),
        (42, b"a", None),
        (42, b"aba", None),
        (42, b"00", None),
        (42, b"ab+c", None),
        (42, b"ab-c", None),
        // NOT None: ex04's subject lists exactly three invalid shapes and
        // whitespace is not one of them. A space is a perfectly good symbol to
        // PRINT with -- it is only unusable for PARSING, which is why ex05 adds
        // the clause and ex04 does not. This case used to assert None and so
        // pinned the reference stricter than the subject it speaks for.
        (42, b"ab c", Some(&b"   "[..])),
    ];
    for (n, base, want) in pb {
        let got = o_putnbr_base(*n, base);
        let want = want.map(|w| w.to_vec());
        if got != want {
            eprintln!("CHECK FAIL c04 putnbr_base({}, {:?})", n, base);
            fails += 1;
        }
    }

    // ---- atoi_base ----
    let ab: &[(&[u8], &[u8], i32)] = &[
        (b"42", b"0123456789", 42),
        (b"101010", b"01", 42),
        (b"2A", b"0123456789ABCDEF", 42),
        (b"euoopp", b"poneygua", 123456),
        (b"1A", b"0123456789", 1),
        (b"1012", b"01", 5),
        (b"   -101010", b"01", -42),
        (b"-euo", b"poneygua", -241),
        (b"   ---+--+42ab", b"0123456789", -42),
        (b"--101", b"01", 5),
        (b"- 42", b"0123456789", 0),
        (b"+ 7", b"0123456789", 0),
        (b"2147483647", b"0123456789", 2147483647),
        (b"-2147483648", b"0123456789", -2147483648),
        (b"   -80000000", b"0123456789ABCDEF", -2147483648),
        (b"-80000000", b"0123456789abcdef", -2147483648),
        (b"7fffffff", b"0123456789abcdef", 2147483647),
        (b"-10000000000000000000000000000000", b"01", -2147483648),
        (b"0", b"01", 0),
        (b"", b"01", 0),
        (b"   ", b"01", 0),
        (b"  +-+", b"01", 0),
        (b"42", b"", 0),
        (b"42", b"a", 0),
        (b"42", b"aba", 0),
        (b"42", b"ab+c", 0),
        (b"42", b"ab-c", 0),
        (b"42", b"ab c", 0),
        (b"42", b"ab\tc", 0),
        (b"101", b"01 ", 0),
        (b"11", b"01+", 0),
        (b"11", b"01-", 0),
    ];
    for (s, base, want) in ab {
        if o_atoi_base(s, base) != *want {
            eprintln!("CHECK FAIL c04 atoi_base({:?}, {:?})", s, base);
            fails += 1;
        }
    }

    // ---- properties ----
    let mut rng = Rng::new(1234);
    let pool = safe_pool();
    for _ in 0..20000 {
        // atoi(putnbr(n)) == n  (decimal round-trip, incl. INT_MIN)
        let n = rng.i32val();
        if o_atoi(&o_putnbr(n)) != n {
            eprintln!("CHECK FAIL c04 atoi/putnbr round-trip n={}", n);
            fails += 1;
        }
        // atoi_base(putnbr_base(n, base), base) == n  (arbitrary valid base)
        let base = rand_valid_base(&mut rng, &pool, 2, 20);
        let enc = o_putnbr_base(n, &base).expect("valid base");
        if o_atoi_base(&enc, &base) != n {
            eprintln!("CHECK FAIL c04 base round-trip n={}", n);
            fails += 1;
        }
        // a leading '-' negates a non-negative magnitude's encoding
        let m = (rng.next_u64() % 2147483648) as i64; // [0, INT_MAX]
        let mut signed = vec![b'-'];
        signed.extend_from_slice(&encode_base(m, &base));
        if o_atoi_base(&signed, &base) != -(m as i32) {
            eprintln!("CHECK FAIL c04 atoi_base sign m={}", m);
            fails += 1;
        }
        // an even count of '-' stays positive
        let mut two = vec![b'-', b'-'];
        two.extend_from_slice(&encode_base(m, &base));
        if o_atoi_base(&two, &base) != m as i32 {
            eprintln!("CHECK FAIL c04 atoi_base double-sign m={}", m);
            fails += 1;
        }
        // invalid bases: putnbr_base prints nothing, atoi_base is 0
        let mut bad = base.clone();
        bad.push(bad[0]); // duplicate -> invalid
        if o_putnbr_base(n, &bad).is_some() || o_atoi_base(&enc, &bad) != 0 {
            eprintln!("CHECK FAIL c04 invalid-base guard");
            fails += 1;
        }
    }
    // trailing non-digit stops atoi_base at the boundary
    for _ in 0..5000 {
        let base = rand_valid_base(&mut rng, &pool, 2, 11);
        let m = (rng.next_u64() % 1_000_000) as i64;
        let mut s = encode_base(m, &base);
        s.push(rand_not_in_base(&mut rng, &base));
        s.extend_from_slice(b"9zZ!");
        if o_atoi_base(&s, &base) != m as i32 {
            eprintln!("CHECK FAIL c04 atoi_base stop-at-boundary");
            fails += 1;
        }
    }
    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "c04_putnbr" | "c04_atoi" | "c04_putnbr_base" | "c04_atoi_base") {
        return false;
    }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        match name {
            "c04_putnbr" => { if let Ok(n) = f[0].parse::<i32>() { sink(o_putnbr(n)); } }
            "c04_atoi" => sink(o_atoi(&unhex(f[0]))),
            "c04_putnbr_base" => {
                if f.len() >= 2 { if let Ok(n) = f[0].parse::<i32>() { sink(o_putnbr_base(n, &unhex(f[1]))); } }
            }
            _ => { if f.len() >= 2 { sink(o_atoi_base(&unhex(f[0]), &unhex(f[1]))); } }
        }
    }
    true
}
