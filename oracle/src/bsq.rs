//! BSQ (c-piscine-bsq) reference: the biggest square of empty cells on a map.
//!
//! Line formats (see oracle/README.md) — one shape for all three arms:
//!   bsq_maps    <tag>\t<side>\t<top>\t<left>\t<escaped-file>\t<escaped-expected>
//!   bsq_errors  same shape; tag is err:<slug>, side/top/left are -1
//!   bsq_mixed   same shape; a seeded interleave of the two, for the multi-file mode
//!
//! Both blobs are WHOLE FILES carried on one corpus line, escaped by
//! common::esc_posix — printable ASCII raw, and anything else as "\0NNN" in
//! OCTAL, never rush00's "\xHH". The consumer is tools/bsq_check.sh running
//! under /bin/sh, which is dash here, and dash's `printf %b` does not know
//! "\xHH": it prints the four bytes back literally. The error arm really does
//! emit control bytes -- "three different PRINTABLE characters" is one of the
//! subject's own validity rules, so a non-printable among them is an error case
//! that has to be generated -- which makes the octal form a correctness
//! requirement rather than a preference. See common.rs for the measurement.
//!
//! THE TIE RULE IS THE EXERCISE. Among the squares of maximal side the subject
//! fixes the answer: closest to the TOP first, then the one most to the LEFT.
//! The DP below scans bottom-right corners in row-major order and takes the
//! FIRST STRICT maximum, which is equivalent -- but only because every
//! candidate shares the same side, so (top, left) = (bottom - k + 1, right - k
//! + 1) is monotone in the corner. Relax that `>` to `>=` and an all-empty 2x3
//! map answers (0,1) instead of (0,0). check() holds this against an
//! independently written brute force over EVERY map of at most 12 cells,
//! because exhaustion is the only thing that proves a tie rule.
//!
//! A MAP WITH NO EMPTY CELL prints unchanged. Its side is 0, so there is no
//! square to draw; and it is a VALID file by the subject's own definition (all
//! its characters are declared, all lines are the same length, at least one
//! cell), so "map error" -- which the subject reserves for an invalid file --
//! is textually excluded. The corpus carries such maps deliberately: they are
//! what catches a program that answers "map error" whenever it finds nothing.
//!
//! ------------------------------------------------------------------------
//! WHAT THIS REFERENCE REFUSES TO DECIDE
//!
//! The subject's "Definition of a valid file" settles more than most, which is
//! why -- unlike rush-02's -- this arm may gate. It does not settle everything,
//! and the generator emits none of the following IN EITHER DIRECTION. Each is a
//! question the subject answers twice, or not at all:
//!
//!   * The FULL character appearing in a map body. The description says the map
//!     "is made up of lines containing empty characters and obstacle
//!     characters"; the validity list says "the characters on the map can only
//!     be those introduced in the first line", which is all three. Both are
//!     literal. This is the one most likely to be added later "because it is
//!     obviously an error". It is not obviously anything.
//!   * MORE body lines than the count declares. Fewer is forced (the promised
//!     map is not there); more has two readings -- read the declared number and
//!     answer, or call the file a liar.
//!   * A MISSING FINAL NEWLINE after the last row. "Lines are separated by the
//!     usual newline character" -- separated, not terminated.
//!   * Leading '+', leading zeros, or spaces around the count ("+9.ox",
//!     "09.ox", " 9.ox"). "A valid positive number" adjudicates none of them,
//!     and atoi and a hand-written parser disagree.
//!   * A count that overflows int. "Any valid int" hints at an error, but
//!     whether the PARSE or the line count produces the verdict is a second
//!     rule the subject never states.
//!   * Bytes 0x80..0xff among the three characters: isprint above 0x7f is
//!     locale-dependent. Only 0x01..0x1f and 0x7f are used for the
//!     non-printable case.
//!   * EXIT STATUS, on any path, and anything on STDERR. The subject pins
//!     "map error" to stdout and never mentions either.
//!   * CRLF line endings. Technically settled ('\r' is not printable, so it
//!     cannot be declared, so a body holding it is invalid) but it would read
//!     as a trick and diagnose no real defect.
//!
//! A nonexistent path, a directory and an unreadable file are settled ("map
//! error") but are not expressible in a corpus of file CONTENTS; they belong to
//! the argv cases in c-piscine-bsq/BUILD.bazel.

use crate::common::{esc_posix, sink, unesc_posix, Rng};
use std::io::{self, Write};

// --------------------------------------------------------------------- model

