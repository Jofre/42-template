//! c-00 stdout references.
//!
//! Two shapes live here, and they do not resemble each other:
//!
//! * The SCALAR pair (is_negative, putnbr, i.e. ex04 and ex07). Each case is a
//!   single decimal `int` input; the reference emits the exact text the function
//!   must print. Corpus line: `<decimal-int>\t<reference-output>`. These feed
//!   the differential layer in the ordinary way.
//! * The five ZERO-INPUT arms (ex01, ex02, ex03, ex05, ex06). `void f(void)`
//!   with exactly one correct output each, so there is no corpus and no
//!   differential layer — `gen` prints the answer itself. See the long section
//!   below, and read c05.rs's ten-queens section first: most of the reasoning
//!   is shared, and the one place it is NOT is the point of these arms.

use crate::common::{bench_lines, sink, Rng};
use std::collections::HashSet;
use std::io::{self, Write};

// ------------------------------------------------------------- oracles
/// ft_is_negative: writes 'N' when n < 0, else 'P'.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_is_negative(n: i32) -> &'static str {
    if n < 0 {
        "N"
    } else {
        "P"
    }
}

/// ft_putnbr: the decimal text of n, with a leading '-' for negatives. This is
/// the full 32-bit range including INT_MIN, whose magnitude does not fit in i32
/// — Rust's own i32 formatting handles it correctly (independent of any C impl).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_putnbr(n: i32) -> String {
    n.to_string()
}

// ------------------------------------- zero-input arms (ex01/02/03/05/06)
//
// ft_print_alphabet, ft_print_reverse_alphabet, ft_print_numbers,
// ft_print_comb and ft_print_comb2 are all `void f(void)`. They take no input,
// so each has exactly one correct output and there is nothing for a generator
// to vary — which is why c-piscine-c-00/BUILD.bazel deliberately gives none of
// them a c_diff arm, the same call c-piscine-c-05/BUILD.bazel makes for
// ft_ten_queens_puzzle. Read c05.rs's ten-queens section before this one: most
// of what follows is the same decision made again, and the ONE place the
// reasoning diverges is called out at (3) because getting it backwards would
// leave this layer with nothing to say.
//
// (1) `gen`'s output IS the answer, not a corpus. Every other generator in this
//     crate prints inputs paired with reference outputs; a zero-input function's
//     corpus is its single case. So `oracle c00_print_comb <seed> <count>` —
//     both arguments accepted and ignored, deliberately, so the arm plugs into
//     the same command shape as everything else — prints the complete expected
//     output of ex05: the 120 strictly increasing digit triples, ", "-separated,
//     with no trailing separator and no trailing newline. It is byte-identical
//     to c-piscine-c-00/tests/ex05/expected.txt, and the other four are
//     byte-identical to ex01, ex02, ex03 and ex06. That is worth stating
//     plainly, because it gives five hand-curated fixtures a provenance they did
//     not have: an independently written enumeration reproduces them exactly.
//     (`check()` below re-derives all five from properties and from a second
//     construction rather than from a stored copy; see there for how much that
//     pins and what it still cannot notice.)
//
// (2) Both `gen` and `bench` PRINT, exactly as c05_ten_queens does and unlike
//     every corpus-replay arm in the crate, which computes its answer and
//     discards it. The consumer is tools/ref_compare.sh, an informative cost
//     comparison against the student's whole program, and the student's function
//     has to print: a silent reference would keep every formatted byte and every
//     syscall out of its own count while the student still paid for them.
//
// (3) THE ONE PLACE THIS IS NOT ten-queens: the write() framing.
//
//     c05_ten_queens deliberately MATCHES a reasonable student's framing — one
//     write() per line, 725 calls — so that the instruction ratio is a statement
//     about the search and not about I/O. There, printing is incidental work
//     both sides must do, and the search is the subject.
//
//     Here there is no search. Producing 26 letters or 4 950 pairs is a few
//     thousand instructions whichever way it is written, so the instruction
//     ratio is the less interesting of ref_compare's two columns. The
//     interesting one is the other: how many times each side entered the kernel
//     to emit the same bytes. These exercises authorise exactly one function,
//     write(), and the natural first solution calls it once per character — 26
//     syscalls for ex01, 598 for ex05, 34 648 for ex06. Each arm here therefore
//     emits its whole output in ONE write(), which is the floor, and the
//     distance from 1 to 34 648 is the whole message.
//
//     That gap is the one AGENTS.md §0 names outright: "The owner's own c-00
//     makes far more write() syscalls than the work needs and they never knew,
//     because nothing in the suite ever said so." A reference that framed its
//     output the way a first solution does would report parity on both columns
//     and close the gap back up. So do NOT "fix" these arms into per-character
//     writes for symmetry with ten-queens — it is the same principle (pay for
//     the same output, then let the difference speak), applied to a job whose
//     entire cost is the printing rather than one whose cost is the search.
//
//     One write is a floor, never a demand. Nothing gates on it, ref_compare
//     cannot fail on a number, and a student who writes one character at a time
//     has still written a correct ft_print_comb: the subject asked for the
//     bytes, not for a buffer. Per AGENTS.md §2 the figure is a door held open,
//     and this file's only job is to make the door an honest one.

