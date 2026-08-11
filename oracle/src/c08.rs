//! c-piscine-c-08 ex04 — ft_strs_to_tab.
//!
//! The module's other five exercises are headers and macros, which have no
//! runtime behaviour to compare; ex05 is dealt with at the foot of this file.
//!
//! WHY THIS ONE IS WORTH A DIFFERENTIAL ARM. The subject says `size` is "the
//! length of the string", so the student computes it -- and computing a string
//! length is where this repo's most-documented trap lives: a scan that walks
//! while the current byte is POSITIVE rather than while it is non-zero stops
//! dead at the first byte >= 0x80, because a plain `char` is signed. c-01 and
//! c-02 pin exactly those corners for their own length and traversal
//! exercises; c-08 ex04 computes a length too, and
//! c-piscine-c-08/tests/ex04/test_strs_to_tab.c drives "zero", "", "a" and
//! "fortytwo!" -- printable ASCII throughout. So the bug is red one module
//! earlier and green here, which is the same gap c-04's BUILD file describes
//! from the other side.
//!
//! THE CASE, and why it fits on one line. `tools/rust_diff.sh` reports by LINE
//! -- "it died at or after case N", "feed one of these to your harness" -- so a
//! case that spans lines makes every one of those messages wrong. The harness
//! therefore prints a RENDERING of the returned array rather than anything
//! resembling the array itself:
//!
//!     <n>\t<hex-av-0>...\t<hex-av-n-1>\t<rendering>
//!
//! with the rendering `size/alias/hex-of-copy` per entry joined by `,`, then
//! `;term=1`. Three properties, all of which the subject states:
//!
//!   * `size` is the length. This is the one a corpus of high bytes moves.
//!   * `str` is "the string" -- the pointer handed in, not a copy of it. The
//!     harness compares the returned pointer against `av[i]` and renders `a`
//!     when they are the same object; the reference always predicts `a`.
//!   * "the last element's str set to 0, this will mark the end of the array",
//!     rendered as `term=1`.
//!
//! `copy` is compared by its BYTES, which is what "a copy of the string" means
//! and all a corpus can see. That it is a distinct allocation is a pointer
//! property, checked where pointer properties belong -- the ASan probe in
//! tests/ex04/mem_ft_strs_to_tab.c and the allocation-failure arm beside it.
//!
//! WHAT IS NOT GENERATED:
//!
//!   * A NUL BYTE inside a string. `av` is an array of C strings; there is no
//!     input, valid or not, that could carry one.
//!   * A NULL `av`, or a NULL element inside it. The subject says the function
//!     takes "an array of strings and the size of this array" and says nothing
//!     about either, so a corpus asserting a behaviour would be inventing one.
//!   * ALLOCATION FAILURE, which the subject does cover ("return a NULL pointer
//!     if an error occurs") and which has its own layer already:
//!     tests/ex04/af_ft_strs_to_tab.c drives it under a failing malloc. A
//!     corpus cannot make malloc fail.
//!   * ANY ARM FOR ex05 (ft_show_tab). See the note at the foot of this file.

use crate::common::{rand_body, to_hex, unhex, Rng};

/// The rendering the harness must produce for `av`.
///
/// Deliberately NOT the bytes ft_show_tab would print: this is ex04's arm, and
/// what it asserts is the three field properties the subject states, one per
/// entry, on one line.
fn o_render(av: &[Vec<u8>]) -> String {
    let mut parts: Vec<String> = Vec::new();
    for s in av {
        // `a` for "str is the pointer that was handed in". The reference always
        // predicts it, so a deliverable that stores a copy there renders `-`
        // and diverges on the first case.
        parts.push(format!("{}/a/{}", s.len(), to_hex(s)));
    }
    format!("{};term=1", parts.join(","))
}

