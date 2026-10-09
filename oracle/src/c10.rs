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
//!   * ERROR PATHS. Every message names the path it was given, and the path is
//!     chosen by the runner at run time, so a corpus that carried one would be
//!     testing the runner. The named cases hold them instead, with fixed
//!     names, and their expected files come from the model below (`c10_run`):
//!     ex00's three messages, which its subject quotes, at basic; the tools'
//!     own wording and exit status for ex01-ex03, which "performs the same
//!     function as the system's" tool is READ as asking for, at strict. The
//!     corpus's inputs are all valid, so its expected stderr is empty, which
//!     the runner checks where the call site says why (file_check.sh
//!     --stderr-empty).
//!   * ft_tail with MORE THAN ONE file, which prints `==> path <==` headers,
//!     for the same reason. ft_cat's and ft_hexdump's groups print no path
//!     and are here: several files are one stream to both.
//!   * ft_tail's `+` and `-` signs, which the subject explicitly excludes, and
//!     any option other than `-c` for tail and `-C` for hexdump, which it
//!     limits itself to in the same sentence. tail's attached `-cN` is one
//!     named case, at strict: the subject names the option, not its form.
//!   * hexdump WITHOUT -C. The model renders it (`o_hexdump_default`) for the
//!     named cases, which test both formats; the corpus is about read loops,
//!     and the format does not change them.

use crate::common::{esc_posix, Rng};
use std::io::{Read, Write};

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
///   * SEVERAL FILES are one stream: the dump of their concatenation. A line
///     can hold the end of one file and the start of the next, the offsets
///     carry on, and a run of identical lines collapses across the boundary.
///     Checked against the tool's own transcripts below (`check`).
///
/// The squeeze is the half a hand-written fixture never reaches, because it
/// needs sixteen identical bytes twice over -- and a file of NUL bytes, which
/// is exactly what a fixed-size array printed past the end of the data looks
/// like.
fn o_hexdump(data: &[u8]) -> Vec<u8> {
    o_dump(data, true)
}

/// `hexdump` with no option: the same lines and the same squeeze, in the
/// tool's default format. Not generated into the corpus -- the subject names
/// -C as the one option to handle, and the corpus is about read loops, which
/// the format does not change -- but it is what the named cases' default-format
/// fixtures are made from (`run_cmd`). Checked against the tool's transcripts
/// in `check`:
///
///   * a line is `%07x`, then eight fields: ` %04x` for each two bytes read as
///     one little-endian 16-bit number (a last odd byte is the low half of a
///     number whose high half is 0), and five spaces for each field the line
///     does not reach;
///   * the last line is the total size as `%07x`.
fn o_hexdump_default(data: &[u8]) -> Vec<u8> {
    o_dump(data, false)
}

/// The line loop both formats share: which 16-byte lines print, which
/// collapse into `*`, and the closing offset.
fn o_dump(data: &[u8], canonical: bool) -> Vec<u8> {
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
        if canonical {
            canonical_line(&mut out, off, chunk);
        } else {
            default_line(&mut out, off, chunk);
        }
        off = end;
    }
    if canonical {
        out.extend_from_slice(format!("{:08x}\n", data.len()).as_bytes());
    } else {
        out.extend_from_slice(format!("{:07x}\n", data.len()).as_bytes());
    }
    out
}

fn canonical_line(out: &mut Vec<u8>, off: usize, chunk: &[u8]) {
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
}

