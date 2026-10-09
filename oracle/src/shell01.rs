//! Shell 01 references that a shell check cannot construct by itself.
//!
//! Each one is here so that a check does not have to run the exercise's own
//! command to know what to expect, which would put the answer in a file the
//! template ships. They are references: two of them (ex07, ex08) compute the
//! whole result the exercise asks for, from the same input the student's
//! program reads. The checks that use them never print what they compute:
//! a check line says PASS or FAIL, and a failure shows the student's own
//! output or the input that was used, never the expected one.
//!
//! ex01 prints the groups of the user named in $FT_USER. Its expected value
//! lives in the machine's user database -- /etc/group on a laptop, LDAP on a 42
//! campus box -- so no fixture can fix it in advance. This asks glibc through
//! the same NSS calls `id` makes (getpwnam, getgrouplist, getgrgid), so it
//! agrees with the machine on whatever backend the machine uses, and it
//! reproduces coreutils' order: the user's primary group first, then the rest
//! in the order getgrouplist returns them, the primary skipped. A group with
//! no name is printed as its number, as `id` does.
//!
//!   oracle shell01_groups <user>
//!       prints g1,g2,... (no newline); exit 1, printing nothing, if the user
//!       does not exist.
//!   oracle shell01_multigroup [<except>]
//!       prints the login of the first user in the user database (getpwent's
//!       order), other than <except>, who is in two groups or more: a user
//!       whose list has a comma in it. Exit 1, printing nothing, if there is
//!       none. The check drives such a user, because a list of one group
//!       cannot show how two are joined.
//!
//! ex04 prints this machine's MAC addresses. Its check used to validate the
//! output with a text pattern, and that pattern is a piece of a common answer.
//! `hwaddr` asks the kernel instead: the addresses of this machine's network
//! interfaces, as Linux publishes them under /sys/class/net/<if>/address.
//!
//!   oracle shell01_hwaddr [--loopback]   < lines
//!       exit 0  every line of stdin is a MAC address (six two-digit hex
//!               numbers joined by ':', either case) AND one of this machine's,
//!               and at least one is a hardware interface's;
//!       exit 1  some line is not a MAC address at all (an empty input, or a
//!               blank line, counts as one);
//!       exit 3  every line is a MAC address, but some are not this machine's;
//!       exit 4  every line is a MAC address, and this machine publishes no
//!               hardware address to compare them with;
//!       exit 5  (--loopback only) every line is this machine's, but each is
//!               the loopback's: no hardware interface's address is printed.
//!       "This machine's" is its hardware interfaces': loopback and all-zero
//!       addresses left out. --loopback also counts the address the kernel
//!       publishes for a loopback interface (00:00:00:00:00:00), which one
//!       reading of "your machine's MAC addresses" includes -- BESIDE the
//!       hardware ones, never instead of them: an output of that line alone
//!       would pass on every Linux machine, so it is 5 and not 0. Nothing is
//!       printed on stdout; stderr names a LINE NUMBER, never an address.
//!   oracle shell01_hwaddr --machine
//!       exit 0 when this machine publishes a hardware address, 4 when it
//!       publishes none; stdin is not read. Asked by a check before it runs
//!       the program, so a machine that has no address to print is a skip
//!       and never a failure of a program that printed nothing.
//!
//! ex07 transforms /etc/passwd in the subject's seven steps and prints one
//! line. `rdwssap` computes that line's names from the same file -- the
//! check points it at the file the program read -- and judges a program's
//! output against them, one property at a time.
//!
//!   oracle shell01_rdwssap <first> <last> [--order locale|c] [--passwd FILE]
//!       reads the program's output (FT_LINE1=<first> FT_LINE2=<last>) on
//!       stdin and prints, on one line, the word for each property it breaks:
//!         comments  a comment line's text is printed as a name
//!         reversed  a name is no login of FILE, read backwards
//!         lines     a name is a login from a line the subject's steps drop,
//!                   or (for a range that covers the whole list) a name those
//!                   steps keep is missing
//!         order     the names are not in reverse alphabetical order -- by
//!                   the test locale's collation, or by bytes (C); with
//!                   --order, by that one only
//!         window    the names are not exactly entries <first>..<last> of
//!                   the whole list, in the order the output follows
//!         c-order   not a fault: in reverse order by bytes, and not by the
//!                   locale's collation (printed only when the two differ)
//!       and nothing when it breaks none. The output is read leniently for
//!       this -- one final newline and the final '.' dropped, names cut at
//!       ',' or a newline, blanks trimmed -- because its exact shape is the
//!       check's own lines, and one misplaced byte should not hide whether
//!       the names are right. FILE is /etc/passwd by default. Exit 2 if FILE
//!       cannot be read or a bound is not a line number.
//!   oracle shell01_rdwssap orders [--passwd FILE]
//!       exit 0 when the test locale's order and C's differ on the names the
//!       steps keep from FILE, 1 when they agree (then no output can tell the
//!       two readings apart).
//!   oracle shell01_rdwssap reaches <n> [--passwd FILE]
//!       exit 0 when the steps keep at least <n> names from FILE, 1 if not.
//!   oracle shell01_rdwssap shows [--passwd FILE]
//!       whether FILE, as a fixture, shows every step a machine's own file
//!       hides: exit 0, or 1 printing a word for each it does not --
//!         comment-first  no comment line before the first login
//!         comment-later  no comment line between two logins that makes
//!                        a difference: removing comments before taking
//!                        every other line, from the first login on, keeps
//!                        the same lines as removing them after
//!         window         fewer than 15 names kept, so the subject's own
//!                        range, lines 7 to 15, runs past the end
//!         orders         the test locale's order and C's agree on the kept
//!                        names, so the two readings of the order look alike
//!       Asked by ex07's check before the fixture runs: a fixture edited until
//!       it no longer shows a step would otherwise pass every program that
//!       skips that step.
//!
//! The collation. "Reverse alphabetical order" names none, and the grader's
//! locale is not known, so there are two readings: bytes (the C locale), and
//! the collation of the locale the test runs in -- LC_ALL=en_US.UTF-8 in
//! .bazelrc -- which is what `sort` uses there. That one is glibc's strcoll
//! with GNU sort's last resort, a byte comparison, when strcoll finds two
//! names equal. Where the locale is not installed, setlocale fails, and both
//! readings are bytes.
//!
//! ex08 adds two numbers written in bases of their own and prints the sum in a
//! third. `chelou` is that sum, and the seeded pairs the check runs.
//!
//!   oracle shell01_chelou
//!       prints the sum of $FT_NBR1 and $FT_NBR2, as the program must print
//!       it, with its newline. Exit 1 if either is not a number in its base
//!       (empty, or holding a byte the base does not have).
//!   oracle shell01_chelou cases <seed>
//!       prints one pair per line, "<label>\t<FT_NBR1>\t<FT_NBR2>": a pair for
//!       each class of input the check covers -- zero as either operand and
//!       as the sum, each quoting-sensitive digit, backslashes side by side, a
//!       lone '?', a sum more than 70 digits long, operands of very different
//!       lengths. No operand starts with its base's zero digit unless it is
//!       that digit alone: whether a padded string is one of the subject's
//!       numbers is open, so none is asked.