/// Arrays a hand-written fixture does not contain.
///
/// The corners are emitted FIRST and the seeded random tail is what shrinks
/// when a caller lowers `count`, so no boundary case is ever lost to a smaller
/// budget -- the rule every generator in this crate follows.
fn corners() -> Vec<Vec<Vec<u8>>> {
    let s = |t: &str| t.as_bytes().to_vec();
    vec![
        // Empty array: the terminator is the whole answer.
        vec![],
        // One empty string: size 0, and a copy that is a valid empty string.
        vec![s("")],
        vec![s("a")],
        // The signed-char corners, which is what this arm is for. A length
        // computed with `while (str[i] > 0)` stops at the first of these.
        vec![vec![0xff]],
        vec![vec![0x80]],
        vec![vec![0x7f, 0x80, 0x81, 0xff]],
        vec![vec![0xff; 5]],
        // High bytes AFTER ordinary text, so a loop that gets the first
        // character right still stops early.
        vec![vec![b'a', b'b', 0xff, b'c', b'd']],
        // Several strings, order-sensitive: a function that reverses or sorts
        // them renders the same multiset in the wrong places.
        vec![s("first"), s("second"), s("third")],
        vec![s("z"), s("y"), s("x")],
        // An empty string BETWEEN two non-empty ones: a loop that treats an
        // empty string as the end of the array truncates here.
        vec![s("before"), s(""), s("after")],
        // The full printable run, and a long string for a fixed-size buffer.
        vec![(0x20u8..=0x7e).collect()],
        vec![vec![b'x'; 300], s("y")],
        // Every byte a C string can hold, in one string.
        vec![(1u8..=255).collect()],
    ]
}

pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    if name != "c08_strs_to_tab" {
        return false;
    }
    let mut rng = Rng::new(seed);
    let mut done = 0usize;
    let mut emit = |av: &[Vec<u8>]| {
        let mut line = av.len().to_string();
        for s in av {
            line.push('\t');
            line.push_str(&to_hex(s));
        }
        line.push('\t');
        line.push_str(&o_render(av));
        println!("{}", line);
    };
    for av in corners() {
        if done >= count {
            return true;
        }
        emit(&av);
        done += 1;
    }
    while done < count {
        let n = rng.below(5);
        // The two draws are taken into locals first: `rand_body(&mut rng,
        // rng.below(17), ...)` borrows rng twice in one call and does not
        // compile. `high` half the time, because rand_body's high mode is what
        // puts bytes >= 0x80 in -- and it never emits 0x00, which av, being an
        // array of C strings, could not carry anyway.
        let mut av: Vec<Vec<u8>> = Vec::with_capacity(n);
        for _ in 0..n {
            let len = rng.below(17);
            let high = rng.below(2) == 1;
            av.push(rand_body(&mut rng, len, high));
        }
        emit(&av);
        done += 1;
    }
    true
}

// ---------------------------------------------------------------------------
// Self-check.

