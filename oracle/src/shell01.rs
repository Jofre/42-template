//! Shell 01 references that a shell check cannot construct by itself.
//!
//! ex01 prints the groups of the user named in $FT_USER. Its expected value
//! lives in the machine's user database -- /etc/group on a laptop, LDAP on a 42
//! campus box -- so no fixture can fix it in advance, and the check used to
//! compute it with the very pipeline the exercise asks for, which put the
//! answer in a file the template ships. This is the reference instead, in
//! Rust, as AGENTS.md §2 describes the oracle: readable, not pasteable into a
//! shell script.
//!
//! It asks glibc through the same NSS calls `id` makes (getpwnam, getgrouplist,
//! getgrgid), so it agrees with the machine on whatever backend the machine
//! uses, and it reproduces coreutils' order: the user's primary group first,
//! then the rest in the order getgrouplist returns them, the primary skipped.
//! A group with no name is printed as its number, as `id` does.
//!
//! Usage:  oracle shell01_groups <user>   -- prints g1,g2,... (no newline);
//!                                           exit 1, printing nothing, if the
//!                                           user does not exist.
//!
//! Two more references live here, each for the same reason:
//!
//! ex07 keeps "only the logins between FT_LINE1 and FT_LINE2 (inclusive)".
//! Its check compares the student's program against ITSELF -- a narrow window
//! must be exactly that slice of the program's own full list -- and taking that
//! slice in shell is the exercise's own step. `line_range` takes it instead.
//!
//!   oracle shell01_line_range <first> <last>   < text
//!       copies lines first..last (numbered from 1, both included) of stdin to
//!       stdout, each with the terminator it had; nothing if first > last.
//!       Exit 2, printing nothing, if either bound is not a number >= 1.
//!
//! ex04 prints this machine's MAC addresses. Its check used to validate the
//! output with a text pattern, and that pattern is a piece of a common answer.
//! `hwaddr` asks the kernel instead: the addresses of this machine's network
//! interfaces, as Linux publishes them under /sys/class/net/<if>/address,
//! loopback and all-zero ones left out.
//!
//!   oracle shell01_hwaddr   < lines
//!       exit 0  every line of stdin is a MAC address (six two-digit hex
//!               numbers joined by ':', either case) AND one of this machine's;
//!       exit 1  some line is not a MAC address at all (an empty input, or a
//!               blank line, counts as one);
//!       exit 3  every line is a MAC address, but some are not this machine's;
//!       exit 4  every line is a MAC address, and this machine publishes no
//!               hardware address to compare them with.
//!       Nothing is printed on stdout; stderr names a LINE NUMBER, never an
//!       address.

use crate::common::Rng;
use std::ffi::{CStr, CString};
use std::io::{Read, Write};
use std::os::raw::{c_char, c_int};
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
    fn getgrgid(gid: Gid) -> *mut Group;
    fn getgrouplist(user: *const c_char, group: Gid, groups: *mut Gid, ngroups: *mut c_int)
        -> c_int;
}

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

// ------------------------------------------------------------- line_range

/// Lines `first..=last` of `input` (numbered from 1), each with the terminator
/// it had in `input`. A last line with no newline after it stays that way.
fn line_range(input: &[u8], first: usize, last: usize) -> Vec<u8> {
    let mut out = Vec::new();
    let mut n = 1usize;
    let mut start = 0usize;
    while start < input.len() && n <= last {
        let end = match input[start..].iter().position(|&b| b == b'\n') {
            Some(p) => start + p + 1,
            None => input.len(),
        };
        if n >= first {
            out.extend_from_slice(&input[start..end]);
        }
        start = end;
        n += 1;
    }
    out
}

fn read_stdin() -> Vec<u8> {
    let mut data = Vec::new();
    if std::io::stdin().read_to_end(&mut data).is_err() {
        eprintln!("oracle: cannot read stdin");
        exit(2);
    }
    data
}

