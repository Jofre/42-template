//! Rush01 VALIDATOR (c-piscine-rush-01 ex00) — which rule a printed grid breaks.
//!
//! Usage:  oracle rush01_validate   — answer one request per line of stdin
//!
//! WHY THIS LIVES HERE AND NOT IN THE RUNNER
//! -----------------------------------------
//! tools/rush01_check.sh judges a student's rush01 by VALIDATING the grid it
//! printed rather than comparing it with one expected grid (rush01.rs explains
//! why no single grid can be expected). When a grid is wrong the runner says
//! which rule it broke, in the subject's words: "row 2 holds the height 3
//! twice", "column 3 is seen as 2 from the top, but clue 3 asks for 3".
//!
//! Working that out — repeated heights in a row or a column, and the view from
//! each of the four sides counted and matched against its clue — is the
//! validity-check half of a rush01 solver. It used to be written out in awk
//! inside the runner, in a shape that ported to C almost line for line, in a
//! file every clone of this repo ships. So it lives here, with the other
//! references, in Rust: AGENTS.md §2 makes the oracle a door a student may read
//! and cannot paste. The runner keeps only the SHAPE of an answer (is this line
//! a row, how many lines, is it Error), which says nothing about the puzzle,
//! and asks this arm for everything else.
//!
//! PROTOCOL
//! --------
//! One request per line, three TAB-separated fields:
//!
//!     <W> <H><TAB><clues><TAB><cells>
//!
//!   W, H   the board's width and height, 1..=9 each (the runner's ceiling,
//!          which is the subject's bonus ceiling).
//!   clues  2W + 2H values separated by single spaces, in the subject's order:
//!          W columns seen from the TOP, W seen from the BOTTOM, then H rows
//!          seen from the LEFT and H seen from the RIGHT. With W == H this is
//!          the familiar 4N layout.
//!   cells  W * H values separated by single spaces, row-major. A NUMBER, not
//!          necessarily a digit — see WHY A CELL IS A NUMBER below.
//!
//! One reply per request, in order, four TAB-separated fields:
//!
//!     <faults><TAB><category><TAB><message><TAB><why>
//!
//!   faults    how many rules the grid breaks; 0 means it answers the clues.
//!   category  of the FIRST broken rule: latin-row, latin-col or clue. `ok`
//!             when faults is 0, and then message and why are empty.
//!   message   the runner's sentence naming that rule, verbatim.
//!   why       the rule itself, restated, verbatim.
//!
//! Exit 0 once every line is answered. A malformed request is a harness bug,
//! not a student's: the arm answers the lines before it, names the line on
//! stderr and exits 2, so the runner sees a short reply and says so.
//!
//! THE RULES, AND THE ORDER THEY ARE REPORTED IN
//! --------------------------------------------
//! Heights run 1..=K with K = max(W, H). Every row holds W heights and every
//! column H heights, none repeated; with W == H == K that is the Latin square
//! rule unchanged (rectangles are a harness-defined extension; see the
//! RECTANGULAR BOARDS section of rush01_bonus.rs). Then every clue must equal
//! the number of boxes seen from its end of its line, a box being seen when it
//! is taller than everything in front of it.
//!
//! Every repeated height in every line counts as one broken rule, and so does
//! every clue that does not match. The one REPORTED is the first in the order
//! the subject introduces them: the rows top to bottom, then the columns left
//! to right (each by ascending height), then the clues in the order of the
//! input string — so what a student is shown is the earliest fault in terms
//! they already know, not whichever one a checker happened to trip over.
//!
//! WHY A CELL IS A NUMBER
//! ----------------------
//! In one of its paths — a grid printed for an input that has no solution — the
//! runner builds the grid before every row has been shown to be well-formed,
//! and its verdict there has always been computed on awk's numeric reading of
//! each token: a missing token is 0, "12" is twelve, "0x1A" is 26 under mawk.
//! The runner does that reading and sends the resulting double (as `%.17g`, so
//! it round-trips exactly); this arm then treats the value the way the awk it
//! replaced did, which is what keeps the runner's verdicts byte-identical:
//!
//!   * a cell COUNTS as height h when awk's array subscript for it reads "h":
//!     an integral value equal to h, or a non-integral one that CONVFMT
//!     (`%.6g`) renders as "h" — 0.9999996 counts as a 1;
//!   * a view compares the values themselves, numerically, starting from 0 —
//!     so a 0 is never seen, and a missing height is not a fault by itself (it
//!     only ever shows up as a repeat somewhere else, or as a wrong view).
//!
//! For every grid a correct or nearly-correct program prints — digits 1..=K —
//! none of this is visible.

