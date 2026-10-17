//! Libft references, Part 3: the t_list functions (subject v19.3, pp.14-16;
//! t_list = {void *content; struct s_list *next;}, content first -- the
//! reverse of C 12's {next, data}).
//!
//! The encoding is c12.rs's: a list travels as its contents, comma-joined
//! decimal ints, and "" is the empty list, which is a NULL list (ft_lstclear
//! ends by setting the pointer to the list to NULL). The reader harness builds
//! real nodes from that sequence, runs the student's function and writes the
//! result back the same way. Values travel as `(void *)(intptr_t)v` where the
//! content is never dereferenced, and as a malloc'd `int *` where the FIXED
//! callback reads it. Nothing here is hex: no field holds a string.
//!
//! Arms (input fields, then reference output):
//!   ft_lstnew       c12_create_elem (c12.rs), reused as is:
//!                   <v>\t<v>\t1          (content stored; 1 == next is NULL)
//!   ft_lstadd_front libft_lstadd_front  <csv>\t<result-csv>
//!                   (one node per value, each added at the front in input
//!                    order, the first onto the empty list: the input reversed)
//!   ft_lstsize      libft_lstsize       <csv>\t<size>
//!   ft_lstlast      libft_lstlast       <csv>\t<lastValue>
//!                   (never the empty list: what ft_lstlast returns for one
//!                    is a reading, which a strict fixture tests, not this)
//!   ft_lstadd_back  libft_lstadd_back   <csv>\t<result-csv>
//!                   (one node per value, each added at the end in input
//!                    order, the first onto the empty list, each new node's
//!                    next NULL, as ft_lstnew leaves it: the input)
//!   ft_lstclear     libft_lstclear      <csv>\t<delCount>\t<headNull>
//!                   (del called once per node; headNull 1 == the pointer to
//!                    the list is NULL afterwards)
//!   ft_lstiter      libft_lstiter       <csv>\t<result-csv>
//!                   (FIXED f: the int content x becomes x*3-1, in place)
//!   ft_lstmap       libft_lstmap        <csv>\t<result-csv>
//!                   (FIXED f: a new int x*3-1 for each content x; the result
//!                    is the new list's contents, "" for the empty list)
//!   ft_lstdelone    no arm: it takes one node, and the basic fixture holds it.
//!
//! Why C 12's list arms are not reused for the rest, though the formats match:
//! their longest list holds 2000 nodes, short of every round capacity (4096),
//! and c12.rs's corpora are C 12's to keep; c12_list_clear carries no headNull
//! and c12_list_last holds the empty list. The values are drawn as C 12's are
//! (c12::full_val, and c12::ranged_val within +/-1 000 000 for the two
//! callbacks, so that x*3-1 cannot overflow an int), and f is C 12's
//! o_foreach.
//!
//! Every corpus starts with a fixed head -- the empty list (but lstlast's),
//! small shapes, the value boundaries, and lists of 600 and 5000 nodes drawn
//! from a seed of their own -- and a small count keeps the whole head.

use crate::c12::{full_val, o_foreach, ranged_val};
use crate::common::{bench_lines, ints_csv, join_csv, longest_csv, sink, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
/// ft_lstadd_front, once per value in input order from the empty list.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_lstadd_front(v: &[i32]) -> Vec<i32> {
    v.iter().rev().copied().collect()
}

/// ft_lstsize.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_lstsize(v: &[i32]) -> usize {
    v.len()
}

/// ft_lstlast; None for the empty list, which no corpus here holds.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_lstlast(v: &[i32]) -> Option<i32> {
    v.last().copied()
}

/// ft_lstadd_back, once per value in input order from the empty list, each
/// new node's next NULL (as ft_lstnew leaves it).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_lstadd_back(v: &[i32]) -> Vec<i32> {
    v.to_vec()
}

/// ft_lstclear: how many times del is called, and whether the pointer to the
/// list is NULL afterwards.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_lstclear(v: &[i32]) -> (usize, bool) {
    (v.len(), true)
}

// ------------------------------------------------------------- the corpora
/// The two callbacks' value range: x*3-1 stays inside an int.
const MAP_LO: i32 = -1_000_000;
const MAP_HI: i32 = 1_000_000;

/// The long lists every corpus carries; the second is past every round
/// capacity (16, 64, 256, 1024, 4096).
const LONG: [usize; 2] = [600, 5000];
const PAST: usize = 4096;
/// The long lists' own seed, so they are the same whatever the corpus's.
const LONG_SEED: u64 = 0x11f7_0003;

