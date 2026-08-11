//! Rush01 (c-piscine-rush-01 ex00) — the 4x4 skyscrapers reference.
//!
//! Corpus line format. ONE case per line, TAB-separated:
//!
//!     <16 space-separated clues>\t<solution>\t<solution>...
//!
//! Field 1 is the argv string the student's `rush01` is invoked with, verbatim:
//! sixteen digits '1'..'4' separated by single spaces, in the subject's order —
//! the four columns seen from ABOVE, the four columns seen from BELOW, the four
//! rows seen from the LEFT, then the four rows seen from the RIGHT.
//!
//! Every field AFTER the first is one solution of that clue vector, written as
//! the 16 grid digits in row-major order with no spaces, e.g. the subject's own
//! example `1234234134124123` for
//!
//!     1 2 3 4
//!     2 3 4 1
//!     3 4 1 2
//!     4 1 2 3
//!
//! and the fields together are EVERY solution it has, not the first one. A
//! vector with no solution carries no solution field, so those lines END IN A
//! TAB with nothing after it: the trailing tab is deliberate, so that "no
//! solution" reads as an empty field rather than as a line a consumer has to
//! special-case, and it lets `is this line solvable` be answered by looking at
//! the last byte. `Error` is the correct answer for exactly those lines.
//!
//! THE SEPARATOR IS A TAB AND `|` IS NOT FREE FOR THIS JOB — worth stating
//! because `|` is the obvious choice and it is taken. tools/rush01_check.sh,
//! which defines this format and is the only consumer, strips `/`, `,`, `|` and
//! spaces from INSIDE a solution field so that a reference may write one grid as
//! `1234/2341/3412/4123`. A `|` between two solutions is therefore read as a
//! 32-digit grid and rejected, which is what it did: a `|`-separated corpus made
//! the sweep exit 2 ("the corpus is unusable") on all 66 multi-solution lines,
//! for every student including a correct one. `SOL_SEP` below is the single
//! place this is spelled, so the emitter and this file's own self-check cannot
//! drift apart again.
//!
//! What a consumer must NOT do is keep only the first solution field. That
//! silently narrows a solution SET to whichever answer this file happened to
//! list first, which is the one thing this whole design exists to prevent.
//!
//! Two things about field 1 that WILL bite a runner author, in this repo more
//! than most:
//!
//!   * It CONTAINS SPACES. Split corpus lines on TAB, never on whitespace, and
//!     pass the whole field to the binary as ONE argv element (`"$clues"`, not
//!     `$clues`). The subject fixes this interface — one argument holding 16
//!     space-separated digits — so a runner that cannot carry a space through
//!     must be fixed rather than the interface reformatted. Note in particular
//!     that Bazel's `sh_test` re-tokenises `args` on whitespace, which this repo
//!     has been bitten by three times; a corpus read from a file at run time,
//!     as here, is not affected, but an `args = [...]` shortcut would be.
//!   * Every vector here is WELL-FORMED — 16 tokens, all in '1'..'4'. The
//!     subject's other error branch (wrong argument count, non-digit, out of
//!     range, empty string) is not representable in this format and does not
//!     belong here; that branch is argv-case territory (see the argv tables in
//!     c-piscine-c-10/BUILD.bazel for the shape). What this corpus covers is the
//!     harder half: well-formed input that simply has no solution.
//!
//! WHY THE CORPUS CARRIES ALL SOLUTIONS, AND NOT JUST THE FIRST
//!
//! The subject asks for "the first solution you encounter", and 66 of the 438
//! solvable clue vectors have more than one solution (34 have two, 28 have four,
//! 4 have six). WHICH one a correct program prints is a consequence of the order
//! it searches in, which the subject does not fix — so a byte comparison against
//! one stored grid would fail correct programs, and would fail them for writing
//! their loops in a different order rather than for being wrong. The runner must
//! therefore VALIDATE the student's grid, not compare it: accept any output that
//! is a Latin square satisfying all 16 clues. Emitting every solution here is
//! what lets the runner do that with a set-membership test instead of
//! re-implementing the puzzle, and it is why this module exists at all.
//!
//! (Set membership and validation are the same test, given this corpus is
//! complete: the solution fields are the whole solution set, so "in the list"
//! and "is a correct answer" coincide. A runner may do either; membership is
//! cheaper and needs no puzzle logic on the student's side of the fence.)
//!
//! SCOPE: 4x4 only, on purpose. The subject's bonus allows sizes up to 9x9, and
//! a bonus must never gate — so there is deliberately no NxN arm here to wire a
//! gate to. The exhaustive design below is also specific to 4x4: it enumerates
//! all 576 Latin squares of order 4 once and buckets them by clue vector, which
//! is what makes "every achievable vector, with every solution" a fact rather
//! than a sample. Order 5 has 161 280 squares (still fine); order 6 has
//! 812 851 200 (not). If a bonus layer ever needs a bigger board, it wants the
//! single-vector `search()` below generalised, not this enumeration.
//!
//! THE NUMBERS THIS FILE IS BUILT ON (all re-derived by `check()`, never
//! trusted): 576 Latin squares of order 4; they realise 438 distinct clue
//! vectors; 372 of those have one solution, 34 have two, 28 have four and 4 have
//! six (372 + 68 + 112 + 24 = 576). Of the 4^16 = 4 294 967 296 well-formed
//! 16-digit inputs, only those 438 are solvable — the other 4 294 966 858 must
//! print `Error`, which makes `Error` by far the most common correct answer and
//! is why the corpus is at least half unsolvable cases.

use crate::common::{bench_lines, sink, Rng};
use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Write};

/// Board width. Fixed at 4 by the subject's required part; see the SCOPE note.
const N: usize = 4;
/// Cells in a grid, and — not a coincidence — clues in a vector: 4 per side.
const CELLS: usize = N * N;

/// A filled grid, row-major: index `r * N + c`.
type Grid = [u8; CELLS];
/// A clue vector in the subject's argv order (see the four offsets below).
type Clues = [u8; CELLS];

// The subject's clue layout, named once so no other line in this file has to
// spell out a bare 8 or 12. The offsets are verified against the subject's own
// worked example in `check()`, which is the only thing that can catch a
// transposition here: swapping LEFT and RIGHT (or top and bottom) still yields a
// self-consistent module that solves the wrong puzzle.
const TOP: usize = 0; // 0..4   columns 1..4, looking down
const BOTTOM: usize = 4; // 4..8   columns 1..4, looking up
const LEFT: usize = 8; // 8..12  rows 1..4, looking right
const RIGHT: usize = 12; // 12..16 rows 1..4, looking left

