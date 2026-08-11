//! c-05 scalar int -> int references (factorial, power, fibonacci, sqrt,
//! is_prime, find_next_prime). Every case line is:
//!     <decimal-int-inputs...>\t<reference-output>
//! Inputs are BOUNDED so a correct signed-int implementation never overflows:
//!   factorial: 0..=12 (13! overflows) plus negatives (-> 0)
//!   power:     nb/power chosen so nb^power fits i32; power<0 -> 0
//!   fibonacci: 0..=46 (fib(47) overflows) plus negatives (-> -1)
//!   sqrt:      full i32 range; perfect square -> root, else 0; negative -> 0
//!   is_prime / find_next_prime: full range; INT_MAX (2147483647) is prime, so
//!              find_next_prime always terminates.
//!
//! ex08 (ten_queens) breaks that shape completely and is documented where it is
//! implemented, below the scalar oracles.

use crate::common::{bench_lines, sink, Rng};
use std::io::{self, Write};

// ------------------------------------------------------------- oracles

/// n! for n in 0..=12 (fits i32); negative -> 0 per the error convention.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_factorial(nb: i32) -> i32 {
    if nb < 0 {
        return 0;
    }
    let mut r: i64 = 1;
    let mut i: i64 = 2;
    while i <= nb as i64 {
        r *= i;
        i += 1;
    }
    r as i32
}

/// nb^power; power<0 -> 0. Caller guarantees the result fits i32.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_power(nb: i32, power: i32) -> i32 {
    if power < 0 {
        return 0;
    }
    let mut r: i64 = 1;
    let mut k: i32 = 0;
    while k < power {
        r *= nb as i64;
        k += 1;
    }
    r as i32
}

/// fib(0)=0, fib(1)=1, fib(n)=fib(n-1)+fib(n-2); negative index -> -1.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_fibonacci(index: i32) -> i32 {
    if index < 0 {
        return -1;
    }
    if index == 0 {
        return 0;
    }
    let mut a: i64 = 0;
    let mut b: i64 = 1;
    let mut i: i32 = 1;
    while i < index {
        let c = a + b;
        a = b;
        b = c;
        i += 1;
    }
    b as i32
}

/// Integer sqrt only when nb is a perfect square, else 0; negative -> 0.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_sqrt(nb: i32) -> i32 {
    if nb < 0 {
        return 0;
    }
    let n = nb as i64;
    // start near the true root, then snap to floor(sqrt(n)) exactly.
    let mut r = (n as f64).sqrt() as i64;
    while r > 0 && r * r > n {
        r -= 1;
    }
    while (r + 1) * (r + 1) <= n {
        r += 1;
    }
    if r * r == n {
        r as i32
    } else {
        0
    }
}

/// 1 if nb is prime, else 0. nb < 2 -> 0 (covers 0,1, all negatives, INT_MIN).
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_is_prime(nb: i32) -> i32 {
    if nb < 2 {
        return 0;
    }
    let n = nb as i64;
    if n % 2 == 0 {
        return (n == 2) as i32;
    }
    if n % 3 == 0 {
        return (n == 3) as i32;
    }
    let mut i: i64 = 5;
    while i * i <= n {
        if n % i == 0 || n % (i + 2) == 0 {
            return 0;
        }
        i += 6;
    }
    1
}

/// Smallest prime >= nb (nb<2 -> 2). INT_MAX is prime, so this terminates.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_find_next_prime(nb: i32) -> i32 {
    let mut c: i32 = if nb < 2 { 2 } else { nb };
    while o_is_prime(c) == 0 {
        c += 1;
    }
    c
}

// ------------------------------------------------- work counts (cycles layer)
//
// WHY THESE EXIST. tools/cycles_check.sh divides an instruction count by a unit
// of work taken straight off the corpus, so the per-unit figure means something
// a student can reason about ("a byte scan is a load, a compare and an
// increment"). For every other module that unit is derivable from the input --
// c-09 uses length($1)/2. For the arithmetic family it is NOT: the work in
// ft_sqrt or ft_is_prime is a function of the VALUE, through a loop bound
// nothing in the corpus records. c-05 therefore lost its cycles layer rather
// than report a figure per CASE, which mixed sqrt(4) and sqrt(2147395600) into
// one average and produced numbers like "1419 instructions per division".
//
// So the unit is MEASURED instead of modelled: each function below returns the
// iteration count its reference actually performed, and the generators emit it
// as a third corpus column that unit_expr reads as $3.
//
// THE RISK, AND WHAT GUARDS IT. A counting copy of an algorithm can drift from
// the algorithm. Every one of these therefore returns the ANSWER as well as the
// count, and check() below asserts the answer equals the reference's for the
// same input -- so a divergence is a self-check failure rather than a quietly
// wrong unit. They are separate functions rather than a counter threaded
// through the references because the references are also what the diff layer
// runs, and neither their instruction counts nor their output may move.
//
// WHAT COUNTS AS ONE ITERATION is stated per function, because the number is
// meaningless otherwise -- it is the denominator a student divides by.

/// (answer, candidate roots examined) for o_sqrt.
///
/// THE ONE PLACE THE UNIT IS NOT THE REFERENCE'S OWN LOOP COUNT, and the reason
/// is measured rather than argued. o_sqrt seeds from `(n as f64).sqrt()` and
/// then corrects; on this corpus the f64 lands exactly every time, so BOTH
/// correction loops run zero times -- 0 units over all 3000 cases, which as a
/// denominator is not a small number, it is no number at all.
///
/// That is not a defect in o_sqrt: a generator may take any shortcut it likes
/// to produce answers quickly. It just means the reference does not do the work
/// the exercise is about. c-05 forbids every function, so a student has no
/// sqrt() to call and must bracket the root with integer arithmetic.
///
/// So the unit here is floor(sqrt(n)): the number of candidate roots lying
/// between 1 and the answer, which is what an ascending integer scan examines
/// and the count a binary search is measured AGAINST. It is a property of the
/// input, not of any one algorithm, and it is exact rather than estimated --
/// the closed form of the loop count, not a model of it. A student whose scan
/// descends, or bisects, is compared against the same honest denominator.
fn o_sqrt_work(nb: i32) -> (i32, u64) {
    if nb < 0 {
        return (0, 0);
    }
    let n = nb as i64;
    // The same bracketing o_sqrt does, kept because floor(sqrt) has to be exact
    // here: an f64 that landed one low would understate the unit for that case.
    let mut r = (n as f64).sqrt() as i64;
    while r > 0 && r * r > n {
        r -= 1;
    }
    while (r + 1) * (r + 1) <= n {
        r += 1;
    }
    let ans = if r * r == n { r as i32 } else { 0 };
    (ans, r as u64)
}

