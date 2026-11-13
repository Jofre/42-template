//! c-12 references: singly-linked-list family (t_list = {next, void *data}).
//!
//! The corpus encodes the INPUT list as a comma-joined decimal int sequence
//! (empty string == the empty list; push_strs's strings are hex instead, as
//! its line below says). The reader harness builds a real t_list
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
//!   push_strs     <hex-csv>\t<result-hex-csv>    (strings, hex and comma-joined
//!                                                 as diffio.h's dio_hex_list
//!                                                 reads them; none is empty)
//!   list_reverse  <csv>\t<result-csv>
//!   list_sort     <csv>\t<sorted-csv>            (FIXED cmp: ascending int)
//!   list_clear    <csv>\t<freeCount>             (== size; free_fct call count)
//!   foreach       <csv>\t<result-csv>            (FIXED f: x -> x*3-1)
//!   foreach_if    <csv>\t<ref>\t<result-csv>     (FIXED f/cmp: +100 where ==ref)
//!   remove_if     <csv>\t<ref>\t<result-csv>\t<freeCount>
//!                                                (FIXED cmp: drop where ==ref;
//!                                                 free_fct calls == removed)
//!   sorted_list_insert <sorted-csv>\t<x>\t<result-csv>
//!                                                (the input list sorted
//!                                                 ascending; FIXED cmp:
//!                                                 ascending int)
//!   sorted_list_merge  <sorted-csv>\t<sorted-csv>\t<result-csv>
//!                                                (both input lists sorted
//!                                                 ascending; FIXED cmp:
//!                                                 ascending int)
//!   list_merge    <csv>\t<csv>\t<result-csv>      (the input lists
//!                                                 deliberately NOT sorted)

use crate::common::{bench_lines, ints_csv, join_csv, join_hex, or_null, sink, unhex_csv, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
/// ex05: the list ft_list_push_strs builds from `strs`, read from its head.
/// The order is the subject's: "The first element should be at the end of
/// the list".
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_push_strs<T: Clone>(strs: &[T]) -> Vec<T> {
    strs.iter().rev().cloned().collect()
}

/// FIXED foreach callback: each element's int value x becomes x*3-1.
#[inline(never)] // keep this attributable under callgrind (see tools/)
pub(crate) fn o_foreach(v: &[i32]) -> Vec<i32> {
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

/// ex13: the second list placed at the END of the first. Concatenation, and
/// nothing else.
///
/// The subject fixes this completely, which is what makes a differential worth
/// having here: "places elements of a list begin2 at the end of another list
/// begin1", with "element creation is not authorised" and a `void` return. So
/// the answer for (a, b) is a followed by b, in order, for every pair -- there
/// is no tie rule to leave open and no allocation to be ambiguous about.
///
/// It is NOT ex17 without the sort. ex17 merges two ALREADY-SORTED lists by a
/// comparator; this one preserves each list's own order and simply joins them,
/// so a corpus of unsorted pairs is the point rather than an oversight.
fn o_list_merge(a: &[i32], b: &[i32]) -> Vec<i32> {
    let mut r = a.to_vec();
    r.extend_from_slice(b);
    r
}

// ------------------------------------------------------------- helpers
//
// THE VALUES. The value-only functions (create_elem, size, last, at, the
// pushes, reverse, clear) never dereference their data, so the full int
// range is safe: Rng::i32val, biased toward small magnitudes and both ends
// of int. The callback functions' C comparator or transform does int
// arithmetic (`a-b`, `x*3-1`, `x+100`), so theirs come from Rng::range_i32
// within bounds that keep every such operation well inside int.

/// The lengths of the long lists every int_lists corpus carries.
const LONG_LISTS: [usize; 2] = [600, 2000];

/// Structured + boundary + seeded-random int lists (sizes 0..=12, and the
/// LONG_LISTS). `val`
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
    // Lists of hundreds and thousands of nodes (finding 041): every list
    // above holds twelve at most, so a function that walked a list through an
    // array of its own (16, 64, 512, 1024) passed every case. The values are
    // the generator's own kind, drawn from a seed of their own, so the head
    // is the same whatever the corpus's seed.
    let mut long = Rng::new(0x1157);
    for n in LONG_LISTS {
        out.push((0..n).map(|_| val(&mut long)).collect());
    }
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

/// A second list, for the two-list arms: its length drawn first, below
/// `max_len`, then each value in [lo, hi].
fn rand_ints(rng: &mut Rng, max_len: usize, lo: i32, hi: i32) -> Vec<i32> {
    let n = rng.below(max_len);
    (0..n).map(|_| rng.range_i32(lo, hi)).collect()
}

/// The one-list corpora: each list int_lists draws with `val`, then the
/// answer `answer` gives for it, tab-separated.
fn emit_lists(seed: u64, count: usize, val: fn(&mut Rng) -> i32, answer: impl Fn(&[i32]) -> String) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, val);
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let _ = writeln!(w, "{}\t{}", join_csv(v), answer(v));
    }
}

