//! c-13 btree references (create_node, insert_data, search_item, level_count,
//! apply_prefix/infix/suffix, apply_by_level). See oracle/README.md.
//!
//! Corpus encodes the INPUT tree as a sequence of byte-strings inserted in
//! order under one rule (fixed comparator = strcmp: item < node -> left, item >=
//! node -> right, per the ex04 subject "lower on the left, higher-or-equal on
//! the right"). Strings are lowercase-hex encoded and comma-joined; an empty
//! field is the empty tree. The reference builds that tree, runs the modelled
//! function, and serialises the result in the SAME encoding the harness emits.
//!
//! The C harnesses never apply that rule themselves. Every arm whose harness
//! needs a ready-made tree also emits its <shape>: for each item in order, `-`
//! if it is the root, else `<parent index><L|R>` -- the earlier item it hangs
//! under and on which side. The harness links node i under node <parent> and
//! is done: it compares no item and walks no tree, so it holds no insert. ex04
//! is the exception the other way round -- there the STUDENT builds the tree,
//! and the corpus carries <paths> to look at it with (see `probes`).
//!
//! Line formats (input fields, then reference output):
//!   c13_create_node <hexItem>\t<hexItem>\tNULL\tNULL\t1  (trailing 1: item aliased)
//!   c13_insert_data  <seq>\t<paths>\t<found-csv>  (hex at an item's path, NULL at an empty slot)
//!   c13_search_item  <seq>\t<shape>\t<hexQuery>\t<hexFound|NULL>
//!   c13_level_count  <seq>\t<shape>\t<height>
//!   c13_apply_prefix <seq>\t<shape>\t<prefix-hex-csv>
//!   c13_apply_infix  <seq>\t<shape>\t<infix-hex-csv>
//!   c13_apply_suffix <seq>\t<shape>\t<suffix-hex-csv>
//!   c13_apply_by_level <seq>\t<shape>\t<hex@level@first,...>
//!
//! <seq> stays the FIRST field of every arm: the c_cycles targets count nodes
//! off $1 (c-piscine-c-13/BUILD.bazel, NODE).

use crate::common::{bench_lines, push_hex, rand_body, sink, to_hex, unhex, unhex_csv, Rng};
use std::fmt::Write as _;
use std::io::{self, Write};

// ------------------------------------------------------------- tree model
type Link = Option<Box<Node>>;

// PartialEq compares the whole tree -- shape AND bytes -- which is what the
// ex04 probe check below needs to decide whether two trees differ at all.
#[derive(PartialEq)]
struct Node {
    item: Vec<u8>,
    left: Link,
    right: Link,
}

/// Which side an item goes, given the item already in the node it meets:
/// true for the right. The subject's rule is `subject_rule`; the others exist
/// only so `check()` can build the WRONG trees ex04's probes must catch.
type Rule = fn(&[u8], &[u8]) -> bool;

/// The ex04 contract: strictly-lower keys go left, equal-or-higher keys go
/// right. Byte (unsigned) lexicographic order == strcmp order.
fn subject_rule(item: &[u8], node: &[u8]) -> bool {
    item >= node
}

fn insert_by(root: &mut Link, item: Vec<u8>, rule: Rule) {
    match root {
        None => *root = Some(Box::new(Node { item, left: None, right: None })),
        Some(n) => {
            if rule(&item, &n.item) {
                insert_by(&mut n.right, item, rule);
            } else {
                insert_by(&mut n.left, item, rule);
            }
        }
    }
}

fn insert(root: &mut Link, item: Vec<u8>) {
    insert_by(root, item, subject_rule);
}

fn build(seq: &[Vec<u8>]) -> Link {
    let mut root: Link = None;
    for s in seq {
        insert(&mut root, s.clone());
    }
    root
}