use crate::common::Rng;
use std::ffi::{CStr, CString};
use std::io::{Read, Write};
use std::os::raw::{c_char, c_int};
use std::os::unix::ffi::OsStrExt;
use std::process::exit;

type Gid = u32;

// glibc's struct passwd and struct group, field for field (x86_64 Linux).
#[repr(C)]
struct Passwd {
    pw_name: *mut c_char,
    pw_passwd: *mut c_char,
    pw_uid: u32,
    pw_gid: Gid,
    pw_gecos: *mut c_char,
    pw_dir: *mut c_char,
    pw_shell: *mut c_char,
}

#[repr(C)]
struct Group {
    gr_name: *mut c_char,
    gr_passwd: *mut c_char,
    gr_gid: Gid,
    gr_mem: *mut *mut c_char,
}

extern "C" {
    fn getpwnam(name: *const c_char) -> *mut Passwd;
    fn setpwent();
    fn getpwent() -> *mut Passwd;
    fn endpwent();
    fn getgrgid(gid: Gid) -> *mut Group;
    fn getgrouplist(user: *const c_char, group: Gid, groups: *mut Gid, ngroups: *mut c_int)
        -> c_int;
    fn setlocale(category: c_int, locale: *const c_char) -> *mut c_char;
    fn strcoll(a: *const c_char, b: *const c_char) -> c_int;
}

/// glibc's LC_COLLATE.
const LC_COLLATE: c_int = 3;

fn group_name(gid: Gid) -> String {
    // SAFETY: getgrgid returns NULL or a pointer to static storage that stays
    // valid until the next getgr* call; the name is copied out before that.
    unsafe {
        let g = getgrgid(gid);
        if g.is_null() || (*g).gr_name.is_null() {
            return gid.to_string();
        }
        CStr::from_ptr((*g).gr_name).to_string_lossy().into_owned()
    }
}

/// The group names of `user`, in the order `id -Gn user` prints them, or None
/// if the user does not exist.
fn groups_of(user: &str) -> Option<Vec<String>> {
    let cuser = CString::new(user).ok()?;
    // SAFETY: getpwnam returns NULL or static storage; pw_gid is copied out.
    let primary = unsafe {
        let pw = getpwnam(cuser.as_ptr());
        if pw.is_null() {
            return None;
        }
        (*pw).pw_gid
    };
    let mut n: c_int = 64;
    let mut list: Vec<Gid> = vec![0; n as usize];
    loop {
        let mut got = n;
        // SAFETY: `list` holds `n` elements and getgrouplist writes at most
        // `got` of them, updating `got` to the number it needs.
        let rc = unsafe { getgrouplist(cuser.as_ptr(), primary, list.as_mut_ptr(), &mut got) };
        if rc >= 0 {
            list.truncate(got as usize);
            break;
        }
        n = if got > n { got } else { n * 2 };
        list = vec![0; n as usize];
    }
    let mut gids = vec![primary];
    for g in list {
        if !gids.contains(&g) {
            gids.push(g);
        }
    }
    Some(gids.into_iter().map(group_name).collect())
}

/// `oracle shell01_groups <user>`
pub fn groups(user: &str) -> ! {
    match groups_of(user) {
        Some(names) => {
            print!("{}", names.join(","));
            exit(0);
        }
        None => exit(1),
    }
}

/// How many entries of the user database `multigroup_user` reads at most. A
/// campus box may enumerate a directory service behind getpwent; the first
/// user in two groups is nearly always a local one near the top.
const MAX_USERS: usize = 10_000;

/// The logins of the user database, in getpwent's order.
fn all_logins() -> Vec<String> {
    let mut names = Vec::new();
    // SAFETY: getpwent returns NULL or static storage valid until the next
    // getpw* call; each name is copied out before the next one. The names are
    // collected first because groups_of calls getpwnam, which would disturb
    // the walk.
    unsafe {
        setpwent();
        while names.len() < MAX_USERS {
            let pw = getpwent();
            if pw.is_null() {
                break;
            }
            if !(*pw).pw_name.is_null() {
                names.push(CStr::from_ptr((*pw).pw_name).to_string_lossy().into_owned());
            }
        }
        endpwent();
    }
    names
}

/// `oracle shell01_multigroup [<except>]`
pub fn multigroup_cmd(except: Option<&str>) -> ! {
    for name in all_logins() {
        if Some(name.as_str()) == except {
            continue;
        }
        if groups_of(&name).map_or(false, |g| g.len() >= 2) {
            print!("{}", name);
            exit(0);
        }
    }
    exit(1);
}

fn read_stdin() -> Vec<u8> {
    let mut data = Vec::new();
    if std::io::stdin().read_to_end(&mut data).is_err() {
        eprintln!("oracle: cannot read stdin");
        exit(2);
    }
    data
}

// ----------------------------------------------------------------- hwaddr

/// `hh:hh:hh:hh:hh:hh`, each `h` a hex digit of either case, and nothing else.
fn parse_mac(s: &[u8]) -> Option<[u8; 6]> {
    if s.len() != 17 {
        return None;
    }
    let mut mac = [0u8; 6];
    for (k, byte) in mac.iter_mut().enumerate() {
        let at = k * 3;
        if k > 0 && s[at - 1] != b':' {
            return None;
        }
        let hi = (s[at] as char).to_digit(16)?;
        let lo = (s[at + 1] as char).to_digit(16)?;
        *byte = (hi * 16 + lo) as u8;
    }
    Some(mac)
}

