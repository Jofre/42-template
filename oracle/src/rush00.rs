//! Rush00 (c-piscine-rush-00) references: the five rectangle variants of `void rush(int x, int y)`.
//!
//! Line formats (see oracle/README.md):
//!   rush_v0 .. rush_v4            <x>\t<y>\t<escaped-rectangle>
//!   rush_v0_edge .. rush_v4_edge  <x>\t<y>\t<escaped-rectangle>   (degenerate sizes)
//! and one that is not a corpus:
//!   rush00_fixtures               <path under tests/ex00/>\t<bytes, esc_posix>:
//!                                 every file a Rush 00 target reads -- the
//!                                 curated table's cases and expected tables,
//!                                 the survival layer's cases and rows,
//!                                 ft_putchar's bytes, the defense case --
//!                                 which ex00_oracle_fixtures holds the ones in
//!                                 c-piscine/c-piscine-rush-00/tests/ex00/ to
//!                                 (tools/oracle_fixtures.sh)
//!
//! `rush_vN` maps to the subject's `rush0N.c`. Unlike every other oracle here,
//! the reference output is MULTI-LINE, so it is escaped onto ONE corpus line:
//!
//!   '\\' -> "\\\\",  '\n' -> "\\n",  any other byte < 0x20 or > 0x7e -> "\\xHH",
//!   everything else raw.
//!
//! The escape is not decoration: variant 1 draws corners with a literal
//! backslash, so an unescaped corpus would be ambiguous. The C reader harness
//! (tests/ex00/rush_capture.h) escapes the student's captured bytes with the
//! exact same rules, hence a byte-diff of the two lines is a byte-diff of the
//! two rectangles — including trailing spaces and the final newline.
//!
//! The `_edge` corpora hold sizes the subject leaves UNDEFINED (zero, negative,
//! INT_MIN, and huge dimensions paired with a non-positive one). Their reference
//! output is therefore NOT authoritative and they are only ever replayed in
//! `--crash-only` mode (tools/rust_diff.sh), which ignores values and asserts
//! only that the student's code survives ASan/UBSan without hanging.

use crate::common::{esc_posix, Rng};
use std::collections::HashSet;
use std::io::{self, Write};

/// The six characters that define a variant: four corners plus the horizontal
/// (top/bottom) and vertical (left/right) wall characters. Interior is ' '.
struct Spec {
    tl: u8,
    tr: u8,
    bl: u8,
    br: u8,
    horiz: u8,
    vert: u8,
}

/// Variants 0..=4, transcribed from the subject's chapters V..IX. Every entry is
/// pinned by the subject's own five worked examples in `check()`.
const SPECS: [Spec; 5] = [
    // rush00: o---o / |   | / o---o
    Spec { tl: b'o', tr: b'o', bl: b'o', br: b'o', horiz: b'-', vert: b'|' },
    // rush01: /***\ / *   * / \***/
    Spec { tl: b'/', tr: b'\\', bl: b'\\', br: b'/', horiz: b'*', vert: b'*' },
    // rush02: ABBBA / B   B / CBBBC
    Spec { tl: b'A', tr: b'A', bl: b'C', br: b'C', horiz: b'B', vert: b'B' },
    // rush03: ABBBC / B   B / ABBBC
    Spec { tl: b'A', tr: b'C', bl: b'A', br: b'C', horiz: b'B', vert: b'B' },
    // rush04: ABBBC / B   B / CBBBA
    Spec { tl: b'A', tr: b'C', bl: b'C', br: b'A', horiz: b'B', vert: b'B' },
];

// ------------------------------------------------------------- oracles

/// The character at row `r`, column `c` of an `x` by `y` rectangle.
///
/// Precedence — this is the whole exercise, and the subject pins it: a cell that
/// is both a top and a bottom row (y == 1) is a TOP cell, and a cell that is
/// both a left and a right column (x == 1) is a LEFT cell. Hence rush(1, 1) is
/// the top-left corner for every variant, rush(x, 1) is `tl horiz.. tr`, and
/// rush(1, y) is `tl vert.. bl`.
fn cell(s: &Spec, x: i32, y: i32, r: i32, c: i32) -> u8 {
    let top = r == 0;
    let bottom = r == y - 1;
    let left = c == 0;
    let right = c == x - 1;
    if top && left {
        s.tl
    } else if top && right {
        s.tr
    } else if bottom && left {
        s.bl
    } else if bottom && right {
        s.br
    } else if top || bottom {
        s.horiz
    } else if left || right {
        s.vert
    } else {
        b' '
    }
}

/// The exact bytes a correct `rush(x, y)` writes: `y` lines of `x` characters,
/// each line terminated by '\n' (the subject's transcripts return to the shell
/// prompt on a fresh line). Nothing at all for a non-positive dimension — the
/// subject does not define that case, so this is only used by the `_edge`
/// corpora, which are never value-compared.
fn render(s: &Spec, x: i32, y: i32) -> Vec<u8> {
    if x <= 0 || y <= 0 {
        return Vec::new();
    }
    let mut out = Vec::with_capacity((x as usize + 1) * y as usize);
    let mut r = 0;
    while r < y {
        let mut c = 0;
        while c < x {
            out.push(cell(s, x, y, r, c));
            c += 1;
        }
        out.push(b'\n');
        r += 1;
    }
    out
}

