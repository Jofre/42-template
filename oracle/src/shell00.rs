//! Shell 00 references that a shell check cannot construct by itself.
//!
//! ex07 asks for a file `b`: the text you get when the edits recorded in the
//! subject's `sw.diff` are replayed onto the subject's `a`. Both inputs are 42's
//! own material (resources.tar.gz), which this repo does not redistribute, so
//! the expected `b` cannot be written down here -- and the check used to build
//! it by running the very command the exercise asks for, which put the answer
//! in a file the template ships. This is the reference instead, in Rust, as
//! AGENTS.md §2 describes the oracle: readable, not pasteable into a shell
//! script.
//!
//! It reads the "normal" diff format -- the one `diff` prints when it is given
//! no option, and the one sw.diff is written in. A normal diff is a list of
//! hunks, each a command line followed by the lines it talks about:
//!
//!   `F,TcF2,T2`  lines F..T of the old file become lines F2..T2 of the new
//!                one: the old lines follow, each prefixed by `< `, then a
//!                `---` line, then the new lines, each prefixed by `> `.
//!   `F,TdL`      lines F..T of the old file are removed; L says where they
//!                would have been in the new file (after its line L).
//!   `LaF2,T2`    after line L of the old file (0 = before the first), the
//!                new file's lines F2..T2 are inserted, each prefixed by `> `.
//!
//! A range of one line is written as a single number. A line reading
//! `\ No newline at end of file` (the words vary with the locale, the leading
//! backslash does not) says the line just above it is the last of its file
//! and has no newline after it.
//!
//! The reader is STRICT on purpose, stricter than the tools that apply diffs
//! for a living: every removed line must be exactly the old file's line at
//! that position, hunks must come in order and not overlap, and every new-file
//! line number must agree with what has been written so far. A diff that does
//! not describe an edit of the given file is an error, never a best guess --
//! a reference that guesses would fail a correct student for its own mistake.
//!
//! Usage:  oracle shell00_diff_apply <old-file> <diff-file>
//!           prints the edited text on stdout and exits 0; or prints nothing
//!           on stdout, says why on stderr (by line number, never the text),
//!           and exits 1.

use crate::common::Rng;
use std::io::Write;
use std::process::exit;

/// One line of a file: its bytes without the terminator, and whether a
/// newline followed it (only a file's LAST line can lack one).
#[derive(Clone, Debug, PartialEq, Eq)]
struct Line {
    text: Vec<u8>,
    nl: bool,
}

/// Split a file into lines. An empty file has none; a final line with no
/// newline after it is kept, flagged as such.
fn split_lines(data: &[u8]) -> Vec<Line> {
    let mut out = Vec::new();
    let mut start = 0;
    for (i, &b) in data.iter().enumerate() {
        if b == b'\n' {
            out.push(Line {
                text: data[start..i].to_vec(),
                nl: true,
            });
            start = i + 1;
        }
    }
    if start < data.len() {
        out.push(Line {
            text: data[start..].to_vec(),
            nl: false,
        });
    }
    out
}

fn join_lines(lines: &[Line]) -> Vec<u8> {
    let mut out = Vec::new();
    for l in lines {
        out.extend_from_slice(&l.text);
        if l.nl {
            out.push(b'\n');
        }
    }
    out
}

/// A decimal line number: digits only, no sign, no blank.
fn number(s: &[u8]) -> Option<usize> {
    if s.is_empty() || !s.iter().all(u8::is_ascii_digit) {
        return None;
    }
    std::str::from_utf8(s).ok()?.parse().ok()
}

/// `N` or `N,M` (M >= N) as an inclusive pair.
fn range(s: &[u8]) -> Option<(usize, usize)> {
    match s.iter().position(|&b| b == b',') {
        None => number(s).map(|n| (n, n)),
        Some(p) => {
            let (f, t) = (number(&s[..p])?, number(&s[p + 1..])?);
            if t < f {
                None
            } else {
                Some((f, t))
            }
        }
    }
}

/// A hunk's command line, split at its one command letter.
fn command(s: &[u8]) -> Option<((usize, usize), u8, (usize, usize))> {
    let p = s.iter().position(|&b| b == b'a' || b == b'c' || b == b'd')?;
    Some((range(&s[..p])?, s[p], range(&s[p + 1..])?))
}

