//! c-13 btree references (create_node, insert_data, search_item, level_count,
//! apply_prefix/infix/suffix, apply_by_level). See oracle/README.md.
//!
//! Corpus encodes the INPUT tree as a sequence of byte-strings the harness BST-
//! inserts (fixed comparator = strcmp: item < node -> left, item >= node ->
//! right, per the ex04 subject "lower on the left, higher-or-equal on the
//! right"). Strings are lowercase-hex encoded and comma-joined; an empty field
//! is the empty tree. The reference builds the same tree, runs the modelled
//! function, and serialises the result in the SAME encoding the harness emits.
//!
//! Line formats (input fields, then reference output):
//!   c13_create_node <hexItem>\t<hexItem>\tNULL\tNULL\t1  (trailing 1: item aliased)
//!   c13_insert_data  <seq>\t<infix-hex-csv>\t<prefix-hex-csv>  (infix sorted; prefix shape)
//!   c13_search_item  <seq>\t<hexQuery>\t<hexFound|NULL>
//!   c13_level_count  <seq>\t<height>
//!   c13_apply_prefix <seq>\t<prefix-hex-csv>
//!   c13_apply_infix  <seq>\t<infix-hex-csv>
//!   c13_apply_suffix <seq>\t<suffix-hex-csv>
//!   c13_apply_by_level <seq>\t<hex@level@first,...>

use crate::common::{bench_lines, push_hex, rand_body, sink, to_hex, unhex, unhex_csv, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- tree model
type Link = Option<Box<Node>>;

struct Node {
    item: Vec<u8>,
    left: Link,
    right: Link,
}

/// BST insert with the ex04 contract: strictly-lower keys go left, equal-or-
/// higher keys go right. Byte (unsigned) lexicographic order == strcmp order.
fn insert(root: &mut Link, item: Vec<u8>) {
    match root {
        None => *root = Some(Box::new(Node { item, left: None, right: None })),
        Some(n) => {
            if item < n.item {
                insert(&mut n.left, item);
            } else {
                insert(&mut n.right, item);
            }
        }
    }
}

fn build(seq: &[Vec<u8>]) -> Link {
    let mut root: Link = None;
    for s in seq {
        insert(&mut root, s.clone());
    }
    root
}

// The traversals BORROW each node's bytes rather than cloning them. The tree
// outlives the vector of results in every caller, and join_hex only reads, so
// the clone was pure copying — one allocation per node per traversal, and
// gen_insert_data runs two traversals per case.
fn prefix<'a>(n: &'a Link, out: &mut Vec<&'a [u8]>) {
    if let Some(b) = n {
        out.push(&b.item);
        prefix(&b.left, out);
        prefix(&b.right, out);
    }
}

fn infix<'a>(n: &'a Link, out: &mut Vec<&'a [u8]>) {
    if let Some(b) = n {
        infix(&b.left, out);
        out.push(&b.item);
        infix(&b.right, out);
    }
}

fn suffix<'a>(n: &'a Link, out: &mut Vec<&'a [u8]>) {
    if let Some(b) = n {
        suffix(&b.left, out);
        suffix(&b.right, out);
        out.push(&b.item);
    }
}

/// "size of the largest branch": node-count height. Empty -> 0, single -> 1.
fn height(n: &Link) -> i64 {
    match n {
        None => 0,
        Some(b) => 1 + height(&b.left).max(height(&b.right)),
    }
}

/// btree_search_item: infix-first node whose key equals `q`. Because equal keys
/// share identical bytes, membership decides the result and the found item's
/// bytes equal `q`; a BST descent finds a present key.
fn contains(n: &Link, q: &[u8]) -> bool {
    match n {
        None => false,
        Some(b) => {
            if q == b.item.as_slice() {
                true
            } else if q < b.item.as_slice() {
                contains(&b.left, q)
            } else {
                contains(&b.right, q)
            }
        }
    }
}

