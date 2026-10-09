//! Length series for the perf layer: `oracle <arm> <seed> <cases> <length>`.
//!
//! The perf layer's scaling varies the NUMBER of cases, each one a small input,
//! so what it fits is how many calls add up -- a cubic sort over arrays of a
//! dozen ints is linear in how many arrays it is handed (finding 044). These
//! arms hold the number of cases still and vary the length of the one input
//! instead: `cases` lines, each an input of exactly `length` elements, for a
//! harness that reads a line of any length (tests/exNN/len_*.c, wired by
//! c_perf's `length`).
//!
//! No reference column: the length harness checks its own result (sorted, and
//! the same values), because comparing long outputs line by line is the diff
//! layer's job and would make the harness's own cost grow with what it prints.
//! The values are the same kind the exercise's diff generator uses.

use crate::common::{join_csv, Rng};
use std::io::{self, Write};

/// A value in [lo, hi], uniform.
fn ranged(rng: &mut Rng, lo: i64, hi: i64) -> i32 {
    (lo + rng.below((hi - lo + 1) as usize) as i64) as i32
}

/// A word of 1..=max letters drawn from `alphabet`.
fn word(rng: &mut Rng, alphabet: &[u8], max: usize) -> String {
    let n = 1 + rng.below(max);
    (0..n).map(|_| alphabet[rng.below(alphabet.len())] as char).collect()
}

/// What an element of a line is, for each arm: how the self-check counts them.
#[derive(Clone, Copy, PartialEq)]
enum Unit {
    /// comma-separated values
    Csv,
    /// words between runs of the split arms' separators, '_' and '-'
    Words,
    /// bytes
    Chars,
}

/// The arms, and what each one's `length` counts.
const ARMS: [(&str, Unit); 8] = [
    ("c01_sort_int_tab_len", Unit::Csv),
    ("c12_list_sort_len", Unit::Csv),
    ("c11_sort_string_tab_len", Unit::Csv),
    ("c11_advanced_sort_string_tab_len", Unit::Csv),
    ("c07_split_len", Unit::Words),
    ("c09_split_len", Unit::Words),
    ("c02_str_is_alpha_len", Unit::Chars),
    ("c03_strstr_len", Unit::Chars),
];

/// The lines an arm writes, or None for a name that is not one of these arms.
fn lines(name: &str, seed: u64, count: usize, len: usize) -> Option<Vec<String>> {
    let mut rng = Rng::new(seed);
    let mut out = Vec::with_capacity(count);
    for _ in 0..count {
        let line = match name {
            // C 01 ex08: any int, the boundaries included.
            "c01_sort_int_tab_len" => join_csv(&(0..len).map(|_| rng.i32val()).collect::<Vec<i32>>()),
            // C 12 ex14: bounded as c12_list_sort is, so the harness's
            // comparator, *a - *b, never overflows.
            "c12_list_sort_len" => {
                join_csv(&(0..len).map(|_| ranged(&mut rng, -100_000, 100_000)).collect::<Vec<i32>>())
            }
            // C 11 ex06 and ex07: `len` strings of a small alphabet and up to
            // six letters, as c11_sort_string_tab draws them -- many ties and
            // shared prefixes -- joined by commas, which none holds.
            "c11_sort_string_tab_len" | "c11_advanced_sort_string_tab_len" => {
                (0..len).map(|_| word(&mut rng, b"abcde", 6)).collect::<Vec<String>>().join(",")
            }
            // C 07 ex05 and C 09 ex02: `len` words of letters, each run of
            // separators one or two of the charset's '_' and '-', one run at
            // either end now and then; then a tab and the words, comma-joined,
            // which the generator laid down and the harness compares the
            // result with (it splits nothing itself). The harness passes "_-"
            // as the charset.
            "c07_split_len" | "c09_split_len" => {
                let mut words: Vec<String> = Vec::new();
                let mut l = String::new();
                let sep = |rng: &mut Rng| -> String {
                    (0..1 + rng.below(2)).map(|_| if rng.below(2) == 0 { '_' } else { '-' }).collect()
                };
                if len > 0 && rng.below(4) == 0 {
                    l.push_str(&sep(&mut rng));
                }
                for i in 0..len {
                    if i > 0 {
                        l.push_str(&sep(&mut rng));
                    }
                    let w = word(&mut rng, b"abcdefghijklmnopqrstuvwxyz", 6);
                    l.push_str(&w);
                    words.push(w);
                }
                if len > 0 && rng.below(4) == 0 {
                    l.push_str(&sep(&mut rng));
                }
                format!("{}\t{}", l, words.join(","))
            }
            // C 02 ex02: `len` letters of both cases, so the answer is 1 and
            // the whole string is read to find it.
            "c02_str_is_alpha_len" => (0..len)
                .map(|_| {
                    let c = b'a' + rng.below(26) as u8;
                    (if rng.below(2) == 0 { c } else { c - 32 }) as char
                })
                .collect(),
            // C 03 ex04: `len` letters, the needle "zzz" only at the very end
            // (the rest never holds a 'z'), so a search reads the whole string
            // to find it; shorter than the needle, no 'z' and no match. The
            // harness looks for "zzz", and knows where it is by construction.
            "c03_strstr_len" => {
                let head = len.saturating_sub(3);
                let mut l: String = (0..head).map(|_| (b'a' + rng.below(25) as u8) as char).collect();
                if len >= 3 {
                    l.push_str("zzz");
                } else {
                    l.extend((0..len).map(|_| 'a'));
                }
                l
            }
            _ => return None,
        };
        out.push(line);
    }
    Some(out)
}