/// One-line escape of a rectangle (see the module header for the rules).
fn esc(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() + 8);
    for &b in bytes {
        match b {
            b'\\' => out.push_str("\\\\"),
            b'\n' => out.push_str("\\n"),
            0x20..=0x7e => out.push(b as char),
            _ => out.push_str(&format!("\\x{:02x}", b)),
        }
    }
    out
}

// ---------------------------------------------------------- generators

/// Case-generation contract for the VALID corpus, asserted in `check()`: no
/// dimension above `MAX_DIM`, no rectangle above `MAX_AREA` cells. The random
/// tail keeps to the much tighter `TAIL_MAX_DIM` / `TAIL_MAX_AREA` — past a few
/// hundred, random sizes add no new structure, they only inflate the corpus.
const MAX_DIM: i32 = 4097;
const MAX_AREA: i32 = 12300;
const TAIL_MAX_DIM: i32 = 200;
const TAIL_MAX_AREA: i32 = 4000;

/// Widths (and, transposed, heights) that sit exactly on the ceilings students
/// actually hit: the capacity of a hand-sized internal buffer (64, 80, 100,
/// 128, 256, 512, 1024, 2048, 4096) and the range of a `char` counter (127,
/// 128, 255, 256), each with its neighbours so an off-by-one at the ceiling is
/// distinguishable from the ceiling itself. A fixed buffer overrun still prints
/// the right rectangle, so the value diff alone cannot see it — but the same
/// sizes replayed under ASan can (tests/ex00/mem_rush.c), and having them in
/// BOTH corpora means one size list explains both failures.
///
/// The `short`-counter ceilings (32768, 65536) and the deep-recursion cases
/// live in tests/ex00/edge_cases.tsv instead: their rectangles are hundreds of
/// kilobytes, and all they can prove is that the run terminates.
const CEILINGS: [i32; 27] = [
    63, 64, 65, 79, 80, 81, 99, 100, 101, 127, 128, 129, 255, 256, 257, 511, 512, 513, 1023, 1024,
    1025, 2047, 2048, 2049, 4095, 4096, 4097,
];

/// Push `(x, y)` once, deduplicating against `seen`.
fn push_size(out: &mut Vec<(i32, i32)>, seen: &mut HashSet<(i32, i32)>, x: i32, y: i32) {
    if seen.insert((x, y)) {
        out.push((x, y));
    }
}

/// Valid sizes: the subject's own examples, an exhaustive small block, the thin
/// bands (width/height 1, 2 and 3), the square diagonal, the buffer/counter
/// CEILINGS, then a seeded random tail. Every case obeys `1 <= x, y <= MAX_DIM`
/// and `x * y <= MAX_AREA`, which keeps one corpus a few megabytes rather than
/// unbounded.
///
/// The small block is exhaustive on purpose: every off-by-one in the fill count
/// or the row count shows up inside 1..=40, and the width/height 1 and 2 bands
/// are where corner precedence collapses (x == 1 or y == 1) or where a rectangle
/// is *all* corners (2 by 2).
///
/// The structured cases are emitted whatever `count` says (like the other oracle
/// modules, `count` only sizes the random tail); the tail additionally gives up
/// after a bounded number of draws, so a `count` larger than the pool of legal
/// distinct sizes can never spin forever.
fn size_cases(rng: &mut Rng, count: usize) -> Vec<(i32, i32)> {
    let mut out: Vec<(i32, i32)> = Vec::new();
    let mut seen: HashSet<(i32, i32)> = HashSet::new();

    // The subject's five worked examples first, then its defense example.
    for &(x, y) in &[(5, 3), (5, 1), (1, 1), (1, 5), (4, 4), DEFENSE] {
        push_size(&mut out, &mut seen, x, y);
    }
    // Exhaustive small block: every off-by-one lives in here.
    for x in 1..=40 {
        for y in 1..=40 {
            push_size(&mut out, &mut seen, x, y);
        }
    }
    // Long thin bands (1, 2 and 3 wide/tall) and the square diagonal. Bounded by
    // TAIL_MAX_DIM: past a couple of hundred, the only widths worth their bytes
    // are the CEILINGS below.
    for n in 1..=TAIL_MAX_DIM {
        for k in 1..=3 {
            push_size(&mut out, &mut seen, n, k);
            push_size(&mut out, &mut seen, k, n);
        }
        if n * n <= MAX_AREA {
            push_size(&mut out, &mut seen, n, n);
        }
    }
    // Buffer- and counter-ceiling widths, one to three rows tall, both ways up.
    for &n in CEILINGS.iter() {
        for k in 1..=3 {
            push_size(&mut out, &mut seen, n, k);
            push_size(&mut out, &mut seen, k, n);
        }
    }
    // Seeded random tail, area-capped so the corpus stays small on disk.
    let mut draws = 0;
    while out.len() < count && draws < 40 * count + 1000 {
        draws += 1;
        let x = 1 + rng.below(TAIL_MAX_DIM as usize) as i32;
        let y = 1 + rng.below(TAIL_MAX_DIM as usize) as i32;
        if x * y > TAIL_MAX_AREA {
            continue;
        }
        push_size(&mut out, &mut seen, x, y);
    }
    // No truncation: count.max(len) is never below len, so this only ever
    // raised the corpus. A small --count therefore keeps the whole
    // structured head rather than cutting into it, which is the policy;
    // it used to be spelled as a call that could not do anything.
    out
}

