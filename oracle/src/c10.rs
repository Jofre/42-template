//! c-piscine-c-10 — the file module.
//!
//! Four programs, all of which read FILES and write bytes. One corpus shape
//! serves all four: a list of flags, a list of file contents, and the bytes the
//! program must produce.
//!
//! WHY A DIFFERENTIAL LAYER HERE, given that each exercise already has
//! hand-written cases with fixtures. The subject's own words are the reason:
//!
//!   "You must complete this exercise by declaring a fixed-size array."
//!
//! Every one of these programs is a READ LOOP around a buffer, and a read loop
//! is wrong at exactly the sizes nobody writes a fixture for. `read()` may
//! return short; the file may be a whole number of buffers, or one byte more,
//! or one byte less; the last buffer may be empty. A fixture of "sample.txt"
//! exercises one length. The corpus below walks every boundary around the
//! buffer sizes people actually choose -- 1, 2, 4, 8, 16, 32, 64, 128, 512,
//! 1024, 4096 and the ~30 000 ex01's subject names -- at each one testing
//! size-1, size and size+1.
//!
//! It also carries content a text fixture cannot: NUL bytes, 0xff, a file with
//! no trailing newline, and a file that is one enormous line. A program that
//! treats its buffer as a C string stops at the first NUL, and a text fixture
//! never contains one.
//!
//! WHAT IS DELIBERATELY NOT GENERATED, IN EITHER DIRECTION:
//!
//!   * ERROR MESSAGES for ex01, ex02 and ex03. Those three are specified as
//!     "the same function as the system's tool", and their allowed list adds
//!     strerror and basename -- but no line of the subject fixes the message
//!     FORMAT, and the system tools do not agree with each other either. ex00
//!     is the exception: its three messages are quoted in the subject, so its
//!     hand-written cases assert them and this corpus does not need to.
//!   * ft_tail with MORE THAN ONE file, which prints `==> path <==` headers.
//!     The header holds the path the runner happened to write the fixture to,
//!     so the expected bytes could not be generated ahead of time without
//!     fixing that path -- and a corpus that fixes a path is a corpus that
//!     tests the runner. ft_cat's multi-file case has no header and is here.
//!   * ft_tail's `+` and `-` signs, which the subject explicitly excludes, and
//!     any option other than `-c` for tail and `-C` for hexdump, which it
//!     limits itself to in the same sentence.
//!   * EXIT STATUS and stderr on every path. The subject pins neither.
//!   * hexdump WITHOUT -C, which is a different format the subject does not ask
//!     for.

use crate::common::{esc_posix, Rng};

/// `<tag>\t<nflags>\t<flag>...\t<nfiles>\t<file>...\t<escaped-expected>`
///
/// Every field is POSIX-escaped (`\n`, `\t`, `\\`, `\0NNN` octal), which is
/// what lets a file's contents -- newlines, tabs and NULs included -- travel on
/// one line. Octal and not `\xHH`: the consumer is dash, whose `printf %b`
/// decodes `\0NNN` and prints `\xHH` back literally.
///
/// The two counts are in the line so a reader peels exactly the right number of
/// fields rather than guessing which tab ends which list.
fn line(tag: &str, flags: &[&str], files: &[Vec<u8>], expected: &[u8]) -> String {
    let mut s = String::from(tag);
    s.push('\t');
    s.push_str(&flags.len().to_string());
    for f in flags {
        s.push('\t');
        s.push_str(&esc_posix(f.as_bytes()));
    }
    s.push('\t');
    s.push_str(&files.len().to_string());
    for f in files {
        s.push('\t');
        s.push_str(&esc_posix(f));
    }
    s.push('\t');
    s.push_str(&esc_posix(expected));
    s
}

/// The last `n` bytes, or all of them when the file is shorter. `tail -c`.
fn o_tail(data: &[u8], n: usize) -> Vec<u8> {
    if n >= data.len() {
        return data.to_vec();
    }
    data[data.len() - n..].to_vec()
}

