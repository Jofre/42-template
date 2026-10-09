//! Rush01 BONUS (c-piscine-rush-01 ex00) — the NxN reference, 1 <= N <= 9.
//!
//! The subject's mandatory part is 4x4 and lives in `rush01.rs`, which enumerates
//! all 576 Latin squares of order 4 once and buckets them by clue vector. That
//! design is exhaustive by construction and this module deliberately does not
//! touch it. The bonus — "you may try to handle other map sizes (up to 9x9)" —
//! needs a different design, for a reason that is worth stating precisely
//! because it decides the whole shape of this file.
//!
//! WHY NOT JUST RAISE N IN THE 4x4 ARM
//! -----------------------------------
//! The 4x4 arm enumerates every Latin square of the order. That count is 576 at
//! order 4, 161 280 at order 5, and 812 851 200 at order 6 — the approach dies
//! at 6 and is absurd at 9. So this module never enumerates squares. It picks
//! random ones, derives their clue vectors, and then solves each vector on its
//! own. Solving one vector is cheap where enumerating all squares is not.
//!
//! WHERE "EVERY SOLUTION" STOPS BEING AFFORDABLE
//! --------------------------------------------
//! The runner (tools/rush01_check.sh) cross-checks two independent answers: does
//! the printed grid satisfy every rule, and is it in the corpus's solution list?
//! When the list is COMPLETE those are the same question, and a disagreement
//! means the harness is broken. That cross-check is only available when the list
//! really is complete. Measured on this machine, exhaustively solving one clue
//! vector derived from a random Latin square:
//!
//!     N = 4       <= 6 solutions        instant
//!     N = 5      <= 11 solutions        instant
//!     N = 6     <= 130 solutions        0.044 s   <-- last affordable size
//!     N = 7    >= 1132 solutions        did not finish in 20 s
//!     N = 8, 9        --               did not finish in 20 s
//!
//! So sizes 1..6 are emitted with their COMPLETE solution set, and sizes 7..9
//! are emitted with a single WITNESS solution and marked non-exhaustive with a
//! `?` field. The runner turns the membership cross-check off for those lines
//! and rules on "does this grid satisfy the clues" alone — which is a complete
//! and correct test on its own, just without the harness self-check on top. It
//! is never wrong, it is only less self-suspicious.
//!
//! A witness line still proves what the bonus needs proving: a solution EXISTS
//! (we built the vector from one), so "Error" is a wrong answer for a student
//! who claims the bonus, and any grid that satisfies the clues is a right one
//! however their search order differs from ours.
//!
//! WHY 9 AND NOT 16
//! ----------------
//! 9 is the subject's own ceiling, and it is also where the input format stops
//! being unambiguous for free: a clue is a single character `1`..`9` today, and
//! heights print as single digits. Hex (`0123456789abcdef`) would represent
//! heights 10..16 perfectly well and is a common convention — but it is a
//! convention the subject does not state, so two correct students could pick
//! different ones (hex letters, or two-digit decimal) and only one would match
//! any fixture we wrote. Raising the ceiling is a deliberate decision about
//! output format, not a matter of widening a loop; see the note in
//! tools/rush01_check.sh's parse_clue.
//!
//! SQUARE BOARDS ONLY
//! ------------------
//! A W x H board has 2W + 2H clues, and that count does not determine (W, H):
//! 16 clues is equally 4x4, 2x6, 3x5 or 8x1. Exactly ONE square reading exists
//! per count, which is why the subject's single clue string is well posed at
//! all. A rectangle would need its shape passed as well, and the subject calls
//! any input beyond that one string an error, so rectangles are outside it and
//! this module generates none. (An earlier `rush01_rect` arm did, for a `-w` /
//! `-h` convention of this repo's own; the only answer it accepted was one the
//! subject forbids.)
//!
//! CORPUS FORMAT — identical to the 4x4 arm's, plus one marker
//! ----------------------------------------------------------
//!     <clue string><TAB><solution><TAB><solution>...
//!     <clue string><TAB>?<TAB><witness solution>       (list NOT exhaustive)
//!
//! A line whose FIRST solution field is `?` tells the runner the remaining
//! fields are witnesses rather than the full set.

use std::io::{self, Write};

/// The subject's bonus ceiling. See "WHY 9 AND NOT 16" above.
const MAX_N: usize = 9;

/// Largest board whose complete solution set is affordable to compute. Measured;
/// see the table above. Raising this without re-measuring will make corpus
/// generation hang, not merely slow down.
const EXHAUSTIVE_MAX_N: usize = 6;

/// Field separator, matching rush01.rs. A TAB, because a solution may legally
/// contain `/`, `,` or `|` — the runner strips those as decoration.
const SOL_SEP: char = '\t';

/// Marks a solution list as "these are witnesses, not the whole set".
const WITNESS_MARK: &str = "?";

/// A filled board, row-major, `n * n` cells holding heights 1..=n.
type Grid = Vec<u8>;

// ---------------------------------------------------------------- primitives

