//! Rush02 (c-piscine-rush-02) reference: convert a number to its written value.
//!
//! Line format (see oracle/README.md):
//!   rush02_words   <decimal-number>\t<written-value>
//!
//! THE DICTIONARY IS FIXED HERE, and it matches the fixture at
//! c-piscine-rush-02/tests/ex00/fixtures/ref.dict entry for entry. The check
//! script passes that same file to the student's binary, so both sides read the
//! same dictionary and any difference is the program's. Change one and you must
//! change the other BY HAND -- nothing compares them. This used to claim
//! `oracle_check` did; it does not, and cannot: the oracle opens no files at
//! all (that is the property tools/oracle_check.sh exists to assert), so
//! `check()` below tests the subject's worked examples and the validity rules,
//! never this file against that one. Treat the pair as a hand-kept invariant.
//!
//! ON PROVENANCE, because this file is published and the question is fair. The
//! subject fixes the line format (`N: word`) and English fixes the words, so any
//! dictionary that spells the same magnitudes is very nearly forced to be the
//! same bytes -- and for a long time this fixture WAS byte-identical to 42's
//! issued numbers.dict, which made "we wrote our own" impossible to tell apart
//! from "we copied theirs". It now carries duodecillion (10^39), which 42's does
//! not, so the two files are distinguishable and this one covers a magnitude
//! further. 42's numbers.dict is its issued resource and is what a student
//! downloads with their subject. On the PRIVATE branch two copies of it are
//! tracked, because rush-02 is turned in with one; `//tools:make_template`
//! strips every `*.dict`, so the published template carries none. This file --
//! ref.dict -- is the harness's own and ships.
//!
//! WHAT THIS REFERENCE ASSUMES, AND WHY IT CANNOT GATE
//! ---------------------------------------------------
//! The subject pins four outputs and no composition rule. It shows `forty two`
//! and `one hundred thousand`, which fix the separator (a single space), the
//! tens-then-units order and the "<group> <scale>" shape. Everything else is
//! open: whether 101 reads "one hundred one" or "one hundred and one", whether a
//! leading group of one is spelled out, and which of several decompositions is
//! preferred. Bonus 1 then explicitly legalises "-", "," and "and" on top.
//!
//! So this implements ONE reading -- the one the subject's own transcripts
//! demonstrate -- and the target that consumes it is tagged `manual`. It is a
//! tool a team points at their own implementation once they have chosen their
//! composition, not a gate that decides whether they are right. A team whose
//! output differs here has not necessarily got a bug; they may simply have
//! answered a question the subject left to them.
//!
//! This is the same reason rush-01 validates with tools/rush01_check.sh instead
//! of byte-diffing: where a subject admits several correct answers, a differ
//! that demands one of them is a broken test, not a strict one.

use crate::common::{sink, Rng};
use std::io::{self, Write};

/// The reference key set, with the values ref.dict uses. Keys are decimal
/// strings because they run past u128 (duodecillion is 10^39, and the subject
/// says numbers go "beyond the range of unsigned int" without an upper bound).
const DICT: &[(&str, &str)] = &[
    ("0", "zero"),
    ("1", "one"),
    ("2", "two"),
    ("3", "three"),
    ("4", "four"),
    ("5", "five"),
    ("6", "six"),
    ("7", "seven"),
    ("8", "eight"),
    ("9", "nine"),
    ("10", "ten"),
    ("11", "eleven"),
    ("12", "twelve"),
    ("13", "thirteen"),
    ("14", "fourteen"),
    ("15", "fifteen"),
    ("16", "sixteen"),
    ("17", "seventeen"),
    ("18", "eighteen"),
    ("19", "nineteen"),
    ("20", "twenty"),
    ("30", "thirty"),
    ("40", "forty"),
    ("50", "fifty"),
    ("60", "sixty"),
    ("70", "seventy"),
    ("80", "eighty"),
    ("90", "ninety"),
    ("100", "hundred"),
    ("1000", "thousand"),
    ("1000000", "million"),
    ("1000000000", "billion"),
    ("1000000000000", "trillion"),
    ("1000000000000000", "quadrillion"),
    ("1000000000000000000", "quintillion"),
    ("1000000000000000000000", "sextillion"),
    ("1000000000000000000000000", "septillion"),
    ("1000000000000000000000000000", "octillion"),
    ("1000000000000000000000000000000", "nonillion"),
    ("1000000000000000000000000000000000", "decillion"),
    ("1000000000000000000000000000000000000", "undecillion"),
    ("1000000000000000000000000000000000000000", "duodecillion"),
];