/// Degenerate sizes for the crash-fuzz corpus: zero, negative, INT_MIN/INT_MAX,
/// and every mixed pairing of those with a small valid dimension. A huge
/// dimension only ever appears next to a non-positive one — `rush(INT_MAX, 42)`
/// is not a bug, it is 90 billion legitimate characters, so it is never asked
/// for. Valid small sizes are interleaved so the sanitizer also walks the normal
/// path.
fn edge_cases(rng: &mut Rng, count: usize) -> Vec<(i32, i32)> {
    let degenerate: [i32; 8] = [0, -1, -2, -7, -42, i32::MIN, i32::MIN + 1, -1000];
    let small: [i32; 7] = [1, 2, 3, 4, 5, 40, 123];
    let huge: [i32; 3] = [i32::MAX, i32::MAX - 1, 100000];
    let mut out: Vec<(i32, i32)> = Vec::new();
    let mut seen: HashSet<(i32, i32)> = HashSet::new();

    for &a in &degenerate {
        for &b in &degenerate {
            push_size(&mut out, &mut seen, a, b);
        }
        for &b in &small {
            push_size(&mut out, &mut seen, a, b);
            push_size(&mut out, &mut seen, b, a);
        }
        // A huge dimension is only ever paired with a non-positive one.
        for &b in &huge {
            push_size(&mut out, &mut seen, a, b);
            push_size(&mut out, &mut seen, b, a);
        }
    }
    // Normal-path company for the sanitizer.
    for x in 1..=24 {
        for y in 1..=24 {
            push_size(&mut out, &mut seen, x, y);
        }
    }
    let mut draws = 0;
    while out.len() < count && draws < 40 * count + 1000 {
        draws += 1;
        let pick = rng.below(4);
        let d = degenerate[rng.below(degenerate.len())];
        let v = 1 + rng.below(60) as i32;
        match pick {
            0 => push_size(&mut out, &mut seen, d, v),
            1 => push_size(&mut out, &mut seen, v, d),
            2 => push_size(&mut out, &mut seen, d, d),
            _ => push_size(&mut out, &mut seen, v, v),
        }
    }
    // No truncation: count.max(len) is never below len, so this only ever
    // raised the corpus. A small --count therefore keeps the whole
    // structured head rather than cutting into it, which is the policy;
    // it used to be spelled as a call that could not do anything.
    out
}

/// The curated, human-labelled case list behind the pedagogic layer
/// (tests/ex00/cases.tsv + rush0N.txt, both generated from here so the
/// labels and the expectations can never drift apart). Ordered trivial ->
/// conceptually hardest, and every label is referenced by tests/ex00/clues.tsv:
/// renaming one here means renaming it there.
const FIXED: [(&str, i32, i32); 26] = [
    ("1x1 single cell", 1, 1),
    ("2x1 one row", 2, 1),
    ("1x2 one column", 1, 2),
    ("2x2 all corners", 2, 2),
    ("3x1 row of three", 3, 1),
    ("1x3 column of three", 1, 3),
    ("3x2", 3, 2),
    ("2x3", 2, 3),
    ("3x3 first interior", 3, 3),
    ("4x4 (subject)", 4, 4),
    ("5x1 (subject)", 5, 1),
    ("1x5 (subject)", 1, 5),
    ("5x3 (subject)", 5, 3),
    ("5x5", 5, 5),
    ("6x2", 6, 2),
    ("2x6", 2, 6),
    ("7x3", 7, 3),
    ("3x7", 3, 7),
    ("8x1 wide row", 8, 1),
    ("1x8 tall column", 1, 8),
    ("9x4", 9, 4),
    ("4x9", 4, 9),
    ("10x2", 10, 2),
    ("12x5", 12, 5),
    ("20x3 wide", 20, 3),
    ("3x20 tall", 3, 20),
];

/// Emit `<label>\t<x>\t<y>\t<escaped-rectangle>` for the curated list. Both
/// halves of the pedagogic fixture are cut out of this one stream: fields 1..3
/// are the case list the C harness replays, fields 1 and 4 are the expected
/// table (see tests/ex00/regen.sh).
fn emit_fixed(spec: &Spec) {
    let stdout = io::stdout();
    let mut w = io::BufWriter::new(stdout.lock());
    for &(label, x, y) in FIXED.iter() {
        let _ = writeln!(w, "{}\t{}\t{}\t{}", label, x, y, esc(&render(spec, x, y)));
    }
    let _ = w.flush();
}

/// The subject's defense case: "Your main function will be modified during the
/// defense ... Here is an example of a test that will be performed:
/// rush(123, 42);". In the diff corpus's head (size_cases), and drawn in full,
/// per variant, by the fixtures below, which each variant's `<p>_defense`
/// target compares at basic: the subject says the defense runs it.
const DEFENSE: (i32, i32) = (123, 42);