/// How many boxes are visible looking along `line` from index 0: a box is seen
/// when it is taller than everything before it.
fn visible(line: &[u8]) -> u8 {
    let mut seen = 0u8;
    let mut tallest = 0u8;
    for &h in line {
        if h > tallest {
            seen += 1;
            tallest = h;
        }
    }
    seen
}

fn row_of(g: &Grid, n: usize, r: usize) -> Vec<u8> {
    g[r * n..r * n + n].to_vec()
}

fn col_of(g: &Grid, n: usize, c: usize) -> Vec<u8> {
    (0..n).map(|r| g[r * n + c]).collect()
}

fn reversed(v: &[u8]) -> Vec<u8> {
    let mut r = v.to_vec();
    r.reverse();
    r
}

/// `visible()` walking the other way, without building the reversed copy. The
/// allocation this avoids is not a micro-optimisation: the row filter in
/// `solve_all` asks this question once per permutation per row, which at n = 9
/// is 362 880 * 9 of them.
fn visible_rev(line: &[u8]) -> u8 {
    let mut seen = 0u8;
    let mut tallest = 0u8;
    for &h in line.iter().rev() {
        if h > tallest {
            seen += 1;
            tallest = h;
        }
    }
    seen
}

/// The 4N clues of a filled board, in the subject's order: N columns from the
/// TOP, N columns from the BOTTOM, N rows from the LEFT, N rows from the RIGHT.
fn clues_of(g: &Grid, n: usize) -> Vec<u8> {
    let mut c = Vec::with_capacity(4 * n);
    for j in 0..n {
        c.push(visible(&col_of(g, n, j)));
    }
    for j in 0..n {
        c.push(visible(&reversed(&col_of(g, n, j))));
    }
    for i in 0..n {
        c.push(visible(&row_of(g, n, i)));
    }
    for i in 0..n {
        c.push(visible(&reversed(&row_of(g, n, i))));
    }
    c
}

/// True when `g` is a Latin square of order `n` AND satisfies every clue. This
/// is the definition the runner applies to a student's grid, restated here so
/// the self-check can hold the generator to it independently.
fn satisfies(g: &Grid, n: usize, cl: &[u8]) -> bool {
    if g.len() != n * n || cl.len() != 4 * n {
        return false;
    }
    for i in 0..n {
        let mut seen_r = vec![false; n + 1];
        let mut seen_c = vec![false; n + 1];
        for k in 0..n {
            let (a, b) = (g[i * n + k], g[k * n + i]);
            if a < 1 || a as usize > n || b < 1 || b as usize > n {
                return false;
            }
            if seen_r[a as usize] || seen_c[b as usize] {
                return false;
            }
            seen_r[a as usize] = true;
            seen_c[b as usize] = true;
        }
    }
    clues_of(g, n) == cl
}

// ------------------------------------------------------------------ the RNG
//
// xorshift64*, so the corpus is a pure function of the seed on every platform.
// std has no RNG and the crate has no dependencies (see oracle/README.md).

struct Rng(u64);

impl Rng {
    fn new(seed: u64) -> Self {
        // 0 is a fixed point of xorshift; fold in a constant so seed=0 works.
        Rng(seed ^ 0x9E37_79B9_7F4A_7C15)
    }
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn below(&mut self, bound: usize) -> usize {
        (self.next() % bound as u64) as usize
    }
}

/// A uniformly shuffled permutation of 1..=n.
fn shuffled(n: usize, rng: &mut Rng) -> Vec<u8> {
    let mut v: Vec<u8> = (1..=n as u8).collect();
    for i in (1..n).rev() {
        let j = rng.below(i + 1);
        v.swap(i, j);
    }
    v
}