/// (answer, iterations) for o_is_prime. One iteration is one turn of the 6k+/-1
/// wheel, i.e. one pair of trial divisions. The two constant-time divisibility
/// tests before the loop are not iterations and are not counted; a zero here
/// means the answer was decided without looping, which is the honest figure.
fn o_is_prime_work(nb: i32) -> (i32, u64) {
    if nb < 2 {
        return (0, 0);
    }
    let n = nb as i64;
    if n % 2 == 0 {
        return ((n == 2) as i32, 0);
    }
    if n % 3 == 0 {
        return ((n == 3) as i32, 0);
    }
    let mut iters: u64 = 0;
    let mut i: i64 = 5;
    while i * i <= n {
        iters += 1;
        if n % i == 0 || n % (i + 2) == 0 {
            return (0, iters);
        }
        i += 6;
    }
    (1, iters)
}

/// (answer, iterations) for o_find_next_prime. The unit is the wheel turn
/// again, summed over every candidate tested -- NOT the number of candidates.
/// That is the whole point: "how many numbers did it try" hides the fact that
/// testing a large candidate costs far more than testing a small one, which is
/// exactly the cost this exercise is about.
fn o_find_next_prime_work(nb: i32) -> (i32, u64) {
    let mut c: i32 = if nb < 2 { 2 } else { nb };
    let mut iters: u64 = 0;
    loop {
        let (is_p, k) = o_is_prime_work(c);
        iters += k;
        if is_p == 1 {
            return (c, iters);
        }
        c += 1;
    }
}

// --------------------------------------------------- ten queens (ex08)
//
// ex08 is the odd one out in this module, and in the crate. `int
// ft_ten_queens_puzzle(void)` takes NO input: it prints the 724 solutions of
// the ten-queens puzzle and returns 724. There is nothing to seed, nothing to
// fuzz and nothing to vary, so ex08 has no differential layer and correctly
// should not have one — its curated fixture is already exhaustive.
//
// What it has instead is an INFORMATIVE cost comparison (tools/ref_compare.sh):
// the student's instructions-per-solution against this reference's. That single
// consumer explains two decisions below that would otherwise look arbitrary.
//
// (1) This search is deliberately OPTIMISED, not merely correct. A reference
//     that mirrored the first approach anyone writes would report a ratio near
//     1.0 and say nothing at all. The gap IS the message: the same output, and
//     — for a student who prunes the same way, which is the common case — the
//     same search tree, yet still a large multiple of the work. Measured here
//     against an equivalent naive search in this same language, with the same
//     output and the same write() framing: 19.7M instructions against 2.5M,
//     just under 8x. That is the honesty check on the whole layer, because it
//     puts the naive Rust figure within a few percent of a student's C one and
//     so shows the gap is algorithmic rather than Rust-versus-C. Both numbers
//     will drift with the toolchain; do not hardcode either anywhere.
//
//     Whatever it says, it is a clue meant to make a student curious and never
//     a verdict: ref_compare.sh cannot fail on it.
//
// (2) Both `gen` and `bench` PRINT all 724 boards, unlike every other bench arm
//     in this crate, which computes the answer and discards it (see `bench`
//     below for why silence is the right call there). Here printing is not
//     noise to be excluded: the student's function has to print too, so a
//     silent reference would leave every digit formatted and every write()
//     issued out of its own count while the student still paid for them, and
//     the ratio would be inflated by work the student cannot avoid.
//
//     Both sides necessarily emit the same 7968 bytes. This side emits them in
//     725 write() calls, one per line, and against a student who frames their
//     output the same way that leaves the search as the only thing the ratio is
//     measuring. Do NOT write that down as a given: a student printing one
//     character at a time makes thousands of calls instead, and then part of
//     the gap is I/O rather than search. ref_compare.sh measures both counts
//     and claims less when they differ, which is the correct division of
//     labour — this file's job is only to pay for the same output.

/// Board width. Fixed by the subject: ten queens on a 10x10 board.
const QUEENS: usize = 10;

/// The ten low bits — every candidate position on one level of the search.
const QUEENS_FULL: u32 = (1 << QUEENS) - 1;