/// ARPHRD_LOOPBACK, as /sys/class/net/<interface>/type spells it.
const LOOPBACK_TYPE: &[u8] = b"772";

/// The six-byte addresses this machine's network interfaces publish under
/// /sys/class/net, as (hardware, loopback): the hardware ones with all-zero
/// addresses left out, and the loopback ones as they are (lo publishes
/// 00:00:00:00:00:00). An address that is not six bytes long is left out
/// (tunnels publish four- or sixteen-byte ones). Both are empty where the
/// directory does not exist or nothing in it qualifies.
fn host_addrs() -> (Vec<[u8; 6]>, Vec<[u8; 6]>) {
    let (mut hw, mut lo) = (Vec::new(), Vec::new());
    let dir = match std::fs::read_dir("/sys/class/net") {
        Ok(d) => d,
        Err(_) => return (hw, lo),
    };
    for entry in dir.flatten() {
        let p = entry.path();
        let ty = std::fs::read(p.join("type")).unwrap_or_default();
        let addr = match std::fs::read(p.join("address")) {
            Ok(a) => a,
            Err(_) => continue,
        };
        let mac = match parse_mac(addr.trim_ascii()) {
            Some(m) => m,
            None => continue,
        };
        if ty.trim_ascii() == LOOPBACK_TYPE {
            if !lo.contains(&mac) {
                lo.push(mac);
            }
        } else if mac != [0u8; 6] && !hw.contains(&mac) {
            hw.push(mac);
        }
    }
    (hw, lo)
}

/// The verdict `shell01_hwaddr` exits with (see the module header), and the
/// number of the line that decided it (0 when no single line did). `hw` is
/// the machine's hardware addresses, `also` what else counts as its own --
/// beside them: an output of `also`'s lines alone is 5, never 0.
fn hwaddr_verdict(input: &[u8], hw: &[[u8; 6]], also: &[[u8; 6]]) -> (i32, usize) {
    let body = input.strip_suffix(b"\n").unwrap_or(input);
    let mut macs = Vec::new();
    for (i, l) in body.split(|&b| b == b'\n').enumerate() {
        match parse_mac(l) {
            Some(m) => macs.push(m),
            None => return (1, i + 1),
        }
    }
    if hw.is_empty() {
        return (4, 0);
    }
    for (i, m) in macs.iter().enumerate() {
        if !hw.contains(m) && !also.contains(m) {
            return (3, i + 1);
        }
    }
    if !macs.iter().any(|m| hw.contains(m)) {
        return (5, 0);
    }
    (0, 0)
}

/// `oracle shell01_hwaddr [--loopback]`
pub fn hwaddr_cmd(loopback: bool) -> ! {
    let (hw, lo) = host_addrs();
    let also: &[[u8; 6]] = if loopback { &lo } else { &[] };
    let (rc, line) = hwaddr_verdict(&read_stdin(), &hw, also);
    match rc {
        1 => eprintln!("oracle shell01_hwaddr: line {} is not a MAC address", line),
        3 => eprintln!(
            "oracle shell01_hwaddr: line {} is a MAC address, but not one of this machine's",
            line
        ),
        4 => eprintln!("oracle shell01_hwaddr: this machine publishes no hardware address to compare with"),
        5 => eprintln!("oracle shell01_hwaddr: every line is the loopback's; none is a hardware interface's"),
        _ => {}
    }
    exit(rc);
}

/// `oracle shell01_hwaddr --machine`: 0 when this machine publishes a
/// hardware address, 4 when it publishes none. Keyed off the machine alone.
pub fn hwaddr_machine_cmd() -> ! {
    let (hw, _) = host_addrs();
    if hw.is_empty() {
        eprintln!("oracle shell01_hwaddr: this machine publishes no hardware address");
        exit(4);
    }
    exit(0);
}

// ---------------------------------------------------------------- rdwssap

/// The lines of a passwd file: cut at each '\n', a final empty piece (after
/// the file's last newline) not a line.
fn pw_lines(data: &[u8]) -> Vec<&[u8]> {
    let mut v: Vec<&[u8]> = data.split(|&b| b == b'\n').collect();
    if v.last().map_or(false, |l| l.is_empty()) {
        v.pop();
    }
    v
}

/// A comment line: one whose first byte is '#'.
fn is_comment(line: &[u8]) -> bool {
    line.first() == Some(&b'#')
}

/// A line's login: what comes before its first ':', or the whole line.
fn login(line: &[u8]) -> &[u8] {
    match line.iter().position(|&b| b == b':') {
        Some(p) => &line[..p],
        None => line,
    }
}

/// `name` backwards, a character at a time where it is UTF-8 (as rev(1)
/// reads it in a UTF-8 locale), a byte at a time where it is not.
fn backwards(name: &[u8]) -> Vec<u8> {
    match std::str::from_utf8(name) {
        Ok(s) => s.chars().rev().collect::<String>().into_bytes(),
        Err(_) => name.iter().rev().copied().collect(),
    }
}