/// `oracle shell01_line_range <first> <last>`
pub fn line_range_cmd(first: &str, last: &str) -> ! {
    let bound = |s: &str| match s.parse::<usize>() {
        Ok(n) if n >= 1 && s.bytes().all(|b| b.is_ascii_digit()) => n,
        _ => {
            eprintln!("oracle shell01_line_range: bounds are line numbers, from 1");
            exit(2);
        }
    };
    let (first, last) = (bound(first), bound(last));
    let out = line_range(&read_stdin(), first, last);
    let mut so = std::io::stdout();
    if so.write_all(&out).and_then(|_| so.flush()).is_err() {
        exit(2);
    }
    exit(0);
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

/// The hardware addresses of this machine's network interfaces, as the kernel
/// publishes them: one per interface under /sys/class/net, with loopback and
/// all-zero addresses left out, and so are the ones that are not six bytes
/// long (tunnels publish four- or sixteen-byte ones). Empty where the
/// directory does not exist or nothing in it qualifies.
fn host_hwaddrs() -> Vec<[u8; 6]> {
    let mut out = Vec::new();
    let dir = match std::fs::read_dir("/sys/class/net") {
        Ok(d) => d,
        Err(_) => return out,
    };
    for entry in dir.flatten() {
        let p = entry.path();
        let ty = std::fs::read(p.join("type")).unwrap_or_default();
        if ty.trim_ascii() == LOOPBACK_TYPE {
            continue;
        }
        let addr = match std::fs::read(p.join("address")) {
            Ok(a) => a,
            Err(_) => continue,
        };
        if let Some(mac) = parse_mac(addr.trim_ascii()) {
            if mac != [0u8; 6] && !out.contains(&mac) {
                out.push(mac);
            }
        }
    }
    out
}

/// The verdict `shell01_hwaddr` exits with (see the module header), and the
/// number of the line that decided it (0 when no single line did).
fn hwaddr_verdict(input: &[u8], host: &[[u8; 6]]) -> (i32, usize) {
    let body = input.strip_suffix(b"\n").unwrap_or(input);
    let mut macs = Vec::new();
    for (i, l) in body.split(|&b| b == b'\n').enumerate() {
        match parse_mac(l) {
            Some(m) => macs.push(m),
            None => return (1, i + 1),
        }
    }
    if host.is_empty() {
        return (4, 0);
    }
    for (i, m) in macs.iter().enumerate() {
        if !host.contains(m) {
            return (3, i + 1);
        }
    }
    (0, 0)
}

/// `oracle shell01_hwaddr`
pub fn hwaddr_cmd() -> ! {
    let (rc, line) = hwaddr_verdict(&read_stdin(), &host_hwaddrs());
    match rc {
        1 => eprintln!("oracle shell01_hwaddr: line {} is not a MAC address", line),
        3 => eprintln!(
            "oracle shell01_hwaddr: line {} is a MAC address, but not one of this machine's",
            line
        ),
        4 => eprintln!("oracle shell01_hwaddr: this machine publishes no hardware address to compare with"),
        _ => {}
    }
    exit(rc);
}

// ------------------------------------------------------------- self-check

/// Self-check: root exists on every Linux box this runs on, and its primary
/// group is gid 0, whose name is root. A reference that cannot say that much is
/// broken, and would otherwise surface as a CORRECT print_groups.sh going red.
/// Then line_range and hwaddr, against hand-worked tables and properties.
pub fn check() -> usize {
    let mut fails = check_line_range() + check_hwaddr();
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
    fails
}

fn check_line_range() -> usize {
    let mut fails = 0;
    let table: &[(&[u8], usize, usize, &[u8])] = &[
        (b"a\nb\nc\nd\n", 2, 3, b"b\nc\n"),
        (b"a\nb\nc\nd\n", 1, 1, b"a\n"),
        (b"a\nb\nc\nd\n", 3, 9, b"c\nd\n"),
        (b"a\nb\nc\nd\n", 5, 6, b""),
        (b"a\nb\nc\nd\n", 3, 2, b""),
        (b"a\nb", 2, 2, b"b"),
        (b"a\n\nc\n", 2, 2, b"\n"),
        (b"", 1, 5, b""),
    ];
    for (i, (input, f, l, want)) in table.iter().enumerate() {
        if line_range(input, *f, *l).as_slice() != *want {
            eprintln!("CHECK FAIL shell01 line_range table case {}", i);
            fails += 1;
        }
    }
    // Properties over random inputs: the three windows before, inside and
    // after [first, last], put back together, ARE the input; and the window
    // holds exactly as many lines as an inclusive range says it should.
    let mut rng = Rng::new(0x5e11_0107);
    for case in 0..20000 {
        let n = rng.below(12);
        let mut input = Vec::new();
        for _ in 0..n {
            for _ in 0..rng.below(4) {
                input.push(b"ab ,."[rng.below(5)]);
            }
            input.push(b'\n');
        }
        if rng.below(4) == 0 {
            // an unterminated last line
            input.push(b'z');
        }
        let lines = n + usize::from(input.last().map_or(false, |&b| b != b'\n'));
        let first = 1 + rng.below(14);
        let last = first + rng.below(14);
        let before = line_range(&input, 1, first - 1);
        let inside = line_range(&input, first, last);
        let after = line_range(&input, last + 1, usize::MAX);
        let whole = [before.as_slice(), inside.as_slice(), after.as_slice()].concat();
        let want = if first > lines { 0 } else { last.min(lines) - first + 1 };
        let got = inside.iter().filter(|&&b| b == b'\n').count()
            + usize::from(inside.last().map_or(false, |&b| b != b'\n'));
        if whole != input || got != want {
            eprintln!(
                "CHECK FAIL shell01 line_range sweep case {}: first={} last={} lines={} got={} want={}",
                case, first, last, lines, got, want
            );
            fails += 1;
        }
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
    // box it runs on.
    let host = [[0x02, 0, 0, 0, 0, 0x01], [0x02, 0, 0, 0, 0, 0x02]];
    let verdicts: &[(&[u8], i32, usize)] = &[
        (b"02:00:00:00:00:01\n", 0, 0),
        (b"02:00:00:00:00:01\n02:00:00:00:00:02\n", 0, 0),
        (b"02:00:00:00:00:02", 0, 0),
        (b"02:00:00:00:00:01\n02:00:00:00:00:03\n", 3, 2),
        (b"02:00:00:00:00:01\n\n", 1, 2),
        (b"\n", 1, 1),
        (b"", 1, 1),
        (b"02:00:00:00:00:01 \n", 1, 1),
        (b"inet 127.0.0.1\n", 1, 1),
    ];
    for (i, (input, rc, line)) in verdicts.iter().enumerate() {
        if hwaddr_verdict(input, &host) != (*rc, *line) {
            eprintln!("CHECK FAIL shell01 hwaddr verdict case {}", i);
            fails += 1;
        }
    }
    if hwaddr_verdict(b"02:00:00:00:00:01\n", &[]) != (4, 0) {
        eprintln!("CHECK FAIL shell01 hwaddr: no host address must read as 4");
        fails += 1;
    }
    // This machine: whatever it publishes, none of it may be all-zero, and
    // each address must be accepted when it is fed back as a line.
    let mine = host_hwaddrs();
    for m in &mine {
        let line = format!(
            "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}\n",
            m[0], m[1], m[2], m[3], m[4], m[5]
        );
        if *m == [0u8; 6] || hwaddr_verdict(line.as_bytes(), &mine) != (0, 0) {
            eprintln!("CHECK FAIL shell01 hwaddr: this machine's own address is refused");
            fails += 1;
        }
    }
    fails
}
