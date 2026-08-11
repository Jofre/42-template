//! c-12 references: singly-linked-list family (t_list = {next, void *data}).
//!
//! The corpus encodes the INPUT list as a comma-joined decimal int sequence
//! (empty string == the empty list). The reader harness builds a real t_list
//! from that sequence (data carried either as `(void*)(intptr_t)v` for the
//! value-only functions, or as a malloc'd `int*` for the callback functions),
//! runs the student's function, then serialises the RESULT list's data back in
//! the same comma-joined-decimal encoding — so a correct impl is byte-identical
//! to the reference. See oracle/README.md for the format contract.
//!
//! Line formats (input fields, then reference output):
//!   create_elem   <v>\t<v>\t1                     (data stored; next==NULL flag)
//!   list_size     <csv>\t<size>
//!   list_last     <csv>\t<lastValue|NULL>
//!   list_at       <csv>\t<idx>\t<valueAtIdx|NULL>
//!   push_front    <csv>\t<result-csv>            (== input reversed)
//!   push_back     <csv>\t<result-csv>            (== input)
//!   list_reverse  <csv>\t<result-csv>
//!   list_sort     <csv>\t<sorted-csv>            (FIXED cmp: ascending int)
//!   list_clear    <csv>\t<freeCount>             (== size; free_fct call count)
//!   foreach       <csv>\t<result-csv>            (FIXED f: x -> x*3-1)
//!   foreach_if    <csv>\t<ref>\t<result-csv>     (FIXED f/cmp: +100 where ==ref)
//!   remove_if     <csv>\t<ref>\t<result-csv>     (FIXED cmp: drop where ==ref)

use crate::common::{bench_lines, ints_csv, join_csv, sink, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
/// FIXED foreach callback: each element's int value x becomes x*3-1.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_foreach(v: &[i32]) -> Vec<i32> {
    v.iter().map(|&x| (x as i64 * 3 - 1) as i32).collect()
}

/// FIXED foreach_if: add 100 to every element whose value equals `data_ref`
/// (cmp_int(a,b) == 0 means a match, exactly as the exercise's own harness).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_foreach_if(v: &[i32], data_ref: i32) -> Vec<i32> {
    v.iter()
        .map(|&x| if x == data_ref { x + 100 } else { x })
        .collect()
}

/// FIXED remove_if: drop every element whose value equals `data_ref`.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_remove_if(v: &[i32], data_ref: i32) -> Vec<i32> {
    v.iter().copied().filter(|&x| x != data_ref).collect()
}

/// list_sort with the FIXED ascending-int comparator.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_sort(v: &[i32]) -> Vec<i32> {
    let mut r = v.to_vec();
    r.sort();
    r
}

/// ex16: one value inserted into an already-sorted list, ascending.
///
/// WHERE EQUAL VALUES GO IS NOT DECIDED HERE, and must not be. The subject says
/// only "so that it remains sorted in ascending order", which both before and
/// after an equal element satisfy. The corpus carries ints, and two equal ints
/// are indistinguishable once printed, so the emitted sequence is the same
/// either way -- the diff stays exact without this reference taking a position
/// the subject declines to take.
fn o_sorted_insert(v: &[i32], x: i32) -> Vec<i32> {
    let mut r = v.to_vec();
    let at = r.iter().position(|&y| y > x).unwrap_or(r.len());
    r.insert(at, x);
    r
}

/// ex17: the second sorted list merged into the first, ascending.
///
/// Same non-decision as above about equal values, for the same reason.
fn o_sorted_merge(a: &[i32], b: &[i32]) -> Vec<i32> {
    let mut r = a.to_vec();
    r.extend_from_slice(b);
    r.sort();
    r
}

// ------------------------------------------------------------- helpers
/// A signed 32-bit value biased toward small magnitudes and the i32 boundaries.
/// Used by the value-only functions (data is never dereferenced, so the full
/// range — including i32::MIN/MAX — is safe).
fn full_val(rng: &mut Rng) -> i32 {
    match rng.below(8) {
        0 => 0,
        1 => i32::MIN,
        2 => i32::MAX,
        3 => -(rng.below(1000) as i32),
        4 => rng.below(1000) as i32,
        _ => rng.next_u64() as i32,
    }
}

