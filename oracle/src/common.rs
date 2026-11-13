//! Shared primitives for the differential-test references.
//!
//! Determinism: a fixed seed drives SplitMix64, so every generator is
//! bit-reproducible across runs and hosts. No external crate, no wall-clock.

/// SplitMix64 — tiny deterministic PRNG.
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Rng(seed)
    }
    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    /// uniform in [0, n); n == 0 -> 0.
    pub fn below(&mut self, n: usize) -> usize {
        if n == 0 {
            0
        } else {
            (self.next_u64() % n as u64) as usize
        }
    }
    /// a signed 32-bit value biased toward small magnitudes and boundaries.
    pub fn i32val(&mut self) -> i32 {
        match self.below(8) {
            0 => 0,
            1 => i32::MIN,
            2 => i32::MAX,
            3 => -(self.below(1000) as i32),
            4 => self.below(1000) as i32,
            _ => self.next_u64() as i32,
        }
    }
    /// uniform in [lo, hi], both ends included: one below() draw. The span is
    /// taken in i64, so any pair of i32 bounds is safe.
    pub fn range_i32(&mut self, lo: i32, hi: i32) -> i32 {
        (lo as i64 + self.below((hi as i64 - lo as i64 + 1) as usize) as i64) as i32
    }
}

/// Lowercase-hex encode a byte slice.
pub fn to_hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    push_hex(&mut s, bytes);
    s
}

/// Append `bytes` as lowercase hex to an existing String.
///
/// The same characters `to_hex` produces, written straight into the caller's
/// buffer. Generators that hex-encode a LIST (join_hex, below, which c11, c12
/// and c13 run per element per case) were calling to_hex in a loop, which allocates a String
/// per element, copies it into the accumulator and drops it again. At 400k
/// cases with multi-node trees that is millions of pointless allocations, and
/// the oracle's generation cost is the dominant term in a diff test's wall
/// time — so this is the hot path worth removing, not a micro-optimisation.
///
/// Output is byte-identical to to_hex by construction: same digits, same order.
pub fn push_hex(s: &mut String, bytes: &[u8]) {
    s.reserve(bytes.len() * 2);
    for &b in bytes {
        s.push(char::from_digit((b >> 4) as u32, 16).unwrap());
        s.push(char::from_digit((b & 0xf) as u32, 16).unwrap());
    }
}

/// Comma-joined lowercase-hex of each byte-string (empty slice -> ""), the
/// list field a C reader decodes with diffio.h's dio_hex_list. Its inverse is
/// unhex_csv.
pub fn join_hex<T: AsRef<[u8]>>(seq: &[T]) -> String {
    // Hex straight into the accumulator. The previous version called to_hex per
    // element, which allocated a String, copied it in and dropped it — once per
    // tree node per case. Same bytes out; see push_hex.
    let mut s = String::with_capacity(seq.iter().map(|x| x.as_ref().len() * 2 + 1).sum());
    for (i, x) in seq.iter().enumerate() {
        if i != 0 {
            s.push(',');
        }
        push_hex(&mut s, x.as_ref());
    }
    s
}

/// The isspace(3) bytes of the C locale: "space, form-feed ('\f'), newline
/// ('\n'), carriage return ('\r'), horizontal tab ('\t'), and vertical tab
/// ('\v')". Every reference that skips white space (c04, c07, c11,
/// libft_str) reads this one set, and generators index it, so its order is
/// part of their corpora: keep it.
pub const ISSPACE: [u8; 6] = [b' ', b'\t', b'\n', 0x0b, 0x0c, b'\r'];

/// Whether `b` is one of ISSPACE's bytes.
pub fn is_space(b: u8) -> bool {
    ISSPACE.contains(&b)
}

/// A random C-string body: `len` bytes, NEVER 0x00 (that would terminate). When
/// `high` is set the full 0x01..=0xFF range is used (exercises signed char);
/// otherwise lowercase letters.
pub fn rand_body(rng: &mut Rng, len: usize, high: bool) -> Vec<u8> {
    rand_body_without(rng, len, high, 0)
}