/// The item separator these two enumerations share: comma, space, and none
/// after the last item. Named once because "where does the separator go" is
/// precisely the off-by-one both exercises are really about, and both fixtures
/// end on a digit.
const COMB_SEP: &[u8] = b", ";

/// ex01: the 26 lowercase letters ascending, no separator, no trailing newline.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_print_alphabet() -> Vec<u8> {
    let mut out = Vec::with_capacity(26);
    let mut c = b'a';
    while c <= b'z' {
        out.push(c);
        c += 1;
    }
    out
}

/// ex02: the same 26 letters descending. Written as its own descent rather than
/// as `o_print_alphabet()` reversed, so that a bug in one cannot hide inside the
/// other — the check below is what asserts the two are mirror images, and it can
/// only assert that if they were arrived at separately.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_print_reverse_alphabet() -> Vec<u8> {
    let mut out = Vec::with_capacity(26);
    let mut c = b'z';
    loop {
        out.push(c);
        if c == b'a' {
            break;
        }
        c -= 1;
    }
    out
}

/// ex03: the ten decimal digits ascending.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_print_numbers() -> Vec<u8> {
    let mut out = Vec::with_capacity(10);
    let mut d = b'0';
    while d <= b'9' {
        out.push(d);
        d += 1;
    }
    out
}

/// ex05: every strictly increasing trio of digits, once each, ", "-separated.
///
/// The bounds do the combinatorics: `b` starts above `a` and `c` above `b`, so
/// no trio can repeat, none needs rejecting, and the 120 of them leave in
/// ascending order because each loop counts up. C(10,3) = 120 items of 3 bytes
/// with 119 separators of 2 is 598 bytes — the size of the ex05 fixture.
///
/// The separator is written BEFORE each item except the first (`out` is empty
/// only there) rather than after each item except the last. The two are not
/// equivalent to write: the trailing-separator bug this exercise is famous for
/// is what you get when the "except the last" case has to be recognised inside
/// three nested loops, and here there is no last case to recognise.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_print_comb() -> Vec<u8> {
    let mut out = Vec::with_capacity(598);
    let mut a = 0u8;
    while a < 10 {
        let mut b = a + 1;
        while b < 10 {
            let mut c = b + 1;
            while c < 10 {
                if !out.is_empty() {
                    out.extend_from_slice(COMB_SEP);
                }
                out.push(b'0' + a);
                out.push(b'0' + b);
                out.push(b'0' + c);
                c += 1;
            }
            b += 1;
        }
        a += 1;
    }
    out
}

/// ex06: every pair of two-digit numbers with the second strictly greater than
/// the first, printed "AA BB" and ", "-separated.
///
/// Same shape as `o_print_comb`, one dimension shorter and two digits wider:
/// C(100,2) = 4 950 items of 5 bytes with 4 949 separators of 2 is 34 648 bytes,
/// the size of the ex06 fixture. Both members are zero-padded to two digits —
/// "00 01" and not "0 1" — which is what makes every item the same width and so
/// makes the stream's lexicographic order and its numeric order the same thing.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_print_comb2() -> Vec<u8> {
    let mut out = Vec::with_capacity(34648);
    let mut a = 0u16;
    while a < 100 {
        let mut b = a + 1;
        while b < 100 {
            if !out.is_empty() {
                out.extend_from_slice(COMB_SEP);
            }
            push_pad2(&mut out, a);
            out.push(b' ');
            push_pad2(&mut out, b);
            b += 1;
        }
        a += 1;
    }
    out
}

/// `n` in 0..100 as exactly two digits, leading zero included.
///
/// Digit arithmetic rather than `format!("{:02}", n)` on purpose: `check()`
/// cross-checks this stream against a construction that DOES use std's
/// formatting, so the padding gets a second opinion instead of one routine
/// agreeing with itself.
fn push_pad2(out: &mut Vec<u8>, n: u16) {
    out.push(b'0' + (n / 10) as u8);
    out.push(b'0' + (n % 10) as u8);
}