fn default_line(out: &mut Vec<u8>, off: usize, chunk: &[u8]) {
    out.extend_from_slice(format!("{:07x}", off).as_bytes());
    for u in 0..8 {
        let lo = 2 * u;
        if lo < chunk.len() {
            let hi = chunk.get(lo + 1).copied().unwrap_or(0) as u16;
            out.extend_from_slice(format!(" {:04x}", (hi << 8) | chunk[lo] as u16).as_bytes());
        } else {
            out.extend_from_slice(b"     ");
        }
    }
    out.push(b'\n');
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

/// The pool cut into groups of one, two and three consecutive files, in turn,
/// so every group size appears and the boundary lengths meet each other at
/// every place in a group.
fn groups(pool: &[Vec<u8>]) -> Vec<Vec<Vec<u8>>> {
    let mut out = Vec::new();
    let mut i = 0;
    let mut k = 0;
    while i < pool.len() {
        let n = 1 + k % 3;
        out.push(pool[i..(i + n).min(pool.len())].to_vec());
        i += n;
        k += 1;
    }
    out
}

/// The groups a stream of several files is wrong at, which consecutive pool
/// files reach only by chance: a run of identical lines that starts in one
/// file and ends in the next (the `*` must carry across, and the next line
/// print at its real offset), a file ending exactly on a line boundary with
/// the run carrying on into the next, and a line made of the ends of three
/// files. A program that dumps each file on its own -- offsets from zero
/// again, a short line flushed at every file's end, the squeeze forgotten
/// between files -- differs from the tool on each.
fn stream_groups() -> Vec<Vec<Vec<u8>>> {
    let mut end = vec![0u8; 44];
    end.extend_from_slice(b"end");
    vec![
        vec![vec![0u8; 20], end],
        vec![vec![b'A'; 16], vec![b'A'; 16], b"B".to_vec()],
        vec![b"0123456789abc".to_vec(), b"de".to_vec(), b"fghij\n".to_vec()],
        vec![Vec::new(), vec![0xffu8; 33]],
    ]
}

/// The bytes of a group, as the one stream the tools read it as.
fn concat(group: &[Vec<u8>]) -> Vec<u8> {
    let mut e = Vec::new();
    for f in group {
        e.extend_from_slice(f);
    }
    e
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
            for group in groups(&file_corpus(&mut rng, count)) {
                let e = concat(&group);
                println!("{}", line("files", &[], &group, &e));
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
        // ex03: `-C` on one to three files, dumped as one stream: `count`
        // files cut into groups (`groups`), then the shapes only a stream
        // has (`stream_groups`). hexdump prints no path, so unlike tail's a
        // group's expected bytes do not depend on where the runner wrote it.
        "c10_hexdump" => {
            let mut all = groups(&file_corpus(&mut rng, count));
            all.extend(stream_groups());
            for group in all {
                let e = o_hexdump(&concat(&group));
                println!("{}", line("hexdump", &["-C"], &group, &e));
            }
        }
        _ => return false,
    }
    true
}

// ---------------------------------------------------------------------------
// THE MODEL: the four programs run on real paths, for the named cases.
//
//   oracle c10_run [--prog NAME] display_file|cat|tail|hexdump ARG...
//
// Reads the paths and stdin the way the pinned tool does and answers with
// the tool's three results: its standard output on stdout, its standard error
// on stderr, and its exit status as its own. NAME stands for the program's
// name in the messages, and defaults to the tool's. c-10's BUILD file reads
// that name as basename(argv[0]), which c-10 allows, and passes exNN_bin: the
// runner starts the student's program by a path ending in it. (GNU cat and
// tail print argv[0] whole; util-linux's hexdump prints its basename. Run as
// a bare NAME, the three agree with the model.)
//
// This is where the named cases' expected files come from (c-10's BUILD file,
// Reloaded's ex27), so that no fixture is typed by hand or cut by running a
// system tool: the model was cross-checked against the tools the exercises
// imitate -- GNU coreutils 8.32's cat and tail, util-linux 2.37.2's hexdump --
// on every path below, and `check` holds it to their pasted transcripts.
//
// What each tool does on its error paths, measured:
//
//   cat      an operand that will not open, or will not read (a directory):
//            `NAME: FILE: <strerror>`, the next operand still copied, exit 1.
//            `-`, or no operand, is standard input.
//   tail     -c N and -cN alike. With several operands, a `==> FILE <==`
//            header before each one that opened (`standard input` for `-`),
//            with a blank line before every header but the first printed.
//            An operand that will not open: `NAME: cannot open 'FILE' for
//            reading: <strerror>`, no header, the next one still read, exit
//            1. One that opens and will not read (a directory): its header,
//            then `NAME: error reading 'FILE': <strerror>`, exit 1. What
//            happens NEXT is the filesystem's, not tail's: tail -c asks the
//            directory where its end is (lseek SEEK_END). Where that answers
//            (ext4, or an overlayfs folder only its upper layer holds) it
//            reads from there, fails inside a die(), and reads no further
//            operand; where it does not (tmpfs, 9p, a merged overlayfs
//            folder) it reads the directory like a pipe, fails, and goes on
//            to the next operand. Both measured with coreutils 8.32 on this
//            machine, one folder apart. So the model answers a directory
//            only as the LAST operand, where both endings print the same,
//            and refuses (exit 2) one with operands after it: no case can
//            ask a student to copy either. -c 0 opens nothing at all: no
//            output, no message, exit 0, whatever the operands.
//   hexdump  the operands are one stream (`o_dump`). One that will not open:
//            `NAME: FILE: <strerror>`, exit 1; when not one opened, also
//            `NAME: all input file arguments failed`. One that opens and will
//            not read (a directory): the same message, and exit 0 -- measured,
//            and read by no case. `-` is a file name, not standard input.
//   display_file  the subject's own three messages, on standard error. Its
//            exit status is not the subject's (it names none) and no case
//            reads it.


struct Run {
    out: Vec<u8>,
    err: Vec<u8>,
    status: i32,
    /// Why the model has no answer for this run, when the tool's own answer
    /// depends on something other than its arguments (tail after a
    /// directory): `c10_run` then says so and exits 2, and nothing is printed.
    no_answer: Option<String>,
}

/// Why reading an operand failed: at open(), or at read() after it opened.
enum Failed {
    Open(i32),
    Read(i32),
}

/// glibc's strerror() text for the errno values these paths reach. Anything
/// else stops the model (exit 2) rather than inventing a message.
fn strerror(errno: i32) -> &'static str {
    match errno {
        2 => "No such file or directory",
        13 => "Permission denied",
        20 => "Not a directory",
        21 => "Is a directory",
        _ => {
            eprintln!("oracle c10_run: no message known for errno {}", errno);
            std::process::exit(2);
        }
    }
}