/// `<p>_defense`'s one table row when the picture is the reference's: the
/// label, a TAB, the verdict. tests/ex00/test_defense.c prints the same row,
/// built from the picture it reads, so the two agree by construction or the
/// target is red on every correct answer, which nobody could miss.
fn defense_row(x: i32, y: i32) -> String {
    format!(
        "rush({}, {}), the subject's defense case\tthe reference's picture, all {} bytes\n",
        x,
        y,
        (i64::from(x) + 1) * i64::from(y)
    )
}

/// A line of tests/ex00/edge_cases.tsv: a comment, or a case.
enum Edge {
    Note(&'static str),
    Case(&'static str, i32, i32),
}

/// The survival layer's hostile sizes (`<p>_survive`, tests/ex00/survive_rush.c
/// reads them from tests/ex00/edge_cases.tsv on stdin), with the comments the
/// file carries, in order. Nothing here is drawn or diffed: each case must come
/// back alive, and a legal size in the rectangle's shape. Every label is
/// referenced by tests/ex00/clues.tsv: renaming one here means renaming it there.
const SURVIVE: [Edge; 68] = [
    Edge::Note("# Hostile sizes for the survival layer, <p>_survive (tests/ex00/survive_rush.c)."),
    Edge::Note("# GENERATED by `oracle rush00_fixtures` (oracle/src/rush00.rs, const SURVIVE),"),
    Edge::Note("# and held to it by ex00_oracle_fixtures: edit the list there, not here."),
    Edge::Note("# Format: <label><TAB><x><TAB><y>"),
    Edge::Note("#"),
    Edge::Note("# Nothing here is diffed against a rectangle: every case has to come back"),
    Edge::Note("# alive, promptly, without burying the terminal, and a legal size (part 2 and"),
    Edge::Note("# 3) also in the rectangle's shape -- y lines of x characters and a newline,"),
    Edge::Note("# which the size alone fixes. Which characters is the value layers' question."),
    Edge::Note("# Labels are referenced by clues.tsv; rename one in SURVIVE and rename it there."),
    Edge::Note("#"),
    Edge::Note("# --- part 1: sizes the subject leaves UNDEFINED -----------------------------"),
    Edge::Note("# \"Your function must never crash or enter an infinite loop\" is a requirement;"),
    Edge::Note("# what a non-positive size should PRINT is not specified, so it is not checked."),
    Edge::Note("# A huge dimension is only ever paired with a non-positive one — rush(2147483647,"),
    Edge::Note("# 42) is 90 billion legitimate characters, not a bug."),
    Edge::Case("1x0 no rows", 1, 0),
    Edge::Case("0x1 no columns", 0, 1),
    Edge::Case("0x0 nothing at all", 0, 0),
    Edge::Case("5x0 no rows", 5, 0),
    Edge::Case("0x5 no columns", 0, 5),
    Edge::Case("2x0", 2, 0),
    Edge::Case("0x2", 0, 2),
    Edge::Case("-1x5 negative width", -1, 5),
    Edge::Case("5x-1 negative height", 5, -1),
    Edge::Case("-1x1", -1, 1),
    Edge::Case("1x-1", 1, -1),
    Edge::Case("-5x-5 both negative", -5, -5),
    Edge::Case("-1x-1 both negative", -1, -1),
    Edge::Case("-42x7", -42, 7),
    Edge::Case("7x-42", 7, -42),
    Edge::Case("INT_MIN width", i32::MIN, 3),
    Edge::Case("INT_MIN height", 3, i32::MIN),
    Edge::Case("INT_MIN both", i32::MIN, i32::MIN),
    Edge::Case("INT_MIN width, no rows", i32::MIN, 0),
    Edge::Case("no columns, INT_MIN height", 0, i32::MIN),
    Edge::Case("INT_MAX width, no rows", i32::MAX, 0),
    Edge::Case("no columns, INT_MAX height", 0, i32::MAX),
    Edge::Case("INT_MAX width, negative height", i32::MAX, -1),
    Edge::Case("negative width, INT_MAX height", -1, i32::MAX),
    Edge::Case("INT_MAX width, INT_MIN height", i32::MAX, i32::MIN),
    Edge::Case("100000x0", 100000, 0),
    Edge::Case("0x100000", 0, 100000),
    Edge::Note("# --- part 2: legal sizes that sit on a counter ceiling ----------------------"),
    Edge::Note("# These are perfectly valid rectangles — the value diff checks the ones up to"),
    Edge::Note("# 4097 — but a `char` counter stops at 127, an `unsigned char` at 255, a `short`"),
    Edge::Note("# at 32767, an `unsigned short` at 65535. Past its ceiling the counter wraps and"),
    Edge::Note("# the loop never ends, so here we ask whether the call comes back at all, and"),
    Edge::Note("# in the rectangle's shape. The last pair asks the same question of the call"),
    Edge::Note("# stack rather than a counter."),
    Edge::Case("128x1 char-counter ceiling", 128, 1),
    Edge::Case("1x128 char-counter ceiling", 1, 128),
    Edge::Case("255x1", 255, 1),
    Edge::Case("256x1 unsigned-char ceiling", 256, 1),
    Edge::Case("1x256 unsigned-char ceiling", 1, 256),
    Edge::Case("257x1", 257, 1),
    Edge::Case("32767x1", 32767, 1),
    Edge::Case("32768x1 short-counter ceiling", 32768, 1),
    Edge::Case("1x32768 short-counter ceiling", 1, 32768),
    Edge::Case("65535x1", 65535, 1),
    Edge::Case("65536x1 unsigned-short ceiling", 65536, 1),
    Edge::Case("1x65536 unsigned-short ceiling", 1, 65536),
    Edge::Case("100000x1 very wide", 100000, 1),
    Edge::Case("1x100000 very tall", 1, 100000),
    Edge::Case("1x400000 very tall (call depth)", 1, 400000),
    Edge::Note("# --- part 3: back to normal -------------------------------------------------"),
    Edge::Case("3x3 still works after all that", 3, 3),
    Edge::Case("7x2 still works after all that", 7, 2),
];

/// survive_rush.c's last row, after every case: rush(3, 3) still draws what
/// it drew before the degenerate calls.
const SURVIVE_LAST: &str = "3x3 unchanged by the degenerate calls\tYES\n";

/// The bytes tests/ex00/test_putchar.c makes ft_putchar write, in its order:
/// "OK" and a newline, then "42", a space and the characters a rush draws
/// with, then a tab, NUL, DEL, 0x80 and 0xff -- every byte is one write(),
/// a char above 0x7f included -- and a final newline.
const PUTCHAR: &[u8] = b"OK\n42 -|/\\~\t\x00\x7f\x80\xff\n";

/// THE NAMED FIXTURES (rush00_fixtures): every file a Rush 00 target reads,
/// as (path under tests/ex00/, bytes). The curated table's case list
/// (cases.tsv) and each variant's expected table (rush0N.txt), cut from the
/// one FIXED list so their labels cannot drift apart; the survival layer's
/// cases (edge_cases.tsv) and expected rows (survive.txt), from SURVIVE;
/// ft_putchar's bytes (putchar.txt); and the defense case: the expected row,
/// and the reference's picture of rush(123, 42) for each variant, which the
/// harness reads on stdin and compares byte for byte. ex00_oracle_fixtures
/// fails when a file there differs from this (tools/oracle_fixtures.sh), or
/// when one its --owns patterns match is not here; tests/ex00/regen.sh
/// rewrites them.
fn fixtures() -> Vec<(String, Vec<u8>)> {
    let mut out = Vec::new();

    let mut cases = String::from(
        "# Curated case list for tests/ex00/test_rush.c \u{2014} GENERATED by `oracle rush00_fixtures`.\n\
         # Source of truth: oracle/src/rush00.rs, const FIXED. Do not hand-edit.\n\
         # Format: <label><TAB><x><TAB><y>\n",
    );
    for &(label, x, y) in FIXED.iter() {
        cases.push_str(&format!("{}\t{}\t{}\n", label, x, y));
    }
    out.push(("cases.tsv".to_string(), cases.into_bytes()));
    for (v, spec) in SPECS.iter().enumerate() {
        let mut table = String::new();
        for &(label, x, y) in FIXED.iter() {
            table.push_str(&format!("{}\t{}\n", label, esc(&render(spec, x, y))));
        }
        out.push((format!("rush0{}.txt", v), table.into_bytes()));
    }

    let mut edge = String::new();
    let mut survive = String::new();
    for e in SURVIVE.iter() {
        match *e {
            Edge::Note(n) => edge.push_str(&format!("{}\n", n)),
            Edge::Case(label, x, y) => {
                edge.push_str(&format!("{}\t{}\t{}\n", label, x, y));
                survive.push_str(&format!("{}\tsurvived\n", label));
            }
        }
    }
    survive.push_str(SURVIVE_LAST);
    out.push(("edge_cases.tsv".to_string(), edge.into_bytes()));
    out.push(("survive.txt".to_string(), survive.into_bytes()));
    out.push(("putchar.txt".to_string(), PUTCHAR.to_vec()));

    let (x, y) = DEFENSE;
    out.push(("defense.txt".to_string(), defense_row(x, y).into_bytes()));
    for (v, spec) in SPECS.iter().enumerate() {
        out.push((format!("defense_rush0{}.txt", v), render(spec, x, y)));
    }
    out
}

fn emit_fixtures() {
    let stdout = io::stdout();
    let mut w = io::BufWriter::new(stdout.lock());
    for (path, bytes) in fixtures() {
        let _ = writeln!(w, "{}\t{}", path, esc_posix(&bytes));
    }
    let _ = w.flush();
}

/// Emit `<x>\t<y>\t<escaped-rectangle>` for one variant's case list.
fn emit(spec: &Spec, sizes: &[(i32, i32)]) {
    let stdout = io::stdout();
    let mut w = io::BufWriter::new(stdout.lock());
    for &(x, y) in sizes {
        let _ = writeln!(w, "{}\t{}\t{}", x, y, esc(&render(spec, x, y)));
    }
    let _ = w.flush();
}

// ------------------------------------------------------------- dispatch

/// `rush_vN`, `rush_vN_edge` and `rush_vN_fixed` for N in 0..=4, and
/// `rush00_fixtures` (seed and count ignored: a fixed set of files).
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    if name == "rush00_fixtures" {
        emit_fixtures();
        return true;
    }
    let (stem, edge, fixed) = match (name.strip_suffix("_edge"), name.strip_suffix("_fixed")) {
        (Some(stem), _) => (stem, true, false),
        (_, Some(stem)) => (stem, false, true),
        _ => (name, false, false),
    };
    let v = match stem {
        "rush_v0" => 0,
        "rush_v1" => 1,
        "rush_v2" => 2,
        "rush_v3" => 3,
        "rush_v4" => 4,
        _ => return false,
    };
    if fixed {
        emit_fixed(&SPECS[v]);
        return true;
    }
    let mut rng = Rng::new(seed);
    let sizes = if edge {
        edge_cases(&mut rng, count)
    } else {
        size_cases(&mut rng, count)
    };
    emit(&SPECS[v], &sizes);
    true
}

// ----------------------------------------------------------- self-check

/// An INDEPENDENT second construction of the rectangle, used only by `check()`:
/// start from a grid of spaces, paint the four walls, then stamp the corners
/// last. It shares no code path with `cell()`, so the two agreeing on every
/// size is real evidence the reference is not quietly wrong.
fn render_by_painting(s: &Spec, x: i32, y: i32) -> Vec<u8> {
    if x <= 0 || y <= 0 {
        return Vec::new();
    }
    let w = x as usize;
    let h = y as usize;
    let mut grid = vec![vec![b' '; w]; h];
    for row in grid.iter_mut() {
        row[0] = s.vert;
        row[w - 1] = s.vert;
    }
    for c in 0..w {
        grid[0][c] = s.horiz;
        grid[h - 1][c] = s.horiz;
    }
    // Corners last, in the subject's precedence order: a 1-wide or 1-tall
    // rectangle must end up with the TOP-LEFT character in its shared cell.
    grid[h - 1][w - 1] = s.br;
    grid[h - 1][0] = s.bl;
    grid[0][w - 1] = s.tr;
    grid[0][0] = s.tl;
    let mut out = Vec::new();
    for row in grid {
        out.extend_from_slice(&row);
        out.push(b'\n');
    }
    out
}

/// Self-check: the subject's hand-transcribed examples for all five variants,
/// plus structural properties over a wide size sweep. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- the subject's own worked examples (chapters V..IX), verbatim ----
    let expected: [[&str; 5]; 5] = [
        [
            "o---o\n|   |\no---o\n",
            "o---o\n",
            "o\n",
            "o\n|\n|\n|\no\n",
            "o--o\n|  |\n|  |\no--o\n",
        ],
        [
            "/***\\\n*   *\n\\***/\n",
            "/***\\\n",
            "/\n",
            "/\n*\n*\n*\n\\\n",
            "/**\\\n*  *\n*  *\n\\**/\n",
        ],
        [
            "ABBBA\nB   B\nCBBBC\n",
            "ABBBA\n",
            "A\n",
            "A\nB\nB\nB\nC\n",
            "ABBA\nB  B\nB  B\nCBBC\n",
        ],
        [
            "ABBBC\nB   B\nABBBC\n",
            "ABBBC\n",
            "A\n",
            "A\nB\nB\nB\nA\n",
            "ABBC\nB  B\nB  B\nABBC\n",
        ],
        [
            "ABBBC\nB   B\nCBBBA\n",
            "ABBBC\n",
            "A\n",
            "A\nB\nB\nB\nC\n",
            "ABBC\nB  B\nB  B\nCBBA\n",
        ],
    ];
    let sizes: [(i32, i32); 5] = [(5, 3), (5, 1), (1, 1), (1, 5), (4, 4)];
    for (v, spec) in SPECS.iter().enumerate() {
        for (k, &(x, y)) in sizes.iter().enumerate() {
            let got = render(spec, x, y);
            if got != expected[v][k].as_bytes() {
                eprintln!(
                    "CHECK FAIL rush_v{} render({}, {})\n  want {:?}\n  got  {:?}",
                    v,
                    x,
                    y,
                    expected[v][k],
                    String::from_utf8_lossy(&got)
                );
                fails += 1;
            }
        }
    }