/// Read the lines of one side of a hunk: `count` lines, each starting with
/// `mark` (then one space, which an empty line may omit), each optionally
/// followed by the no-newline marker. `at` is the index of the next diff line.
fn side(diff: &[Line], at: &mut usize, mark: u8, count: usize) -> Result<Vec<Line>, String> {
    let mut got = Vec::with_capacity(count);
    for _ in 0..count {
        let d = diff.get(*at).ok_or_else(|| {
            format!(
                "the diff ends where a line starting with '{}' was expected",
                mark as char
            )
        })?;
        let text = match d.text.as_slice() {
            [m] if *m == mark => Vec::new(),
            [m, b' ', rest @ ..] if *m == mark => rest.to_vec(),
            _ => {
                return Err(format!(
                    "diff line {}: expected a line starting with '{}'",
                    *at + 1,
                    mark as char
                ))
            }
        };
        *at += 1;
        let mut nl = true;
        if diff.get(*at).map_or(false, |n| n.text.first() == Some(&b'\\')) {
            nl = false;
            *at += 1;
        }
        got.push(Line { text, nl });
    }
    Ok(got)
}

/// Replay a normal-format diff onto `old`. Err says which diff line is wrong
/// and why, by position only.
fn apply(old: &[Line], diff: &[Line]) -> Result<Vec<Line>, String> {
    let mut out: Vec<Line> = Vec::new();
    let mut pos = 0usize; // old lines already consumed
    let mut at = 0usize; // next diff line
    while at < diff.len() {
        let here = at + 1;
        let ((f, t), cmd, (f2, t2)) = command(&diff[at].text)
            .ok_or_else(|| format!("diff line {}: not a hunk command", here))?;
        at += 1;
        // The old-file lines this hunk replaces, as a 0-based half-open span.
        let (start, end) = match cmd {
            b'a' => {
                if f != t {
                    return Err(format!("diff line {}: an insertion names one old line", here));
                }
                (f, f)
            }
            _ => {
                if f == 0 {
                    return Err(format!("diff line {}: old lines are numbered from 1", here));
                }
                (f - 1, t)
            }
        };
        if start < pos {
            return Err(format!("diff line {}: this hunk is out of order or overlaps the previous one", here));
        }
        if end > old.len() {
            return Err(format!("diff line {}: names old lines past the end of the file", here));
        }
        out.extend_from_slice(&old[pos..start]);
        // Where the new file stands after the untouched lines just copied.
        match cmd {
            b'd' => {
                if f2 != t2 || f2 != out.len() {
                    return Err(format!("diff line {}: its new-file position does not add up", here));
                }
            }
            _ => {
                if f2 != out.len() + 1 {
                    return Err(format!("diff line {}: its new-file position does not add up", here));
                }
            }
        }
        if cmd != b'a' {
            let removed = side(diff, &mut at, b'<', end - start)?;
            if removed.as_slice() != &old[start..end] {
                return Err(format!(
                    "the hunk at diff line {}: its removed lines are not the old file's lines {}..{}",
                    here, f, t
                ));
            }
        }
        if cmd == b'c' {
            match diff.get(at) {
                Some(l) if l.text.as_slice() == b"---" => at += 1,
                _ => {
                    return Err(format!(
                        "the hunk at diff line {}: no '---' between its old and new lines",
                        here
                    ))
                }
            }
        }
        if cmd != b'd' {
            let added = side(diff, &mut at, b'>', t2 - f2 + 1)?;
            out.extend(added);
        }
        pos = end;
    }
    out.extend_from_slice(&old[pos..]);
    // Only the very last line of a file may go without a newline.
    if out.iter().rev().skip(1).any(|l| !l.nl) {
        return Err("the result would hold a line with no newline before its last line".into());
    }
    Ok(out)
}

/// `oracle shell00_diff_apply <old> <diff>`
pub fn diff_apply_cmd(old_path: &str, diff_path: &str) -> ! {
    let read = |p: &str| match std::fs::read(p) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("oracle shell00_diff_apply: cannot read {}: {}", p, e);
            exit(1);
        }
    };
    let (old, diff) = (read(old_path), read(diff_path));
    match apply(&split_lines(&old), &split_lines(&diff)) {
        Ok(lines) => {
            let mut so = std::io::stdout();
            if so.write_all(&join_lines(&lines)).and_then(|_| so.flush()).is_err() {
                exit(1);
            }
            exit(0);
        }
        Err(why) => {
            eprintln!("oracle shell00_diff_apply: {}", why);
            exit(1);
        }
    }
}

// ---------------------------------------------------------------- self-check