/// ex08's whole domain, one line per n, exactly as a harness driving 1..9 emits
/// it. `c00_print_combn 0 0` IS tests/ex08/expected.txt.
///
/// SEPARATE FROM THE ZERO-INPUT FAMILY BELOW, though it takes no argument
/// either. Those five are one fixed stream each and their check() walks them by
/// index against a five-name table; this one is nine streams with a newline
/// after each, so folding it in would mean renumbering assertions that exist to
/// catch a name wired to the wrong arm. It gets its own checks instead.
///
/// WHY IT EXISTS AT ALL, when ex08 already had a fixture: that fixture drove
/// four of the nine values the subject defines (1, 2, 4 and 9), and
/// c-piscine-c-00/BUILD.bazel's own comment named the remedy -- "the cheap and
/// correct answer is five more calls in that harness, not a fuzz layer". This
/// is where the bytes for those five come from, so the fixture is derived from
/// a checked reference rather than from whatever the deliverable happened to
/// print on the day.
///
/// The subject: "The value of n will be such that: 0 < n < 10." Nine values,
/// no more. Combinations of n DISTINCT digits in ascending order, each group
/// ascending, groups in lexicographic order, `", "` between them, no separator
/// after the last.
fn o_print_combn_all() -> Vec<u8> {
    let mut out = Vec::new();
    for n in 1..=9usize {
        let mut digits: Vec<u8> = (0..n as u8).collect();
        loop {
            for &d in &digits {
                out.push(b'0' + d);
            }
            // Advance to the next combination in lexicographic order: find the
            // rightmost digit that can still be raised, raise it, and reset
            // everything after it to run consecutively upwards.
            let mut i = n;
            while i > 0 {
                i -= 1;
                if digits[i] < 10 - (n - i) as u8 {
                    break;
                }
                if i == 0 {
                    i = n; // exhausted
                    break;
                }
            }
            if i == n {
                break;
            }
            digits[i] += 1;
            for j in i + 1..n {
                digits[j] = digits[j - 1] + 1;
            }
            out.extend_from_slice(COMB_SEP);
        }
        out.push(b'\n');
    }
    out
}

/// The five zero-input arms, by name. `None` for anything else.
///
/// Both `gen` and `bench` go through here, and so does every assertion in
/// `check()` — deliberately. Five arms whose outputs are all short ASCII streams
/// invite one specific mistake that no content property could ever catch: a name
/// wired to the wrong arm. "c00_print_alphabet returns 26 distinct lowercase
/// letters in order" is just as true of the reverse alphabet read backwards, and
/// a swapped pair would sail through a check that called `o_*` directly.
fn zero_input_output(name: &str) -> Option<Vec<u8>> {
    match name {
        "c00_print_alphabet" => Some(o_print_alphabet()),
        "c00_print_reverse_alphabet" => Some(o_print_reverse_alphabet()),
        "c00_print_numbers" => Some(o_print_numbers()),
        "c00_print_comb" => Some(o_print_comb()),
        "c00_print_comb2" => Some(o_print_comb2()),
        _ => None,
    }
}

/// Write `bytes` and nothing else.
///
/// Split out from `emit_once` and generic over the writer so `check()` can run
/// the very path the binary runs into a `Vec<u8>` and confirm it adds no framing
/// of its own. That reads like checking that a wrapper wraps nothing, and today
/// it is — but the edit it guards against is one word (`writeln!` for
/// `write_all`, or a stray `\n` added "to tidy the terminal output"), and all
/// five of these fixtures end WITHOUT a trailing newline. Such an edit leaves
/// every content property below green while putting all five arms one byte away
/// from their expected.txt, which is exactly the failure c05.rs's count-line
/// check exists to catch in its own arm.
fn write_once<W: Write>(w: &mut W, bytes: &[u8]) {
    let _ = w.write_all(bytes);
}

/// The whole output in ONE write() syscall — see point (3) above for why that
/// number is the message rather than an implementation detail.
///
/// This leans on two properties of std's stdout, written down because a refactor
/// could otherwise cost the syscall in silence:
///   * `io::stdout()` is a `LineWriter` over a 1 KiB buffer. None of these five
///     outputs contains a newline ANYWHERE, so nothing can trigger a mid-stream
///     line flush; the short arms (10 and 26 bytes) simply sit in the buffer
///     until the flush below and leave as one call.
///   * A write larger than that buffer — 598 bytes for ex05, 34 648 for ex06 —
///     bypasses it and goes straight to the fd, again as one call.
///
/// The explicit `flush()` is what makes the short arms one call rather than none
/// here and one at process exit. Do not drop it on the grounds that std flushes
/// stdout at exit anyway: "it happens somewhere" is a weaker claim than "it
/// happens once", and once is what is being measured.
///
/// Measured under callgrind with ref_compare.sh's own write() counter, stdout to
/// /dev/null: one write() per arm, all five. The single case this cannot promise
/// is a slow reader on the far end of a PIPE, where the kernel may accept a
/// partial write and `write_all` loops to finish it; ref_compare redirects both
/// sides to /dev/null, where it does not arise.
fn emit_once(bytes: &[u8]) {
    let mut w = io::stdout().lock();
    write_once(&mut w, bytes);
    let _ = w.flush();
}