    // ---- structural properties over a wide sweep ----
    for (v, spec) in SPECS.iter().enumerate() {
        let chars = [spec.tl, spec.tr, spec.bl, spec.br, spec.horiz, spec.vert];
        for x in 1..=60 {
            for y in 1..=60 {
                let out = render(spec, x, y);
                // 1. independent construction agrees
                if out != render_by_painting(spec, x, y) {
                    eprintln!("CHECK FAIL rush_v{} painting mismatch ({}, {})", v, x, y);
                    fails += 1;
                }
                let lines: Vec<&[u8]> = out.split(|&b| b == b'\n').collect();
                // 2. exactly y lines, each terminated (split leaves a trailing "")
                if lines.len() != y as usize + 1 || !lines[y as usize].is_empty() {
                    eprintln!("CHECK FAIL rush_v{} line count ({}, {})", v, x, y);
                    fails += 1;
                    continue;
                }
                for (r, line) in lines[..y as usize].iter().enumerate() {
                    // 3. every line is exactly x wide (no trailing spaces, no short row)
                    if line.len() != x as usize {
                        eprintln!("CHECK FAIL rush_v{} width row {} ({}, {})", v, r, x, y);
                        fails += 1;
                        continue;
                    }
                    for (c, &b) in line.iter().enumerate() {
                        let interior = r > 0
                            && r + 1 < y as usize
                            && c > 0
                            && c + 1 < x as usize;
                        // 4. interior is space, border is one of the six chars
                        if interior != (b == b' ') || (!interior && !chars.contains(&b)) {
                            eprintln!(
                                "CHECK FAIL rush_v{} char at ({}, {}) of ({}, {})",
                                v, r, c, x, y
                            );
                            fails += 1;
                        }
                    }
                }
                // 5. the four corners are the four corner characters
                let first = lines[0];
                let last = lines[y as usize - 1];
                let corners = [
                    (first[0], spec.tl),
                    (first[x as usize - 1], if x == 1 { spec.tl } else { spec.tr }),
                    (last[0], if y == 1 { spec.tl } else { spec.bl }),
                    (
                        last[x as usize - 1],
                        match (x, y) {
                            (1, 1) => spec.tl,
                            (1, _) => spec.bl,
                            (_, 1) => spec.tr,
                            _ => spec.br,
                        },
                    ),
                ];
                for (k, (got, want)) in corners.iter().enumerate() {
                    if got != want {
                        eprintln!("CHECK FAIL rush_v{} corner {} of ({}, {})", v, k, x, y);
                        fails += 1;
                    }
                }
            }
        }
        // 6. a non-positive dimension renders nothing
        for &(x, y) in &[(0, 0), (0, 5), (5, 0), (-1, 5), (5, -1), (i32::MIN, 3)] {
            if !render(spec, x, y).is_empty() {
                eprintln!("CHECK FAIL rush_v{} non-empty for ({}, {})", v, x, y);
                fails += 1;
            }
        }
    }