fn lookup(key: &str) -> Option<&'static str> {
    DICT.iter().find(|(k, _)| *k == key).map(|(_, v)| *v)
}

/// The scale key for group `i` counted from the right: 1000^i as a decimal
/// string. Built by text rather than arithmetic because 1000^12 does not fit in
/// any integer type Rust offers, which is the whole point of this exercise.
fn scale_key(i: usize) -> String {
    let mut s = String::from("1");
    for _ in 0..(3 * i) {
        s.push('0');
    }
    s
}

/// Render one group of 1..=999. Returns None if the dictionary lacks a key.
fn group_words(n: u32, out: &mut Vec<&'static str>) -> Option<()> {
    let h = n / 100;
    let r = n % 100;
    if h > 0 {
        out.push(lookup(&h.to_string())?);
        out.push(lookup("100")?);
    }
    if r == 0 {
        return Some(());
    }
    if r < 20 {
        out.push(lookup(&r.to_string())?);
    } else {
        out.push(lookup(&((r / 10) * 10).to_string())?);
        if r % 10 != 0 {
            out.push(lookup(&(r % 10).to_string())?);
        }
    }
    Some(())
}

/// The reference conversion. `digits` must already be known-valid (all ASCII
/// digits, non-empty). Returns None when the dictionary cannot express it,
/// which is the "Dict Error" case.
pub fn words(digits: &str) -> Option<String> {
    let trimmed = digits.trim_start_matches('0');
    if trimmed.is_empty() {
        // every digit was a zero
        return Some(lookup("0")?.to_string());
    }
    // split into groups of three, from the right
    let bytes = trimmed.as_bytes();
    let mut groups: Vec<u32> = Vec::new();
    let mut end = bytes.len();
    while end > 0 {
        let start = end.saturating_sub(3);
        let g: u32 = trimmed[start..end].parse().ok()?;
        groups.push(g);
        end = start;
    }
    let mut out: Vec<&'static str> = Vec::new();
    for i in (0..groups.len()).rev() {
        if groups[i] == 0 {
            continue;
        }
        group_words(groups[i], &mut out)?;
        if i > 0 {
            let owned = scale_key(i);
            // lookup returns a 'static str, so the key must outlive the call;
            // DICT is 'static, so the found value is too -- only the KEY is
            // temporary here.
            out.push(lookup(&owned)?);
        }
    }
    Some(out.join(" "))
}

/// Is this argument a valid number for the subject's purposes? "must be a valid
/// and positive integer" -- and `./rush-02 0` prints zero, so 0 counts. Nothing
/// else is decided here: a leading '+', a leading zero and surrounding spaces
/// are all cases the subject never rules on, so the generator never emits them
/// and this returns false only for inputs the subject's own example rejects.
pub fn valid_number(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

/// A random decimal string of `len` digits, no leading zero.
fn rand_digits(rng: &mut Rng, len: usize) -> String {
    let mut s = String::new();
    s.push((b'1' + (rng.below(9) as u8)) as char);
    for _ in 1..len {
        s.push((b'0' + (rng.below(10) as u8)) as char);
    }
    s
}

pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    if name == "rush02_dicts" {
        gen_dicts(seed, count);
        return true;
    }
    if name != "rush02_words" {
        return false;
    }
    let mut rng = Rng::new(seed);
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());

    // The subject's own four, first, so a corpus always covers them.
    for n in ["42", "0", "100000", "20"] {
        if let Some(v) = words(n) {
            let _ = writeln!(w, "{}\t{}", n, v);
        }
    }
    for i in 0..count {
        // Sweep the whole representable range: small values, the awkward teens
        // and round tens, and lengths up to 42 digits -- past duodecillion, where
        // the dictionary runs out and the answer is "Dict Error" rather than a
        // string. Those are skipped here; the check script covers them from the
        // fixture side.
        let len = match i % 8 {
            0 => 1,
            1 => 2,
            2 => 3,
            3 => 6,
            4 => 12,
            5 => 21,
            6 => 30,
            _ => 37,
        };
        let n = rand_digits(&mut rng, len);
        if let Some(v) = words(&n) {
            let _ = writeln!(w, "{}\t{}", n, v);
        }
    }
    let _ = w.flush();
    true
}

