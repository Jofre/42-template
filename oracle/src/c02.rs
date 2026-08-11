//! c-02 string-copy / classification / case references. See oracle/README.md
//! for the corpus-line format per function.
//!
//! Format contract per function (input fields are lowercase hex unless noted).
//! A trailing `1` on the copy/case families asserts the function returned the
//! (dest/str) pointer it was handed — the harness reprints `ret == arg`.
//!   c02_strcpy            <hexSrc>\t<hexDestContent>\t1
//!   c02_strncpy           <hexSrc>\t<n>\t<hexDest(n bytes)>\t1
//!   c02_str_is_*          <hexStr>\t<0|1>
//!   c02_strupcase         <hexStr>\t<hexResult>\t1
//!   c02_strlowcase        <hexStr>\t<hexResult>\t1
//!   c02_strcapitalize     <hexStr>\t<hexResult>\t1
//!   c02_strlcpy           <hexSrc>\t<size>\t<hexDestContent>\t<ret>
//!   c02_putstr_non_printable  <hexStr>\t<escaped-output-verbatim>
//! The escaped output of putstr_non_printable contains only bytes 0x20..=0x7e
//! (printable + backslash), so it carries no TAB/NL and rides raw in the field.

use crate::common::{bench_lines, sink, unhex, rand_body, to_hex, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
/// ft_strcpy: the NUL-terminated content copied into dest == src (no interior
/// NUL in generated inputs, so this is the whole string).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strcpy(src: &[u8]) -> Vec<u8> {
    src.to_vec()
}

/// ft_strncpy: exactly `n` bytes — src[..min(n,len)] then NUL padding to n.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strncpy(src: &[u8], n: usize) -> Vec<u8> {
    let mut d = vec![0u8; n];
    let k = n.min(src.len());
    d[..k].copy_from_slice(&src[..k]);
    d
}

fn is_alpha(s: &[u8]) -> bool {
    s.iter()
        .all(|&b| (b'A'..=b'Z').contains(&b) || (b'a'..=b'z').contains(&b))
}
fn is_numeric(s: &[u8]) -> bool {
    s.iter().all(|&b| (b'0'..=b'9').contains(&b))
}
fn is_lowercase(s: &[u8]) -> bool {
    s.iter().all(|&b| (b'a'..=b'z').contains(&b))
}
fn is_uppercase(s: &[u8]) -> bool {
    s.iter().all(|&b| (b'A'..=b'Z').contains(&b))
}
fn is_printable(s: &[u8]) -> bool {
    s.iter().all(|&b| (0x20..=0x7e).contains(&b))
}

/// ft_strupcase: a..z -> A..Z in place, everything else untouched.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strupcase(s: &[u8]) -> Vec<u8> {
    s.iter()
        .map(|&b| if (b'a'..=b'z').contains(&b) { b - 0x20 } else { b })
        .collect()
}

/// ft_strlowcase: A..Z -> a..z in place, everything else untouched.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strlowcase(s: &[u8]) -> Vec<u8> {
    s.iter()
        .map(|&b| if (b'A'..=b'Z').contains(&b) { b + 0x20 } else { b })
        .collect()
}

fn is_alnum(b: u8) -> bool {
    (b'A'..=b'Z').contains(&b) || (b'a'..=b'z').contains(&b) || (b'0'..=b'9').contains(&b)
}

/// ft_strcapitalize (documented contract): a "word" is a maximal run of
/// alphanumeric bytes. The first byte of each word, if a lowercase letter, is
/// uppercased; every other letter is lowercased; non-letters are untouched.
/// Example: "salut, 42mots quarante-deux" -> "Salut, 42mots Quarante-Deux".
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strcapitalize(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    let mut prev_alnum = false;
    for &b in s {
        let at_word_start = !prev_alnum;
        let nb = if at_word_start {
            if (b'a'..=b'z').contains(&b) {
                b - 0x20
            } else {
                b
            }
        } else if (b'A'..=b'Z').contains(&b) {
            b + 0x20
        } else {
            b
        };
        out.push(nb);
        prev_alnum = is_alnum(nb); // case change never alters alnum-ness
    }
    out
}