/// One level of the search: choose the position for index `i`, then recurse.
///
/// `cols`, `d1` and `d2` are the positions the `i` queens placed so far already
/// attack, expressed as bit sets over the ten candidates of THIS level: `cols`
/// does not move between levels, `d1` shifts one place left per level and `d2`
/// one place right, because a diagonal advances by exactly one position per
/// level in either direction. Their union is therefore the forbidden set for
/// level `i` as it stands, with nothing left to compute — testing a candidate
/// is one AND, and nothing has to be undone on the way back up because each
/// call recurses with its own copies rather than mutating shared state.
///
/// Candidates are consumed lowest bit first, so position 0 is tried before
/// position 1 at every level and the 724 boards leave in ascending
/// lexicographic order. That is not incidental: it is the order the ex08
/// fixture is in, and it falls out of the traversal rather than out of a sort.
fn queens_step<W: Write>(
    i: usize,
    cols: u32,
    d1: u32,
    d2: u32,
    board: &mut [u8; QUEENS],
    w: &mut W,
    found: &mut usize,
) {
    if i == QUEENS {
        // Ten digits plus '\n' in ONE write_all. The framing matters: stdout is
        // line-buffered in Rust, so one call per completed line is one write()
        // syscall per line — the parity with the student's binary that point
        // (2) at the top of this section depends on.
        let mut line = [b'\n'; QUEENS + 1];
        let mut k = 0usize;
        while k < QUEENS {
            line[k] = b'0' + board[k];
            k += 1;
        }
        let _ = w.write_all(&line);
        *found += 1;
        return;
    }
    let mut free = QUEENS_FULL & !(cols | d1 | d2);
    while free != 0 {
        let bit = free & free.wrapping_neg(); // lowest remaining candidate
        free ^= bit;
        board[i] = bit.trailing_zeros() as u8;
        queens_step(
            i + 1,
            cols | bit,
            ((d1 | bit) << 1) & QUEENS_FULL,
            (d2 | bit) >> 1,
            board,
            w,
            found,
        );
    }
}

/// The ten-queens reference: writes all 724 boards to `w`, returns 724.
///
/// Generic over the writer so the self-check can run the very same code into a
/// `Vec<u8>` and inspect what was actually PRINTED — digits, framing and all —
/// rather than a private list the printing path could still disagree with.
#[inline(never)] // keep this attributable under callgrind (see tools/)
fn o_ten_queens<W: Write>(w: &mut W) -> usize {
    let mut board = [0u8; QUEENS];
    let mut found = 0usize;
    queens_step(0, 0, 0, 0, &mut board, w, &mut found);
    found
}

// ---------------------------------------------------------- generators

/// Largest exponent e (>=0) such that |nb|^e <= i32::MAX. For |nb| in {0,1}
/// every power fits, so a large sentinel is returned.
fn max_pow(nb: i32) -> i32 {
    let a = (nb as i64).unsigned_abs();
    if a <= 1 {
        return 1_000_000;
    }
    let mut e: i32 = 0;
    let mut r: i128 = 1;
    let cap = i32::MAX as i128;
    loop {
        r *= a as i128;
        if r > cap {
            return e;
        }
        e += 1;
    }
}

fn factorial_inputs(rng: &mut Rng, count: usize) -> Vec<i32> {
    let mut v: Vec<i32> = Vec::new();
    for n in 0..=12 {
        v.push(n);
    }
    for &n in &[-1, -5, -12, -100, -123456, i32::MIN, i32::MIN + 1] {
        v.push(n);
    }
    while v.len() < count {
        match rng.below(4) {
            0 => v.push(rng.below(13) as i32), // 0..=12
            1 => v.push(-(1 + rng.below(2_000_000_000) as i32)),
            2 => v.push(i32::MIN),
            _ => v.push(rng.below(13) as i32),
        }
    }
    v.truncate(count);
    v
}

fn power_inputs(rng: &mut Rng, count: usize) -> Vec<(i32, i32)> {
    let mut v: Vec<(i32, i32)> = Vec::new();
    for &c in &[
        (2, 3),
        (7, 1),
        (0, 5),
        (5, 0),
        (0, 0),
        (1, 100),
        (10, 9),
        (2, 30),
        (-2, 2),
        (-2, 3),
        (-1, 100),
        (-1, 101),
        (2, -3),
        (7, -1),
        (5, i32::MIN),
        (0, -5),          // base 0, negative power -> 0 (error path, not 0^0)
        (3, 19),
        (-3, 19),
        (46340, 1),
        (-46340, 1),
        (-46340, 2),      // negative base, even power at the i32 bound (2147395600)
        (1, 0),           // base 1, power 0 -> 1
        (-1, 0),          // base -1, power 0 -> 1
        (i32::MAX, 0),    // huge base, power 0 -> 1 (base case must win)
        (i32::MIN, 0),    // huge negative base, power 0 -> 1
        (i32::MAX, 1),    // base^1 must return the base unchanged (INT_MAX)
        (i32::MIN, 1),    // base^1 must return the base unchanged (INT_MIN)
    ] {
        v.push(c);
    }
    while v.len() < count {
        // error branch: negative power -> result is 0 regardless of base.
        if rng.below(5) == 0 {
            let nb = rng.below(40) as i32 - 20;
            let p = -(1 + rng.below(2_000_000_000) as i32);
            v.push((nb, p));
            continue;
        }
        // valid branch: pick base, then a power that keeps the result in i32.
        let nb: i32 = match rng.below(6) {
            0 => 0,
            1 => 1,
            2 => -1,
            3 => rng.below(31) as i32 + 2,        // 2..=32
            4 => -((rng.below(31) as i32) + 2),   // -32..=-2
            _ => rng.below(41) as i32 - 20,       // -20..=20
        };
        let em = max_pow(nb);
        let hi = em.min(1000); // cap the sentinel case (nb in {0,1,-1})
        let p = rng.below((hi + 1) as usize) as i32;
        v.push((nb, p));
    }
    v.truncate(count);
    v
}