/// The names the subject's steps keep from `data`, before the sort: comments
/// removed, then every other line from the second, each login backwards.
fn kept_names(data: &[u8]) -> Vec<Vec<u8>> {
    pw_lines(data)
        .into_iter()
        .filter(|l| !is_comment(l))
        .enumerate()
        .filter(|(i, _)| i % 2 == 1)
        .map(|(_, l)| backwards(login(l)))
        .collect()
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Coll {
    /// Bytes, as the C locale compares them.
    C,
    /// The test locale's strcoll, bytes when it finds two names equal.
    Locale,
}

/// setlocale(LC_COLLATE, "") once, so Coll::Locale follows the environment
/// (LC_ALL, then LC_COLLATE, then LANG), as sort(1) does.
fn use_env_locale() {
    // SAFETY: a valid NUL-terminated string; the result is not kept.
    unsafe {
        setlocale(LC_COLLATE, b"\0".as_ptr() as *const c_char);
    }
}

fn coll_cmp(a: &[u8], b: &[u8], how: Coll) -> std::cmp::Ordering {
    if how == Coll::Locale {
        if let (Ok(ca), Ok(cb)) = (CString::new(a), CString::new(b)) {
            // SAFETY: two valid NUL-terminated strings.
            let d = unsafe { strcoll(ca.as_ptr(), cb.as_ptr()) };
            if d != 0 {
                return d.cmp(&0);
            }
        }
    }
    a.cmp(b)
}

/// `names` in reverse order by `how`: what `sort -r` prints.
fn sorted_desc(names: &[Vec<u8>], how: Coll) -> Vec<Vec<u8>> {
    let mut v = names.to_vec();
    v.sort_by(|a, b| coll_cmp(b, a, how));
    v
}

fn is_desc(seq: &[Vec<u8>], how: Coll) -> bool {
    seq.windows(2).all(|w| coll_cmp(&w[0], &w[1], how) != std::cmp::Ordering::Less)
}

/// The names in a program's output, read leniently (see the module header).
fn out_names(output: &[u8]) -> Vec<Vec<u8>> {
    let mut body = output.strip_suffix(b"\n").unwrap_or(output);
    body = body.strip_suffix(b".").unwrap_or(body);
    if body.is_empty() {
        return Vec::new();
    }
    body.split(|&b| b == b',' || b == b'\n')
        .map(|t| t.trim_ascii().to_vec())
        .collect()
}

/// How many times `x` is in `v`.
fn count(v: &[Vec<u8>], x: &[u8]) -> usize {
    v.iter().filter(|y| y.as_slice() == x).count()
}

/// The words `shell01_rdwssap` prints for `output`, run with lines
/// `first`..`last`, against the passwd file `data`. `pick` is the one order
/// asked for, or None for either.
fn rdwssap_judge(
    data: &[u8],
    output: &[u8],
    first: usize,
    last: usize,
    pick: Option<Coll>,
) -> Vec<&'static str> {
    let lines = pw_lines(data);
    let comment_names: Vec<Vec<u8>> = lines
        .iter()
        .filter(|l| is_comment(l))
        .map(|l| backwards(login(l)))
        .collect();
    let logins: Vec<Vec<u8>> = lines
        .iter()
        .filter(|l| !is_comment(l))
        .map(|l| backwards(login(l)))
        .collect();
    let kept = kept_names(data);
    let got = out_names(output);
    let mut words = Vec::new();

    if got.iter().any(|t| comment_names.contains(t) && !logins.contains(t)) {
        words.push("comments");
    }
    if got.iter().any(|t| !comment_names.contains(t) && !logins.contains(t)) {
        words.push("reversed");
    }
    // Every name that is a login must be one the steps keep, as often as they
    // keep it; over a range that covers the whole list, every kept name too.
    let from_logins: Vec<Vec<u8>> = got.iter().filter(|t| logins.contains(t)).cloned().collect();
    let mut wrong = from_logins.iter().any(|t| count(&from_logins, t) > count(&kept, t));
    if first == 1 && last >= kept.len() {
        wrong = wrong || kept.iter().any(|k| count(&from_logins, k) < count(&kept, k));
    }
    if wrong {
        words.push("lines");
    }

    let by_locale = is_desc(&got, Coll::Locale);
    let by_bytes = is_desc(&got, Coll::C);
    let follows = match pick {
        Some(how) => {
            if !is_desc(&got, how) {
                words.push("order");
            }
            how
        }
        None => {
            if !by_locale && !by_bytes {
                words.push("order");
            }
            if by_bytes && !by_locale {
                words.push("c-order");
                Coll::C
            } else {
                Coll::Locale
            }
        }
    };
    let list = sorted_desc(&kept, follows);
    let from = (first - 1).min(list.len());
    let to = last.min(list.len()).max(from);
    if got.as_slice() != &list[from..to] {
        words.push("window");
    }
    words
}

/// The passwd file `--passwd` names, /etc/passwd by default.
fn read_passwd(path: &str) -> Vec<u8> {
    match std::fs::read(path) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("oracle shell01_rdwssap: cannot read {}: {}", path, e);
            exit(2);
        }
    }
}

fn line_number(s: &str) -> usize {
    match s.parse::<usize>() {
        Ok(n) if n >= 1 && s.bytes().all(|b| b.is_ascii_digit()) => n,
        _ => {
            eprintln!("oracle shell01_rdwssap: {:?} is not a line number (from 1)", s);
            exit(2);
        }
    }
}

/// The steps `data`, as ex07's fixture, does not show (`shell01_rdwssap
/// shows`, in the module header): the words for each, in a fixed order.
fn fixture_misses(data: &[u8]) -> Vec<&'static str> {
    let lines = pw_lines(data);
    let first_login = lines.iter().position(|l| !is_comment(l));
    let mut out = Vec::new();
    if !matches!(first_login, Some(f) if lines[..f].iter().any(|l| is_comment(l))) {
        out.push("comment-first");
    }
    // From the first login on, the two orders of the subject's first two
    // steps -- comments removed, then every other line; or every other line,
    // then comments removed -- keep different lines only where comments
    // between two logins shift which line is the second, the fourth, ...: an
    // even run of them shifts nothing, and one after the last login keeps
    // nothing more.
    let later = match first_login {
        Some(f) => {
            let from: Vec<&[u8]> = lines[f..].to_vec();
            let steps: Vec<&[u8]> = from
                .iter()
                .copied()
                .filter(|l| !is_comment(l))
                .enumerate()
                .filter(|(i, _)| i % 2 == 1)
                .map(|(_, l)| l)
                .collect();
            let swapped: Vec<&[u8]> = from
                .iter()
                .copied()
                .enumerate()
                .filter(|(i, _)| i % 2 == 1)
                .map(|(_, l)| l)
                .filter(|l| !is_comment(l))
                .collect();
            steps != swapped
        }
        None => false,
    };
    if !later {
        out.push("comment-later");
    }
    let kept = kept_names(data);
    if kept.len() < 15 {
        out.push("window");
    }
    if sorted_desc(&kept, Coll::C) == sorted_desc(&kept, Coll::Locale) {
        out.push("orders");
    }
    out
}