/// `hexdump -C`, byte for byte.
///
/// Derived from the tool itself rather than from memory, and every rule below
/// was checked against it while this was written:
///
///   * An EMPTY file produces NOTHING AT ALL -- not even the final offset line.
///   * A line is `%08x`, two spaces, then sixteen `%02x ` fields with ONE EXTRA
///     space after the eighth, padded with spaces to a fixed width, then the
///     sixteen bytes again between `|` as printable characters (0x20..=0x7e) or
///     `.`.
///   * The hex area is 50 columns whatever the line holds -- sixteen `%02x `
///     fields (48), the extra space after the eighth, and ONE MORE before the
///     `|` -- which is what keeps the `|` at column 60 on a short final line.
///     Counted from the tool's own output rather than reasoned about: the
///     first version of this made it 49 and every line was one column short.
///   * CONSECUTIVE identical 16-byte lines collapse: the first prints, every
///     repeat after it is replaced by a single `*` line, and the next different
///     line prints at its REAL offset. Two identical lines with a different one
///     between them do not collapse.
///   * The last line is the total size as `%08x` and nothing else.
///
/// The squeeze is the half a hand-written fixture never reaches, because it
/// needs sixteen identical bytes twice over -- and a file of NUL bytes, which
/// is exactly what a fixed-size array printed past the end of the data looks
/// like.
fn o_hexdump(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    if data.is_empty() {
        return out;
    }
    let mut squeezing = false;
    let mut prev: Option<&[u8]> = None;
    let mut off = 0usize;
    while off < data.len() {
        let end = (off + 16).min(data.len());
        let chunk = &data[off..end];
        // Only a FULL line can be squeezed: the last, short line is never
        // equal to a full one, so this cannot swallow the end of the file.
        if chunk.len() == 16 && prev == Some(chunk) {
            if !squeezing {
                out.extend_from_slice(b"*\n");
                squeezing = true;
            }
            off = end;
            continue;
        }
        squeezing = false;
        prev = Some(chunk);
        out.extend_from_slice(format!("{:08x}  ", off).as_bytes());
        let mut col = 0;
        for (i, b) in chunk.iter().enumerate() {
            out.extend_from_slice(format!("{:02x} ", b).as_bytes());
            col += 3;
            if i == 7 {
                out.push(b' ');
                col += 1;
            }
        }
        while col < 50 {
            out.push(b' ');
            col += 1;
        }
        out.push(b'|');
        for b in chunk {
            out.push(if (0x20..=0x7e).contains(b) { *b } else { b'.' });
        }
        out.extend_from_slice(b"|\n");
        off = end;
    }
    out.extend_from_slice(format!("{:08x}\n", data.len()).as_bytes());
    out
}

/// The lengths a read loop is wrong at.
///
/// Every plausible buffer size, and around each of them size-1, size and
/// size+1. 30 000 is in the list because ex01's subject names it: "slightly
/// less than 30 ko". The three largest are the only ones over 8 KiB, and they
/// appear once each rather than per-arm: a corpus is replayed by a fork and an
/// exec per case, so its total size is wall-clock.
fn boundary_lengths() -> Vec<usize> {
    let mut v = vec![0usize, 1, 2, 3];
    for base in [4usize, 8, 16, 32, 64, 128, 256, 512, 1024, 4096] {
        v.push(base - 1);
        v.push(base);
        v.push(base + 1);
    }
    v.push(29999);
    v.push(30000);
    v.push(30001);
    v
}

/// Content that is not text.
///
/// `kind` picks the shape rather than the bytes being uniformly random,
/// because the shapes are what the exercises get wrong: a run of identical
/// bytes is hexdump's squeeze, a NUL early on is every program that treats the
/// buffer as a string, and a file with no trailing newline is the one every
/// hand-written fixture has.
fn body(rng: &mut Rng, len: usize, kind: usize) -> Vec<u8> {
    match kind % 6 {
        // Plain text with newlines: the ordinary case, still at odd lengths.
        0 => (0..len)
            .map(|i| if i % 17 == 16 { b'\n' } else { b'a' + (i % 26) as u8 })
            .collect(),
        // All one byte: hexdump squeezes this, and nothing else in the corpus
        // makes it do so.
        1 => vec![0x00; len],
        2 => vec![0xff; len],
        // A NUL early, then text. A program using str* functions stops here.
        3 => (0..len).map(|i| if i == len / 3 { 0 } else { b'x' }).collect(),
        // One enormous line: no newline anywhere, including at the end.
        4 => vec![b'Z'; len],
        // Uniformly random bytes, so nothing above is load-bearing on its own.
        _ => (0..len).map(|_| rng.below(256) as u8).collect(),
    }
}