    // ---- the escape is unambiguous and lossless ----
    let mut rng = Rng::new(7);
    for _ in 0..2000 {
        let v = rng.below(5);
        let x = 1 + rng.below(30) as i32;
        let y = 1 + rng.below(30) as i32;
        let raw = render(&SPECS[v], x, y);
        let e = esc(&raw);
        if unesc(&e) != raw {
            eprintln!("CHECK FAIL rush escape round-trip v{} ({}, {})", v, x, y);
            fails += 1;
        }
        // an escaped line can never contain a raw newline or tab: the corpus
        // format depends on it
        if e.contains('\n') || e.contains('\t') {
            eprintln!("CHECK FAIL rush escape leaked a separator v{}", v);
            fails += 1;
        }
    }

    // ---- the case generators stay inside their contract ----
    let mut rng = Rng::new(1);
    let valid = size_cases(&mut rng, 4200);
    for &(x, y) in &valid {
        if x < 1 || y < 1 || x > MAX_DIM || y > MAX_DIM || x * y > MAX_AREA {
            eprintln!("CHECK FAIL rush size_cases out of contract ({}, {})", x, y);
            fails += 1;
        }
    }
    // the corpus must actually reach the requested size, and hold no duplicates
    if valid.len() < 4200 {
        eprintln!("CHECK FAIL rush size_cases short: {} < 4200", valid.len());
        fails += 1;
    }
    if valid.iter().collect::<HashSet<_>>().len() != valid.len() {
        eprintln!("CHECK FAIL rush size_cases has duplicates");
        fails += 1;
    }
    for &(x, y) in &[(5, 3), (5, 1), (1, 1), (1, 5), (4, 4), (123, 42)] {
        if !valid.contains(&(x, y)) {
            eprintln!("CHECK FAIL rush size_cases missing subject case ({}, {})", x, y);
            fails += 1;
        }
    }
    // the ceilings are the whole point of the wide bands: a regression that
    // drops them fails `oracle check` instead of hiding in the random tail
    for &n in CEILINGS.iter() {
        if !valid.contains(&(n, 1)) || !valid.contains(&(1, n)) {
            eprintln!("CHECK FAIL rush size_cases missing ceiling {}", n);
            fails += 1;
        }
    }
    // ---- the curated pedagogic list is a usable fixture ----
    let mut labels: HashSet<&str> = HashSet::new();
    for &(label, x, y) in FIXED.iter() {
        if !labels.insert(label) {
            eprintln!("CHECK FAIL rush FIXED duplicate label {:?}", label);
            fails += 1;
        }
        if label.contains('\t') || label.contains('\n') || label.is_empty() {
            eprintln!("CHECK FAIL rush FIXED unusable label {:?}", label);
            fails += 1;
        }
        if x < 1 || y < 1 || x * y > 200 {
            eprintln!("CHECK FAIL rush FIXED size out of table range ({}, {})", x, y);
            fails += 1;
        }
    }
    for &(x, y) in &[(5, 3), (5, 1), (1, 1), (1, 5), (4, 4)] {
        if !FIXED.iter().any(|&(_, fx, fy)| (fx, fy) == (x, y)) {
            eprintln!("CHECK FAIL rush FIXED missing subject case ({}, {})", x, y);
            fails += 1;
        }
    }