// ---------------------------------------------------------- generators
/// Exhaustive small band + every 32-bit boundary + power-of-ten neighbours,
/// then a seeded random tail biased toward 0 / INT_MIN / INT_MAX / small.
fn int_cases(rng: &mut Rng, count: usize) -> Vec<i32> {
    let mut out: Vec<i32> = Vec::new();

    let fixed: &[i32] = &[
        0,
        1,
        -1,
        i32::MAX,     // 2147483647
        i32::MIN,     // -2147483648
        i32::MAX - 1, // 2147483646
        i32::MIN + 1, // -2147483647
    ];
    for &v in fixed {
        out.push(v);
    }
    // Every value in a small band around zero (covers all 1-3 digit texts and
    // the -/+ single-digit transitions).
    for v in -1000i32..=1000 {
        out.push(v);
    }
    // Powers of ten and their neighbours (carry / digit-count boundaries), both
    // signs. Guarded through i64 so 10^9 * neighbours never overflow i32.
    let mut p: i64 = 1;
    while p <= 2_000_000_000 {
        for d in [-1i64, 0, 1] {
            let v = p + d;
            if v >= i32::MIN as i64 && v <= i32::MAX as i64 {
                out.push(v as i32);
                let nv = -v;
                if nv >= i32::MIN as i64 && nv <= i32::MAX as i64 {
                    out.push(nv as i32);
                }
            }
        }
        p *= 10;
    }

    while out.len() < count {
        out.push(rng.i32val());
    }
    out
}

fn gen_is_negative(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let cases = int_cases(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for n in &cases {
        let _ = writeln!(w, "{}\t{}", n, o_is_negative(*n));
    }
}

fn gen_putnbr(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let cases = int_cases(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for n in &cases {
        let _ = writeln!(w, "{}\t{}", n, o_putnbr(*n));
    }
}

/// Dispatch: returns true if `name` belongs to this module.
///
/// The zero-input arms are tried FIRST and ignore `seed`/`count` — there is one
/// case, it is this one, and varying either could only produce the same bytes
/// again. What they print is the exercise's expected output; see point (1) of
/// the zero-input section above.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    if let Some(bytes) = zero_input_output(name) {
        emit_once(&bytes);
        return true;
    }
    if name == "c00_print_combn" {
        emit_once(&o_print_combn_all());
        return true;
    }
    match name {
        "c00_is_negative" => gen_is_negative(seed, count),
        "c00_putnbr" => gen_putnbr(seed, count),
        _ => return false,
    }
    true
}

// ------------------------------------------------------------- self-check

/// Deliberately naive ex05 stream, for cross-checking `o_print_comb`.
///
/// GENERATE AND FILTER, where the reference bounds its loops: all 1 000 digit
/// triples are visited and the ones that are not strictly increasing are thrown
/// away. It formats through `format!` rather than by adding to b'0', and it
/// joins with `Vec::join` rather than deciding per item where the separator
/// goes. Nothing about how the reference builds its bytes is reused, which is
/// the point — the same role `naive_queens` plays in c05.rs. An off-by-one in a
/// loop bound, a digit written with the wrong base offset, or a separator on the
/// wrong side of an item would all have to be reproduced here by coincidence to
/// survive.
///
/// Filtering in this loop order still yields (a, b, c) ascending, so this is a
/// second opinion on the ORDER of the fixture and not only on its contents.
fn naive_comb() -> Vec<u8> {
    let mut items: Vec<String> = Vec::new();
    for a in 0..10 {
        for b in 0..10 {
            for c in 0..10 {
                if a < b && b < c {
                    items.push(format!("{}{}{}", a, b, c));
                }
            }
        }
    }
    items.join(", ").into_bytes()
}