/// One case per boundary length, cycling through the content shapes.
fn file_corpus(rng: &mut Rng, count: usize) -> Vec<Vec<u8>> {
    let lens = boundary_lengths();
    let mut out = Vec::new();
    let mut i = 0;
    while out.len() < count {
        let len = lens[i % lens.len()];
        // Past one full pass over the lengths, the big ones are dropped: they
        // dominate the corpus's size and the boundary they test has already
        // been tested once.
        if i >= lens.len() && len > 8192 {
            i += 1;
            continue;
        }
        out.push(body(rng, len, i / lens.len() + i));
        i += 1;
    }
    out
}

pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    let mut rng = Rng::new(seed);
    match name {
        // ex00: one file in, its bytes out.
        "c10_display_file" => {
            for f in file_corpus(&mut rng, count) {
                let e = f.clone();
                println!("{}", line("file", &[], &[f], &e));
            }
        }
        // ex01: one to three files, concatenated. No headers, so the expected
        // bytes do not depend on where the runner wrote them.
        "c10_cat" => {
            let pool = file_corpus(&mut rng, count);
            let mut i = 0;
            while i < pool.len() {
                let n = 1 + (i % 3);
                let group: Vec<Vec<u8>> = pool[i..(i + n).min(pool.len())].to_vec();
                let mut e = Vec::new();
                for f in &group {
                    e.extend_from_slice(f);
                }
                println!("{}", line("files", &[], &group, &e));
                i += n;
            }
        }
        // ex02: `-c N` on one file. N walks the same boundaries as the length,
        // so "exactly the file", "one more" and "one less" all appear.
        "c10_tail" => {
            let lens = boundary_lengths();
            for (i, f) in file_corpus(&mut rng, count).into_iter().enumerate() {
                let n = match i % 5 {
                    0 => 0,
                    1 => 1,
                    2 => f.len(),
                    3 => f.len() + 1,
                    _ => lens[i % lens.len()].min(f.len() + 7),
                };
                let e = o_tail(&f, n);
                println!("{}", line("tail", &["-c", &n.to_string()], &[f], &e));
            }
        }
        // ex03: `-C` on one file.
        "c10_hexdump" => {
            for f in file_corpus(&mut rng, count) {
                let e = o_hexdump(&f);
                println!("{}", line("hexdump", &["-C"], &[f], &e));
            }
        }
        _ => return false,
    }
    true
}

// ---------------------------------------------------------------------------
// Self-check.