    // ---- the defense case: in the corpus head, and drawn by the fixtures ----
    if !size_cases(&mut Rng::new(1), 0).contains(&DEFENSE) {
        eprintln!("CHECK FAIL rush the corpus head lost the defense case {:?}", DEFENSE);
        fails += 1;
    }
    let fx = fixtures();
    let file = |name: &str| fx.iter().find(|(p, _)| p == name).map(|(_, b)| b.clone());
    if file("defense.txt") != Some(defense_row(DEFENSE.0, DEFENSE.1).into_bytes()) {
        eprintln!("CHECK FAIL rush00_fixtures: the defense row");
        fails += 1;
    }
    let pictures: Vec<&(String, Vec<u8>)> = fx.iter().filter(|(p, _)| p.starts_with("defense_rush0")).collect();
    if pictures.len() != SPECS.len() {
        eprintln!("CHECK FAIL rush00_fixtures: one defense picture per variant");
        fails += 1;
    }
    // The curated table: one row per FIXED case in every variant's file and
    // in the case list, the same labels in the same order, each a rectangle
    // that unescapes to the reference's.
    let labels: Vec<&str> = FIXED.iter().map(|&(l, _, _)| l).collect();
    for name in std::iter::once("cases.tsv".to_string()).chain((0..SPECS.len()).map(|v| format!("rush0{}.txt", v))) {
        let text = String::from_utf8(file(&name).unwrap_or_default()).unwrap_or_default();
        let got: Vec<&str> = text.lines().filter(|l| !l.starts_with('#')).map(|l| l.split('\t').next().unwrap_or("")).collect();
        if got != labels {
            eprintln!("CHECK FAIL rush00_fixtures {}: its labels are not FIXED's, in order", name);
            fails += 1;
        }
    }
    for (v, spec) in SPECS.iter().enumerate() {
        let text = String::from_utf8(file(&format!("rush0{}.txt", v)).unwrap_or_default()).unwrap_or_default();
        for (line, &(label, x, y)) in text.lines().zip(FIXED.iter()) {
            if unesc(line.splitn(2, '\t').nth(1).unwrap_or("")) != render(spec, x, y) {
                eprintln!("CHECK FAIL rush00_fixtures rush0{}.txt: {} is not the reference's", v, label);
                fails += 1;
            }
        }
    }
    // The survival layer: a case row per SURVIVE case, the same labels in
    // survive.txt with "survived", and its last row; every label once.
    let edge = String::from_utf8(file("edge_cases.tsv").unwrap_or_default()).unwrap_or_default();
    let surv = String::from_utf8(file("survive.txt").unwrap_or_default()).unwrap_or_default();
    let elabels: Vec<&str> = edge.lines().filter(|l| !l.starts_with('#')).map(|l| l.split('\t').next().unwrap_or("")).collect();
    let srows: Vec<&str> = surv.lines().collect();
    let mut seen = HashSet::new();
    if elabels.is_empty()
        || srows.len() != elabels.len() + 1
        || elabels.iter().zip(srows.iter()).any(|(l, r)| *r != format!("{}\tsurvived", l))
        || format!("{}\n", srows[srows.len() - 1]) != SURVIVE_LAST
        || !elabels.iter().all(|l| seen.insert(*l))
    {
        eprintln!("CHECK FAIL rush00_fixtures: edge_cases.tsv and survive.txt disagree");
        fails += 1;
    }
    if file("putchar.txt").as_deref() != Some(PUTCHAR) {
        eprintln!("CHECK FAIL rush00_fixtures: putchar.txt");
        fails += 1;
    }
    for (path, bytes) in pictures {
        let rows: Vec<&[u8]> = bytes.split(|&b| b == b'\n').collect();
        let (x, y) = (DEFENSE.0 as usize, DEFENSE.1 as usize);
        // y rows of x characters, each ended by a newline: y + 1 pieces, the
        // last one empty.
        if rows.len() != y + 1 || !rows[y].is_empty() || rows[..y].iter().any(|r| r.len() != x) {
            eprintln!("CHECK FAIL rush00_fixtures {} is not {} rows of {}", path, y, x);
            fails += 1;
        }
    }