/// A parsed map: the three declared characters and an obstacle bitmap.
struct MapSpec {
    empty: u8,
    obstacle: u8,
    full: u8,
    /// `grid[r][c] == true` means obstacle.
    grid: Vec<Vec<bool>>,
}

impl MapSpec {
    fn rows(&self) -> usize {
        self.grid.len()
    }

    /// The whole file: `<count><empty><obstacle><full>\n` then one line per row.
    fn file(&self) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(self.rows().to_string().as_bytes());
        out.push(self.empty);
        out.push(self.obstacle);
        out.push(self.full);
        out.push(b'\n');
        for row in &self.grid {
            for &ob in row {
                out.push(if ob { self.obstacle } else { self.empty });
            }
            out.push(b'\n');
        }
        out
    }

    /// The expected stdout: the body with the square painted. The header line
    /// is NOT reprinted -- the subject's transcript does not.
    fn solved(&self, side: usize, top: usize, left: usize) -> Vec<u8> {
        let mut out = Vec::new();
        for (r, row) in self.grid.iter().enumerate() {
            for (c, &ob) in row.iter().enumerate() {
                let inside =
                    side > 0 && r >= top && r < top + side && c >= left && c < left + side;
                if inside {
                    out.push(self.full);
                } else {
                    out.push(if ob { self.obstacle } else { self.empty });
                }
            }
            out.push(b'\n');
        }
        out
    }
}

// ------------------------------------------------------------------- oracles

/// The reference: side of the biggest all-empty square, and its top-left cell.
///
/// dp[r][c] is the side of the biggest all-empty square whose BOTTOM-RIGHT cell
/// is (r, c). Row-major scan, strict `>`, so the first maximum wins -- see the
/// module header for why that is exactly "topmost, then leftmost".
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_bsq(grid: &[Vec<bool>]) -> (usize, usize, usize) {
    let rows = grid.len();
    let cols = if rows == 0 { 0 } else { grid[0].len() };
    let mut dp = vec![vec![0usize; cols]; rows];
    let (mut best, mut br, mut bc) = (0usize, 0usize, 0usize);
    for r in 0..rows {
        for c in 0..cols {
            if grid[r][c] {
                dp[r][c] = 0;
                continue;
            }
            let up = if r > 0 { dp[r - 1][c] } else { 0 };
            let le = if c > 0 { dp[r][c - 1] } else { 0 };
            let di = if r > 0 && c > 0 { dp[r - 1][c - 1] } else { 0 };
            let mut m = up;
            if le < m {
                m = le;
            }
            if di < m {
                m = di;
            }
            dp[r][c] = 1 + m;
            if dp[r][c] > best {
                best = dp[r][c];
                br = r;
                bc = c;
            }
        }
    }
    if best == 0 {
        (0, 0, 0)
    } else {
        (best, br + 1 - best, bc + 1 - best)
    }
}

/// The same answer, computed a completely different way, for check() only.
///
/// It shares no code path with o_bsq: it indexes by TOP-LEFT rather than
/// bottom-right, it re-scans the whole candidate block instead of recurring on
/// three neighbours, and it resolves ties by construction order instead of by a
/// comparison. Two formulations that disagree on none of ~35 000 exhaustively
/// enumerated maps is real evidence; one formulation asserted against itself is
/// not.
fn o_bsq_naive(grid: &[Vec<bool>]) -> (usize, usize, usize) {
    let rows = grid.len();
    let cols = if rows == 0 { 0 } else { grid[0].len() };
    let (mut best, mut bt, mut bl) = (0usize, 0usize, 0usize);
    for t in 0..rows {
        for l in 0..cols {
            let mut k = 0usize;
            while t + k + 1 <= rows && l + k + 1 <= cols {
                let n = k + 1;
                let mut clear = true;
                for row in grid.iter().skip(t).take(n) {
                    for &ob in row.iter().skip(l).take(n) {
                        if ob {
                            clear = false;
                            break;
                        }
                    }
                    if !clear {
                        break;
                    }
                }
                if !clear {
                    break;
                }
                k = n;
            }
            if k > best {
                best = k;
                bt = t;
                bl = l;
            }
        }
    }
    (best, bt, bl)
}

/// Is there ANY all-empty square of side `side` anywhere? Used by check() to
/// assert maximality independently of both solvers.
fn any_square_of(grid: &[Vec<bool>], side: usize) -> bool {
    if side == 0 {
        return true;
    }
    let rows = grid.len();
    let cols = if rows == 0 { 0 } else { grid[0].len() };
    if side > rows || side > cols {
        return false;
    }
    for t in 0..=(rows - side) {
        for l in 0..=(cols - side) {
            let mut clear = true;
            for row in grid.iter().skip(t).take(side) {
                for &ob in row.iter().skip(l).take(side) {
                    if ob {
                        clear = false;
                        break;
                    }
                }
                if !clear {
                    break;
                }
            }
            if clear {
                return true;
            }
        }
    }
    false
}