use std::io::{self, BufRead, Write};
use std::process::exit;

use crate::common::Rng;

/// The runner's ceiling on either side of the board (the subject's "up to 9x9").
const MAX_SIDE: usize = 9;

/// The sentence every clue fault carries as its `why`.
const VIEW_RULE: &str = "A taller box hides every shorter box behind it, so what you see \
from one side is the count of boxes taller than everything in front of them.";

// ------------------------------------------------------------------ board

/// The four ends a line can be looked along from.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Side {
    Top,
    Bottom,
    Left,
    Right,
}

impl Side {
    fn name(self) -> &'static str {
        match self {
            Side::Top => "the top",
            Side::Bottom => "the bottom",
            Side::Left => "the left",
            Side::Right => "the right",
        }
    }
    fn line(self) -> &'static str {
        match self {
            Side::Top | Side::Bottom => "column",
            Side::Left | Side::Right => "row",
        }
    }
}

/// One broken rule, before it is put into words. Only the first one found is
/// ever formatted, so a grid breaking twenty rules costs twenty of these and
/// one `format!`.
enum Broken {
    /// (row, height, how many times), 1-based.
    Row(usize, usize, usize),
    /// (column, height, how many times), 1-based.
    Col(usize, usize, usize),
    /// (clue slot, side, line index, boxes seen, clue value), 1-based.
    View(usize, Side, usize, usize, usize),
}

/// The first broken rule, in the runner's words.
#[derive(Debug, PartialEq)]
pub struct Fault {
    pub cat: &'static str,
    pub msg: String,
    pub why: String,
}

/// The whole answer for one grid.
#[derive(Debug, PartialEq)]
pub struct Verdict {
    pub faults: usize,
    pub first: Option<Fault>,
}

impl Verdict {
    /// The reply line, without its newline.
    fn reply(&self) -> String {
        match &self.first {
            Some(f) => format!("{}\t{}\t{}\t{}", self.faults, f.cat, f.msg, f.why),
            None => format!("{}\tok\t\t", self.faults),
        }
    }
}

/// awk's reading of "this cell is height `h`". See WHY A CELL IS A NUMBER: an
/// integral value counts only as itself, a non-integral one as whatever its
/// six-significant-digit rendering says.
fn counts_as(x: f64, h: usize) -> bool {
    let h = h as f64;
    if x == x.trunc() {
        x == h
    } else {
        format!("{:.5e}", x).parse::<f64>().map_or(false, |r| r == h)
    }
}

/// How many boxes are seen walking along `line` from its first element.
fn seen<'a>(line: impl Iterator<Item = &'a f64>) -> usize {
    line.fold((0.0f64, 0usize), |(tallest, n), &x| {
        if x > tallest {
            (x, n + 1)
        } else {
            (tallest, n)
        }
    })
    .1
}

/// Every (line, height, times) where a height repeats, lines in order and
/// heights ascending within a line.
fn repeats(lines: &[Vec<f64>], k: usize) -> Vec<(usize, usize, usize)> {
    lines
        .iter()
        .enumerate()
        .flat_map(|(i, line)| {
            (1..=k).filter_map(move |h| {
                let n = line.iter().filter(|&&x| counts_as(x, h)).count();
                if n > 1 {
                    Some((i + 1, h, n))
                } else {
                    None
                }
            })
        })
        .collect()
}

fn times(n: usize) -> String {
    if n == 2 {
        "twice".to_string()
    } else {
        format!("{} times", n)
    }
}