/// Deliberately naive ex06 stream, for cross-checking `o_print_comb2`.
///
/// Same construction as `naive_comb`: visit all 10 000 pairs, keep the ordered
/// ones, join. The padding here is `{:02}` — std's own formatting — against the
/// reference's `push_pad2` digit arithmetic, so the leading zero that "00 01"
/// needs and "10 11" does not is checked by something that shares no code with
/// the routine that produced it.
fn naive_comb2() -> Vec<u8> {
    let mut items: Vec<String> = Vec::new();
    for a in 0..100 {
        for b in 0..100 {
            if a < b {
                items.push(format!("{:02} {:02}", a, b));
            }
        }
    }
    items.join(", ").into_bytes()
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // The structured HEAD of the corpus (count == 1 emits only the deterministic
    // cases, no random tail) MUST always contain the contract corners for the
    // numeric family: 0, +/-1, and every 32-bit boundary. Both void functions
    // (is_negative sign flip at 0; putnbr INT_MIN whose magnitude overflows i32)
    // are only reliably caught if these run every time — assert they are pinned
    // so a regression that drops one fails `oracle check` instead of hiding in
    // the 400k random tail.
    let head = int_cases(&mut Rng::new(1), 1);
    let required: &[i32] = &[0, 1, -1, i32::MAX, i32::MIN, i32::MAX - 1, i32::MIN + 1];
    for &req in required {
        if !head.contains(&req) {
            eprintln!("CHECK FAIL c00 corpus head missing corner {}", req);
            fails += 1;
        }
    }

    let neg: &[(i32, &str)] = &[
        (0, "P"),
        (1, "P"),
        (-1, "N"),
        (42, "P"),
        (-42, "N"),
        (i32::MAX, "P"),
        (i32::MIN, "N"),
    ];
    for (n, want) in neg {
        if o_is_negative(*n) != *want {
            eprintln!("CHECK FAIL c00 is_negative({})", n);
            fails += 1;
        }
    }

    let pn: &[(i32, &str)] = &[
        (0, "0"),
        (5, "5"),
        (-5, "-5"),
        (42, "42"),
        (-42, "-42"),
        (100, "100"),
        (-100, "-100"),
        (2147483647, "2147483647"),
        (-2147483648, "-2147483648"),
        (2147483646, "2147483646"),
        (-2147483647, "-2147483647"),
    ];
    for (n, want) in pn {
        if o_putnbr(*n) != *want {
            eprintln!("CHECK FAIL c00 putnbr({})", n);
            fails += 1;
        }
    }

    // Properties over the whole seeded corpus.
    let mut rng = Rng::new(7);
    for _ in 0..20000 {
        let n = rng.i32val();

        // is_negative: exactly 'N' iff n < 0, exactly 'P' otherwise; single char.
        let s = o_is_negative(n);
        if s.len() != 1 || (n < 0) != (s == "N") || (n >= 0) != (s == "P") {
            eprintln!("CHECK FAIL c00 is_negative property n={}", n);
            fails += 1;
        }

        // putnbr: round-trips through i32 parse, sign marker matches, no NUL/space,
        // and every non-sign byte is a decimal digit.
        let t = o_putnbr(n);
        if t.parse::<i32>() != Ok(n) {
            eprintln!("CHECK FAIL c00 putnbr roundtrip n={}", n);
            fails += 1;
        }
        if (n < 0) != t.starts_with('-') {
            eprintln!("CHECK FAIL c00 putnbr sign n={}", n);
            fails += 1;
        }
        let digits = t.trim_start_matches('-');
        if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
            eprintln!("CHECK FAIL c00 putnbr digits n={}", n);
            fails += 1;
        }
        // No leading zeros except the literal "0".
        if t != "0" && (digits.starts_with('0')) {
            eprintln!("CHECK FAIL c00 putnbr leading-zero n={}", n);
            fails += 1;
        }
    }

    // ---- the five zero-input arms: the anti-bugged-oracle guard for c-00.
    //
    // These carry more weight than everything above them, for the reason
    // c05.rs's ten-queens block spells out about itself. ex01, ex02, ex03, ex05
    // and ex06 have no differential layer to contradict a wrong reference;
    // `gen`'s output for each IS the exercise fixture; and the only consumer is
    // a cost report shown to a student who has ALREADY been told their answer is
    // correct. A bug here would print a fabricated comparison at working code,
    // and nothing else in the suite is positioned to notice.
    //
    // Everything below goes through `zero_input_output` — the same dispatch the
    // binary uses — rather than calling the `o_*` functions directly, so that a
    // name wired to the wrong arm fails here. See that function's own comment
    // for why that mistake is the one this particular family invites.
    // ---- ex08's nine lines.
    //
    // Checked against an INDEPENDENT enumeration written here: generate every
    // n-digit sequence and keep the strictly increasing ones, which is the
    // "generate and filter" shape the ex05 cross-check uses and which shares
    // nothing with the reference's next-combination walk.
    {
        let all = o_print_combn_all();
        let lines: Vec<&[u8]> = all.split(|&b| b == b'\n').collect();
        // split leaves a trailing empty element after the final newline.
        if lines.len() != 10 || !lines[9].is_empty() {
            eprintln!("CHECK FAIL c00 print_combn is not nine newline-terminated lines");
            fails += 1;
        }
        for n in 1..=9usize {
            let mut want: Vec<String> = Vec::new();
            let mut idx = vec![0usize; n];
            // Odometer over all 10^n digit tuples; keep the strictly
            // increasing ones. Slow and obviously correct, which is the point.
            let total = 10usize.pow(n as u32);
            for v in 0..total {
                let mut x = v;
                for slot in idx.iter_mut().rev() {
                    *slot = x % 10;
                    x /= 10;
                }
                if idx.windows(2).all(|w| w[0] < w[1]) {
                    want.push(idx.iter().map(|d| d.to_string()).collect::<String>());
                }
            }
            let joined = want.join(", ");
            if lines[n - 1] != joined.as_bytes() {
                eprintln!("CHECK FAIL c00 print_combn line for n={} disagrees with the odometer", n);
                fails += 1;
            }
            // C(10, n) groups, no more and no fewer.
            let mut expect = 1usize;
            for k in 0..n {
                expect = expect * (10 - k) / (k + 1);
            }
            if want.len() != expect {
                eprintln!("CHECK FAIL c00 print_combn n={} has {} groups, not C(10,{})={}",
                    n, want.len(), n, expect);
                fails += 1;
            }
        }
        // No separator before the first group or after the last, on any line.
        for (i, l) in lines[..9].iter().enumerate() {
            if l.starts_with(b", ") || l.ends_with(b", ") || l.ends_with(b",") {
                eprintln!("CHECK FAIL c00 print_combn line {} has a dangling separator", i + 1);
                fails += 1;
            }
        }
    }

    let names: [&str; 5] = [
        "c00_print_alphabet",
        "c00_print_reverse_alphabet",
        "c00_print_numbers",
        "c00_print_comb",
        "c00_print_comb2",
    ];
    let mut streams: Vec<Vec<u8>> = Vec::new();
    for name in names {
        match zero_input_output(name) {
            Some(b) => streams.push(b),
            None => {
                eprintln!("CHECK FAIL c00 zero-input arm {} is not dispatched", name);
                fails += 1;
                // Push an empty stream so the indices below stay aligned with
                // `names`. Every property then fails loudly for this arm, which
                // is noisy but correct — a missing arm is not a small problem.
                streams.push(Vec::new());
            }
        }
    }

    // (a) The three fixed streams, as hand-written literals. For 26 and 10 bytes
    // of constant text a transcribed table IS the strongest available check —
    // there is no property of "the alphabet" stronger than the alphabet — so
    // these are pinned character by character and the properties that follow are
    // the second opinion rather than the first.
    let fixed: &[(&str, &[u8])] = &[
        ("c00_print_alphabet", b"abcdefghijklmnopqrstuvwxyz"),
        ("c00_print_reverse_alphabet", b"zyxwvutsrqponmlkjihgfedcba"),
        ("c00_print_numbers", b"0123456789"),
    ];
    for (name, want) in fixed {
        let got = zero_input_output(name).unwrap_or_default();
        if got != *want {
            eprintln!(
                "CHECK FAIL c00 {} = {:?}, want {:?}",
                name,
                String::from_utf8_lossy(&got),
                String::from_utf8_lossy(want)
            );
            fails += 1;
        }
    }

    // (b) Properties over the three fixed streams. Deliberately stated as
    // "ascending by exactly one from 'a' to 'z'" rather than as a length plus a
    // character-class test: a stream of 26 lowercase letters can still be the
    // wrong 26, and a byte count on its own is the weakest thing that could be
    // asserted about any of these five.
    let alpha = &streams[0];
    if alpha.len() != 26 || alpha.first() != Some(&b'a') || alpha.last() != Some(&b'z') {
        eprintln!("CHECK FAIL c00 print_alphabet is not 26 bytes from 'a' to 'z'");
        fails += 1;
    }
    // The per-byte sweeps below are capped at the length the stream is SUPPOSED
    // to be, not at the length it has. `b'a' + i as u8` overflows once i passes
    // 130, and an over-long stream is exactly the bug most likely to produce
    // that — a check that panics reports its failure through a stack trace and a
    // signal instead of through `fails`, which is a worse way to say the same
    // thing. The length assertion just above is what catches the excess.
    for i in 0..alpha.len().min(26) {
        // Ascending by one AND in the lowercase range, checked per byte so the
        // message names the position rather than the whole string.
        if !alpha[i].is_ascii_lowercase() || alpha[i] != b'a' + i as u8 {
            eprintln!("CHECK FAIL c00 print_alphabet byte #{} is {:?}", i, alpha[i] as char);
            fails += 1;
        }
    }
    let rev = &streams[1];
    if rev.len() != 26 || rev.first() != Some(&b'z') || rev.last() != Some(&b'a') {
        eprintln!("CHECK FAIL c00 print_reverse_alphabet is not 26 bytes from 'z' to 'a'");
        fails += 1;
    }
    for i in 0..rev.len().min(26) {
        if !rev[i].is_ascii_lowercase() || rev[i] != b'z' - i as u8 {
            eprintln!("CHECK FAIL c00 print_reverse_alphabet byte #{} is {:?}", i, rev[i] as char);
            fails += 1;
        }
    }
    // The mirror relation between the two, which neither arm's own properties
    // can see. o_print_reverse_alphabet counts down independently precisely so
    // this comparison means something; see its comment.
    let mirrored: Vec<u8> = alpha.iter().rev().copied().collect();
    if *rev != mirrored {
        eprintln!("CHECK FAIL c00 print_reverse_alphabet is not print_alphabet reversed");
        fails += 1;
    }
    let nums = &streams[2];
    if nums.len() != 10 || nums.first() != Some(&b'0') || nums.last() != Some(&b'9') {
        eprintln!("CHECK FAIL c00 print_numbers is not 10 bytes from '0' to '9'");
        fails += 1;
    }
    for i in 0..nums.len().min(10) {
        if !nums[i].is_ascii_digit() || nums[i] != b'0' + i as u8 {
            eprintln!("CHECK FAIL c00 print_numbers byte #{} is {:?}", i, nums[i] as char);
            fails += 1;
        }
    }

    // (c) ex05. The stream is checked three ways: against the independent
    // generate-and-filter construction, against its arithmetic size, and against
    // the properties the subject's wording actually states — every trio strictly
    // increasing, every trio present exactly once, the whole list ascending.
    let comb = &streams[3];
    if *comb != naive_comb() {
        eprintln!("CHECK FAIL c00 print_comb disagrees with the naive enumeration");
        fails += 1;
    }
    // 120 items of 3 bytes + 119 separators of 2. Written as the arithmetic
    // rather than as `598` so the number stays readable as a consequence of the
    // shape instead of a constant someone would have to trust.
    if comb.len() != 120 * 3 + 119 * COMB_SEP.len() {
        eprintln!("CHECK FAIL c00 print_comb is {} bytes, want 598", comb.len());
        fails += 1;
    }
    fails += check_comb_stream("print_comb", comb, 3, 120, |item| {
        // "abc" with a < b < c, digits only.
        let d: Vec<u8> = item.to_vec();
        if !d.iter().all(|c| c.is_ascii_digit()) {
            return Err("not all digits".to_string());
        }
        if !(d[0] < d[1] && d[1] < d[2]) {
            return Err("digits are not strictly increasing".to_string());
        }
        // Rank each trio into a 1000-slot space so completeness can be counted.
        Ok(((d[0] - b'0') as usize * 100)
            + ((d[1] - b'0') as usize * 10)
            + (d[2] - b'0') as usize)
    });
    // Completeness, stated the other way round: every strictly increasing trio
    // must APPEAR. `check_comb_stream` proves the items are distinct and in
    // order; with 120 distinct valid trios out of the 120 that exist, the set is
    // forced — but assert it directly anyway, because "120" is otherwise a human
    // saying C(10,3) out loud and this is the arm nothing downstream can correct.
    {
        let s = String::from_utf8_lossy(comb).to_string();
        let present: HashSet<&str> = s.split(", ").collect();
        for a in 0..10u32 {
            for b in (a + 1)..10 {
                for c in (b + 1)..10 {
                    let want = format!("{}{}{}", a, b, c);
                    if !present.contains(want.as_str()) {
                        eprintln!("CHECK FAIL c00 print_comb is missing {}", want);
                        fails += 1;
                    }
                }
            }
        }
    }

    // (d) ex06, the same three ways.
    let comb2 = &streams[4];
    if *comb2 != naive_comb2() {
        eprintln!("CHECK FAIL c00 print_comb2 disagrees with the naive enumeration");
        fails += 1;
    }
    // 4950 items of 5 bytes + 4949 separators of 2 = 34648.
    if comb2.len() != 4950 * 5 + 4949 * COMB_SEP.len() {
        eprintln!("CHECK FAIL c00 print_comb2 is {} bytes, want 34648", comb2.len());
        fails += 1;
    }
    fails += check_comb_stream("print_comb2", comb2, 5, 4950, |item| {
        // "AA BB" with AA < BB, both zero-padded, exactly one space between.
        if item[2] != b' ' {
            return Err("no space between the two numbers".to_string());
        }
        if !(item[0].is_ascii_digit()
            && item[1].is_ascii_digit()
            && item[3].is_ascii_digit()
            && item[4].is_ascii_digit())
        {
            return Err("not all digits".to_string());
        }
        let lo = (item[0] - b'0') as usize * 10 + (item[1] - b'0') as usize;
        let hi = (item[3] - b'0') as usize * 10 + (item[4] - b'0') as usize;
        if lo >= hi {
            return Err(format!("{} is not strictly less than {}", lo, hi));
        }
        Ok(lo * 100 + hi)
    });
    // Capped, unlike ex05's: a reference that dropped whole rows of the
    // enumeration would report thousands of missing items and drown every other
    // module. ex05 has only 120 to report, so it is left uncapped there.
    {
        let s = String::from_utf8_lossy(comb2).to_string();
        let present: HashSet<&str> = s.split(", ").collect();
        let mut shown = 0usize;
        for a in 0..100u32 {
            for b in (a + 1)..100 {
                let want = format!("{:02} {:02}", a, b);
                if !present.contains(want.as_str()) {
                    fails += 1;
                    if shown < 5 {
                        eprintln!("CHECK FAIL c00 print_comb2 is missing {}", want);
                        shown += 1;
                    }
                }
            }
        }
    }

    // (e) The emit path adds nothing. Every property above inspects what
    // `zero_input_output` RETURNS; this runs what the binary actually writes,
    // into a Vec, and compares. It is the c-00 counterpart of c05.rs's count-line
    // assertion: cheap, currently trivial, and the only thing standing between a
    // one-word edit (`writeln!`, a stray '\n') and five arms that are one byte
    // away from their fixtures with a green check.
    //
    // What it does NOT cover is the syscall FRAMING — bytes are all a Vec can
    // show, so an output that left in 34 648 write() calls would read identically
    // here. Nothing in this crate can check that; it is a property of the process
    // and belongs to whoever measures the write() column (tools/ref_compare.sh).
    for (i, name) in names.iter().enumerate() {
        let mut buf: Vec<u8> = Vec::new();
        write_once(&mut buf, &streams[i]);
        if buf != streams[i] {
            eprintln!("CHECK FAIL c00 {} emit path altered its {} bytes", name, streams[i].len());
            fails += 1;
        }
        // No newline anywhere in any of the five. Asserted separately from the
        // byte-equality above because it is the thing a human is most likely to
        // "improve" in either direction, and none of these fixtures has one —
        // not even a final one.
        if streams[i].contains(&b'\n') {
            eprintln!("CHECK FAIL c00 {} contains a newline; no c-00 fixture has one", name);
            fails += 1;
        }
    }

    fails
}