/// ft_strlcpy: returns (dest C-string content, return value == strlen(src)).
/// Copies min(strlen(src), size-1) bytes then a NUL when size>0. The returned
/// content is the bytes up to (not including) that NUL.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_strlcpy(src: &[u8], size: usize) -> (Vec<u8>, u64) {
    let slen = src.len();
    let content = if size > 0 {
        let k = slen.min(size - 1);
        src[..k].to_vec()
    } else {
        Vec::new()
    };
    (content, slen as u64)
}

fn hexd(n: u8) -> u8 {
    b"0123456789abcdef"[(n & 0xf) as usize]
}

/// ft_putstr_non_printable: printable bytes (0x20..=0x7e, backslash included)
/// pass through; every other byte becomes '\' + two lowercase hex digits.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_putstr_np(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    for &b in s {
        if (0x20..=0x7e).contains(&b) {
            out.push(b);
        } else {
            out.push(b'\\');
            out.push(hexd(b >> 4));
            out.push(hexd(b & 0xf));
        }
    }
    out
}

// ---------------------------------------------------------- generators
/// Structured + boundary + seeded-random single strings for the copy/case
/// families (no interior NUL). Bias toward short bodies; cover ascii + high.
fn bodies(rng: &mut Rng, count: usize) -> Vec<Vec<u8>> {
    let mut out: Vec<Vec<u8>> = Vec::new();
    out.push(vec![]);
    out.push(vec![b'a']);
    out.push(vec![b'A']);
    out.push(vec![b'z']);
    out.push(vec![b'Z']);
    out.push(vec![0x7f]);
    out.push(vec![0x80]);
    out.push(vec![0xff]);
    out.push(b"Hello World".to_vec());
    out.push(b"aBcDeF 123 xyz".to_vec());
    out.push(b"salut, comment 42mots quarante-deux; a+b".to_vec());
    // strcapitalize corners: leading non-letter word, an already-capitalized
    // word, an all-caps word, and digit/punct word-separators.
    out.push(b"+hello".to_vec());
    out.push(b"Hello".to_vec());
    out.push(b"HELLO".to_vec());
    out.push(b"ab1cd ef2gh".to_vec());
    out.push(b"a-b-c 1a2b".to_vec());
    out.push(b"42abc".to_vec());
    while out.len() < count {
        let high = rng.below(2) == 1;
        let len = rng.below(30);
        out.push(rand_body(rng, len, high));
    }
    out
}

/// Strings for a predicate: empty, every "passing" byte alone, boundary bad
/// singles, all-pass runs, all-pass-with-one-bad, mixed ascii, high bytes.
fn pred_bodies(rng: &mut Rng, count: usize, pass: &[u8]) -> Vec<Vec<u8>> {
    let mut out: Vec<Vec<u8>> = Vec::new();
    out.push(vec![]);
    for &c in pass {
        out.push(vec![c]);
    }
    // boundary singles just outside each class: 0x2f/0x3a straddle '0'..'9',
    // 0x40/0x5b straddle 'A'..'Z', 0x60/0x7b straddle 'a'..'z', 0x1f/0x7f/0x80
    // straddle printable, plus 0xff (high-bit / signed-char trap).
    for &c in &[0x1fu8, 0x20, 0x2f, 0x3a, 0x40, 0x5b, 0x60, 0x7b, 0x7e, 0x7f, 0x80, 0xff] {
        out.push(vec![c]);
    }
    // deterministic "all-in-class then one-out" and "one-out then all-in": 0x7f
    // lies outside every class here (alpha/numeric/lower/upper/printable).
    if let Some(&a) = pass.first() {
        out.push(vec![a, a, a, 0x7f]);
        out.push(vec![0x7f, a, a, a]);
    }
    while out.len() < count {
        let len = rng.below(14);
        match rng.below(4) {
            0 => out.push((0..len).map(|_| pass[rng.below(pass.len())]).collect()),
            1 if len > 0 => {
                let mut v: Vec<u8> = (0..len).map(|_| pass[rng.below(pass.len())]).collect();
                let i = rng.below(v.len());
                v[i] = (1 + rng.below(255)) as u8;
                out.push(v);
            }
            2 => out.push((0..len).map(|_| (0x20 + rng.below(0x5f)) as u8).collect()),
            _ => out.push(rand_body(rng, len, true)),
        }
    }
    out
}

