//! c-piscine-c-06 — the argv module.
//!
//! Four programs, and between them they need exactly one thing generated: a
//! LIST OF ARGUMENTS. Every exercise here is "do something with argv and write
//! it out", so one corpus shape serves all four and the arm names differ only
//! in what the expected block holds.
//!
//! WHY THIS IS WORTH A DIFFERENTIAL LAYER AT ALL, given that each exercise
//! already has hand-written output cases. The hand-written ones use arguments a
//! human types: `test1 test2 test3`. The bugs live everywhere else --
//!
//!   * an EMPTY argument. `./a.out "" x` must print a blank line and then x. A
//!     loop that stops on `*argv[i] == '\0'` prints nothing at all, and no case
//!     anybody types by hand contains an empty string.
//!   * an argument with a NEWLINE or a SPACE in it, which is one argument and
//!     not two, and which a program that splits on whitespace gets wrong.
//!   * BYTES >= 0x80 in ft_sort_params. "ASCII order" on a machine where `char`
//!     is signed means \xff sorts BELOW 'a' if the comparison is done on chars
//!     and ABOVE it if done on unsigned chars. The subject says ASCII order;
//!     the reference sorts unsigned, which is what strcmp does. This is the
//!     single likeliest silent difference in the module and no hand case has a
//!     byte above 0x7f in it.
//!   * a PREFIX pair -- "ab" against "abc" -- where the shorter must come
//!     first. A comparison that stops at the shorter length calls them equal
//!     and leaves the order to the sort's stability, which is not a rule the
//!     subject gives.
//!   * DUPLICATES, which a sort that swaps on `<= 0` will keep swapping.
//!   * ZERO arguments, where all four programs print nothing at all except
//!     ex00, which still prints its own name.
//!
//! WHAT IS NOT GENERATED, and why:
//!
//!   * a NUL byte inside an argument. execve cannot express one -- the argument
//!     vector is NUL-terminated strings -- so there is no program, correct or
//!     not, that could be distinguished by it.
//!   * argv[0], because "all arguments except argv[0]" means what it holds
//!     cannot show in the output. ex00 IS argv[0] and has no arm here at all:
//!     tools/progname_test.sh already runs that binary under two different
//!     names and checks its exit status as well as its output, so a corpus of
//!     more names would be a second copy of a layer that exists.
//!   * anything about EXIT STATUS or stderr. The subject pins neither, and
//!     three of these four exercises have no error path at all.

use crate::common::{esc_posix, o_strcmp, Rng};

/// One case: the arguments after argv[0], and what the program must print.
///
/// The line shape is
///     <tag>\t<nargs>\t<arg1>\t...\t<argN>\t<escaped-expected>
/// with every field POSIX-escaped (`\n`, `\t`, `\\`, `\0NNN`), which is what
/// lets an argument hold a tab without becoming two fields. nargs is present so
/// the reader can peel exactly that many before the expected block, rather than
/// guessing from a separator that an argument could also contain.
///
/// Octal, not `\xHH`: /bin/sh here is dash, and dash's `printf %b` decodes
/// `\0NNN` and prints `\xHH` back literally. rush00's hex form is read by a C
/// program; this one is read by the shell.
fn line(tag: &str, args: &[Vec<u8>], expected: &[u8]) -> String {
    let mut s = String::from(tag);
    s.push('\t');
    s.push_str(&args.len().to_string());
    for a in args {
        s.push('\t');
        s.push_str(&esc_posix(a));
    }
    s.push('\t');
    s.push_str(&esc_posix(expected));
    s
}

/// Every argument on its own line, in the order given. ft_print_params.
fn o_print(args: &[Vec<u8>]) -> Vec<u8> {
    let mut out = Vec::new();
    for a in args {
        out.extend_from_slice(a);
        out.push(b'\n');
    }
    out
}

/// The same, last to first. ft_rev_params.
fn o_rev(args: &[Vec<u8>]) -> Vec<u8> {
    let mut out = Vec::new();
    for a in args.iter().rev() {
        out.extend_from_slice(a);
        out.push(b'\n');
    }
    out
}

/// The same, in ASCII order. ft_sort_params.
///
/// UNSIGNED byte comparison, and the whole exercise turns on it: `char` is
/// signed on x86, so a comparison written on `char` puts every byte >= 0x80
/// BELOW every ASCII letter. "ASCII order" is the order of the code points, so
/// 0xff is the largest byte there is. o_strcmp is the reference's own strcmp
/// (unsigned, NUL-terminated), shared from common.rs rather than repeated here.
///
/// A stable sort, so that equal arguments keep the order they arrived in. The
/// subject does not settle what happens to duplicates -- but any correct
/// answer prints the same MULTISET, and since equal strings are
/// indistinguishable in the output, stability is a property of the reference
/// rather than a demand on the student.
fn o_sort(args: &[Vec<u8>]) -> Vec<u8> {
    let mut v: Vec<Vec<u8>> = args.to_vec();
    // Insertion sort, written out rather than taken from the standard library:
    // this file is the definition of the answer, and `sort_by` would put the
    // comparison one level away from the property being defined.
    for i in 1..v.len() {
        let mut j = i;
        while j > 0 && o_strcmp(&v[j - 1], &v[j]) > 0 {
            v.swap(j - 1, j);
            j -= 1;
        }
    }
    o_print(&v)
}