/// Shared property check for the two ", "-separated enumerations.
///
/// Splits `stream` on the separator and holds every item to: the exact width
/// `width`, whatever `item_rank` says is well-formed, distinctness, and strictly
/// ascending order. `item_rank` returns a small integer identifying the item so
/// distinctness can be decided without knowing what an item MEANS — a trio of
/// digits and a pair of two-digit numbers rank differently but sort the same way.
///
/// Ordering is compared on the raw bytes, which is legitimate here and only here:
/// every item is the same width, and within a fixed width ASCII digit order and
/// numeric order agree (for ex06 the embedded ' ' is 0x20, below every digit, and
/// it sits at the same offset in every item, so it cannot reorder anything).
/// Strictly ascending also PROVES distinctness in the same comparison.
///
/// Reporting is capped at five messages per failure kind. A reference that lost
/// its separator entirely would otherwise report thousands of malformed items and
/// bury every other module's output; the failure COUNT still rises for each, so
/// the exit status is unaffected. Same reasoning, and same cap, as c05.rs.
fn check_comb_stream(
    what: &str,
    stream: &[u8],
    width: usize,
    want_items: usize,
    item_rank: impl Fn(&[u8]) -> Result<usize, String>,
) -> usize {
    let mut fails = 0usize;
    // A leading or trailing separator is invisible to a per-item test — the
    // split would just yield an empty item — so name it explicitly. The trailing
    // one is the classic bug in both of these exercises and it is exactly what
    // would put this reference one separator away from expected.txt.
    if stream.starts_with(COMB_SEP) {
        eprintln!("CHECK FAIL c00 {} starts with a separator", what);
        fails += 1;
    }
    if stream.ends_with(COMB_SEP) || stream.ends_with(b",") || stream.ends_with(b" ") {
        eprintln!("CHECK FAIL c00 {} ends with a separator or part of one", what);
        fails += 1;
    }
    let s = match std::str::from_utf8(stream) {
        Ok(s) => s,
        Err(e) => {
            // Everything these arms emit is ASCII by construction; a non-UTF-8
            // byte means a digit was computed with the wrong offset and landed
            // outside the printable range.
            eprintln!("CHECK FAIL c00 {} is not valid UTF-8: {}", what, e);
            return fails + 1;
        }
    };
    let items: Vec<&str> = s.split(", ").collect();
    if items.len() != want_items {
        eprintln!(
            "CHECK FAIL c00 {} has {} items, want {}",
            what,
            items.len(),
            want_items
        );
        fails += 1;
    }
    let mut ranks: Vec<usize> = Vec::with_capacity(items.len());
    let mut shown = 0usize;
    for (i, it) in items.iter().enumerate() {
        if it.len() != width {
            fails += 1;
            if shown < 5 {
                eprintln!("CHECK FAIL c00 {} item #{} is {:?}, want {} bytes", what, i, it, width);
                shown += 1;
            }
            continue;
        }
        match item_rank(it.as_bytes()) {
            Ok(r) => ranks.push(r),
            Err(why) => {
                fails += 1;
                if shown < 5 {
                    eprintln!("CHECK FAIL c00 {} item #{} {:?}: {}", what, i, it, why);
                    shown += 1;
                }
            }
        }
    }
    // Strictly ascending over the ranks: distinctness and the fixture's ordering
    // in one comparison, exactly as c05.rs pins its 724 boards.
    let mut shown = 0usize;
    for i in 1..ranks.len() {
        if ranks[i] <= ranks[i - 1] {
            fails += 1;
            if shown < 5 {
                eprintln!(
                    "CHECK FAIL c00 {} items #{} and #{} are out of order or equal",
                    what,
                    i - 1,
                    i
                );
                shown += 1;
            }
        }
    }
    fails
}

/// Replay a corpus and compute the reference answers; see common::bench_lines.
///
/// The five zero-input arms are the exception, exactly as `c05_ten_queens` is:
/// they read NOTHING from stdin (so they cannot block on an inherited terminal)
/// and they PRINT, where every corpus-replay arm below computes and discards.
/// Both departures are deliberate and both are argued at length in the
/// zero-input section above — points (2) and (3). Tidying either of them away
/// would not be a cleanup, it would put a thumb on the scale of the only layer
/// that consumes them.
pub fn bench(name: &str) -> bool {
    if let Some(bytes) = zero_input_output(name) {
        emit_once(&bytes);
        return true;
    }
    match name {
        "c00_is_negative" => for l in bench_lines() {
            if let Some(a) = l.split('\t').next().and_then(|x| x.parse::<i32>().ok()) { sink(o_is_negative(a)); }
        },
        "c00_putnbr" => for l in bench_lines() {
            if let Some(a) = l.split('\t').next().and_then(|x| x.parse::<i32>().ok()) { sink(o_putnbr(a)); }
        },
        _ => return false,
    }
    true
}