fn fibonacci_inputs(_rng: &mut Rng, _count: usize) -> Vec<i32> {
    // EXHAUSTIVE, and deliberately tiny. `count` is ignored.
    //
    // ft_fibonacci's interesting input space is finite and small: 0..=46, because
    // fib(47) = 2971215073 does not fit in an i32, plus a handful of negatives.
    // That is 53 values, and every one of them is here, so this corpus is not a
    // sample of the contract — it IS the contract.
    //
    // The old generator drew a 400 000-case corpus uniformly from 0..=46, which
    // replayed those same 53 answers about 7500 times each. That bought no
    // coverage at all, and it made the layer impossible to pass for the
    // implementation the module is teaching: c-05 is the recursion module and
    // ex04 sits between ft_recursive_factorial and ft_sqrt, so the expected
    // answer is the naive two-call recursion, whose cost is phi^n. Measured on
    // this machine at -O2: fib(46) alone is 9.0s, and the ~4300 cases the old
    // corpus placed at index 46 came to an estimated 28 HOURS against a 60s
    // budget. A correct, subject-shaped answer could not pass — which is a bug
    // in the test, not in the answer.
    //
    // Exhaustive 0..=46 costs 27.3s natively and 33.0s under the sanitizers,
    // both measured, which is why ex04's diff arms are sized "medium" rather
    // than "small". The top three indices are two thirds of that; everything
    // below 40 is together under a second.
    let mut v: Vec<i32> = Vec::new();
    for n in 0..=46 {
        v.push(n);
    }
    // Negatives and the far edge. The subject fixes no behaviour above 46, so
    // these check only that the guard fires and nothing overflows or hangs.
    for &n in &[-1, -5, -46, -100, i32::MIN, i32::MIN + 1] {
        v.push(n);
    }
    v
}

fn sqrt_inputs(rng: &mut Rng, count: usize) -> Vec<i32> {
    let mut v: Vec<i32> = Vec::new();
    for &n in &[
        0,
        1,
        4,
        9,
        16,
        25,
        100,
        144,
        2,
        3,
        12,
        26,
        -4,
        i32::MIN,
        2147395600, // 46340^2, the largest perfect square in i32
        2147395599,
        2147395601,
        i32::MAX,
    ] {
        v.push(n);
    }
    const MAXROOT: i64 = 46340;
    while v.len() < count {
        match rng.below(5) {
            0 => {
                // exact perfect square
                let r = rng.below((MAXROOT + 1) as usize) as i64;
                v.push((r * r) as i32);
            }
            1 => {
                // one off a perfect square (usually not a square)
                let r = 1 + rng.below(MAXROOT as usize) as i64;
                let d = if rng.below(2) == 0 { 1 } else { -1 };
                v.push((r * r + d) as i32);
            }
            2 => v.push(rng.below(2_147_483_648) as i32), // any 0..=INT_MAX
            3 => v.push(-(rng.below(2_147_483_648) as i32)), // negatives
            _ => v.push(rng.below(10_000) as i32),        // dense small band
        }
    }
    v.truncate(count);
    v
}

fn is_prime_inputs(rng: &mut Rng, count: usize) -> Vec<i32> {
    let mut v: Vec<i32> = Vec::new();
    for n in -3..=300 {
        v.push(n);
    }
    for &n in &[
        i32::MIN,
        -97,
        1000000007,
        1000000008,
        1000000005,
        999999937,
        999999939,
        2147483647, // INT_MAX, prime
        2147483646,
        2147483629, // prime
        2147483645,
    ] {
        v.push(n);
    }
    while v.len() < count {
        match rng.below(10) {
            0 => v.push(rng.below(2_147_483_648) as i32), // ~10% full-range
            1 => v.push(-(rng.below(2_000_000) as i32)),
            2 => v.push(rng.below(1000) as i32),
            _ => v.push(rng.below(2_000_000) as i32), // bulk small-ish
        }
    }
    v.truncate(count);
    v
}

fn find_next_prime_inputs(rng: &mut Rng, count: usize) -> Vec<i32> {
    let mut v: Vec<i32> = Vec::new();
    for n in -3..=200 {
        v.push(n);
    }
    for &n in &[
        i32::MIN,
        -5,
        0,
        1,
        999999937, // prime
        999999930,
        1000000007, // prime
        1000000000,
        2147483647, // INT_MAX, prime
        2147483629, // prime
        2147483620,
    ] {
        v.push(n);
    }
    while v.len() < count {
        match rng.below(20) {
            0 => v.push(2_100_000_000 + rng.below(47_483_648) as i32), // rare near-MAX
            1 => v.push(-(rng.below(2_000_000) as i32)),
            2 => v.push(rng.below(1000) as i32),
            _ => v.push(rng.below(1_000_000) as i32), // bulk: cheap to scan
        }
    }
    v.truncate(count);
    v
}

fn gen_factorial(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = factorial_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for nb in &inputs {
        let _ = writeln!(w, "{}\t{}", nb, o_factorial(*nb));
    }
}

fn gen_power(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = power_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for (nb, p) in &inputs {
        let _ = writeln!(w, "{}\t{}\t{}", nb, p, o_power(*nb, *p));
    }
}

fn gen_fibonacci(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = fibonacci_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for idx in &inputs {
        let _ = writeln!(w, "{}\t{}", idx, o_fibonacci(*idx));
    }
}

fn gen_sqrt(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = sqrt_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for nb in &inputs {
        let _ = writeln!(w, "{}\t{}", nb, o_sqrt(*nb));
    }
}

fn gen_is_prime(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = is_prime_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for nb in &inputs {
        let _ = writeln!(w, "{}\t{}", nb, o_is_prime(*nb));
    }
}

fn gen_find_next_prime(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = find_next_prime_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for nb in &inputs {
        let _ = writeln!(w, "{}\t{}", nb, o_find_next_prime(*nb));
    }
}

// The cycles-layer corpora: the same inputs as the diff corpora above, with the
// measured iteration count as a third column. SEPARATE generators, so the diff
// corpora stay byte-identical -- adding a column to those would have meant
// touching all eight c-05 diff harnesses and every expected.txt in one commit,
// for a layer that never gates. The harness that reads these takes field 0 and
// ignores the rest, so one corpus shape serves both.
fn gen_sqrt_cycles(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = sqrt_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for nb in &inputs {
        let (ans, iters) = o_sqrt_work(*nb);
        let _ = writeln!(w, "{}\t{}\t{}", nb, ans, iters);
    }
}

fn gen_is_prime_cycles(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = is_prime_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for nb in &inputs {
        let (ans, iters) = o_is_prime_work(*nb);
        let _ = writeln!(w, "{}\t{}\t{}", nb, ans, iters);
    }
}