/// rand_body that never holds `skip` either: a byte drawn as `skip` is drawn
/// again. With a `skip` neither branch can draw (0, which rand_body passes,
/// or b'\n' for the letters) no draw is repeated, so the stream is
/// rand_body's. c01 skips b'\n', which would split the corpus line its
/// harness replays.
pub fn rand_body_without(rng: &mut Rng, len: usize, high: bool, skip: u8) -> Vec<u8> {
    (0..len)
        .map(|_| loop {
            let b = if high { (1 + rng.below(255)) as u8 } else { (b'a' as usize + rng.below(26)) as u8 };
            if b != skip {
                return b;
            }
        })
        .collect()
}

/// Structured + boundary + seeded-random pairs of C-string bodies (no interior
/// NUL), for the comparator/search families. Structured shapes come first
/// (deterministic), then a random tail biased toward deep-shared-prefix pairs
/// (equal / one-byte-flipped / truncated), which actually exercise a comparator.
pub fn string_pairs(rng: &mut Rng, count: usize) -> Vec<(Vec<u8>, Vec<u8>)> {
    let mut out: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();

    out.push((vec![], vec![]));
    out.push((vec![], vec![b'a']));
    out.push((vec![b'a'], vec![]));
    out.push((vec![b'a'], vec![b'a']));
    out.push((vec![b'a'], vec![b'b']));
    for v in 1u16..=255 {
        out.push((vec![v as u8], vec![b'M']));
        out.push((vec![b'M'], vec![v as u8]));
    }
    for k in 0..8usize {
        let mut a = vec![b'x'; k];
        let mut b = a.clone();
        a.push(b'A');
        b.push(b'B');
        out.push((a, b));
        let base = vec![b'y'; k + 1];
        let mut longer = base.clone();
        longer.push(b'z');
        out.push((base, longer));
    }
    out.push((vec![b'A', 0x80], vec![b'A', 0x7f]));
    out.push((vec![0x80], vec![0x01]));
    out.push((vec![0xff], vec![b'a']));

    while out.len() < count {
        let mode = rng.below(4);
        let high = rng.below(2) == 1;
        let la = rng.below(33);
        let a = rand_body(rng, la, high);
        let b = if mode == 1 {
            a.clone()
        } else if mode == 2 && !a.is_empty() {
            let mut b = a.clone();
            let i = rng.below(b.len());
            b[i] = (1 + rng.below(255)) as u8;
            b
        } else if mode == 3 {
            let mut b = a.clone();
            let cut = rng.below(b.len() + 1);
            b.truncate(cut);
            b
        } else {
            let lb = rng.below(33);
            rand_body(rng, lb, high)
        };
        out.push((a, b));
    }
    // No truncation: count.max(len) is never below len, so this only ever
    // raised the corpus. A small --count therefore keeps the whole
    // structured head rather than cutting into it, which is the policy;
    // it used to be spelled as a call that could not do anything.
    out
}

/// A corpus's cases: the `head` in order, then `draw()` for as long as it
/// takes, until `count` of them are kept. A case `keep` refuses is skipped and
/// does not count, a head case as much as a drawn one, and a refused draw has
/// still consumed whatever its closure drew from the rng. It stops at `count`
/// kept, so a count below the head's length cuts the head short: that is the
/// count policy of every arm built on it (the corpus is a prefix of a longer
/// one), where string_pairs and int_cases(.., false) keep their heads whole.
pub fn head_then_drawn<T>(head: Vec<T>, count: usize, mut draw: impl FnMut() -> T, keep: impl Fn(&T) -> bool) -> Vec<T> {
    let mut out: Vec<T> = Vec::with_capacity(count.min(1 << 20));
    let mut head = head.into_iter();
    while out.len() < count {
        let x = head.next().unwrap_or_else(&mut draw);
        if keep(&x) {
            out.push(x);
        }
    }
    out
}

/// `cases` with `long` put in at `at` (the end of a structured head), cut
/// back to `count` cases or to the head and `long`, whichever is more: a
/// small --count keeps the capacity cases, a large one stays exact. The
/// count policy of c03's string corpora and c11's int arrays, where
/// head_then_drawn's cuts the head short.
pub fn with_long<T>(mut cases: Vec<T>, at: usize, long: Vec<T>, count: usize) -> Vec<T> {
    let keep = count.max(at + long.len());
    let tail = cases.split_off(at.min(cases.len()));
    cases.extend(long);
    cases.extend(tail);
    cases.truncate(keep);
    cases
}