/// What a corpus's values are.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Vals {
    /// any int: the content is never dereferenced.
    Full,
    /// MAP_LO..=MAP_HI: the FIXED f computes x*3-1 on it.
    Mapped,
}

fn val(kind: Vals, rng: &mut Rng) -> i32 {
    match kind {
        Vals::Full => full_val(rng),
        Vals::Mapped => ranged_val(rng, MAP_LO, MAP_HI),
    }
}

/// The boundary list each kind's head carries.
fn edges(kind: Vals) -> Vec<i32> {
    match kind {
        Vals::Full => vec![i32::MIN, -1, 0, i32::MAX],
        Vals::Mapped => vec![MAP_LO, -1, 0, MAP_HI],
    }
}

/// The fixed head (the empty list when `empty`, small shapes, the edges, the
/// LONG lists), then seeded lists of `min`..=12 values until `count`.
fn lists(rng: &mut Rng, count: usize, kind: Vals, empty: bool) -> Vec<Vec<i32>> {
    let shapes: [&[i32]; 8] = [
        &[0],
        &[7],
        &[1, 2],
        &[2, 1],
        &[1, 2, 3, 4, 5],
        &[5, 4, 3, 2, 1],
        &[7, 7, 7, 7],
        &[3, 1, 2],
    ];
    let mut out: Vec<Vec<i32>> = Vec::new();
    if empty {
        out.push(Vec::new());
    }
    out.extend(shapes.iter().map(|s| s.to_vec()));
    out.push(edges(kind));
    let mut long = Rng::new(LONG_SEED);
    for n in LONG {
        out.push((0..n).map(|_| val(kind, &mut long)).collect());
    }
    let min = if empty { 0 } else { 1 };
    while out.len() < count {
        let size = min + rng.below(13 - min);
        out.push((0..size).map(|_| val(kind, rng)).collect());
    }
    out
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Arm {
    AddFront,
    Size,
    Last,
    AddBack,
    Clear,
    Iter,
    Map,
}

const ARMS: [(&str, Arm); 7] = [
    ("libft_lstadd_front", Arm::AddFront),
    ("libft_lstsize", Arm::Size),
    ("libft_lstlast", Arm::Last),
    ("libft_lstadd_back", Arm::AddBack),
    ("libft_lstclear", Arm::Clear),
    ("libft_lstiter", Arm::Iter),
    ("libft_lstmap", Arm::Map),
];

fn arm(name: &str) -> Option<Arm> {
    ARMS.iter().find(|(n, _)| *n == name).map(|&(_, a)| a)
}

impl Arm {
    fn vals(self) -> Vals {
        match self {
            Arm::Iter | Arm::Map => Vals::Mapped,
            _ => Vals::Full,
        }
    }
    /// Whether the corpus holds the empty list: every arm but lstlast's.
    fn empty(self) -> bool {
        self != Arm::Last
    }
    /// How many reference fields follow the input.
    fn fields(self) -> usize {
        if self == Arm::Clear {
            2
        } else {
            1
        }
    }
}

/// The reference fields of one line, after the input's.
fn reference(a: Arm, v: &[i32]) -> String {
    match a {
        Arm::AddFront => join_csv(&o_lstadd_front(v)),
        Arm::Size => o_lstsize(v).to_string(),
        Arm::Last => match o_lstlast(v) {
            Some(x) => x.to_string(),
            None => "NULL".to_string(),
        },
        Arm::AddBack => join_csv(&o_lstadd_back(v)),
        Arm::Clear => {
            let (n, null) = o_lstclear(v);
            format!("{}\t{}", n, null as u8)
        }
        Arm::Iter | Arm::Map => join_csv(&o_foreach(v)),
    }
}

fn write_corpus<W: Write>(w: &mut W, a: Arm, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    for v in lists(&mut rng, count, a.vals(), a.empty()) {
        let _ = writeln!(w, "{}\t{}", join_csv(&v), reference(a, &v));
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match arm(name) {
        Some(a) => {
            write_corpus(&mut io::BufWriter::new(io::stdout()), a, seed, count);
            true
        }
        None => false,
    }
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    let Some(a) = arm(name) else {
        return false;
    };
    for l in bench_lines() {
        let v = ints_csv(l.split('\t').next().unwrap_or(""));
        match a {
            Arm::AddFront => sink(o_lstadd_front(&v)),
            Arm::Size => sink(o_lstsize(&v)),
            Arm::Last => sink(o_lstlast(&v)),
            Arm::AddBack => sink(o_lstadd_back(&v)),
            Arm::Clear => sink(o_lstclear(&v)),
            Arm::Iter | Arm::Map => sink(o_foreach(&v)),
        }
    }
    true
}

// ------------------------------------------------------------- self-check
fn capture(a: Arm, seed: u64, count: usize) -> Vec<u8> {
    let mut v = Vec::new();
    write_corpus(&mut v, a, seed, count);
    v
}

/// Self-check: hand-verified tables, properties over a seeded sweep, and what
/// each corpus promises. Returns the failure count.
pub fn check() -> usize {
    let mut bad: Vec<String> = Vec::new();
    let (min, max) = (i32::MIN, i32::MAX);

    // ---- 1. hand tables, at every boundary ----
    let rev: &[(&[i32], &[i32])] = &[
        (&[], &[]),
        (&[7], &[7]),
        (&[1, 2], &[2, 1]),
        (&[1, 2, 3, 4, 5], &[5, 4, 3, 2, 1]),
        (&[7, 7, 7, 7], &[7, 7, 7, 7]),
        (&[min, 0, max], &[max, 0, min]),
    ];
    for (v, want) in rev {
        if o_lstadd_front(v) != *want {
            bad.push(format!("lstadd_front({:?})", v));
        }
        if o_lstadd_back(v) != *v {
            bad.push(format!("lstadd_back({:?})", v));
        }
    }
    let size: &[(&[i32], usize)] = &[(&[], 0), (&[7], 1), (&[1, 2], 2), (&[3, 1, 2], 3), (&[min, max], 2)];
    for (v, want) in size {
        if o_lstsize(v) != *want || o_lstclear(v) != (*want, true) {
            bad.push(format!("lstsize/lstclear({:?})", v));
        }
    }
    let last: &[(&[i32], Option<i32>)] = &[
        (&[], None),
        (&[7], Some(7)),
        (&[1, 2], Some(2)),
        (&[3, 1, 2], Some(2)),
        (&[min], Some(min)),
        (&[max, 0], Some(0)),
    ];
    for (v, want) in last {
        if o_lstlast(v) != *want {
            bad.push(format!("lstlast({:?})", v));
        }
    }
    let f: &[(i32, i32)] = &[(0, -1), (1, 2), (-1, -4), (2, 5), (MAP_HI, 2_999_999), (MAP_LO, -3_000_001)];
    for (x, want) in f {
        if o_foreach(&[*x]) != vec![*want] {
            bad.push(format!("f({})", x));
        }
    }
    if !o_foreach(&[]).is_empty() {
        bad.push("f over the empty list".into());
    }
    // The bytes of a line's reference fields.
    let lines: &[(Arm, &[i32], &str)] = &[
        (Arm::AddFront, &[1, -2, 3], "3,-2,1"),
        (Arm::AddFront, &[], ""),
        (Arm::Size, &[], "0"),
        (Arm::Size, &[5, 5], "2"),
        (Arm::Last, &[1, 2, 3], "3"),
        (Arm::AddBack, &[min, max], "-2147483648,2147483647"),
        (Arm::Clear, &[], "0\t1"),
        (Arm::Clear, &[1, 2, 3], "3\t1"),
        (Arm::Iter, &[0, 1], "-1,2"),
        (Arm::Map, &[], ""),
        (Arm::Map, &[1, 2, 3], "2,5,8"),
    ];
    for (a, v, want) in lines {
        if reference(*a, v) != *want {
            bad.push(format!("{:?} line for {:?}: {:?}", a, v, reference(*a, v)));
        }
    }

    // ---- 2. properties over a seeded sweep (20 000) ----
    let mut rng = Rng::new(0x11f7_4242);
    for i in 0..20_000 {
        let n = if i % 2000 == 0 { PAST + 1 } else { rng.below(13) };
        let v: Vec<i32> = (0..n).map(|_| full_val(&mut rng)).collect();
        // Built a second way: node by node, as the harness calls the function.
        let mut front: Vec<i32> = Vec::new();
        let mut back: Vec<i32> = Vec::new();
        for &x in &v {
            front.insert(0, x);
            back.push(x);
        }
        if o_lstadd_front(&v) != front || o_lstadd_front(&o_lstadd_front(&v)) != v {
            bad.push(format!("lstadd_front property, n={}", n));
        }
        if o_lstadd_back(&v) != back {
            bad.push(format!("lstadd_back property, n={}", n));
        }
        if o_lstsize(&v) != v.iter().fold(0, |c, _| c + 1) || o_lstclear(&v) != (n, true) {
            bad.push(format!("lstsize/lstclear property, n={}", n));
        }
        if o_lstlast(&v) != (if n == 0 { None } else { Some(v[n - 1]) }) {
            bad.push(format!("lstlast property, n={}", n));
        }
        let m: Vec<i32> = (0..n).map(|_| ranged_val(&mut rng, MAP_LO, MAP_HI)).collect();
        let r = o_foreach(&m);
        if r.len() != m.len() || r.iter().zip(&m).any(|(&y, &x)| y as i64 != x as i64 * 3 - 1) {
            bad.push(format!("f property, n={}", n));
        }
    }

    // ---- 3. what each corpus promises ----
    // What each corpus must hold is written here again, not read from Arm's
    // own methods, so a change there cannot carry its check along with it.
    for &(name, a) in ARMS.iter() {
        let callback = matches!(name, "libft_lstiter" | "libft_lstmap");
        let empty = name != "libft_lstlast";
        let (lo, hi) = if callback { (MAP_LO, MAP_HI) } else { (i32::MIN, i32::MAX) };
        if arm(name) != Some(a) {
            bad.push(format!("{} is not dispatched to itself", name));
        }
        let one = capture(a, 1, 200);
        if one != capture(a, 1, 200) {
            bad.push(format!("{}: seed 1 gave two corpora", name));
        }
        let head = capture(a, 1, 0);
        let head_len = (empty as usize) + 8 + 1 + LONG.len();
        if head.iter().filter(|&&b| b == b'\n').count() != head_len {
            bad.push(format!("{}: a count of 0 does not keep the whole head", name));
        }
        // Past every round capacity, at any count.
        if longest_csv(&head, 0) <= PAST || longest_csv(&one, 0) <= PAST {
            bad.push(format!("{}: no list of more than {} nodes", name, PAST));
        }
        let text = String::from_utf8_lossy(&one).into_owned();
        let other = String::from_utf8_lossy(&capture(a, 9, 200)).into_owned();
        let long_of = |t: &str| -> Vec<String> {
            t.lines().filter(|l| l.split('\t').next().unwrap_or("").matches(',').count() >= 12).map(String::from).collect()
        };
        if long_of(&text) != long_of(&other) || long_of(&text).len() != LONG.len() {
            bad.push(format!("{}: the long lists depend on the seed", name));
        }
        if text.lines().count() != 200 {
            bad.push(format!("{}: {} lines for a count of 200", name, text.lines().count()));
        }
        let mut saw_empty = false;
        let mut saw = (false, false);
        for l in text.lines() {
            let f: Vec<&str> = l.split('\t').collect();
            if f.len() != 1 + a.fields() {
                bad.push(format!("{}: a line of {} fields", name, f.len()));
                break;
            }
            let v = ints_csv(f[0]);
            if join_csv(&v) != f[0] {
                bad.push(format!("{}: an input that is not a list of ints: {:.40}", name, f[0]));
                break;
            }
            if f[1..].join("\t") != reference(a, &v) {
                bad.push(format!("{}: a line whose answer is not its input's: {:.40}", name, l));
                break;
            }
            if callback && v.iter().any(|&x| !(MAP_LO..=MAP_HI).contains(&x)) {
                bad.push(format!("{}: a value x*3-1 overflows", name));
                break;
            }
            saw_empty |= v.is_empty();
            saw.0 |= v.contains(&lo);
            saw.1 |= v.contains(&hi);
        }
        // The empty list is agreed everywhere but lstlast, whose plain corpus
        // holds only the cases every reading agrees on.
        if saw_empty != empty {
            bad.push(format!("{}: the empty list is {}", name, if saw_empty { "there" } else { "missing" }));
        }
        if a == Arm::Last && text.contains("NULL") {
            bad.push(format!("{}: a NULL answer", name));
        }
        if saw != (true, true) {
            bad.push(format!("{}: the value boundaries are missing", name));
        }
    }
    for name in ["libft_lstnew", "libft_lstdelone", "c12_list_size", "libft_lstlast_readings"] {
        if arm(name).is_some() {
            bad.push(format!("{} was claimed", name));
        }
    }

    for b in &bad {
        eprintln!("CHECK FAIL libft_list {}", b);
    }
    bad.len()
}
