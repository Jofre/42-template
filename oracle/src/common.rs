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
/// buffer. Generators that hex-encode a LIST (c13's join_hex, which runs per
/// tree node per case) were calling to_hex in a loop, which allocates a String
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

/// A random C-string body: `len` bytes, NEVER 0x00 (that would terminate). When
/// `high` is set the full 0x01..=0xFF range is used (exercises signed char);
/// otherwise lowercase letters.
pub fn rand_body(rng: &mut Rng, len: usize, high: bool) -> Vec<u8> {
    (0..len)
        .map(|_| {
            if high {
                (1 + rng.below(255)) as u8
            } else {
                (b'a' as usize + rng.below(26)) as u8
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

// ------------------------------------------------------------- bench support
/// Every line of stdin. Used by `oracle bench <fn>`, which replays a corpus and
/// computes the reference answers WITHOUT generating or printing them — so the
/// perf layer can time the reference doing the same work the student does.
pub fn bench_lines() -> impl Iterator<Item = String> {
    use std::io::BufRead;
    std::io::stdin().lock().lines().map_while(Result::ok)
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

/// Keep the optimiser from deleting a computation whose result we discard.
pub fn sink<T>(v: T) {
    std::hint::black_box(v);
}