// ------------------------------------------------------- the int corpus
//
// One corpus of ints, shared by the arms that turn an int into its decimal
// text, ft_putnbr's (C 00 ex07, and C 04 ex02, which replays it),
// ft_putnbr_fd's and ft_itoa's, and by ft_is_negative's (C 00 ex04,
// Reloaded ex08), which reads the same inputs.
// Libft's two had a head of their own, the same 20 hand-picked values, with
// no 4-digit number in it: a carry wrong only at 999 -> 1000 or at -10000
// was met in the random tail by chance, less than once in 600 000 draws
// (3/8 of i32val's draws are uniform over all 2^32 ints, and 18 000 of
// those have 4 digits).

/// The deterministic head: 0, +/-1 and both ends of int with their
/// neighbours; every value in -1000..=1000, so every text of one to three
/// digits of either sign; then every 10^k-1, 10^k and 10^k+1 that fits an
/// int, of both signs, where a digit carries into a new place. No seed
/// reaches it.
fn int_head() -> Vec<i32> {
    let mut out: Vec<i32> = vec![
        0,
        1,
        -1,
        i32::MAX,     // 2147483647
        i32::MIN,     // -2147483648
        i32::MAX - 1, // 2147483646
        i32::MIN + 1, // -2147483647
    ];
    out.extend(-1000i32..=1000);
    // Guarded through i64 so 10^9 and its neighbours never overflow i32.
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
    out
}

/// How many values the head holds: the count at which int_cases starts to
/// draw, and the least count whose corpus holds every corner int_corners_missing
/// asks for.
pub fn int_head_len() -> usize {
    int_head().len()
}

/// The int corpus: the head, then `rng.i32val()` draws (biased toward 0,
/// the ends of int and small values) until there are `count`.
///
/// `cut` is the count policy, and the two callers want different ones. With
/// it false the head is written whole, however small `count` is, so a count
/// of 1 is the head alone (C 00's arms). With it true the corpus is exactly
/// `count` values, the head cut short below its length, so every corpus is a
/// prefix of a longer one (Libft's arms, whose self-checks hold each corpus to
/// as many lines as asked). Either way the draws start after the whole head,
/// so a corpus past it is the same under both.
pub fn int_cases(rng: &mut Rng, count: usize, cut: bool) -> Vec<i32> {
    let mut out = int_head();
    while out.len() < count {
        out.push(rng.i32val());
    }
    if cut {
        out.truncate(count);
    }
    out
}

/// The corners an int corpus of at least int_head_len() values must hold,
/// which are missing from `cases`: 0, +/-1, i32::MIN and i32::MAX and their
/// neighbours, and every 10^k-1, 10^k and 10^k+1 (k = 0..9) of both signs.
/// Each module that writes an int corpus calls it in its check() on what its
/// generator wrote, so that a corpus that stops being int_cases, or a head
/// that loses a corner, turns `oracle check` red instead of leaving the case
/// to the random tail. Written apart from int_head, not derived from it.
pub fn int_corners_missing(cases: &[i32]) -> Vec<i32> {
    let mut want: Vec<i64> = vec![0, 1, -1, i32::MAX as i64, i32::MIN as i64, i32::MAX as i64 - 1, i32::MIN as i64 + 1];
    for k in 0..10u32 {
        let p = 10i64.pow(k);
        want.extend([p - 1, p, p + 1, 1 - p, -p, -p - 1]);
    }
    want.sort_unstable();
    want.dedup();
    want.into_iter()
        .filter(|&v| !cases.iter().any(|&c| c as i64 == v))
        .map(|v| v as i32)
        .collect()
}