/// Judge a `w` x `h` board (row-major `cells`) against `clues`. Lengths are the
/// caller's contract (`parse_request` enforces them for the protocol).
pub fn judge(w: usize, h: usize, clues: &[usize], cells: &[f64]) -> Verdict {
    let k = w.max(h);
    let rows: Vec<Vec<f64>> = cells.chunks(w).map(<[f64]>::to_vec).collect();
    let cols: Vec<Vec<f64>> = (0..w)
        .map(|c| cells.iter().skip(c).step_by(w).copied().collect())
        .collect();

    // The sightlines, in exactly the order the clue string lists them.
    let sights = |side: Side, lines: &[Vec<f64>]| -> Vec<(Side, usize, usize)> {
        lines
            .iter()
            .enumerate()
            .map(|(i, l)| {
                let n = match side {
                    Side::Top | Side::Left => seen(l.iter()),
                    Side::Bottom | Side::Right => seen(l.iter().rev()),
                };
                (side, i + 1, n)
            })
            .collect()
    };
    let views = sights(Side::Top, &cols)
        .into_iter()
        .chain(sights(Side::Bottom, &cols))
        .chain(sights(Side::Left, &rows))
        .chain(sights(Side::Right, &rows));

    let broken: Vec<Broken> = repeats(&rows, k)
        .into_iter()
        .map(|(r, ht, n)| Broken::Row(r, ht, n))
        .chain(repeats(&cols, k).into_iter().map(|(c, ht, n)| Broken::Col(c, ht, n)))
        .chain(
            views
                .zip(clues.iter())
                .enumerate()
                .filter(|(_, (view, want))| view.2 != **want)
                .map(|(slot, (view, want))| Broken::View(slot + 1, view.0, view.1, view.2, *want)),
        )
        .collect();

    let first = broken.first().map(|b| match *b {
        Broken::Row(r, ht, n) => Fault {
            cat: "latin-row",
            msg: format!("row {} holds the height {} {}.", r, ht, times(n)),
            why: if w == h {
                format!("Every row must hold each of the heights 1..{} exactly once.", k)
            } else {
                format!("Every row holds {} different heights from 1..{}, so none may repeat.", w, k)
            },
        },
        Broken::Col(c, ht, n) => Fault {
            cat: "latin-col",
            msg: format!("column {} holds the height {} {}.", c, ht, times(n)),
            why: if w == h {
                format!("Every column must hold each of the heights 1..{} exactly once.", k)
            } else {
                format!("Every column holds {} different heights from 1..{}, so none may repeat.", h, k)
            },
        },
        Broken::View(slot, side, idx, got, want) => Fault {
            cat: "clue",
            msg: format!(
                "{} {} is seen as {} from {}, but clue {} asks for {}.",
                side.line(),
                idx,
                got,
                side.name(),
                slot,
                want
            ),
            why: VIEW_RULE.to_string(),
        },
    });
    Verdict {
        faults: broken.len(),
        first,
    }
}

// --------------------------------------------------------------- protocol

/// One parsed request.
struct Request {
    w: usize,
    h: usize,
    clues: Vec<usize>,
    cells: Vec<f64>,
}

fn parse_request(line: &str) -> Result<Request, String> {
    let f: Vec<&str> = line.split('\t').collect();
    if f.len() != 3 {
        return Err(format!(
            "{} TAB-separated field(s), want 3: \"<W> <H>\", the clues, the cells",
            f.len()
        ));
    }
    let dims: Vec<usize> = f[0]
        .split(' ')
        .map(|t| t.parse::<usize>())
        .collect::<Result<_, _>>()
        .map_err(|_| format!("board size \"{}\" is not two numbers", f[0]))?;
    let (w, h) = match dims[..] {
        [w, h] if (1..=MAX_SIDE).contains(&w) && (1..=MAX_SIDE).contains(&h) => (w, h),
        _ => return Err(format!("board size \"{}\" is not \"<W> <H>\" within 1..={}", f[0], MAX_SIDE)),
    };
    let clues: Vec<usize> = f[1]
        .split(' ')
        .map(|t| {
            if !t.is_empty() && t.bytes().all(|b| b.is_ascii_digit()) {
                t.parse::<usize>().map_err(|_| ())
            } else {
                Err(())
            }
        })
        .collect::<Result<_, _>>()
        .map_err(|_| format!("clue list \"{}\" is not whole numbers separated by single spaces", f[1]))?;
    if clues.len() != 2 * w + 2 * h {
        return Err(format!("{} clue(s) for a {}x{} board, want {}", clues.len(), w, h, 2 * w + 2 * h));
    }
    let cells: Vec<f64> = f[2]
        .split(' ')
        .map(|t| t.parse::<f64>())
        .collect::<Result<_, _>>()
        .map_err(|_| format!("cell list \"{}\" is not numbers separated by single spaces", f[2]))?;
    if cells.len() != w * h {
        return Err(format!("{} cell(s) for a {}x{} board, want {}", cells.len(), w, h, w * h));
    }
    Ok(Request { w, h, clues, cells })
}