fn slurp(path: &str) -> Result<Vec<u8>, Failed> {
    let mut f = std::fs::File::open(path).map_err(|e| Failed::Open(e.raw_os_error().unwrap_or(0)))?;
    let mut v = Vec::new();
    f.read_to_end(&mut v).map_err(|e| Failed::Read(e.raw_os_error().unwrap_or(0)))?;
    Ok(v)
}

/// Standard input, read whole the first time and at its end every time after:
/// a second `-` reads what the first left, which is nothing.
fn stdin_once(taken: &mut bool) -> Vec<u8> {
    let mut v = Vec::new();
    if !*taken {
        *taken = true;
        let _ = std::io::stdin().read_to_end(&mut v);
    }
    v
}

/// A file name as GNU tail quotes it in a message. Its quoting depends on the
/// characters in the name, so the model takes only names it quotes plainly.
fn quoted(name: &str) -> String {
    if name.is_empty() || !name.bytes().all(|b| b.is_ascii_alphanumeric() || b"._/-+".contains(&b)) {
        eprintln!("oracle c10_run: a name tail would quote in another way: {:?}", name);
        std::process::exit(2);
    }
    format!("'{}'", name)
}

fn m_display_file(args: &[String]) -> Run {
    let mut r = Run { out: Vec::new(), err: Vec::new(), status: 0, no_answer: None };
    let msg = match args.len() {
        0 => Some("File name missing.\n"),
        1 => match slurp(&args[0]) {
            Ok(b) => {
                r.out = b;
                None
            }
            Err(_) => Some("Cannot read file.\n"),
        },
        _ => Some("Too many arguments.\n"),
    };
    if let Some(m) = msg {
        r.err.extend_from_slice(m.as_bytes());
        r.status = 1;
    }
    r
}

fn m_cat(prog: &str, args: &[String]) -> Run {
    let mut r = Run { out: Vec::new(), err: Vec::new(), status: 0, no_answer: None };
    let mut taken = false;
    let stdin_only = vec!["-".to_string()];
    for f in if args.is_empty() { &stdin_only[..] } else { args } {
        if f == "-" {
            r.out.extend(stdin_once(&mut taken));
            continue;
        }
        match slurp(f) {
            Ok(b) => r.out.extend(b),
            Err(Failed::Open(e)) | Err(Failed::Read(e)) => {
                r.err.extend_from_slice(format!("{}: {}: {}\n", prog, f, strerror(e)).as_bytes());
                r.status = 1;
            }
        }
    }
    r
}