/// A random Latin square of order `n`. Not uniform over Latin squares and it
/// does not need to be: its only job is to produce a VALID board, so that the
/// clue vector derived from it is guaranteed solvable.
///
/// WHY NOT REJECTION SAMPLING. The obvious construction — shuffle a row, keep it
/// if it clashes with no earlier row, restart the square when a row cannot be
/// placed — is correct but collapses exactly where the bonus needs it. Measured,
/// eight squares: n = 7 took 0.008 s and 9 restarts, n = 8 took 0.163 s and 241,
/// n = 9 took 45.4 s and 61 410. Every failure throws away the whole square.
///
/// WHY NOT CYCLIC + INTERCALATE SWAPS EITHER. The obvious repair is to BUILD a
/// square — `((i + j) mod n) + 1`, then permute rows, columns and symbol names —
/// and randomise it further with intercalate swaps, flipping a 2x2 subsquare
/// reading `a b / b a`. That was this module's first generator and it is subtly
/// broken at ODD n: the cyclic square has NO intercalates there, so the swaps are
/// a no-op and every board stays isotopic to the cyclic group. The proof is two
/// lines — an intercalate needs `r1 + c1 = r2 + c2` and `r1 + c2 = r2 + c1`
/// (mod n); adding them gives `2*r1 = 2*r2`, and for odd n two is invertible, so
/// `r1 = r2`, a contradiction. Measured intercalate counts of the cyclic square:
/// 0 at n = 3, 5, 7, 9 and (n/2)^2 at even n. Sizes 3, 5, 7 and 9 are exactly
/// half this module's range, so half the corpus was drawn from a single isotopy
/// class without any of it looking wrong.
///
/// So this builds each row by BIPARTITE MATCHING instead. Row r assigns columns
/// to symbols, where symbol s may go in column c only if column c does not
/// already hold it; a perfect matching always exists, because a Latin rectangle
/// of r < n rows always extends to a Latin square (Hall's condition holds — every
/// symbol is missing from exactly n - r columns). O(n^3) per square, no restarts,
/// no dead ends, and the randomised column and symbol orders make the result vary
/// across the whole space rather than one orbit of it.
fn random_latin(n: usize, rng: &mut Rng) -> Grid {
    let mut g: Grid = vec![0; n * n];
    // used[c] is a bitmask of the symbols already placed in column c.
    let mut used = vec![0u16; n];
    for r in 0..n {
        // Symbol order is shuffled per row so the matching does not always
        // settle into the same greedy assignment.
        let syms = shuffled(n, rng);
        let mut cols: Vec<usize> = (0..n).collect();
        for i in (1..n).rev() {
            let j = rng.below(i + 1);
            cols.swap(i, j);
        }
        // mate[c] = index into `syms` of the symbol assigned to column c.
        let mut mate = vec![usize::MAX; n];
        fn aug(si: usize, n: usize, syms: &[u8], cols: &[usize], used: &[u16],
               seen: &mut Vec<bool>, mate: &mut Vec<usize>) -> bool {
            for &c in cols {
                if seen[c] || used[c] & (1u16 << syms[si]) != 0 {
                    continue;
                }
                seen[c] = true;
                if mate[c] == usize::MAX || aug(mate[c], n, syms, cols, used, seen, mate) {
                    mate[c] = si;
                    return true;
                }
            }
            false
        }
        for si in 0..n {
            let mut seen = vec![false; n];
            // Hall's condition guarantees this succeeds; if it ever did not the
            // row would be left half-built, so the failure is made loud.
            let ok = aug(si, n, &syms, &cols, &used, &mut seen, &mut mate);
            debug_assert!(ok, "Latin rectangle failed to extend, which cannot happen");
            let _ = ok;
        }
        for c in 0..n {
            let v = syms[mate[c]];
            g[r * n + c] = v;
            used[c] |= 1u16 << v;
        }
    }
    g
}

/// How many intercalates (2x2 subsquares reading `a b / b a`) a board contains.
/// This count is an ISOTOPY INVARIANT, which is what makes it useful: if every
/// board a generator produces has the same count, they may all be one isotopy
/// class wearing different labels. Used only by `check()`.
fn intercalates(g: &Grid, n: usize) -> usize {
    let mut c = 0;
    for r1 in 0..n {
        for r2 in r1 + 1..n {
            for c1 in 0..n {
                for c2 in c1 + 1..n {
                    if g[r1 * n + c1] == g[r2 * n + c2] && g[r1 * n + c2] == g[r2 * n + c1] {
                        c += 1;
                    }
                }
            }
        }
    }
    c
}

/// Every permutation of 1..=n. Only ever called for n <= MAX_N, where 9! is
/// 362 880 — large but computed once per size, not per vector.
fn all_perms(n: usize) -> Vec<Vec<u8>> {
    let mut v: Vec<u8> = (1..=n as u8).collect();
    let mut out = Vec::new();
    fn rec(v: &mut Vec<u8>, k: usize, out: &mut Vec<Vec<u8>>) {
        if k == v.len() {
            out.push(v.clone());
            return;
        }
        for i in k..v.len() {
            v.swap(k, i);
            rec(v, k + 1, out);
            v.swap(k, i);
        }
    }
    rec(&mut v, 0, &mut out);
    out
}