/// Arguments a person would never type, which is the point.
///
/// Ordered least to most exotic, so the first failing case is the most
/// fundamental thing wrong.
fn fixed_cases() -> Vec<Vec<Vec<u8>>> {
    let s = |t: &str| t.as_bytes().to_vec();
    vec![
        // The subject's own example.
        vec![s("test1"), s("test2"), s("test3")],
        // Nothing at all. Three of the four print nothing; a program that
        // writes a newline "to finish off" fails here and nowhere else.
        vec![],
        // One argument, so "between the arguments" and "after each argument"
        // stop being distinguishable anywhere else.
        vec![s("only")],
        // An empty argument, twice over. A loop that treats an empty string as
        // the end of the list prints nothing from here on.
        vec![s(""), s("after")],
        vec![s("before"), s(""), s("after")],
        // Whitespace INSIDE one argument. One argument, not two.
        vec![s("two words"), s("tab\there"), s("nl\nhere")],
        // The prefix pair, both ways round, and a duplicate. Only ex03 can
        // tell these apart, and it is where a comparison that stops at the
        // shorter length goes wrong.
        vec![s("ab"), s("abc")],
        vec![s("abc"), s("ab")],
        vec![s("same"), s("same"), s("same")],
        // Case and digits against letters: '0' < 'A' < 'a' in ASCII, which a
        // sort written with tolower() gets wrong.
        vec![s("banana"), s("Apple"), s("42"), s("apple"), s("Banana")],
        // The signed-char trap. 0xff is the LARGEST byte; a comparison on
        // signed char calls it the smallest.
        vec![vec![0xff], s("a"), vec![0x80], s("~"), vec![0x01]],
        // A long argument beside short ones, for a fixed-size buffer.
        vec![s(&"x".repeat(300)), s("y")],
    ]
}

/// A random argument: length 0..12, bytes drawn to hit the boundaries that
/// matter rather than uniformly over 1..=255.
fn rand_arg(rng: &mut Rng) -> Vec<u8> {
    let len = rng.below(13);
    let mut a = Vec::with_capacity(len);
    for _ in 0..len {
        // A small alphabet makes ties, prefixes and near-misses COMMON, which
        // is what the sort has to get right; a uniform draw over 255 bytes
        // makes every argument distinct at its first character and tests
        // nothing but the loop.
        let b = match rng.below(10) {
            0..=5 => b'a' + rng.below(4) as u8,
            6 => b'A' + rng.below(4) as u8,
            7 => b'0' + rng.below(3) as u8,
            8 => 0x80 + rng.below(0x80) as u8,
            _ => match rng.below(3) {
                0 => b' ',
                1 => b'\t',
                _ => b'\n',
            },
        };
        a.push(b);
    }
    a
}

fn corpus(rng: &mut Rng, count: usize) -> Vec<Vec<Vec<u8>>> {
    let mut out = fixed_cases();
    while out.len() < count {
        let n = rng.below(7);
        out.push((0..n).map(|_| rand_arg(rng)).collect());
    }
    out.truncate(count.max(fixed_cases().len()));
    out
}

pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    let mut rng = Rng::new(seed);
    match name {
        "c06_print_params" => {
            for c in corpus(&mut rng, count) {
                println!("{}", line("args", &c, &o_print(&c)));
            }
        }
        "c06_rev_params" => {
            for c in corpus(&mut rng, count) {
                println!("{}", line("args", &c, &o_rev(&c)));
            }
        }
        "c06_sort_params" => {
            for c in corpus(&mut rng, count) {
                println!("{}", line("args", &c, &o_sort(&c)));
            }
        }
        _ => return false,
    }
    true
}

// ---------------------------------------------------------------------------
// Self-check.
//
// Each property is checked against something OTHER than the function that
// produces it, because a reference compared with itself is a tautology.