/// `oracle shell01_rdwssap ...` (see the module header), `args` after the name.
pub fn rdwssap_cmd(args: &[String]) -> ! {
    use_env_locale();
    let mut rest: Vec<&str> = Vec::new();
    let mut passwd = "/etc/passwd".to_string();
    let mut pick = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--passwd" if i + 1 < args.len() => {
                passwd = args[i + 1].clone();
                i += 2;
            }
            "--order" if i + 1 < args.len() => {
                pick = match args[i + 1].as_str() {
                    "locale" => Some(Coll::Locale),
                    "c" => Some(Coll::C),
                    o => {
                        eprintln!("oracle shell01_rdwssap: --order is locale or c, not {:?}", o);
                        exit(2);
                    }
                };
                i += 2;
            }
            a => {
                rest.push(a);
                i += 1;
            }
        }
    }
    let data = read_passwd(&passwd);
    match rest.as_slice() {
        ["orders"] => {
            let kept = kept_names(&data);
            exit(if sorted_desc(&kept, Coll::C) != sorted_desc(&kept, Coll::Locale) { 0 } else { 1 });
        }
        ["reaches", n] => exit(if kept_names(&data).len() >= line_number(n) { 0 } else { 1 }),
        ["shows"] => {
            let missing = fixture_misses(&data);
            if missing.is_empty() {
                exit(0);
            }
            println!("{}", missing.join(" "));
            exit(1);
        }
        [first, last] => {
            let words = rdwssap_judge(&data, &read_stdin(), line_number(first), line_number(last), pick);
            println!("{}", words.join(" "));
            exit(0);
        }
        _ => {
            eprintln!("usage: oracle shell01_rdwssap <first> <last> [--order locale|c] [--passwd FILE]");
            eprintln!("       oracle shell01_rdwssap orders|reaches <n>|shows [--passwd FILE]");
            exit(2);
        }
    }
}

// ----------------------------------------------------------------- chelou

/// FT_NBR1's base, FT_NBR2's and the sum's, each digit's value its position.
const CHELOU_IN1: &[u8] = b"'\\\"?!";
const CHELOU_IN2: &[u8] = b"mrdoc";
const CHELOU_OUT: &[u8] = b"gtaio luSnemf";

/// `digits` read in `alphabet`'s base, as the sum's base digits, least
/// significant first ([] for zero). None if it is empty or holds a byte the
/// alphabet does not.
fn chelou_value(digits: &[u8], alphabet: &[u8]) -> Option<Vec<u32>> {
    if digits.is_empty() {
        return None;
    }
    let (from, to) = (alphabet.len() as u32, CHELOU_OUT.len() as u32);
    let mut acc: Vec<u32> = Vec::new();
    for &c in digits {
        let mut carry = alphabet.iter().position(|&a| a == c)? as u32;
        for d in acc.iter_mut() {
            let v = *d * from + carry;
            *d = v % to;
            carry = v / to;
        }
        while carry > 0 {
            acc.push(carry % to);
            carry /= to;
        }
    }
    Some(acc)
}

/// a + b, both least significant first, in the sum's base.
fn chelou_add(a: &[u32], b: &[u32]) -> Vec<u32> {
    let to = CHELOU_OUT.len() as u32;
    let mut out = Vec::new();
    let mut carry = 0;
    for i in 0..a.len().max(b.len()) {
        let v = a.get(i).copied().unwrap_or(0) + b.get(i).copied().unwrap_or(0) + carry;
        out.push(v % to);
        carry = v / to;
    }
    if carry > 0 {
        out.push(carry);
    }
    out
}

/// The line the program prints for `n1` and `n2`, without its newline.
fn chelou(n1: &[u8], n2: &[u8]) -> Option<Vec<u8>> {
    let sum = chelou_add(&chelou_value(n1, CHELOU_IN1)?, &chelou_value(n2, CHELOU_IN2)?);
    let mut out: Vec<u8> = sum.iter().rev().skip_while(|&&d| d == 0).map(|&d| CHELOU_OUT[d as usize]).collect();
    if out.is_empty() {
        out.push(CHELOU_OUT[0]);
    }
    Some(out)
}

/// `oracle shell01_chelou`
pub fn chelou_cmd() -> ! {
    let var = |k: &str| std::env::var_os(k).map(|v| v.as_bytes().to_vec()).unwrap_or_default();
    match chelou(&var("FT_NBR1"), &var("FT_NBR2")) {
        Some(mut line) => {
            line.push(b'\n');
            let mut so = std::io::stdout();
            if so.write_all(&line).and_then(|_| so.flush()).is_err() {
                exit(2);
            }
            exit(0);
        }
        None => {
            eprintln!("oracle shell01_chelou: FT_NBR1 or FT_NBR2 is not a number in its base");
            exit(1);
        }
    }
}

/// A number of `len` digits in `alphabet`, its first digit not the zero one.
fn chelou_number(rng: &mut Rng, alphabet: &[u8], len: usize) -> Vec<u8> {
    let mut v = vec![alphabet[1 + rng.below(alphabet.len() - 1)]];
    for _ in 1..len {
        v.push(alphabet[rng.below(alphabet.len())]);
    }
    v
}

/// A number of `len` digits, most of them `digit`, with `digit` at least twice
/// in a row, and its first digit not the zero one.
fn chelou_run_of(rng: &mut Rng, digit: u8, len: usize) -> Vec<u8> {
    let mut v = chelou_number(rng, CHELOU_IN1, len);
    for (i, d) in v.iter_mut().enumerate().skip(1) {
        if i <= 3 || rng.below(3) > 0 {
            *d = digit;
        }
    }
    v
}