/// Self-check: the subject's transcript, plus structural properties.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- the subject's own worked examples (chapter IV), verbatim ----
    let cases: [(&str, &str); 3] = [
        ("42", "forty two"),
        ("0", "zero"),
        ("100000", "one hundred thousand"),
    ];
    for (n, want) in cases {
        match words(n) {
            Some(got) if got == want => {}
            other => {
                eprintln!("rush02: {} -> {:?}, want {:?}", n, other, want);
                fails += 1;
            }
        }
    }

    // ---- the number validity rule the subject demonstrates ----
    if valid_number("10.4") {
        eprintln!("rush02: '10.4' must not be a valid number");
        fails += 1;
    }
    if !valid_number("0") || !valid_number("100000") {
        eprintln!("rush02: '0' and '100000' must be valid numbers");
        fails += 1;
    }

    // ---- structural: every emitted token is a dictionary value ----
    let mut rng = Rng::new(0xC0FFEE);
    for _ in 0..2000 {
        let len = 1 + (rng.below(37) as usize);
        let n = rand_digits(&mut rng, len);
        if let Some(v) = words(&n) {
            for tok in v.split(' ') {
                if !DICT.iter().any(|(_, val)| *val == tok) {
                    eprintln!("rush02: {} produced non-dictionary token {:?}", n, tok);
                    fails += 1;
                    break;
                }
            }
        }
    }

    // ---- beyond the dictionary's reach is Dict Error, not a wrong answer ----
    let too_big = "1".to_string() + &"0".repeat(42);
    if words(&too_big).is_some() {
        eprintln!("rush02: 10^42 is past duodecillion; the dictionary cannot express it");
        fails += 1;
    }

    sink(fails);
    fails
}

// ---------------------------------------------------------------- dictionary fuzz
//
// The arm above pins ONE dictionary, so it only ever exercises composition. This
// one generates a fresh dictionary per case and hands the SAME file to both
// sides, which reaches three things the fixed-dictionary corpus cannot:
//
//   * values are random strings, not English number words. A program that
//     hardcodes "forty"/"hundred" instead of reading the file passes every
//     fixed-dictionary test and fails here on the first case. The subject's
//     grammar says the value is "any printable characters" and its own example
//     redefines 20 to "hey everybody !", so this is mandatory behaviour, not an
//     edge case -- and argv[1] being a replacement dictionary is the base
//     subject, not a bonus.
//   * the parser meets real variation: zero-to-many spaces on both sides of the
//     colon, blank lines, entries in arbitrary order, keys beyond the reference
//     set. All explicitly legal, so all must parse.
//   * "Dict Error" gets generated deliberately, by dropping a key the number
//     needs, instead of being asserted from one hand-written fixture.
//
// Corpus line: <escaped-dict>\t<number>\t<expected>, where the escape is
// rush00's ('\\' -> "\\\\", '\n' -> "\\n", other non-printables -> "\\xHH") so a
// whole multi-line file rides on one line. The expected field is the literal
// string "Dict Error" when the dictionary cannot express the number.

fn esc(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 8);
    for &b in s.as_bytes() {
        match b {
            b'\\' => out.push_str("\\\\"),
            b'\n' => out.push_str("\\n"),
            b'\t' => out.push_str("\\t"),
            0x20..=0x7e => out.push(b as char),
            _ => out.push_str(&format!("\\x{:02x}", b)),
        }
    }
    out
}

/// A random printable value: letters, digits and interior spaces. Never starts
/// or ends with a space -- the subject says to TRIM those, so a value that had
/// them would make the expected output ambiguous rather than testing anything.
fn rand_value(rng: &mut Rng) -> String {
    const A: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?+-*/#@";
    let len = 1 + rng.below(7);
    let mut s = String::new();
    for i in 0..len {
        if i > 0 && rng.below(6) == 0 {
            s.push(' ');
        }
        s.push(A[rng.below(A.len())] as char);
    }
    s
}