// ------------------------------------------------------------- bench support
/// Every line of stdin. Used by `oracle bench <fn>`, which replays a corpus and
/// computes the reference answers WITHOUT generating or printing them — so the
/// perf layer can time the reference doing the same work the student does.
///
/// Split on b'\n' as bytes, never with lines(): a corpus field may hold raw
/// bytes (c01_putstr's string after the tab), and lines() ends the whole
/// iteration at the first line that is not UTF-8, so the bench replayed five
/// lines of that corpus and exited 0. Each line is decoded lossily, which no
/// arm can see: every arm parses only the hex and decimal fields, which come
/// before a raw one. Nor is a trailing '\r' stripped, as lines() would: no
/// generator ends its lines with "\r\n", and where a line does end in '\r'
/// it is c01_putstr's raw string, which no arm reads.
/// check_bench_stdin (main.rs) holds an arm to reading its stdin to the end.
pub fn bench_lines() -> impl Iterator<Item = String> {
    use std::io::BufRead;
    std::io::stdin()
        .lock()
        .split(b'\n')
        .map_while(Result::ok)
        .map(|v| String::from_utf8_lossy(&v).into_owned())
}

/// Decode a lowercase-hex field back to bytes (inverse of to_hex).
pub fn unhex(s: &str) -> Vec<u8> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len() / 2);
    let hv = |c: u8| -> u8 {
        match c {
            b'0'..=b'9' => c - b'0',
            b'a'..=b'f' => c - b'a' + 10,
            b'A'..=b'F' => c - b'A' + 10,
            _ => 0,
        }
    };
    let mut i = 0;
    while i + 1 < b.len() {
        out.push((hv(b[i]) << 4) | hv(b[i + 1]));
        i += 2;
    }
    out
}

/// Comma-separated hex fields -> a list of byte strings (empty field -> empty list).
pub fn unhex_csv(s: &str) -> Vec<Vec<u8>> {
    if s.is_empty() {
        return Vec::new();
    }
    s.split(',').map(unhex).collect()
}

/// Comma-separated decimal ints.
pub fn ints_csv(s: &str) -> Vec<i32> {
    if s.is_empty() {
        return Vec::new();
    }
    s.split(',').filter_map(|x| x.parse::<i32>().ok()).collect()
}

/// A list of ints as one comma-separated field. The inverse of `ints_csv`, and
/// it lives beside it: three modules (c01, c11, c12) each carried a
/// byte-identical private copy while the function it undoes was already here.
pub fn join_csv(v: &[i32]) -> String {
    let mut s = String::new();
    for (i, x) in v.iter().enumerate() {
        if i != 0 {
            s.push(',');
        }
        s.push_str(&x.to_string());
    }
    s
}

/// The corpus's not-found token: what a line holds for a pointer the function
/// returns, or a node or index it finds, when there is none. The C readers
/// print the same token for a NULL they get back and compare against it, and
/// so do the checks that read a corpus back, so it is spelled here only.
pub const NULL: &str = "NULL";

/// `o` rendered by `f`, or the not-found token `NULL` for none.
pub fn or_null_with<T>(o: Option<T>, f: impl FnOnce(T) -> String) -> String {
    match o {
        Some(x) => f(x),
        None => NULL.to_string(),
    }
}

/// A value as its text, or the not-found token `NULL` for none.
pub fn or_null<T: std::fmt::Display>(o: Option<T>) -> String {
    or_null_with(o, |x| x.to_string())
}

// ------------------------------------------------- one-line escape for /bin/sh
//
// A whole multi-line FILE carried on one corpus line, for the arms whose input
// or answer is a text file rather than a value. rush00.rs has an escape of its
// own and keeps it: its consumer is a C reader (tests/ex00/rush_capture.h) that
// decodes "\xHH", and moving that pair would mean changing both sides together
// for no gain.
//
// THIS ONE IS OCTAL, AND THAT IS THE WHOLE POINT. Its consumer is a shell
// runner calling `printf '%b'`, /bin/sh here is dash, and "\xHH" is a bashism:
//
//     dash -c "printf '%b' 'A\x42C'"   ->  A \ x 4 2 C     (six bytes, literal)
//     dash -c "printf '%b' 'A\0102C'"  ->  A B C
//
// Both measured on this box. A corpus that only decodes under bash would be a
// harness that grades correctly for whoever ran it and wrongly for everyone
// else, and it would do it silently -- the map would simply be different bytes.
//
// Three octal digits, always, because "\0NNN" ends after exactly three: the
// escape of '0' followed by a literal '5' is "\00605", which dash decodes as
// "05" rather than as one character. A two-digit form would be ambiguous
// wherever a digit follows, and a digit is a legal map character.
//
// NUL is never produced by the generators that use this, and must not be: the
// decoded bytes travel through a shell variable, which cannot hold one.