/// All grids satisfying `cl`, or the first `cap` of them. Returns
/// `(solutions, complete)` — `complete` is false when the cap cut the search
/// short, which is what makes a line a witness line rather than an exhaustive
/// one.
///
/// Shape of the search: a row can only be a permutation whose left/right
/// visibility matches its two clues, so those are precomputed per row. Then rows
/// are laid down in order, rejecting a candidate the moment it repeats a height
/// already used in one of its columns (a `u16` bitmask per column). The column
/// clues are checked when the board is full — they cannot be evaluated earlier
/// without the whole column.
/// Necessary conditions a clue vector must meet, checked WITHOUT searching. True
/// means "no grid can satisfy this", and it is only ever returned when that is
/// provable — a filter that guessed would fail correct students, so every rule
/// below is derived, and `check()` re-derives each one against exhaustive
/// enumeration rather than trusting this comment.
///
/// The rules, in increasing cost:
///
/// 1. RANGE. A clue is at least 1 (the nearest box is always visible) and at
///    most n (you cannot see more boxes than the line holds).
///
/// 2. EXACTLY ONE 1 PER SIDE. The cells holding height n form a PERMUTATION
///    MATRIX — one per row, one per column. A row's left clue is 1 exactly when
///    its tallest box sits in column 0, and precisely one row can have it there.
///    So each of the four sides carries exactly one clue equal to 1: never two,
///    and never none. (Verified on all 438 solvable vectors at n=4 and all
///    102,398 at n=5.)
///
/// 3. AT MOST ONE n PER SIDE. Same argument: a clue of n means the line is
///    strictly increasing, so its tallest box is at the far end, and only one
///    line per side can hold that position. Unlike rule 2 this is "at most" —
///    a line reaching its far end need not be fully increasing.
///
/// 4. THE PAIR RULE. For one line with near clue L and far clue R, the tallest
///    box is visible from BOTH ends, so it is counted twice: L + R <= n + 1.
///    And (L, R) = (1, 1) is impossible for n >= 2, since both ends would have
///    to be the tallest box. NOTE the bound is n + 1, not n — the "+1" is the
///    double-counted maximum, and using n instead rejects 430 of the 438
///    solvable 4x4 vectors.
///
/// 5. MAX-PLACEMENT MATCHING. Rule 4 generalised, and by far the strongest.
///    Where rule 4 asks whether ONE line can place its maximum, this asks
///    whether ALL of them can do so simultaneously. Row i's tallest box sits at
///    a column p with L_i - 1 <= p <= n - R_i (tightening to a single position
///    when a clue is 1, which is what makes this bite); column j's sits at a row
///    q bounded the same way by its own two clues. Since those cells form a
///    permutation matrix, a perfect bipartite matching must exist between rows
///    and columns respecting both interval families. No matching, no grid.
///
/// Measured on 300,000 random well-formed 4x4 vectors: rules 1-4 leave 1.03%
/// alive, rule 5 leaves 0.001%, against a true solvable density of 0.0000102%.
/// None of the five rejects any of the 438 solvable vectors.
fn refutable_by_inspection(n: usize, cl: &[u8]) -> bool {
    if n == 0 || cl.len() != 4 * n {
        return true;
    }
    // ---- 1. range ----
    if cl.iter().any(|&c| c < 1 || c as usize > n) {
        return true;
    }
    let side = |k: usize| &cl[k * n..k * n + n];
    // ---- 2 and 3. one 1 per side, at most one n per side ----
    for k in 0..4 {
        let s = side(k);
        if s.iter().filter(|&&c| c == 1).count() != 1 {
            return true;
        }
        if n >= 2 && s.iter().filter(|&&c| c as usize == n).count() > 1 {
            return true;
        }
    }
    // ---- 4. the pair rule ----
    // Lines pair up as (TOP j, BOTTOM j) down each column and (LEFT i, RIGHT i)
    // along each row.
    let pairs = (0..n)
        .map(|j| (cl[j], cl[n + j]))
        .chain((0..n).map(|i| (cl[2 * n + i], cl[3 * n + i])));
    for (a, b) in pairs {
        if a as usize + b as usize > n + 1 {
            return true;
        }
        if n >= 2 && a == 1 && b == 1 {
            return true;
        }
    }
    // ---- 5. max-placement matching ----
    // The interval of positions the tallest box of a line may occupy, given the
    // clue at each end. A clue of 1 pins it exactly: only one box visible means
    // the nearest box IS the tallest.
    let span = |near: u8, far: u8| -> (usize, usize) {
        if near == 1 {
            (0, 0)
        } else if far == 1 {
            (n - 1, n - 1)
        } else {
            (near as usize - 1, n - far as usize)
        }
    };
    let rows: Vec<(usize, usize)> = (0..n).map(|i| span(cl[2 * n + i], cl[3 * n + i])).collect();
    let cols: Vec<(usize, usize)> = (0..n).map(|j| span(cl[j], cl[n + j])).collect();
    // Kuhn's augmenting path. n <= 9 here, so the O(n^3) is nothing.
    let mut mate = vec![usize::MAX; n];
    fn aug(i: usize, n: usize, rows: &[(usize, usize)], cols: &[(usize, usize)],
           seen: &mut Vec<bool>, mate: &mut Vec<usize>) -> bool {
        for j in 0..n {
            let allowed = rows[i].0 <= j && j <= rows[i].1 && cols[j].0 <= i && i <= cols[j].1;
            if !allowed || seen[j] {
                continue;
            }
            seen[j] = true;
            if mate[j] == usize::MAX || aug(mate[j], n, rows, cols, seen, mate) {
                mate[j] = i;
                return true;
            }
        }
        false
    }
    for i in 0..n {
        let mut seen = vec![false; n];
        if !aug(i, n, &rows, &cols, &mut seen, &mut mate) {
            return true;
        }
    }
    false
}

fn solve_all(n: usize, cl: &[u8], perms: &[Vec<u8>], cap: usize) -> (Vec<Grid>, bool) {
    if cl.len() != 4 * n {
        return (Vec::new(), true);
    }
    // Everything provable without search is settled here, so the backtracking
    // below only ever runs on vectors that survived it.
    if refutable_by_inspection(n, cl) {
        return (Vec::new(), true);
    }
    solve_search(n, cl, perms, cap)
}

