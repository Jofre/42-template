//! Rush02 (c-piscine-rush-02) reference: convert a number to its written value.
//!
//! Line format (see oracle/README.md):
//!   rush02_words   <decimal-number>\t<written-value>
//!
//! THE DICTIONARY IS FIXED HERE, and this file writes the fixture
//! c-piscine/c-piscine-rush-02/tests/ex00/fixtures/ref.dict from it, entry for
//! entry (`rush02_fixtures`, below). The check script passes that same file to
//! the student's binary, so both sides read the same dictionary and any
//! difference is the program's. The pair used to be kept by hand -- "change
//! one and you must change the other", with nothing comparing them -- and now
//! //c-piscine/c-piscine-rush-02:ex00_oracle_fixtures (tools/oracle_fixtures.sh)
//! fails when the file is not what this module writes. It opens no file to do
//! so: it prints the bytes, and the test compares them. The one file read here
//! is a dictionary a named case hands the reference program (`run`, below),
//! as it hands it a student's.
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
//! tracked, because rush-02 is turned in with one; the template build
//! strips every `*.dict`, so the published template carries none. This file --
//! ref.dict -- is the harness's own and ships.
//!
//! WHAT THIS REFERENCE ASSUMES, AND WHERE IT GATES
//! -----------------------------------------------
//! The subject pins four outputs and no composition rule. It shows `forty two`
//! and `one hundred thousand`, which fix the separator (a single space), the
//! tens-then-units order and the "<group> <scale>" shape. Everything else is
//! open: whether 101 reads "one hundred one" or "one hundred and one", whether a
//! leading group of one is spelled out, and which of several decompositions is
//! preferred. Bonus 1 then explicitly legalises "-", "," and "and" on top.
//!
//! So this implements ONE reading -- the one the subject's own transcripts
//! demonstrate -- and a comparison of whole outputs against it is a tool a team
//! points at their own implementation (the `manual` targets), not a gate. What
//! does gate is what every reading agrees on: the named cases, whose
//! dictionaries and expected outputs `rush02_fixtures` writes, and, at strict,
//! the differences from these corpora that no reading explains
//! (tools/rush02_check.sh --settled): "Error" for a valid number, "Dict Error"
//! from a dictionary holding every key the reference needs, words that are
//! not the dictionary's values.
//!
//! This is the same reason rush-01 validates with tools/rush01_check.sh instead
//! of byte-diffing: where a subject admits several correct answers, a differ
//! that demands one of them is a broken test, not a strict one.

use crate::common::{esc_posix, sink, unesc_posix, Rng};
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
/// and positive integer" -- and `./rush-02 0` prints zero, so 0 counts. So an
/// empty argument, a sign and any byte that is not a digit are Error, which the
/// named cases hold every program to ('', '-42', '4a2', the subject's '10.4').
/// A leading zero is open: whether "0042" is a valid and positive integer the
/// subject never says, so its named cases accept the number's words or Error
/// (any_of), and this reference reads it as its value (`words` drops the
/// zeros). The generator never emits one, nor a '+' or surrounding spaces,
/// which the subject never rules on either.
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
    if name == "rush02_fixtures" {
        gen_fixtures();
        return true;
    }
    if name == "rush02_big_dict" {
        print!("{}", big_dict());
        return true;
    }
    if name != "rush02_words" {
        return false;
    }
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    let _ = w.write_all(corpus_words(seed, count).as_bytes());
    let _ = w.flush();
    true
}

/// The length of case `i` of rush02_words: small values, the teens and
/// round tens, EVERY length from 1 to 42 digits -- the whole reach of
/// duodecillion, ref.dict's largest scale (10^39), whose last number is
/// 10^42 - 1 -- and one bucket past it (43 to 45 digits), where the
/// dictionary runs out. Five buckets of every twelve walk the lengths from 4
/// to 39 one after another, so any corpus of 92 cases or more holds each of
/// them (check() asserts it at the count the targets run): the sweep used to
/// draw 6, 12, 21, 30 and 37 only, and never 38 or 39, undecillion's last
/// lengths before duodecillion. The
/// reference answers "Dict Error" there, which is ONE reading of "If the
/// dictionary does not allow you to perform the conversion": a spelling that
/// combines scale words is another, so the settled check reads a spelling
/// there as information, and only "Error" as a verdict, since the number is
/// a valid and positive integer (finding 170: the sweep stopped at 37
/// digits, so duodecillion was never reached, and a program answering Error
/// past 39 digits agreed with every case).
fn words_len(rng: &mut Rng, i: usize) -> usize {
    match i % 12 {
        0 => 1,
        1 => 2,
        2 => 3,
        b @ 3..=7 => 4 + ((i / 12) * 5 + b - 3) % 36,
        8 => 40,
        9 => 41,
        10 => 42,
        _ => 43 + rng.below(3),
    }
}

/// The numbers of the two shapes the named cases at basic hold as every
/// reading spells them (the module's BUILD file, "what the subject states in
/// words"): a number below 100 with a key of its own -- every teen, and a
/// ten -- and a round number in the "<group> <scale>" shape of the subject's
/// "one hundred thousand", the group one key other than one. Words drawn at
/// random hold a teen alone one time in a hundred, and a round number almost
/// never, so a program that spelled 13 "ten three" passed the settled
/// corpus (the mutation run of 2026-10-03). rush02_check.sh --settled reads
/// the shapes from the number and the dictionary, never from this list;
/// check() holds each to its shape.
const SETTLED_SHAPES: [&str; 14] = [
    "11", "12", "13", "14", "15", "16", "17", "18", "19", "70", "13000", "7000000", "90000000000",
    "2000000000000000000000000000000000000000",
];

