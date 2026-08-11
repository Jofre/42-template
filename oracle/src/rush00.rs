//! Rush00 (c-piscine-rush-00) references: the five rectangle variants of `void rush(int x, int y)`.
//!
//! Line formats (see oracle/README.md):
//!   rush_v0 .. rush_v4            <x>\t<y>\t<escaped-rectangle>
//!   rush_v0_edge .. rush_v4_edge  <x>\t<y>\t<escaped-rectangle>   (degenerate sizes)
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

use crate::common::Rng;
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
    for &(x, y) in &[(5, 3), (5, 1), (1, 1), (1, 5), (4, 4), (123, 42)] {
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
/// (tests/ex00/cases.tsv + expected_rush0N.txt, both generated from here so the
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

/// `rush_vN`, `rush_vN_edge` and `rush_vN_fixed` for N in 0..=4.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
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