pub fn check() -> usize {
    let mut fails = 0;
    let s = |t: &str| t.as_bytes().to_vec();

    // The subject's own example, byte for byte.
    if o_print(&[s("test1"), s("test2"), s("test3")]) != s("test1\ntest2\ntest3\n") {
        eprintln!("c06: the subject's ft_print_params example does not reproduce");
        fails += 1;
    }

    // Reversing twice is the identity, for every corpus case. This catches an
    // off-by-one at either end that a single hand-checked example would not.
    let mut rng = Rng::new(7);
    for c in corpus(&mut rng, 200) {
        let rev: Vec<Vec<u8>> = c.iter().rev().cloned().collect();
        if o_rev(&c) != o_print(&rev) {
            eprintln!("c06: rev is not print-of-reversed");
            fails += 1;
            break;
        }
        // Every arm prints exactly one newline per argument and nothing else,
        // so the total length is fixed no matter the order.
        let want: usize = c.iter().map(|a| a.len() + 1).sum();
        for (what, got) in [("print", o_print(&c)), ("rev", o_rev(&c)), ("sort", o_sort(&c))] {
            if got.len() != want {
                eprintln!("c06: {} changed the total byte count", what);
                fails += 1;
            }
            if !got.is_empty() && *got.last().unwrap() != b'\n' {
                eprintln!("c06: {} did not end with a newline", what);
                fails += 1;
            }
        }
    }

    // SORTEDNESS, checked without o_sort: split the output back into lines and
    // require each to be <= the next under an INDEPENDENT comparison written
    // here, not o_strcmp.
    let cmp = |a: &[u8], b: &[u8]| -> bool {
        let n = a.len().min(b.len());
        for i in 0..n {
            if a[i] != b[i] {
                return a[i] < b[i]; // unsigned: this is what "ASCII order" means
            }
        }
        a.len() <= b.len()
    };
    let mut rng = Rng::new(11);
    for c in corpus(&mut rng, 300) {
        let out = o_sort(&c);
        // An argument may contain a newline, so the output cannot be split on
        // one to recover the arguments. Sortedness is checked on the sorted
        // VECTOR instead, rebuilt the same way o_sort builds it.
        let mut v = c.clone();
        for i in 1..v.len() {
            let mut j = i;
            while j > 0 && o_strcmp(&v[j - 1], &v[j]) > 0 {
                v.swap(j - 1, j);
                j -= 1;
            }
        }
        for w in v.windows(2) {
            if !cmp(&w[0], &w[1]) {
                eprintln!("c06: sort produced an out-of-order pair");
                fails += 1;
                break;
            }
        }
        // ...and it is a PERMUTATION, not a filter: same multiset in, same out.
        let mut a = c.clone();
        let mut b = v.clone();
        a.sort();
        b.sort();
        if a != b {
            eprintln!("c06: sort lost or invented an argument");
            fails += 1;
        }
        if out != o_print(&v) {
            eprintln!("c06: sort's output is not its sorted vector printed");
            fails += 1;
        }
    }

    // The signed-char trap, stated as its own case so that a future "tidy-up"
    // of o_strcmp into a signed comparison fails here by name.
    //
    // The expectation is built from BYTES rather than from a &str: 0xff inside
    // a Rust string literal is U+00FF, which encodes as the two bytes c3 bf,
    // and comparing against that would be comparing against the wrong thing.
    let mut want = s("a");
    want.push(b'\n');
    want.push(0xff);
    want.push(b'\n');
    if o_sort(&[vec![0xff], s("a")]) != want {
        eprintln!("c06: 0xff did not sort ABOVE 'a' -- ASCII order is unsigned");
        fails += 1;
    }

    // The prefix rule, both ways round: "ab" before "abc" whichever order they
    // arrive in.
    let mut pref = s("ab");
    pref.push(b'\n');
    pref.extend_from_slice(b"abc\n");
    for c in [vec![s("ab"), s("abc")], vec![s("abc"), s("ab")]] {
        if o_sort(&c) != pref {
            eprintln!("c06: a prefix did not sort before the longer string");
            fails += 1;
        }
    }

    // An empty argument is a line, not the end of the list.
    if o_print(&[s(""), s("after")]) != s("\nafter\n") {
        eprintln!("c06: an empty argument did not print as a blank line");
        fails += 1;
    }

    // No arguments: nothing at all, from all three of the argv arms.
    for (what, got) in [("print", o_print(&[])), ("rev", o_rev(&[])), ("sort", o_sort(&[]))] {
        if !got.is_empty() {
            eprintln!("c06: {} printed something for an empty argument list", what);
            fails += 1;
        }
    }

    // THE ESCAPE ROUND-TRIPS, including the bytes that make it necessary. A
    // corpus is only as good as the encoding that carries it, and an argument
    // holding a tab is one that would otherwise become two fields.
    let mut rng = Rng::new(13);
    for c in corpus(&mut rng, 200) {
        for a in &c {
            if crate::common::unesc_posix(&esc_posix(a)) != *a {
                eprintln!("c06: an argument did not survive the escape round-trip");
                fails += 1;
                break;
            }
        }
    }
    // ...and it must never emit \xHH, which dash prints back literally instead
    // of decoding. This is what stops someone unifying this escape with
    // rush00's hex one, whose consumer is a C reader and not the shell.
    let mut rng = Rng::new(17);
    for c in corpus(&mut rng, 400) {
        for a in &c {
            if esc_posix(a).contains("\\x") {
                eprintln!("c06: the escape emitted \\x, which dash does not decode");
                fails += 1;
                break;
            }
        }
    }

    // A NUL byte must never reach the corpus: execve cannot carry one, so a
    // case containing one would be a case no program could fail.
    let mut rng = Rng::new(19);
    for c in corpus(&mut rng, 400) {
        for a in &c {
            if a.contains(&0) {
                eprintln!("c06: an argument contained a NUL, which argv cannot hold");
                fails += 1;
                break;
            }
        }
    }

    fails
}