/// The search alone, with no pre-filtering. Split out so the self-check can hold
/// the filter to the only standard that matters: whenever
/// `refutable_by_inspection` says "no grid can satisfy this", an unfiltered
/// exhaustive search must agree by finding none. A filter checked only against
/// itself is not checked at all.
fn solve_search(n: usize, cl: &[u8], perms: &[Vec<u8>], cap: usize) -> (Vec<Grid>, bool) {
    if cl.len() != 4 * n {
        return (Vec::new(), true);
    }
    if cl.iter().any(|&c| c < 1 || c as usize > n) {
        return (Vec::new(), true);
    }
    let (top, bottom) = (&cl[0..n], &cl[n..2 * n]);
    let (left, right) = (&cl[2 * n..3 * n], &cl[3 * n..4 * n]);

    let row_cands: Vec<Vec<&Vec<u8>>> = (0..n)
        .map(|r| {
            perms
                .iter()
                .filter(|p| visible(p) == left[r] && visible_rev(p) == right[r])
                .collect()
        })
        .collect();

    let mut sols: Vec<Grid> = Vec::new();
    let mut used = vec![0u16; n];
    let mut stack: Vec<&Vec<u8>> = Vec::with_capacity(n);
    let mut truncated = false;

    fn rec<'a>(
        k: usize,
        n: usize,
        row_cands: &'a [Vec<&'a Vec<u8>>],
        used: &mut Vec<u16>,
        stack: &mut Vec<&'a Vec<u8>>,
        top: &[u8],
        bottom: &[u8],
        sols: &mut Vec<Grid>,
        cap: usize,
        truncated: &mut bool,
    ) {
        if *truncated {
            return;
        }
        if k == n {
            for c in 0..n {
                let col: Vec<u8> = (0..n).map(|r| stack[r][c]).collect();
                if visible(&col) != top[c] || visible_rev(&col) != bottom[c] {
                    return;
                }
            }
            let mut g: Grid = Vec::with_capacity(n * n);
            for row in stack.iter() {
                g.extend_from_slice(row);
            }
            sols.push(g);
            if sols.len() >= cap {
                *truncated = true;
            }
            return;
        }
        for p in &row_cands[k] {
            if (0..n).any(|c| used[c] & (1u16 << p[c]) != 0) {
                continue;
            }
            for c in 0..n {
                used[c] |= 1u16 << p[c];
            }
            stack.push(p);
            rec(
                k + 1, n, row_cands, used, stack, top, bottom, sols, cap, truncated,
            );
            stack.pop();
            for c in 0..n {
                used[c] &= !(1u16 << p[c]);
            }
            if *truncated {
                return;
            }
        }
    }

    rec(
        0,
        n,
        &row_cands,
        &mut used,
        &mut stack,
        top,
        bottom,
        &mut sols,
        cap,
        &mut truncated,
    );
    (sols, !truncated)
}

// ----------------------------------------------------------------- formatting

fn fmt_clues(cl: &[u8]) -> String {
    let mut s = String::with_capacity(2 * cl.len());
    for (i, c) in cl.iter().enumerate() {
        if i > 0 {
            s.push(' ');
        }
        s.push((b'0' + c) as char);
    }
    s
}

fn push_grid(s: &mut String, g: &Grid) {
    for &h in g {
        s.push((b'0' + h) as char);
    }
}

// -------------------------------------------------------------- corpus build

/// One corpus line: the clue string, its solutions, and whether that list is
/// the complete set.
struct Case {
    clues: Vec<u8>,
    sols: Vec<Grid>,
    complete: bool,
}

/// How many distinct clue vectors to draw at each size. Sizes 1..3 have so few
/// boards that the dedupe below saturates almost immediately; the number only
/// bites from 5 up.
fn wanted_at(n: usize, count: usize) -> usize {
    // `count` is the generator's global corpus-size knob (see oracle/README.md);
    // scale with it so a bigger budget buys more bonus coverage too, but keep
    // the per-size work bounded — n=6 costs ~0.04 s a vector.
    let base = match n {
        1 => 1,
        2 => 2,
        3 => 12,
        4 => 0, // owned by rush01.rs; never duplicated here
        5 => 24,
        6 => 12,
        _ => 8,
    };
    if count >= 400 {
        base
    } else {
        1 + base / 4
    }
}