// ------------------------------------------------------------------- records

/// One corpus record.
struct Case {
    tag: String,
    side: i64,
    top: i64,
    left: i64,
    file: Vec<u8>,
    expected: Vec<u8>,
}

fn ok_case(m: &MapSpec) -> Case {
    let (side, top, left) = o_bsq(&m.grid);
    Case {
        tag: "ok".to_string(),
        side: side as i64,
        top: if side == 0 { -1 } else { top as i64 },
        left: if side == 0 { -1 } else { left as i64 },
        file: m.file(),
        expected: m.solved(side, top, left),
    }
}

fn err_case(slug: &str, file: Vec<u8>) -> Case {
    Case {
        tag: format!("err:{}", slug),
        side: -1,
        top: -1,
        left: -1,
        file,
        expected: b"map error\n".to_vec(),
    }
}

fn emit(w: &mut impl Write, c: &Case) {
    let _ = writeln!(
        w,
        "{}\t{}\t{}\t{}\t{}\t{}",
        c.tag,
        c.side,
        c.top,
        c.left,
        esc_posix(&c.file),
        esc_posix(&c.expected)
    );
}

// ---------------------------------------------------------------- map builders

/// A map from row strings, where `#` marks an obstacle and anything else is
/// empty. Only for hand-written cases -- the characters come from `chars`.
fn from_rows(rows: &[&str], chars: (u8, u8, u8)) -> MapSpec {
    MapSpec {
        empty: chars.0,
        obstacle: chars.1,
        full: chars.2,
        grid: rows
            .iter()
            .map(|r| r.bytes().map(|b| b == b'#').collect())
            .collect(),
    }
}

fn uniform(rows: usize, cols: usize, obstacle: bool, chars: (u8, u8, u8)) -> MapSpec {
    MapSpec {
        empty: chars.0,
        obstacle: chars.1,
        full: chars.2,
        grid: vec![vec![obstacle; cols]; rows],
    }
}

const DOT_OX: (u8, u8, u8) = (b'.', b'o', b'x');

/// The subject's own example, chapter III. 9 rows, 27 columns; the answer is a
/// 7x7 square at row 0, column 5, and check() holds the rendered output against
/// the transcript printed in the PDF.
fn subject_example() -> MapSpec {
    from_rows(
        &[
            "...........................",
            "....#......................",
            "............#..............",
            "...........................",
            "....#......................",
            "...............#...........",
            "...........................",
            "......#..............#.....",
            "..#.......#................",
        ],
        DOT_OX,
    )
}

// --------------------------------------------------------------- valid corpus