/// What separates two solutions on a corpus line. See the header: it is a TAB
/// because the consumer strips `|` from inside a solution field, and it is a
/// named constant because the emitter and `check()`'s re-parse of the emitted
/// bytes must never be able to disagree about it.
const SOL_SEP: char = '\t';

/// The subject's worked example, kept as the argv string a student would type.
const SUBJECT_CLUES: &str = "4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2";
/// ...and its one and only solution, transcribed from the subject's transcript.
const SUBJECT_SOLUTION: &str = "1234234134124123";

// ------------------------------------------------------------- oracles

/// How many boxes are visible looking along `line` from index 0: a box is seen
/// when it is taller than everything before it, and hides everything shorter
/// behind it.
///
/// Running-maximum formulation. `visible_rescan` below computes the same number
/// a different way and the two are used by DIFFERENT halves of this file, so
/// `check()` comparing those halves is also comparing these — see the note there.
fn visible(line: &[u8; N]) -> u8 {
    let mut tallest = 0u8;
    let mut seen = 0u8;
    let mut i = 0;
    while i < N {
        if line[i] > tallest {
            tallest = line[i];
            seen += 1;
        }
        i += 1;
    }
    seen
}

/// The same count, computed by re-scanning: position `i` is visible when no
/// earlier position is at least as tall. Shares no state with `visible` — no
/// accumulator, no ordering assumption — so a bug in either shows up as a
/// disagreement rather than as two matching wrong answers.
fn visible_rescan(line: &[u8; N]) -> u8 {
    let mut seen = 0u8;
    let mut i = 0;
    while i < N {
        let mut hidden = false;
        let mut j = 0;
        while j < i {
            if line[j] >= line[i] {
                hidden = true;
            }
            j += 1;
        }
        if !hidden {
            seen += 1;
        }
        i += 1;
    }
    seen
}

fn row_of(g: &Grid, r: usize) -> [u8; N] {
    let mut v = [0u8; N];
    let mut c = 0;
    while c < N {
        v[c] = g[r * N + c];
        c += 1;
    }
    v
}

fn col_of(g: &Grid, c: usize) -> [u8; N] {
    let mut v = [0u8; N];
    let mut r = 0;
    while r < N {
        v[r] = g[r * N + c];
        r += 1;
    }
    v
}

fn reversed(v: &[u8; N]) -> [u8; N] {
    let mut o = [0u8; N];
    let mut i = 0;
    while i < N {
        o[i] = v[N - 1 - i];
        i += 1;
    }
    o
}

/// The clue vector a finished grid produces — the puzzle read backwards, which
/// is the only direction that is cheap. This is the whole trick behind the
/// exhaustive table: rather than solve 4^16 vectors, walk the 576 grids and let
/// each one say which vector it answers.
fn clues_of(g: &Grid) -> Clues {
    let mut c = [0u8; CELLS];
    let mut i = 0;
    while i < N {
        let col = col_of(g, i);
        c[TOP + i] = visible(&col);
        c[BOTTOM + i] = visible(&reversed(&col));
        let row = row_of(g, i);
        c[LEFT + i] = visible(&row);
        c[RIGHT + i] = visible(&reversed(&row));
        i += 1;
    }
    c
}

/// `clues_of` through the rescanning counter, for `check()` only.
fn clues_of_rescan(g: &Grid) -> Clues {
    let mut c = [0u8; CELLS];
    let mut i = 0;
    while i < N {
        let col = col_of(g, i);
        c[TOP + i] = visible_rescan(&col);
        c[BOTTOM + i] = visible_rescan(&reversed(&col));
        let row = row_of(g, i);
        c[LEFT + i] = visible_rescan(&row);
        c[RIGHT + i] = visible_rescan(&reversed(&row));
        i += 1;
    }
    c
}

/// Every row and every column holds each of 1..=N exactly once.
fn is_latin(g: &Grid) -> bool {
    let full = ((1u16 << (N + 1)) - 1) & !1; // bits 1..=N
    let mut i = 0;
    while i < N {
        let mut rmask = 0u16;
        let mut cmask = 0u16;
        let mut k = 0;
        while k < N {
            rmask |= 1u16 << g[i * N + k];
            cmask |= 1u16 << g[k * N + i];
            k += 1;
        }
        if rmask != full || cmask != full {
            return false;
        }
        i += 1;
    }
    true
}

/// The validator a runner needs, stated once: a grid answers a clue vector iff
/// it is a Latin square and reproduces the vector. Deliberately written through
/// the rescanning counter so it is not the same code path the corpus was built
/// with.
fn answers(g: &Grid, c: &Clues) -> bool {
    is_latin(g) && clues_of_rescan(g) == *c
}

/// The 24 permutations of 1..=N, in ascending order.
fn permutations() -> Vec<[u8; N]> {
    let mut out: Vec<[u8; N]> = Vec::with_capacity(24);
    let mut p = [0u8; N];
    perm_step(0, 0, &mut p, &mut out);
    out
}

fn perm_step(i: usize, used: u16, p: &mut [u8; N], out: &mut Vec<[u8; N]>) {
    if i == N {
        out.push(*p);
        return;
    }
    let mut v = 1u8;
    while v <= N as u8 {
        let bit = 1u16 << v;
        if used & bit == 0 {
            p[i] = v;
            perm_step(i + 1, used | bit, p, out);
        }
        v += 1;
    }
}