/// `oracle rush01_validate`: answer every request on stdin, then exit.
pub fn run() -> ! {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    for (n, line) in stdin.lock().lines().enumerate() {
        let parsed = line
            .map_err(|e| format!("unreadable: {}", e))
            .and_then(|l| parse_request(&l));
        match parsed {
            Ok(q) => {
                let _ = writeln!(out, "{}", judge(q.w, q.h, &q.clues, &q.cells).reply());
            }
            Err(why) => {
                let _ = out.flush();
                eprintln!("oracle rush01_validate: request {}: {}", n + 1, why);
                exit(2);
            }
        }
    }
    if out.flush().is_err() {
        exit(2);
    }
    exit(0);
}

// ------------------------------------------------------------- self-check
//
// Three kinds of evidence, none of which trusts `judge` to grade itself:
//
//   1. a hand-written table of requests and the exact replies — every string
//      checked once against the awk this arm replaced, run side by side;
//   2. properties over seeded MADE-UP boards of every shape 1..=9 x 1..=9: a
//      valid board against its own clues (computed here by a re-scanning
//      counter that shares nothing with `seen`) must pass, and each mutation —
//      a repeated height in a row, a swap that repeats one in a column, a
//      triple, a wrong clue on each of the four sides — must be rejected with
//      the category and sentence the mutation predicts;
//   3. all 4x4: every one of the 576 Latin squares against every one of the
//      438 solvable clue vectors, where "no fault" must coincide EXACTLY with
//      rush01.rs's enumerated table — validity and membership are the same
//      question there, and the runner relies on that.
//
// The boards in 2 are built by construction — a cyclic Latin square with its
// rows, columns and symbols shuffled, cut down to W x H — which produces a
// valid board and its clues without ever solving anything.

/// A shuffled 1..=n (or 0..n when `from_zero`).
fn shuffle(n: usize, from_zero: bool, rng: &mut Rng) -> Vec<usize> {
    let mut v: Vec<usize> = (0..n).map(|i| if from_zero { i } else { i + 1 }).collect();
    for i in (1..n).rev() {
        v.swap(i, rng.below(i + 1));
    }
    v
}

/// A valid `w` x `h` board: rows, columns and symbols of the cyclic square of
/// order max(w, h) shuffled, then its top-left corner kept. Every row of a
/// Latin square is a permutation and so is every column, so any corner of one
/// has no repeat in any line.
fn made_up_board(w: usize, h: usize, rng: &mut Rng) -> Vec<f64> {
    let k = w.max(h);
    let rp = shuffle(k, true, rng);
    let cp = shuffle(k, true, rng);
    let sym = shuffle(k, false, rng);
    (0..h)
        .flat_map(|r| {
            let (rp, cp, sym) = (&rp, &cp, &sym);
            (0..w).map(move |c| sym[(rp[r] + cp[c]) % k] as f64)
        })
        .collect()
}

/// Boxes seen along `line`, counted the slow way: position i is seen when
/// every position before it is lower. Shares nothing with `seen`.
fn seen_rescan(line: &[f64]) -> usize {
    (0..line.len())
        .filter(|&i| line[..i].iter().all(|&p| p < line[i]))
        .count()
}

/// Where clue slot `slot` (1-based) looks from, decoded the arithmetic way —
/// a different formulation from `judge`'s chain of four sides.
fn slot_where(w: usize, h: usize, slot: usize) -> (Side, usize) {
    let s = slot - 1;
    if s < 2 * w {
        (if s < w { Side::Top } else { Side::Bottom }, s % w + 1)
    } else {
        let t = s - 2 * w;
        (if t < h { Side::Left } else { Side::Right }, t % h + 1)
    }
}

/// The line clue slot `slot` looks along, first element nearest the viewer.
fn slot_line(w: usize, h: usize, cells: &[f64], slot: usize) -> Vec<f64> {
    let (side, idx) = slot_where(w, h, slot);
    let i = idx - 1;
    let mut line: Vec<f64> = match side {
        Side::Top | Side::Bottom => (0..h).map(|r| cells[r * w + i]).collect(),
        Side::Left | Side::Right => (0..w).map(|c| cells[i * w + c]).collect(),
    };
    if side == Side::Bottom || side == Side::Right {
        line.reverse();
    }
    line
}