/// The structured head: emitted whatever `count` says. `count` only ever RAISES
/// a corpus here, by growing the random tail -- the repo-wide policy.
fn ok_head() -> Vec<MapSpec> {
    let mut out: Vec<MapSpec> = Vec::new();

    // 1. The subject's own example, first, so every corpus covers it.
    out.push(subject_example());

    // 2. Degenerate shapes: one cell, one row, one column, each all-empty and
    //    all-obstacle, plus a single obstacle walked along the line. These are
    //    where the r-1 / c-1 guards in any DP break.
    for n in 1..=8usize {
        out.push(uniform(1, n, false, DOT_OX));
        out.push(uniform(1, n, true, DOT_OX));
        out.push(uniform(n, 1, false, DOT_OX));
        out.push(uniform(n, 1, true, DOT_OX));
        for k in 0..n {
            let mut m = uniform(1, n, false, DOT_OX);
            m.grid[0][k] = true;
            out.push(m);
            let mut m = uniform(n, 1, false, DOT_OX);
            m.grid[k][0] = true;
            out.push(m);
        }
    }

    // 3. Every all-empty and all-obstacle rectangle up to 8x8. The non-square
    //    all-empty ones are not filler: each is a live tie, and every R != C
    //    pair separates a strict `>` from a `>=`.
    for r in 1..=8usize {
        for c in 1..=8usize {
            out.push(uniform(r, c, false, DOT_OX));
            out.push(uniform(r, c, true, DOT_OX));
        }
    }

    // 4. THE TIE BATTERY -- what distinguishes this corpus from a random one.
    //    The first pair is the one that separates "top beats left" from "left
    //    beats top": two 3x3 squares fit, one at (0,5) and one at (2,0), and
    //    the subject picks the higher one. Its transpose flips the answer, so a
    //    program with the rule backwards fails one of the two whichever way it
    //    is wrong.
    let top_beats_left = from_rows(
        &["#####...", "#####...", "...##...", "...#####", "...#####"],
        DOT_OX,
    );
    let transposed = {
        let g = &top_beats_left.grid;
        let (r, c) = (g.len(), g[0].len());
        MapSpec {
            empty: b'.',
            obstacle: b'o',
            full: b'x',
            grid: (0..c).map(|j| (0..r).map(|i| g[i][j]).collect()).collect(),
        }
    };
    out.push(top_beats_left);
    out.push(transposed);

    //    Two equal squares side by side -> leftmost wins.
    out.push(from_rows(&["..#..", "..#..", "..#.."], DOT_OX));
    //    Two equal squares stacked -> topmost wins.
    out.push(from_rows(&["...", "...", "###", "...", "..."], DOT_OX));
    //    Overlapping maximal squares offset by one, each direction.
    out.push(from_rows(&["....", "....", "....", "...."], DOT_OX));
    out.push(from_rows(&["#...", "....", "....", "...."], DOT_OX));
    out.push(from_rows(&["...#", "....", "....", "...."], DOT_OX));
    out.push(from_rows(&["....", "....", "....", "#..."], DOT_OX));
    out.push(from_rows(&["....", "....", "....", "...#"], DOT_OX));
    //    A near-miss: the lower-right block would be 4x4 but for one corner
    //    obstacle, so a solver that stops at the first candidate it grows takes
    //    the wrong one.
    out.push(from_rows(
        &["........", "..###...", "..###...", "........", "........", ".......#"],
        DOT_OX,
    ));

    // 5. Edge-touching: the unique maximal square flush against each edge and
    //    each corner, and one strictly interior.
    let blockers: [&[&str]; 5] = [
        &["....", "....", "####", "####"],
        &["####", "####", "....", "...."],
        &["..##", "..##", "..##", "..##"],
        &["##..", "##..", "##..", "##.."],
        &["#####", "#...#", "#...#", "#...#", "#####"],
    ];
    for b in blockers {
        out.push(from_rows(b, DOT_OX));
    }

    // 6. CHARACTER-SET SWEEP. The subject legalises space and digits among the
    //    three, and the count is "all other characters in front of them" -- so
    //    "1123" is one line with characters '1','2','3', not a count of 1123.
    //    A parser that runs atoi over the whole first line dies here.
    let sweeps: [(u8, u8, u8); 8] = [
        (b'.', b'o', b'x'),
        (b' ', b'o', b'x'), // empty is a space: kills anything that trims
        (b'1', b'2', b'3'), // header "1123" for one row
        (b'0', b'1', b'2'),
        (b'.', b'\\', b'x'), // backslash obstacle: exercises our own escape
        (b'.', b'%', b'x'),  // printf-hostile bytes, passed as data not format
        (b'.', b'$', b'`'),
        (b'.', b'o', b'5'), // a digit as full: output lines can look like a header
    ];
    for ch in sweeps {
        out.push(from_rows(&["....", ".#..", "....", "...."], ch));
        out.push(from_rows(&["...", "..."], ch));
    }

    // 7. Density ladder at the subject's own dimensions and a few larger, built
    //    deterministically so the head stays reproducible without the tail Rng.
    for (rows, cols) in [(9usize, 27usize), (20, 20), (30, 40), (12, 50)] {
        for step in [0usize, 17, 7, 3, 2] {
            let mut m = uniform(rows, cols, false, DOT_OX);
            if step > 0 {
                let mut n = 0usize;
                for r in 0..rows {
                    for c in 0..cols {
                        n += 1;
                        if n % step == 0 {
                            m.grid[r][c] = true;
                        }
                    }
                }
            }
            out.push(m);
        }
        out.push(uniform(rows, cols, true, DOT_OX));
    }

    out
}

/// Printable characters the random tail draws its triples from. Space and the
/// digits are in on purpose -- the subject names them explicitly.
const POOL: &[u8] = b".ox#*@+-_=/\\|<>[]{}()!?,;:'\"`~^&%$0123456789abcXYZ ";

fn draw_chars(rng: &mut Rng) -> (u8, u8, u8) {
    loop {
        let a = POOL[rng.below(POOL.len())];
        let b = POOL[rng.below(POOL.len())];
        let c = POOL[rng.below(POOL.len())];
        if a != b && b != c && a != c {
            return (a, b, c);
        }
    }
}