/// The rush02_words corpus, one case per line: <number>\t<expected>, the
/// expected output being the words or "Dict Error" (check() reads it back).
fn corpus_words(seed: u64, count: usize) -> String {
    use std::fmt::Write as _;
    let mut rng = Rng::new(seed);
    let mut w = String::new();

    // The subject's own four, first, so a corpus always covers them; then
    // SETTLED_SHAPES, the numbers every reading spells alike, which
    // rush02_check.sh --settled compares word for word.
    for n in ["42", "0", "100000", "20"].iter().chain(SETTLED_SHAPES.iter()) {
        if let Some(v) = words(n) {
            let _ = writeln!(w, "{}\t{}", n, v);
        }
    }
    for i in 0..count {
        let len = words_len(&mut rng, i);
        let n = rand_digits(&mut rng, len);
        let v = words(&n).unwrap_or_else(|| "Dict Error".to_string());
        let _ = writeln!(w, "{}\t{}", n, v);
    }
    w
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
        let len = 1 + rng.below(42);
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
    if words(&"9".repeat(42)).is_none() {
        eprintln!("rush02: 10^42 - 1 is duodecillion's last number; the dictionary expresses it");
        fails += 1;
    }

    // ---- the corpora reach as far as the dictionary does, and past it ----
    // Finding 170: both stopped at 37 digits, so ref.dict's duodecillion was
    // never needed, and a program answering Error past 39 digits agreed with
    // every case. Every line of rush02_words is a valid number with its
    // words, or Dict Error exactly when it is longer than 42 digits.
    let (mut reach, mut past) = (false, false);
    let mut lens = [false; 43];
    for line in corpus_words(1, 200).lines() {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() != 2 || !valid_number(f[0]) || f[0].starts_with('0') && f[0] != "0" {
            eprintln!("rush02: rush02_words line {:?} is not a valid number, a tab and what it prints", line);
            fails += 1;
            continue;
        }
        if (f[1] == "Dict Error") != (f[0].len() > 42) {
            eprintln!("rush02: rush02_words expects {:?} for a {}-digit number", f[1], f[0].len());
            fails += 1;
        }
        reach |= f[0].len() >= 40 && f[0].len() <= 42;
        past |= f[0].len() > 42;
        if f[0].len() <= 42 {
            lens[f[0].len()] = true;
        }
    }
    if !reach || !past {
        eprintln!("rush02: rush02_words reaches 40-42 digits: {}, and past them: {}", reach, past);
        fails += 1;
    }
    // Every length, at the counts ex00_settled_words_diff (200) and
    // ex00_settled_dicts_diff (150) run with seed 1: docs/rushes.md says
    // both sweep every length up to 42 digits, and 38 and 39 were missing.
    let missing: Vec<usize> = (1..=42).filter(|&l| !lens[l]).collect();
    if !missing.is_empty() {
        eprintln!("rush02: rush02_words (seed 1, 200 cases) has no number of {:?} digits", missing);
        fails += 1;
    }
    // Every settled shape is in the corpus, and is one: one key's value
    // (below 100), or a group key's and a scale key's, word for word.
    let corpus = corpus_words(1, 200);
    for n in SETTLED_SHAPES.iter() {
        let want = if n.len() <= 2 {
            lookup(n).map(|v| v.to_string())
        } else {
            let lead = if (n.len() - 1) % 3 == 0 { &n[..1] } else { &n[..2] };
            let scale = format!("1{}", &n[lead.len()..]);
            match (lookup(lead), lookup(&scale)) {
                (Some(a), Some(b)) if lead != "1" && n[lead.len()..].bytes().all(|b| b == b'0') => {
                    Some(format!("{} {}", a, b))
                }
                _ => None,
            }
        };
        let line = format!("{}\t{}", n, want.clone().unwrap_or_default());
        if want.is_none() || !corpus.lines().any(|l| l == line) {
            eprintln!("rush02: the settled shape {} is not in rush02_words as {:?}", n, want);
            fails += 1;
        }
    }
    let mut lens = [false; 43];
    for line in corpus_dicts(1, 150).lines() {
        if let Some(n) = line.split('\t').nth(1) {
            if n.len() <= 42 {
                lens[n.len()] = true;
            }
        }
    }
    let missing: Vec<usize> = (1..=42).filter(|&l| !lens[l]).collect();
    if !missing.is_empty() {
        eprintln!("rush02: rush02_dicts (seed 1, 150 cases) has no number of {:?} digits", missing);
        fails += 1;
    }

    fails += check_fixtures();
    fails += check_dict_gen();

    // ---- the big dictionary keeps every promise its header makes ----
    let big = big_dict();
    // Read by the reference's own parser (parse_dict, the grammar the
    // reference program applies): a dictionary it refused would be Dict Error
    // for every program held to it, whatever the header promises.
    let kv = match parse_dict(big.as_bytes()) {
        Some(kv) => kv,
        None => {
            eprintln!("rush02: the big dictionary does not parse under the reference's reading");
            fails += 1;
            Vec::new()
        }
    };
    let mut keys: Vec<&str> = kv.iter().map(|(k, _)| k.as_str()).collect();
    keys.sort_unstable();
    let n_keys = keys.len();
    keys.dedup();
    if keys.len() != n_keys {
        eprintln!("rush02: the big dictionary holds a key twice");
        fails += 1;
    }
    for (k, _) in DICT {
        if !kv.iter().any(|(kk, _)| kk == k) {
            eprintln!("rush02: the big dictionary lacks the reference key {}", k);
            fails += 1;
        }
    }
    for (k, _) in &kv {
        let in_dict = DICT.iter().any(|(dk, _)| dk == k);
        let small = k.len() <= 3;
        let power = k.starts_with('1') && k[1..].bytes().all(|b| b == b'0');
        if !in_dict && (small || power || k.starts_with('0') || !k.bytes().all(|b| b.is_ascii_digit())) {
            eprintln!("rush02: the big dictionary's filler key {:?} could be looked up", k);
            fails += 1;
            break;
        }
    }
    if compose_with("42", &kv).as_deref() != Some("forty two") {
        eprintln!("rush02: the big dictionary does not spell 42 as the subject does");
        fails += 1;
    }
    let forty = big.find("\n40: forty\n").map(|i| i + 1);
    let two = big.find("\n2: two\n").map(|i| i + 1);
    if forty != Some(BIG_DICT_SPLIT_AT) || BIG_DICT_SPLIT_AT + 4 >= 4096 || BIG_DICT_SPLIT_AT + 8 < 4096 {
        eprintln!("rush02: \"40: forty\" starts at {:?}, its value not across byte 4096", forty);
        fails += 1;
    }
    if two.map_or(true, |i| i <= 65536) || big.len() <= 65536 {
        eprintln!("rush02: \"2: two\" is not past 64 KiB ({:?} of {})", two, big.len());
        fails += 1;
    }
    if !big.lines().any(|l| l.len() > 4096) || !big.contains("\n\n") {
        eprintln!("rush02: the big dictionary lacks a value past 4096 bytes or a blank line");
        fails += 1;
    }
    if big.bytes().any(|b| b != b'\n' && !(0x20..=0x7e).contains(&b)) {
        eprintln!("rush02: the big dictionary holds a byte that is not printable");
        fails += 1;
    }

    sink(fails);
    fails
}