/// A value in the inclusive range [lo, hi]. For the callback functions whose C
/// comparator/transform does int arithmetic, this keeps every operation
/// (`a-b`, `x*3-1`, `x+100`) well within i32 so there is no signed overflow.
fn ranged_val(rng: &mut Rng, lo: i32, hi: i32) -> i32 {
    let span = (hi as i64 - lo as i64 + 1) as usize;
    lo + rng.below(span) as i32
}

/// Structured + boundary + seeded-random int lists (sizes 0..=12). `val`
/// supplies each element; structured shapes are emitted first (deterministic),
/// then a random tail.
fn int_lists(rng: &mut Rng, count: usize, val: fn(&mut Rng) -> i32) -> Vec<Vec<i32>> {
    let mut out: Vec<Vec<i32>> = Vec::new();
    out.push(vec![]);
    out.push(vec![0]);
    out.push(vec![7]);
    out.push(vec![1, 2]);
    out.push(vec![2, 1]);
    out.push(vec![1, 2, 3, 4, 5]);
    out.push(vec![5, 4, 3, 2, 1]);
    out.push(vec![7, 7, 7, 7]);
    out.push(vec![3, 1, 2]);
    while out.len() < count {
        let size = rng.below(13);
        let v: Vec<i32> = (0..size).map(|_| val(rng)).collect();
        out.push(v);
    }
    // No truncation: count.max(len) is never below len, so this only ever
    // raised the corpus. A small --count therefore keeps the whole
    // structured head rather than cutting into it, which is the policy;
    // it used to be spelled as a call that could not do anything.
    out
}

// ---------------------------------------------------------- generators
fn gen_create_elem(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let structured: &[i32] = &[0, 1, -1, 42, i32::MIN, i32::MAX];
    let mut done = 0usize;
    for &v in structured {
        if done >= count {
            break;
        }
        // trailing 1: create_elem must leave the lone node's `next` == NULL.
        let _ = writeln!(w, "{}\t{}\t1", v, v);
        done += 1;
    }
    while done < count {
        let v = full_val(&mut rng);
        let _ = writeln!(w, "{}\t{}\t1", v, v);
        done += 1;
    }
}

fn gen_list_size(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, full_val);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let _ = writeln!(w, "{}\t{}", join_csv(v), v.len());
    }
}

fn gen_list_last(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, full_val);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let out = match v.last() {
            Some(x) => x.to_string(),
            None => "NULL".to_string(),
        };
        let _ = writeln!(w, "{}\t{}", join_csv(v), out);
    }
}

fn gen_list_at(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    // Pinned contract corners (deterministic): empty list at index 0 and far,
    // single-element at its only index and just past it, and a 3-element list
    // at first / last / just-past-end / far-out-of-range. Every out-of-range
    // access must yield NULL.
    let structured: &[(&[i32], usize)] = &[
        (&[], 0),
        (&[], 5),
        (&[7], 0),
        (&[7], 1),
        (&[1, 2, 3], 0),
        (&[1, 2, 3], 2),
        (&[1, 2, 3], 3),
        (&[1, 2, 3], 100),
    ];
    for &(v, idx) in structured {
        if done >= count {
            break;
        }
        let out = match v.get(idx) {
            Some(x) => x.to_string(),
            None => "NULL".to_string(),
        };
        let _ = writeln!(w, "{}\t{}\t{}", join_csv(v), idx, out);
        done += 1;
    }
    let lists = int_lists(&mut rng, count, full_val);
    for v in &lists {
        if done >= count {
            break;
        }
        // exercise in-range and out-of-range indices (0 ..= len+2)
        let idx = rng.below(v.len() + 3);
        let out = match v.get(idx) {
            Some(x) => x.to_string(),
            None => "NULL".to_string(),
        };
        let _ = writeln!(w, "{}\t{}\t{}", join_csv(v), idx, out);
        done += 1;
    }
}

fn gen_push_front(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, full_val);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let mut r = v.clone();
        r.reverse();
        let _ = writeln!(w, "{}\t{}", join_csv(v), join_csv(&r));
    }
}

fn gen_push_back(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, full_val);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let _ = writeln!(w, "{}\t{}", join_csv(v), join_csv(v));
    }
}