/// Area cap for the GATING corpus. Every case is a fork+exec, and a correct but
/// naive O(R*C*k^2) solution is not something the subject forbids -- "does it
/// scale" is what the perf and cycles layers are for, at level 4. Reddening a
/// submission over it would be inventing a requirement.
const MAX_AREA: usize = 2500;

fn ok_tail(rng: &mut Rng, want: usize, out: &mut Vec<MapSpec>) {
    let mut draws = 0usize;
    while out.len() < want && draws < 40 * want + 1000 {
        draws += 1;
        let rows = 1 + rng.below(30);
        let cols = 1 + rng.below(30);
        if rows * cols > MAX_AREA {
            continue;
        }
        let chars = draw_chars(rng);
        // Density drawn from a ladder rather than uniformly: the interesting
        // maps are the sparse ones (big squares, many ties) and the dense ones
        // (side 0), and a uniform draw lands in the dull middle.
        let pct = [0usize, 3, 10, 25, 50, 75, 100][rng.below(7)];
        let mut m = uniform(rows, cols, false, chars);
        for r in 0..rows {
            for c in 0..cols {
                if rng.below(100) < pct {
                    m.grid[r][c] = true;
                }
            }
        }
        out.push(m);
    }
}

// ------------------------------------------------------------- invalid corpus

/// Every way the subject SETTLES that a file is invalid. One slug each; the
/// slug travels in the tag so a failure can say which rule was broken.
///
/// Two construction rules: the defect is not always on the first line (a
/// validator that checks only lines 1 and 2 has to be caught), and the random
/// tail MUTATES a valid map rather than hand-typing more files, so the invalid
/// corpus keeps the size and character variety of the valid one.
fn err_head() -> Vec<Case> {
    let mut out = Vec::new();
    let body4 = "....\n....\n....\n....\n";

    out.push(err_case("empty_file", Vec::new()));
    out.push(err_case("header_only", b"9.ox".to_vec()));
    out.push(err_case("header_short", b"\n".to_vec()));
    out.push(err_case("header_short", b"x\n....\n".to_vec()));
    out.push(err_case("header_short", b"ox\n....\n".to_vec()));
    out.push(err_case("no_digits", format!(".ox\n{}", body4).into_bytes()));
    out.push(err_case("count_junk", format!("9a.ox\n{}", body4).into_bytes()));
    out.push(err_case("count_junk", format!("9-2.ox\n{}", body4).into_bytes()));
    out.push(err_case("count_zero", format!("0.ox\n{}", body4).into_bytes()));
    out.push(err_case("count_negative", format!("-3.ox\n{}", body4).into_bytes()));
    out.push(err_case("chars_repeat", format!("4..x\n{}", body4).into_bytes()));
    out.push(err_case("chars_repeat", format!("4.oo\n{}", body4).into_bytes()));
    out.push(err_case("chars_repeat", format!("4xxx\n{}", body4).into_bytes()));

    // A non-printable among the three. 0x01..0x1f and 0x7f only -- see the
    // header for why 0x80.. is left alone.
    for bad in [0x01u8, 0x07, 0x1f, 0x7f] {
        let mut f = Vec::new();
        f.extend_from_slice(b"4.o");
        f.push(bad);
        f.push(b'\n');
        f.extend_from_slice(body4.as_bytes());
        out.push(err_case("chars_nonprintable", f));
    }

    out.push(err_case("no_body", b"4.ox\n".to_vec()));
    out.push(err_case("zero_width", b"3.ox\n\n\n\n".to_vec()));

    // Ragged lines, defect placed first / middle / last so a validator that
    // stops after two lines is caught.
    out.push(err_case("ragged_first", b"4.ox\n...\n....\n....\n....\n".to_vec()));
    out.push(err_case("ragged_mid", b"4.ox\n....\n...\n....\n....\n".to_vec()));
    out.push(err_case("ragged_last", b"4.ox\n....\n....\n....\n.....\n".to_vec()));

    // A character that is none of the three, at the first cell, an interior
    // cell, and the last cell.
    out.push(err_case("undeclared_char", b"4.ox\nZ...\n....\n....\n....\n".to_vec()));
    out.push(err_case("undeclared_char", b"4.ox\n....\n..Z.\n....\n....\n".to_vec()));
    out.push(err_case("undeclared_char", b"4.ox\n....\n....\n....\n...Z\n".to_vec()));

    // Declared more lines than the file holds: the promised map is not there.
    out.push(err_case("count_short", b"9.ox\n....\n....\n".to_vec()));
    out.push(err_case("count_short", b"2.ox\n....\n".to_vec()));

    out
}