/// Level-order traversal, left-to-right; is_first == 1 for the first node seen
/// at each level.
fn by_level(root: &Link) -> Vec<(Vec<u8>, i64, i64)> {
    let mut res: Vec<(Vec<u8>, i64, i64)> = Vec::new();
    let mut cur: Vec<&Node> = Vec::new();
    if let Some(b) = root {
        cur.push(b);
    }
    let mut level = 0i64;
    while !cur.is_empty() {
        let mut next: Vec<&Node> = Vec::new();
        for (i, n) in cur.iter().enumerate() {
            res.push((n.item.clone(), level, if i == 0 { 1 } else { 0 }));
            if let Some(l) = &n.left {
                next.push(l.as_ref());
            }
            if let Some(r) = &n.right {
                next.push(r.as_ref());
            }
        }
        cur = next;
        level += 1;
    }
    res
}

// ------------------------------------------------------------- helpers
/// Comma-joined lowercase-hex of each byte-string (empty slice -> "").
fn join_hex<T: AsRef<[u8]>>(seq: &[T]) -> String {
    // Hex straight into the accumulator. The previous version called to_hex per
    // element, which allocated a String, copied it in and dropped it — once per
    // tree node per case. Same bytes out; see common::push_hex.
    let mut s = String::with_capacity(seq.iter().map(|x| x.as_ref().len() * 2 + 1).sum());
    for (i, x) in seq.iter().enumerate() {
        if i != 0 {
            s.push(',');
        }
        push_hex(&mut s, x.as_ref());
    }
    s
}

/// `hex@level@first` entries comma-joined.
fn join_level(v: &[(Vec<u8>, i64, i64)]) -> String {
    let mut s = String::new();
    for (i, (it, lv, fst)) in v.iter().enumerate() {
        if i != 0 {
            s.push(',');
        }
        s.push_str(&to_hex(it));
        s.push('@');
        s.push_str(&lv.to_string());
        s.push('@');
        s.push_str(&fst.to_string());
    }
    s
}

/// A non-empty byte-string body (len 1..=6), never containing 0x00.
fn rand_str(rng: &mut Rng, high: bool) -> Vec<u8> {
    let len = 1 + rng.below(6);
    rand_body(rng, len, high)
}

/// Structured + boundary + seeded-random string sequences (tree corpora),
/// handed to `f` ONE AT A TIME.
///
/// This used to build the whole corpus into a Vec<Vec<Vec<u8>>> and return it,
/// which meant a 1M-case run held every sequence in memory before emitting a
/// byte — measured at 388 MB peak RSS for c13_insert_data. Nothing needs the
/// corpus as a whole: each generator consumes one sequence, writes one line and
/// moves on. Streaming makes the oracle's memory use independent of `count`.
///
/// The RNG is touched in exactly the same order as before (the structured head
/// consumes none, the tail draws the same values in the same sequence), so the
/// corpus is byte-identical at every seed and count.
fn for_each_seq<F: FnMut(&[Vec<u8>])>(rng: &mut Rng, count: usize, mut f: F) {
    let s = |b: &[u8]| b.to_vec();
    let head: Vec<Vec<Vec<u8>>> = vec![
        vec![],                                                                  // empty tree
        vec![s(b"m")],                                                           // single
        vec![s(b"a"), s(b"b"), s(b"c"), s(b"d")],                                // ascending -> right chain
        vec![s(b"d"), s(b"c"), s(b"b"), s(b"a")],                                // descending -> left chain
        vec![s(b"m"), s(b"f"), s(b"t"), s(b"c"), s(b"h"), s(b"p"), s(b"z")],     // balanced-ish
        vec![s(b"5"), s(b"5"), s(b"5")],                                         // all-equal (>= right chain)
        vec![s(b"b"), s(b"a"), s(b"b"), s(b"c"), s(b"b")],                       // duplicates mixed
        vec![s(b"kk"), s(b"kk"), s(b"aa"), s(b"zz"), s(b"kk")],
        vec![s(&[0xff]), s(&[0x80]), s(b"a"), s(&[0x01])],                       // high bytes (unsigned cmp)
        vec![s(b"ab"), s(b"abc"), s(b"a"), s(b"abcd")],                          // strict-prefix keys
        vec![s(b"b"), s(b"a"), s(b"b")],                                         // equal->right structural corner
    ];
    // The structured head is emitted in FULL even when count < 11, exactly as
    // the old Vec-building version did (it pushed all 11, then topped up while
    // len < count). These are the pinned contract corners; dropping them for a
    // small count would quietly weaken the corpus.
    let mut emitted = 0usize;
    for seq in head.iter() {
        f(seq);
        emitted += 1;
    }
    // One reused buffer for the random tail: the callback never keeps the slice.
    let mut seq: Vec<Vec<u8>> = Vec::new();
    while emitted < count {
        seq.clear();
        let n = rng.below(11); // 0..=10 nodes
        let high = rng.below(2) == 1;
        for _ in 0..n {
            seq.push(rand_str(rng, high));
        }
        // sometimes force a duplicate to exercise the equal->right rule
        if rng.below(3) == 0 && !seq.is_empty() {
            let idx = rng.below(seq.len());
            let d = seq[idx].clone();
            let pos = rng.below(seq.len() + 1);
            seq.insert(pos, d);
        }
        f(&seq);
        emitted += 1;
    }
}