/// All 576 Latin squares of order 4, ascending by their row-major digit string.
///
/// Deliberately the dumbest construction that is obviously right: take the
/// 24^4 = 331 776 ways to stack four permutations and keep the ones whose
/// columns are also permutations. That is ~5M byte operations, i.e. free next to
/// the process start-up around it, and it buys something worth more than the
/// microseconds — nothing about the skyscraper puzzle is baked into it, so the
/// squares cannot inherit a bug from the clue logic they are about to be sorted
/// by. The cell-by-cell `search()` further down is the constrained, pruning
/// formulation; keeping the two shapes apart is what makes `check()`'s
/// comparison of them meaningful.
///
/// Ascending order falls out of the enumeration (permutations ascend, the outer
/// loop is the first row) rather than out of a sort, which is what lets every
/// solution list in the table be ascending without one.
fn all_latin_squares() -> Vec<Grid> {
    let perms = permutations();
    let mut out: Vec<Grid> = Vec::with_capacity(576);
    for r0 in &perms {
        for r1 in &perms {
            for r2 in &perms {
                for r3 in &perms {
                    let rows = [r0, r1, r2, r3];
                    let mut ok = true;
                    let mut c = 0;
                    while c < N {
                        let mut mask = 0u16;
                        let mut r = 0;
                        while r < N {
                            mask |= 1u16 << rows[r][c];
                            r += 1;
                        }
                        if mask.count_ones() != N as u32 {
                            ok = false;
                            break;
                        }
                        c += 1;
                    }
                    if !ok {
                        continue;
                    }
                    let mut g = [0u8; CELLS];
                    let mut r = 0;
                    while r < N {
                        let mut c = 0;
                        while c < N {
                            g[r * N + c] = rows[r][c];
                            c += 1;
                        }
                        r += 1;
                    }
                    out.push(g);
                }
            }
        }
    }
    out
}

/// Clue vector -> every grid that answers it, for all 438 achievable vectors.
///
/// A `BTreeMap` and not a `HashMap`: std's hasher is randomly seeded per
/// process, so a `HashMap` here would emit the corpus in a different order on
/// every run and quietly break the determinism contract this crate rests on
/// (see oracle/README.md). Ordering by key is free here and reproducible
/// everywhere.
fn build_table() -> BTreeMap<Clues, Vec<Grid>> {
    let mut t: BTreeMap<Clues, Vec<Grid>> = BTreeMap::new();
    for g in all_latin_squares() {
        t.entry(clues_of(&g)).or_default().push(g);
    }
    t
}

// ------------------------------------------------- the single-vector search
//
// The second, independent implementation: given ONE clue vector, find grids that
// answer it. The table above never solves anything — it recognises. This does
// the job the student's program does, and that is exactly what it is for:
//
//   * `bench` runs it per corpus line, so the perf baseline is a search for a
//     solution rather than a lookup of one. Timing a `BTreeMap` hit against a
//     student's search would report a ratio about the data structure and
//     nothing about either program.
//   * `check()` runs it over all 438 achievable vectors and a seeded sample of
//     unsolvable ones and demands it agree with the table, grid for grid and in
//     order. Two ways of getting the same 576 answers, sharing no code below
//     `row_of`/`col_of`: this one places digits cell by cell under row/column
//     masks and prunes on clues as each line completes, the other stacks whole
//     permutations and reads the clues off afterwards.
//
// It is written for clarity, NOT tuned. c-05's ten queens is deliberately
// optimised because a cost comparison is its whole consumer and the gap is its
// message; here the search tree bottoms out at 576 leaves and any correct
// approach finishes in microseconds, so a "fast" version would only make the
// numbers noisier without making them mean more.

/// Fill cell `i` (row-major) and recurse. Stops once `out` holds `limit` grids.
///
/// Pruning is only ever applied to a line that is FINISHED, which is the honest
/// place for it: the left/right clues of row `r` become checkable exactly when
/// its last cell is placed, and the top/bottom clues of column `c` exactly when
/// the last row is placed. Nothing is guessed about a partial line.
fn step(
    i: usize,
    clues: &Clues,
    g: &mut Grid,
    rows: &mut [u16; N],
    cols: &mut [u16; N],
    limit: usize,
    out: &mut Vec<Grid>,
) {
    if out.len() >= limit {
        return;
    }
    if i == CELLS {
        out.push(*g);
        return;
    }
    let r = i / N;
    let c = i % N;
    let mut v = 1u8;
    while v <= N as u8 {
        let bit = 1u16 << v;
        if rows[r] & bit == 0 && cols[c] & bit == 0 {
            g[i] = v;
            rows[r] |= bit;
            cols[c] |= bit;
            let mut ok = true;
            if c == N - 1 {
                let line = row_of(g, r);
                ok = visible_rescan(&line) == clues[LEFT + r]
                    && visible_rescan(&reversed(&line)) == clues[RIGHT + r];
            }
            if ok && r == N - 1 {
                let line = col_of(g, c);
                ok = visible_rescan(&line) == clues[TOP + c]
                    && visible_rescan(&reversed(&line)) == clues[BOTTOM + c];
            }
            if ok {
                step(i + 1, clues, g, rows, cols, limit, out);
            }
            rows[r] &= !bit;
            cols[c] &= !bit;
            g[i] = 0;
            if out.len() >= limit {
                return;
            }
        }
        v += 1;
    }
}

/// Up to `limit` grids answering `clues`, ascending (candidates are tried in
/// ascending order at every cell). `limit == 1` is "the first solution you
/// encounter" for one particular search order — ours, not authoritatively the
/// student's, which is the entire reason the runner validates instead of
/// comparing. `usize::MAX` enumerates the solution set.
#[inline(never)] // keep this attributable if a cost layer is ever pointed here
fn search(clues: &Clues, limit: usize) -> Vec<Grid> {
    let mut out: Vec<Grid> = Vec::new();
    let mut g = [0u8; CELLS];
    let mut rows = [0u16; N];
    let mut cols = [0u16; N];
    step(0, clues, &mut g, &mut rows, &mut cols, limit, &mut out);
    out
}

// ------------------------------------------------------------- formatting

/// `"4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2"` — the argv string, field 1 of a line.
fn fmt_clues(c: &Clues) -> String {
    let mut s = String::with_capacity(2 * CELLS - 1);
    let mut i = 0;
    while i < CELLS {
        if i > 0 {
            s.push(' ');
        }
        s.push((b'0' + c[i]) as char);
        i += 1;
    }
    s
}

/// `"1234234134124123"` — one grid, row-major, appended to `s`.
fn push_grid(s: &mut String, g: &Grid) {
    let mut i = 0;
    while i < CELLS {
        s.push((b'0' + g[i]) as char);
        i += 1;
    }
}