/// The 16 slugs the head covers. check() asserts every one appears, so a class
/// cannot silently fall out of the corpus.
const ERR_SLUGS: [&str; 16] = [
    "empty_file",
    "header_only",
    "header_short",
    "no_digits",
    "count_junk",
    "count_zero",
    "count_negative",
    "chars_repeat",
    "chars_nonprintable",
    "no_body",
    "zero_width",
    "ragged_first",
    "ragged_mid",
    "ragged_last",
    "undeclared_char",
    "count_short",
];

/// Mutate a valid map into an invalid file, one randomly chosen way.
fn mutate_invalid(rng: &mut Rng, m: &MapSpec) -> Case {
    let f = m.file();
    let text = String::from_utf8_lossy(&f).to_string();
    let mut lines: Vec<String> = text.split('\n').map(|s| s.to_string()).collect();
    // split('\n') on a trailing newline leaves a final empty element.
    if lines.last().map(|s| s.is_empty()).unwrap_or(false) {
        lines.pop();
    }
    if lines.len() < 2 {
        return err_case("no_body", f);
    }
    let body_lines = lines.len() - 1;
    let rejoin = |v: &Vec<String>| -> Vec<u8> {
        let mut s = v.join("\n");
        s.push('\n');
        s.into_bytes()
    };

    match rng.below(6) {
        0 => {
            // count -> 0
            let head = &lines[0];
            let three = &head[head.len() - 3..];
            lines[0] = format!("0{}", three);
            err_case("count_zero", rejoin(&lines))
        }
        1 => {
            // make two of the three characters equal
            let head = lines[0].clone();
            let n = head.len();
            let stem = &head[..n - 3];
            let c1 = &head[n - 3..n - 2];
            lines[0] = format!("{}{}{}{}", stem, c1, c1, &head[n - 1..]);
            err_case("chars_repeat", rejoin(&lines))
        }
        2 => {
            // drop one character from a body line
            let k = 1 + rng.below(body_lines);
            if lines[k].is_empty() {
                return err_case("zero_width", rejoin(&lines));
            }
            lines[k].pop();
            err_case("ragged_mid", rejoin(&lines))
        }
        3 => {
            // put an undeclared character in a body cell
            let k = 1 + rng.below(body_lines);
            if lines[k].is_empty() {
                return err_case("zero_width", rejoin(&lines));
            }
            let pos = rng.below(lines[k].len());
            let mut b = lines[k].clone().into_bytes();
            // pick something none of the three is
            let mut cand = b'Z';
            while cand == m.empty || cand == m.obstacle || cand == m.full {
                cand = cand.wrapping_add(1);
                if cand < 0x20 || cand > 0x7e {
                    cand = b'A';
                }
            }
            b[pos] = cand;
            lines[k] = String::from_utf8_lossy(&b).to_string();
            err_case("undeclared_char", rejoin(&lines))
        }
        4 => {
            // remove the last body line, leaving fewer than declared
            lines.pop();
            if lines.len() < 2 {
                return err_case("no_body", rejoin(&lines));
            }
            err_case("count_short", rejoin(&lines))
        }
        _ => {
            // a non-printable among the three
            let head = lines[0].clone();
            let n = head.len();
            let mut f2 = Vec::new();
            f2.extend_from_slice(head[..n - 1].as_bytes());
            f2.push(0x01 + rng.below(0x1f) as u8);
            f2.push(b'\n');
            for l in lines.iter().skip(1) {
                f2.extend_from_slice(l.as_bytes());
                f2.push(b'\n');
            }
            err_case("chars_nonprintable", f2)
        }
    }
}

// ----------------------------------------------------------------- generators

fn gen_maps(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut maps = ok_head();
    ok_tail(&mut rng, count, &mut maps);
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    for m in &maps {
        emit(&mut w, &ok_case(m));
    }
    let _ = w.flush();
}

fn gen_errors(seed: u64, count: usize) {
    let mut rng = Rng::new(seed ^ 0x5b5);
    let mut cases = err_head();
    let mut maps: Vec<MapSpec> = Vec::new();
    ok_tail(&mut rng, count, &mut maps);
    for m in &maps {
        if cases.len() >= count.max(ERR_SLUGS.len()) {
            break;
        }
        cases.push(mutate_invalid(&mut rng, m));
    }
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    for c in &cases {
        emit(&mut w, c);
    }
    let _ = w.flush();
}