/// Build a dictionary file body from a key->value map, with the legal noise the
/// subject guarantees a parser must survive.
fn render_dict(rng: &mut Rng, kv: &[(String, String)]) -> String {
    let mut idx: Vec<usize> = (0..kv.len()).collect();
    for i in (1..idx.len()).rev() {
        idx.swap(i, rng.below(i + 1));
    }
    let mut out = String::new();
    for &i in &idx {
        if rng.below(7) == 0 {
            out.push('\n');
        }
        let before = rng.below(4);
        let after = rng.below(4);
        out.push_str(&kv[i].0);
        for _ in 0..before {
            out.push(' ');
        }
        out.push(':');
        for _ in 0..after {
            out.push(' ');
        }
        out.push_str(&kv[i].1);
        out.push('\n');
    }
    if rng.below(3) == 0 {
        out.push('\n');
    }
    out
}

/// Which reference keys does `digits` actually need, under this reference's
/// composition? Derived by running the conversion against a probe dictionary
/// that maps every key to itself, so it cannot drift from `words()`.
fn needed_keys(digits: &str) -> Option<Vec<String>> {
    let probe: Vec<(String, String)> =
        DICT.iter().map(|(k, _)| (k.to_string(), k.to_string())).collect();
    let rendered = compose_with(digits, &probe)?;
    Some(rendered.split(' ').map(|s| s.to_string()).collect())
}

/// `words()` generalised to an arbitrary key->value table. The fixed-dictionary
/// path above is this with DICT; keeping one implementation means the fuzz and
/// the corpus can never disagree about composition.
pub fn compose_with(digits: &str, kv: &[(String, String)]) -> Option<String> {
    let get = |k: &str| -> Option<String> {
        kv.iter().find(|(kk, _)| kk == k).map(|(_, v)| v.clone())
    };
    let trimmed = digits.trim_start_matches('0');
    if trimmed.is_empty() {
        return get("0");
    }
    let mut groups: Vec<u32> = Vec::new();
    let mut end = trimmed.len();
    while end > 0 {
        let start = end.saturating_sub(3);
        groups.push(trimmed[start..end].parse().ok()?);
        end = start;
    }
    let mut out: Vec<String> = Vec::new();
    for i in (0..groups.len()).rev() {
        let n = groups[i];
        if n == 0 {
            continue;
        }
        let h = n / 100;
        let r = n % 100;
        if h > 0 {
            out.push(get(&h.to_string())?);
            out.push(get("100")?);
        }
        if r != 0 {
            if r < 20 {
                out.push(get(&r.to_string())?);
            } else {
                out.push(get(&((r / 10) * 10).to_string())?);
                if r % 10 != 0 {
                    out.push(get(&(r % 10).to_string())?);
                }
            }
        }
        if i > 0 {
            out.push(get(&scale_key(i))?);
        }
    }
    Some(out.join(" "))
}

pub fn gen_dicts(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());

    for i in 0..count {
        // a number whose size sweeps the whole representable range
        let len = 1 + rng.below(match i % 4 {
            0 => 3,
            1 => 9,
            2 => 21,
            _ => 37,
        });
        let n = rand_digits(&mut rng, len);

        // every reference key, with a RANDOM value -- this is the part that
        // catches a program which hardcodes English instead of reading the file
        let mut kv: Vec<(String, String)> = DICT
            .iter()
            .map(|(k, _)| (k.to_string(), rand_value(&mut rng)))
            .collect();

        // keys the subject allows a dictionary to ADD beyond the reference set
        for _ in 0..rng.below(3) {
            kv.push((format!("{}", 7 + rng.below(900000)), rand_value(&mut rng)));
        }

        // one case in five, remove a key this number needs -> "Dict Error"
        let mut expect_err = false;
        if rng.below(5) == 0 {
            if let Some(need) = needed_keys(&n) {
                if !need.is_empty() {
                    let victim = need[rng.below(need.len())].clone();
                    kv.retain(|(k, _)| *k != victim);
                    expect_err = true;
                }
            }
        }

        let body = render_dict(&mut rng, &kv);
        let expected = if expect_err {
            "Dict Error".to_string()
        } else {
            match compose_with(&n, &kv) {
                Some(v) => v,
                None => "Dict Error".to_string(),
            }
        };
        let _ = writeln!(w, "{}\t{}\t{}", esc(&body), n, expected);
    }
    let _ = w.flush();
}