// ------------------------------------------------------------- shape
/// Where each item of `seq` lands when the items are inserted in order under
/// the subject's rule: entry i is None for the root (always item 0), else
/// Some((parent, right)) -- the index of the item it hangs under, and whether
/// on the right. Worked out on an index arena rather than on boxes so each
/// item keeps its index; `check()` holds it to `build`'s tree node for node.
///
/// This is what lets the C harnesses hold no insert of their own: they link
/// node i under node `parent` on the side given, and never compare an item or
/// walk a tree. The placement rule lives here, in the oracle, and only here.
fn shape(seq: &[Vec<u8>]) -> Vec<Option<(usize, bool)>> {
    let mut kids: Vec<[Option<usize>; 2]> = Vec::with_capacity(seq.len());
    let mut out: Vec<Option<(usize, bool)>> = Vec::with_capacity(seq.len());
    for (i, it) in seq.iter().enumerate() {
        kids.push([None, None]);
        if i == 0 {
            out.push(None);
            continue;
        }
        let mut at = 0usize;
        loop {
            let right = subject_rule(it, &seq[at]);
            match kids[at][right as usize] {
                Some(next) => at = next,
                None => {
                    kids[at][right as usize] = Some(i);
                    out.push(Some((at, right)));
                    break;
                }
            }
        }
    }
    out
}

/// The <shape> field: `-` for the root, `<parent>L` or `<parent>R` for every
/// other item, comma-joined in insertion order; "" for the empty tree.
fn shape_field(sh: &[Option<(usize, bool)>]) -> String {
    let mut s = String::with_capacity(sh.len() * 3);
    for (i, e) in sh.iter().enumerate() {
        if i != 0 {
            s.push(',');
        }
        match e {
            None => s.push('-'),
            Some((p, right)) => {
                // Straight into the field, no temporary String per node (the
                // same reasoning as join_hex below).
                let _ = write!(s, "{}{}", p, if *right { 'R' } else { 'L' });
            }
        }
    }
    s
}

/// The route from the root to every node of a shape, as letters: L takes the
/// left link, R the right. The root's route is empty. A parent always comes
/// before its child in insertion order, so its route is already known.
fn routes(sh: &[Option<(usize, bool)>]) -> Vec<String> {
    let mut r: Vec<String> = Vec::with_capacity(sh.len());
    for e in sh {
        let mut p = String::new();
        if let Some((parent, right)) = e {
            p.push_str(&r[*parent]);
            p.push(if *right { 'R' } else { 'L' });
        }
        r.push(p);
    }
    r
}

/// ex04's probe list, and the reason it is enough.
///
/// In ex04 the student's code builds the tree, and the harness must look at it
/// without walking it in any traversal order. So the reference names WHERE to
/// look: the route of every inserted item, in insertion order, then the route
/// of every EMPTY child slot the correct tree has -- n + 1 of them, taken node
/// by node in insertion order, left before right; the root slot itself when
/// the tree is empty. The harness follows each route and prints what is there.
///
/// That is a complete observation. Two trees that agree at every node route of
/// the reference AND are empty at every one of its empty slots are the same
/// tree: an extra node anywhere hangs, somewhere up its own route, off one of
/// those empty slots, so the slot is not empty. A missing node leaves its route
/// empty; a misplaced one shows the wrong bytes or none. `check()` confirms it
/// on trees built with the wrong rules.
///
/// Returns the routes and how many of them (the first ones) lead to an item.
fn probes(seq: &[Vec<u8>]) -> (Vec<String>, usize) {
    let sh = shape(seq);
    let mut r = routes(&sh);
    let n = r.len();
    let mut taken = vec![[false; 2]; n];
    for (p, right) in sh.iter().flatten() {
        taken[*p][*right as usize] = true;
    }
    if n == 0 {
        r.push(String::new());
    }
    for i in 0..n {
        for (side, c) in [(0usize, 'L'), (1usize, 'R')] {
            if !taken[i][side] {
                let mut p = r[i].clone();
                p.push(c);
                r.push(p);
            }
        }
    }
    (r, n)
}

/// A route as the corpus spells it: the root's empty route is written `.`.
fn route_text(r: &str) -> &str {
    if r.is_empty() {
        "."
    } else {
        r
    }
}