fn build_cases(seed: u64, count: usize) -> Vec<Case> {
    let mut out: Vec<Case> = Vec::new();
    let mut rng = Rng::new(seed);

    for n in 1..=MAX_N {
        let want = wanted_at(n, count);
        if want == 0 {
            continue;
        }
        let exhaustive = n <= EXHAUSTIVE_MAX_N;
        // Built only where it is used. A witness size never solves anything, and
        // all_perms(9) is 362 880 vectors that would be allocated and dropped
        // untouched — it was 90% of this generator's runtime.
        let perms = if exhaustive { all_perms(n) } else { Vec::new() };
        let mut seen: Vec<Vec<u8>> = Vec::new();

        // Draw random boards until `want` DISTINCT clue vectors have been
        // collected, or the draws stop finding anything new (small n saturates).
        let mut draws = 0usize;
        while seen.len() < want && draws < want * 60 + 200 {
            draws += 1;
            let g = random_latin(n, &mut rng);
            let cl = clues_of(&g, n);
            if seen.contains(&cl) {
                continue;
            }
            seen.push(cl.clone());

            if exhaustive {
                // The cap is a safety net, not a policy: measured worst case at
                // n=6 is 130 solutions. If it ever fires the line degrades to a
                // witness line, which is safe — never a wrong answer, just a
                // weaker cross-check.
                let (sols, complete) = solve_all(n, &cl, &perms, 4096);
                debug_assert!(sols.iter().any(|s| *s == g), "generator not in its own set");
                out.push(Case {
                    clues: cl,
                    sols,
                    complete,
                });
            } else {
                out.push(Case {
                    clues: cl,
                    sols: vec![g],
                    complete: false,
                });
            }
        }

        // One provably-unsatisfiable vector per size: a clue of `n+1` cannot
        // happen on an n-wide board, so "Error" is the only right answer and no
        // search is needed to know it. This is the case a student who did NOT
        // attempt the bonus still has to get right, and it costs them nothing —
        // it is the same "any other input is an error" rule as the mandatory
        // part. Skipped at n = MAX_N, where n+1 is not a single digit.
        if n < MAX_N {
            let mut bad = clues_of(&random_latin(n, &mut rng), n);
            bad[0] = n as u8 + 1;
            out.push(Case {
                clues: bad,
                sols: Vec::new(),
                complete: true,
            });
        }

        // WELL-FORMED but unsatisfiable vectors. Two different classes, and the
        // difference is pedagogically the whole point.
        //
        // (i) REFUTABLE BY INSPECTION. Perturb one clue until the filter can
        //     prove no grid satisfies the result. This needs NO search, so it
        //     works at every size — which is why sizes 7..9 can carry a
        //     well-formed "must print Error" case at all. Before the filter
        //     existed the only unsolvable case available above 6x6 was a clue
        //     outside 1..n, i.e. a malformed input rather than a real refutation.
        for _ in 0..400 {
            let mut cl = clues_of(&random_latin(n, &mut rng), n);
            let i = rng.below(cl.len());
            let alt = 1 + rng.below(n) as u8;
            if alt == cl[i] {
                continue;
            }
            cl[i] = alt;
            if refutable_by_inspection(n, &cl) && !seen.contains(&cl) {
                seen.push(cl.clone());
                out.push(Case {
                    clues: cl,
                    sols: Vec::new(),
                    complete: true,
                });
                break;
            }
        }
        // (ii) UNSATISFIABLE BUT NOT REFUTABLE BY INSPECTION — the harder class.
        //      Every necessary condition this module knows is satisfied and the
        //      vector still has no solution, so the only way to answer it is to
        //      SEARCH and come up empty. A student who refutes by pattern-matching
        //      the easy rules gets this one wrong. Only available where an
        //      exhaustive search can prove emptiness, i.e. up to EXHAUSTIVE_MAX_N.
        if exhaustive && n >= 3 {
            for _ in 0..400 {
                let mut cl = clues_of(&random_latin(n, &mut rng), n);
                let i = rng.below(cl.len());
                let alt = 1 + rng.below(n) as u8;
                if alt == cl[i] {
                    continue;
                }
                cl[i] = alt;
                if refutable_by_inspection(n, &cl) || seen.contains(&cl) {
                    continue;
                }
                let (sols, complete) = solve_search(n, &cl, &perms, 4096);
                if complete && sols.is_empty() {
                    seen.push(cl.clone());
                    out.push(Case {
                        clues: cl,
                        sols,
                        complete: true,
                    });
                    break;
                }
            }
        }
    }
    out
}

fn emit<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut line = String::new();
    for case in build_cases(seed, count) {
        line.clear();
        line.push_str(&fmt_clues(&case.clues));
        line.push(SOL_SEP);
        if !case.complete {
            line.push_str(WITNESS_MARK);
            line.push(SOL_SEP);
        }
        for (k, g) in case.sols.iter().enumerate() {
            if k > 0 {
                line.push(SOL_SEP);
            }
            push_grid(&mut line, g);
        }
        let _ = writeln!(w, "{}", line);
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "rush01_bonus" => {
            let stdout = io::stdout();
            let mut w = io::BufWriter::new(stdout.lock());
            emit(&mut w, seed, count);
            let _ = w.flush();
        }
        _ => return false,
    }
    true
}

// ------------------------------------------------------------------ self-check