/// A normal-format diff from `a` to `b`, written the way `diff` writes one:
/// the edit script of a longest common subsequence, grouped into hunks. Used
/// ONLY to feed `apply` inputs it did not write itself -- see check().
fn make_diff(a: &[Line], b: &[Line]) -> Vec<u8> {
    let (n, m) = (a.len(), b.len());
    // lcs[i][j] = length of the LCS of a[i..] and b[j..].
    let mut lcs = vec![vec![0usize; m + 1]; n + 1];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            lcs[i][j] = if a[i] == b[j] {
                lcs[i + 1][j + 1] + 1
            } else {
                lcs[i + 1][j].max(lcs[i][j + 1])
            };
        }
    }
    let r = |f: usize, t: usize| {
        if f == t {
            f.to_string()
        } else {
            format!("{},{}", f, t)
        }
    };
    let emit = |out: &mut Vec<u8>, mark: &[u8], l: &Line| {
        out.extend_from_slice(mark);
        out.extend_from_slice(&l.text);
        out.push(b'\n');
        if !l.nl {
            out.extend_from_slice(b"\\ No newline at end of file\n");
        }
    };
    let mut out = Vec::new();
    let (mut i, mut j) = (0, 0);
    while i < n || j < m {
        if i < n && j < m && a[i] == b[j] {
            i += 1;
            j += 1;
            continue;
        }
        let (i0, j0) = (i, j);
        while (i < n || j < m) && !(i < n && j < m && a[i] == b[j]) {
            if j >= m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1]) {
                i += 1;
            } else {
                j += 1;
            }
        }
        let head = match (i > i0, j > j0) {
            (true, true) => format!("{}c{}", r(i0 + 1, i), r(j0 + 1, j)),
            (true, false) => format!("{}d{}", r(i0 + 1, i), j0),
            _ => format!("{}a{}", i0, r(j0 + 1, j)),
        };
        out.extend_from_slice(head.as_bytes());
        out.push(b'\n');
        for l in &a[i0..i] {
            emit(&mut out, b"< ", l);
        }
        if i > i0 && j > j0 {
            out.extend_from_slice(b"---\n");
        }
        for l in &b[j0..j] {
            emit(&mut out, b"> ", l);
        }
    }
    out
}

/// A random file of up to `max` lines, drawn from a small pool so two files
/// share many lines (which is what makes the diffs between them interesting).
/// The pool holds lines that LOOK like diff syntax, so content is never
/// mistaken for structure.
fn rand_file(rng: &mut Rng, max: usize) -> Vec<u8> {
    const POOL: &[&[u8]] = &[
        b"alpha", b"beta", b"", b"  indented", b"---", b"< looks old", b"> looks new",
        b"\\ backslash first", b"1,2c3", b"tab\there", b"gamma",
    ];
    let mut out = Vec::new();
    let k = rng.below(max + 1);
    for _ in 0..k {
        out.extend_from_slice(POOL[rng.below(POOL.len())]);
        out.push(b'\n');
    }
    // Sometimes the last line has no newline -- the case diff marks with `\`.
    if !out.is_empty() && rng.below(4) == 0 {
        out.pop();
        if out.last() == Some(&b'\n') || out.is_empty() {
            // the last line was empty: an unterminated empty line is no line
            // at all, so give it a body
            out.extend_from_slice(b"tail");
        }
    }
    out
}