/// What the ex04 harness sees along each route: the node's bytes, or None as
/// soon as a link is empty. The C side does the same, one letter at a time.
fn observe<'a>(root: &'a Link, routes: &[String]) -> Vec<Option<&'a [u8]>> {
    routes
        .iter()
        .map(|r| {
            let mut at = root.as_deref();
            for c in r.bytes() {
                at = at.and_then(|n| if c == b'L' { n.left.as_deref() } else { n.right.as_deref() });
            }
            at.map(|n| n.item.as_slice())
        })
        .collect()
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
        // Routes, then what the student's tree must hold at the end of each:
        // the item that was inserted n-th at the n-th route, nothing at the
        // empty slots after them. This used to print the infix and prefix
        // traversals, which made the harness walk the student's tree in both
        // orders -- two exercise answers in a test file. The routes see
        // strictly more: infix + prefix cannot always tell two trees with
        // repeated items apart, and these always can (see `probes`).
        let (routes, n) = probes(seq);
        let mut paths = String::new();
        let mut found = String::new();
        for (k, r) in routes.iter().enumerate() {
            if k != 0 {
                paths.push(',');
                found.push(',');
            }
            paths.push_str(route_text(r));
            if k < n {
                push_hex(&mut found, &seq[k]);
            } else {
                found.push_str("NULL");
            }
        }
        let _ = writeln!(w, "{}\t{}\t{}", join_hex(seq), paths, found);
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
        let sh = shape_field(&shape(seq));
        let _ = writeln!(w, "{}\t{}\t{}\t{}", join_hex(seq), sh, to_hex(q), res);
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
        let sh = shape_field(&shape(seq));
        let _ = writeln!(w, "{}\t{}\t{}\t{}", join_hex(seq), sh, to_hex(&q), res);
        done += 1;
    }
}

fn gen_level_count(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    for_each_seq(&mut rng, count, |seq| {
        let root = build(seq);
        let sh = shape_field(&shape(seq));
        let _ = writeln!(w, "{}\t{}\t{}", join_hex(seq), sh, height(&root));
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
        let sh = shape_field(&shape(seq));
        let _ = writeln!(w, "{}\t{}\t{}", join_hex(seq), sh, join_hex(&out));
    });
}