fn clues_rescan(w: usize, h: usize, cells: &[f64]) -> Vec<usize> {
    (1..=2 * w + 2 * h)
        .map(|slot| seen_rescan(&slot_line(w, h, cells, slot)))
        .collect()
}

fn nums(s: &str) -> Vec<usize> {
    s.split(' ').map(|t| t.parse().unwrap()).collect()
}

fn cells_of(s: &str) -> Vec<f64> {
    s.split(' ').map(|t| t.parse().unwrap()).collect()
}

/// Kind 1: literal requests and the literal reply for each.
fn check_table() -> usize {
    const SUBJECT_CLUES: &str = "4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2";
    const SUBJECT_GRID: &str = "1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3";
    let row4 = "Every row must hold each of the heights 1..4 exactly once.";
    let col4 = "Every column must hold each of the heights 1..4 exactly once.";
    let cases: Vec<(&str, String)> = vec![
        // The subject's worked example answers its own clues.
        (
            "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
            "0\tok\t\t".to_string(),
        ),
        // One clue wrong on the BOTTOM side: column 1 read upwards is 4 3 2 1.
        (
            "4 4\t4 3 2 1 2 2 2 2 4 3 2 1 1 2 2 2\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
            format!("1\tclue\tcolumn 1 is seen as 1 from the bottom, but clue 5 asks for 2.\t{}", VIEW_RULE),
        ),
        // ...and on the RIGHT side: row 4 read leftwards is 3 2 1 4.
        (
            "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 1\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
            format!("1\tclue\trow 4 is seen as 2 from the right, but clue 16 asks for 1.\t{}", VIEW_RULE),
        ),
        // A repeated 2 in row 1 also repeats it in column 1 and blinds two
        // views: four rules, the row reported first.
        (
            "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t2 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
            format!("4\tlatin-row\trow 1 holds the height 2 twice.\t{}", row4),
        ),
        // Swapping two cells of row 1 keeps the rows clean and breaks two
        // columns: the column is reported first.
        (
            "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t2 1 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
            format!("4\tlatin-col\tcolumn 1 holds the height 2 twice.\t{}", col4),
        ),
        // Nine ones: every row and every column repeats, every view is 1.
        (
            "3 3\t1 1 1 1 1 1 1 1 1 1 1 1\t1 1 1 1 1 1 1 1 1",
            "6\tlatin-row\trow 1 holds the height 1 3 times.\tEvery row must hold each of the heights 1..3 exactly once."
                .to_string(),
        ),
        // Rectangles phrase the rule as distinctness, W for a row, H for a column.
        (
            "3 2\t1 2 1 1 1 2 3 2 1 2\t1 2 3 1 3 2",
            "1\tlatin-col\tcolumn 1 holds the height 1 twice.\tEvery column holds 2 different heights from 1..3, so none may repeat."
                .to_string(),
        ),
        (
            "2 3\t3 2 1 2 1 2 1 1 1 2\t1 1 2 3 3 2",
            "1\tlatin-row\trow 1 holds the height 1 twice.\tEvery row holds 2 different heights from 1..3, so none may repeat."
                .to_string(),
        ),
        // awk's reading of a number (WHY A CELL IS A NUMBER): 0.9999996 is a 1
        // to the repeat test and just under 1 to the views, so this passes...
        (
            "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t0.9999996 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
            "0\tok\t\t".to_string(),
        ),
        // ...a 0 is never seen and repeats nothing...
        (
            "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t0 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
            format!("2\tclue\tcolumn 1 is seen as 3 from the top, but clue 1 asks for 4.\t{}", VIEW_RULE),
        ),
        // ...and a height above K is no repeat either, only a wrong view.
        (
            "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 5",
            format!("4\tclue\tcolumn 4 is seen as 2 from the top, but clue 4 asks for 1.\t{}", VIEW_RULE),
        ),
    ];
    let mut fails = 0;
    for (req, want) in &cases {
        let got = match parse_request(req) {
            Ok(q) => judge(q.w, q.h, &q.clues, &q.cells).reply(),
            Err(e) => format!("(refused: {})", e),
        };
        if got != *want {
            eprintln!("CHECK FAIL rush01_validate table: {:?}\n    got  {:?}\n    want {:?}", req, got, want);
            fails += 1;
        }
    }
    // The table's first case must BE the subject's example, not a copy of it
    // that drifted: pinned against rush01.rs's own transcription.
    if cells_of(SUBJECT_GRID).iter().map(|&x| x as u8).collect::<Vec<_>>()
        != crate::rush01::subject_solution_digits()
        || nums(SUBJECT_CLUES) != crate::rush01::subject_clue_values()
    {
        eprintln!("CHECK FAIL rush01_validate: the table's subject example differs from rush01.rs's");
        fails += 1;
    }
    fails
}