fn m_tail(prog: &str, args: &[String]) -> Run {
    let mut r = Run { out: Vec::new(), err: Vec::new(), status: 0, no_answer: None };
    let mut n: Option<usize> = None;
    let mut ops: Vec<String> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        let count = if a == "-c" {
            i += 1;
            args.get(i).cloned()
        } else if let Some(v) = a.strip_prefix("-c") {
            Some(v.to_string())
        } else {
            ops.push(a.clone());
            None
        };
        if a.starts_with("-c") {
            match count.as_deref().and_then(|v| v.parse::<usize>().ok()) {
                Some(v) => n = Some(v),
                None => {
                    eprintln!("oracle c10_run: tail -c needs a count, as every c-10 case gives one");
                    std::process::exit(2);
                }
            }
        }
        i += 1;
    }
    let n = match n {
        Some(v) => v,
        None => {
            eprintln!("oracle c10_run: tail without -c: \"All tests will be conducted using the -c option.\"");
            std::process::exit(2);
        }
    };
    if n == 0 {
        return r;
    }
    if ops.is_empty() {
        ops.push("-".to_string());
    }
    let headers = ops.len() > 1;
    let mut printed = false;
    let mut taken = false;
    for (at, f) in ops.iter().enumerate() {
        let (name, got) = if f == "-" {
            ("standard input".to_string(), Ok(stdin_once(&mut taken)))
        } else {
            (f.clone(), slurp(f))
        };
        if let Err(Failed::Open(e)) = got {
            r.err.extend_from_slice(
                format!("{}: cannot open {} for reading: {}\n", prog, quoted(f), strerror(e)).as_bytes(),
            );
            r.status = 1;
            continue;
        }
        if headers {
            if printed {
                r.out.push(b'\n');
            }
            r.out.extend_from_slice(format!("==> {} <==\n", name).as_bytes());
            printed = true;
        }
        match got {
            Ok(b) => r.out.extend(o_tail(&b, n)),
            Err(Failed::Read(e)) | Err(Failed::Open(e)) => {
                // What the tool does NEXT is the filesystem's, not tail's (THE
                // MODEL above): the model answers only where both agree.
                if at + 1 < ops.len() {
                    r.no_answer = Some(format!(
                        "tail -c on {} with operands after it: GNU tail stops there on one \
                         filesystem and reads on on another, so the model has no answer. \
                         Put the operand that will not read last.",
                        quoted(f)
                    ));
                    return r;
                }
                let shown = if f == "-" { name.clone() } else { quoted(f) };
                r.err.extend_from_slice(format!("{}: error reading {}: {}\n", prog, shown, strerror(e)).as_bytes());
                r.status = 1;
            }
        }
    }
    r
}

fn m_hexdump(prog: &str, args: &[String]) -> Run {
    let mut r = Run { out: Vec::new(), err: Vec::new(), status: 0, no_answer: None };
    let canonical = args.iter().any(|a| a == "-C");
    let ops: Vec<&String> = args.iter().filter(|a| *a != "-C").collect();
    let mut data = Vec::new();
    if ops.is_empty() {
        let mut taken = false;
        data = stdin_once(&mut taken);
    } else {
        let mut opened = false;
        for f in &ops {
            match slurp(f) {
                Ok(b) => {
                    data.extend(b);
                    opened = true;
                }
                Err(Failed::Open(e)) => {
                    r.err.extend_from_slice(format!("{}: {}: {}\n", prog, f, strerror(e)).as_bytes());
                    r.status = 1;
                }
                Err(Failed::Read(e)) => {
                    r.err.extend_from_slice(format!("{}: {}: {}\n", prog, f, strerror(e)).as_bytes());
                    opened = true;
                }
            }
        }
        if !opened {
            r.err.extend_from_slice(format!("{}: all input file arguments failed\n", prog).as_bytes());
        }
    }
    r.out = o_dump(&data, canonical);
    r
}