/// Escape a byte string onto one line: `\` -> `\\`, newline -> `\n`, tab ->
/// `\t`, printable ASCII raw, anything else -> `\0NNN` (three OCTAL digits).
pub fn esc_posix(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() + 8);
    for &b in bytes {
        match b {
            b'\\' => out.push_str("\\\\"),
            b'\n' => out.push_str("\\n"),
            b'\t' => out.push_str("\\t"),
            0x20..=0x7e => out.push(b as char),
            _ => out.push_str(&format!("\\0{:03o}", b)),
        }
    }
    out
}

/// Decode `esc_posix`. Self-check only -- the shell side uses `printf '%b'`,
/// and this exists so a round-trip assertion can prove the two agree.
pub fn unesc_posix(s: &str) -> Vec<u8> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] != b'\\' {
            out.push(b[i]);
            i += 1;
        } else if i + 1 < b.len() && b[i + 1] == b'\\' {
            out.push(b'\\');
            i += 2;
        } else if i + 1 < b.len() && b[i + 1] == b'n' {
            out.push(b'\n');
            i += 2;
        } else if i + 1 < b.len() && b[i + 1] == b't' {
            out.push(b'\t');
            i += 2;
        } else if i + 4 < b.len() + 1 && i + 1 < b.len() && b[i + 1] == b'0' {
            let oct = std::str::from_utf8(&b[i + 2..i + 5]).unwrap_or("000");
            out.push(u8::from_str_radix(oct, 8).unwrap_or(0));
            i += 5;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    out
}

// ------------------------------------------------------- shared oracle bodies
//
// Two references that more than one module needs, held once. c-09 is a libft
// rebuild, so its contracts genuinely repeat c-03's and c-07's -- but "the same
// contract" was being spelled as "a second copy of the function", and the
// copies were character-identical. The corpora they feed still differ per
// module (c07 and c09 emit ft_split's fields in a different order, each matched
// to its own reader); what is shared is the answer, not the record layout.
//
// #[inline(never)] is load-bearing and travels with them: it keeps each one
// attributable in a callgrind profile.

/// ft_strcmp: (unsigned char)a[k]-(unsigned char)b[k] at the first difference.
#[inline(never)] // keep this attributable under callgrind (see tools/)
pub fn o_strcmp(a: &[u8], b: &[u8]) -> i64 {
    let mut i = 0usize;
    loop {
        let av = *a.get(i).unwrap_or(&0);
        let bv = *b.get(i).unwrap_or(&0);
        if av != bv || av == 0 {
            return av as i64 - bv as i64;
        }
        i += 1;
    }
}

/// ft_split: maximal runs of bytes NOT in `charset`.
#[inline(never)] // keep this attributable under callgrind (see tools/)
pub fn o_split(s: &[u8], charset: &[u8]) -> Vec<Vec<u8>> {
    let is_sep = |c: u8| charset.contains(&c);
    let mut out: Vec<Vec<u8>> = Vec::new();
    let mut i = 0usize;
    let n = s.len();
    while i < n {
        if is_sep(s[i]) {
            i += 1;
            continue;
        }
        let start = i;
        while i < n && !is_sep(s[i]) {
            i += 1;
        }
        out.push(s[start..i].to_vec());
    }
    out
}

// ------------------------------------------------- shared corpus builders
//
// What more than one module's generators and self-checks build their cases
// from, and the sort c06's reference prints with. None is a reference's
// entry point, so none carries #[inline(never)].

/// strcmp as a comparison of `char`s, signed on x86: the other reading of
/// "ASCII order" above 0x7f, where every such byte sorts below 0x00, the
/// terminator included. Never a reference: the sort corpora use it only to
/// tell the cases the two readings part on from the rest (sort_readings_agree).
pub fn strcmp_signed(a: &[u8], b: &[u8]) -> i64 {
    let mut i = 0usize;
    loop {
        let av = *a.get(i).unwrap_or(&0) as i8;
        let bv = *b.get(i).unwrap_or(&0) as i8;
        if av != bv || av == 0 {
            return av as i64 - bv as i64;
        }
        i += 1;
    }
}