fn gen_find_next_prime_cycles(seed: u64, count: usize) {
    let mut rng = Rng::new(seed);
    let inputs = find_next_prime_inputs(&mut rng, count);
    let mut w = io::BufWriter::new(io::stdout());
    for nb in &inputs {
        let (ans, iters) = o_find_next_prime_work(*nb);
        let _ = writeln!(w, "{}\t{}\t{}", nb, ans, iters);
    }
}

/// `oracle c05_ten_queens <seed> <count>` — seed and count are IGNORED — and
/// `oracle bench c05_ten_queens`, which runs exactly this same function. (The
/// binary has no `gen` subcommand: generating is the default, unprefixed form.)
/// The bench arm reads nothing from stdin, so it cannot block when it is handed
/// a terminal rather than a corpus.
///
/// Every other generator here writes a CORPUS: a list of inputs, each with the
/// reference answer beside it. ft_ten_queens_puzzle has no inputs at all, so a
/// zero-input function's corpus IS its answer — there is one case, it is this
/// one, and varying the seed or the count could only produce the same bytes
/// again. What this prints is therefore the complete expected output of ex08:
/// 724 board lines of ten digits, ascending lexicographically, then the count
/// line "724". It is byte-identical to c-piscine-c-05/tests/ex08/expected.txt,
/// which is worth stating plainly because it gives that curated fixture a
/// provenance it otherwise lacks — an independently written search reproduces
/// it exactly. (`check()` below re-derives the whole stream from properties
/// rather than from a stored copy; see there for exactly how much that pins and
/// what it still cannot notice.)
///
/// Generic over the writer for the same reason `o_ten_queens` is: the self-check
/// runs THIS function, count line and all, into a `Vec<u8>`. The tail below is
/// the one part of the 7968 bytes no board-level property can see, so it has to
/// be reachable from the check, not walled off behind `io::stdout()`.
fn emit_ten_queens<W: Write>(w: &mut W) -> usize {
    let n = o_ten_queens(w);
    // Pre-formatted into ONE write_all so the count leaves as one write() like
    // the 724 lines before it, and so that that is OUR doing rather than std's.
    // `writeln!(w, "{}", n)` hands the line buffer "724" and "\n" as two
    // separate fragments; measured, it still comes out as 725 syscalls today,
    // because BufWriter coalesces the two before the newline triggers its flush
    // — so this is not fixing an observed extra syscall, and do not repeat the
    // claim that it is. It is that the 725-write parity with the student's
    // binary is load-bearing for the cost comparison, and leaning on a
    // coalescing detail of std's line buffering to hold it up is a strange
    // thing to do when one write_all states it outright.
    let tail = format!("{}\n", n);
    let _ = w.write_all(tail.as_bytes());
    n
}

fn gen_ten_queens() {
    let mut out = io::stdout().lock();
    emit_ten_queens(&mut out);
}

/// Dispatch: returns true if `name` belongs to this module.
pub fn gen(name: &str, seed: u64, count: usize) -> bool {
    match name {
        "c05_iter_factorial" | "c05_rec_factorial" => gen_factorial(seed, count),
        "c05_iter_power" | "c05_rec_power" => gen_power(seed, count),
        "c05_fibonacci" => gen_fibonacci(seed, count),
        "c05_sqrt" => gen_sqrt(seed, count),
        "c05_is_prime" => gen_is_prime(seed, count),
        "c05_find_next_prime" => gen_find_next_prime(seed, count),
        "c05_sqrt_cycles" => gen_sqrt_cycles(seed, count),
        "c05_is_prime_cycles" => gen_is_prime_cycles(seed, count),
        "c05_find_next_prime_cycles" => gen_find_next_prime_cycles(seed, count),
        "c05_ten_queens" => gen_ten_queens(),
        _ => return false,
    }
    true
}

// ------------------------------------------------------------- self-check

// Independent trial-division primality (divisors 2..n-1) for cross-checking
// o_is_prime on small n without sharing its 6k+/-1 wheel logic.
fn naive_prime(n: i64) -> bool {
    if n < 2 {
        return false;
    }
    let mut d = 2i64;
    while d < n {
        if n % d == 0 {
            return false;
        }
        d += 1;
    }
    true
}

/// Deliberately naive ten-queens search, for cross-checking o_ten_queens.
///
/// It keeps the queens placed so far in a plain array and RESCANS that array
/// for every candidate — the obvious formulation, sharing none of the bit-set
/// arithmetic (no masks, no shifts, no lowest-bit trick). That is the whole
/// point: a shift in the wrong direction or an off-by-one in the diagonal
/// bookkeeping would have to be reproduced here by coincidence to slip through.
/// It is also the baseline the cost layer's ratio is implicitly about, so it is
/// useful to have it standing next to the fast one.
fn naive_queens(i: usize, board: &mut [u8; QUEENS], out: &mut Vec<[u8; QUEENS]>) {
    if i == QUEENS {
        out.push(*board);
        return;
    }
    for v in 0..QUEENS as u8 {
        let mut ok = true;
        let mut k = 0usize;
        while k < i {
            let dv = board[k] as i32 - v as i32;
            let dk = (i - k) as i32;
            if dv == 0 || dv == dk || dv == -dk {
                ok = false;
                break;
            }
            k += 1;
        }
        if ok {
            board[i] = v;
            naive_queens(i + 1, board, out);
        }
    }
}

/// First pair of queens on `b` that attack each other, if any: same line (equal
/// digits) or same diagonal (digit distance equal to position distance).
fn queens_conflict(b: &[u8; QUEENS]) -> Option<(usize, usize)> {
    let mut a = 0usize;
    while a < QUEENS {
        let mut c = a + 1;
        while c < QUEENS {
            let dv = b[a] as i32 - b[c] as i32;
            let dc = (c - a) as i32;
            if dv == 0 || dv == dc || dv == -dc {
                return Some((a, c));
            }
            c += 1;
        }
        a += 1;
    }
    None
}