fn pass_pool(kind: u8) -> Vec<u8> {
    match kind {
        0 => (b'A'..=b'Z').chain(b'a'..=b'z').collect(),           // alpha
        1 => (b'0'..=b'9').collect(),                              // numeric
        2 => (b'a'..=b'z').collect(),                              // lowercase
        3 => (b'A'..=b'Z').collect(),                              // uppercase
        _ => (0x20u8..=0x7e).collect(),                            // printable
    }
}

fn gen_strcpy(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let bs = bodies(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for s in &bs {
        // trailing 1: strcpy must return the dest pointer it was given.
        let _ = writeln!(w, "{}\t{}\t1", to_hex(s), to_hex(&o_strcpy(s)));
    }
}

fn gen_strncpy(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut emitted = 0usize;
    // Structured (src, n) corners so they always run and a failure names them:
    // n==0 (nothing written), n<len (NO NUL written), n==len (still no NUL),
    // n>len (NUL padding out to n). Cover empty/ascii/high-byte sources.
    let srcs: [&[u8]; 4] = [b"", b"abc", b"Hello", &[0x80u8, b'a', 0xff]];
    for src in srcs {
        let len = src.len();
        for &n in &[0usize, 1, len.saturating_sub(1), len, len + 1, len + 3] {
            if emitted >= count {
                break;
            }
            // trailing 1: strncpy must return the dest pointer it was given.
            let _ = writeln!(w, "{}\t{}\t{}\t1", to_hex(src), n, to_hex(&o_strncpy(src, n)));
            emitted += 1;
        }
    }
    let bs = bodies(&mut rng, count);
    for s in &bs {
        if emitted >= count {
            break;
        }
        let n = rng.below(s.len() + 6);
        let _ = writeln!(w, "{}\t{}\t{}\t1", to_hex(s), n, to_hex(&o_strncpy(s, n)));
        emitted += 1;
    }
}

fn gen_pred(seed: u64, count: usize, kind: u8, pred: fn(&[u8]) -> bool) {
    let mut rng = Rng::new(seed);
    let bs = pred_bodies(&mut rng, count, &pass_pool(kind));
    let mut w = io::BufWriter::new(io::stdout());
    for s in &bs {
        let _ = writeln!(w, "{}\t{}", to_hex(s), if pred(s) { 1 } else { 0 });
    }
}

fn gen_case(seed: u64, count: usize, xform: fn(&[u8]) -> Vec<u8>) {
    let mut rng = Rng::new(seed);
    let bs = bodies(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for s in &bs {
        // trailing 1: strupcase/strlowcase/strcapitalize return their str arg.
        let _ = writeln!(w, "{}\t{}\t1", to_hex(s), to_hex(&xform(s)));
    }
}

fn gen_strlcpy(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    // Structured corners: size==0 (nothing written, ret==strlen), size==1 (only
    // the NUL fits), size<len (truncated copy), size==len (last byte dropped for
    // the NUL), size==len+1 (exact fit), size>len (room to spare); empty src.
    let structured: &[(&[u8], usize)] = &[
        (b"", 0),
        (b"", 1),
        (b"", 5),
        (b"hello", 0),
        (b"hello", 1),
        (b"hello", 3),
        (b"hello", 5),
        (b"hello", 6),
        (b"hello", 10),
        (&[0x80u8, b'a', 0xff], 0),
        (&[0x80u8, b'a', 0xff], 2),
        (&[0x80u8, b'a', 0xff], 4),
    ];
    for &(src, size) in structured {
        if done >= count {
            break;
        }
        let (content, ret) = o_strlcpy(src, size);
        let _ = writeln!(w, "{}\t{}\t{}\t{}", to_hex(src), size, to_hex(&content), ret);
        done += 1;
    }
    while done < count {
        let high = rng.below(2) == 1;
        let slen = rng.below(30);
        let src = rand_body(&mut rng, slen, high);
        let size = rng.below(slen + 6);
        let (content, ret) = o_strlcpy(&src, size);
        let _ = writeln!(
            w,
            "{}\t{}\t{}\t{}",
            to_hex(&src),
            size,
            to_hex(&content),
            ret
        );
        done += 1;
    }
}

fn gen_putstr_np(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let bs = bodies(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for s in &bs {
        let esc = o_putstr_np(s);
        // esc is pure ASCII 0x20..=0x7e -> valid UTF-8, no TAB/NL.
        let _ = writeln!(w, "{}\t{}", to_hex(s), String::from_utf8(esc).unwrap());
    }
}

/// ft_print_memory's rendering, with the ADDRESS COLUMN AS AN OFFSET.
///
/// The subject prints the real address of the area, which no reference can
/// know -- so both sides normalise it the same way: row 0 is 0, row 1 is 0x10,
/// and so on. That is exactly what the output layer's `sanitize` already does
/// to this exercise's fixture; this is the same normalisation, applied where
/// the bytes are produced rather than after the fact.
///
/// The layout, from the subject's own example: sixteen bytes a row; the hex in
/// eight groups of two bytes separated by single spaces; then one space; then
/// the printable column, non-printable replaced by a dot. A short final row
/// pads with spaces -- which needs no special case here, because a missing byte
/// simply contributes two spaces where its two hex digits would have gone, and
/// the group separators keep the field at its full width either way.
fn o_print_memory(bytes: &[u8], size: usize) -> String {
    let mut out = String::new();
    if size == 0 {
        return out;
    }
    let n = size.min(bytes.len());
    let mut row = 0usize;
    while row < n {
        // address
        for shift in (0..16).rev() {
            out.push(hexd(((row >> (shift * 4)) & 0xf) as u8) as char);
        }
        out.push(':');
        out.push(' ');
        // hex, eight groups of two bytes
        for g in 0..8 {
            if g != 0 {
                out.push(' ');
            }
            for k in 0..2 {
                let i = row + g * 2 + k;
                if i < n {
                    out.push(hexd(bytes[i] >> 4) as char);
                    out.push(hexd(bytes[i] & 0xf) as char);
                } else {
                    out.push_str("  ");
                }
            }
        }
        out.push(' ');
        // printable column
        let mut i = row;
        while i < n && i < row + 16 {
            let b = bytes[i];
            out.push(if (0x20..=0x7e).contains(&b) { b as char } else { '.' });
            i += 1;
        }
        out.push('\n');
        row += 16;
    }
    out
}

/// The render as ONE corpus field: backslash doubled, newline as \n.
///
/// A record here is one line, and this render is many -- so it has to be
/// escaped rather than embedded. Backslash is escaped FIRST and is not
/// decoration: 0x5c is printable, so it reaches the third column as itself, and
/// without doubling it a literal `\` followed by `n` would decode as a row
/// break that was never there.
fn escape_render(r: &str) -> String {
    let mut out = String::new();
    for c in r.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            _ => out.push(c),
        }
    }
    out
}

fn gen_print_memory(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    // The corners first, so shrinking `count` never drops them: size 0 (the
    // subject says nothing is displayed), sizes either side of a row boundary,
    // and a block of bytes that sit either side of the printable range.
    let mut cases: Vec<(Vec<u8>, usize)> = vec![
        (vec![], 0),
        (b"A".to_vec(), 0),
        (b"A".to_vec(), 1),
        (b"0123456789abcde".to_vec(), 15),
        (b"0123456789abcdef".to_vec(), 16),
        (b"0123456789abcdefg".to_vec(), 17),
        ((0x1cu8..=0x23).collect::<Vec<u8>>(), 8),
        ((0x7bu8..=0x82).collect::<Vec<u8>>(), 8),
        (vec![0u8; 16], 16),
        (vec![0xffu8; 33], 33),
    ];
    while cases.len() < count {
        let len = rng.below(49);
        let body = rand_body(&mut rng, len, true);
        // Ask for at most what was allocated: reading past the block is the
        // student's bug to have, not one this corpus should require.
        let size = if len == 0 { 0 } else { rng.below(len + 1) };
        cases.push((body, size));
    }
    for (body, size) in &cases {
        let _ = writeln!(
            w,
            "{}\t{}\t{}",
            to_hex(body),
            size,
            escape_render(&o_print_memory(body, *size))
        );
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c02_strcpy" => gen_strcpy(seed, count),
        "c02_strncpy" => gen_strncpy(seed, count),
        "c02_str_is_alpha" => gen_pred(seed, count, 0, is_alpha),
        "c02_str_is_numeric" => gen_pred(seed, count, 1, is_numeric),
        "c02_str_is_lowercase" => gen_pred(seed, count, 2, is_lowercase),
        "c02_str_is_uppercase" => gen_pred(seed, count, 3, is_uppercase),
        "c02_str_is_printable" => gen_pred(seed, count, 4, is_printable),
        "c02_strupcase" => gen_case(seed, count, o_strupcase),
        "c02_strlowcase" => gen_case(seed, count, o_strlowcase),
        "c02_strcapitalize" => gen_case(seed, count, o_strcapitalize),
        "c02_strlcpy" => gen_strlcpy(seed, count),
        "c02_putstr_non_printable" => gen_putstr_np(seed, count),
        "c02_print_memory" => gen_print_memory(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- ft_print_memory (ex12) ----
    //
    // The subject's OWN example, byte for byte, taken from the exercise's
    // committed fixture: 92 bytes across six rows, the last of them short. It
    // is the one case where the layout is not this reference's opinion but the
    // subject's printed page, so a renderer that drifted would be caught here
    // rather than by 74 targets going red at once.
    //
    // Addresses are offsets, not the real ones -- see o_print_memory.
    {
        let bytes: &[u8] = b"Bonjour les aminches\x09\x0a\x09c\x07 est fou\x09tout\x09ce qu on peut faire avec\x09\x0a\x09print_memory\x0a\x0a\x0a\x09lol.lol. \x00";
        let want = concat!(
        "0000000000000000: 426f 6e6a 6f75 7220 6c65 7320 616d 696e Bonjour les amin\n",
        "0000000000000010: 6368 6573 090a 0963 0720 6573 7420 666f ches...c. est fo\n",
        "0000000000000020: 7509 746f 7574 0963 6520 7175 206f 6e20 u.tout.ce qu on \n",
        "0000000000000030: 7065 7574 2066 6169 7265 2061 7665 6309 peut faire avec.\n",
        "0000000000000040: 0a09 7072 696e 745f 6d65 6d6f 7279 0a0a ..print_memory..\n",
        "0000000000000050: 0a09 6c6f 6c2e 6c6f 6c2e 2000           ..lol.lol. .\n",
        );
        if o_print_memory(bytes, bytes.len()) != want {
            eprintln!("CHECK FAIL c02 print_memory subject example");
            fails += 1;
        }
        // size 0 displays nothing, which the subject states outright.
        if !o_print_memory(bytes, 0).is_empty() {
            eprintln!("CHECK FAIL c02 print_memory size 0");
            fails += 1;
        }
        // Properties, over the shapes a fixture cannot enumerate: every row is
        // the same width until the last, every row starts at its own offset,
        // and the row count follows the size rather than the block.
        let mut rng = Rng::new(3);
        for _ in 0..300 {
            let len = rng.below(70);
            let body = rand_body(&mut rng, len, true);
            let size = if len == 0 { 0 } else { rng.below(len + 1) };
            let r = o_print_memory(&body, size);
            let lines: Vec<&str> = r.lines().collect();
            if lines.len() != size.div_ceil(16) {
                eprintln!("CHECK FAIL c02 print_memory row count");
                fails += 1;
                break;
            }
            let bad = lines.iter().enumerate().any(|(i, l)| {
                let addr = format!("{:016x}: ", i * 16);
                !l.starts_with(&addr) || l.len() < addr.len() + 39
            });
            if bad {
                eprintln!("CHECK FAIL c02 print_memory row shape");
                fails += 1;
                break;
            }
        }
    }
    macro_rules! want {
        ($cond:expr, $msg:expr) => {
            if !($cond) {
                eprintln!("CHECK FAIL c02 {}", $msg);
                fails += 1;
            }
        };
    }

    // ---- strncpy hand cases (NUL-padding to n) ----
    want!(o_strncpy(b"abc", 5) == b"abc\0\0", "strncpy pad");
    want!(o_strncpy(b"abcdef", 3) == b"abc", "strncpy trunc");
    want!(o_strncpy(b"", 2) == b"\0\0", "strncpy empty");
    want!(o_strncpy(b"abc", 0) == b"", "strncpy zero");

    // ---- predicates (empty string is TRUE) ----
    want!(is_alpha(b""), "is_alpha empty");
    want!(is_alpha(b"abcXYZ") && !is_alpha(b"abc1") && !is_alpha(b"a b"), "is_alpha");
    want!(is_numeric(b"") && is_numeric(b"0129") && !is_numeric(b"12a"), "is_numeric");
    want!(is_lowercase(b"") && is_lowercase(b"abz") && !is_lowercase(b"abZ"), "is_lowercase");
    want!(is_uppercase(b"") && is_uppercase(b"ABZ") && !is_uppercase(b"ABz"), "is_uppercase");
    want!(is_printable(b"") && is_printable(b" ~") && !is_printable(&[0x1f]) && !is_printable(&[0x7f]), "is_printable");
    // boundary bytes around the letter ranges must classify as non-alpha
    for &b in &[b'@', b'[', b'`', b'{'] {
        want!(!is_alpha(&[b]), "is_alpha boundary");
    }

    // ---- case transforms ----
    want!(o_strupcase(b"aBc-9 z") == b"ABC-9 Z".to_vec(), "strupcase");
    want!(o_strlowcase(b"AbC-9 Z") == b"abc-9 z".to_vec(), "strlowcase");
    want!(o_strupcase(&[0x80, b'a', 0xff]) == vec![0x80, b'A', 0xff], "strupcase high");

    // ---- strcapitalize documented example ----
    want!(
        o_strcapitalize(b"salut, comment tu vas ? 42mots quarante-deux; cinquante+et+un")
            == b"Salut, Comment Tu Vas ? 42mots Quarante-Deux; Cinquante+Et+Un".to_vec(),
        "strcapitalize example"
    );
    want!(o_strcapitalize(b"HELLO") == b"Hello".to_vec(), "strcapitalize allcaps");
    want!(o_strcapitalize(b"") == b"".to_vec(), "strcapitalize empty");

    // ---- strlcpy hand cases (ret == strlen(src)) ----
    want!(o_strlcpy(b"hello", 3) == (b"he".to_vec(), 5), "strlcpy trunc");
    want!(o_strlcpy(b"hi", 10) == (b"hi".to_vec(), 2), "strlcpy fits");
    want!(o_strlcpy(b"hi", 0) == (b"".to_vec(), 2), "strlcpy size0");
    want!(o_strlcpy(b"hi", 1) == (b"".to_vec(), 2), "strlcpy size1");
    want!(o_strlcpy(b"", 5) == (b"".to_vec(), 0), "strlcpy emptysrc");

    // ---- putstr_non_printable hand cases ----
    want!(o_putstr_np(b" ~") == b" ~".to_vec(), "putstr printable");
    want!(o_putstr_np(b"a\\b") == b"a\\b".to_vec(), "putstr backslash");
    want!(o_putstr_np(b"A\nB") == b"A\\0aB".to_vec(), "putstr newline");
    want!(o_putstr_np(&[0x7f]) == b"\\7f".to_vec(), "putstr del");
    want!(o_putstr_np(&[0x00, 0xff]) == b"\\00\\ff".to_vec(), "putstr nul/high");

    // ---- seeded property assertions ----
    let mut rng = Rng::new(11);
    for _ in 0..20000 {
        let len = rng.below(20);
        let s = rand_body(&mut rng, len, true);

        // strncpy: exactly n bytes; prefix matches min(n,len); tail is 0.
        let n = rng.below(len + 5);
        let d = o_strncpy(&s, n);
        want!(d.len() == n, "prop strncpy len");
        let k = n.min(s.len());
        want!(d[..k] == s[..k], "prop strncpy prefix");
        want!(d[k..].iter().all(|&b| b == 0), "prop strncpy pad");

        // case transforms: length preserved, involutive across up/low on letters,
        // and alnum-ness preserved.
        let up = o_strupcase(&s);
        let lo = o_strlowcase(&s);
        want!(up.len() == s.len() && lo.len() == s.len(), "prop case len");
        want!(o_strlowcase(&up) == o_strlowcase(&s), "prop up-then-low");
        want!(o_strupcase(&lo) == o_strupcase(&s), "prop low-then-up");

        // strcapitalize: idempotent, length preserved, alnum positions unchanged.
        let cap = o_strcapitalize(&s);
        want!(cap.len() == s.len(), "prop cap len");
        want!(o_strcapitalize(&cap) == cap, "prop cap idempotent");
        for (a, b) in s.iter().zip(cap.iter()) {
            want!(is_alnum(*a) == is_alnum(*b), "prop cap alnum");
            want!(a.to_ascii_lowercase() == b.to_ascii_lowercase(), "prop cap sameletter");
        }

        // strlcpy: ret == strlen(src); content is a prefix of src bounded by size-1.
        let size = rng.below(len + 5);
        let (content, ret) = o_strlcpy(&s, size);
        want!(ret == s.len() as u64, "prop strlcpy ret");
        if size > 0 {
            want!(content.len() == s.len().min(size - 1), "prop strlcpy contentlen");
        } else {
            want!(content.is_empty(), "prop strlcpy size0");
        }
        want!(content == s[..content.len()], "prop strlcpy prefix");

        // putstr: printable bytes survive 1:1, others expand to 3 (backslash+hex),
        // and the escaped stream is itself all-printable.
        let esc = o_putstr_np(&s);
        let expect_len: usize = s
            .iter()
            .map(|&b| if (0x20..=0x7e).contains(&b) { 1 } else { 3 })
            .sum();
        want!(esc.len() == expect_len, "prop putstr len");
        want!(esc.iter().all(|&b| (0x20..=0x7e).contains(&b)), "prop putstr allprintable");
    }
    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "c02_strcpy" | "c02_strncpy" | "c02_str_is_alpha" | "c02_str_is_numeric"
        | "c02_str_is_lowercase" | "c02_str_is_uppercase" | "c02_str_is_printable"
        | "c02_strupcase" | "c02_strlowcase" | "c02_strcapitalize" | "c02_strlcpy"
        | "c02_putstr_non_printable") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        let a = unhex(f[0]);
        match name {
            "c02_strcpy" => sink(o_strcpy(&a)),
            "c02_strncpy" => { if f.len() >= 2 { if let Ok(n) = f[1].parse::<usize>() { sink(o_strncpy(&a, n)); } } }
            "c02_strupcase" => sink(o_strupcase(&a)),
            "c02_strlowcase" => sink(o_strlowcase(&a)),
            "c02_strcapitalize" => sink(o_strcapitalize(&a)),
            "c02_strlcpy" => { if f.len() >= 2 { if let Ok(n) = f[1].parse::<usize>() { sink(o_strlcpy(&a, n)); } } }
            "c02_putstr_non_printable" => sink(o_putstr_np(&a)),
            _ => sink(a.iter().all(|&c| c != 0)),
        }
    }
    true
}