/// The pairs `shell01_chelou cases <seed>` prints.
fn chelou_cases(seed: u64) -> Vec<(&'static str, Vec<u8>, Vec<u8>)> {
    let mut rng = Rng::new(seed ^ 0x5e11_0108);
    let r = &mut rng;
    let mut v: Vec<(&'static str, Vec<u8>, Vec<u8>)> = Vec::new();
    let n2 = chelou_number(r, CHELOU_IN2, 7);
    v.push(("zero as FT_NBR1", b"'".to_vec(), n2));
    let n1 = chelou_number(r, CHELOU_IN1, 7);
    v.push(("zero as FT_NBR2", n1, b"m".to_vec()));
    v.push(("a zero sum", b"'".to_vec(), b"m".to_vec()));
    for (label, digit) in [
        ("single quotes in FT_NBR1", b'\''),
        ("backslashes side by side in FT_NBR1", b'\\'),
        ("double quotes in FT_NBR1", b'"'),
        ("question marks in FT_NBR1", b'?'),
        ("exclamation marks in FT_NBR1", b'!'),
    ] {
        let n1 = chelou_run_of(r, digit, 9);
        let n2 = chelou_number(r, CHELOU_IN2, 9);
        v.push((label, n1, n2));
    }
    let mut n1 = chelou_number(r, CHELOU_IN1, 6);
    n1.push(b'\\');
    let n2 = chelou_number(r, CHELOU_IN2, 6);
    v.push(("a backslash as FT_NBR1's last digit", n1, n2));
    let n2 = chelou_number(r, CHELOU_IN2, 5);
    v.push(("a lone '?' as FT_NBR1", b"?".to_vec(), n2));
    let n1 = chelou_number(r, CHELOU_IN1, 170);
    let n2 = chelou_number(r, CHELOU_IN2, 170);
    v.push(("a sum more than 70 digits long", n1, n2));
    let n1 = chelou_number(r, CHELOU_IN1, 2);
    let n2 = chelou_number(r, CHELOU_IN2, 60);
    v.push(("operands of very different lengths", n1, n2));
    v
}

/// `oracle shell01_chelou cases <seed>`
pub fn chelou_cases_cmd(seed: &str) -> ! {
    let seed: u64 = match seed.parse() {
        Ok(s) => s,
        Err(_) => {
            eprintln!("oracle shell01_chelou cases: the seed is a number");
            exit(2);
        }
    };
    let mut out = Vec::new();
    for (label, n1, n2) in chelou_cases(seed) {
        out.extend_from_slice(label.as_bytes());
        out.push(b'\t');
        out.extend_from_slice(&n1);
        out.push(b'\t');
        out.extend_from_slice(&n2);
        out.push(b'\n');
    }
    let mut so = std::io::stdout();
    if so.write_all(&out).and_then(|_| so.flush()).is_err() {
        exit(2);
    }
    exit(0);
}

// ------------------------------------------------------------- self-check

/// Self-check: root exists on every Linux box this runs on, and its primary
/// group is gid 0, whose name is root. A reference that cannot say that much is
/// broken, and would otherwise surface as a CORRECT print_groups.sh going red.
/// Then hwaddr, rdwssap and chelou, against hand-worked tables and properties.
pub fn check() -> usize {
    let mut fails = check_hwaddr() + check_rdwssap() + check_chelou();
    match groups_of("root") {
        Some(names) if names.first().map(String::as_str) == Some("root") => {}
        other => {
            eprintln!("shell01 groups_of(root): expected root first, got {:?}", other);
            fails += 1;
        }
    }
    if groups_of("no-such-user-42-oracle").is_some() {
        eprintln!("shell01 groups_of(unknown user): expected None");
        fails += 1;
    }
    if !all_logins().iter().any(|n| n == "root") {
        eprintln!("shell01 all_logins: root is not among them");
        fails += 1;
    }
    fails
}

fn check_hwaddr() -> usize {
    let mut fails = 0;
    let parse: &[(&[u8], Option<[u8; 6]>)] = &[
        (b"00:1a:2b:3c:4d:5e", Some([0x00, 0x1a, 0x2b, 0x3c, 0x4d, 0x5e])),
        (b"AA:bb:CC:dd:EE:ff", Some([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])),
        (b"00-1a-2b-3c-4d-5e", None),
        (b"00:1a:2b:3c:4d", None),
        (b"00:1a:2b:3c:4d:5e:6f", None),
        (b"00:1a:2b:3c:4d:5e ", None),
        (b" 00:1a:2b:3c:4d:5e", None),
        (b"0:1a:2b:3c:4d:5e0", None),
        (b"00:1g:2b:3c:4d:5e", None),
        (b"ether 00:1a:2b:3c", None),
        (b"", None),
    ];
    for (i, (s, want)) in parse.iter().enumerate() {
        if parse_mac(s) != *want {
            eprintln!("CHECK FAIL shell01 parse_mac case {}", i);
            fails += 1;
        }
    }
    // Verdicts against a made-up machine, so the table does not depend on the
    // box it runs on. `lo` is what --loopback adds.
    let host = [[0x02, 0, 0, 0, 0, 0x01], [0x02, 0, 0, 0, 0, 0x02]];
    let lo = [[0u8; 6]];
    let verdicts: &[(&[u8], bool, i32, usize)] = &[
        (b"02:00:00:00:00:01\n", false, 0, 0),
        (b"02:00:00:00:00:01\n02:00:00:00:00:02\n", false, 0, 0),
        (b"02:00:00:00:00:02", false, 0, 0),
        (b"02:00:00:00:00:01\n02:00:00:00:00:03\n", false, 3, 2),
        (b"02:00:00:00:00:01\n\n", false, 1, 2),
        (b"\n", false, 1, 1),
        (b"", false, 1, 1),
        (b"02:00:00:00:00:01 \n", false, 1, 1),
        (b"inet 127.0.0.1\n", false, 1, 1),
        (b"02:00:00:00:00:01\n00:00:00:00:00:00\n", false, 3, 2),
        (b"02:00:00:00:00:01\n00:00:00:00:00:00\n", true, 0, 0),
        (b"00:00:00:00:00:00\n02:00:00:00:00:02\n", true, 0, 0),
        (b"ff:ff:ff:ff:ff:ff\n", true, 3, 1),
        // The loopback's line alone: this machine's under --loopback, and
        // no hardware interface's. It would pass on every Linux machine, so
        // it is refused as 5; without --loopback it is not this machine's.
        (b"00:00:00:00:00:00\n", true, 5, 0),
        (b"00:00:00:00:00:00\n00:00:00:00:00:00\n", true, 5, 0),
        (b"00:00:00:00:00:00\n", false, 3, 1),
        // A line that is no one's still says 3 before the missing hardware
        // address says 5.
        (b"00:00:00:00:00:00\nff:ff:ff:ff:ff:ff\n", true, 3, 2),
    ];
    for (i, (input, with_lo, rc, line)) in verdicts.iter().enumerate() {
        let also: &[[u8; 6]] = if *with_lo { &lo } else { &[] };
        if hwaddr_verdict(input, &host, also) != (*rc, *line) {
            eprintln!("CHECK FAIL shell01 hwaddr verdict case {}", i);
            fails += 1;
        }
    }
    if hwaddr_verdict(b"02:00:00:00:00:01\n", &[], &lo) != (4, 0) {
        eprintln!("CHECK FAIL shell01 hwaddr: no hardware address must read as 4");
        fails += 1;
    }
    // This machine: whatever it publishes, no hardware address may be
    // all-zero, and each must be accepted when it is fed back as a line.
    let (mine, _) = host_addrs();
    for m in &mine {
        let line = format!(
            "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}\n",
            m[0], m[1], m[2], m[3], m[4], m[5]
        );
        if *m == [0u8; 6] || hwaddr_verdict(line.as_bytes(), &mine, &[]) != (0, 0) {
            eprintln!("CHECK FAIL shell01 hwaddr: this machine's own address is refused");
            fails += 1;
        }
    }
    fails
}

/// A made-up passwd: two comment lines at the top and one in the middle, so
/// the steps' order shows (a comment removed after the every-other-line step
/// shifts which lines are kept).
const PW_FIXTURE: &[u8] = b"# made up\n\
# for the oracle\n\
aa:x:1:1::/:/bin/sh\n\
bc:x:2:2::/:/bin/sh\n\
cd:x:3:3::/:/bin/sh\n\
# middle\n\
de:x:4:4::/:/bin/sh\n\
ef:x:5:5::/:/bin/sh\n\
fg:x:6:6::/:/bin/sh\n\
gh\n";

fn names(v: &[&str]) -> Vec<Vec<u8>> {
    v.iter().map(|s| s.as_bytes().to_vec()).collect()
}

fn joined(v: &[&str]) -> Vec<u8> {
    let mut s = v.join(", ").into_bytes();
    s.push(b'.');
    s
}

fn check_rdwssap() -> usize {
    // The tables below are worked in bytes: the C locale, whatever the
    // environment says, until the part that is about the locale.
    // SAFETY: a valid NUL-terminated string.
    unsafe {
        setlocale(LC_COLLATE, b"C\0".as_ptr() as *const c_char);
    }
    let mut fails = 0;
    let mut fail = |what: &str| {
        eprintln!("CHECK FAIL shell01 rdwssap: {}", what);
        fails += 1;
    };
    // By hand: the logins without comments are aa bc cd de ef fg gh; the
    // second, fourth and sixth are bc de fg; backwards cb ed gf.
    if kept_names(PW_FIXTURE) != names(&["cb", "ed", "gf"]) {
        fail("kept_names on the fixture");
    }
    // What a fixture shows (`shows`), here in bytes, where no order of the
    // locale's can differ: PW_FIXTURE has a comment first and one between
    // logins, and three names, short of the window.
    if fixture_misses(PW_FIXTURE) != vec!["window", "orders"] {
        fail("fixture_misses on the hand table");
    }
    if fixture_misses(b"aa:x\nbb:x\n# late\n") != vec!["comment-first", "comment-later", "window", "orders"]
        || fixture_misses(b"# top\naa:x\n# mid\nbb:x\n") != vec!["window", "orders"]
    {
        fail("fixture_misses: a comment after the last login is no comment between two");
    }
    // Two comments side by side between logins shift no line's place: the
    // steps keep the same lines in either order, so the fixture does not show
    // that comments go first.
    if fixture_misses(b"# top\naa:x\n# a\n# b\nbb:x\ncc:x\n") != vec!["comment-later", "window", "orders"]
        || fixture_misses(b"# top\naa:x\n# a\n# b\n# c\nbb:x\ncc:x\n") != vec!["window", "orders"]
    {
        fail("fixture_misses: comment-later asks whether the comments shift which lines are kept");
    }
    if backwards("é:ab".as_bytes()) != "ba:é".as_bytes() || backwards(b"\xffab") != b"ba\xff" {
        fail("backwards reads UTF-8 by character, anything else by byte");
    }
    if out_names(b"a, b.\n") != names(&["a", "b"])
        || out_names(b"a,b") != names(&["a", "b"])
        || out_names(b"a\nb\n") != names(&["a", "b"])
        || !out_names(b"").is_empty()
        || !out_names(b".").is_empty()
    {
        fail("out_names reads a list leniently");
    }
    let judge = |out: &[u8], f: usize, l: usize, pick: Option<Coll>| rdwssap_judge(PW_FIXTURE, out, f, l, pick);
    let none: Vec<&str> = Vec::new();
    // The whole list, right: gf ed cb (letters, so both orders agree).
    let table: &[(&[&str], usize, usize, &[&str])] = &[
        (&["gf", "ed", "cb"], 1, 999, &[]),
        (&["gf", "ed", "cb"], 1, 3, &[]),
        (&["ed", "cb"], 2, 3, &[]),
        (&["ed"], 2, 2, &[]),
        // an unreversed login
        (&["gf", "de", "cb"], 1, 999, &["reversed", "lines", "window"]),
        // the odd lines kept instead: aa cd ef gh -> aa dc fe hg
        (&["hg", "fe", "dc", "aa"], 1, 999, &["lines", "window"]),
        // ascending
        (&["cb", "ed", "gf"], 1, 999, &["order", "window"]),
        // comments never removed: lines 2, 4, 6, 8 and 10 of the file are
        // "# for the oracle", bc, "# middle", ef and gh
        (
            &["hg", "fe", "elddim #", "elcaro eht rof #", "cb"],
            1,
            999,
            &["comments", "lines", "window"],
        ),
        // the same lines, the comments removed only after them: bc, ef, gh
        (&["hg", "fe", "cb"], 1, 999, &["lines", "window"]),
        // a name missing from the whole list
        (&["gf", "cb"], 1, 999, &["lines", "window"]),
        // the window of the other bounds
        (&["gf", "ed"], 2, 3, &["window"]),
        // nothing printed for a range that holds names
        (&[], 1, 2, &["window"]),
    ];
    for (i, (out, f, l, want)) in table.iter().enumerate() {
        let got = judge(&joined(out), *f, *l, None);
        if got.as_slice() != *want {
            eprintln!("CHECK FAIL shell01 rdwssap table case {}: got {:?}, want {:?}", i, got, want);
            fails += 1;
        }
    }
    let mut fail = |what: &str| {
        eprintln!("CHECK FAIL shell01 rdwssap: {}", what);
        fails += 1;
    };
    if judge(b"gf, ed, cb.\n", 1, 999, None) != none {
        fail("a final newline is the check's to judge, not the names'");
    }
    if judge(b".", 4, 5, None) != none {
        fail("an empty window past the end of the list is that window");
    }
    // Where the two orders differ. By bytes '_' (0x5f) sorts before 'a'
    // (0x61); the locale's collation, whatever it is here, may or may not.
    let pw = b"x0:x\nab:x\nx1:x\nb_a:x\nx2:x\nba:x\n";
    let kept = kept_names(pw);
    if kept != names(&["ba", "a_b", "ab"]) {
        fail("kept_names on the order fixture");
    }
    if sorted_desc(&kept, Coll::Locale) != sorted_desc(&kept, Coll::C)
        || sorted_desc(&kept, Coll::C) != names(&["ba", "ab", "a_b"])
    {
        fail("in the C locale, the locale's order is bytes");
    }
    if rdwssap_judge(pw, &joined(&["ba", "ab", "a_b"]), 1, 9, None) != none
        || rdwssap_judge(pw, &joined(&["ba", "ab", "a_b"]), 1, 9, Some(Coll::Locale)) != none
    {
        fail("byte order is the locale's where the locale is C");
    }
    use_env_locale();
    for how in [Coll::C, Coll::Locale] {
        let s = sorted_desc(&kept, how);
        let mut a = s.clone();
        let mut b = kept.clone();
        a.sort();
        b.sort();
        if !is_desc(&s, how) || a != b {
            fail("sorted_desc is a permutation in reverse order");
        }
        if rdwssap_judge(pw, &joined_bytes(&s), 1, 9, Some(how)).contains(&"order") {
            fail("a list in the order asked for is not out of order");
        }
    }
    let loc = sorted_desc(&kept, Coll::Locale);
    let byte = sorted_desc(&kept, Coll::C);
    let words = rdwssap_judge(pw, &joined_bytes(&byte), 1, 9, None);
    if loc != byte {
        if words != ["c-order"] {
            fail("a list in byte order only is c-order, and nothing else");
        }
        if rdwssap_judge(pw, &joined_bytes(&byte), 1, 9, Some(Coll::Locale)) != ["order", "window"] {
            fail("byte order, where the locale's was asked for, is out of order");
        }
    } else if words != none {
        fail("where the two orders agree, byte order is the locale's");
    }
    fails
}

fn joined_bytes(v: &[Vec<u8>]) -> Vec<u8> {
    let mut s = v.join(&b", "[..]);
    s.push(b'.');
    s
}

fn check_chelou() -> usize {
    let mut fails = 0;
    // By hand: ' is 0 and ! is 4 in the first base, m is 0 and c is 4 in the
    // second, and the sum's digits are g t a i o ' ' l u S n e m f, 0 to 12.
    let table: &[(&[u8], &[u8], Option<&[u8]>)] = &[
        (b"'", b"m", Some(b"g")),
        (b"!", b"c", Some(b"S")),
        (b"\\'", b"r", Some(b"l")),
        (b"!!", b"cc", Some(b"in")),
        (b"\\", b"m", Some(b"t")),
        (b"'", b"cc", Some(b"tm")),
        (b"", b"m", None),
        (b"'", b"", None),
        (b"a", b"m", None),
        (b"'", b"'", None),
    ];
    for (i, (a, b, want)) in table.iter().enumerate() {
        if chelou(a, b).as_deref() != *want {
            eprintln!("CHECK FAIL shell01 chelou table case {}", i);
            fails += 1;
        }
    }
    // Against u128 arithmetic, for operands small enough to fit.
    let mut rng = Rng::new(0x5e11_0108);
    for case in 0..20000 {
        let (l1, l2) = (1 + rng.below(25), 1 + rng.below(25));
        let n1 = chelou_number(&mut rng, CHELOU_IN1, l1);
        let n2 = chelou_number(&mut rng, CHELOU_IN2, l2);
        let val = |s: &[u8], a: &[u8]| {
            s.iter().fold(0u128, |acc, c| acc * a.len() as u128 + a.iter().position(|x| x == c).unwrap() as u128)
        };
        let mut n = val(&n1, CHELOU_IN1) + val(&n2, CHELOU_IN2);
        let mut want = Vec::new();
        loop {
            want.push(CHELOU_OUT[(n % 13) as usize]);
            n /= 13;
            if n == 0 {
                break;
            }
        }
        want.reverse();
        if chelou(&n1, &n2) != Some(want) {
            eprintln!("CHECK FAIL shell01 chelou sweep case {}", case);
            fails += 1;
        }
    }
    // The cases: every operand a number, none padded with a zero digit, and
    // the classes the check names each there.
    let cases = chelou_cases(42);
    for (label, n1, n2) in &cases {
        let padded = |s: &[u8], zero: u8| s.len() > 1 && s[0] == zero;
        if chelou(n1, n2).is_none() || padded(n1, b'\'') || padded(n2, b'm') {
            eprintln!("CHECK FAIL shell01 chelou cases: {:?} is not two plain numbers", label);
            fails += 1;
        }
    }
    let has = |pred: &dyn Fn(&[u8], &[u8]) -> bool| cases.iter().any(|(_, a, b)| pred(a, b));
    let checks: &[(&str, bool)] = &[
        ("zero as FT_NBR1", has(&|a, _| a == b"'")),
        ("zero as FT_NBR2", has(&|_, b| b == b"m")),
        ("a zero sum", cases.iter().any(|(_, a, b)| chelou(a, b).as_deref() == Some(&b"g"[..]))),
        ("two backslashes side by side", has(&|a, _| a.windows(2).any(|w| w == b"\\\\"))),
        ("a final backslash", has(&|a, _| a.last() == Some(&b'\\'))),
        ("a lone ?", has(&|a, _| a == b"?")),
        ("a sum over 70 digits", cases.iter().any(|(_, a, b)| chelou(a, b).map_or(0, |s| s.len()) > 70)),
    ];
    for (what, ok) in checks {
        if !ok {
            eprintln!("CHECK FAIL shell01 chelou cases: none has {}", what);
            fails += 1;
        }
    }
    for d in CHELOU_IN1 {
        if !cases.iter().any(|(_, a, _)| a.windows(2).any(|w| w[0] == *d && w[1] == *d)) {
            eprintln!("CHECK FAIL shell01 chelou cases: no run of the digit {:?}", *d as char);
            fails += 1;
        }
    }
    if chelou_cases(42) != chelou_cases(42) {
        eprintln!("CHECK FAIL shell01 chelou cases: not reproducible from the seed");
        fails += 1;
    }
    fails
}
