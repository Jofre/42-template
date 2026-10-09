//! BSQ (c-piscine-bsq) reference: the biggest square of empty cells on a map.
//!
//! Line formats (see oracle/README.md) — one shape for the four corpus arms:
//!   bsq_maps     <tag>\t<side>\t<top>\t<left>\t<escaped-file>\t<escaped-expected>
//!   bsq_errors   same shape; tag is err:<slug>, side/top/left are -1
//!   bsq_mixed    same shape; a seeded interleave of the two, for every transport
//!   bsq_readings same shape; the ONE reading this repo takes of the sentences
//!                the subject leaves open (see WHAT THIS REFERENCE REFUSES TO
//!                DECIDE), for the strict ex00_readings target only
//! and one that is not a corpus:
//!   bsq_fixtures <path under tests/ex00/>\t<escaped bytes>: every map and
//!                expected output the named cases in
//!                c-piscine/c-piscine-bsq/BUILD.bazel run, which
//!                ex00_oracle_fixtures holds the files there to
//!                (tools/oracle_fixtures.sh), so they cannot drift from this file
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
//!     usual newline character" -- separated, not terminated -- so the verdict
//!     is open. The OUTPUT is not: "map error" and a newline, or the solved map
//!     with every row terminated, and the basic case no_final_newline accepts
//!     exactly those two. bsq_readings takes one reading, the literal one:
//!     rows are separated, the last one needs no newline, the map is solved.
//!   * Leading '+', leading zeros, or spaces around the count ("+9.ox",
//!     "09.ox", " 9.ox", "9 .ox"). "A valid positive number" adjudicates none
//!     of them, and atoi and a hand-written parser disagree. bsq_readings
//!     takes one reading: the count field is decimal digits only, and its
//!     value is positive and fits an int -- so "09" is valid, and "+9", " 9"
//!     and "9 " are map error. check() asserts that no settled record holds
//!     one of these forms.
//!   * Bytes 0x80..0xff among the three characters: isprint above 0x7f is
//!     locale-dependent. Only 0x01..0x1f and 0x7f are used for the
//!     non-printable case.
//!   * EXIT STATUS, on any path, and anything on STDERR. The subject pins
//!     "map error" to stdout and never mentions either.
//!   * CRLF line endings. Technically settled ('\r' is not printable, so it
//!     cannot be declared, so a body holding it is invalid) but it would read
//!     as a trick and diagnose no real defect.
//!
//! A COUNT THAT OVERFLOWS INT is NOT on that list. "It can be any valid int"
//! makes a count past INT_MAX invalid, and over any body a test can hold the
//! body's own line count disagrees with it too, so every reading says "map
//! error" -- only a parse that WRAPS accepts it. count_overflow is built so
//! that the wrap lands exactly on the body's line count, in 32 and in 64 bits.
//!
//! A nonexistent path, a directory and an unreadable file are settled ("map
//! error") but are not expressible in a corpus of file CONTENTS; they belong to
//! the argv cases in c-piscine/c-piscine-bsq/BUILD.bazel.
//!
//! AN ERROR RECORD ISOLATES ITS RULE. A defect paired with a body whose length
//! disagrees with how a program would misread it is caught by the line-count
//! rule first, and the record then tests nothing it is named for: "9a.ox" over
//! four rows is rejected by a program that never looked at the "a" (it reads
//! 9, and there are 4 rows), and "-3.ox" over four rows by one that dropped
//! the sign (it reads 3). So each count slug's misread count -- the digits the
//! header starts with once a sign or a space before them is passed over,
//! exactly and wrapped to 32 and 64 bits -- equals the body's line count, and
//! check() asserts it for every count slug: count_zero, count_junk,
//! count_overflow and count_negative.

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
#[derive(Clone)]
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

/// Two 3x3 squares fit, one at (0,5) and one at (2,0): the subject's "closest
/// to the top of the map, then the one that is most to the left" picks the
/// first, and a rule applied the other way round picks the second. In the tie
/// battery below, and the named case `tie_top_first`.
fn top_beats_left() -> MapSpec {
    from_rows(
        &["#####...", "#####...", "...##...", "...#####", "...#####"],
        DOT_OX,
    )
}