/// `args` sorted by `cmp`: a stable insertion sort, so equal strings keep
/// the order they arrived in. c06's o_sort prints its answer with it, under
/// o_strcmp. Written out rather than taken from the standard library: it is
/// the definition of that answer, and `sort_by` would put the comparison
/// one level away from the property being defined.
pub fn sorted_by(args: &[Vec<u8>], cmp: fn(&[u8], &[u8]) -> i64) -> Vec<Vec<u8>> {
    let mut v: Vec<Vec<u8>> = args.to_vec();
    for i in 1..v.len() {
        let mut j = i;
        while j > 0 && cmp(&v[j - 1], &v[j]) > 0 {
            v.swap(j - 1, j);
            j -= 1;
        }
    }
    v
}

/// Whether the two readings of "ASCII order" give one order for `v`: the
/// references', unsigned as strcmp (o_strcmp), and a comparison of `char`s,
/// signed on x86 (strcmp_signed), under which every byte above 0x7f sorts
/// below 0x00. They part only where such a byte is the first one two
/// strings differ in. C 06 ex03's and C 11 ex06's sort corpora split on it.
pub fn sort_readings_agree(v: &[Vec<u8>]) -> bool {
    sorted_by(v, strcmp_signed) == sorted_by(v, o_strcmp)
}

/// `n` words, "w0" to "w<n-1>", each followed by one to three bytes of `sep`
/// taken in turn: runs of separators between the words and after the last.
/// For the split corpora's large cases -- hundreds and thousands of words,
/// past every capacity an array of words is usually given (16, 64, 256, 1024,
/// 4096), which no random string of theirs comes near (finding 041). Built
/// from the index alone, so a corpus's head is the same whatever the seed.
pub fn many_words(n: usize, sep: &[u8]) -> Vec<u8> {
    let mut s = Vec::new();
    for i in 0..n {
        s.extend_from_slice(format!("w{}", i).as_bytes());
        for k in 0..(1 + i % 3) {
            s.push(sep[(i + k) % sep.len()]);
        }
    }
    s
}

/// `n` strings, "s0" to "s<n-1>", every seventh of them empty, for the
/// array corpora's large cases (c07's strjoin, c08's strs_to_tab): past
/// every capacity an array of strings is usually given (finding 041).
/// Built from the index alone, so a corpus's head is the same whatever the
/// seed.
pub fn many_strs(n: usize) -> Vec<Vec<u8>> {
    (0..n).map(|i| if i % 7 == 6 { Vec::new() } else { format!("s{}", i).into_bytes() }).collect()
}

/// The split corpora's large cases (c07 and c09), each a string of
/// many_words(n, sep) split on `sep`: hundreds and thousands of words, past
/// every capacity an array of words is usually given (finding 041).
pub const SPLIT_LARGE: [(usize, &[u8]); 2] = [(300, b" "), (5000, b",; ")];

/// One case of the split corpora's random tail (c07 and c09), a string and
/// a charset, in one of three modes: a small alphabet that overlaps the
/// charset, so the string really splits; bytes of the whole range, with
/// separators picked from the string itself so that some split; an empty
/// charset, which leaves the string one token.
pub fn split_draw(rng: &mut Rng) -> (Vec<u8>, Vec<u8>) {
    let alpha: &[u8] = b"abcd ,;.";
    match rng.below(3) {
        0 => {
            let ls = rng.below(24);
            let s: Vec<u8> = (0..ls).map(|_| alpha[rng.below(alpha.len())]).collect();
            let seps: &[u8] = b" ,;.";
            let lc = rng.below(4);
            let cs: Vec<u8> = (0..lc).map(|_| seps[rng.below(seps.len())]).collect();
            (s, cs)
        }
        1 => {
            let high = rng.below(2) == 1;
            let sl = rng.below(20);
            let s = rand_body(rng, sl, high);
            let lc = rng.below(4);
            let cs = if lc == 0 || s.is_empty() {
                rand_body(rng, lc, high)
            } else {
                (0..lc).map(|_| s[rng.below(s.len())]).collect()
            };
            (s, cs)
        }
        _ => {
            let sl = rng.below(20);
            let high = rng.below(2) == 1;
            let s = rand_body(rng, sl, high);
            (s, vec![])
        }
    }
}