/// push_front's and list_reverse's answer: the list reversed.
fn reversed_csv(v: &[i32]) -> String {
    let mut r = v.to_vec();
    r.reverse();
    join_csv(&r)
}

// ---------------------------------------------------------- generators
/// ex05's corpus: each list int_lists draws, as strings -- each value's
/// decimal text, so that no string is empty (a comma join cannot tell one
/// empty string from none) and none holds a NUL -- then the list built from
/// them. The function stores its strings and never reads them, so what they
/// hold matters only to the harness that prints them back.
fn gen_push_strs<W: Write>(w: &mut W, seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    for v in &int_lists(&mut rng, count, Rng::i32val) {
        let strs: Vec<String> = v.iter().map(|x| x.to_string()).collect();
        let _ = writeln!(w, "{}\t{}", join_hex(&strs), join_hex(&o_push_strs(&strs)));
    }
}

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
        let v = rng.i32val();
        let _ = writeln!(w, "{}\t{}\t1", v, v);
        done += 1;
    }
}

fn gen_list_at(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let mut done = 0usize;
    // Pinned contract corners (deterministic): empty list at index 0 and far,
    // single-element at its only index and just past it, and a 3-element list
    // at first / last / just-past-end / far-out-of-range. Every out-of-range
    // access must yield NULL. nbr is an unsigned int, so the upper half of its
    // range is input too: 2^31 and UINT_MAX on a short list, and UINT_MAX on
    // an empty one -- where a counter that is a signed int stops, wraps or
    // turns negative before it reaches the index (finding 127).
    let structured: &[(&[i32], usize)] = &[
        (&[], 0),
        (&[], 5),
        (&[7], 0),
        (&[7], 1),
        (&[1, 2, 3], 0),
        (&[1, 2, 3], 2),
        (&[1, 2, 3], 3),
        (&[1, 2, 3], 100),
        (&[1, 2, 3], 2_147_483_648),
        (&[1, 2, 3], 4_294_967_295),
        (&[], 4_294_967_295),
    ];
    for &(v, idx) in structured {
        if done >= count {
            break;
        }
        let _ = writeln!(w, "{}\t{}\t{}", join_csv(v), idx, or_null(v.get(idx)));
        done += 1;
    }
    let lists = int_lists(&mut rng, count, Rng::i32val);
    for v in &lists {
        if done >= count {
            break;
        }
        // exercise in-range and out-of-range indices (0 ..= len+2)
        let idx = rng.below(v.len() + 3);
        let _ = writeln!(w, "{}\t{}\t{}", join_csv(v), idx, or_null(v.get(idx)));
        done += 1;
    }
}

fn gen_sorted_list_insert(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    // Bounded for the C comparator's (*a - *b), exactly as list_sort's corpus is.
    // SORTED on the way out: this exercise's precondition is that the list it
    // is handed is already in order, so a corpus of unsorted lists would be
    // asking the deliverable a question the subject never poses.
    let lists = int_lists(&mut rng, count, |r| r.range_i32(-100_000, 100_000));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let sorted = o_sort(v);
        let x = rng.range_i32(-100_000, 100_000);
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
    let lists = int_lists(&mut rng, count, |r| r.range_i32(-100_000, 100_000));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        // The second list is drawn independently, so the pairs cover the cases
        // that matter for a merge: either side empty, one entirely below the
        // other, and interleaved.
        let other = rand_ints(&mut rng, 9, -100_000, 100_000);
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

fn gen_foreach_if(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    // small range so equality with `ref` (and hence matches) is common.
    let lists = int_lists(&mut rng, count, |r| r.range_i32(0, 20));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let data_ref = rng.range_i32(0, 20);
        let r = o_foreach_if(v, data_ref);
        let _ = writeln!(w, "{}\t{}\t{}", join_csv(v), data_ref, join_csv(&r));
    }
}

fn gen_remove_if(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, |r| r.range_i32(0, 20));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        let data_ref = rng.range_i32(0, 20);
        let r = o_remove_if(v, data_ref);
        // "The data from an element to be erased should be freed using
        // free_fct": one call per element removed (finding 130).
        let _ = writeln!(
            w,
            "{}\t{}\t{}\t{}",
            join_csv(v),
            data_ref,
            join_csv(&r),
            v.len() - r.len()
        );
    }
}