/// `oracle c10_run ...`: see THE MODEL above. Never returns.
pub fn run_cmd(args: &[String]) -> ! {
    let (prog, rest) = if args.len() >= 2 && args[0] == "--prog" {
        (Some(args[1].clone()), &args[2..])
    } else {
        (None, args)
    };
    let Some((tool, operands)) = rest.split_first() else {
        eprintln!("usage: oracle c10_run [--prog NAME] display_file|cat|tail|hexdump ARG...");
        std::process::exit(2);
    };
    let prog = prog.unwrap_or_else(|| tool.clone());
    let r = match tool.as_str() {
        "display_file" => m_display_file(operands),
        "cat" => m_cat(&prog, operands),
        "tail" => m_tail(&prog, operands),
        "hexdump" => m_hexdump(&prog, operands),
        _ => {
            eprintln!("oracle c10_run: no model for {:?}", tool);
            std::process::exit(2);
        }
    };
    if let Some(why) = &r.no_answer {
        eprintln!("oracle c10_run: {}", why);
        std::process::exit(2);
    }
    let _ = std::io::stdout().write_all(&r.out);
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().write_all(&r.err);
    std::process::exit(r.status);
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

    // ---- SEVERAL FILES, one stream: the tool's own transcripts, pasted.
    //
    // `hexdump -C a b` and `hexdump a b` with a = "0123456789abc" (13 bytes)
    // and b = "defghijklmnopqrstuvwxyz\n" (24): a line holds the end of one
    // file and the start of the next, and the offsets carry on. Then z1 = 20
    // NULs, z2 = 44 NULs and "end", h = 80 81 ff: the squeeze runs across
    // the boundary and the next line prints at its real offset. util-linux
    // 2.37.2, run on those files and pasted.
    let a: &[u8] = b"0123456789abc";
    let b: &[u8] = b"defghijklmnopqrstuvwxyz\n";
    let ab = concat(&[a.to_vec(), b.to_vec()]);
    let want_c_ab = "00000000  30 31 32 33 34 35 36 37  38 39 61 62 63 64 65 66  |0123456789abcdef|\n\
00000010  67 68 69 6a 6b 6c 6d 6e  6f 70 71 72 73 74 75 76  |ghijklmnopqrstuv|\n\
00000020  77 78 79 7a 0a                                    |wxyz.|\n\
00000025\n";
    if o_hexdump(&ab) != want_c_ab.as_bytes() {
        eprintln!("c10: hexdump -C of two files is not the tool's one stream");
        fails += 1;
    }
    let want_d_ab = "0000000 3130 3332 3534 3736 3938 6261 6463 6665\n\
0000010 6867 6a69 6c6b 6e6d 706f 7271 7473 7675\n\
0000020 7877 7a79 000a                         \n\
0000025\n";
    if o_hexdump_default(&ab) != want_d_ab.as_bytes() {
        eprintln!("c10: hexdump of two files, default format, is not the tool's");
        fails += 1;
    }
    let mut z2 = vec![0u8; 44];
    z2.extend_from_slice(b"end");
    let zzh = concat(&[vec![0u8; 20], z2, vec![0x80, 0x81, 0xff]]);
    let want_c_zzh = "00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|\n\
*\n\
00000040  65 6e 64 80 81 ff                                 |end...|\n\
00000046\n";
    if o_hexdump(&zzh) != want_c_zzh.as_bytes() {
        eprintln!("c10: hexdump -C did not squeeze a run across a file boundary as the tool does");
        fails += 1;
    }
    let want_d_zzh = "0000000 0000 0000 0000 0000 0000 0000 0000 0000\n\
*\n\
0000040 6e65 8064 ff81                         \n\
0000046\n";
    if o_hexdump_default(&zzh) != want_d_zzh.as_bytes() {
        eprintln!("c10: hexdump (default format) did not squeeze across a file boundary as the tool does");
        fails += 1;
    }
    // The default format's own layout, on c-10's committed fixture dedup.bin
    // (69 bytes: 48 x 'A', 16 x 'B', "CCCCC"): an odd last byte is the low
    // half of its number, and a short line is padded field by field.
    let mut dd = vec![b'A'; 48];
    dd.extend_from_slice(&[b'B'; 16]);
    dd.extend_from_slice(b"CCCCC");
    let want_d_dd = "0000000 4141 4141 4141 4141 4141 4141 4141 4141\n\
*\n\
0000030 4242 4242 4242 4242 4242 4242 4242 4242\n\
0000040 4343 4343 0043                         \n\
0000045\n";
    if o_hexdump_default(&dd) != want_d_dd.as_bytes() {
        eprintln!("c10: hexdump's default format does not match the tool on dedup.bin");
        fails += 1;
    }

    // ---- the grouped corpora: every group size, and the stream's shapes.
    let mut rng = Rng::new(11);
    let gs = groups(&file_corpus(&mut rng, 60));
    for size in 1..=3 {
        if !gs.iter().any(|g| g.len() == size) {
            eprintln!("c10: no group of {} file(s) in a grouped corpus", size);
            fails += 1;
        }
    }
    if gs.iter().map(|g| g.len()).sum::<usize>() != 60 {
        eprintln!("c10: the groups lost or repeated a file of the pool");
        fails += 1;
    }
    let sg = stream_groups();
    // A run that crosses a boundary: the dump of the stream has a `*` that no
    // file's own dump has.
    if !sg.iter().any(|g| {
        g.len() > 1
            && String::from_utf8_lossy(&o_hexdump(&concat(g))).contains('*')
            && !g.iter().any(|f| String::from_utf8_lossy(&o_hexdump(f)).contains('*'))
    }) {
        eprintln!("c10: no stream group whose squeeze exists only across a file boundary");
        fails += 1;
    }
    // A file whose size is not a multiple of 16 followed by another: its last
    // line is shared.
    if !sg.iter().any(|g| g.len() > 1 && g[0].len() % 16 != 0 && !g[0].is_empty()) {
        eprintln!("c10: no stream group where a line holds two files' bytes");
        fails += 1;
    }

    // ---- THE MODEL's messages, against the tools' own, pasted from coreutils
    // 8.32 and util-linux 2.37.2 run as `tail` and `hexdump` on a missing name
    // and on `.`. A name no system has, so the paths are the same everywhere.
    let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<String>>();
    let miss = "/nonexistent-c10-check";
    let t = m_tail("tail", &s(&["-c", "5", miss]));
    if t.err != format!("tail: cannot open '{}' for reading: No such file or directory\n", miss).as_bytes()
        || !t.out.is_empty()
        || t.status != 1
    {
        eprintln!("c10: the tail model's missing-file path is not the tool's");
        fails += 1;
    }
    let t = m_tail("tail", &s(&["-c", "0", miss]));
    if !t.err.is_empty() || !t.out.is_empty() || t.status != 0 {
        eprintln!("c10: the tail model opens something under -c 0, which the tool does not");
        fails += 1;
    }
    let t = m_tail("tail", &s(&["-c5", "."]));
    if t.err != b"tail: error reading '.': Is a directory\n" || !t.out.is_empty() || t.status != 1 {
        eprintln!("c10: the tail model's directory path is not the tool's");
        fails += 1;
    }
    // A directory with operands after it: the tool's next step is the
    // filesystem's (THE MODEL), so the model gives no answer rather than one.
    let t = m_tail("tail", &s(&["-c", "5", ".", miss]));
    if t.no_answer.is_none() {
        eprintln!("c10: the tail model answers for a directory before another operand, where the tool's answer is the filesystem's");
        fails += 1;
    }
    let t = m_tail("tail", &s(&["-c", "5", miss, "."]));
    if t.out != b"==> . <==\n" || t.status != 1 {
        eprintln!("c10: the tail model does not head a directory among several operands as the tool does");
        fails += 1;
    }
    let h = m_hexdump("hexdump", &s(&["-C", miss]));
    if h.err != format!("hexdump: {}: No such file or directory\nhexdump: all input file arguments failed\n", miss).as_bytes()
        || h.status != 1
    {
        eprintln!("c10: the hexdump model's all-failed path is not the tool's");
        fails += 1;
    }
    let h = m_hexdump("hexdump", &s(&["-C", ".", miss]));
    if h.err != format!("hexdump: .: Is a directory\nhexdump: {}: No such file or directory\n", miss).as_bytes()
        || h.status != 1
    {
        eprintln!("c10: the hexdump model counts a directory as failing to open, which the tool does not");
        fails += 1;
    }
    let c = m_cat("cat", &s(&[miss, "."]));
    if c.err != format!("cat: {}: No such file or directory\ncat: .: Is a directory\n", miss).as_bytes() || c.status != 1 {
        eprintln!("c10: the cat model's error paths are not the tool's");
        fails += 1;
    }
    let d = m_display_file(&s(&[miss, miss]));
    if d.err != b"Too many arguments.\n" {
        eprintln!("c10: the display_file model does not print the subject's message for two names");
        fails += 1;
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