pub fn check() -> usize {
    let mut fails = 0usize;
    let run = |old: &[u8], diff: &[u8]| {
        apply(&split_lines(old), &split_lines(diff)).map(|l| join_lines(&l))
    };

    // ---- hand-written cases, each worked out by hand from the format rules.
    let good: &[(&[u8], &[u8], &[u8])] = &[
        // one line changed
        (b"1\n2\n3\n", b"2c2\n< 2\n---\n> two\n", b"1\ntwo\n3\n"),
        // inserted before the first line
        (b"1\n", b"0a1\n> zero\n", b"zero\n1\n"),
        // inserted after the last line
        (b"a\nb\n", b"2a3,4\n> c\n> d\n", b"a\nb\nc\nd\n"),
        // a range removed
        (b"1\n2\n3\n4\n", b"2,3d1\n< 2\n< 3\n", b"1\n4\n"),
        // two hunks, the second's new-file number shifted by the first
        (b"p\nq\nr\ns\n", b"1,2c1,3\n< p\n< q\n---\n> P\n> Q\n> R\n4d4\n< s\n", b"P\nQ\nR\nr\n"),
        // the old file ends without a newline; the new one gains it
        (b"a\nb", b"2c2\n< b\n\\ No newline at end of file\n---\n> b\n", b"a\nb\n"),
        // the new file loses its final newline
        (b"a\n", b"1c1\n< a\n---\n> a\n\\ No newline at end of file\n", b"a"),
        // an empty diff changes nothing, an empty file can be filled
        (b"x\ny\n", b"", b"x\ny\n"),
        (b"", b"0a1\n> only\n", b"only\n"),
        // an empty line, written with and without its space after the mark
        (b"a\n\nb\n", b"2d1\n<\n", b"a\nb\n"),
        (b"a\n\nb\n", b"2d1\n< \n", b"a\nb\n"),
    ];
    for (i, (old, diff, want)) in good.iter().enumerate() {
        match run(old, diff) {
            Ok(got) if got.as_slice() == *want => {}
            other => {
                eprintln!("CHECK FAIL shell00 diff_apply good case {}: got {:?}", i, other);
                fails += 1;
            }
        }
    }
    let bad: &[(&[u8], &[u8])] = &[
        // the removed line is not what the old file holds there
        (b"a\n", b"1c1\n< nope\n---\n> x\n"),
        // hunks out of order
        (b"a\nb\nc\n", b"3d2\n< c\n1d0\n< a\n"),
        // not a command
        (b"a\n", b"1x1\n"),
        (b"a\n", b"garbage\n"),
        // past the end of the old file
        (b"a\n", b"5d4\n< e\n"),
        // fewer new lines than the command announces
        (b"a\n", b"1c1,2\n< a\n---\n> b\n"),
        // no separator between the two sides of a change
        (b"a\n", b"1c1\n< a\n> b\n"),
        // new-file number that does not add up
        (b"a\n", b"1c2\n< a\n---\n> b\n"),
        (b"a\nb\n", b"2d0\n< b\n"),
        // the removed line matches in text but not in its missing newline
        (b"a\nb\n", b"2c2\n< b\n\\ No newline at end of file\n---\n> c\n"),
        // a newline-less line followed by more lines
        (b"a\nb\n", b"1c1\n< a\n---\n> a\n\\ No newline at end of file\n"),
        // old lines are numbered from 1
        (b"a\n", b"0d0\n"),
        // a descending range
        (b"a\nb\n", b"2,1d0\n< b\n< a\n"),
    ];
    for (i, (old, diff)) in bad.iter().enumerate() {
        if run(old, diff).is_ok() {
            eprintln!("CHECK FAIL shell00 diff_apply bad case {}: accepted", i);
            fails += 1;
        }
    }

    // ---- property: for random pairs of files, the diff between them, as
    // written by an LCS edit script, replays the first into the second --
    // byte for byte, final-newline state included. And the empty diff is the
    // identity.
    let mut rng = Rng::new(0x5e11_0007);
    for case in 0..5000 {
        let a = rand_file(&mut rng, 12);
        let b = rand_file(&mut rng, 12);
        let (la, lb) = (split_lines(&a), split_lines(&b));
        let diff = make_diff(&la, &lb);
        match run(&a, &diff) {
            Ok(got) if got == b => {}
            other => {
                eprintln!(
                    "CHECK FAIL shell00 diff_apply sweep case {}: a={:?} b={:?} diff={:?} got={:?}",
                    case,
                    String::from_utf8_lossy(&a),
                    String::from_utf8_lossy(&b),
                    String::from_utf8_lossy(&diff),
                    other
                );
                fails += 1;
            }
        }
        if run(&a, b"").ok().as_deref() != Some(a.as_slice()) {
            eprintln!("CHECK FAIL shell00 diff_apply sweep case {}: empty diff not identity", case);
            fails += 1;
        }
        // Every removed line is verified against the old file, and no kept
        // line is: altering old line k, one k at a time, must make the diff
        // refuse exactly as many times as the diff removes lines.
        let removed = split_lines(&diff)
            .iter()
            .filter(|l| l.text.first() == Some(&b'<'))
            .count();
        let mut refused = 0;
        for k in 0..la.len() {
            let mut altered = la.clone();
            altered[k].text = b"altered".to_vec();
            if apply(&altered, &split_lines(&diff)).is_err() {
                refused += 1;
            }
        }
        if refused != removed {
            eprintln!(
                "CHECK FAIL shell00 diff_apply sweep case {}: {} altered lines refused, {} removed",
                case, refused, removed
            );
            fails += 1;
        }
    }
    fails
}