// ---------------------------------------------------------------- the big dictionary
//
// Every dictionary the harness hands over is under 1 KiB, so a program that
// read the file in one read() of 4096 bytes, or of 64 KiB, or kept its entries
// in an array of 64 or 1024, passed every layer (finding 041). This one is past
// all of those, and every byte of it is a dictionary the subject calls legal
// (p.7), so every reading agrees on what 42 prints with it: "forty two", the
// subject's own transcript. A FILE, not a corpus: `oracle rush02_big_dict`
// prints it, seed and count unread, and //oracle:rush02_big_dict writes it for
// the ex00_dict_big case (c-piscine/c-piscine-rush-02/BUILD.bazel).
//
//   * filler: entries in the subject's own form whose keys 42 never looks up
//     -- none in 0..999, none a power of ten, so none is a key of DICT or of
//     the number or its group -- plus blank lines ("There can be empty
//     lines"), values of 300 and 5000 printable characters, and never a key
//     twice or one with a leading zero;
//   * the filler first, the keys 42 needs last: "2: two" after byte 65536;
//   * one needed value across byte 4096: "40: forty" starts at byte 4090, so
//     "forty" is bytes 4094..4098 (counted from 0), cut "fo" | "rty" by a
//     read of 4096;
//   * every key of DICT, once (the subject: the dictionary holds the reference
//     keys).

/// Where "40: forty" starts (counted from 0): its value, at +4, spans 4096.
pub const BIG_DICT_SPLIT_AT: usize = 4090;

fn filler_line(key: usize) -> String {
    // A printable value that is not a number word, never with a space at
    // either end (the subject trims those), longer every so often.
    let long = match key % 97 {
        0 => 300,
        _ => 0,
    };
    let mut v = format!("filler {}", key);
    while v.len() < long {
        v.push('z');
    }
    format!("{}: {}\n", key, v)
}

pub fn big_dict() -> String {
    let mut out = String::new();
    let mut key = 1001usize;
    // Filler up to the split, a blank line at a time once a whole entry no
    // longer fits, so "40: forty" starts at exactly BIG_DICT_SPLIT_AT.
    loop {
        let l = filler_line(key);
        if out.len() + l.len() > BIG_DICT_SPLIT_AT {
            break;
        }
        out.push_str(&l);
        key += 1;
        if key % 13 == 0 {
            out.push('\n');
        }
    }
    while out.len() < BIG_DICT_SPLIT_AT {
        out.push('\n');
    }
    out.push_str("40: forty\n");
    // One value longer than any read() a program might pick.
    out.push_str(&format!("{}: {}\n", key, "y".repeat(5000)));
    key += 1;
    while out.len() <= 65536 + 1024 {
        out.push_str(&filler_line(key));
        key += 1;
        if key % 13 == 0 {
            out.push('\n');
        }
    }
    for (k, v) in DICT {
        if *k != "40" {
            out.push_str(&format!("{}: {}\n", k, v));
        }
    }
    out
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

/// A random printable value: letters, digits, punctuation, colons and runs of
/// interior spaces. "[any printable characters]" admits all of them, and a
/// value is trimmed at its ends only, so "a  b" prints as "a  b" and "12:30" as
/// "12:30" (finding 168: a parser that splits on every ':' or squeezes spaces
/// passed every corpus before). Never a space at either end -- the subject says
/// to TRIM those, so a value that had them would make the expected output
/// ambiguous rather than testing anything -- nor a colon: "20::x" has one
/// reading, but nothing is gained by asking which colon separates.
fn rand_value(rng: &mut Rng) -> String {
    const ENDS: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?+-*/#@";
    const INNER: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?+-*/#@:";
    let len = 1 + rng.below(7);
    let mut s = String::new();
    for i in 0..len {
        if i > 0 && rng.below(6) == 0 {
            for _ in 0..1 + rng.below(3) {
                s.push(' ');
            }
        }
        let a = if i == 0 || i + 1 == len { ENDS } else { INNER };
        s.push(a[rng.below(a.len())] as char);
    }
    s
}

/// Build a dictionary file body from a key->value map, with the legal noise the
/// subject guarantees a parser must survive: empty lines, 0-3 spaces either
/// side of the colon, and 0-3 after the value.
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
        // Spaces after the value too, which the subject says to trim: the
        // fuzzed dictionaries never had one, so a value kept untrimmed at its
        // end passed every generated case (the mutation run of 2026-10-03).
        for _ in 0..rng.below(4) {
            out.push(' ');
        }
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
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    let _ = w.write_all(corpus_dicts(seed, count).as_bytes());
    let _ = w.flush();
}