/// The whole corpus at once. Only check() wants this; the generators stream.
fn gen_seqs(rng: &mut Rng, count: usize) -> Vec<Vec<Vec<u8>>> {
    let mut out = Vec::new();
    for_each_seq(rng, count, |seq| out.push(seq.to_vec()));
    out
}

// ---------------------------------------------------------- generators
fn gen_create_node(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    let structured: Vec<Vec<u8>> = vec![
        vec![],
        b"a".to_vec(),
        b"hello".to_vec(),
        b"42".to_vec(),
        vec![0xff, 0x80, 0x01],
    ];
    let mut done = 0usize;
    for it in &structured {
        if done >= count {
            break;
        }
        let h = to_hex(it);
        // trailing 1: create_node must STORE the given item pointer (node->item
        // == item), not a copy of the bytes.
        let _ = writeln!(w, "{}\t{}\tNULL\tNULL\t1", h, h);
        done += 1;
    }
    while done < count {
        let high = rng.below(2) == 1;
        let len = rng.below(17);
        let it = rand_body(&mut rng, len, high);
        let h = to_hex(&it);
        let _ = writeln!(w, "{}\t{}\tNULL\tNULL\t1", h, h);
        done += 1;
    }
}

fn gen_insert_data(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    for_each_seq(&mut rng, count, |seq| {
        let root = build(seq);
        let mut ino: Vec<&[u8]> = Vec::new();
        infix(&root, &mut ino);
        // Also emit the PREFIX (pre-order) traversal: infix of a BST is the
        // sorted multiset regardless of where equal keys land, so it CANNOT see
        // the "equal-or-higher goes right" rule. Pre-order is shape-sensitive and
        // pins that corner (an equal->left insert diverges here).
        let mut pre: Vec<&[u8]> = Vec::new();
        prefix(&root, &mut pre);
        let _ = writeln!(
            w,
            "{}\t{}\t{}",
            join_hex(seq),
            join_hex(&ino),
            join_hex(&pre)
        );
    });
}