/// One obstacle at (1,1) of a 4x4 map, under three given characters: the
/// character sweep's first shape, and the named cases `space_char` and
/// `digit_chars`.
fn sweep_shape(chars: (u8, u8, u8)) -> MapSpec {
    from_rows(&["....", ".#..", "....", "...."], chars)
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
    let top_beats_left = top_beats_left();
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
        out.push(sweep_shape(ch));
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

/// `want` more maps on `out`, past whatever is there: `count` sizes the
/// random tail, as in every oracle module. It used to fill `out` up to
/// `want` maps in all, and the head is 288, so a corpus asked for 60 maps
/// and one asked for 120 were the same 288.
fn ok_tail(rng: &mut Rng, want: usize, out: &mut Vec<MapSpec>) {
    let target = out.len() + want;
    let mut draws = 0usize;
    while out.len() < target && draws < 40 * want + 1000 {
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
    // Each count defect ISOLATES its rule (see the header): the count a program
    // that skips the rule would read is the body's own line count, so nothing
    // but that rule can reject the file. Junk after a count of 4, over four
    // rows; a count of 0 over no rows at all; counts that wrap to 4 in 32 bits
    // (2^32 + 4) and in 64 bits (2^64 + 4), over four rows; and -4 over four
    // rows, which a parse that drops the sign reads as 4.
    out.push(err_case("count_junk", format!("4a.ox\n{}", body4).into_bytes()));
    out.push(err_case("count_junk", format!("4-2.ox\n{}", body4).into_bytes()));
    out.push(err_case("count_zero", b"0.ox\n".to_vec()));
    out.push(err_case("count_overflow", format!("4294967300.ox\n{}", body4).into_bytes()));
    out.push(err_case(
        "count_overflow",
        format!("18446744073709551620.ox\n{}", body4).into_bytes(),
    ));
    out.push(err_case("count_negative", format!("-4.ox\n{}", body4).into_bytes()));
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

/// The 17 slugs the head covers. check() asserts every one appears, so a class
/// cannot silently fall out of the corpus.
const ERR_SLUGS: [&str; 17] = [
    "empty_file",
    "header_only",
    "header_short",
    "no_digits",
    "count_junk",
    "count_zero",
    "count_overflow",
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

    match rng.below(7) {
        0 => {
            // count -> 0, and the body with it: a count of 0 over the map's
            // rows would be rejected by the line count first (see the header,
            // AN ERROR RECORD ISOLATES ITS RULE).
            let head = &lines[0];
            let three = &head[head.len() - 3..];
            err_case("count_zero", format!("0{}\n", three).into_bytes())
        }
        6 => {
            // junk after the TRUE count: only a program that reads past the
            // digits sees it. A letter, never '+', a space or a digit, which
            // are the open forms bsq_readings holds.
            let head = lines[0].clone();
            let n = head.len();
            let junk = (b'a' + rng.below(26) as u8) as char;
            lines[0] = format!("{}{}{}", &head[..n - 3], junk, &head[n - 3..]);
            err_case("count_junk", rejoin(&lines))
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
        2 if body_lines >= 2 => {
            // drop one character from a body line. Only with a second line
            // to be ragged against: a ONE-row map with a character fewer is
            // just a narrower valid map, which this arm once filed as
            // err:ragged_mid and a correct program then "failed" (the
            // stdin transport's longer tail met one). check() now holds
            // every record to the validity list (valid_under).
            let k = 1 + rng.below(body_lines);
            if lines[k].is_empty() {
                return err_case("zero_width", rejoin(&lines));
            }
            lines[k].pop();
            err_case("ragged_mid", rejoin(&lines))
        }
        2 | 3 => {
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

// ------------------------------------------------------------ readings corpus

/// The file of `m` with its count written as `before` + count + `after`: the
/// forms "a valid positive number" does not settle.
fn with_count(m: &MapSpec, before: &str, after: &str) -> Vec<u8> {
    let f = m.file();
    let digits = m.rows().to_string();
    let mut out = Vec::new();
    out.extend_from_slice(before.as_bytes());
    out.extend_from_slice(digits.as_bytes());
    out.extend_from_slice(after.as_bytes());
    out.extend_from_slice(&f[digits.len()..]);
    out
}

/// A valid-map case whose FILE is `file` rather than `m.file()`: the answer is
/// still `m`'s, which is what the reading says the file means. Tagged
/// "ok:<slug>", the open form it holds, so a failure can say which question it
/// is about (tools/bsq_check.sh words each slug); a settled record is "ok".
fn ok_case_as(slug: &str, m: &MapSpec, file: Vec<u8>) -> Case {
    let mut c = ok_case(m);
    c.tag = format!("ok:{}", slug);
    c.file = file;
    c
}

/// THE READINGS (bsq_readings): the sentences the subject leaves open, each
/// under the ONE reading this repo takes (the header's list, and
/// c-piscine/c-piscine-bsq/BUILD.bazel). Never mixed into the settled arms:
/// a program taking the other reading fails only ex00_readings, at strict.
///
///   the count   decimal digits only, positive, fitting an int: a leading zero
///               is valid ("09"); a '+', or a space before or after the digits,
///               is map error
///   the end     "Lines are separated by the usual newline character": the
///               last row needs no newline of its own, and the map is solved
///               (every OUTPUT row still ends in one)
///
/// Over five maps, one of them all obstacles (side 0) and the subject's own,
/// so the floors bsq_check.sh holds every corpus to are met. Every record
/// names its form in its tag -- ok:count_leading_zero, ok:no_final_newline,
/// err:count_plus, err:count_space_before, err:count_space_after -- and
/// bsq_check.sh --readings refuses a record that does not, or one whose form
/// it has no sentence for: a failure here has to say which question it is.
fn readings() -> Vec<Case> {
    let bases = [
        subject_example(),
        uniform(3, 3, true, DOT_OX),
        sweep_shape(DOT_OX),
        uniform(2, 5, false, DOT_OX),
        top_beats_left(),
    ];
    let mut out = Vec::new();
    for m in &bases {
        out.push(ok_case_as("count_leading_zero", m, with_count(m, "0", "")));
        out.push(err_case("count_plus", with_count(m, "+", "")));
        out.push(err_case("count_space_before", with_count(m, " ", "")));
        out.push(err_case("count_space_after", with_count(m, "", " ")));
        let mut f = m.file();
        f.pop();
        out.push(ok_case_as("no_final_newline", m, f));
    }
    out
}

// ------------------------------------------------------------ named fixtures

/// The `nth` record of `slug` in the error head: a named case's map IS a
/// corpus record, so the two cannot say different things about one rule.
fn err_file(slug: &str, nth: usize) -> Vec<u8> {
    let tag = format!("err:{}", slug);
    err_head()
        .into_iter()
        .filter(|c| c.tag == tag)
        .nth(nth)
        .map(|c| c.file)
        .unwrap_or_default()
}

/// THE NAMED FIXTURES (bsq_fixtures): every file the named cases in
/// c-piscine/c-piscine-bsq/BUILD.bazel read, as (path under tests/ex00/,
/// bytes). ex00_oracle_fixtures fails when a file there differs from this, and
/// `bazel run //c-piscine/c-piscine-bsq:ex00_oracle_fixtures -- --write`
/// rewrites them. An invalid map is an error-head record, a valid one a map
/// this file builds, and every expected output is rendered here.
fn fixtures() -> Vec<(String, Vec<u8>)> {
    let mut out: Vec<(String, Vec<u8>)> = Vec::new();
    let map_error = b"map error\n".to_vec();
    let solved = |m: &MapSpec| {
        let (side, top, left) = o_bsq(&m.grid);
        m.solved(side, top, left)
    };
    let valid = |out: &mut Vec<(String, Vec<u8>)>, stem: &str, m: &MapSpec| {
        out.push((format!("fixtures/{}.map", stem), m.file()));
        out.push((format!("{}.txt", stem), solved(m)));
    };
    let subject = subject_example();
    let one = uniform(1, 1, false, DOT_OX);
    valid(&mut out, "subject", &subject);
    valid(&mut out, "one", &one);
    valid(&mut out, "nosquare", &uniform(3, 3, true, DOT_OX));
    // The characters the subject names outright: a space, and digits (the
    // last three characters of the first line are the map's, the rest the
    // count -- "4123" is four rows of '1', '2' and '3').
    valid(&mut out, "space_char", &sweep_shape((b' ', b'o', b'x')));
    valid(&mut out, "digit_chars", &sweep_shape((b'1', b'2', b'3')));
    valid(&mut out, "tie_top_first", &top_beats_left());
    // Taller and wider than nine, which no other fixture is (finding 113):
    // record 296 of `oracle bsq_maps 1 400`, tall_map's, 20 rows of 23.
    let mut rng = Rng::new(1);
    let mut maps = ok_head();
    ok_tail(&mut rng, 400 - maps.len(), &mut maps);
    valid(&mut out, "tall", &maps[295]);

    // Invalid, one validity rule each. Each is a corpus record.
    for (stem, slug, nth) in [
        ("dupchars", "chars_repeat", 1),
        ("ragged", "ragged_last", 0),
        ("undeclared", "undeclared_char", 1),
        ("count_short", "count_short", 0),
        ("count_zero", "count_zero", 0),
        ("nonprintable", "chars_nonprintable", 0),
        ("zero_width", "zero_width", 0),
    ] {
        out.push((format!("fixtures/{}.map", stem), err_file(slug, nth)));
    }
    out.push(("maperror.txt".to_string(), map_error.clone()));

    // Two files in one run: one empty line BETWEEN the outputs.
    let mut two = solved(&subject);
    two.push(b'\n');
    two.extend_from_slice(&map_error);
    out.push(("two.txt".to_string(), two));
    let mut errthenmap = map_error.clone();
    errthenmap.push(b'\n');
    errthenmap.extend_from_slice(&solved(&one));
    out.push(("errthenmap.txt".to_string(), errthenmap));

    // No final newline: the case accepts "map error" or this, the map solved
    // with every row terminated (the header's list says why both).
    let nonl = from_rows(&["....", "..#.", "...."], DOT_OX);
    let mut f = nonl.file();
    f.pop();
    out.push(("fixtures/no_final_newline.map".to_string(), f));
    out.push(("no_final_newline.txt".to_string(), solved(&nonl)));
    out
}

fn gen_fixtures() {
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    for (path, bytes) in fixtures() {
        let _ = writeln!(w, "{}\t{}", path, esc_posix(&bytes));
    }
    let _ = w.flush();
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

fn gen_readings() {
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    for c in &readings() {
        emit(&mut w, c);
    }
    let _ = w.flush();
}

// ----------------------------------------------------------- the big maps

/// The maps no seeded corpus reaches: every map above is at most 30 a side
/// (MAX_AREA, 2500 cells), and the hand-written fixtures at most 9 rows, so a
/// program that kept its map in room of a fixed size (a 64 x 64 array, one
/// read() of 64 KiB, a line buffer of 4096, a row count in 16 bits) passed
/// every layer (finding 041). Each map below is past one such capacity, and
/// the answers come from the same o_bsq as every other record. They are two
/// lists, because the subject sets no time limit and some of these maps cost
/// a slow program far more than others (the owner's ruling R4, 2026-10-02):
///
/// `bsq_long`, LONG_MAPS, for basic: maps whose biggest square is at most one
/// cell a side, so that finding it costs any program that reads the map a
/// constant per cell, whatever its method. Every capacity above is passed by
/// one of them:
///
///   1 x 70000    one line longer than 64 KiB, its only empty cell the last
///                (past a line buffer, one read() of 64 KiB, 64 columns);
///   70000 x 1    more lines than 16 bits count, its only empty cell the last
///                (past 64 rows, and a file past 64 KiB);
///   300 x 300    no empty cell at all: printed unchanged, and the record
///                that keeps "map error whenever nothing is found" from
///                passing (bsq_check.sh's floor).
///
/// `bsq_big`, BIG_MAPS, for strict: maps where the method matters, so a
/// correct program that is slow enough may not finish them in the time a
/// test has. Its target says "did not finish", never that the answer is
/// wrong (bsq_check.sh):
///
///   1000 x 1000  a million cells, sparse enough (one obstacle in 1000) that
///                the biggest square is well over 64 a side;
///   10000 x 100  ten thousand lines, a five-digit count on the first line;
///   1000 x 1000  a million cells and three obstacles: the biggest square is
///                hundreds of cells a side, where a method that grows each
///                candidate one cell at a time and reads the whole square
///                at every step does work of the fifth power of the side
///                (finding 041c). The two maps above hold squares of 84
///                and 20 a side, and such a solver finished each in about
///                13 seconds (the mutation run of 2026-10-03); this one's is
///                652;
///   300 x 300    the floor's map again, which every list needs.
///
/// FIXED lists: `count` is not read, and the runner holds each list to its
/// exact length (bsq_check.sh --fixed). The seed only draws the obstacles of
/// the first three big maps.
fn long_maps() -> Vec<MapSpec> {
    let mut line = uniform(1, 70000, true, DOT_OX);
    line.grid[0][69999] = false;
    let mut column = uniform(70000, 1, true, DOT_OX);
    column.grid[69999][0] = false;
    vec![line, column, uniform(300, 300, true, DOT_OX)]
}

fn big_maps(seed: u64) -> Vec<MapSpec> {
    let mut rng = Rng::new(seed ^ 0xB16);
    let mut sparse = |rows: usize, cols: usize, one_in: usize| {
        let mut m = uniform(rows, cols, false, DOT_OX);
        for r in 0..rows {
            for c in 0..cols {
                if rng.below(one_in) == 0 {
                    m.grid[r][c] = true;
                }
            }
        }
        m
    };
    let million = sparse(1000, 1000, 1000);
    let tall = sparse(10000, 100, 30);
    let mut nearly_empty = uniform(1000, 1000, false, DOT_OX);
    for _ in 0..NEARLY_EMPTY_OBSTACLES {
        let (r, c) = (rng.below(1000), rng.below(1000));
        nearly_empty.grid[r][c] = true;
    }
    vec![million, tall, nearly_empty, uniform(300, 300, true, DOT_OX)]
}

/// How many records each list makes: the --fixed the BUILD file passes.
pub const LONG_MAPS: usize = 3;
pub const BIG_MAPS: usize = 4;

/// The obstacles of the nearly empty big map: few enough that one of four
/// strips a quarter of the map wide holds none, so its biggest square is at
/// least 250 a side (check() holds it there).
const NEARLY_EMPTY_OBSTACLES: usize = 3;

fn emit_maps(maps: &[MapSpec]) {
    let out = io::stdout();
    let mut w = io::BufWriter::new(out.lock());
    for m in maps {
        emit(&mut w, &ok_case(m));
    }
    let _ = w.flush();
}

/// Is (side, top, left) the answer, by a second formulation: a table of
/// obstacle counts over every rectangle from the corner (prefix sums), which
/// says in O(1) whether a square holds an obstacle. o_bsq recurs on three
/// neighbours; this counts. Linear in the map, so it holds the big maps, which
/// o_bsq_naive cannot: no square of side + 1 is clear anywhere, and the first
/// clear square of `side` in reading order -- top first, then left -- is
/// (top, left).
fn holds_by_counts(grid: &[Vec<bool>], side: usize, top: usize, left: usize) -> bool {
    let rows = grid.len();
    let cols = if rows == 0 { 0 } else { grid[0].len() };
    let mut p = vec![0u32; (rows + 1) * (cols + 1)];
    for r in 0..rows {
        for c in 0..cols {
            p[(r + 1) * (cols + 1) + c + 1] = grid[r][c] as u32 + p[r * (cols + 1) + c + 1]
                + p[(r + 1) * (cols + 1) + c]
                - p[r * (cols + 1) + c];
        }
    }
    let clear = |t: usize, l: usize, k: usize| {
        let a = p[(t + k) * (cols + 1) + l + k] + p[t * (cols + 1) + l];
        let b = p[t * (cols + 1) + l + k] + p[(t + k) * (cols + 1) + l];
        a == b
    };
    let first = |k: usize| -> Option<(usize, usize)> {
        if k == 0 || k > rows || k > cols {
            return None;
        }
        for t in 0..=(rows - k) {
            for l in 0..=(cols - k) {
                if clear(t, l, k) {
                    return Some((t, l));
                }
            }
        }
        None
    };
    if first(side + 1).is_some() {
        return false;
    }
    side == 0 || first(side) == Some((top, left))
}

// ------------------------------------------------- the reference program

/// A map file read by the subject's "Definition of a valid file", or None
/// for one it calls invalid. Where the subject leaves a sentence open this
/// takes bsq_readings' reading -- the count is decimal digits only, positive
/// and fitting an int; the last row needs no newline of its own -- and the
/// two questions no layer asks in either direction (the full character in
/// the body, more rows than the count) it answers as invalid only because a
/// program must answer them: `run` serves the named cases, none of which
/// holds either, and must never be read as settling them.
fn parse_map(bytes: &[u8]) -> Option<MapSpec> {
    let nl = bytes.iter().position(|&b| b == b'\n')?;
    let head = &bytes[..nl];
    if head.len() < 4 {
        return None;
    }
    let (count, chars) = head.split_at(head.len() - 3);
    if count.is_empty() || !count.iter().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let rows: usize = std::str::from_utf8(count).ok()?.parse().ok()?;
    if rows == 0 || rows > i32::MAX as usize {
        return None;
    }
    let (empty, obstacle, full) = (chars[0], chars[1], chars[2]);
    let printable = |c: u8| (0x20..=0x7e).contains(&c);
    if !printable(empty) || !printable(obstacle) || !printable(full)
        || empty == obstacle || empty == full || obstacle == full
    {
        return None;
    }
    let mut body: Vec<&[u8]> = bytes[nl + 1..].split(|&b| b == b'\n').collect();
    if body.last().map_or(false, |l| l.is_empty()) {
        body.pop();
    }
    if body.len() != rows || body[0].is_empty() || body.iter().any(|l| l.len() != body[0].len()) {
        return None;
    }
    let mut grid = Vec::with_capacity(rows);
    for line in &body {
        let mut row = Vec::with_capacity(line.len());
        for &c in line.iter() {
            if c == empty {
                row.push(false);
            } else if c == obstacle {
                row.push(true);
            } else {
                return None;
            }
        }
        grid.push(row);
    }
    Some(MapSpec { empty, obstacle, full, grid })
}

/// What a correct program prints for one map file's bytes.
fn answer(bytes: &[u8]) -> Vec<u8> {
    match parse_map(bytes) {
        Some(m) => {
            let (side, top, left) = o_bsq(&m.grid);
            m.solved(side, top, left)
        }
        None => b"map error\n".to_vec(),
    }
}

/// `oracle run bsq <file>...`: what `./bsq <file>...` prints, for
/// c_program(reference = True) (tools/reference_cases.sh): each file's
/// answer, one blank line between two of them; a name that will not open is
/// a map error, and with no name the map comes on standard input. Returns 0:
/// the subject names no exit status.
pub fn run(args: &[String]) -> i32 {
    let mut out: Vec<u8> = Vec::new();
    if args.is_empty() {
        let mut bytes = Vec::new();
        let _ = io::Read::read_to_end(&mut io::stdin(), &mut bytes);
        out.extend(answer(&bytes));
    }
    for (i, f) in args.iter().enumerate() {
        if i > 0 {
            out.push(b'\n');
        }
        match std::fs::read(f) {
            Ok(bytes) => out.extend(answer(&bytes)),
            Err(_) => out.extend_from_slice(b"map error\n"),
        }
    }
    let mut w = io::stdout();
    let _ = w.write_all(&out);
    let _ = w.flush();
    0
}

/// `bsq_readings` and `bsq_fixtures` ignore seed and count: both are fixed
/// lists, the one a strict target replays and the other a set of files.
/// `bsq_long` ignores both, and `bsq_big` ignores count and reads the seed
/// for two maps' obstacles.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "bsq_maps" => gen_maps(seed, count),
        "bsq_errors" => gen_errors(seed, count),
        "bsq_mixed" => gen_mixed(seed, count),
        "bsq_readings" => gen_readings(),
        "bsq_fixtures" => gen_fixtures(),
        "bsq_long" => emit_maps(&long_maps()),
        "bsq_big" => emit_maps(&big_maps(seed)),
        _ => return false,
    }
    true
}

// ---------------------------------------------------------------- self-checks

/// The body's line count: newlines after the first line, plus an unterminated
/// last row.
fn body_lines(file: &[u8]) -> usize {
    let body = match file.iter().position(|&b| b == b'\n') {
        Some(i) => &file[i + 1..],
        None => return 0,
    };
    let nl = body.iter().filter(|&&b| b == b'\n').count();
    nl + usize::from(!body.is_empty() && body.last() != Some(&b'\n'))
}

/// The count field: the first line without its last three characters.
fn count_field(file: &[u8]) -> &[u8] {
    let end = file.iter().position(|&b| b == b'\n').unwrap_or(file.len());
    let head = &file[..end];
    &head[..head.len().saturating_sub(3)]
}

/// What a program that skips one count rule reads as the count: leading
/// spaces and a sign ('+' or '-') passed over, then the digits -- exactly, and
/// wrapped to 32 and to 64 bits. Empty when no digit follows. The '-' is
/// passed over because that is the misreading count_negative guards: a parse
/// that skips every non-digit before the number reads "-4" as 4.
fn misread_counts(file: &[u8]) -> Vec<u128> {
    let f = count_field(file);
    let mut i = 0;
    while i < f.len() && (f[i] == b' ' || f[i] == b'+' || f[i] == b'-') {
        i += 1;
    }
    let mut v: u128 = 0;
    let mut any = false;
    while i < f.len() && f[i].is_ascii_digit() {
        v = v.saturating_mul(10).saturating_add(u128::from(f[i] - b'0'));
        any = true;
        i += 1;
    }
    if !any {
        return Vec::new();
    }
    vec![v, v % (1u128 << 32), v % (1u128 << 64)]
}

/// Whether `file` is a valid map under the subject's "Definition of a valid
/// file", read at one pole of every question it leaves open: `lenient` reads
/// the count as atoi would (spaces and a '+' before it, spaces after) and lets
/// the last row go without its newline; otherwise the count is digits only and
/// every row ends in one. Only for check(): a record the corpus files as
/// invalid must be invalid at BOTH poles, and a valid one valid at both, or it
/// is not a settled record. (The FULL character in a body and more rows than
/// the count are open too; no record holds either, and both poles refuse them.)
fn valid_under(file: &[u8], lenient: bool) -> bool {
    let nl = match file.iter().position(|&b| b == b'\n') {
        Some(i) => i,
        None => return false,
    };
    let head = &file[..nl];
    if head.len() < 4 {
        return false;
    }
    let (field, ch) = head.split_at(head.len() - 3);
    let printable = |b: u8| (0x20..=0x7e).contains(&b);
    if !ch.iter().all(|&b| printable(b)) || ch[0] == ch[1] || ch[1] == ch[2] || ch[0] == ch[2] {
        return false;
    }
    let mut i = 0;
    if lenient {
        while i < field.len() && (field[i] == b' ' || field[i] == b'+') {
            i += 1;
        }
    }
    let start = i;
    let mut count: u64 = 0;
    while i < field.len() && field[i].is_ascii_digit() {
        count = count.saturating_mul(10).saturating_add(u64::from(field[i] - b'0'));
        i += 1;
    }
    if i == start {
        return false;
    }
    let rest_ok = if lenient {
        field[i..].iter().all(|&b| b == b' ')
    } else {
        i == field.len()
    };
    if !rest_ok || count == 0 || count > i32::MAX as u64 {
        return false;
    }
    let body = &file[nl + 1..];
    let terminated = body.last() == Some(&b'\n');
    if !terminated && !lenient {
        return false;
    }
    let text = if terminated { &body[..body.len() - 1] } else { body };
    if body.is_empty() {
        return false;
    }
    let rows: Vec<&[u8]> = text.split(|&b| b == b'\n').collect();
    if rows.len() as u64 != count || rows[0].is_empty() {
        return false;
    }
    rows.iter()
        .all(|r| r.len() == rows[0].len() && r.iter().all(|&b| b == ch[0] || b == ch[1]))
}

/// Which open form of the count this file's first line has, if any: the forms
/// "a valid positive number" does not settle (the header's list).
fn open_count_form(file: &[u8]) -> Option<&'static str> {
    let f = count_field(file);
    if f.first() == Some(&b'+') {
        Some("a '+'")
    } else if f.first() == Some(&b' ') {
        Some("a space before it")
    } else if f.last() == Some(&b' ') && f.iter().any(|b| b.is_ascii_digit()) {
        Some("a space after it")
    } else if f.len() > 1 && f[0] == b'0' && f[1].is_ascii_digit() {
        Some("a leading zero")
    } else {
        None
    }
}

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
    // ---- each count slug ISOLATES its rule (header) ----
    //
    // The count a program that skips the rule would read -- the digits the
    // header starts with, exactly or wrapped -- is the body's own line count,
    // or the line-count rule rejects the file first and the record tests
    // nothing it is named for. Over the head, and over a sample of mutations.
    let isolated = ["count_zero", "count_junk", "count_overflow", "count_negative"];
    let mut sample: Vec<Case> = Vec::new();
    let mut mrng = Rng::new(0x150);
    let mut mmaps: Vec<MapSpec> = Vec::new();
    ok_tail(&mut mrng, 2000, &mut mmaps);
    for m in &mmaps {
        sample.push(mutate_invalid(&mut mrng, m));
    }
    for c in errs.iter().chain(sample.iter()) {
        let slug = c.tag.trim_start_matches("err:");
        if !isolated.contains(&slug) {
            continue;
        }
        let lines = body_lines(&c.file);
        if !misread_counts(&c.file).contains(&(lines as u128)) {
            eprintln!(
                "CHECK FAIL bsq {} record {:?} does not isolate its rule: a program that skips it \
                 reads {:?}, and the body holds {} line(s)",
                slug,
                String::from_utf8_lossy(&c.file),
                misread_counts(&c.file),
                lines
            );
            fails += 1;
        }
    }
    for slug in isolated {
        // count_overflow and count_negative are head records only: a
        // mutation keeps the map's own count, which is positive and small.
        if !sample.iter().any(|c| c.tag == format!("err:{}", slug))
            && slug != "count_overflow"
            && slug != "count_negative"
        {
            eprintln!("CHECK FAIL bsq mutate_invalid never produces {}", slug);
            fails += 1;
        }
    }

    // ---- the settled arms hold no open reading (header) ----
    //
    // No count with a '+', a space or a leading zero, and no valid file
    // without its final newline: those are bsq_readings' alone.
    for c in head.iter().map(ok_case).chain(errs.iter().cloned()).chain(sample.into_iter()) {
        // Settled: valid at both poles of every open question, or invalid at
        // both. A mutation that leaves a valid map behind fails here.
        let (a, b) = (valid_under(&c.file, false), valid_under(&c.file, true));
        if a != b || a != (c.tag == "ok") {
            eprintln!(
                "CHECK FAIL bsq record {} is not settled by the validity list: {:?} (valid: {} strictly, {} leniently)",
                c.tag,
                String::from_utf8_lossy(&c.file),
                a,
                b
            );
            fails += 1;
        }
        if let Some(form) = open_count_form(&c.file) {
            eprintln!("CHECK FAIL bsq a settled record holds an open count ({}): {:?}", form, c.tag);
            fails += 1;
        }
        if c.tag == "ok" && c.file.last() != Some(&b'\n') {
            eprintln!("CHECK FAIL bsq a settled valid record has no final newline");
            fails += 1;
        }
    }

    // ---- the readings arm says what the header says it does ----
    let rd = readings();
    for c in &rd {
        let form = open_count_form(&c.file);
        let nonl = c.file.last() != Some(&b'\n');
        // The tag names the one open form the record holds, and nothing else
        // is open in it.
        let ok = match c.tag.as_str() {
            "ok:count_leading_zero" => form == Some("a leading zero") && !nonl,
            "ok:no_final_newline" => form.is_none() && nonl,
            "err:count_plus" => form == Some("a '+'") && !nonl,
            "err:count_space_before" => form == Some("a space before it") && !nonl,
            "err:count_space_after" => form == Some("a space after it") && !nonl,
            _ => false,
        };
        if !ok {
            eprintln!("CHECK FAIL bsq readings record {:?} is not the one open form its tag names", c.tag);
            fails += 1;
        }
        // Each is isolated too: only the reading can reject a "+9" over nine rows.
        if c.tag.starts_with("err:") && !misread_counts(&c.file).contains(&(body_lines(&c.file) as u128)) {
            eprintln!("CHECK FAIL bsq readings record {:?} is rejected by the line count first", c.tag);
            fails += 1;
        }
    }
    if rd.len() < 20 || !rd.iter().any(|c| c.tag.starts_with("ok:") && c.side == 0) {
        eprintln!("CHECK FAIL bsq readings corpus is below bsq_check.sh's floors (20 records, a side-0 map)");
        fails += 1;
    }

    // ---- the named fixtures are files a test can hold ----
    let fx = fixtures();
    let mut seen: Vec<&str> = Vec::new();
    for (path, bytes) in &fx {
        let safe = !path.is_empty()
            && !path.starts_with('/')
            && !path.split('/').any(|p| p == ".." || p.is_empty())
            && path
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'.' || b == b'/' || b == b'-');
        if !safe || seen.contains(&path.as_str()) {
            eprintln!("CHECK FAIL bsq fixture path {:?} is unsafe or repeated", path);
            fails += 1;
        }
        seen.push(path);
        if bytes.is_empty() {
            eprintln!("CHECK FAIL bsq fixture {:?} is empty: its error-head record is gone", path);
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

    // ---- the reference program answers every record of every corpus as the
    //      record expects: the settled ones, and the readings under the one
    //      reading it takes ----
    {
        let mut corpus: Vec<Case> = Vec::new();
        let mut r = Rng::new(3);
        let mut maps = ok_head();
        ok_tail(&mut r, 200, &mut maps);
        corpus.extend(maps.iter().map(ok_case));
        corpus.extend(err_head());
        corpus.extend(readings());
        let bad = corpus.iter().filter(|c| answer(&c.file) != c.expected).count();
        if bad != 0 {
            eprintln!("CHECK FAIL bsq run: {} of {} records answered otherwise than they expect", bad, corpus.len());
            fails += 1;
        }
    }

    // ---- `count` sizes the random tail: a corpus asked for more maps has
    // more, from the same head, the same first records ----
    {
        let sized = |count: usize| {
            let mut r = Rng::new(1);
            let mut m = ok_head();
            ok_tail(&mut r, count, &mut m);
            m.len()
        };
        let head = ok_head().len();
        if sized(60) != head + 60 || sized(120) != head + 120 {
            eprintln!("CHECK FAIL bsq count does not size the tail: {} and {} maps", sized(60), sized(120));
            fails += 1;
        }
    }

    // ---- the long and the big maps: each past the capacity it is there
    // for, each answer held by a second formulation ----
    let long = long_maps();
    let big = big_maps(1);
    for (name, list, want) in [("long", &long, LONG_MAPS), ("big", &big, BIG_MAPS)] {
        if list.len() != want {
            eprintln!("CHECK FAIL bsq {}_maps makes {} maps, the constant says {}", name, list.len(), want);
            fails += 1;
        }
    }
    let dims = |l: &Vec<MapSpec>| -> Vec<(usize, usize)> { l.iter().map(|m| (m.rows(), m.grid[0].len())).collect() };
    if dims(&long) != vec![(1, 70000), (70000, 1), (300, 300)] {
        eprintln!("CHECK FAIL bsq long_maps sizes are {:?}", dims(&long));
        fails += 1;
    }
    if dims(&big) != vec![(1000, 1000), (10000, 100), (1000, 1000), (300, 300)] {
        eprintln!("CHECK FAIL bsq big_maps sizes are {:?}", dims(&big));
        fails += 1;
    }
    let mut answers: Vec<(usize, usize, usize)> = Vec::new();
    for m in long.iter().chain(big.iter()) {
        let (s, t, l) = o_bsq(&m.grid);
        answers.push((s, t, l));
        if !holds_by_counts(&m.grid, s, t, l) {
            eprintln!(
                "CHECK FAIL bsq big map {}x{}: o_bsq says side {} at ({}, {}), the counts disagree",
                m.rows(),
                m.grid[0].len(),
                s,
                t,
                l
            );
            fails += 1;
        }
        let e = esc_posix(&m.file());
        if e.contains('\t') || e.contains('\n') {
            eprintln!("CHECK FAIL bsq a big map's record field holds a raw separator");
            fails += 1;
        }
    }
    if answers.len() == LONG_MAPS + BIG_MAPS {
        // The long maps' promise to basic: no square bigger than one cell,
        // and each list holds the floor's map with no empty cell.
        if answers[..LONG_MAPS].iter().any(|a| a.0 > 1) {
            eprintln!("CHECK FAIL bsq a long map's square is past one cell: {:?}", &answers[..LONG_MAPS]);
            fails += 1;
        }
        if answers[0] != (1, 0, 69999) || answers[1] != (1, 69999, 0) || answers[2].0 != 0 {
            eprintln!("CHECK FAIL bsq the line, the column or the full map answers {:?}", &answers[..LONG_MAPS]);
            fails += 1;
        }
        if answers[LONG_MAPS].0 <= 64 {
            eprintln!("CHECK FAIL bsq the million-cell map's square is {}, not past 64", answers[LONG_MAPS].0);
            fails += 1;
        }
        // The nearly empty map: hardly an obstacle, and a square hundreds
        // of cells a side, where a solver whose work grows with a high power
        // of the square's side does not finish (finding 041c).
        let obstacles = big[2].grid.iter().flatten().filter(|&&o| o).count();
        if obstacles > NEARLY_EMPTY_OBSTACLES || answers[LONG_MAPS + 2].0 < 250 {
            eprintln!(
                "CHECK FAIL bsq the nearly empty big map holds {} obstacles and a square of {}, not at most {} and at least 250",
                obstacles,
                answers[LONG_MAPS + 2].0,
                NEARLY_EMPTY_OBSTACLES
            );
            fails += 1;
        }
        if answers[LONG_MAPS + BIG_MAPS - 1].0 != 0 {
            eprintln!("CHECK FAIL bsq the big list has no map without an empty cell");
            fails += 1;
        }
        if m_file_len(&long[0]) <= 65536 || m_file_len(&long[1]) <= 65536 {
            eprintln!("CHECK FAIL bsq the one-line or the one-column map is not past 64 KiB");
            fails += 1;
        }
    }

    sink(fails);
    fails
}

/// The length of a map's file, header included.
fn m_file_len(m: &MapSpec) -> usize {
    m.file().len()
}