fn gen_apply_by_level(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let mut w = io::BufWriter::new(io::stdout());
    for_each_seq(&mut rng, count, |seq| {
        let root = build(seq);
        let lv = by_level(&root);
        let sh = shape_field(&shape(seq));
        let _ = writeln!(w, "{}\t{}\t{}", join_hex(seq), sh, join_level(&lv));
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

    // ---- shape: the tree the harnesses link, derived by hand ----
    // 4 2 6 1 3 5 7: 2 and 6 hang under 4, then two under each of them.
    if shape_field(&shape(&seq)) != "-,0L,0R,1L,1R,2L,2R" {
        eprintln!("CHECK FAIL c13 shape balanced");
        fails += 1;
    }
    // equal keys: each copy goes right of the one before it.
    if shape_field(&shape(&[s(b"5"), s(b"5"), s(b"5")])) != "-,0R,1R" {
        eprintln!("CHECK FAIL c13 shape all-equal");
        fails += 1;
    }
    // b a b: a left of b, the second b right of the first.
    if shape_field(&shape(&[s(b"b"), s(b"a"), s(b"b")])) != "-,0L,0R" {
        eprintln!("CHECK FAIL c13 shape equal->right");
        fails += 1;
    }
    if !shape_field(&shape(&[])).is_empty() {
        eprintln!("CHECK FAIL c13 shape empty");
        fails += 1;
    }

    // ---- ex04's probes, derived by hand ----
    // tests/ex04/test_btree_insert_data.c inserts 5 3 8 1 4 7 9 2 6 as ints;
    // single digits order the same as bytes, so the model can place them. The
    // routes below were worked out by hand from the subject's rule, one insert
    // at a time, and tests/ex04/expected.txt was written from the same
    // derivation. This check does not READ that file: the two agree because
    // both were derived the same way, and this is the second derivation.
    let fx: Vec<Vec<u8>> = b"538147926".iter().map(|c| vec![*c]).collect();
    let (r, n) = probes(&fx);
    let want_nodes = ["", "L", "R", "LL", "LR", "RL", "RR", "LLR", "RLL"];
    let mut slots: Vec<&str> = r[n.min(r.len())..].iter().map(|x| x.as_str()).collect();
    slots.sort();
    let want_slots = ["LLL", "LLRL", "LLRR", "LRL", "LRR", "RLLL", "RLLR", "RLR", "RRL", "RRR"];
    if n != 9 || r[..9] != want_nodes || slots != want_slots {
        eprintln!("CHECK FAIL c13 ex04 fixture routes");
        fails += 1;
    }
    // Its dup block: 5 5 5 at the root, R and RR, and every other slot empty.
    let (r, n) = probes(&[s(b"5"), s(b"5"), s(b"5")]);
    let mut slots: Vec<&str> = r[n.min(r.len())..].iter().map(|x| x.as_str()).collect();
    slots.sort();
    if n != 3 || r[..3] != ["", "R", "RR"] || slots != ["L", "RL", "RRL", "RRR"] {
        eprintln!("CHECK FAIL c13 ex04 dup routes");
        fails += 1;
    }
    // The empty tree has one probe -- the root slot -- and it must stay empty.
    let (r, n) = probes(&[]);
    if n != 0 || r != vec![String::new()] {
        eprintln!("CHECK FAIL c13 ex04 empty routes");
        fails += 1;
    }
    // The routes field as the corpus spells it, slots in node order.
    let (r, _) = probes(&[s(b"b"), s(b"a"), s(b"b")]);
    let spelled: Vec<&str> = r.iter().map(|x| route_text(x)).collect();
    if spelled.join(",") != ".,L,R,LL,LR,RL,RR" {
        eprintln!("CHECK FAIL c13 ex04 routes field");
        fails += 1;
    }

    // Wrong rules for the probe sweep below: equal keys to the left, and the
    // whole comparison mirrored with equal keys on either side.
    let wrong: [(&str, Rule); 3] = [
        ("equal-left", |a, b| a > b),
        ("mirrored", |a, b| a < b),
        ("mirrored equal-right", |a, b| a <= b),
    ];
    // How often each kind of wrong tree really differed, so the sweep cannot
    // pass by never producing one: wrong rules, then a lost and a doubled item.
    let mut differed = [0usize; 5];

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

        // shape: item 0 is the root and only item 0; every other item hangs
        // under an EARLIER one, so the harness can link in one pass; no slot is
        // claimed twice.
        let sh = shape(seq);
        let mut claimed: Vec<(usize, bool)> = Vec::new();
        for (i, e) in sh.iter().enumerate() {
            let ok = match e {
                None => i == 0,
                Some(pr) => i != 0 && pr.0 < i && !claimed.contains(pr),
            };
            if !ok {
                eprintln!("CHECK FAIL c13 shape malformed");
                fails += 1;
                break;
            }
            if let Some(pr) = e {
                claimed.push(*pr);
            }
        }

        // ex04's probes against build(): the k-th inserted item at the k-th
        // route, nothing at any empty-slot route. By the argument at `probes`
        // that pins build()'s whole tree -- so it also proves that the shape
        // the other harnesses link (the same routes) IS build()'s tree.
        let (routes, n) = probes(seq);
        let want: Vec<Option<&[u8]>> = (0..routes.len())
            .map(|k| if k < n { Some(seq[k].as_slice()) } else { None })
            .collect();
        if n != seq.len() || routes.len() != 2 * n + 1 || observe(&root, &routes) != want {
            eprintln!("CHECK FAIL c13 ex04 probes vs build");
            fails += 1;
        }

        // ... and the probes tell a wrong tree from the right one exactly when
        // it IS different: never a false alarm, never a miss.
        let mut wrong_trees: Vec<Link> = Vec::new();
        for (_, rule) in wrong.iter() {
            let mut t: Link = None;
            for x in seq {
                insert_by(&mut t, x.clone(), *rule);
            }
            wrong_trees.push(t);
        }
        if !seq.is_empty() {
            // an insert that is lost, and one that lands twice
            let k = seq.len() / 2;
            let mut lost = seq.clone();
            lost.remove(k);
            wrong_trees.push(build(&lost));
            let mut twice = seq.clone();
            twice.insert(k + 1, seq[k].clone());
            wrong_trees.push(build(&twice));
        }
        for (i, t) in wrong_trees.iter().enumerate() {
            let same = *t == root;
            if (observe(t, &routes) == want) != same {
                let what = if i < wrong.len() { wrong[i].0 } else if i == wrong.len() { "lost" } else { "twice" };
                eprintln!("CHECK FAIL c13 ex04 probes vs a {} tree", what);
                fails += 1;
            }
            if !same {
                differed[i] += 1;
            }
        }
    }
    if differed.iter().any(|&d| d == 0) {
        eprintln!("CHECK FAIL c13 ex04 probe sweep never built one kind of wrong tree");
        fails += 1;
    }

    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
/// Every c13 line starts with <seq>: the comma-hex node list the tree is built
/// from, so the reference work is building that tree and walking it. (The C
/// harnesses link it from <shape> instead; for at most eleven nodes the two
/// costs are the same order, and neither is the student's.)
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
            // <seq>\t<shape>\t<hexQuery>\t...
            _ => { if f.len() >= 3 { sink(contains(&root, &unhex(f[2]))); } }
        }
        sink(out.len());
    }
    true
}