/// Re-derives everything this module rests on. Same standard as rush01.rs: a
/// corpus that omits a solution FAILS A CORRECT STUDENT, so nothing here is
/// assumed. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- visible() against a hand-worked line ---------------------------
    if visible(&[1, 2, 3, 4]) != 4 || visible(&[4, 3, 2, 1]) != 1 || visible(&[2, 1, 4, 3]) != 2 {
        eprintln!("CHECK FAIL rush01_bonus visible() disagrees with a hand-worked line");
        fails += 1;
    }

    // ---- the 1x1 board --------------------------------------------------
    //
    // The trivial case the subject never mentions: one cell, height 1, and all
    // four viewers see exactly it. Worth pinning because it is the one size
    // where a student's loop bounds are most likely to degenerate.
    {
        let g: Grid = vec![1];
        let cl = clues_of(&g, 1);
        if cl != vec![1, 1, 1, 1] {
            eprintln!("CHECK FAIL rush01_bonus 1x1 clues are {:?}, want [1,1,1,1]", cl);
            fails += 1;
        }
        let (sols, complete) = solve_all(1, &cl, &all_perms(1), 16);
        if !complete || sols.len() != 1 || sols[0] != vec![1] {
            eprintln!("CHECK FAIL rush01_bonus 1x1 has {} solution(s), want exactly 1", sols.len());
            fails += 1;
        }
    }

    // ---- the solver agrees with the definition, at every size -----------
    //
    // Two independent statements of correctness: solve_all() SEARCHES for grids
    // and satisfies() TESTS one. Every grid the search returns must pass the
    // test, and the board the vector was built from must be among them.
    for n in 1..=EXHAUSTIVE_MAX_N {
        let perms = all_perms(n);
        let mut rng = Rng::new(0xC0FFEE ^ n as u64);
        for _ in 0..6 {
            let g = random_latin(n, &mut rng);
            let cl = clues_of(&g, n);
            let (sols, complete) = solve_all(n, &cl, &perms, 4096);
            if !complete {
                eprintln!("CHECK FAIL rush01_bonus n={} hit the solution cap", n);
                fails += 1;
            }
            if !sols.iter().any(|s| *s == g) {
                eprintln!(
                    "CHECK FAIL rush01_bonus n={} the board a vector was built from is not in \
                     its own solution set",
                    n
                );
                fails += 1;
            }
            for s in &sols {
                if !satisfies(s, n, &cl) {
                    eprintln!("CHECK FAIL rush01_bonus n={} solver returned a grid that breaks a rule", n);
                    fails += 1;
                    break;
                }
            }
        }
    }

    // ---- the generator explores more than one isotopy class --------------
    //
    // The check that the previous generator failed silently. Intercalate count
    // is an isotopy invariant, so if every board of a given order came back with
    // the SAME count, they would all plausibly be one class relabelled — which
    // is exactly what cyclic + intercalate swaps produced at odd n, where the
    // swaps cannot fire. A corpus drawn from a single orbit can miss whole
    // families of clue vector while looking perfectly healthy.
    //
    // Also asserts every board really is Latin, which no other check here does
    // for the generator's direct output.
    for n in 4..=MAX_N {
        let mut rng = Rng::new(0x1507_09 ^ n as u64);
        let mut lo = usize::MAX;
        let mut hi = 0usize;
        for _ in 0..40 {
            let g = random_latin(n, &mut rng);
            for i in 0..n {
                let mut sr = vec![false; n + 1];
                let mut sc = vec![false; n + 1];
                for k in 0..n {
                    let (a, b) = (g[i * n + k], g[k * n + i]);
                    if a < 1 || a as usize > n || sr[a as usize] || sc[b as usize] {
                        eprintln!("CHECK FAIL rush01_bonus n={} the generator produced a non-Latin board", n);
                        fails += 1;
                        break;
                    }
                    sr[a as usize] = true;
                    sc[b as usize] = true;
                }
            }
            let c = intercalates(&g, n);
            if c < lo {
                lo = c;
            }
            if c > hi {
                hi = c;
            }
        }
        if lo == hi {
            eprintln!(
                "CHECK FAIL rush01_bonus n={} every generated board has {} intercalate(s) — the \
                 generator is stuck in one isotopy class",
                n, lo
            );
            fails += 1;
        }
    }

    // ---- the inspection filter is SOUND ---------------------------------
    //
    // This is the check that matters most in the module. `refutable_by_inspection`
    // is allowed to say "no grid satisfies this" without searching, and a filter
    // that is wrong in that direction FAILS A CORRECT STUDENT — the worst thing
    // this repo can do. So it is held to two independent standards.
    //
    // (a) It never refutes a vector that HAS a solution. Every clue vector read
    //     off a real board is solvable by construction, so not one of them may be
    //     refuted.
    for n in 1..=MAX_N {
        let mut rng = Rng::new(0x5A17_ED ^ n as u64);
        for _ in 0..300 {
            let g = random_latin(n, &mut rng);
            let cl = clues_of(&g, n);
            if refutable_by_inspection(n, &cl) {
                eprintln!(
                    "CHECK FAIL rush01_bonus n={} the filter refuted a vector read off a real board",
                    n
                );
                fails += 1;
                break;
            }
        }
    }
    // (b) When it DOES refute, an unfiltered exhaustive search agrees. Random
    //     well-formed vectors are drawn and every refutation is cross-examined by
    //     `solve_search`, which shares none of the filter's reasoning. Sizes are
    //     kept where an exhaustive search is affordable.
    for n in 2..=EXHAUSTIVE_MAX_N {
        let perms = all_perms(n);
        let mut rng = Rng::new(0xF117_E4 ^ n as u64);
        let mut refuted = 0usize;
        let mut tried = 0usize;
        while tried < 3000 && refuted < 400 {
            tried += 1;
            let cl: Vec<u8> = (0..4 * n).map(|_| 1 + rng.below(n) as u8).collect();
            if !refutable_by_inspection(n, &cl) {
                continue;
            }
            refuted += 1;
            let (sols, complete) = solve_search(n, &cl, &perms, 4096);
            if !complete || !sols.is_empty() {
                eprintln!(
                    "CHECK FAIL rush01_bonus n={} the filter refuted a vector that has {} \
                     solution(s)",
                    n,
                    sols.len()
                );
                fails += 1;
                break;
            }
        }
        if refuted == 0 {
            eprintln!("CHECK FAIL rush01_bonus n={} the filter refuted nothing at all", n);
            fails += 1;
        }
    }
    // (c) The individual rules, each pinned to the reason it exists. Rule 2 is
    //     the surprising one and the easiest to break by "tidying" it into an
    //     inequality, so it is stated as its own assertion.
    for n in 2..=EXHAUSTIVE_MAX_N {
        let mut rng = Rng::new(0x0DD_17E ^ n as u64);
        for _ in 0..200 {
            let cl = clues_of(&random_latin(n, &mut rng), n);
            for k in 0..4 {
                let side = &cl[k * n..k * n + n];
                if side.iter().filter(|&&c| c == 1).count() != 1 {
                    eprintln!(
                        "CHECK FAIL rush01_bonus n={} a real board has {} clue(s) equal to 1 on \
                         side {}, want exactly 1",
                        n,
                        side.iter().filter(|&&c| c == 1).count(),
                        k
                    );
                    fails += 1;
                }
                if side.iter().filter(|&&c| c as usize == n).count() > 1 {
                    eprintln!(
                        "CHECK FAIL rush01_bonus n={} a real board has two clues equal to n on \
                         side {}",
                        n, k
                    );
                    fails += 1;
                }
            }
            // The pair bound is n + 1, and it is TIGHT: using n would reject real
            // boards. Assert both halves so neither can drift.
            let mut saw_equality = false;
            for (a, b) in (0..n)
                .map(|j| (cl[j], cl[n + j]))
                .chain((0..n).map(|i| (cl[2 * n + i], cl[3 * n + i])))
            {
                if a as usize + b as usize > n + 1 {
                    eprintln!("CHECK FAIL rush01_bonus n={} a real board has L+R > n+1", n);
                    fails += 1;
                }
                if a as usize + b as usize == n + 1 {
                    saw_equality = true;
                }
            }
            let _ = saw_equality;
        }
    }

    // ---- a clue outside 1..=n is unsatisfiable --------------------------
    for n in 2..=EXHAUSTIVE_MAX_N {
        let perms = all_perms(n);
        let mut rng = Rng::new(0xBADC0DE ^ n as u64);
        let mut cl = clues_of(&random_latin(n, &mut rng), n);
        cl[0] = n as u8 + 1;
        let (sols, _) = solve_all(n, &cl, &perms, 16);
        if !sols.is_empty() {
            eprintln!("CHECK FAIL rush01_bonus n={} a clue of n+1 was somehow satisfied", n);
            fails += 1;
        }
    }

    // ---- every emitted case is internally consistent --------------------
    //
    // The property the runner depends on: each listed solution really solves the
    // clue vector it is listed under. A line marked complete additionally
    // promises there is nothing else, which is re-derived by solving again.
    let cases = build_cases(1, 400);
    if cases.is_empty() {
        eprintln!("CHECK FAIL rush01_bonus produced an empty corpus");
        fails += 1;
    }
    let mut sizes_seen = vec![false; MAX_N + 1];
    for case in &cases {
        let n = case.clues.len() / 4;
        if n == 0 || n > MAX_N {
            eprintln!("CHECK FAIL rush01_bonus emitted a case of size {}", n);
            fails += 1;
            continue;
        }
        sizes_seen[n] = true;
        for s in &case.sols {
            if !satisfies(s, n, &case.clues) {
                eprintln!(
                    "CHECK FAIL rush01_bonus n={} a listed solution does not solve its own vector",
                    n
                );
                fails += 1;
                break;
            }
        }
        if case.complete && n <= EXHAUSTIVE_MAX_N {
            let (again, complete) = solve_all(n, &case.clues, &all_perms(n), 4096);
            if !complete || again.len() != case.sols.len() {
                eprintln!(
                    "CHECK FAIL rush01_bonus n={} a line claims {} solution(s), a fresh solve \
                     found {}",
                    n,
                    case.sols.len(),
                    again.len()
                );
                fails += 1;
            }
        }
    }
    // 4 is rush01.rs's; every other size in range must be represented.
    for n in 1..=MAX_N {
        if n != 4 && !sizes_seen[n] {
            eprintln!("CHECK FAIL rush01_bonus no case of size {} was emitted", n);
            fails += 1;
        }
    }

    fails
}