fn gen_list_reverse(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, full_val);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let mut r = v.clone();
        r.reverse();
        let _ = writeln!(w, "{}\t{}", join_csv(v), join_csv(&r));
    }
}

fn gen_list_sort(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    // bounded so the C comparator's (*a - *b) never overflows.
    let lists = int_lists(&mut rng, count, |r| ranged_val(r, -100_000, 100_000));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let _ = writeln!(w, "{}\t{}", join_csv(v), join_csv(&o_sort(v)));
    }
}

fn gen_sorted_list_insert(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    // Bounded for the C comparator's (*a - *b), exactly as gen_list_sort is.
    // SORTED on the way out: this exercise's precondition is that the list it
    // is handed is already in order, so a corpus of unsorted lists would be
    // asking the deliverable a question the subject never poses.
    let lists = int_lists(&mut rng, count, |r| ranged_val(r, -100_000, 100_000));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let sorted = o_sort(v);
        let x = ranged_val(&mut rng, -100_000, 100_000);
        let _ = writeln!(
            w,
            "{}\t{}\t{}",
            join_csv(&sorted),
            x,
            join_csv(&o_sorted_insert(&sorted, x))
        );
    }
}

fn gen_sorted_list_merge(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, |r| ranged_val(r, -100_000, 100_000));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        // The second list is drawn independently, so the pairs cover the cases
        // that matter for a merge: either side empty, one entirely below the
        // other, and interleaved.
        let n = rng.below(9) as usize;
        let mut other: Vec<i32> = Vec::new();
        while other.len() < n {
            other.push(ranged_val(&mut rng, -100_000, 100_000));
        }
        let a = o_sort(v);
        let b = o_sort(&other);
        let _ = writeln!(
            w,
            "{}\t{}\t{}",
            join_csv(&a),
            join_csv(&b),
            join_csv(&o_sorted_merge(&a, &b))
        );
    }
}

fn gen_list_clear(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, full_val);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        // a correct clear invokes free_fct exactly once per element.
        let _ = writeln!(w, "{}\t{}", join_csv(v), v.len());
    }
}

fn gen_foreach(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    // bounded so the C transform (x*3 - 1) never overflows.
    let lists = int_lists(&mut rng, count, |r| ranged_val(r, -1_000_000, 1_000_000));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let _ = writeln!(w, "{}\t{}", join_csv(v), join_csv(&o_foreach(v)));
    }
}

fn gen_foreach_if(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    // small range so equality with `ref` (and hence matches) is common.
    let lists = int_lists(&mut rng, count, |r| ranged_val(r, 0, 20));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let data_ref = ranged_val(&mut rng, 0, 20);
        let r = o_foreach_if(v, data_ref);
        let _ = writeln!(w, "{}\t{}\t{}", join_csv(v), data_ref, join_csv(&r));
    }
}