pub fn check() -> usize {
    let mut fails = 0;

    // ---- hexdump, against transcripts taken from the tool ITSELF.
    //
    // These three literals were generated from `hexdump -C`'s real output and
    // pasted, not typed: the whole content of this format is which column
    // things land in, and a hand-counted literal asserts the counting rather
    // than the format.
    if !o_hexdump(b"").is_empty() {
        eprintln!("c10: hexdump of an empty file must print nothing at all");
        fails += 1;
    }
    let want_a = "00000000  41                                                |A|\n00000001\n";
    if o_hexdump(b"A") != want_a.as_bytes() {
        eprintln!("c10: hexdump of one byte does not match the tool");
        fails += 1;
    }
    let want_hw = "00000000  48 65 6c 6c 6f 20 77 6f  72 6c 64 21 0a           |Hello world!.|\n0000000d\n";
    if o_hexdump(b"Hello world!\n") != want_hw.as_bytes() {
        eprintln!("c10: hexdump of the 13-byte example does not match the tool");
        fails += 1;
    }
    let mut sq = vec![0u8; 48];
    sq.push(b'A');
    let want_sq = "00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|\n*\n00000030  41                                                |A|\n00000031\n";
    if o_hexdump(&sq) != want_sq.as_bytes() {
        eprintln!("c10: hexdump did not squeeze three identical lines into one *");
        fails += 1;
    }

    // A repeat with a DIFFERENT line between must not collapse.
    let mut ab = vec![b'A'; 16];
    ab.extend_from_slice(&[b'B'; 16]);
    ab.extend_from_slice(&[b'A'; 16]);
    let hd = String::from_utf8_lossy(&o_hexdump(&ab)).to_string();
    if hd.contains('*') {
        eprintln!("c10: hexdump squeezed two identical lines that are not consecutive");
        fails += 1;
    }
    if hd.lines().count() != 4 {
        eprintln!("c10: hexdump of three distinct lines is not three lines and an offset");
        fails += 1;
    }

    // STRUCTURAL properties, checked without re-deriving the format: for every
    // corpus file, each hex line's `|` sits in the same column, and the last
    // line is the size.
    let mut rng = Rng::new(5);
    for f in file_corpus(&mut rng, 60) {
        let out = o_hexdump(&f);
        if f.is_empty() {
            if !out.is_empty() {
                eprintln!("c10: hexdump printed something for an empty file");
                fails += 1;
            }
            continue;
        }
        let text = String::from_utf8_lossy(&out).to_string();
        let lines: Vec<&str> = text.lines().collect();
        if lines.last() != Some(&format!("{:08x}", f.len()).as_str()) {
            eprintln!("c10: hexdump's last line is not the file size");
            fails += 1;
        }
        for l in &lines[..lines.len() - 1] {
            if *l == "*" {
                continue;
            }
            match l.find('|') {
                Some(60) => {}
                _ => {
                    eprintln!("c10: a hexdump line's | is not in column 60");
                    fails += 1;
                    break;
                }
            }
            if !l.ends_with('|') {
                eprintln!("c10: a hexdump line does not end with |");
                fails += 1;
                break;
            }
        }
    }

    // ---- tail, against properties rather than against o_tail itself.
    let mut rng = Rng::new(9);
    for f in file_corpus(&mut rng, 60) {
        for n in [0, 1, 7, f.len(), f.len() + 1, f.len() / 2] {
            let t = o_tail(&f, n);
            if t.len() != n.min(f.len()) {
                eprintln!("c10: tail -c {} returned {} bytes", n, t.len());
                fails += 1;
                break;
            }
            // It is a SUFFIX: the bytes are the end of the file, in order.
            if f[f.len() - t.len()..] != t[..] {
                eprintln!("c10: tail -c did not return a suffix");
                fails += 1;
                break;
            }
        }
    }
    if o_tail(b"abcdefghij", 3) != b"hij" {
        eprintln!("c10: tail -c 3 of abcdefghij is not hij");
        fails += 1;
    }
    if !o_tail(b"abc", 0).is_empty() {
        eprintln!("c10: tail -c 0 must print nothing");
        fails += 1;
    }

    // ---- the corpus itself must contain what it claims to.
    let mut rng = Rng::new(3);
    let corp = file_corpus(&mut rng, 90);
    if !corp.iter().any(|f| f.is_empty()) {
        eprintln!("c10: no empty file in the corpus");
        fails += 1;
    }
    if !corp.iter().any(|f| f.contains(&0)) {
        eprintln!("c10: no file with a NUL byte -- a program using str* would pass");
        fails += 1;
    }
    if !corp.iter().any(|f| !f.is_empty() && *f.last().unwrap() != b'\n') {
        eprintln!("c10: every file ends in a newline, which no real corpus does");
        fails += 1;
    }
    if !corp.iter().any(|f| f.len() > 4096) {
        eprintln!("c10: no file larger than one common buffer size");
        fails += 1;
    }
    // The squeeze needs a file with two identical consecutive 16-byte lines.
    if !corp
        .iter()
        .any(|f| f.len() >= 32 && f[..16] == f[16..32])
    {
        eprintln!("c10: no file that makes hexdump squeeze");
        fails += 1;
    }

    // ---- the escape, end to end. A corpus is only as good as the encoding
    // that carries it, and these files hold every byte there is.
    let mut rng = Rng::new(23);
    for f in file_corpus(&mut rng, 40) {
        if crate::common::unesc_posix(&esc_posix(&f)) != f {
            eprintln!("c10: a file did not survive the escape round-trip");
            fails += 1;
            break;
        }
    }
    // ...and it must be OCTAL, asserted on the encoder rather than by scanning
    // its output for "\\x". That scan is wrong and this corpus proved it: a file
    // containing the two bytes `\\` and `x` escapes to `\\\\x`, whose substring is
    // `\\x` -- a false alarm on data that round-trips perfectly. What actually
    // matters is what the encoder does with a byte it cannot print, and dash's
    // `printf %b` decodes \\0NNN while printing \\xHH back literally.
    //
    // `\\0033`, with the leading zero: the form is `\\0` followed by THREE octal
    // digits, so 0x1b is 0o33 written as 033. That is what dash's `printf %b`
    // reads -- `\\0` then up to three digits -- and writing `\\033` here instead
    // is what this assertion caught in its own first draft.
    if esc_posix(&[0x1b]) != "\\0033" || esc_posix(&[0xff]) != "\\0377" {
        eprintln!("c10: esc_posix does not emit \\0NNN octal for a non-printable byte");
        fails += 1;
    }

    fails
}