/// How many elements `line` holds, counted as `unit` says.
fn elements(line: &str, unit: Unit) -> usize {
    match unit {
        Unit::Csv => {
            if line.is_empty() {
                0
            } else {
                line.split(',').count()
            }
        }
        Unit::Words => {
            let s = line.split('\t').next().unwrap_or("");
            s.split(|c| c == '_' || c == '-').filter(|w| !w.is_empty()).count()
        }
        Unit::Chars => line.len(),
    }
}

/// Dispatch: true if `name` is one of this module's arms.
pub fn gen(name: &str, seed: u64, count: usize, len: usize) -> bool {
    match lines(name, seed, count, len) {
        Some(ls) => {
            let mut w = io::BufWriter::new(io::stdout());
            for l in ls {
                let _ = writeln!(w, "{}", l);
            }
            true
        }
        None => false,
    }
}

/// Self-check: each arm writes `count` lines of exactly `len` elements each
/// (as ARMS counts them), an empty line for length 0, and the same lines for
/// the same seed; a string arm's line never holds its own separator inside an
/// element, and strstr's needle is where its harness looks for it.
pub fn check() -> usize {
    let mut fails = 0usize;
    for &(name, unit) in ARMS.iter() {
        for len in [0usize, 1, 2, 3, 7, 1000] {
            let a = lines(name, 3, 5, len).unwrap_or_default();
            let b = lines(name, 3, 5, len).unwrap_or_default();
            if a.len() != 5 || a != b {
                eprintln!("CHECK FAIL length {} len={}: {} lines, repeatable={}", name, len, a.len(), a == b);
                fails += 1;
            }
            for l in &a {
                let n = elements(l, unit);
                if n != len {
                    eprintln!("CHECK FAIL length {} len={}: a line of {} elements", name, len, n);
                    fails += 1;
                }
                if unit == Unit::Csv && name.starts_with("c11_") && l.split(',').any(|w| w.is_empty()) && len > 0 {
                    eprintln!("CHECK FAIL length {}: an empty string, which a comma join cannot carry", name);
                    fails += 1;
                }
                if unit == Unit::Words {
                    // The words after the tab are the string's, in order.
                    let mut parts = l.splitn(2, '\t');
                    let s = parts.next().unwrap_or("");
                    let want = parts.next().unwrap_or("");
                    let got: Vec<&str> = s.split(|c| c == '_' || c == '-').filter(|w| !w.is_empty()).collect();
                    if got.join(",") != want {
                        eprintln!("CHECK FAIL length {} len={}: the words after the tab are not the string's", name, len);
                        fails += 1;
                    }
                }
                if name == "c03_strstr_len" {
                    let at = l.find("zzz");
                    if (len >= 3 && at != Some(len - 3)) || (len < 3 && l.contains('z')) {
                        eprintln!("CHECK FAIL length {} len={}: the needle is not only at the end", name, len);
                        fails += 1;
                    }
                }
                if name == "c12_list_sort_len"
                    && l.split(',').filter(|x| !x.is_empty()).any(|x| {
                        x.parse::<i64>().map_or(true, |v| !(-100_000..=100_000).contains(&v))
                    })
                {
                    eprintln!("CHECK FAIL length {}: a value outside the comparator's range", name);
                    fails += 1;
                }
            }
        }
    }
    if lines("c01_nope_len", 1, 1, 1).is_some() {
        eprintln!("CHECK FAIL length: an unknown arm was claimed");
        fails += 1;
    }
    fails
}