/// Self-check: hand-verified cases + properties. Returns the failure count.
pub fn check() -> usize {
    let mut fails = 0usize;

    // ---- factorial: curated expected.txt values + recurrence + error path.
    let fac: &[(i32, i32)] = &[
        (0, 1),
        (1, 1),
        (2, 2),
        (3, 6),
        (4, 24),
        (5, 120),
        (10, 3628800),
        (12, 479001600),
        (-1, 0),
        (-5, 0),
        (i32::MIN, 0),
    ];
    for (n, want) in fac {
        if o_factorial(*n) != *want {
            eprintln!("CHECK FAIL c05 factorial({})", n);
            fails += 1;
        }
    }
    for n in 1..=12 {
        if o_factorial(n) != n * o_factorial(n - 1) {
            eprintln!("CHECK FAIL c05 factorial recurrence at {}", n);
            fails += 1;
        }
    }

    // ---- power: curated values + recurrence + negative-exponent path.
    let pw: &[(i32, i32, i32)] = &[
        (2, 3, 8),
        (7, 1, 7),
        (0, 5, 0),
        (5, 0, 1),
        (0, 0, 1),
        (1, 100, 1),
        (10, 9, 1000000000),
        (2, 30, 1073741824),
        (-2, 2, 4),
        (-2, 3, -8),
        (2, -3, 0),
        (5, i32::MIN, 0),
        (0, -5, 0),
        (-1, 100, 1),
        (-1, 101, -1),
        (-46340, 2, 2147395600),
        (1, 0, 1),
        (-1, 0, 1),
        (i32::MAX, 0, 1),
        (i32::MIN, 0, 1),
        (i32::MAX, 1, i32::MAX),
        (i32::MIN, 1, i32::MIN),
    ];
    for (nb, p, want) in pw {
        if o_power(*nb, *p) != *want {
            eprintln!("CHECK FAIL c05 power({},{})", nb, p);
            fails += 1;
        }
    }
    for &nb in &[-3i32, -2, -1, 0, 1, 2, 3, 7] {
        if o_power(nb, 0) != 1 {
            eprintln!("CHECK FAIL c05 power base case {}", nb);
            fails += 1;
        }
        for p in 1..=6 {
            if nb != 0 && o_power(nb, p) != nb * o_power(nb, p - 1) {
                eprintln!("CHECK FAIL c05 power recurrence {}^{}", nb, p);
                fails += 1;
            }
        }
        if o_power(nb, -1) != 0 || o_power(nb, i32::MIN) != 0 {
            eprintln!("CHECK FAIL c05 power neg-exp {}", nb);
            fails += 1;
        }
    }

    // ---- fibonacci: curated values + recurrence + error path.
    let fib: &[(i32, i32)] = &[
        (0, 0),
        (1, 1),
        (2, 1),
        (3, 2),
        (4, 3),
        (5, 5),
        (6, 8),
        (7, 13),
        (10, 55),
        (20, 6765),
        (30, 832040),
        (46, 1836311903),
        (-1, -1),
        (-5, -1),
        (i32::MIN, -1),
    ];
    for (i, want) in fib {
        if o_fibonacci(*i) != *want {
            eprintln!("CHECK FAIL c05 fibonacci({})", i);
            fails += 1;
        }
    }
    for i in 2..=46 {
        if o_fibonacci(i) != o_fibonacci(i - 1) + o_fibonacci(i - 2) {
            eprintln!("CHECK FAIL c05 fibonacci recurrence at {}", i);
            fails += 1;
        }
    }

    // ---- sqrt: curated + perfect-square property + off-by-one non-squares.
    let sq: &[(i32, i32)] = &[
        (0, 0),
        (1, 1),
        (4, 2),
        (9, 3),
        (144, 12),
        (2, 0),
        (26, 0),
        (-4, 0),
        (i32::MIN, 0),
        (2147395600, 46340),
        (2147395599, 0),
        (2147395601, 0),
        (i32::MAX, 0),
    ];
    for (n, want) in sq {
        if o_sqrt(*n) != *want {
            eprintln!("CHECK FAIL c05 sqrt({})", n);
            fails += 1;
        }
    }
    for r in 0i64..=46340 {
        let n = (r * r) as i32;
        if o_sqrt(n) != r as i32 {
            eprintln!("CHECK FAIL c05 sqrt perfect-square {}", r);
            fails += 1;
        }
        // r*r+1 is never a perfect square for r>=1 (it's below (r+1)^2).
        if r >= 1 && o_sqrt(n + 1) != 0 {
            eprintln!("CHECK FAIL c05 sqrt non-square {}", (n as i64) + 1);
            fails += 1;
        }
    }

    // ---- is_prime: agree with independent trial division over a dense band.
    for n in -5i64..=2000 {
        let want = naive_prime(n) as i32;
        if o_is_prime(n as i32) != want {
            eprintln!("CHECK FAIL c05 is_prime({}) vs naive", n);
            fails += 1;
        }
    }
    let known: &[(i32, i32)] = &[
        (2, 1),
        (3, 1),
        (11, 1),
        (17, 1),
        (97, 1),
        (0, 0),
        (1, 0),
        (4, 0),
        (25, 0),
        (49, 0),
        (1000000007, 1),
        (999999937, 1),
        (1000000008, 0),
        (2147483647, 1),
        (2147483646, 0),
        (2147483629, 1),
        (i32::MIN, 0),
        (-7, 0),
    ];
    for (n, want) in known {
        if o_is_prime(*n) != *want {
            eprintln!("CHECK FAIL c05 is_prime known({})", n);
            fails += 1;
        }
    }

    // ---- find_next_prime: result is prime, >= max(nb,2), and nothing between.
    let mut rng = Rng::new(99);
    let mut probes: Vec<i32> = (-5..=500).collect();
    for _ in 0..2000 {
        probes.push(rng.below(2_000_000) as i32);
    }
    probes.extend_from_slice(&[999999900, 1000000000, 2147483000, 2147483629]);
    for nb in probes {
        let r = o_find_next_prime(nb);
        let floor = if nb < 2 { 2 } else { nb };
        if r < floor || o_is_prime(r) != 1 {
            eprintln!("CHECK FAIL c05 next_prime({}) = {}", nb, r);
            fails += 1;
            continue;
        }
        let mut m = floor;
        while m < r {
            if o_is_prime(m) == 1 {
                eprintln!("CHECK FAIL c05 next_prime({}) skipped {}", nb, m);
                fails += 1;
                break;
            }
            m += 1;
        }
    }

    // ---- ten queens: the anti-bugged-oracle guard for the cost layer.
    //
    // This one carries more weight than the others. ex08 has no differential
    // test to contradict a wrong reference, and `gen c05_ten_queens` output is
    // the ex08 fixture itself — so a bug here would hand a correct student a
    // fabricated cost ratio, i.e. slander working code, with nothing else in
    // the suite in a position to notice. It is checked against what was
    // PRINTED, so the digit formatting and line framing are covered too.
    let mut buf: Vec<u8> = Vec::new();
    let n = o_ten_queens(&mut buf);
    if n != 724 {
        eprintln!("CHECK FAIL c05 ten_queens returned {}, want 724", n);
        fails += 1;
    }
    // Split on '\n'; the output ends with one, so the final piece is empty.
    let mut boards: Vec<[u8; QUEENS]> = Vec::new();
    let mut shown = 0usize; // see the capping note below
    for line in buf.split(|&b| b == b'\n') {
        if line.is_empty() {
            continue;
        }
        if line.len() != QUEENS || line.iter().any(|c| !c.is_ascii_digit()) {
            fails += 1;
            if shown < 5 {
                eprintln!(
                    "CHECK FAIL c05 ten_queens malformed line {:?}",
                    String::from_utf8_lossy(line)
                );
                shown += 1;
            }
            continue;
        }
        let mut b = [0u8; QUEENS];
        for (k, c) in line.iter().enumerate() {
            b[k] = c - b'0';
        }
        boards.push(b);
    }
    if boards.len() != 724 {
        eprintln!("CHECK FAIL c05 ten_queens printed {} boards, want 724", boards.len());
        fails += 1;
    }
    // Every board must be a legal position in its own right: two queens may
    // share neither a line (equal digits) nor a diagonal (digit distance equal
    // to position distance). Reporting is CAPPED, unlike the rest of this
    // module: the other checks sweep a bounded probe list, but a search with a
    // broken constraint set emits tens of thousands of boards (a wrong shift
    // direction measured 82 297 here), and one message per attacking pair would
    // bury every other module's output under millions of lines. The count still
    // rises for each one, so the exit status is unaffected.
    let mut shown = 0usize;
    for (idx, b) in boards.iter().enumerate() {
        if let Some((a, c)) = queens_conflict(b) {
            fails += 1;
            if shown < 5 {
                eprintln!(
                    "CHECK FAIL c05 ten_queens board #{} self-attacks at {} and {}",
                    idx, a, c
                );
                shown += 1;
            }
        }
    }
    // Strictly increasing proves DISTINCTNESS and pins the fixture's ordering
    // in one comparison: all lines are the same length and '0'..'9' is monotone
    // in ASCII, so comparing the digit arrays is comparing the printed lines.
    let mut i = 1usize;
    let mut shown = 0usize;
    while i < boards.len() {
        if boards[i] <= boards[i - 1] {
            fails += 1;
            if shown < 5 {
                eprintln!(
                    "CHECK FAIL c05 ten_queens boards #{} and #{} out of order or equal",
                    i - 1,
                    i
                );
                shown += 1;
            }
        }
        i += 1;
    }
    // Same solutions, same order, from a search that shares no logic with it.
    let mut nb = [0u8; QUEENS];
    let mut naive: Vec<[u8; QUEENS]> = Vec::new();
    naive_queens(0, &mut nb, &mut naive);
    if naive != boards {
        eprintln!(
            "CHECK FAIL c05 ten_queens disagrees with the naive search ({} vs {} boards)",
            boards.len(),
            naive.len()
        );
        fails += 1;
    }
    // And finally the COUNT LINE, which none of the above can see: it is written
    // by emit_ten_queens after the search returns, so every property checked so
    // far stays green if it loses its newline or gains a prefix. Measured, it
    // does: dropping the '\n' left `oracle check` reporting OK while the output
    // no longer matched expected.txt. That tail is 4 of the 7968 bytes the ex08
    // fixture is made of.
    //
    // What this does NOT cover is the syscall FRAMING — bytes are all a Vec can
    // show, so a tail that went out as two write() calls would read identically
    // here. Nothing in the crate can check that; it is a property of the process
    // and belongs to whoever measures the 725-write parity.
    //
    // Together with the properties above this closes the loop, and it is worth
    // spelling out why: a board that survives queens_conflict IS a ten-queens
    // solution, and there are exactly 724 of those, so "724 legal boards, all
    // distinct" cannot be satisfied by any set other than the complete one.
    // Add "strictly ascending" and the boards are in one fixed order; add this
    // line and the whole byte stream is fixed. A green check therefore pins
    // `oracle c05_ten_queens` to exactly one possible output — which is what
    // lets oracle/README.md say that a future divergence from expected.txt has
    // to be an edit to the fixture rather than a regression in here.
    let mut whole: Vec<u8> = Vec::new();
    emit_ten_queens(&mut whole);
    let mut want = buf.clone();
    want.extend_from_slice(b"724\n");
    if whole != want {
        eprintln!(
            "CHECK FAIL c05 ten_queens emitted {} bytes; want the boards then \"724\\n\" ({})",
            whole.len(),
            want.len()
        );
        fails += 1;
    }

    // ---- the work counters agree with the references they count.
    //
    // These feed the cycles layer's denominator, and a counting copy that had
    // drifted from the algorithm it counts would produce a per-unit figure that
    // is confidently wrong -- worse than none, because the whole point of the
    // number is that a student can reason about it. So each *_work is asserted
    // to return the SAME ANSWER as its reference, across the same shapes the
    // corpora draw from: the boundaries, a perfect square and its neighbours,
    // small primes and composites, and INT_MAX (prime, and the worst case for
    // find_next_prime).
    let work_probe: &[i32] = &[
        i32::MIN,
        -7,
        -1,
        0,
        1,
        2,
        3,
        4,
        5,
        8,
        9,
        10,
        24,
        25,
        26,
        49,
        97,
        100,
        101,
        7919,
        65535,
        65536,
        1000003,
        2147395600,
        i32::MAX - 1,
        i32::MAX,
    ];
    for n in work_probe {
        let (a, _) = o_sqrt_work(*n);
        if a != o_sqrt(*n) {
            eprintln!("CHECK FAIL c05 sqrt_work({}) = {}, o_sqrt = {}", n, a, o_sqrt(*n));
            fails += 1;
        }
        let (a, _) = o_is_prime_work(*n);
        if a != o_is_prime(*n) {
            eprintln!(
                "CHECK FAIL c05 is_prime_work({}) = {}, o_is_prime = {}",
                n,
                a,
                o_is_prime(*n)
            );
            fails += 1;
        }
        let (a, _) = o_find_next_prime_work(*n);
        if a != o_find_next_prime(*n) {
            eprintln!(
                "CHECK FAIL c05 next_prime_work({}) = {}, o_find_next_prime = {}",
                n,
                a,
                o_find_next_prime(*n)
            );
            fails += 1;
        }
    }
    // A count of zero for a value that demonstrably loops would make the whole
    // layer divide by nothing, so the counts are asserted to be non-trivial
    // where they must be. 2147395600 is 46340^2, the largest perfect square in
    // an int -- if the sqrt correction loop ever counted zero there, every
    // per-unit figure would be an accidental infinity.
    // floor(sqrt) is the sqrt unit, so it must track the input rather than the
    // ANSWER: a non-square still costs a scan, and returning 0 there (which is
    // what o_sqrt answers) would zero the denominator for 2368 of 3000 cases.
    if o_sqrt_work(2147395601).1 != 46340 || o_sqrt_work(26).1 != 5 {
        eprintln!("CHECK FAIL c05 sqrt_work counts the answer, not the candidates");
        fails += 1;
    }
    if o_is_prime_work(1000003).1 == 0 {
        eprintln!("CHECK FAIL c05 is_prime_work(1000003) counted no wheel turns");
        fails += 1;
    }
    if o_find_next_prime_work(1000000).1 == 0 {
        eprintln!("CHECK FAIL c05 next_prime_work(1000000) counted no wheel turns");
        fails += 1;
    }
    fails
}