/// Strict reader for field 1: exactly 16 tokens of one digit each, all '1'..'4',
/// separated by single spaces. Anything else is `None`.
///
/// This parses THIS FILE'S OWN OUTPUT (and nothing else), so it is allowed to be
/// this strict — a double space or a stray token means the corpus is corrupt,
/// not that a lenient reading is wanted. It is emphatically NOT a model of what
/// the student's argv parser has to accept or reject; that is the subject's
/// business and the argv-case layer's.
fn parse_clues(s: &str) -> Option<Clues> {
    let mut c = [0u8; CELLS];
    let mut n = 0usize;
    for tok in s.split(' ') {
        let b = tok.as_bytes();
        if n == CELLS || b.len() != 1 || b[0] < b'1' || b[0] > b'0' + N as u8 {
            return None;
        }
        c[n] = b[0] - b'0';
        n += 1;
    }
    if n == CELLS {
        Some(c)
    } else {
        None
    }
}

/// A grid as the subject prints it: `N` lines of space-separated digits, each
/// ending in '\n'. Used only by `check()`, to pin that our compact row-major
/// digit string really is the grid the subject's transcript shows.
fn display(g: &Grid) -> String {
    let mut s = String::with_capacity((2 * N) * N);
    let mut r = 0;
    while r < N {
        let mut c = 0;
        while c < N {
            if c > 0 {
                s.push(' ');
            }
            s.push((b'0' + g[r * N + c]) as char);
            c += 1;
        }
        s.push('\n');
        r += 1;
    }
    s
}

// ---------------------------------------------------------- generators

/// Unsolvable vectors worth having in every corpus regardless of seed, each one
/// a shape a student's program can plausibly get wrong rather than a random
/// miss. `check()` asserts all of them really are unsolvable, so this list
/// cannot rot into "cases that quietly became solvable" if anything above
/// changes; it also asserts they survive into the emitted corpus.
///
/// The notes say what is impossible about each — they are notes about the INPUT,
/// which is what a grader needs to know when a case fails. Nothing here is
/// student-facing, and none of it belongs in a feedback message.
const CURATED_UNSOLVABLE: [&str; 12] = [
    // Uniform vectors: every side reads the same, which no Latin square does.
    "1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1",
    "2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2",
    "3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3",
    "4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4",
    // Opposite sides both extreme: a column read as 4 from the top is 1,2,3,4
    // top-down, and cannot also be that from the bottom.
    "4 4 4 4 1 1 1 1 4 4 4 4 1 1 1 1",
    "1 1 1 1 4 4 4 4 1 1 1 1 4 4 4 4",
    // Tidy-looking vectors that a "surely this one works" reading would expect
    // to be solvable. They are not, and they are the ones that catch a program
    // that prints a grid without verifying it.
    "1 2 3 4 1 2 3 4 1 2 3 4 1 2 3 4",
    "4 3 2 1 4 3 2 1 4 3 2 1 4 3 2 1",
    "1 2 3 4 4 3 2 1 1 2 3 4 4 3 2 1",
    "2 2 2 2 3 3 3 3 2 2 2 2 3 3 3 3",
    // The subject's own example with ONE clue changed — the nearest possible
    // miss, and the case that separates "solved it" from "recognised it".
    "3 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2",
    "4 3 2 1 1 2 2 2 4 3 2 1 2 2 2 2",
];

/// The solvable half of the corpus: all 438 achievable vectors with all their
/// solutions, ordered interesting-first — the subject's own example, then the
/// multi-solution vectors (six solutions, then four, then two), then the 372
/// single-solution ones, ascending within each group.
///
/// The head is where the design lives: those 66 multi-solution vectors are the
/// reason this corpus carries solution SETS, so they are the cases a consumer
/// that samples a prefix most needs to see. (House habit, same as c00 keeping
/// its boundaries out of the random tail: what matters goes at the front, and
/// `check()` asserts it is still there.)
fn solvable_cases(table: &BTreeMap<Clues, Vec<Grid>>) -> Vec<(Clues, Vec<Grid>)> {
    let subject = parse_clues(SUBJECT_CLUES).expect("SUBJECT_CLUES must parse");
    let mut rest: Vec<(Clues, Vec<Grid>)> = table
        .iter()
        .filter(|(c, _)| **c != subject)
        .map(|(c, s)| (*c, s.clone()))
        .collect();
    // Descending solution count, then ascending vector. `iter()` on a BTreeMap
    // is already key-ascending and `sort_by_key` is stable, so the second key
    // needs no comparator of its own.
    rest.sort_by_key(|(_, s)| std::cmp::Reverse(s.len()));
    let mut out: Vec<(Clues, Vec<Grid>)> = Vec::with_capacity(table.len());
    if let Some(sols) = table.get(&subject) {
        out.push((subject, sols.clone()));
    }
    out.extend(rest);
    out
}

/// `want` distinct unsolvable well-formed vectors: the curated list, then
/// single-clue perturbations of achievable vectors, then uniform draws.
///
/// The mix is the point. Uniform draws are what the input space actually looks
/// like — 4 294 966 858 of the 4 294 967 296 well-formed inputs are unsolvable,
/// so a random one is unsolvable with probability 0.99999990 — but they are also
/// the EASY unsolvable cases, rejected by the first clue anyone checks. The
/// perturbations sit one clue away from a solvable vector and can only be
/// rejected by finishing the work, so they are what actually exercises the
/// `Error` path. Everything is membership-tested against the table, so a
/// perturbation that lands back on a solvable vector (measured: ~0.3% of them)
/// is dropped rather than mislabelled.
fn unsolvable_cases(
    table: &BTreeMap<Clues, Vec<Grid>>,
    solvable: &[(Clues, Vec<Grid>)],
    rng: &mut Rng,
    want: usize,
) -> Vec<Clues> {
    let mut seen: BTreeSet<Clues> = BTreeSet::new();
    let mut out: Vec<Clues> = Vec::with_capacity(want);
    let push = |c: Clues, seen: &mut BTreeSet<Clues>, out: &mut Vec<Clues>| {
        if !table.contains_key(&c) && seen.insert(c) {
            out.push(c);
        }
    };
    for s in CURATED_UNSOLVABLE.iter() {
        if let Some(c) = parse_clues(s) {
            push(c, &mut seen, &mut out);
        }
    }
    // A draw guard rather than a bare `while`: the space is 4^16 wide and
    // collisions are vanishingly rare, but a bounded loop can never hang the
    // whole test suite if that assumption ever stops holding.
    let mut draws = 0usize;
    let cap = 40 * want + 1000;
    while out.len() < want && draws < cap {
        draws += 1;
        let c = if !solvable.is_empty() && rng.below(3) != 0 {
            // near miss: one clue of an achievable vector moved
            let (base, _) = &solvable[rng.below(solvable.len())];
            let mut c = *base;
            let i = rng.below(CELLS);
            let mut v = 1 + rng.below(N) as u8;
            if v == c[i] {
                v = 1 + (v % N as u8); // step to a different value, staying in 1..=N
            }
            c[i] = v;
            c
        } else {
            let mut c = [0u8; CELLS];
            let mut i = 0;
            while i < CELLS {
                c[i] = 1 + rng.below(N) as u8;
                i += 1;
            }
            c
        };
        // Through the same `push` as the curated entries, so the "is it really
        // unsolvable" test cannot diverge between the two sources.
        push(c, &mut seen, &mut out);
    }
    out
}