fn gen_list_merge(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let lists = int_lists(&mut rng, count, |r| r.range_i32(-100_000, 100_000));
    let mut w = io::BufWriter::new(io::stdout());
    for v in &lists {
        // The second list is drawn independently, so the pairs cover what a
        // concatenation can get wrong: either side empty -- which is where a
        // merge that walks to the end of begin1 without checking for NULL
        // dies -- one much longer than the other, and both non-empty.
        //
        // Deliberately NOT sorted, unlike ex17's corpus: this subject says
        // nothing about order, so preserving each list's own is the whole
        // requirement, and a corpus of sorted pairs would be passed by an
        // implementation that sorted.
        let other = rand_ints(&mut rng, 9, -100_000, 100_000);
        let _ = writeln!(
            w,
            "{}\t{}\t{}",
            join_csv(v),
            join_csv(&other),
            join_csv(&o_list_merge(v, &other))
        );
    }
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c12_create_elem" => gen_create_elem(seed, count),
        // list_clear's answer is free_fct's call count: a correct clear makes
        // one per element.
        "c12_list_size" | "c12_list_clear" => emit_lists(seed, count, Rng::i32val, |v| v.len().to_string()),
        "c12_list_last" => emit_lists(seed, count, Rng::i32val, |v| or_null(v.last())),
        "c12_list_at" => gen_list_at(seed, count),
        "c12_push_front" | "c12_list_reverse" => emit_lists(seed, count, Rng::i32val, reversed_csv),
        "c12_push_back" => emit_lists(seed, count, Rng::i32val, join_csv),
        "c12_push_strs" => gen_push_strs(&mut io::BufWriter::new(io::stdout()), seed, count),
        // bounded so the C comparator's (*a - *b) never overflows.
        "c12_list_sort" => emit_lists(seed, count, |r| r.range_i32(-100_000, 100_000), |v| join_csv(&o_sort(v))),
        "c12_sorted_list_insert" => gen_sorted_list_insert(seed, count),
        "c12_sorted_list_merge" => gen_sorted_list_merge(seed, count),
        "c12_list_merge" => gen_list_merge(seed, count),
        // bounded so the C transform (x*3 - 1) never overflows.
        "c12_foreach" => emit_lists(seed, count, |r| r.range_i32(-1_000_000, 1_000_000), |v| join_csv(&o_foreach(v))),
        "c12_foreach_if" => gen_foreach_if(seed, count),
        "c12_remove_if" => gen_remove_if(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- every int_lists corpus carries its long lists, the same at every
    //      seed and count (finding 041) ----
    for seed in [1u64, 7] {
        let lists = int_lists(&mut Rng::new(seed), 0, Rng::i32val);
        let long: Vec<usize> = lists.iter().map(|l| l.len()).filter(|&n| n > 12).collect();
        if long != LONG_LISTS.to_vec() || int_lists(&mut Rng::new(seed), 0, Rng::i32val) != lists {
            eprintln!("CHECK FAIL c12 int_lists: the long lists are {:?}", long);
            fails += 1;
        }
    }
    if int_lists(&mut Rng::new(1), 0, Rng::i32val)[9] != int_lists(&mut Rng::new(9), 0, Rng::i32val)[9] {
        eprintln!("CHECK FAIL c12 int_lists: a long list depends on the corpus's seed");
        fails += 1;
    }

    // ---- push_strs (ex05) ----
    //
    // Read back from the corpus itself, at two seeds: each line's list is its
    // strings in the order the subject asks for ("The first element should be
    // at the end of the list"), checked index by index rather than by the
    // reference; no string is empty or holds a NUL, which the C reader could
    // not carry; and the corpus holds every size from 0 to 12 and the long
    // lists, so it asks what the output fixture's three sizes do not.
    for seed in [1u64, 7] {
        let mut buf = Vec::new();
        gen_push_strs(&mut buf, seed, 3000);
        let text = String::from_utf8_lossy(&buf);
        let mut sizes = std::collections::BTreeSet::new();
        let (mut lines, mut wrong, mut uncarried) = (0usize, None, None);
        for l in text.lines() {
            lines += 1;
            let f: Vec<&str> = l.split('\t').collect();
            let (strs, got) = (unhex_csv(f[0]), unhex_csv(f.get(1).copied().unwrap_or("")));
            let n = strs.len();
            if f.len() != 2 || got.len() != n || (0..n).any(|k| got[k] != strs[n - 1 - k]) {
                wrong = wrong.or(Some(f[0].to_string()));
            }
            if strs.iter().any(|s| s.is_empty() || s.contains(&0)) {
                uncarried = uncarried.or(Some(f[0].to_string()));
            }
            sizes.insert(n);
        }
        if let Some(l) = wrong {
            eprintln!("CHECK FAIL c12 push_strs seed {}: the list for {:?} is not the subject's", seed, l);
            fails += 1;
        }
        if let Some(l) = uncarried {
            eprintln!("CHECK FAIL c12 push_strs seed {}: a string the C reader cannot carry in {:?}", seed, l);
            fails += 1;
        }
        if lines != 3000 || (0..=12).any(|n| !sizes.contains(&n)) || !LONG_LISTS.iter().all(|n| sizes.contains(n)) {
            eprintln!("CHECK FAIL c12 push_strs seed {}: {} lines, sizes {:?}", seed, lines, sizes);
            fails += 1;
        }
    }
    {
        let (mut a, mut b) = (Vec::new(), Vec::new());
        gen_push_strs(&mut a, 1, 3000);
        gen_push_strs(&mut b, 7, 3000);
        if a == b {
            eprintln!("CHECK FAIL c12 push_strs: seeds 1 and 7 give the same corpus");
            fails += 1;
        }
    }

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
    // ---- plain merge (ex13) ----
    //
    // Hand cases first, and the empty ones are not ceremony: begin1 empty is
    // where an implementation that walks to the last node without checking for
    // NULL dies, and begin2 empty is where one that unconditionally links a
    // node appends a NULL.
    if o_list_merge(&[], &[]) != Vec::<i32>::new()
        || o_list_merge(&[1, 3], &[]) != vec![1, 3]
        || o_list_merge(&[], &[2, 4]) != vec![2, 4]
        || o_list_merge(&[3, 1], &[4, 2]) != vec![3, 1, 4, 2]
        || o_list_merge(&[9], &[9]) != vec![9, 9]
    {
        eprintln!("CHECK FAIL c12 list_merge hand cases");
        fails += 1;
    }
    {
        // The property, and it is the one that separates this from ex17: the
        // result is exactly a followed by b, so neither side's own order may
        // change and nothing may be dropped or duplicated. A reference that
        // sorted would pass a length check and fail this.
        let mut rng = Rng::new(11);
        for _ in 0..500 {
            let a = rand_ints(&mut rng, 9, -50, 50);
            let b = rand_ints(&mut rng, 9, -50, 50);
            let m = o_list_merge(&a, &b);
            if m.len() != a.len() + b.len()
                || m[..a.len()] != a[..]
                || m[a.len()..] != b[..]
            {
                eprintln!("CHECK FAIL c12 list_merge property");
                fails += 1;
                break;
            }
        }
    }

    {
        let mut rng = Rng::new(7);
        for _ in 0..500 {
            let a = o_sort(&rand_ints(&mut rng, 9, -50, 50));
            let b = o_sort(&rand_ints(&mut rng, 9, -50, 50));
            let x = rng.range_i32(-50, 50);

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
        let sv: Vec<i32> = (0..size).map(|_| rng.range_i32(-100_000, 100_000)).collect();
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
        let fv: Vec<i32> = (0..size).map(|_| rng.range_i32(-1_000_000, 1_000_000)).collect();
        let fr = o_foreach(&fv);
        if fr.len() != fv.len() || fr.iter().zip(&fv).any(|(&y, &x)| y != x * 3 - 1) {
            eprintln!("CHECK FAIL c12 foreach prop");
            fails += 1;
        }

        // remove_if: result is exactly the elements != ref, order preserved
        let rv: Vec<i32> = (0..size).map(|_| rng.range_i32(0, 20)).collect();
        let rf = rng.range_i32(0, 20);
        let rr = o_remove_if(&rv, rf);
        let expect: Vec<i32> = rv.iter().copied().filter(|&x| x != rf).collect();
        if rr != expect || rr.iter().any(|&x| x == rf) {
            eprintln!("CHECK FAIL c12 remove_if prop");
            fails += 1;
        }
        // ...and the free_fct count the corpus carries, v.len() - r.len(), is
        // one call per element equal to ref: the elements removed.
        if rv.len() - rr.len() != rv.iter().filter(|&&x| x == rf).count() {
            eprintln!("CHECK FAIL c12 remove_if free count");
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
        | "c12_sorted_list_insert" | "c12_sorted_list_merge"
        | "c12_list_merge" | "c12_push_strs") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        if name == "c12_push_strs" {
            sink(o_push_strs(&unhex_csv(f[0])));
            continue;
        }
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
            "c12_list_merge" => {
                if f.len() >= 2 {
                    sink(o_list_merge(&v, &ints_csv(f[1])));
                }
            }
            "c12_foreach" => sink(o_foreach(&v)),
            "c12_foreach_if" => { if f.len() >= 2 { if let Ok(d) = f[1].parse::<i32>() { sink(o_foreach_if(&v, d)); } } }
            _ => { if f.len() >= 2 { if let Ok(d) = f[1].parse::<i32>() { sink(o_remove_if(&v, d)); } } }
        }
    }
    true
}