fn gen_search_item(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let seqs = gen_seqs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    let s = |b: &[u8]| b.to_vec();
    // Deterministic corners emitted first (each pins one contract edge):
    //   empty tree + any query -> NULL; single node found; single-node miss on
    //   both descent sides; a strict PREFIX of a present key is NOT present;
    //   a present key that is a strict prefix of another IS found; duplicate key
    //   found; high-byte (unsigned) key found; a near-miss differing only in the
    //   last byte -> NULL.
    let corners: Vec<(Vec<Vec<u8>>, Vec<u8>)> = vec![
        (vec![], s(b"a")),
        (vec![s(b"m")], s(b"m")),
        (vec![s(b"m")], s(b"a")),
        (vec![s(b"m")], s(b"z")),
        (vec![s(b"abc")], s(b"ab")),
        (vec![s(b"ab"), s(b"abc"), s(b"abcd")], s(b"ab")),
        (vec![s(b"ab"), s(b"abc"), s(b"abcd")], s(b"abc")),
        (vec![s(b"ab"), s(b"abc"), s(b"abcd")], s(b"abcde")),
        (vec![s(b"5"), s(b"5"), s(b"5")], s(b"5")),
        (vec![s(&[0xff]), s(&[0x80]), s(b"a")], s(&[0xff])),
        (vec![s(&[0xff]), s(&[0x80]), s(b"a")], s(&[0x80])),
        (vec![s(b"abc"), s(b"abd")], s(b"abe")),
        (vec![s(b"abc"), s(b"abd")], s(b"abd")),
    ];
    let mut done = 0usize;
    for (seq, q) in &corners {
        if done >= count {
            break;
        }
        let root = build(seq);
        let res = if contains(&root, q) {
            to_hex(q)
        } else {
            "NULL".to_string()
        };
        let _ = writeln!(w, "{}\t{}\t{}", join_hex(seq), to_hex(q), res);
        done += 1;
    }
    // NOT .skip(done). The corpus opens with 11 structured tree shapes — empty,
    // single, both chains, all-equal, high-byte, strict-prefix — and `done` is
    // 13 by the time the deterministic corner queries above have run, so
    // skipping that many stepped over every one of them. btree_search_item was
    // therefore only ever exercised against randomly-shaped trees: never an
    // empty tree, never a pure chain, never a set of equal keys. Starting from
    // the beginning keeps the total at `count` (the loop still breaks there) and
    // costs only 13 random tail cases.
    for seq in seqs.iter() {
        if done >= count {
            break;
        }
        let root = build(seq);
        // half the time query a present key, else a random (usually absent) one
        let q = if rng.below(2) == 0 && !seq.is_empty() {
            seq[rng.below(seq.len())].clone()
        } else {
            let high = rng.below(2) == 1;
            rand_str(&mut rng, high)
        };
        let res = if contains(&root, &q) {
            to_hex(&q)
        } else {
            "NULL".to_string()
        };
        let _ = writeln!(w, "{}\t{}\t{}", join_hex(seq), to_hex(&q), res);
        done += 1;
    }
}

fn gen_level_count(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    for_each_seq(&mut rng, count, |seq| {
        let root = build(seq);
        let _ = writeln!(w, "{}\t{}", join_hex(seq), height(&root));
    });
}

fn gen_traversal(seed: u64, count: usize, kind: u8) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    for_each_seq(&mut rng, count, |seq| {
        let root = build(seq);
        let mut out: Vec<&[u8]> = Vec::new();
        match kind {
            0 => prefix(&root, &mut out),
            1 => infix(&root, &mut out),
            _ => suffix(&root, &mut out),
        }
        let _ = writeln!(w, "{}\t{}", join_hex(seq), join_hex(&out));
    });
}