/// Replay a corpus WITHOUT generating it: read the input fields from stdin,
/// compute the reference answer, discard it.
///
/// This is the baseline the perf layer measures the student against. It cannot
/// be `gen`: `oracle <fn> <seed> <count>` spends most of its time producing the
/// corpus (seeded RNG, hex encoding, formatting) rather than computing answers —
/// 94% of it for the heavier generators — so timing gen would measure the
/// generator, not the reference. Here the generation is already done and sitting
/// on stdin, so what is left is the work the student's function also has to do.
///
/// Nothing is printed. Printing is not part of the comparison, and for the
/// write()-per-character exercises it would dominate exactly the number we are
/// trying to read. `sink` exists only so the optimiser cannot delete the call.
///
/// Both paragraphs above describe the corpus-replay arms, which is all of them
/// bar one. `c05_ten_queens` reads no stdin and DOES print, deliberately: it
/// has no corpus, and its consumer is the cost comparison rather than the perf
/// layer, where the student's own printing is unavoidable work that a silent
/// reference would exclude from its own count while the student still paid for
/// it. See the ten-queens section above before tidying that arm into silence —
/// it would not be a cleanup, it would put a thumb on the scale. (The same
/// caveat applies to the blanket wording on `dispatch_bench` in main.rs.)
pub fn bench(name: &str) -> bool {
    let one = |f: fn(i32) -> i32| {
        let mut acc: i64 = 0;
        for line in bench_lines() {
            if let Some(a) = line.split('\t').next().and_then(|x| x.parse::<i32>().ok()) {
                acc = acc.wrapping_add(f(a) as i64);
            }
        }
        sink(acc);
    };
    let two = |f: fn(i32, i32) -> i32| {
        let mut acc: i64 = 0;
        for line in bench_lines() {
            let mut it = line.split('\t');
            let a = it.next().and_then(|x| x.parse::<i32>().ok());
            let b = it.next().and_then(|x| x.parse::<i32>().ok());
            if let (Some(a), Some(b)) = (a, b) {
                acc = acc.wrapping_add(f(a, b) as i64);
            }
        }
        sink(acc);
    };
    match name {
        "c05_iter_factorial" | "c05_rec_factorial" => one(o_factorial),
        "c05_iter_power" | "c05_rec_power" => two(o_power),
        "c05_fibonacci" => one(o_fibonacci),
        "c05_sqrt" => one(o_sqrt),
        "c05_is_prime" => one(o_is_prime),
        "c05_find_next_prime" => one(o_find_next_prime),
        // The one arm that prints, and the one arm that ignores stdin: ex08 has
        // no corpus to replay, and its consumer is the cost comparison rather
        // than the perf layer. See the ten-queens section above for why staying
        // silent here would make the comparison dishonest instead of cleaner.
        "c05_ten_queens" => gen_ten_queens(),
        _ => return false,
    }
    true
}