/// The corpus as a list of cases, in emission order.
///
/// SIZE: `max(count, 876)` lines — all 438 solvable vectors and at least 438
/// unsolvable ones. The floor is not negotiable downwards: "every achievable
/// vector at least once" is the contract this file advertises, so a small
/// `count` raises the corpus rather than truncating it (same shape as
/// `rush00::size_cases`, which ends in `truncate(count.max(out.len()))`). Above
/// the floor, every extra case is an unsolvable one, which is the right way for
/// this corpus to grow: the solvable half is already complete and cannot grow.
///
/// ORDER: the subject's own example first, then the two streams — solvable in
/// interesting-first order, unsolvable in curated-then-random order — merged by
/// seeded coin flips weighted by how many of each are left. Each stream keeps
/// its internal order; only the interleaving is drawn. So any slice a consumer
/// takes holds both a grid to validate and an `Error` to expect, instead of 438
/// grids and no `Error`.
///
/// A STRICT ALTERNATION IS WHAT THIS IS AVOIDING, and it is worth writing down
/// because it looks like the obvious answer and is a trap. A consumer that caps
/// its case count sensibly takes every k-th line — a STRIDE, precisely so that a
/// corpus ordered structured-first is not truncated down to one class of case.
/// Against a corpus that alternates solvable, unsolvable, solvable, …, every
/// even stride selects one class and nothing else: cap 876 cases at 400, land on
/// a stride of 2, and a runner would replay 400 unsolvable vectors and not one
/// grid — a green sweep that never checked a single solution. Any fixed period
/// has some stride that erases it, so the merge is drawn rather than patterned.
/// `check()` asserts the property directly, over strides 2..=12 at every offset.
///
/// Determinism is unaffected: same seed, same flips, same file (asserted too).
/// The exhaustiveness guarantee is a property of the WHOLE file — a consumer
/// that samples keeps a representative mix but no longer holds every achievable
/// vector.
fn corpus_cases(seed: u64, count: usize) -> Vec<(Clues, Vec<Grid>)> {
    let table = build_table();
    let solvable = solvable_cases(&table);
    let mut rng = Rng::new(seed);
    let want_unsolvable = count.saturating_sub(solvable.len()).max(solvable.len());
    let unsolvable = unsolvable_cases(&table, &solvable, &mut rng, want_unsolvable);

    let mut out: Vec<(Clues, Vec<Grid>)> = Vec::with_capacity(solvable.len() + unsolvable.len());
    let mut si = 0usize;
    let mut ui = 0usize;
    // The subject's worked example stays on line 0 whatever the seed: it is the
    // one case a human reads first when something looks wrong.
    if !solvable.is_empty() {
        out.push(solvable[0].clone());
        si = 1;
    }
    while si < solvable.len() || ui < unsolvable.len() {
        let s_left = solvable.len() - si;
        let u_left = unsolvable.len() - ui;
        let take_solvable = if s_left == 0 {
            false
        } else if u_left == 0 {
            true
        } else {
            rng.below(s_left + u_left) < s_left
        };
        if take_solvable {
            out.push(solvable[si].clone());
            si += 1;
        } else {
            out.push((unsolvable[ui], Vec::new()));
            ui += 1;
        }
    }
    out
}

/// Write the corpus. Generic over the writer so `check()` can inspect the exact
/// bytes this emits rather than a private structure the formatting could still
/// disagree with (same reason c05's ten-queens emitter is generic).
fn emit_corpus<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut line = String::with_capacity(2 * CELLS + 7 * CELLS);
    for (clues, sols) in corpus_cases(seed, count) {
        line.clear();
        line.push_str(&fmt_clues(&clues));
        // Unconditional, so a vector with no solution still ends in a TAB and
        // every line has the same shape: clue field, then one field per
        // solution.
        line.push(SOL_SEP);
        for (k, g) in sols.iter().enumerate() {
            if k > 0 {
                line.push(SOL_SEP);
            }
            push_grid(&mut line, g);
        }
        let _ = writeln!(w, "{}", line);
    }
}

fn gen_solve(seed: u64, count: usize) {
    let stdout = io::stdout();
    let mut w = io::BufWriter::new(stdout.lock());
    emit_corpus(&mut w, seed, count);
    let _ = w.flush();
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "rush01_solve" => gen_solve(seed, count),
        _ => return false,
    }
    true
}

// ------------------------------------------------------------- self-check