    let mut rng = Rng::new(1);
    let edges = edge_cases(&mut rng, 2000);
    for &(x, y) in &edges {
        // never two big positives: that is a legitimately enormous rectangle,
        // not a bug to catch
        if (x > 200 && y > 0) || (y > 200 && x > 0) {
            eprintln!("CHECK FAIL rush edge_cases too big ({}, {})", x, y);
            fails += 1;
        }
    }
    for &(x, y) in &[(0, 0), (i32::MIN, 3), (3, i32::MIN), (i32::MAX, 0), (0, i32::MAX)] {
        if !edges.contains(&(x, y)) {
            eprintln!("CHECK FAIL rush edge_cases missing ({}, {})", x, y);
            fails += 1;
        }
    }
    fails
}

/// Decode `esc()` — self-check only, to prove the escape is lossless.
fn unesc(s: &str) -> Vec<u8> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] != b'\\' {
            out.push(b[i]);
            i += 1;
        } else if i + 1 < b.len() && b[i + 1] == b'\\' {
            out.push(b'\\');
            i += 2;
        } else if i + 1 < b.len() && b[i + 1] == b'n' {
            out.push(b'\n');
            i += 2;
        } else if i + 3 < b.len() && b[i + 1] == b'x' {
            let hex = std::str::from_utf8(&b[i + 2..i + 4]).unwrap_or("00");
            out.push(u8::from_str_radix(hex, 16).unwrap_or(0));
            i += 4;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    out
}