/// The rush02_dicts corpus, one case per line (check_dict_gen reads it back).
fn corpus_dicts(seed: u64, count: usize) -> String {
    use std::fmt::Write as _;
    let mut rng = Rng::new(seed);
    let mut w = String::new();

    for i in 0..count {
        // a number whose size sweeps the whole range the reference keys
        // reach: every length up to 42 digits, duodecillion's last (finding
        // 170). Two buckets of every five walk 1 to 39 one after another, so
        // a corpus of 99 cases or more holds each (check() asserts it); they
        // drew 1 to 37 at random, and never 38 or 39.
        let len = match i % 5 {
            0 => 1 + rng.below(3),
            1 => 1 + rng.below(9),
            b @ 2..=3 => 1 + ((i / 5) * 2 + b - 2) % 39,
            _ => 40 + rng.below(3),
        };
        let n = rand_digits(&mut rng, len);

        // every reference key, with a RANDOM value -- this is the part that
        // catches a program which hardcodes English instead of reading the file
        let mut kv: Vec<(String, String)> = DICT
            .iter()
            .map(|(k, _)| (k.to_string(), rand_value(&mut rng)))
            .collect();

        // keys the subject allows a dictionary to ADD beyond the reference set.
        // Half of them are shaped like a key a number needs -- a 1 and as many
        // digits as the hundred or a scale key has after its 1, never that key
        // itself -- so a lookup that takes a key by its length or its first
        // digit finds one of these (finding 166). A key the dictionary already
        // has is never drawn again: the file is shuffled, and which of two
        // entries a program keeps is not a question the subject answers.
        for _ in 0..rng.below(3) {
            let key = if rng.below(2) == 0 {
                let after = if rng.below(4) == 0 { 2 } else { 3 * (1 + rng.below(13)) };
                let mut k = String::from("1");
                for _ in 0..after {
                    k.push((b'0' + rng.below(10) as u8) as char);
                }
                k
            } else {
                format!("{}", 7 + rng.below(900000))
            };
            if kv.iter().any(|(k, _)| *k == key) {
                continue;
            }
            kv.push((key, rand_value(&mut rng)));
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
    w
}

// ---------------------------------------------------------------- named fixtures
//
// THE FILES THE NAMED CASES READ (rush02_fixtures): every dictionary under
// tests/ex00/fixtures/ and every expected output under tests/ex00/, written by
// this module, and //c-piscine/c-piscine-rush-02:ex00_oracle_fixtures fails
// when a file there is not these bytes. Each expected output is this
// reference's answer to the (dictionary, number) pairs that name it, so a
// fixture, the number a case gives with it and what it must print cannot
// drift apart -- the three were typed by hand, once, and nothing held them
// together. Two pairs that name one file must agree, or nothing is written.
//
// Every number here is shaped like the subject's transcripts ("forty two",
// "one hundred thousand": the "<group> <scale>" shape, a leading group other
// than one, no group that raises the "and" question), so every reading of the
// open composition questions agrees on it, and a named case may assert it at
// basic. Record: <path under tests/ex00/>\t<bytes, as common::esc_posix>.

/// A dictionary as this reference reads the subject's grammar,
/// "[a number][0 to n spaces]:[0 to n spaces][any printable characters]\n",
/// or None for "Dict Error". An empty line is skipped ("There can be empty
/// lines"); the value is trimmed of spaces at its ends and nothing else ("You
/// will trim the spaces before and after the values"). A byte that is not
/// printable anywhere in the value is an error, and that is ONE reading: a CR
/// before the newline is not printable here, while a program that trims every
/// kind of white space would drop it -- the basic case with CRLF line endings
/// accepts either answer, and the strict one takes this reading. A value must
/// have one character at least, and a key digits only.
pub fn parse_dict(bytes: &[u8]) -> Option<Vec<(String, String)>> {
    let mut kv: Vec<(String, String)> = Vec::new();
    let body = match bytes.last() {
        Some(b'\n') => &bytes[..bytes.len() - 1],
        _ => bytes,
    };
    if body.is_empty() {
        return Some(kv);
    }
    for line in body.split(|&b| b == b'\n') {
        if line.is_empty() {
            continue;
        }
        let mut i = 0;
        while i < line.len() && line[i].is_ascii_digit() {
            i += 1;
        }
        if i == 0 {
            return None;
        }
        let key = &line[..i];
        while i < line.len() && line[i] == b' ' {
            i += 1;
        }
        if i >= line.len() || line[i] != b':' {
            return None;
        }
        let mut v = &line[i + 1..];
        while let [b' ', rest @ ..] = v {
            v = rest;
        }
        while let [rest @ .., b' '] = v {
            v = rest;
        }
        if v.is_empty() || v.iter().any(|&b| !(0x20..=0x7e).contains(&b)) {
            return None;
        }
        kv.push((
            String::from_utf8(key.to_vec()).ok()?,
            String::from_utf8(v.to_vec()).ok()?,
        ));
    }
    Some(kv)
}

/// What `./rush-02 <dictionary> <number>` prints under this reference: the
/// words, "Error" for a number that is not a valid and positive integer, or
/// "Dict Error" for a dictionary that does not parse or cannot spell it --
/// each with the newline the subject's transcripts show (`| cat -e`, `$`).
pub fn answer(dict: &[u8], number: &str) -> Vec<u8> {
    let s = if !valid_number(number) {
        "Error".to_string()
    } else {
        match parse_dict(dict).and_then(|kv| compose_with(number, &kv)) {
            Some(v) => v,
            None => "Dict Error".to_string(),
        }
    };
    let mut b = s.into_bytes();
    b.push(b'\n');
    b
}

/// `./rush-02 <arg>...` under this reference, as `oracle run rush-02` runs it
/// for c_program's `reference = True`: one argument is the number, with the
/// dictionary numbers.dict where the program runs -- the subject's `./rush-02
/// 42`, beside the numbers.dict its transcript greps -- and two are the
/// dictionary's path and the number. Any other count is one the subject
/// leaves to the program ("handle errors coherently"): "Error". A number that
/// is not a valid and positive integer is "Error" whatever the dictionary;
/// a dictionary that cannot be read allows no conversion: "Dict Error". The
/// exit status is 0: the subject names none.
pub fn run(args: &[String]) -> i32 {
    let (path, number) = match args {
        [n] => ("numbers.dict", n.as_str()),
        [d, n] => (d.as_str(), n.as_str()),
        _ => ("", ""),
    };
    let out = match std::fs::read(path) {
        Ok(dict) => answer(&dict, number),
        Err(_) if !valid_number(number) => answer(b"", number),
        Err(_) => b"Dict Error\n".to_vec(),
    };
    let stdout = io::stdout();
    let mut w = stdout.lock();
    let _ = w.write_all(&out);
    let _ = w.flush();
    0
}

/// Lines "key: value", each ending in `eol`.
fn render_lines(lines: &[String], eol: &str) -> Vec<u8> {
    let mut out = String::new();
    for l in lines {
        out.push_str(l);
        out.push_str(eol);
    }
    out.into_bytes()
}

/// The reference's entries as "key: value" lines, with `edit` applied to each
/// (key, line) -- None drops the line.
fn ref_lines(upto: usize, edit: &dyn Fn(&str, String) -> Option<String>) -> Vec<String> {
    DICT[..upto]
        .iter()
        .filter_map(|(k, v)| edit(k, format!("{}: {}", k, v)))
        .collect()
}

/// How many entries the subject's "reference dictionary" has: the keys up to
/// undecillion, which is where 42's numbers.dict stops. ref.dict adds
/// duodecillion, a key "more entries can be added" allows; the fixtures that
/// break one line keep 42's set, so that the line they break is their only
/// difference from a dictionary every program must read.
fn n42() -> usize {
    DICT.len() - 1
}

/// Every dictionary the named cases read, by its path under tests/ex00/.
fn fixture_dicts() -> Vec<(&'static str, Vec<u8>)> {
    let same = |_: &str, l: String| Some(l);
    let all = DICT.len();
    let mut out: Vec<(&'static str, Vec<u8>)> = Vec::new();

    // The harness's own reference dictionary: the reference, entry for entry.
    out.push(("fixtures/ref.dict", render_lines(&ref_lines(all, &same), "\n")));
    // The subject's own replaced value, spelled as its transcript greps it:
    // `20    :     hey everybody ! $` -- spaces either side of the colon and
    // one after the value, which trimming removes.
    out.push((
        "fixtures/custom.dict",
        render_lines(
            &ref_lines(n42(), &|k, l| {
                Some(if k == "20" { "20 : hey everybody ! ".to_string() } else { l })
            }),
            "\n",
        ),
    ));
    // The two ways a line can break the grammar: no colon, a key that is no
    // number.
    out.push((
        "fixtures/nocolon.dict",
        render_lines(
            &ref_lines(n42(), &|k, l| Some(if k == "40" { "40 forty".to_string() } else { l })),
            "\n",
        ),
    ));
    out.push((
        "fixtures/badkey.dict",
        render_lines(
            &ref_lines(n42(), &|k, l| Some(if k == "40" { "forty: 40".to_string() } else { l })),
            "\n",
        ),
    ));
    // A key gone that nothing else can stand in for: 5 is a unit, where a
    // missing scale could be argued to compose from others.
    out.push((
        "fixtures/nofive.dict",
        render_lines(&ref_lines(n42(), &|k, l| if k == "5" { None } else { Some(l) }), "\n"),
    ));
    // Everything the grammar allows a parser to meet: empty lines, entries out
    // of order, no space and several either side of the colon, spaces after a
    // value -- the two 42 is spelled with, "You will trim the spaces before
    // and after the values": no line ended in one, so a value never trimmed
    // at its end passed this case (finding 042, the mutation run of
    // 2026-10-03) -- and a key beyond the reference set.
    let quirks: Vec<String> = [
        "",
        "1000000:million",
        "9   :   nine",
        "",
        "100:hundred",
        "0: zero",
        "1000  :  thousand",
    ]
    .iter()
    .map(|s| s.to_string())
    .chain(ref_lines(n42(), &|k, l| {
        if ["1000000", "9", "100", "0", "1000"].contains(&k) {
            None
        } else if k == "40" || k == "2" {
            Some(format!("{}   ", l))
        } else {
            Some(l)
        }
    }))
    .chain(
        ["", "999999999999999999999999999999999999999: a key the subject never required"]
            .iter()
            .map(|s| s.to_string()),
    )
    .collect();
    out.push(("fixtures/quirks.dict", render_lines(&quirks, "\n")));
    // Keys shaped like the ones a number needs, before the real ones: a 1 and
    // as many digits as the hundred or a scale key has after its 1 (finding
    // 166). A lookup that takes a key by its length or its first digit meets
    // these first.
    let decoys: Vec<String> = ["123", "1234", "1001", "12345", "1234567"]
        .iter()
        .map(|k| format!("{}: not the key {}", k, k))
        .chain(ref_lines(all, &same))
        .collect();
    out.push(("fixtures/decoys.dict", render_lines(&decoys, "\n")));
    // A value with colons in it, and one with runs of spaces inside and
    // around it: "[any printable characters]", trimmed at its ends only
    // (finding 168).
    out.push((
        "fixtures/colon.dict",
        render_lines(
            &ref_lines(all, &|k, l| {
                Some(if k == "20" { "20: it is 20:00 : twenty".to_string() } else { l })
            }),
            "\n",
        ),
    ));
    out.push((
        "fixtures/spaced.dict",
        render_lines(
            &ref_lines(all, &|k, l| {
                Some(if k == "20" { "20 :   hey   every  body !   ".to_string() } else { l })
            }),
            "\n",
        ),
    ));
    // Bytes that are not printable (finding 169): a tab inside a value 42
    // needs, which is an error under every reading ("any printable
    // characters", and trimming touches the ends only); and every line ended
    // with CR LF, which one reading trims away with the spaces.
    out.push((
        "fixtures/tab.dict",
        render_lines(
            &ref_lines(all, &|k, l| Some(if k == "40" { "40: for\tty".to_string() } else { l })),
            "\n",
        ),
    ));
    out.push(("fixtures/crlf.dict", render_lines(&ref_lines(all, &same), "\r\n")));
    // Every value made up (finding 160): each reference word spelled
    // backwards, so no value is one a program could print from English of
    // its own. "The values inside it must be used to print the result."
    out.push((
        "fixtures/replaced.dict",
        render_lines(&ref_lines(all, &|k, _| lookup(k).map(|v| format!("{}: {}", k, made_up(v)))), "\n"),
    ));
    out
}

/// A reference value made up: the word spelled backwards.
fn made_up(v: &str) -> String {
    v.chars().rev().collect()
}

/// The round numbers the named cases spell, by the expected output each
/// names: a leading group of one word that is not one, and a scale -- the
/// "<group> <scale>" of the subject's "one hundred thousand", which every
/// reading of the open composition questions spells alike. Past unsigned int
/// (nine billion, ten digits) and as far as ref.dict's largest scale (two
/// duodecillion, forty digits, past any integer type C has).
const ROUND: &[(&str, &str, usize)] = &[
    ("seven_million.txt", "7", 2),
    ("nine_billion.txt", "9", 3),
    ("two_duodecillion.txt", "2", 13),
];

/// The group `lead` times 1000^scale, as digits.
fn round_number(lead: &str, scale: usize) -> String {
    format!("{}{}", lead, "000".repeat(scale))
}

/// The smallest number ref.dict cannot reach: 10^42, one past duodecillion's
/// last. A valid and positive integer, so never Error; Dict Error is this
/// reference's reading, and the strict case's.
fn past_dictionary() -> String {
    format!("1{}", "0".repeat(42))
}

/// The number whose unit is missing in the middle of its spelling, with
/// nofive.dict: "four thousand five hundred forty two", or "forty five
/// hundred forty two" -- every spelling needs the key 5, and has words
/// before it and after it (finding 160: the only Dict Error case for a
/// missing key gave 5 itself, where the missing word is the number's only
/// word, so a program that skipped what it could not find passed).
const MID_NUMBER: &str = "4542";

/// The (dictionary, number) pairs whose answers are expected outputs, by the
/// file under tests/ex00/ each one names. A pair here is a named case in
/// c-piscine/c-piscine-rush-02/BUILD.bazel (the one-argument cases stage the
/// dictionary as numbers.dict and give the number alone: the same pair).
fn fixture_answers() -> Vec<(&'static str, &'static str, String)> {
    let mut v = vec![
        // The subject's transcripts, and its replaced value.
        ("forty_two.txt", "fixtures/ref.dict", "42".to_string()),
        ("zero.txt", "fixtures/ref.dict", "0".to_string()),
        ("error.txt", "fixtures/ref.dict", "10.4".to_string()),
        ("hundred_thousand.txt", "fixtures/ref.dict", "100000".to_string()),
        ("custom20.txt", "fixtures/custom.dict", "20".to_string()),
        // Not a valid and positive integer: empty, signed, a letter inside.
        ("error.txt", "fixtures/ref.dict", "".to_string()),
        ("error.txt", "fixtures/ref.dict", "-42".to_string()),
        ("error.txt", "fixtures/ref.dict", "4a2".to_string()),
        // What the dictionary's grammar allows, and what it does not.
        ("forty_two.txt", "fixtures/quirks.dict", "42".to_string()),
        ("hundred_thousand.txt", "fixtures/decoys.dict", "100000".to_string()),
        ("colon20.txt", "fixtures/colon.dict", "20".to_string()),
        ("spaced20.txt", "fixtures/spaced.dict", "20".to_string()),
        ("dicterr.txt", "fixtures/nocolon.dict", "42".to_string()),
        ("dicterr.txt", "fixtures/badkey.dict", "42".to_string()),
        ("dicterr.txt", "fixtures/tab.dict", "42".to_string()),
        ("dicterr.txt", "fixtures/crlf.dict", "42".to_string()),
        // A key the number needs is missing, and nothing else can stand in:
        // the whole number, and in the middle of one.
        ("dicterr.txt", "fixtures/nofive.dict", "5".to_string()),
        ("dicterr.txt", "fixtures/nofive.dict", MID_NUMBER.to_string()),
        // What the subject states in words, on numbers shaped like its
        // transcripts: a teen, which has a key of its own; round numbers
        // past unsigned int (ROUND); the first number past the dictionary,
        // the strict case's reading; every value replaced.
        ("thirteen.txt", "fixtures/ref.dict", "13".to_string()),
        ("dicterr.txt", "fixtures/ref.dict", past_dictionary()),
        ("replaced0.txt", "fixtures/replaced.dict", "0".to_string()),
        ("replaced42.txt", "fixtures/replaced.dict", "42".to_string()),
        ("replaced100000.txt", "fixtures/replaced.dict", "100000".to_string()),
    ];
    for (file, lead, scale) in ROUND {
        v.push((file, "fixtures/ref.dict", round_number(lead, *scale)));
    }
    v
}

/// The argument files the named cases read ("argv_file" in BUILD.bazel): the
/// arguments Bazel's `args` cannot carry, one per line, an empty line an
/// empty argument. Each is the number of a pair in fixture_answers, so the
/// file a case hands its program and the answer it expects come from one
/// place (check_fixtures holds them together).
const ARGV_FILES: &[(&str, &[&str])] = &[
    // Not a valid and positive integer: the empty number, which Bazel drops.
    ("empty_arg.argv", &[""]),
];

/// An argument file's bytes: each argument, then a newline.
fn argv_bytes(args: &[&str]) -> Vec<u8> {
    let mut b = Vec::new();
    for a in args {
        b.extend_from_slice(a.as_bytes());
        b.push(b'\n');
    }
    b
}

/// Every file, by its path under tests/ex00/: the dictionaries, the argument
/// files, then each expected output once. Err names two pairs that disagree
/// about one file.
fn fixture_files() -> Result<Vec<(String, Vec<u8>)>, String> {
    let dicts = fixture_dicts();
    let mut files: Vec<(String, Vec<u8>)> =
        dicts.iter().map(|(p, b)| (p.to_string(), b.clone())).collect();
    files.extend(ARGV_FILES.iter().map(|(p, a)| (p.to_string(), argv_bytes(a))));
    let mut outs: Vec<(String, Vec<u8>, String)> = Vec::new();
    for (file, dict, number) in fixture_answers() {
        let body = match dicts.iter().find(|(p, _)| *p == dict) {
            Some((_, b)) => b,
            None => return Err(format!("{} names {}, which no fixture is", file, dict)),
        };
        let got = answer(body, &number);
        let from = format!("{} {:?}", dict, number);
        match outs.iter().find(|(p, _, _)| p == file) {
            Some((_, b, first)) if *b != got => {
                return Err(format!(
                    "{}: {} answers {:?}, {} answers {:?}",
                    file,
                    first,
                    String::from_utf8_lossy(b),
                    from,
                    String::from_utf8_lossy(&got)
                ));
            }
            Some(_) => {}
            None => outs.push((file.to_string(), got, from)),
        }
    }
    outs.sort();
    files.extend(outs.into_iter().map(|(p, b, _)| (p, b)));
    Ok(files)
}

fn gen_fixtures() {
    let files = match fixture_files() {
        Ok(f) => f,
        Err(e) => {
            eprintln!("rush02_fixtures: {}", e);
            std::process::exit(1);
        }
    };
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    for (path, bytes) in files {
        let _ = writeln!(w, "{}\t{}", path, esc_posix(&bytes));
    }
    let _ = w.flush();
}

/// The named fixtures: consistent, faithful to the subject's transcripts, and
/// each file doing the one thing it is there for.
fn check_fixtures() -> usize {
    let mut fails = 0usize;
    let files = match fixture_files() {
        Ok(f) => f,
        Err(e) => {
            eprintln!("rush02: fixtures: {}", e);
            return 1;
        }
    };
    let get = |p: &str| -> Vec<u8> {
        files.iter().find(|(q, _)| q == p).map(|(_, b)| b.clone()).unwrap_or_default()
    };
    // The subject's transcripts, verbatim (chapter IV, with `| cat -e`).
    for (p, want) in [
        ("forty_two.txt", "forty two\n"),
        ("zero.txt", "zero\n"),
        ("error.txt", "Error\n"),
        ("hundred_thousand.txt", "one hundred thousand\n"),
        ("custom20.txt", "hey everybody !\n"),
        ("dicterr.txt", "Dict Error\n"),
    ] {
        if get(p) != want.as_bytes() {
            eprintln!("rush02: fixtures: {} is {:?}, the subject shows {:?}", p, String::from_utf8_lossy(&get(p)), want);
            fails += 1;
        }
    }
    // Every file travels as a record: printable, one line, and back intact.
    for (p, b) in &files {
        let e = esc_posix(b);
        if unesc_posix(&e) != *b || e.contains('\n') || e.contains('\t') {
            eprintln!("rush02: fixtures: {} does not survive its record", p);
            fails += 1;
        }
    }
    // ref.dict IS the reference: it parses back to DICT, entry for entry.
    let refd = parse_dict(&get("fixtures/ref.dict"));
    let dict: Vec<(String, String)> = DICT.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
    if refd.as_ref() != Some(&dict) {
        eprintln!("rush02: fixtures: ref.dict does not parse back to the reference's entries");
        fails += 1;
    }
    // Each broken dictionary is broken by its one line, and each legal one
    // parses: nothing else can be why a case expects what it expects.
    for (p, parses) in [
        ("fixtures/custom.dict", true),
        ("fixtures/quirks.dict", true),
        ("fixtures/decoys.dict", true),
        ("fixtures/colon.dict", true),
        ("fixtures/spaced.dict", true),
        ("fixtures/nofive.dict", true),
        ("fixtures/nocolon.dict", false),
        ("fixtures/badkey.dict", false),
        ("fixtures/tab.dict", false),
        ("fixtures/crlf.dict", false),
        ("fixtures/replaced.dict", true),
    ] {
        if parse_dict(&get(p)).is_some() != parses {
            eprintln!("rush02: fixtures: {} {} parse", p, if parses { "must" } else { "must not" });
            fails += 1;
        }
    }
    // With the tab and the CRs taken out, those two are ref.dict again, so
    // the one byte is the whole difference.
    let untab: Vec<u8> = get("fixtures/tab.dict").into_iter().filter(|&b| b != b'\t').collect();
    let uncr: Vec<u8> = get("fixtures/crlf.dict").into_iter().filter(|&b| b != b'\r').collect();
    if untab != get("fixtures/ref.dict") || uncr != get("fixtures/ref.dict") {
        eprintln!("rush02: fixtures: tab.dict and crlf.dict must be ref.dict but for their one byte");
        fails += 1;
    }
    // The decoys come first, are none of the reference's keys and start with
    // the 1 the hundred and every scale key start with; three of them have
    // the length of one too (123, 1234, 1234567: the hundred, the thousand,
    // the million).
    let decoys = parse_dict(&get("fixtures/decoys.dict")).unwrap_or_default();
    let mut shaped = 0;
    for (k, _) in decoys.iter().take(5) {
        if DICT.iter().any(|(r, _)| r == k) || !k.starts_with('1') {
            eprintln!("rush02: fixtures: decoy key {} must start with 1 and be no reference key", k);
            fails += 1;
        }
        if DICT.iter().any(|(r, _)| r.len() == k.len() && r.starts_with('1')) {
            shaped += 1;
        }
    }
    if shaped < 3 {
        eprintln!("rush02: fixtures: only {} decoy keys have the length of a needed key", shaped);
        fails += 1;
    }
    // Which files a case accepts for the run it makes is not checked here --
    // 0042 and 00, crlf.dict's 42: that pairing is the case's, in
    // BUILD.bazel, and ex00_reference_cases runs every case with `oracle run
    // rush-02` (run, above), any_of ones included. A list here was a second
    // copy of it, kept by hand.
    // Each argument file holds one line per argument, and its arguments are
    // the number of a pair whose answer a case expects.
    let pairs = fixture_answers();
    for (p, args) in ARGV_FILES {
        let b = get(p);
        let lines: Vec<&[u8]> = match b.split_last() {
            Some((&b'\n', body)) => body.split(|&c| c == b'\n').collect(),
            _ => Vec::new(),
        };
        if lines.len() != args.len()
            || lines.iter().zip(args.iter()).any(|(l, a)| *l != a.as_bytes())
            || !args.iter().any(|a| pairs.iter().any(|(_, _, n)| n == a))
        {
            eprintln!("rush02: fixtures: {} must hold {:?}, one per line, the number of a named pair", p, args);
            fails += 1;
        }
    }
    fails + check_stated()
}

/// The cases for what the subject states in words (finding 160, 170) assert
/// only what every reading agrees on: each is checked here for the shape
/// that makes it so, never against words typed in.
fn check_stated() -> usize {
    let mut fails = 0usize;
    let files = match fixture_files() {
        Ok(f) => f,
        Err(_) => return 1,
    };
    let get = |p: &str| -> String {
        files
            .iter()
            .find(|(q, _)| q == p)
            .map(|(_, b)| String::from_utf8_lossy(b).into_owned())
            .unwrap_or_default()
    };
    let w = |k: &str| lookup(k).unwrap_or("?").to_string();
    // A teen is one key of its own.
    if get("thirteen.txt") != w("13") + "\n" {
        eprintln!("rush02: fixtures: thirteen.txt must be the value of the key 13 alone");
        fails += 1;
    }
    // "<group> <scale>": a group of one word that is not one, then its scale.
    for (file, lead, scale) in ROUND {
        let want = format!("{} {}\n", w(lead), w(&scale_key(*scale)));
        if *lead == "1" || w(lead).contains(' ') || get(file) != want {
            eprintln!("rush02: fixtures: {} must be a one-word group other than one, then its scale", file);
            fails += 1;
        }
    }
    // Past unsigned int, and past every integer type C has.
    let big = |f: &str| ROUND.iter().find(|(p, _, _)| *p == f).map(|(_, l, s)| round_number(l, *s)).unwrap_or_default();
    if big("nine_billion.txt").parse::<u64>().map_or(true, |n| n <= u32::MAX as u64)
        || big("two_duodecillion.txt").parse::<u128>().is_ok()
        || big("two_duodecillion.txt").len() != scale_key(13).len()
    {
        eprintln!("rush02: fixtures: the round numbers must pass unsigned int, and reach duodecillion past u128");
        fails += 1;
    }
    // The first number past the dictionary, and only just.
    let past = past_dictionary();
    if words(&past).is_some() || past.len() != 43 {
        eprintln!("rush02: fixtures: past_dictionary() must be 10^42, which ref.dict cannot reach");
        fails += 1;
    }
    // The missing unit sits mid-number: words before and after it, and it is
    // the only key the number lacks in nofive.dict.
    let toks: Vec<String> = words(MID_NUMBER).unwrap_or_default().split(' ').map(|t| t.to_string()).collect();
    let at = toks.iter().position(|t| *t == w("5"));
    let mut nofive = parse_dict(&files.iter().find(|(p, _)| p == "fixtures/nofive.dict").map(|(_, b)| b.clone()).unwrap_or_default())
        .unwrap_or_default();
    let lacks = compose_with(MID_NUMBER, &nofive).is_none();
    nofive.push(("5".to_string(), w("5")));
    if !matches!(at, Some(i) if i > 0 && i + 1 < toks.len()) || !lacks || compose_with(MID_NUMBER, &nofive).is_none() {
        eprintln!("rush02: fixtures: {} must need the key 5 mid-number, and nofive.dict lack only that", MID_NUMBER);
        fails += 1;
    }
    // Every replaced value is none of the reference's words, and so is every
    // word the replaced cases print.
    let replaced = parse_dict(&get("fixtures/replaced.dict").into_bytes()).unwrap_or_default();
    let keys: Vec<&str> = replaced.iter().map(|(k, _)| k.as_str()).collect();
    let refkeys: Vec<&str> = DICT.iter().map(|(k, _)| *k).collect();
    if keys != refkeys || replaced.iter().any(|(_, v)| DICT.iter().any(|(_, r)| r == v)) {
        eprintln!("rush02: fixtures: replaced.dict must hold every reference key, and no reference value");
        fails += 1;
    }
    for f in ["replaced0.txt", "replaced42.txt", "replaced100000.txt"] {
        let out = get(f);
        if out.trim_end().is_empty() || out.trim_end().split(' ').any(|t| DICT.iter().any(|(_, r)| *r == t)) {
            eprintln!("rush02: fixtures: {} must print the replaced values only", f);
            fails += 1;
        }
    }
    // quirks.dict ends the lines of 40 and 2, the keys 42 is spelled with,
    // in spaces: what "trim the spaces ... after the values" is about.
    let q = get("fixtures/quirks.dict");
    for k in ["40", "2"] {
        let key_of = |l: &str| l.split(':').next().unwrap_or("").trim_end().to_string();
        if !q.lines().any(|l| key_of(l) == k && l.ends_with(' ')) {
            eprintln!("rush02: fixtures: quirks.dict has no line for {} whose value is followed by a space", k);
            fails += 1;
        }
    }
    fails
}

/// The generated dictionaries keep the promises gen_dicts makes: values with
/// colons and runs of spaces inside, extra keys shaped like needed ones, and
/// no key twice.
fn check_dict_gen() -> usize {
    let mut fails = 0usize;
    let mut rng = Rng::new(0xD1C7);
    let (mut colon, mut runs) = (false, false);
    for _ in 0..2000 {
        let v = rand_value(&mut rng);
        if v.starts_with(' ') || v.ends_with(' ') || v.starts_with(':') || v.ends_with(':') {
            eprintln!("rush02: rand_value {:?} has a space or a colon at an end", v);
            fails += 1;
        }
        colon |= v.contains(':');
        runs |= v.contains("  ");
    }
    if !colon || !runs {
        eprintln!("rush02: rand_value never makes a colon ({}) or a run of spaces ({})", colon, runs);
        fails += 1;
    }
    // The corpus itself, parsed back: every dictionary through parse_dict, a
    // decoy-shaped extra key somewhere.
    let mut buf: Vec<u8> = Vec::new();
    let mut decoy = false;
    for line in corpus_dicts(1, 200).lines() {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() != 3 {
            eprintln!("rush02: rush02_dicts line with {} fields", f.len());
            fails += 1;
            continue;
        }
        buf.clear();
        buf.extend(unesc_posix(f[0]));
        let kv = match parse_dict(&buf) {
            Some(kv) => kv,
            None => {
                eprintln!("rush02: rush02_dicts wrote a dictionary its own parser refuses");
                fails += 1;
                continue;
            }
        };
        let mut keys: Vec<&String> = kv.iter().map(|(k, _)| k).collect();
        keys.sort();
        keys.dedup();
        if keys.len() != kv.len() {
            eprintln!("rush02: rush02_dicts wrote a key twice");
            fails += 1;
        }
        decoy |= kv.iter().any(|(k, _)| {
            k.starts_with('1') && !DICT.iter().any(|(r, _)| r == k) && DICT.iter().any(|(r, _)| r.len() == k.len() && r.starts_with('1'))
        });
        // What the corpus expects is what its own file answers, read back
        // the way a program reads it: shuffled, spaced, with its extra keys.
        let got = answer(&buf, f[1]);
        if got[..got.len() - 1] != *f[2].as_bytes() {
            eprintln!(
                "rush02: rush02_dicts expects {:?} where the parsed file answers {:?}",
                f[2],
                String::from_utf8_lossy(&got)
            );
            fails += 1;
        }
    }
    if !decoy {
        eprintln!("rush02: rush02_dicts holds no decoy key");
        fails += 1;
    }
    fails
}