/// One draw of o_split's property, for a self-check's sweep (c07 and c09
/// each call it once per turn of a loop whose rng other properties share):
/// every token is non-empty and holds no byte of the charset, and the
/// tokens, joined, are the string with its separators taken out. Returns
/// the failures, each reported under `label`.
pub fn split_prop(rng: &mut Rng, label: &str) -> usize {
    let mut fails = 0usize;
    let sl = rng.below(16);
    let s = rand_body(rng, sl, false);
    let cs = if rng.below(2) == 0 {
        let cl = rng.below(3);
        rand_body(rng, cl, false)
    } else {
        vec![]
    };
    let toks = o_split(&s, &cs);
    for t in &toks {
        if t.is_empty() || t.iter().any(|c| cs.contains(c)) {
            eprintln!("CHECK FAIL {} split token invariant", label);
            fails += 1;
        }
    }
    let kept: Vec<u8> = s.iter().cloned().filter(|c| !cs.contains(c)).collect();
    if kept != toks.concat() {
        eprintln!("CHECK FAIL {} split reconstruction", label);
        fails += 1;
    }
    fails
}

/// `n` bytes of text for a corpus's capacity cases: words of one to nine
/// letters of both cases and digits, each followed by a space or a
/// punctuation byte. Printable ASCII only, never a NUL. Drawn from `seed`, a
/// seed of the case's own, so a corpus's head is the same whatever the
/// corpus's seed. `n` past every capacity a string is usually given room for
/// (16, 64, 256, 1024, 4096) is what no random string of the corpora comes
/// near (finding 041).
pub fn long_text(n: usize, seed: u64) -> Vec<u8> {
    let mut rng = Rng::new(seed);
    let mut out = Vec::with_capacity(n + 10);
    while out.len() < n {
        for _ in 0..1 + rng.below(9) {
            out.push(match rng.below(3) {
                0 => b'a' + rng.below(26) as u8,
                1 => b'A' + rng.below(26) as u8,
                _ => b'0' + rng.below(10) as u8,
            });
        }
        out.push(b"  ,.;-!?"[rng.below(8)]);
    }
    out.truncate(n);
    out
}

// ------------------------------------------------- capacity self-checks
//
// What a module's check() reads to hold its corpora to their capacity cases
// (finding 041): the corpus a generator writes into a buffer, one line per
// case and one tab between fields, read back field by field. A field may hold
// raw bytes (c01_putstr's output), so nothing here assumes UTF-8.

/// Field `k` of every line of `corpus`, as bytes (a short line gives none).
fn fields_at(corpus: &[u8], k: usize) -> impl Iterator<Item = &[u8]> {
    corpus
        .split(|&b| b == b'\n')
        .filter_map(move |l| l.split(|&b| b == b'\t').nth(k))
}

/// The most bytes field `k`, written in hex, holds on any line of `corpus`.
pub fn widest_hex(corpus: &[u8], k: usize) -> usize {
    fields_at(corpus, k).map(|f| f.len() / 2).max().unwrap_or(0)
}

/// The largest number field `k`, written in decimal, holds on any line of
/// `corpus` (a field that is no number counts as none).
pub fn largest_dec(corpus: &[u8], k: usize) -> i64 {
    fields_at(corpus, k)
        .filter_map(|f| std::str::from_utf8(f).ok()?.parse::<i64>().ok())
        .max()
        .unwrap_or(i64::MIN)
}

/// The most elements field `k`, a comma-separated list, holds on any line
/// of `corpus`.
pub fn longest_csv(corpus: &[u8], k: usize) -> usize {
    fields_at(corpus, k)
        .map(|f| if f.is_empty() { 0 } else { f.iter().filter(|&&b| b == b',').count() + 1 })
        .max()
        .unwrap_or(0)
}

/// Write `bytes` to standard output and flush it. The caller checks the
/// result and picks its own exit code: the shell references that use this
/// report a failed write as a failure, never as a silent success.
pub fn write_stdout(bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let mut so = std::io::stdout();
    so.write_all(bytes).and_then(|_| so.flush())
}

/// Keep the optimiser from deleting a computation whose result we discard.
pub fn sink<T>(v: T) {
    std::hint::black_box(v);
}