fn gen_mixed(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut maps = ok_head();
    ok_tail(&mut rng, count, &mut maps);
    let oks: Vec<Case> = maps.iter().map(ok_case).collect();

    let mut ergn = Rng::new(seed ^ 0x5b5);
    let mut errs = err_head();
    let mut emaps: Vec<MapSpec> = Vec::new();
    ok_tail(&mut ergn, count, &mut emaps);
    for m in &emaps {
        errs.push(mutate_invalid(&mut ergn, m));
    }

    // A SEEDED merge, never a fixed alternation: any fixed period has a stride
    // that erases it, and the multi-file mode groups K consecutive records --
    // so a strict A/B corpus sliced at K=2 would be all-valid or all-invalid
    // groups. rush01.rs documents the same trap.
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    let (mut i, mut j) = (0usize, 0usize);
    let mut pick = Rng::new(seed ^ 0xA5A5);
    while i < oks.len() || j < errs.len() {
        let take_ok = if i >= oks.len() {
            false
        } else if j >= errs.len() {
            true
        } else {
            pick.below(2) == 0
        };
        if take_ok {
            emit(&mut w, &oks[i]);
            i += 1;
        } else {
            emit(&mut w, &errs[j]);
            j += 1;
        }
    }
    let _ = w.flush();
}

pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "bsq_maps" => gen_maps(seed, count),
        "bsq_errors" => gen_errors(seed, count),
        "bsq_mixed" => gen_mixed(seed, count),
        _ => return false,
    }
    true
}

// ---------------------------------------------------------------- self-checks

pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- the subject's own transcript, verbatim from chapter III ----
    let m = subject_example();
    let (side, top, left) = o_bsq(&m.grid);
    if (side, top, left) != (7, 0, 5) {
        eprintln!(
            "CHECK FAIL bsq subject example: got side {} at ({}, {}), want 7 at (0, 5)",
            side, top, left
        );
        fails += 1;
    }
    let want_transcript = concat!(
        ".....xxxxxxx...............\n",
        "....oxxxxxxx...............\n",
        ".....xxxxxxxo..............\n",
        ".....xxxxxxx...............\n",
        "....oxxxxxxx...............\n",
        ".....xxxxxxx...o...........\n",
        ".....xxxxxxx...............\n",
        "......o..............o.....\n",
        "..o.......o................\n",
    );
    if m.solved(side, top, left) != want_transcript.as_bytes() {
        eprintln!("CHECK FAIL bsq subject example: rendered output differs from the subject");
        fails += 1;
    }
    if m.file() != b"9.ox\n...........................\n....o......................\n............o..............\n...........................\n....o......................\n...............o...........\n...........................\n......o..............o.....\n..o.......o................\n".to_vec() {
        eprintln!("CHECK FAIL bsq subject example: the FILE we emit is not the subject's");
        fails += 1;
    }

    // ---- the DP and an independent brute force agree, EXHAUSTIVELY ----
    //
    // Every map of at most 12 cells: all (rows, cols) with rows*cols <= 12, and
    // all 2^(rows*cols) obstacle patterns of each. ~35 000 maps. A tie rule is a
    // claim about WHICH of several equally-sized answers is chosen, and only
    // exhaustion over small maps can prove two formulations coincide on it.
    for rows in 1..=12usize {
        for cols in 1..=12usize {
            let cells = rows * cols;
            if cells > 12 {
                continue;
            }
            for mask in 0u32..(1u32 << cells) {
                let mut grid = vec![vec![false; cols]; rows];
                for k in 0..cells {
                    if mask & (1 << k) != 0 {
                        grid[k / cols][k % cols] = true;
                    }
                }
                let a = o_bsq(&grid);
                let b = o_bsq_naive(&grid);
                if a != b {
                    eprintln!(
                        "CHECK FAIL bsq {}x{} mask {}: dp {:?} vs brute force {:?}",
                        rows, cols, mask, a, b
                    );
                    fails += 1;
                    if fails > 20 {
                        sink(fails);
                        return fails;
                    }
                }
                // maximality, independently of both: no square one larger fits
                if any_square_of(&grid, a.0 + 1) {
                    eprintln!(
                        "CHECK FAIL bsq {}x{} mask {}: claimed {} but {} fits",
                        rows,
                        cols,
                        mask,
                        a.0,
                        a.0 + 1
                    );
                    fails += 1;
                }
            }
        }
    }

    // ---- the painting properties, over a seeded sweep ----
    let mut rng = Rng::new(0xB5B5);
    for _ in 0..4000 {
        let rows = 1 + rng.below(14);
        let cols = 1 + rng.below(14);
        let pct = rng.below(101);
        let mut m = uniform(rows, cols, false, DOT_OX);
        for r in 0..rows {
            for c in 0..cols {
                if rng.below(100) < pct {
                    m.grid[r][c] = true;
                }
            }
        }
        let (side, top, left) = o_bsq(&m.grid);
        let body: Vec<u8> = m.solved(0, 0, 0);
        let painted = m.solved(side, top, left);
        if body.len() != painted.len() {
            eprintln!("CHECK FAIL bsq painting changed the output length");
            fails += 1;
        }
        let diff = body
            .iter()
            .zip(painted.iter())
            .filter(|(a, b)| a != b)
            .count();
        if diff != side * side {
            eprintln!(
                "CHECK FAIL bsq painting changed {} cells, want {}",
                diff,
                side * side
            );
            fails += 1;
        }
        for (a, b) in body.iter().zip(painted.iter()) {
            if a != b && (*a != m.empty || *b != m.full) {
                eprintln!("CHECK FAIL bsq painting overwrote something that was not empty");
                fails += 1;
                break;
            }
        }
        if painted.last() != Some(&b'\n') {
            eprintln!("CHECK FAIL bsq painted output does not end in a newline");
            fails += 1;
        }
    }

    // ---- the escape is lossless, leaks no separator, and is OCTAL ----
    //
    // The last of those three is the one worth its two lines: someone
    // "unifying" this with rush00's hex escape would break the dash consumer
    // invisibly, because the failure only shows on a box whose /bin/sh is not
    // bash.
    let mut rng = Rng::new(7);
    for _ in 0..2000 {
        let n = rng.below(64);
        let raw: Vec<u8> = (0..n).map(|_| (1 + rng.below(255)) as u8).collect();
        let e = esc_posix(&raw);
        if unesc_posix(&e) != raw {
            eprintln!("CHECK FAIL bsq escape round-trip");
            fails += 1;
            break;
        }
        if e.contains('\n') || e.contains('\t') {
            eprintln!("CHECK FAIL bsq escape leaked a separator");
            fails += 1;
            break;
        }
        if e.contains("\\x") {
            eprintln!("CHECK FAIL bsq escape emitted a \\xHH form, which dash cannot decode");
            fails += 1;
            break;
        }
    }

    // ---- the generator's own contract ----
    let head = ok_head();
    if head.is_empty() {
        eprintln!("CHECK FAIL bsq ok_head is empty");
        fails += 1;
    }
    let zero_side = head.iter().any(|m| o_bsq(&m.grid).0 == 0);
    if !zero_side {
        eprintln!("CHECK FAIL bsq corpus has no side-0 map: 'always map error' would pass");
        fails += 1;
    }
    let changes = head.iter().any(|m| {
        let (s, t, l) = o_bsq(&m.grid);
        m.solved(s, t, l) != m.solved(0, 0, 0)
    });
    if !changes {
        eprintln!("CHECK FAIL bsq corpus has no map whose answer differs from its input: cat would pass");
        fails += 1;
    }
    let space_empty = head.iter().any(|m| m.empty == b' ');
    let backslash = head.iter().any(|m| m.obstacle == b'\\');
    let all_digits = head
        .iter()
        .any(|m| m.empty.is_ascii_digit() && m.obstacle.is_ascii_digit() && m.full.is_ascii_digit());
    if !space_empty || !backslash || !all_digits {
        eprintln!("CHECK FAIL bsq character sweep is missing space / backslash / all-digit triples");
        fails += 1;
    }
    for m in &head {
        if m.empty == m.obstacle || m.obstacle == m.full || m.empty == m.full {
            eprintln!("CHECK FAIL bsq a valid head map has two equal characters");
            fails += 1;
            break;
        }
    }

    // every error slug is actually produced
    let errs = err_head();
    for slug in ERR_SLUGS {
        if !errs.iter().any(|c| c.tag == format!("err:{}", slug)) {
            eprintln!("CHECK FAIL bsq error corpus never produces slug {}", slug);
            fails += 1;
        }
    }
    // and no record's fields can break the corpus format
    for c in head.iter().map(ok_case).chain(errs.into_iter()) {
        let f = esc_posix(&c.file);
        let e = esc_posix(&c.expected);
        if f.contains('\t') || f.contains('\n') || e.contains('\t') || e.contains('\n') {
            eprintln!("CHECK FAIL bsq a record field holds a raw separator");
            fails += 1;
            break;
        }
    }

    sink(fails);
    fails
}