pub fn check() -> usize {
    let mut fails = 0;
    let s = |t: &str| t.as_bytes().to_vec();

    // The empty array renders as the terminator and nothing else.
    if o_render(&[]) != ";term=1" {
        eprintln!("c08: an empty array does not render as the bare terminator");
        fails += 1;
    }

    // Sizes are LENGTHS, counted independently of Vec::len: walk to the end.
    let mut rng = Rng::new(31);
    for _ in 0..300 {
        let n = rng.below(5);
        let mut av: Vec<Vec<u8>> = Vec::with_capacity(n);
        for _ in 0..n {
            let len = rng.below(17);
            let high = rng.below(2) == 1;
            av.push(rand_body(&mut rng, len, high));
        }
        let r = o_render(&av);
        // Rebuild the expectation by a different route: split the rendering
        // back apart and check each field against the source string.
        let body = r.strip_suffix(";term=1").unwrap_or("");
        let entries: Vec<&str> = if body.is_empty() {
            Vec::new()
        } else {
            body.split(',').collect()
        };
        if entries.len() != av.len() {
            eprintln!("c08: rendering has {} entries for {} strings", entries.len(), av.len());
            fails += 1;
            break;
        }
        for (e, src) in entries.iter().zip(av.iter()) {
            let f: Vec<&str> = e.split('/').collect();
            if f.len() != 3 {
                eprintln!("c08: an entry is not size/alias/hex");
                fails += 1;
                break;
            }
            if f[0].parse::<usize>().ok() != Some(src.len()) {
                eprintln!("c08: an entry's size is not the string's length");
                fails += 1;
            }
            if f[1] != "a" {
                eprintln!("c08: an entry does not predict str aliasing av[i]");
                fails += 1;
            }
            if unhex(f[2]) != *src {
                eprintln!("c08: an entry's copy is not the string's bytes");
                fails += 1;
            }
        }
    }

    // ORDER is preserved: reversing the input reverses the rendering's entries.
    let av = vec![s("first"), s("second"), s("third")];
    let mut rev = av.clone();
    rev.reverse();
    let fwd_s = o_render(&av);
    let bwd_s = o_render(&rev);
    let fwd: Vec<&str> = fwd_s.strip_suffix(";term=1").unwrap().split(',').collect();
    let bwd: Vec<&str> = bwd_s.strip_suffix(";term=1").unwrap().split(',').collect();
    let bwd_rev: Vec<&str> = bwd.iter().rev().copied().collect();
    if fwd != bwd_rev {
        eprintln!("c08: the rendering does not follow the order of av");
        fails += 1;
    }

    // THE CORNERS ARE ACTUALLY THERE. A corpus whose high bytes were quietly
    // tidied away would be passed by the very bug this arm exists for.
    let all = corners();
    if !all.iter().any(|av| av.iter().any(|x| x.iter().any(|&b| b >= 0x80))) {
        eprintln!("c08: no string with a byte >= 0x80 -- the signed-char trap is untested");
        fails += 1;
    }
    if !all.iter().any(|av| av.is_empty()) {
        eprintln!("c08: no empty array in the corners");
        fails += 1;
    }
    if !all.iter().any(|av| av.iter().any(|x| x.is_empty())) {
        eprintln!("c08: no empty string in the corners");
        fails += 1;
    }
    if all.iter().flatten().any(|x| x.contains(&0)) {
        eprintln!("c08: a corner string contains a NUL, which av cannot carry");
        fails += 1;
    }
    // ...and neither does the random tail, whatever the seed.
    let mut rng = Rng::new(97);
    for _ in 0..400 {
        let len = rng.below(17);
        let high = rng.below(2) == 1;
        let b = rand_body(&mut rng, len, high);
        if b.contains(&0) {
            eprintln!("c08: a generated string contains a NUL, which av cannot carry");
            fails += 1;
            break;
        }
    }

    fails
}

// ---------------------------------------------------------------------------
// WHY THERE IS NO ARM FOR ex05 (ft_show_tab), assessed rather than overlooked.
//
// Its output is fully determined -- "the string followed by a '\n', the size
// followed by a '\n', the copy of the string followed by a '\n'", per element,
// until the terminator -- so a reference could be written. Two things together
// make it the wrong trade:
//
// 1. THE COST. ft_show_tab writes to fd 1, and its output is three lines per
//    element. tools/rust_diff.sh reports BY LINE ("it died at or after case N",
//    "feed one of these to your harness"), so a case that spans lines makes
//    every one of those messages wrong. Putting it on one line means capturing
//    fd 1 and escaping it -- the machinery c-piscine-rush-00's rush_capture.h
//    carries, and a second copy of it is not free.
//
// 2. THE VALUE. Unlike ex04, ft_show_tab computes NOTHING. It reads `size` out
//    of the struct and prints it, so the signed-char trap that justifies ex04's
//    arm cannot reach it. What is left -- field order, a missing newline, the
//    terminator condition, rendering an int -- is structural, identical in
//    every case, and already driven by tests/ex05/test_show_tab.c. A corpus of
//    a thousand string arrays would exercise those same four things a thousand
//    times.
//
// If it is ever wanted, the cheap and correct answer is more arrays in that
// harness -- one with a size wide enough to need four digits, one with an empty
// string between two others -- not a fuzz layer. That is the same conclusion
// c-piscine-c-00/BUILD.bazel reached for ft_print_combn, and acting on it there
// is what turned its four-value fixture into a nine-value one.