/// Self-check: the subject's worked example, the enumeration constants, and the
/// two independent implementations held against each other. Returns the failure
/// count.
///
/// This one guards more than a usual module. The corpus it validates is not
/// compared against anything at test time — the runner trusts the solution
/// fields to be the COMPLETE solution set, and a table that missed a solution would fail a
/// student whose program found it, which is this repo's worst failure mode. So
/// every constant the design rests on is re-derived here rather than assumed,
/// and the enumeration is cross-examined by a search that shares none of its
/// logic.
pub fn check() -> usize {
    let mut fails = 0usize;
    let table = build_table();

    // ---- the enumeration constants -------------------------------------
    //
    // These are checked against an INDEPENDENT enumeration done outside this
    // crate before the module was written. If the code below ever disagrees
    // with one of them, the code is what is wrong: do not edit the constant.
    let squares = all_latin_squares();
    if squares.len() != 576 {
        eprintln!(
            "CHECK FAIL rush01 {} Latin squares of order 4, want 576",
            squares.len()
        );
        fails += 1;
    }
    if table.len() != 438 {
        eprintln!(
            "CHECK FAIL rush01 {} achievable clue vectors, want 438",
            table.len()
        );
        fails += 1;
    }
    let mut hist = [0usize; 8]; // solutions-per-vector, 1..=6 in practice
    let mut total_solutions = 0usize;
    for sols in table.values() {
        total_solutions += sols.len();
        if sols.len() < hist.len() {
            hist[sols.len()] += 1;
        } else {
            eprintln!("CHECK FAIL rush01 a vector has {} solutions", sols.len());
            fails += 1;
        }
    }
    for (n, want) in [(1usize, 372usize), (2, 34), (3, 0), (4, 28), (5, 0), (6, 4)] {
        if hist[n] != want {
            eprintln!(
                "CHECK FAIL rush01 {} vectors with {} solution(s), want {}",
                hist[n], n, want
            );
            fails += 1;
        }
    }
    // Redundant on purpose: 372*1 + 34*2 + 28*4 + 4*6 = 576, so the histogram
    // and the square count pin each other and a compensating pair of errors
    // would have to break this too.
    if total_solutions != 576 {
        eprintln!(
            "CHECK FAIL rush01 table holds {} solutions in total, want 576",
            total_solutions
        );
        fails += 1;
    }

    // ---- the subject's worked example ----------------------------------
    //
    // The one assertion that pins the CLUE LAYOUT. Everything else in this file
    // is self-consistent under a transposition of top/bottom or left/right; this
    // is not, because the subject printed the answer.
    let subject = match parse_clues(SUBJECT_CLUES) {
        Some(c) => c,
        None => {
            eprintln!("CHECK FAIL rush01 SUBJECT_CLUES does not parse");
            fails += 1;
            [1u8; CELLS]
        }
    };
    match table.get(&subject) {
        None => {
            eprintln!("CHECK FAIL rush01 the subject's example has no solution");
            fails += 1;
        }
        Some(sols) => {
            // Joined with SOL_SEP rather than a prettier separator: the point is
            // that the subject's example produces exactly ONE field, so anything
            // else must fail this comparison, and using the emitted separator is
            // what makes "one field" the thing being asserted.
            let mut got = String::new();
            for (k, g) in sols.iter().enumerate() {
                if k > 0 {
                    got.push(SOL_SEP);
                }
                push_grid(&mut got, g);
            }
            if got != SUBJECT_SOLUTION {
                eprintln!(
                    "CHECK FAIL rush01 subject example -> {}, want exactly {}",
                    got, SUBJECT_SOLUTION
                );
                fails += 1;
            }
            // ...and that the digit string is the grid the subject's transcript
            // shows, laid out the way the exercise prints it.
            if sols.len() == 1 && display(&sols[0]) != "1 2 3 4\n2 3 4 1\n3 4 1 2\n4 1 2 3\n" {
                eprintln!(
                    "CHECK FAIL rush01 subject example renders as\n{}",
                    display(&sols[0])
                );
                fails += 1;
            }
        }
    }
    // The all-ones vector: sixteen sides that each see one box, which no grid
    // can do. Its `Error` is the corpus's simplest line and worth pinning.
    if table.contains_key(&[1u8; CELLS]) {
        eprintln!("CHECK FAIL rush01 the all-ones vector reports a solution");
        fails += 1;
    }

    // ---- the two visibility counters agree, over every 4-tuple ----------
    // 4^4 = 256 lines, repeats included (a partial line during a search is not
    // a permutation, so the repeat cases are reachable and not decorative).
    for a in 1..=N as u8 {
        for b in 1..=N as u8 {
            for c in 1..=N as u8 {
                for d in 1..=N as u8 {
                    let line = [a, b, c, d];
                    if visible(&line) != visible_rescan(&line) {
                        eprintln!(
                            "CHECK FAIL rush01 visibility {:?}: {} vs {}",
                            line,
                            visible(&line),
                            visible_rescan(&line)
                        );
                        fails += 1;
                    }
                }
            }
        }
    }
    // Two hand-worked lines, so a pair of counters that are wrong the SAME way
    // still fails: 1,2,3,4 shows all four boxes, 4,3,2,1 hides three behind the
    // first.
    if visible(&[1, 2, 3, 4]) != 4 || visible(&[4, 3, 2, 1]) != 1 || visible(&[2, 1, 4, 3]) != 2 {
        eprintln!("CHECK FAIL rush01 hand-worked visibility counts");
        fails += 1;
    }

    // ---- every stored solution really answers its vector ----------------
    let mut shown = 0usize;
    let mut all_grids: BTreeSet<Grid> = BTreeSet::new();
    for (clues, sols) in table.iter() {
        for g in sols {
            if !answers(g, clues) {
                fails += 1;
                if shown < 5 {
                    eprintln!(
                        "CHECK FAIL rush01 grid {:?} does not answer {}",
                        g,
                        fmt_clues(clues)
                    );
                    shown += 1;
                }
            }
            all_grids.insert(*g);
        }
        // Ascending and duplicate-free, which the enumeration gives for free and
        // the runner's membership test would not notice the loss of.
        let mut k = 1usize;
        while k < sols.len() {
            if sols[k] <= sols[k - 1] {
                eprintln!(
                    "CHECK FAIL rush01 solutions of {} out of order or repeated",
                    fmt_clues(clues)
                );
                fails += 1;
                break;
            }
            k += 1;
        }
    }
    // 576 solutions across the table and 576 DISTINCT grids: every Latin square
    // appears exactly once, so no square was double-counted into two vectors.
    if all_grids.len() != 576 {
        eprintln!(
            "CHECK FAIL rush01 {} distinct grids across the table, want 576",
            all_grids.len()
        );
        fails += 1;
    }

    // ---- the independent search agrees, vector by vector ----------------
    //
    // 438 exhaustive searches against 438 table entries. This is the assertion
    // that makes "the solution fields are the COMPLETE set" a checked claim rather
    // than a hope: a missing solution here is a correct student marked wrong.
    let mut shown = 0usize;
    for (clues, sols) in table.iter() {
        let found = search(clues, usize::MAX);
        if found != *sols {
            fails += 1;
            if shown < 5 {
                eprintln!(
                    "CHECK FAIL rush01 search disagrees on {}: {} found vs {} tabled",
                    fmt_clues(clues),
                    found.len(),
                    sols.len()
                );
                shown += 1;
            }
        }
        // ...and the first-solution mode agrees with the first of them.
        let first = search(clues, 1);
        if first.len() != 1 || first[0] != sols[0] {
            eprintln!(
                "CHECK FAIL rush01 first-solution search on {}",
                fmt_clues(clues)
            );
            fails += 1;
        }
    }

    // ---- the curated unsolvable list is still unsolvable -----------------
    for s in CURATED_UNSOLVABLE.iter() {
        match parse_clues(s) {
            None => {
                eprintln!("CHECK FAIL rush01 curated vector {:?} does not parse", s);
                fails += 1;
            }
            Some(c) => {
                if table.contains_key(&c) || !search(&c, 1).is_empty() {
                    eprintln!("CHECK FAIL rush01 curated vector {:?} IS solvable", s);
                    fails += 1;
                }
            }
        }
    }

    // ---- table and search agree on random well-formed vectors ------------
    // 4000 draws off a fixed seed. Nearly all are unsolvable (the space is
    // 4 294 966 858/4 294 967 296 unsolvable), so this is mostly a check that
    // neither implementation invents a solution — the failure that would print a
    // grid where `Error` was correct.
    let mut rng = Rng::new(20260728);
    let mut shown = 0usize;
    for _ in 0..4000 {
        let mut c = [0u8; CELLS];
        let mut i = 0;
        while i < CELLS {
            c[i] = 1 + rng.below(N) as u8;
            i += 1;
        }
        let found = search(&c, usize::MAX);
        let tabled = table.get(&c).cloned().unwrap_or_default();
        if found != tabled {
            fails += 1;
            if shown < 5 {
                eprintln!(
                    "CHECK FAIL rush01 search/table disagree on {}: {} vs {}",
                    fmt_clues(&c),
                    found.len(),
                    tabled.len()
                );
                shown += 1;
            }
        }
    }

    // ---- the corpus itself: format, contract and head --------------------
    //
    // Generator self-check, the kind only c00 and rush do: assert the CORPUS
    // still contains what this file advertises, which nothing downstream would
    // notice the loss of. Everything below reads the emitted BYTES.
    let mut buf: Vec<u8> = Vec::new();
    emit_corpus(&mut buf, 1, 0);
    let text = String::from_utf8_lossy(&buf).into_owned();
    let lines: Vec<&str> = text.lines().collect();
    if lines.len() != 876 {
        eprintln!(
            "CHECK FAIL rush01 corpus(seed=1, count=0) has {} lines, want 876",
            lines.len()
        );
        fails += 1;
    }
    let mut solvable_seen: BTreeSet<Clues> = BTreeSet::new();
    let mut seen_lines: BTreeSet<Clues> = BTreeSet::new();
    let mut unsolvable_seen = 0usize;
    let mut shown = 0usize;
    for (ln, raw) in lines.iter().enumerate() {
        let mut it = raw.split(SOL_SEP);
        let f1 = it.next();
        // Everything after the clue field is a solution field. An unsolvable
        // line is the one case that carries exactly one, empty, field — anything
        // else empty (a doubled tab, a trailing tab after real solutions) is a
        // corrupt line, and the consumer would silently skip it rather than
        // complain, so it has to be caught here.
        let fields: Vec<&str> = it.collect();
        let empty_field = fields.iter().any(|f| f.is_empty());
        if fields.is_empty() || (empty_field && fields.len() != 1) {
            fails += 1;
            if shown < 5 {
                eprintln!(
                    "CHECK FAIL rush01 line {} has a missing or empty solution field: {:?}",
                    ln, raw
                );
                shown += 1;
            }
            continue;
        }
        let clues = match f1.and_then(parse_clues) {
            Some(c) => c,
            None => {
                fails += 1;
                if shown < 5 {
                    eprintln!("CHECK FAIL rush01 line {} clue field {:?}", ln, f1);
                    shown += 1;
                }
                continue;
            }
        };
        if !seen_lines.insert(clues) {
            eprintln!("CHECK FAIL rush01 duplicate clue vector at line {}", ln);
            fails += 1;
        }
        if fields == [""] {
            // An `Error` line, and it must genuinely have no answer.
            unsolvable_seen += 1;
            if !search(&clues, 1).is_empty() {
                eprintln!(
                    "CHECK FAIL rush01 line {} claims no solution but has one",
                    ln
                );
                fails += 1;
            }
            continue;
        }
        solvable_seen.insert(clues);
        let mut prev: Option<Grid> = None;
        let mut n_here = 0usize;
        for tok in fields.iter() {
            let b = tok.as_bytes();
            let mut g = [0u8; CELLS];
            let mut ok = b.len() == CELLS;
            if ok {
                let mut i = 0;
                while i < CELLS {
                    if b[i] < b'1' || b[i] > b'0' + N as u8 {
                        ok = false;
                        break;
                    }
                    g[i] = b[i] - b'0';
                    i += 1;
                }
            }
            // Parsed back out of the printed bytes and validated from scratch:
            // this is exactly the test the runner will apply to the student's
            // grid, run here against our own output.
            if !ok || !answers(&g, &clues) {
                fails += 1;
                if shown < 5 {
                    eprintln!("CHECK FAIL rush01 line {} bad solution {:?}", ln, tok);
                    shown += 1;
                }
                continue;
            }
            if let Some(p) = prev {
                if g <= p {
                    eprintln!("CHECK FAIL rush01 line {} solutions out of order", ln);
                    fails += 1;
                }
            }
            prev = Some(g);
            n_here += 1;
        }
        // The listed set is the WHOLE set, not a prefix of it.
        if n_here != table.get(&clues).map_or(0, |v| v.len()) {
            eprintln!(
                "CHECK FAIL rush01 line {} lists {} solutions, table has {}",
                ln,
                n_here,
                table.get(&clues).map_or(0, |v| v.len())
            );
            fails += 1;
        }
    }
    // The contract in one line: every achievable vector is in the corpus.
    if solvable_seen.len() != 438 {
        eprintln!(
            "CHECK FAIL rush01 corpus carries {} solvable vectors, want all 438",
            solvable_seen.len()
        );
        fails += 1;
    }
    if unsolvable_seen != 438 {
        eprintln!(
            "CHECK FAIL rush01 corpus carries {} unsolvable vectors, want 438 at the floor",
            unsolvable_seen
        );
        fails += 1;
    }
    // The head pins the subject's example — and pins it with a LITERAL tab,
    // spelled out here rather than through SOL_SEP, because this is where the
    // separator itself is under test.
    let want_line0 = format!("{}\t{}", SUBJECT_CLUES, SUBJECT_SOLUTION);
    if lines.first() != Some(&&want_line0[..]) {
        eprintln!(
            "CHECK FAIL rush01 corpus line 0 is {:?}, want {:?}",
            lines.first(),
            want_line0
        );
        fails += 1;
    }
    // No `|` ANYWHERE in the corpus. The consumer strips `/`, `,`, `|` and
    // spaces from inside a solution field (so a reference may write a grid as
    // `1234/2341/3412/4123`), which makes `|` between two solutions read as one
    // 32-digit grid — the whole corpus rejected, the sweep exit 2, every student
    // reddened including a correct one. It cost this module a round trip, so it
    // is asserted by name and not left to the line-0 comparison above to imply.
    if text.contains('|') {
        eprintln!(
            "CHECK FAIL rush01 corpus contains '|', which the consumer strips inside a field"
        );
        fails += 1;
    }
    // Every solution field is 16 digits when split on a LITERAL tab. Same
    // reasoning: this is the assertion a change to SOL_SEP has to survive, so it
    // may not be written through SOL_SEP.
    let mut shown = 0usize;
    for (ln, raw) in lines.iter().enumerate() {
        for (k, f) in raw.split('\t').enumerate().skip(1) {
            if f.len() != CELLS && !(k == 1 && f.is_empty()) {
                fails += 1;
                if shown < 5 {
                    eprintln!(
                        "CHECK FAIL rush01 line {} field {} is {} bytes, want {} digits",
                        ln,
                        k,
                        f.len(),
                        CELLS
                    );
                    shown += 1;
                }
            }
        }
    }
    // ...and SAMPLING the corpus keeps both kinds. This is the assertion behind
    // the drawn merge in `corpus_cases`: a consumer that caps its case count
    // takes every k-th line, and against a strictly alternating corpus every
    // even k would select one class and nothing else — 400 `Error` cases and not
    // one grid validated, reported as a pass. Both a short prefix and every
    // stride from 2 to 12 must stay recognisably mixed (a quarter each way; the
    // corpus is 50/50 at the floor, so a healthy sample is nowhere near this
    // bound and the check fires only on a real collapse).
    //
    // "Ends in a separator" IS "no solutions", by the format: a solution field is
    // 16 digits, so a line whose last byte is the separator has an empty final
    // field and no others.
    let is_solvable = |l: &str| !l.ends_with(SOL_SEP);
    let head_solvable = lines.iter().take(10).filter(|l| is_solvable(l)).count();
    if head_solvable == 0 || head_solvable == 10 {
        eprintln!(
            "CHECK FAIL rush01 first 10 lines hold {} solvable cases, want a mix",
            head_solvable
        );
        fails += 1;
    }
    // Every stride, at every starting offset — the offset matters as much as the
    // stride, since a sampler keeping `i % k == 0` over 1-based line numbers
    // lands on a different phase than one keeping every k-th from the top, and
    // an alternating corpus fails one of the two whichever way it is written.
    // This corpus is 50/50 at the floor, so a quarter each way is a wide margin
    // around a healthy sample and a tight net around a collapse.
    let mut shown = 0usize;
    for k in 2..=12usize {
        for phase in 0..k {
            let mut kept = 0usize;
            let mut s = 0usize;
            let mut i = phase;
            while i < lines.len() {
                kept += 1;
                if is_solvable(lines[i]) {
                    s += 1;
                }
                i += k;
            }
            if kept > 0 && (s * 4 < kept || (kept - s) * 4 < kept) {
                fails += 1;
                if shown < 5 {
                    eprintln!(
                        "CHECK FAIL rush01 every {}th line from offset {}: {} of {} solvable, want a mix",
                        k, phase, s, kept
                    );
                    shown += 1;
                }
            }
        }
    }
    // The curated unsolvable vectors are IN the emitted corpus, not merely
    // unsolvable in principle.
    for s in CURATED_UNSOLVABLE.iter() {
        if let Some(c) = parse_clues(s) {
            if !seen_lines.contains(&c) {
                eprintln!("CHECK FAIL rush01 curated vector {:?} missing from the corpus", s);
                fails += 1;
            }
        }
    }
    // Growth: above the floor the corpus is exactly `count` lines, and the extra
    // ones are all unsolvable (the solvable half is already complete).
    let mut big: Vec<u8> = Vec::new();
    emit_corpus(&mut big, 7, 1500);
    let big_text = String::from_utf8_lossy(&big).into_owned();
    let big_lines: Vec<&str> = big_text.lines().collect();
    let big_solvable = big_lines.iter().filter(|l| !l.ends_with(SOL_SEP)).count();
    if big_lines.len() != 1500 || big_solvable != 438 {
        eprintln!(
            "CHECK FAIL rush01 corpus(seed=7, count=1500): {} lines, {} solvable; want 1500 and 438",
            big_lines.len(),
            big_solvable
        );
        fails += 1;
    }
    // Determinism, the contract the whole crate rests on: same seed and count,
    // same bytes. Cheap to assert here and impossible to notice downstream,
    // where it would surface as a diff that "sometimes" fails.
    let mut again: Vec<u8> = Vec::new();
    emit_corpus(&mut again, 1, 0);
    if again != buf {
        eprintln!("CHECK FAIL rush01 corpus is not reproducible for a fixed seed");
        fails += 1;
    }

    fails
}