/// Kind 2: properties over made-up boards of every shape.
fn check_properties() -> usize {
    let mut rng = Rng::new(0x5EE5_0001);
    let mut fails = 0;
    let fail = |what: &str, w: usize, h: usize, cells: &[f64], clues: &[usize], got: &Verdict| {
        eprintln!(
            "CHECK FAIL rush01_validate {}: {}x{} cells {:?} clues {:?} -> {:?}",
            what, w, h, cells, clues, got
        );
    };
    let mut seen_cat = [0usize; 4]; // latin-row, latin-col, clue by side...
    let mut sides_hit = [false; 4];
    for round in 0..2000 {
        let (w, h) = if round < 81 {
            (round % 9 + 1, round / 9 + 1) // every shape at least once
        } else {
            (rng.below(MAX_SIDE) + 1, rng.below(MAX_SIDE) + 1)
        };
        let k = w.max(h);
        let cells = made_up_board(w, h, &mut rng);
        let clues = clues_rescan(w, h, &cells);

        // A valid board answers its own clues, with nothing broken at all.
        let v = judge(w, h, &clues, &cells);
        if v.faults != 0 || v.first.is_some() || v.reply() != "0\tok\t\t" {
            fail("valid board rejected", w, h, &cells, &clues, &v);
            fails += 1;
        }

        // A wrong clue on every slot whose line can see more than one count:
        // exactly one rule broken, named with the side, the line and both counts.
        for slot in 1..=2 * w + 2 * h {
            let (side, idx) = slot_where(w, h, slot);
            let len = if side == Side::Top || side == Side::Bottom { h } else { w };
            if len < 2 {
                continue;
            }
            let truth = clues[slot - 1];
            let lie = truth % len + 1;
            let mut bad = clues.clone();
            bad[slot - 1] = lie;
            let v = judge(w, h, &bad, &cells);
            let want = Fault {
                cat: "clue",
                msg: format!(
                    "{} {} is seen as {} from {}, but clue {} asks for {}.",
                    side.line(),
                    idx,
                    truth,
                    side.name(),
                    slot,
                    lie
                ),
                why: VIEW_RULE.to_string(),
            };
            if v.faults != 1 || v.first.as_ref() != Some(&want) {
                fail("wrong clue", w, h, &cells, &bad, &v);
                fails += 1;
            }
            seen_cat[2] += 1;
            sides_hit[side as usize] = true;
        }

        let row_why = if w == h {
            format!("Every row must hold each of the heights 1..{} exactly once.", k)
        } else {
            format!("Every row holds {} different heights from 1..{}, so none may repeat.", w, k)
        };
        let col_why = if w == h {
            format!("Every column must hold each of the heights 1..{} exactly once.", k)
        } else {
            format!("Every column holds {} different heights from 1..{}, so none may repeat.", h, k)
        };

        // A height copied along its own row: that row is the first fault.
        if w >= 2 {
            let r = rng.below(h);
            let order = shuffle(w, true, &mut rng);
            let (c, c2) = (order[0], order[1]);
            let mut bad = cells.clone();
            bad[r * w + c] = bad[r * w + c2];
            let v = judge(w, h, &clues, &bad);
            let want = Fault {
                cat: "latin-row",
                msg: format!("row {} holds the height {} twice.", r + 1, bad[r * w + c2]),
                why: row_why.clone(),
            };
            if v.faults < 1 || v.first.as_ref() != Some(&want) {
                fail("repeat in a row", w, h, &bad, &clues, &v);
                fails += 1;
            }
            seen_cat[0] += 1;
        }

        // Three of a kind in one row.
        if w >= 3 {
            let r = rng.below(h);
            let order = shuffle(w, true, &mut rng);
            let mut bad = cells.clone();
            let keep = bad[r * w + order[0]];
            bad[r * w + order[1]] = keep;
            bad[r * w + order[2]] = keep;
            let v = judge(w, h, &clues, &bad);
            let want = Fault {
                cat: "latin-row",
                msg: format!("row {} holds the height {} 3 times.", r + 1, keep),
                why: row_why.clone(),
            };
            if v.first.as_ref() != Some(&want) {
                fail("three in a row", w, h, &bad, &clues, &v);
                fails += 1;
            }
        }

        // Two cells of one row swapped: the row stays clean, and when every
        // column holds every height (h == k) the left one of the two columns
        // now holds the moved-in height twice, and is the first fault.
        if w >= 2 && h == k {
            let r = rng.below(h);
            let order = shuffle(w, true, &mut rng);
            let (c1, c2) = (order[0].min(order[1]), order[0].max(order[1]));
            let mut bad = cells.clone();
            bad.swap(r * w + c1, r * w + c2);
            let v = judge(w, h, &clues, &bad);
            let want = Fault {
                cat: "latin-col",
                msg: format!("column {} holds the height {} twice.", c1 + 1, bad[r * w + c1]),
                why: col_why.clone(),
            };
            if v.faults < 2 || v.first.as_ref() != Some(&want) {
                fail("swap within a row", w, h, &bad, &clues, &v);
                fails += 1;
            }
            seen_cat[1] += 1;
        }
    }
    // The sweep must actually have exercised what it claims to.
    if seen_cat.iter().take(3).any(|&n| n == 0) || sides_hit.iter().any(|&b| !b) {
        eprintln!(
            "CHECK FAIL rush01_validate: the property sweep missed a category ({:?}) or a side ({:?})",
            seen_cat, sides_hit
        );
        fails += 1;
    }
    fails
}