fn gen_apply_by_level(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    for_each_seq(&mut rng, count, |seq| {
        let root = build(seq);
        let lv = by_level(&root);
        let _ = writeln!(w, "{}\t{}", join_hex(seq), join_level(&lv));
    });
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c13_create_node" => gen_create_node(seed, count),
        "c13_insert_data" => gen_insert_data(seed, count),
        "c13_search_item" => gen_search_item(seed, count),
        "c13_level_count" => gen_level_count(seed, count),
        "c13_apply_prefix" => gen_traversal(seed, count, 0),
        "c13_apply_infix" => gen_traversal(seed, count, 1),
        "c13_apply_suffix" => gen_traversal(seed, count, 2),
        "c13_apply_by_level" => gen_apply_by_level(seed, count),
        _ => return false,
    }
    true
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;
    let s = |b: &[u8]| b.to_vec();

    // ---- hand-verified small tree: insert 4,2,6,1,3,5,7 (as bytes) ----
    let seq = vec![
        s(b"4"), s(b"2"), s(b"6"), s(b"1"), s(b"3"), s(b"5"), s(b"7"),
    ];
    let root = build(&seq);

    let mut pre: Vec<&[u8]> = Vec::new();
    prefix(&root, &mut pre);
    if pre != vec![s(b"4"), s(b"2"), s(b"1"), s(b"3"), s(b"6"), s(b"5"), s(b"7")] {
        eprintln!("CHECK FAIL c13 prefix balanced");
        fails += 1;
    }
    let mut ino: Vec<&[u8]> = Vec::new();
    infix(&root, &mut ino);
    if ino != vec![s(b"1"), s(b"2"), s(b"3"), s(b"4"), s(b"5"), s(b"6"), s(b"7")] {
        eprintln!("CHECK FAIL c13 infix balanced");
        fails += 1;
    }
    let mut suf: Vec<&[u8]> = Vec::new();
    suffix(&root, &mut suf);
    if suf != vec![s(b"1"), s(b"3"), s(b"2"), s(b"5"), s(b"7"), s(b"6"), s(b"4")] {
        eprintln!("CHECK FAIL c13 suffix balanced");
        fails += 1;
    }
    if height(&root) != 3 {
        eprintln!("CHECK FAIL c13 height balanced");
        fails += 1;
    }
    let lv = by_level(&root);
    let want_lv: Vec<(Vec<u8>, i64, i64)> = vec![
        (s(b"4"), 0, 1),
        (s(b"2"), 1, 1),
        (s(b"6"), 1, 0),
        (s(b"1"), 2, 1),
        (s(b"3"), 2, 0),
        (s(b"5"), 2, 0),
        (s(b"7"), 2, 0),
    ];
    if lv != want_lv {
        eprintln!("CHECK FAIL c13 by_level balanced");
        fails += 1;
    }

    // ---- degenerate chains ----
    let asc = vec![s(b"a"), s(b"b"), s(b"c"), s(b"d")];
    if height(&build(&asc)) != 4 {
        eprintln!("CHECK FAIL c13 height ascending chain");
        fails += 1;
    }
    let desc = vec![s(b"d"), s(b"c"), s(b"b"), s(b"a")];
    if height(&build(&desc)) != 4 {
        eprintln!("CHECK FAIL c13 height descending chain");
        fails += 1;
    }
    // all-equal keys form a right chain (>= goes right)
    let dup = vec![s(b"x"), s(b"x"), s(b"x")];
    let droot = build(&dup);
    if height(&droot) != 3 {
        eprintln!("CHECK FAIL c13 height dup chain");
        fails += 1;
    }
    let mut dpre: Vec<&[u8]> = Vec::new();
    prefix(&droot, &mut dpre);
    if dpre != vec![s(b"x"), s(b"x"), s(b"x")] {
        eprintln!("CHECK FAIL c13 dup prefix chain");
        fails += 1;
    }

    // ---- equal-goes-right: infix is blind to it, prefix is not ----
    // insert b, a, b: root b; a<b -> left; second b >= b -> right.
    let bab = build(&[s(b"b"), s(b"a"), s(b"b")]);
    let mut bab_pre: Vec<&[u8]> = Vec::new();
    prefix(&bab, &mut bab_pre);
    if bab_pre != vec![s(b"b"), s(b"a"), s(b"b")] {
        eprintln!("CHECK FAIL c13 equal->right prefix");
        fails += 1;
    }
    let mut bab_in: Vec<&[u8]> = Vec::new();
    infix(&bab, &mut bab_in);
    if bab_in != vec![s(b"a"), s(b"b"), s(b"b")] {
        eprintln!("CHECK FAIL c13 equal->right infix");
        fails += 1;
    }

    // ---- strict-prefix keys order by unsigned bytes ("a" < "ab" < "abc") ----
    let pfx = build(&[s(b"ab"), s(b"abc"), s(b"a"), s(b"abcd")]);
    let mut pfx_in: Vec<&[u8]> = Vec::new();
    infix(&pfx, &mut pfx_in);
    if pfx_in != vec![s(b"a"), s(b"ab"), s(b"abc"), s(b"abcd")] {
        eprintln!("CHECK FAIL c13 strict-prefix infix");
        fails += 1;
    }
    if !contains(&pfx, b"abc") || contains(&pfx, b"abcde") || contains(&pfx, b"b") {
        eprintln!("CHECK FAIL c13 strict-prefix membership");
        fails += 1;
    }

    // ---- empty / single edge ----
    let empty: Link = build(&[]);
    if height(&empty) != 0 || contains(&empty, b"a") {
        eprintln!("CHECK FAIL c13 empty tree");
        fails += 1;
    }
    let single = build(&[s(b"q")]);
    if height(&single) != 1 || !contains(&single, b"q") || contains(&single, b"z") {
        eprintln!("CHECK FAIL c13 single tree");
        fails += 1;
    }

    // ---- properties over seeded random corpora ----
    let mut rng = Rng::new(2026);
    let seqs = gen_seqs(&mut rng, 8000);
    for seq in &seqs {
        let root = build(seq);

        // infix is the sorted multiset of the inputs
        let mut got: Vec<&[u8]> = Vec::new();
        infix(&root, &mut got);
        let mut want = seq.clone();
        want.sort();
        if got != want {
            eprintln!("CHECK FAIL c13 infix != sorted");
            fails += 1;
        }

        // every traversal is a permutation of the same multiset, size == node count
        let mut pre: Vec<&[u8]> = Vec::new();
        prefix(&root, &mut pre);
        let mut suf: Vec<&[u8]> = Vec::new();
        suffix(&root, &mut suf);
        let mut a = pre.clone();
        a.sort();
        let mut b = suf.clone();
        b.sort();
        if a != want || b != want {
            eprintln!("CHECK FAIL c13 traversal not a permutation");
            fails += 1;
        }
        if pre.len() != seq.len() || suf.len() != seq.len() {
            eprintln!("CHECK FAIL c13 traversal length");
            fails += 1;
        }

        // level-order: node count matches, level 0 has exactly one node,
        // each level's first flag set exactly once, levels non-decreasing.
        let lv = by_level(&root);
        if lv.len() != seq.len() {
            eprintln!("CHECK FAIL c13 by_level count");
            fails += 1;
        }
        let h = height(&root);
        let mut firsts = 0i64;
        let mut prev = -1i64;
        for (_, level, first) in &lv {
            if *first == 1 {
                firsts += 1;
            }
            if *level < prev {
                eprintln!("CHECK FAIL c13 by_level level order");
                fails += 1;
                break;
            }
            prev = *level;
        }
        if !lv.is_empty() && firsts != h {
            eprintln!("CHECK FAIL c13 by_level first count != height");
            fails += 1;
        }

        // membership: every inserted key is found; a fresh key equals infix-first
        for k in seq {
            if !contains(&root, k) {
                eprintln!("CHECK FAIL c13 search present");
                fails += 1;
                break;
            }
        }
    }

    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