// ------------------------------------------------------------- bench

/// `oracle bench rush01_solve` — replay a corpus on stdin and SOLVE each vector,
/// printing nothing. The perf baseline; see c05::bench for why a bench arm reads
/// its corpus rather than generating one.
///
/// It runs the single-vector `search()` with `limit = 1`, which is deliberate on
/// both counts and worth being explicit about, because two easier arms are
/// available here and both would lie:
///
///   * Looking the vector up in the table would time a `BTreeMap` probe against
///     a student's search. The ratio would be enormous and would say nothing
///     about either program.
///   * Rebuilding the whole table would time an amortised enumeration — one pass
///     for 876 cases — against a student's program, which pays a fresh search
///     per invocation. Different job, meaningless comparison.
///
/// `limit = 1` because the student stops at the first solution too: same work,
/// case for case. Unsolvable vectors exhaust the space on both sides, which is
/// the majority of the corpus and the honest bulk of the measurement.
pub fn bench(name: &str) -> bool {
    match name {
        "rush01_solve" => {
            let mut acc: usize = 0;
            for line in bench_lines() {
                if let Some(c) = line.split('\t').next().and_then(parse_clues) {
                    acc = acc.wrapping_add(search(&c, 1).len());
                }
            }
            sink(acc);
        }
        _ => return false,
    }
    true
}