/// Kind 3: all 576 4x4 Latin squares against all 438 solvable vectors.
fn check_exhaustive_4x4() -> usize {
    let table = crate::rush01::solution_table();
    let squares: Vec<Vec<f64>> = table
        .iter()
        .flat_map(|(_, sols)| sols.iter().map(|g| g.iter().map(|&d| d as f64).collect()))
        .collect();
    let mut fails = 0;
    if squares.len() != 576 || table.len() != 438 {
        eprintln!(
            "CHECK FAIL rush01_validate: rush01.rs's table has {} squares over {} vectors, want 576 over 438",
            squares.len(),
            table.len()
        );
        fails += 1;
    }
    let mut passes = 0usize;
    for (clues, sols) in &table {
        let clues: Vec<usize> = clues.iter().map(|&c| c as usize).collect();
        for sq in &squares {
            let listed = sols
                .iter()
                .any(|g| g.iter().zip(sq.iter()).all(|(&d, &x)| d as f64 == x));
            let valid = judge(4, 4, &clues, sq).faults == 0;
            if valid {
                passes += 1;
            }
            if valid != listed {
                eprintln!(
                    "CHECK FAIL rush01_validate: square {:?} vs clues {:?}: validator says {}, the table says {}",
                    sq, clues, valid, listed
                );
                fails += 1;
            }
        }
    }
    // Every square answers exactly the one vector it produces.
    if passes != 576 {
        eprintln!("CHECK FAIL rush01_validate: {} (square, vector) pairs passed, want 576", passes);
        fails += 1;
    }
    fails
}

/// The protocol: what is refused, what is read, and what a reply looks like.
fn check_protocol() -> usize {
    let mut fails = 0;
    let refused = [
        "",
        "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2",
        "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t1 2 3 4\textra",
        "0 4\t\t",
        "10 1\t1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1\t1 1 1 1 1 1 1 1 1 1",
        "4\t1 1 1 1\t1",
        "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
        "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 x\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
        "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 -2\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 3",
        "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2",
        "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2 three",
        "4 4\t4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2\t1 2 3 4 2 3 4 1 3 4 1 2 4 1 2  3",
    ];
    for req in refused.iter() {
        if parse_request(req).is_ok() {
            eprintln!("CHECK FAIL rush01_validate: accepted the malformed request {:?}", req);
            fails += 1;
        }
    }
    // What a %.17g from awk can look like; each must be read, not refused.
    for cell in ["nan", "-nan", "inf", "-inf", "-0", "1e+20", "26", "0.99999960000000003"] {
        let req = format!("1 1\t1 1 1 1\t{}", cell);
        if parse_request(&req).is_err() {
            eprintln!("CHECK FAIL rush01_validate: refused the awk-formatted cell {:?}", cell);
            fails += 1;
        }
    }
    fails
}

pub fn check() -> usize {
    check_table() + check_properties() + check_exhaustive_4x4() + check_protocol()
}