/// Every c13 line starts with <seq>: the comma-hex node list the harness BST-
/// inserts, so the reference work is building that tree and walking it.
pub fn bench(name: &str) -> bool {
    if !matches!(name, "c13_create_node" | "c13_insert_data" | "c13_search_item"
        | "c13_level_count" | "c13_apply_prefix" | "c13_apply_infix" | "c13_apply_suffix"
        | "c13_apply_by_level") { return false; }
    for l in bench_lines() {
        let f: Vec<&str> = l.split('\t').collect();
        if name == "c13_create_node" {
            sink(unhex(f[0]).len());
            continue;
        }
        let seq = unhex_csv(f[0]);
        let root = build(&seq);
        let mut out: Vec<&[u8]> = Vec::new();
        match name {
            "c13_insert_data" => { infix(&root, &mut out); prefix(&root, &mut out); }
            "c13_apply_prefix" => prefix(&root, &mut out),
            "c13_apply_infix" => infix(&root, &mut out),
            "c13_apply_suffix" => suffix(&root, &mut out),
            "c13_level_count" => sink(height(&root)),
            "c13_apply_by_level" => sink(by_level(&root).len()),
            _ => { if f.len() >= 2 { sink(contains(&root, &unhex(f[1]))); } }
        }
        sink(out.len());
    }
    true
}