fn gen_remove_if(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, |r| ranged_val(r, 0, 20));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let data_ref = ranged_val(&mut rng, 0, 20);
        let r = o_remove_if(v, data_ref);
        let _ = writeln!(w, "{}\t{}\t{}", join_csv(v), data_ref, join_csv(&r));
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c12_create_elem" => gen_create_elem(seed, count),
        "c12_list_size" => gen_list_size(seed, count),
        "c12_list_last" => gen_list_last(seed, count),
        "c12_list_at" => gen_list_at(seed, count),
        "c12_push_front" => gen_push_front(seed, count),
        "c12_push_back" => gen_push_back(seed, count),
        "c12_list_reverse" => gen_list_reverse(seed, count),
        "c12_list_sort" => gen_list_sort(seed, count),
        "c12_sorted_list_insert" => gen_sorted_list_insert(seed, count),
        "c12_sorted_list_merge" => gen_sorted_list_merge(seed, count),
        "c12_list_clear" => gen_list_clear(seed, count),
        "c12_foreach" => gen_foreach(seed, count),
        "c12_foreach_if" => gen_foreach_if(seed, count),
        "c12_remove_if" => gen_remove_if(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- sorted insert / merge (ex16, ex17) ----
    //
    // Hand-verified cases first, then properties. The properties are the part
    // that matters: these two are the exercises whose entire correctness
    // evidence used to be one short expected.txt, so a reference that agreed
    // with itself and with nothing else would have been no improvement.
    if o_sorted_insert(&[], 5) != vec![5]
        || o_sorted_insert(&[1, 3], 2) != vec![1, 2, 3]
        || o_sorted_insert(&[1, 3], 0) != vec![0, 1, 3]
        || o_sorted_insert(&[1, 3], 9) != vec![1, 3, 9]
    {
        eprintln!("CHECK FAIL c12 sorted_insert hand cases");
        fails += 1;
    }
    if o_sorted_merge(&[], &[]) != Vec::<i32>::new()
        || o_sorted_merge(&[1, 3], &[]) != vec![1, 3]
        || o_sorted_merge(&[], &[2, 4]) != vec![2, 4]
        || o_sorted_merge(&[1, 3, 5], &[2, 4]) != vec![1, 2, 3, 4, 5]
        || o_sorted_merge(&[1, 2], &[3, 4]) != vec![1, 2, 3, 4]
    {
        eprintln!("CHECK FAIL c12 sorted_merge hand cases");
        fails += 1;
    }
    {
        let mut rng = Rng::new(7);
        for _ in 0..500 {
            let a = o_sort(&(0..rng.below(9)).map(|_| ranged_val(&mut rng, -50, 50)).collect::<Vec<i32>>());
            let b = o_sort(&(0..rng.below(9)).map(|_| ranged_val(&mut rng, -50, 50)).collect::<Vec<i32>>());
            let x = ranged_val(&mut rng, -50, 50);

            // Insert: one longer, still ordered, and the same multiset plus x.
            let ins = o_sorted_insert(&a, x);
            let mut want = a.clone();
            want.push(x);
            want.sort();
            if ins.len() != a.len() + 1 || ins.windows(2).any(|w| w[0] > w[1]) || ins != want {
                eprintln!("CHECK FAIL c12 sorted_insert property");
                fails += 1;
                break;
            }

            // Merge: the union as a multiset, ordered, and -- the one that
            // catches a merge that drops or duplicates on the seam -- the same
            // answer whichever side it is given first.
            let m = o_sorted_merge(&a, &b);
            let mut union = a.clone();
            union.extend_from_slice(&b);
            union.sort();
            if m.len() != a.len() + b.len()
                || m.windows(2).any(|w| w[0] > w[1])
                || m != union
                || m != o_sorted_merge(&b, &a)
            {
                eprintln!("CHECK FAIL c12 sorted_merge property");
                fails += 1;
                break;
            }
        }
    }

    // ---- foreach transform ----
    if o_foreach(&[1, 2, 3]) != vec![2, 5, 8] {
        eprintln!("CHECK FAIL c12 foreach [1,2,3]");
        fails += 1;
    }
    if o_foreach(&[]) != Vec::<i32>::new() || o_foreach(&[0]) != vec![-1] {
        eprintln!("CHECK FAIL c12 foreach empty/zero");
        fails += 1;
    }

    // ---- foreach_if ----
    if o_foreach_if(&[5, 7, 5, 9, 5], 5) != vec![105, 7, 105, 9, 105] {
        eprintln!("CHECK FAIL c12 foreach_if ref=5");
        fails += 1;
    }
    if o_foreach_if(&[1, 2, 3], 5) != vec![1, 2, 3] {
        eprintln!("CHECK FAIL c12 foreach_if no-match");
        fails += 1;
    }

    // ---- remove_if ----
    if o_remove_if(&[1, 9, 2, 9, 3], 9) != vec![1, 2, 3] {
        eprintln!("CHECK FAIL c12 remove_if interior");
        fails += 1;
    }
    if o_remove_if(&[9, 9, 9], 9) != Vec::<i32>::new() {
        eprintln!("CHECK FAIL c12 remove_if all");
        fails += 1;
    }
    if o_remove_if(&[1, 2], 9) != vec![1, 2] {
        eprintln!("CHECK FAIL c12 remove_if none");
        fails += 1;
    }

    // ---- sort hand cases ----
    if o_sort(&[3, 1, 2]) != vec![1, 2, 3] {
        eprintln!("CHECK FAIL c12 sort [3,1,2]");
        fails += 1;
    }
    if o_sort(&[3, -1, -5, 0, 3]) != vec![-5, -1, 0, 3, 3] {
        eprintln!("CHECK FAIL c12 sort dups/neg");
        fails += 1;
    }

    // ---- properties over seeded random inputs ----
    let mut rng = Rng::new(1212);
    for _ in 0..20000 {
        let size = rng.below(13);

        // sort: ascending AND a permutation of the input
        let sv: Vec<i32> = (0..size).map(|_| ranged_val(&mut rng, -100_000, 100_000)).collect();
        let s = o_sort(&sv);
        if s.windows(2).any(|w| w[0] > w[1]) {
            eprintln!("CHECK FAIL c12 sort not ordered");
            fails += 1;
        }
        let mut a1 = sv.clone();
        let mut a2 = s.clone();
        a1.sort();
        a2.sort();
        if a1 != a2 {
            eprintln!("CHECK FAIL c12 sort not a permutation");
            fails += 1;
        }

        // foreach: length preserved, each element transformed independently
        let fv: Vec<i32> = (0..size).map(|_| ranged_val(&mut rng, -1_000_000, 1_000_000)).collect();
        let fr = o_foreach(&fv);
        if fr.len() != fv.len() || fr.iter().zip(&fv).any(|(&y, &x)| y != x * 3 - 1) {
            eprintln!("CHECK FAIL c12 foreach prop");
            fails += 1;
        }

        // remove_if: result is exactly the elements != ref, order preserved
        let rv: Vec<i32> = (0..size).map(|_| ranged_val(&mut rng, 0, 20)).collect();
        let rf = ranged_val(&mut rng, 0, 20);
        let rr = o_remove_if(&rv, rf);
        let expect: Vec<i32> = rv.iter().copied().filter(|&x| x != rf).collect();
        if rr != expect || rr.iter().any(|&x| x == rf) {
            eprintln!("CHECK FAIL c12 remove_if prop");
            fails += 1;
        }

        // foreach_if: matches +100, non-matches unchanged, length preserved
        let ir = o_foreach_if(&rv, rf);
        if ir.len() != rv.len() {
            eprintln!("CHECK FAIL c12 foreach_if len");
            fails += 1;
        }
        for (&y, &x) in ir.iter().zip(&rv) {
            let want = if x == rf { x + 100 } else { x };
            if y != want {
                eprintln!("CHECK FAIL c12 foreach_if prop");
                fails += 1;
                break;
            }
        }
    }

    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "c12_create_elem" | "c12_list_size" | "c12_list_last" | "c12_list_at"
        | "c12_push_front" | "c12_push_back" | "c12_list_reverse" | "c12_list_sort"
        | "c12_list_clear" | "c12_foreach" | "c12_foreach_if" | "c12_remove_if"
        | "c12_sorted_list_insert" | "c12_sorted_list_merge") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        let v = ints_csv(f[0]);
        match name {
            "c12_create_elem" => sink(f[0].parse::<i32>().ok()),
            "c12_list_size" | "c12_list_clear" => sink(v.len()),
            "c12_list_last" => sink(v.last().copied()),
            "c12_list_at" => { if f.len() >= 2 { if let Ok(i) = f[1].parse::<usize>() { sink(v.get(i).copied()); } } }
            "c12_push_front" | "c12_list_reverse" => sink(v.iter().rev().copied().collect::<Vec<i32>>()),
            "c12_push_back" => sink(v.clone()),
            "c12_list_sort" => sink(o_sort(&v)),
            "c12_sorted_list_insert" => {
                if f.len() >= 2 {
                    if let Ok(x) = f[1].parse::<i32>() {
                        sink(o_sorted_insert(&v, x));
                    }
                }
            }
            "c12_sorted_list_merge" => {
                if f.len() >= 2 {
                    sink(o_sorted_merge(&v, &ints_csv(f[1])));
                }
            }
            "c12_foreach" => sink(o_foreach(&v)),
            "c12_foreach_if" => { if f.len() >= 2 { if let Ok(d) = f[1].parse::<i32>() { sink(o_foreach_if(&v, d)); } } }
            _ => { if f.len() >= 2 { if let Ok(d) = f[1].parse::<i32>() { sink(o_remove_if(&v, d)); } } }
        }
    }
    true
}
